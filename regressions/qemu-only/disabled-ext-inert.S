# QEMU_CPU: max
# Feature: extensions the CHERI policy refuses are really off, not just
# hidden from the ISA string.
#
# The gate's policy stage only checks that QEMU starts or refuses to start
# with an extension. "-cpu max" enables everything and the policy then turns
# the unsafe extensions off; if the turning-off missed a decoder flag or a
# CSR mask, guest code could still use an extension that bypasses
# capability checks (vector loads with raw addresses, pointer masking
# rewriting addresses after the bounds check, ...). Here every refused
# extension must be inert: its instructions are illegal and its CSR bits
# read 0.
#  1: vector: vsetvli is illegal;           2: vector CSR vl is illegal;
#  3: mstatus.VS stays 0;                   4: hypervisor: hlv.d is illegal;
#  5: hypervisor CSR hstatus is illegal;    6: misa has neither V nor H;
#  7: pointer masking: menvcfg.PMM and mseccfg.PMM stay 0;
#  8: Smrnmi: mnret and the mnscratch CSR are illegal;
#  9: Zicfilp/Zicfiss: menvcfg.LPE and menvcfg.SSE stay 0.
#include "cheri-v9.h"
    .option arch, +v, +h
    test_start

#define CAUSE_ILLEGAL 2
#define CSR_MNSCRATCH 0x740
#define MNRET .word 0x70200073

    la t0, expected_trap
    csrw mtvec, t0
    cspecialr x20, x1

    /* Expect insn to be an illegal instruction (check n). */
    .macro illegal n, insn:vararg
    check \n
    trap_expect CAUSE_ILLEGAL, -1, 4f
    \insn
    fail \n
4:
    .endm
    /* Expect bits mask of csr to read 0 after trying to set them. */
    .macro stays_zero n, csr, mask
    check \n
    li t3, \mask
    csrs \csr, t3
    csrr t4, \csr
    and t4, t4, t3
    expect t4, 0, \n
    .endm

    illegal 1, vsetvli t0, a0, e8, m1, ta, ma
    illegal 2, csrr a0, vl
    stays_zero 3, mstatus, (3 << 9)                 /* mstatus.VS */
    illegal 4, hlv.d a0, (a1)
    illegal 5, csrr a0, hstatus

    check 6
    csrr t3, misa
    li t4, (1 << ('V' - 'A')) | (1 << ('H' - 'A'))
    and t3, t3, t4
    expect t3, 0, 6

    stays_zero 7, menvcfg, (3 << 32)                /* menvcfg.PMM */
    stays_zero 7, 0x747, (3 << 32)                  /* mseccfg.PMM */
    illegal 8, MNRET
    illegal 8, csrr a0, CSR_MNSCRATCH
    stays_zero 9, menvcfg, (1 << 2) | (1 << 3)      /* LPE, SSE */
    pass

    expected_trap_handler
