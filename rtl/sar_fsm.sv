// =============================================================================
// Module  : sar_fsm
// Project : 8-bit Split-CDAC SAR ADC — ECE5404, Virginia Tech
// Author  : Victor Velasquez Fonseca
// Date    : 2026
//
// Description:
//   Synthesizable Asynchronous SAR ADC Controller in SystemVerilog.
//   Implements a self-timed N-bit successive approximation algorithm.
//
//   Each bit decision is gated by comp_valid (comparator settled pulse),
//   which makes total conversion time = N × t_comp — independent of clk.
//   This is the defining property of an Asynchronous SAR (ASAR).
//
// Algorithm (Binary Search):
//   1. SAMPLE: S/H closes, CDAC bottom plates → VIN for one cycle
//   2. CONVERT B[N-1]: set MSB=1, wait comp_valid, keep/clear based on result
//   3. CONVERT B[N-2..0]: repeat for each bit MSB→LSB
//   4. DONE: assert eoc for one cycle, latch dout, restart
//
// Timing example (8-bit, 5 MHz master clock):
//   CLK period = 200 ns
//   SAMPLE     = 1 cycle  (100 ns at 10 MHz internal, or gated externally)
//   CONVERT    = 8 × t_comp  (self-timed, ~80 ns at 10 ns/bit)
//   EOC        = 1 cycle
//
// FSM State Diagram:
//   IDLE ──(start)──► SAMPLE ──► CONV ──(bit_ptr==0 & comp_valid)──► DONE
//    ▲                                                                   │
//    └───────────────────────────────────────────────────────────────────┘
//
// Parameters:
//   N  — ADC resolution in bits (default 8)
//
// Ports:
//   clk        — master clock
//   rst_n      — active-low synchronous reset
//   start      — pulse to initiate a new conversion
//   comp_valid — strobe: comparator result is settled and ready
//   comp_out   — comparator result: 1=VIN>VDAC (keep bit), 0=VIN<VDAC (clear)
//   sample     — high during sample phase → bootstrapped S/H control
//   bit_out    — current trial bits → CDAC bottom-plate mux sel inputs
//   dout       — final N-bit digital code (valid when eoc=1)
//   eoc        — end-of-conversion strobe (one cycle pulse)
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module sar_fsm #(
    parameter int unsigned N = 8
) (
    // Clock & Reset
    input  logic                    clk,
    input  logic                    rst_n,
    // Control
    input  logic                    start,
    // Comparator interface (self-timing)
    input  logic                    comp_valid,
    input  logic                    comp_out,
    // CDAC interface
    output logic                    sample,
    output logic [N-1:0]            bit_out,
    // Digital output
    output logic [N-1:0]            dout,
    output logic                    eoc
);

    // -------------------------------------------------------------------------
    // State Encoding
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        S_IDLE   = 2'b00,   // Idle — awaiting start pulse
        S_SAMPLE = 2'b01,   // Sampling VIN onto CDAC top-plate (1 cycle)
        S_CONV   = 2'b10,   // Successive approximation (N comp_valid pulses)
        S_DONE   = 2'b11    // Conversion complete — dout valid, eoc asserted
    } state_e;

    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    state_e                  state;
    logic [$clog2(N)-1:0]    bit_ptr;    // Bit pointer: N-1 (MSB) → 0 (LSB)
    logic [N-1:0]            sar_reg;    // SAR register (trial + result)

    // -------------------------------------------------------------------------
    // Sequential Logic — State register + SAR datapath
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            bit_ptr <= N[($clog2(N))-1:0] - 1;
            sar_reg <= '0;
            dout    <= '0;

        end else begin
            case (state)

                // ── IDLE ────────────────────────────────────────────────────
                S_IDLE: begin
                    if (start) begin
                        sar_reg <= '0;
                        bit_ptr <= N[($clog2(N))-1:0] - 1;
                        state   <= S_SAMPLE;
                    end
                end

                // ── SAMPLE ──────────────────────────────────────────────────
                // Assert sample for one clock cycle.
                // CDAC bottom plates connected to VIN via analog_mux_ideal.
                // On the next cycle, release sample and begin conversion.
                S_SAMPLE: begin
                    sar_reg          <= '0;
                    sar_reg[N-1]     <= 1'b1;       // Set MSB as first trial
                    bit_ptr          <= N[($clog2(N))-1:0] - 1;
                    state            <= S_CONV;
                end

                // ── CONVERT ─────────────────────────────────────────────────
                // Self-timed: advance only on comp_valid strobe.
                // comp_out=1 → VIN > VDAC → current bit was too small → keep 1
                // comp_out=0 → VIN < VDAC → current bit was too large → clear 0
                S_CONV: begin
                    if (comp_valid) begin
                        // Latch comparator decision for current bit
                        sar_reg[bit_ptr] <= comp_out;

                        if (bit_ptr == '0) begin
                            // Final bit decided → output result
                            dout  <= {sar_reg[N-1:1], comp_out};
                            state <= S_DONE;
                        end else begin
                            // Arm next trial bit, advance pointer toward LSB
                            sar_reg[bit_ptr - 1] <= 1'b1;
                            bit_ptr              <= bit_ptr - 1;
                        end
                    end
                end

                // ── DONE ────────────────────────────────────────────────────
                // Hold eoc for one cycle, then return to IDLE.
                // In continuous mode replace S_IDLE with S_SAMPLE below.
                S_DONE: begin
                    state <= S_IDLE;
                end

            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Output assignments
    // -------------------------------------------------------------------------
    assign sample  = (state == S_SAMPLE);
    assign bit_out = sar_reg;
    assign eoc     = (state == S_DONE);

endmodule : sar_fsm

`default_nettype wire
