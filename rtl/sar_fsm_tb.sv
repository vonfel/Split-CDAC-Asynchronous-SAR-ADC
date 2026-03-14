// =============================================================================
// Module  : sar_fsm_tb
// Project : 8-bit Split-CDAC SAR ADC — ECE5404, Virginia Tech
// Author  : Victor Velasquez Fonseca
//
// Description:
//   SystemVerilog testbench for sar_fsm.
//   Sweeps VIN from 0 → VREF in 256 steps, checks digital output matches
//   expected code, and reports INL/DNL.
//
// Run with: vcs -sverilog sar_fsm.sv sar_fsm_tb.sv -R
//       or: iverilog -g2012 sar_fsm.sv sar_fsm_tb.sv && ./a.out
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module sar_fsm_tb;

    // ── Parameters ─────────────────────────────────────────────────────────
    localparam int N      = 8;
    localparam int N_CODES = (1 << N);          // 256
    localparam real VREF  = 1.0;                // Reference voltage (V)
    localparam real VLSB  = VREF / N_CODES;     // 3.906 mV
    localparam real CLK_T = 10.0;               // 10 ns → 100 MHz (fast TB)
    localparam real T_COMP = 2.0;               // 2 ns comparator latency (sim)

    // ── DUT signals ────────────────────────────────────────────────────────
    logic                 clk;
    logic                 rst_n;
    logic                 start;
    logic                 comp_valid;
    logic                 comp_out;
    logic                 sample;
    logic [N-1:0]         bit_out;
    logic [N-1:0]         dout;
    logic                 eoc;

    // ── Analog model signals ────────────────────────────────────────────────
    real vin_held;      // Voltage held by ideal S/H
    real vdac;          // Ideal CDAC output voltage (behavioral)

    // ── INL/DNL tracking ───────────────────────────────────────────────────
    real vdac_code [0:N_CODES-1];   // VDAC at each output code
    real inl, dnl, max_inl, max_dnl;

    // ── DUT instantiation ──────────────────────────────────────────────────
    sar_fsm #(.N(N)) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .comp_valid (comp_valid),
        .comp_out   (comp_out),
        .sample     (sample),
        .bit_out    (bit_out),
        .dout       (dout),
        .eoc        (eoc)
    );

    // ── Clock generation ────────────────────────────────────────────────────
    initial clk = 0;
    always #(CLK_T/2) clk = ~clk;

    // ── Ideal behavioral CDAC model ─────────────────────────────────────────
    // Computes VDAC from bit_out using split-CDAC transfer function
    // V_out = (VREF/256) * (D_MSB*16 + D_LSB*(15/16))
    // where D_MSB = bit_out[7:4], D_LSB = bit_out[3:0]
    function automatic real cdac_voltage(input logic [N-1:0] bits);
        real d_msb, d_lsb, c_eq;
        d_msb = bits[7:4];
        d_lsb = bits[3:0];
        c_eq  = 15.0 / 16.0;   // Bridge cap series combination
        return (VREF / 256.0) * (d_msb * 16.0 + d_lsb * c_eq);
    endfunction

    // ── Ideal comparator ────────────────────────────────────────────────────
    // Fires T_COMP after bit_out changes
    always @(bit_out) begin
        #(T_COMP);
        vdac      = cdac_voltage(bit_out);
        comp_out  = (vin_held > vdac) ? 1'b1 : 1'b0;
        comp_valid = 1'b1;
        @(posedge clk);
        comp_valid = 1'b0;
    end

    // ── Main test sequence ──────────────────────────────────────────────────
    integer i;
    initial begin
        $display("=================================================");
        $display(" 8-bit Split-CDAC SAR ADC — Functional Sim");
        $display(" VREF=%.1fV  VLSB=%.4f mV  N=%0d bits", VREF, VLSB*1000, N);
        $display("=================================================");

        // Reset
        rst_n = 0; start = 0; comp_valid = 0; comp_out = 0;
        vin_held = 0.0; vdac = 0.0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Sweep VIN across full range
        for (i = 0; i < N_CODES; i++) begin
            vin_held = (i + 0.5) * VLSB;   // Mid-code input

            // Start conversion
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            // Wait for EOC
            @(posedge eoc);
            @(posedge clk);

            // Record VDAC at this code
            vdac_code[dout] = cdac_voltage(dout);

            $display("VIN=%6.4fV  code=%3d (0x%02h)  VDAC=%6.4fV",
                     vin_held, dout, dout, vdac_code[dout]);

            // Basic check: output code should equal input index
            if (dout !== i[N-1:0])
                $warning("  *** MISMATCH: expected %0d, got %0d ***", i, dout);
        end

        // ── Compute INL and DNL ───────────────────────────────────────────
        $display("\n── INL / DNL Analysis ──────────────────────────");
        max_inl = 0.0; max_dnl = 0.0;

        for (i = 1; i < N_CODES; i++) begin
            // DNL[i] = (V[i] - V[i-1])/VLSB - 1
            dnl = (vdac_code[i] - vdac_code[i-1]) / VLSB - 1.0;
            // INL[i] = (V[i] - V_ideal[i]) / VLSB
            inl = (vdac_code[i] - i * VLSB) / VLSB;

            if ($abs(dnl) > $abs(max_dnl)) max_dnl = dnl;
            if ($abs(inl) > $abs(max_inl)) max_inl = inl;
        end

        $display("Max |INL| = %6.4f LSB  (spec: ±5 LSB)", max_inl);
        $display("Max |DNL| = %6.4f LSB  (spec: ±5 LSB)", max_dnl);

        if ($abs(max_inl) <= 5.0 && $abs(max_dnl) <= 5.0)
            $display("✓ PASS — INL and DNL within spec");
        else
            $display("✗ FAIL — exceeds ±5 LSB spec");

        $display("=================================================\n");
        $finish;
    end

endmodule : sar_fsm_tb

`default_nettype wire
