# =============================================================================
# split_cdac_model.py
# Ideal Behavioral Model — 8-bit Split-CDAC SAR ADC
# ECE5404 Advanced Analog IC Design | Virginia Tech, Spring 2026
# Author: Victor Velasquez Fonseca
#
# Description:
#   Models the ideal charge-redistribution transfer function of a 4-4 split
#   capacitive DAC (CDAC). Computes INL and DNL using the endpoint method.
#   Uses an integer bridge capacitor (CB = 1 Cu, rounded from ideal 16/15 Cu),
#   which introduces a known −0.9375 LSB gain error and a single INL spike at
#   the MSB/LSB array boundary (code 15 → 16 transition).
#
# Architecture:
#   MSB array : CM3(8Cu) + CM2(4Cu) + CM1(2Cu) + CM0(1Cu dummy) = 16Cu
#   LSB array : CL3(8Cu) + CL2(4Cu) + CL1(2Cu) + CL0(1Cu)      = 15Cu
#   Bridge    : CB = 1Cu  (ideal = 16/15 Cu ≈ 1.0667Cu)
#   Total     : 31Cu across 9 physical MIM capacitors
#
# Results:
#   Max |INL| = 0.9375 LSB  ✓ PASS (spec: ±5 LSB)
#   Max |DNL| = 0.9375 LSB  ✓ PASS (spec: ±5 LSB)
#
# Usage:
#   pip install numpy matplotlib
#   python split_cdac_model.py
#   → generates split_cdac_results.png in the current directory
# =============================================================================

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec

# ── Design Parameters ─────────────────────────────────────────────────────────
N_BITS = 8       # Total ADC resolution (bits)
M_BITS = 4       # MSB sub-array bits
L_BITS = 4       # LSB sub-array bits
CU     = 1.0     # Unit capacitance (normalized)
VREF   = 1.0     # Reference voltage (V)

# ── Bridge Capacitor ──────────────────────────────────────────────────────────
# Ideal bridge value (makes LSB array contribute exactly 1 Cu at MSB node):
CB_ideal = (2**L_BITS / (2**L_BITS - 1)) * CU   # = 16/15 Cu ≈ 1.0667 Cu
# Integer approximation used in Cadence (SKY130 MIM cap only supports integer M):
CB = 1.0 * CU                                     # = 1 Cu

# LSB array total capacitance (no dummy; 8+4+2+1 = 15 Cu):
C_lsb_total = sum([2**(L_BITS-1-i) for i in range(L_BITS)]) * CU

# Equivalent capacitance of LSB array as seen from MSB summing node:
#   C_eq = CB || C_lsb = CB * C_lsb / (CB + C_lsb) = 15/16 Cu
C_eq = (CB * C_lsb_total) / (CB + C_lsb_total)

print("=" * 52)
print("  8-bit Split-CDAC Ideal Model  |  4-4 Split")
print("=" * 52)
print(f"  Ideal CB      : {CB_ideal:.4f} Cu  (16/15 Cu)")
print(f"  Integer CB    : {CB:.4f} Cu  (rounded, used in silicon)")
print(f"  C_LSB_total   : {C_lsb_total:.1f} Cu  (8+4+2+1, no dummy)")
print(f"  C_eq          : {C_eq:.4f} Cu  (target: 1.0000 Cu)")
print(f"  Error         : {1.0 - C_eq:.4f} Cu  (1/16 Cu shortfall)")
print()

# ── Transfer Function ─────────────────────────────────────────────────────────
def cdac_voltage(code):
    """Charge-redistribution output for a given N-bit digital code."""
    D_MSB = (code >> L_BITS) & ((1 << M_BITS) - 1)
    D_LSB =  code             & ((1 << L_BITS) - 1)
    # Standard split-CDAC formula (endpoint normalisation to 2^N):
    return (VREF / 2**N_BITS) * (D_MSB * 2**L_BITS + D_LSB * C_eq / CU)

codes    = np.arange(2**N_BITS)
V_actual = np.array([cdac_voltage(c) for c in codes])
LSB_size = VREF / 2**N_BITS            # ≈ 3.906 mV
V_ideal  = codes * LSB_size

# ── INL / DNL ─────────────────────────────────────────────────────────────────
INL = (V_actual - V_ideal) / LSB_size   # LSB units, endpoint method
DNL = np.diff(V_actual) / LSB_size - 1  # LSB units

inl_max = np.max(np.abs(INL))
dnl_max = np.max(np.abs(DNL))

print(f"  LSB size      : {LSB_size*1e3:.4f} mV")
print(f"  Max |INL|     : {inl_max:.4f} LSB  {'✓ PASS' if inl_max <= 5 else '✗ FAIL'}  (spec: ±5 LSB)")
print(f"  Max |DNL|     : {dnl_max:.4f} LSB  {'✓ PASS' if dnl_max <= 5 else '✗ FAIL'}  (spec: ±5 LSB)")
print(f"  Gain error    : {(V_actual[255] - VREF*(255/256))/LSB_size:.4f} LSB")
print(f"  INL worst at  : code {np.argmax(np.abs(INL))}  (MSB/LSB boundary)")
print(f"  DNL worst at  : code {np.argmax(np.abs(DNL))+1}  (array transition)")
print(f"  Max output    : {V_actual[255]*1e3:.4f} mV  (ideal: {VREF*1e3*255/256:.4f} mV)")
print()

# ── Plot ──────────────────────────────────────────────────────────────────────
V_error_mV = (V_actual - V_ideal) * 1e3
spec_mV    =  5 * LSB_size * 1e3        # ±5 LSB in mV

fig = plt.figure(figsize=(16, 13))
fig.patch.set_facecolor('#1a1a1a')
fig.suptitle(
    'Ideal 8-bit Split-CDAC  |  4-4 Split, CB = 1 Cu, No LSB Dummy\n'
    'ECE5404 Project 2  —  Victor Velasquez Fonseca  |  Virginia Tech',
    fontsize=13, fontweight='bold', color='white', y=0.98
)
gs = gridspec.GridSpec(2, 2, figure=fig, hspace=0.42, wspace=0.32)

def style_ax(ax, title, xlabel, ylabel):
    ax.set_facecolor('#111111')
    ax.set_title(title, fontsize=11, color='white', pad=8)
    ax.set_xlabel(xlabel, fontsize=10, color='#aaaaaa')
    ax.set_ylabel(ylabel, fontsize=10, color='#aaaaaa')
    ax.tick_params(colors='#aaaaaa')
    ax.grid(True, alpha=0.2, color='#444444')
    ax.spines[:].set_color('#333333')

# Panel 1: Transfer function
ax1 = fig.add_subplot(gs[0, 0])
ax1.plot(codes, V_actual*1e3, color='#4fc3f7', lw=1.8, label='CDAC Actual Output', zorder=3)
ax1.scatter(codes[::6], V_ideal[::6]*1e3,
            color='gold', s=18, alpha=0.85, zorder=4, label='Ideal Ramp (every 6th code)')
style_ax(ax1, 'Split-CDAC Transfer Function', 'Digital Code (0–255)', 'Output Voltage (mV)')
ax1.set_xlim([0, 255])
ax1.legend(fontsize=8, facecolor='#222222', labelcolor='white', framealpha=0.8)

# Panel 2: Voltage error
ax2 = fig.add_subplot(gs[0, 1])
ax2.plot(codes, V_error_mV, color='#ff9800', lw=1.2, label='Voltage Error')
ax2.axhline(y= spec_mV, color='#ef5350', lw=1.5, linestyle='--',
            label=f'±5 LSB = ±{spec_mV:.2f} mV')
ax2.axhline(y=-spec_mV, color='#ef5350', lw=1.5, linestyle='--')
ax2.axhline(y=0, color='#555555', lw=0.8)
ax2.fill_between(codes, V_error_mV, 0, where=(V_error_mV < 0),
                 color='#ff9800', alpha=0.15)
style_ax(ax2, f'Voltage Error  [peak = {np.min(V_error_mV):.3f} mV]',
         'Digital Code (0–255)', 'Error (mV)')
ax2.set_xlim([0, 255])
ax2.legend(fontsize=8, facecolor='#222222', labelcolor='white', framealpha=0.8)

# Panel 3: INL
ax3 = fig.add_subplot(gs[1, 0])
ax3.plot(codes, INL, color='#66bb6a', lw=1.2, label='INL')
ax3.axhline(y= 5, color='#ef5350', lw=1.5, linestyle='--', label='±5 LSB Spec')
ax3.axhline(y=-5, color='#ef5350', lw=1.5, linestyle='--')
ax3.axhline(y= 0, color='#555555', lw=0.8)
ax3.fill_between(codes, INL, 0, where=(INL < 0), color='#66bb6a', alpha=0.15)
style_ax(ax3,
         f'Integral Nonlinearity  [Max = {inl_max:.4f} LSB]  ✓ PASS',
         'Digital Code', 'INL (LSB)')
ax3.set_xlim([0, 255]); ax3.set_ylim([-2, 2])
ax3.legend(fontsize=8, facecolor='#222222', labelcolor='white', framealpha=0.8)

# Panel 4: DNL
ax4 = fig.add_subplot(gs[1, 1])
ax4.plot(codes[1:], DNL, color='#ce93d8', lw=1.2, label='DNL')
ax4.axhline(y= 5, color='#ef5350', lw=1.5, linestyle='--', label='±5 LSB Spec')
ax4.axhline(y=-5, color='#ef5350', lw=1.5, linestyle='--')
ax4.axhline(y= 0, color='#555555', lw=0.8)
ax4.fill_between(codes[1:], DNL, 0, where=(DNL > 0), color='#ce93d8', alpha=0.15)
style_ax(ax4,
         f'Differential Nonlinearity  [Max = {dnl_max:.4f} LSB]  ✓ PASS',
         'Digital Code', 'DNL (LSB)')
ax4.set_xlim([0, 255]); ax4.set_ylim([-2, 2])
ax4.legend(fontsize=8, facecolor='#222222', labelcolor='white', framealpha=0.8)

plt.savefig('split_cdac_results.png', dpi=150, bbox_inches='tight',
            facecolor=fig.get_facecolor())
plt.show()
print("Plot saved: split_cdac_results.png")
