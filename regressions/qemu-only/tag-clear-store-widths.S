# QEMU_CPU: rv64
# Feature: tag clearing by ordinary (non-capability) stores, for every store
# width and position.
#
# Memory holds one tag per aligned 16-byte capability slot. Writing any byte
# of a slot with an ordinary store must clear that slot's tag (the bytes are
# no longer a capability), and must not touch any other slot's tag. QEMU
# implements this in the store paths of each instruction kind (integer, FP,
# compressed) and splits misaligned accesses, so each one is checked here.
#
# Two capabilities are stored before every check: A in slot buf + 0..15 and
# B in slot buf + 16..31. Then one store is done and both tags are checked.
#  1-5:  sb/sh/sw/sd at different offsets inside A clear only A;
#  6-7:  FP stores (fsw, fsd) clear only A;
#  8-9:  compressed stores (c.sw, c.sd) clear only A;
#  10:   a store into B clears only B (slots are independent);
#  11-12: misaligned sw (bytes 14..17) and sd (12..19) cross from A into B
#        and must clear both;
#  13:   a load from A clears nothing;
#  14:   a store just before A (buf - 1) clears neither.
#include "cheri-v9.h"
    test_start

    la t0, expected_trap
    csrw mtvec, t0
    li t0, 1 << 13                      /* mstatus.FS = Initial */
    csrs mstatus, t0
    cspecialr x20, x1                   /* c20 = DDC, tagged */
    la s0, buf                          /* s0 = x8, usable by c.sw/c.sd */
    addi s1, s0, 16
    li a1, 0x5a                         /* a1 = x11 */
    fmv.d.x fa0, a1

    /* Store A and B, run insn, then expect A's and B's tags to be ta, tb. */
    .macro store_case n, ta, tb, insn:vararg
    check \n
    sc_ddc x20, s0
    sc_ddc x20, s1
    \insn
    lc_ddc x3, s0
    cgettag a4, x3
    expect a4, \ta, \n
    lc_ddc x3, s1
    cgettag a4, x3
    expect a4, \tb, \n
    .endm

    store_case 1, 0, 1, sb a1, 0(s0)
    store_case 2, 0, 1, sb a1, 15(s0)
    store_case 3, 0, 1, sh a1, 6(s0)
    store_case 4, 0, 1, sw a1, 12(s0)
    store_case 5, 0, 1, sd a1, 8(s0)
    store_case 6, 0, 1, fsw fa0, 4(s0)
    store_case 7, 0, 1, fsd fa0, 0(s0)
    store_case 8, 0, 1, c.sw a1, 4(s0)
    store_case 9, 0, 1, c.sd a1, 8(s0)
    store_case 10, 1, 0, sb a1, 16(s0)
    store_case 11, 0, 0, sw a1, 14(s0)
    store_case 12, 0, 0, sd a1, 12(s0)
    store_case 13, 1, 1, ld a2, 0(s0)
    store_case 14, 1, 1, sb a1, -1(s0)
    pass

    expected_trap_handler

    .data
    .align 4
    .zero 16                            /* room for check 14 */
buf: .zero 32
