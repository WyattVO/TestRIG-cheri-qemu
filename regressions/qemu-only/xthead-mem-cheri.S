# QEMU_CPU: rv64,xtheadmemidx=true,xtheadmempair=true
# The T-Head vendor extensions XTheadMemIdx (indexed and post/pre-increment
# loads/stores) and XTheadMemPair (two-register loads/stores) are accepted
# on CHERI CPUs and go through gen_ddc_interposed_{ld,st}. They must obey
# DDC like ordinary accesses:
#  1:   th.sdd over a stored capability clears its tag;
#  2-4: th.ldd, th.lrd and th.sdia outside DDC raise a CHERI length fault;
#  5:   th.sdd through a DDC without Store permission raises PermitStore.
# Sail has neither extension. QEMU 11 adds the thead-c908 CPU model
# (2044a97253) and more vendor load/store extensions (Xmipslsp); each needs
# the same CHERI treatment or the policy has to refuse it.
#include "cheri-v9.h"
    .option arch, +xtheadmemidx, +xtheadmempair
    test_start

    la t0, expected_trap
    csrw mtvec, t0
    cspecialr x20, x1
    la s0, buf

    check 1
    sc_ddc x20, s0
    li a0, 1
    li a1, 2
    th.sdd a0, a1, (s0), 0, 4
    lc_ddc x3, s0
    cgettag a4, x3
    expect a4, 0, 1

    /* DDC = [buf, buf + 32) */
    csetaddr x21, x20, s0
    li t0, 32
    csetbounds x21, x21, t0
    cspecialw x1, x21
    addi s1, s0, 32                     /* just past DDC */

    check 2
    trap_expect CAUSE_CHERI, TVAL_DDC_LENGTH, 4f
    th.ldd a0, a1, (s1), 0, 4
    fail 2
4:  csetaddr x21, x20, s0               /* (the handler restored DDC) */
    li t0, 32
    csetbounds x21, x21, t0
    cspecialw x1, x21
    check 3
    li a2, 32
    trap_expect CAUSE_CHERI, TVAL_DDC_LENGTH, 5f
    th.lrd a0, s0, a2, 0
    fail 3
5:  cspecialw x1, x21
    check 4
    mv a2, s1
    trap_expect CAUSE_CHERI, TVAL_DDC_LENGTH, 6f
    th.sdia a0, (a2), 8, 0
    fail 4
6:  check 5
    li t0, PERMS_NO_STORE
    candperm x21, x20, t0
    cspecialw x1, x21
    trap_expect CAUSE_CHERI, TVAL_DDC_STORE, 7f
    th.sdd a0, a1, (s0), 0, 4
    fail 5
7:  pass

    expected_trap_handler

    .data
    .align 4
buf: .zero 64
