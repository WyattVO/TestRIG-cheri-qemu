# QEMU_CPU: rv64
# A capability load/store is a 16-byte access: PMP must check all of it.
# Here PMP entry 0 denies S-mode any access to the 8 bytes at buf + 8, so a
# capability store to buf, which covers them, must raise a store access
# fault without writing anything (no partial write, no tag), and a
# capability load must raise a load access fault. An 8-byte access to buf
# and capability accesses to buf + 16 are allowed.
# Sail v9 is not compared on PMP by any template. QEMU 11 reworks PMP
# address and size handling (9afee2bde0 "Align pmp size to pmp-granularity",
# 612f22c19d "Fix integer overflow in TOR and NA4 address computation").
#include "cheri-v9.h"
    test_start

    la t0, trap
    csrw mtvec, t0
    cspecialr x20, x1
    la s0, buf
    li t0, 0x1111
    sd t0, 0(s0)
    li t0, 0x2222
    sd t0, 8(s0)

    /* pmp0: NAPOT 8 bytes at buf + 8, no access; pmp1: everything. */
    addi t0, s0, 8
    srli t0, t0, 2
    csrw pmpaddr0, t0
    li t0, -1
    csrw pmpaddr1, t0
    li t0, (0x1f << 8) | 0x18
    csrw pmpcfg0, t0

    li t0, 1 << 11                      /* MPP = S, satp = 0 (Bare) */
    csrw mstatus, t0
    la t0, smode
    csrw mepc, t0
    li s8, 99
    li s10, -1
    mret

smode:
    check 1
    trap_expect 7, -1, 4f               /* store access fault */
    sc_ddc x20, s0
    fail 1
4:  check 2
    trap_expect 5, -1, 5f               /* load access fault */
    lc_ddc x3, s0
    fail 2
5:  check 3
    ld t0, 0(s0)
    expect t0, 0x1111, 3
    check 4
    addi s1, s0, 16
    sc_ddc x20, s1
    lc_ddc x3, s1
    cgettag a4, x3
    expect a4, 1, 4
    ecall                               /* back to M-mode: mcheck */

mcheck:
    /*
     * A PMP entry that matches only part of an access fails it even in
     * M-mode, so turn PMP off before looking at buf.
     */
    csrw pmpcfg0, zero
    ld t0, 0(s0)
    expect t0, 0x1111, 5                /* no partial write */
    ld t0, 8(s0)
    expect t0, 0x2222, 5
    lc_ddc x3, s0
    cgettag a4, x3
    expect a4, 0, 6                     /* no tag */
    pass

    .align 2
trap:
    csrr t0, mcause
    li t1, 9                            /* ecall from S */
    beq t0, t1, mcheck
    bne t0, s10, 3f
    li s10, -1
    csrw mepc, s11
    mret
3:  fail_reg s8

    .data
    .align 4
buf: .zero 32
