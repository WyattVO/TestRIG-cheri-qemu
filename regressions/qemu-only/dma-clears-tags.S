# QEMU_CPU: rv64,zbb=true
# Feature: CHERI tags vs. device (DMA) writes.
#
# Tags may only be set by capability stores from the CPU. Any other write
# into memory, including a device writing by DMA, must clear the tag of
# every capability it overwrites; otherwise a device (or a guest driving
# one) could leave a tag on bytes it chose, i.e. forge a capability. QEMU
# clears tags in physmem.c (invalidate_and_set_dirty) for all non-CPU writes.
#
# The virt machine's fw_cfg device has a DMA interface; reading the 4-byte
# fw_cfg signature ("QEMU") by DMA writes into guest RAM like any device.
# fw_cfg registers (big-endian): selector at base + 8, DMA address at
# base + 16. A DMA descriptor is { be32 control, be32 length, be64 address };
# control = selector << 16 | SELECT (0x08) | READ (0x02), and the device
# clears it (keeping only ERROR, 0x01) when done.
#
# Two capabilities are stored, A at buf and B at buf + 16. The DMA writes the
# 4 bytes buf + 4 .. buf + 7, i.e. into the middle of A only.
#  1: the DMA finishes without the ERROR bit;
#  2: the bytes arrived ("QEMU" at buf + 4);
#  3: A's tag is cleared (a partial overwrite still clears the whole tag);
#  4: B's tag is kept (a device write clears only the capabilities it
#     touches).
#include "cheri-v9.h"
    .option arch, +zbb
    test_start

#define FW_CFG_DMA   0x10100010
#define FW_CFG_SIG   0x0000          /* fw_cfg key of the signature */
#define DMA_CONTROL  ((FW_CFG_SIG << 16) | 0x08 | 0x02)
#define DMA_LENGTH   4
#define QEMU_LE      0x554d4551      /* "QEMU" read as a little-endian word */

    cspecialr x20, x1                   /* c20 = DDC, a tagged capability */
    la s0, buf
    sc_ddc x20, s0                      /* A at buf */
    addi s1, s0, 16
    sc_ddc x20, s1                      /* B at buf + 16 */

    /* Build the descriptor in big-endian byte order. */
    la s2, desc
    li t0, (DMA_CONTROL << 32) | DMA_LENGTH
    rev8 t0, t0                         /* control and length, BE */
    sd t0, 0(s2)
    addi t0, s0, 4                      /* DMA target: buf + 4 */
    rev8 t0, t0
    sd t0, 8(s2)
    fence

    /* Start the DMA: write the descriptor's address (BE) to the device. */
    li t1, FW_CFG_DMA
    rev8 t0, s2
    sd t0, 0(t1)
    fence

    /* 1: wait until the device clears control; it must not set ERROR. */
    li t2, 1000000
1:  lwu t0, 0(s2)
    rev8 t0, t0
    srli t0, t0, 32                     /* control, CPU byte order */
    andi t3, t0, ~1
    beqz t3, 2f                         /* done */
    addi t2, t2, -1
    bnez t2, 1b
    fail 1                              /* never finished */
2:  andi t0, t0, 1
    expect t0, 0, 1

    /* 2: the device wrote the signature. */
    lwu t0, 4(s0)
    expect t0, QEMU_LE, 2

    /* 3: the capability the device wrote into lost its tag. */
    lc_ddc x3, s0
    cgettag a4, x3
    expect a4, 0, 3

    /* 4: the neighbouring capability was not touched and keeps its tag. */
    lc_ddc x3, s1
    cgettag a4, x3
    expect a4, 1, 4
    pass

    .data
    .align 4
buf:  .zero 32
desc: .zero 16
