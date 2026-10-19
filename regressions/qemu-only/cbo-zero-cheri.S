# QEMU_CPU: rv64,zicboz=true
# cbo.zero (Zicboz) writes a whole cache block (64 bytes) with its own helper
# (helper_cbo_zero_cap), not the normal store path, so the CHERI rules are
# checked separately:
#  1-2: it clears memory and the tags of every capability in the block;
#  3:   its authority (DDC here) needs Store permission (CHERI PermitStore);
#  4-5: the whole block must be inside DDC's bounds (CHERI length violation).
# Sail v9 has no Zicboz, so TestRIG cannot check this. QEMU 11 changes the
# Zicbo translation (d6c5855c76 saves the opcode before the helpers); the
# rebase must keep the _cap helpers.
#include "cheri-v9.h"
    .option arch, +zicboz
    test_start

    la t0, expected_trap
    csrw mtvec, t0
    cspecialr x20, x1                   /* c20 = full DDC */
    la s0, blk

    check 1
    sc_ddc x20, s0                      /* capabilities at both ends */
    addi s1, s0, 48
    sc_ddc x20, s1
    cbo.zero (s0)
    lc_ddc x3, s0
    cgettag a4, x3
    expect a4, 0, 1
    lc_ddc x3, s1
    cgettag a4, x3
    expect a4, 0, 1
    check 2
    ld a5, 0(s0)
    expect a5, 0, 2
    ld a5, 56(s0)
    expect a5, 0, 2

    check 3                             /* DDC without Store permission */
    li t0, PERMS_NO_STORE
    candperm x21, x20, t0
    cspecialw x1, x21
    trap_expect CAUSE_CHERI, TVAL_DDC_STORE, 4f
    cbo.zero (s0)
    fail 3
4:
    check 4                             /* DDC = [blk, blk + 64) */
    csetaddr x21, x20, s0
    li t0, 64
    csetbounds x21, x21, t0
    cspecialw x1, x21
    cbo.zero (s0)                       /* inside: allowed */
    check 5
    addi t1, s0, 64
    trap_expect CAUSE_CHERI, TVAL_DDC_LENGTH, 5f
    cbo.zero (t1)                       /* next block: outside DDC */
    fail 5
5:
    pass

    expected_trap_handler

    .data
    .align 6
blk: .zero 128
