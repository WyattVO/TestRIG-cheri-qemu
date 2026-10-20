# QEMU_CPU: rv64,zicbom=true
# Feature: the Access System Registers (ASR) permission of PCC.
#
# On CHERI, privilege level alone does not grant access to system state: the
# running code's PCC must also have ASR. Compartmentalised kernel code runs
# without it. Without ASR in PCC, these must raise a CHERI exception (cause
# 28) whose mtval names PCC (0x20) and the ASR violation (0x18), i.e. 0x418:
#  1: reading a privileged CSR (mscratch);
#  2: writing a privileged CSR (mtvec);
#  3: reading a privileged special capability register (MTCC, SCR 28);
#  4: mret;
#  5: cbo.inval (it can destroy other software's data);
# while these need no ASR and must work:
#  6: user CSRs (fcsr), and reading DDC;
#  7: ordinary loads and stores.
# Checks 1-5 also make sure the operation did not happen (mscratch and
# mtvec keep their values; mret does not return).
#include "cheri-v9.h"
    .option arch, +zicbom
    test_start

#define TVAL_PCC_ASR ((0x20 << 5) | 0x18)
#define PERM_ASR (1 << 10)

    la t0, expected_trap
    csrw mtvec, t0
    li t0, 1 << 13                      /* mstatus.FS = Initial (for fcsr) */
    csrs mstatus, t0
    li t0, 0x1234
    csrw mscratch, t0
    cspecialr x20, x1                   /* c20 = DDC (handler restores it) */
    la s0, buf

    /* Continue in integer mode with a PCC that lacks ASR. */
    cspecialr x22, x0
    li t0, ~PERM_ASR
    candperm x22, x22, t0
    lla t0, noasr
    csetaddr x22, x22, t0
    cjalr x0, x22

noasr:
    check 1
    li a0, 0
    trap_expect CAUSE_CHERI, TVAL_PCC_ASR, 4f
    csrr a0, mscratch
    fail 1
4:  expect a0, 0, 1                     /* nothing was read */

    check 2
    trap_expect CAUSE_CHERI, TVAL_PCC_ASR, 4f
    csrw mtvec, zero
    fail 2
4:
    check 3
    trap_expect CAUSE_CHERI, TVAL_PCC_ASR, 4f
    cspecialr x5, x28                   /* MTCC */
    fail 3
4:
    check 4
    trap_expect CAUSE_CHERI, TVAL_PCC_ASR, 4f
    mret
    fail 4
4:
    check 5
    trap_expect CAUSE_CHERI, TVAL_PCC_ASR, 4f
    cbo.inval (s0)
    fail 5
4:
    check 6
    csrr a0, fcsr                       /* user CSR: allowed */
    cspecialr x6, x1                    /* DDC: allowed */
    cgettag a4, x6
    expect a4, 1, 6

    check 7
    li t0, 0x77
    sd t0, 0(s0)
    ld t1, 0(s0)
    expect t1, 0x77, 7
    pass

    expected_trap_handler

    .data
    .align 6
buf: .zero 64
