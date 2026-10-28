# QEMU_CPU: rv64,zicboz=true,zacas=true
# QEMU_SMP: 1,maxcpus=4
# QEMU_THREADS: single multi
# With MTTCG and more than one possible hart, QEMU keeps each capability's
# tag in a lock byte (lock_tag: tag in bit 0, lock state above) instead of a
# bitmap, and generated code takes that lock around every store that may
# meet a capability. One hart (maxcpus=4 only switches the mode on) runs every
# kind of write through it, so a broken path fails here deterministically
# instead of only in a race. The same checks run under round-robin TCG
# (thread=single), where the bitmap is used. Four capability slots in one
# 64-byte block, tagged by sc_ddc; after each step CLoadTags must give
# exactly the slots still tagged (CHERI v9 CLoadTags: bit n = nth capability):
#  1: slots 0 and 2 -> 0b0101, and lc of slot 0 is tagged (QEMU's lock_tag
#     series read the lock bytes in host big-endian order, giving 0b1010,
#     which broke CheriBSD's revoker);
#  2: slots 1 and 3 -> 0b1010;
#  3: all four -> 0b1111;
#  4: sd over slot 1 -> 0b1101;
#  5: amoswap.d over slot 0 -> 0b1100;
#  6: lr.d/sc.d over slot 2 -> 0b1000 (sc.d succeeded);
#  7: amocas.d over slot 3 -> 0b0000;
#  8: amoadd.w (a 32-bit AMO) over slot 0 -> 0b0000 again after retagging 0;
#  9: cbo.zero of the block (all four tagged) -> 0b0000 and the data zero;
# 10: the lock state never leaks: after all that, a capability stored and
#     loaded back is tagged and has its address.
#include "cheri-v9.h"
    .option arch, +zicboz, +zacas
    test_start

    cspecialr x20, x1                   /* c20 = full DDC */
    la s0, blk
    csetaddr x21, x20, s0               /* c21 -> blk, for cloadtags */

    .macro expect_tags v, n
    cloadtags a0, x21
    expect a0, \v, \n
    .endm
    /* store DDC (tagged) into slot i of blk */
    .macro tag_slot i
    addi s1, s0, 16 * \i
    sc_ddc x20, s1
    .endm
    .macro clear_all
    .irp i, 0, 1, 2, 3
    sd zero, 16 * \i(s0)
    .endr
    .endm

    tag_slot 0
    tag_slot 2
    expect_tags 0b0101, 1
    lc_ddc x3, s0
    cgettag a4, x3
    expect a4, 1, 1

    clear_all
    tag_slot 1
    tag_slot 3
    expect_tags 0b1010, 2

    tag_slot 0
    tag_slot 2
    expect_tags 0b1111, 3

    li a1, 0x1234
    sd a1, 16(s0)
    expect_tags 0b1101, 4

    amoswap.d a2, a1, (s0)
    expect_tags 0b1100, 5

    addi s1, s0, 32
1:  lr.d a2, (s1)
    sc.d a3, a1, (s1)
    bnez a3, 1b
    expect_tags 0b1000, 6

    addi s1, s0, 48
    ld a2, 0(s1)                        /* expected old value: the address */
    amocas.d a2, a1, (s1)
    expect_tags 0b0000, 7

    tag_slot 0
    amoadd.w a2, a1, (s0)
    expect_tags 0b0000, 8

    tag_slot 0
    tag_slot 1
    tag_slot 2
    tag_slot 3
    expect_tags 0b1111, 9
    cbo.zero (s0)
    expect_tags 0b0000, 9
    ld a2, 0(s0)
    ld a3, 56(s0)
    or a2, a2, a3
    expect a2, 0, 9

    tag_slot 1
    addi s1, s0, 16
    lc_ddc x3, s1
    cgettag a4, x3
    expect a4, 1, 10
    .insn r 0x5b, 0, 0x7f, a5, x3, x15  /* cgetaddr a5, c3 */
    .insn r 0x5b, 0, 0x7f, a6, x20, x15 /* cgetaddr a6, c20 */
    sub a5, a5, a6
    expect a5, 0, 10
    expect_tags 0b0010, 10
    pass

    .data
    .align 6
blk: .zero 64
