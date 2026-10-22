# QEMU_CPU: rv64
# QEMU_ARGS: -global virtio-mmio.force-legacy=true -device virtio-rng-device
# Feature: virtio device writes clear CHERI tags.
#
# dma-clears-tags.S covers devices that write with address_space_write().
# Virtio devices instead map guest buffers (address_space_map()), write
# through the host pointer, and unmap them; tag clearing then happens in
# address_space_unmap(). This is the path CheriBSD's disks, network and RNG
# use, so it is checked on its own. virtio-rng is the simplest virtio device:
# the driver posts a writable buffer and the device fills it with random
# bytes.
#
# The test is a minimal virtio-mmio (legacy, version 1) driver: find the
# device among the virt machine's eight transports, set up queue 0 with one
# descriptor pointing at buf + 4 (8 bytes, inside capability A), notify the
# device and wait for it to return the buffer.
#  1: a virtio-rng device is present (magic "virt", version 1, device ID 4);
#  2: the device consumed and returned the buffer (used.idx = 1);
#  3: it reports writing all 8 bytes;
#  4: the tag of capability A, which the device wrote into, is cleared;
#  5: the tag of capability B at buf + 16, which it did not write, is kept.
#include "cheri-v9.h"
    test_start

#define VIRTIO_BASE   0x10001000
#define VIRTIO_STRIDE 0x1000
#define VIRTIO_MAGIC  0x74726976        /* "virt" */
#define R_MAGIC       0x000
#define R_VERSION     0x004
#define R_DEVICE_ID   0x008
#define R_GUEST_FEAT  0x020
#define R_PAGE_SIZE   0x028
#define R_QUEUE_SEL   0x030
#define R_QUEUE_MAX   0x034
#define R_QUEUE_NUM   0x038
#define R_QUEUE_ALIGN 0x03c
#define R_QUEUE_PFN   0x040
#define R_NOTIFY      0x050
#define R_STATUS      0x070
#define QSIZE         8
#define USED_OFF      4096              /* used ring: next QueueAlign boundary */

    la t0, expected_trap
    csrw mtvec, t0
    cspecialr x20, x1
    la s0, buf
    sc_ddc x20, s0                      /* A */
    addi s1, s0, 16
    sc_ddc x20, s1                      /* B */

    /* 1: find the device. */
    check 1
    li s2, VIRTIO_BASE
    li t3, 8
1:  lwu t0, R_MAGIC(s2)
    li t1, VIRTIO_MAGIC
    bne t0, t1, 2f
    lwu t0, R_DEVICE_ID(s2)
    li t1, 4
    beq t0, t1, 3f
2:  li t0, VIRTIO_STRIDE
    add s2, s2, t0
    addi t3, t3, -1
    bnez t3, 1b
    fail 1
3:  lwu t0, R_VERSION(s2)
    expect t0, 1, 1

    /* Reset, then ACKNOWLEDGE | DRIVER, no features, legacy queue setup. */
    sw zero, R_STATUS(s2)
    li t0, 1
    sw t0, R_STATUS(s2)
    li t0, 3
    sw t0, R_STATUS(s2)
    sw zero, R_GUEST_FEAT(s2)
    li t0, 4096
    sw t0, R_PAGE_SIZE(s2)
    sw zero, R_QUEUE_SEL(s2)
    lwu t0, R_QUEUE_MAX(s2)
    li t1, QSIZE
    bltu t0, t1, 4f
    sw t1, R_QUEUE_NUM(s2)
    li t0, 4096
    sw t0, R_QUEUE_ALIGN(s2)
    la s3, ring
    srli t0, s3, 12
    sw t0, R_QUEUE_PFN(s2)
    li t0, 7                            /* ... | DRIVER_OK */
    sw t0, R_STATUS(s2)

    /* Descriptor 0: buf + 4, 8 bytes, device-writable. */
    addi t0, s0, 4
    sd t0, 0(s3)
    li t0, 8
    sw t0, 8(s3)
    li t0, 2                            /* VIRTQ_DESC_F_WRITE */
    sh t0, 12(s3)
    sh zero, 14(s3)
    /* Available ring (after the 8 descriptors): ring[0] = 0, idx = 1. */
    addi t1, s3, 16 * QSIZE
    sh zero, 4(t1)
    fence
    li t0, 1
    sh t0, 2(t1)
    fence
    sw zero, R_NOTIFY(s2)

    /* 2: wait for used.idx = 1. */
    check 2
    li t0, USED_OFF
    add s4, s3, t0
    li t3, 10000000
5:  fence
    lhu t0, 2(s4)
    li t1, 1
    beq t0, t1, 6f
    addi t3, t3, -1
    bnez t3, 5b
    fail 2
6:  check 3
    lwu t0, 8(s4)                       /* used.ring[0].len */
    expect t0, 8, 3

    check 4
    lc_ddc x3, s0
    cgettag a4, x3
    expect a4, 0, 4
    check 5
    lc_ddc x3, s1
    cgettag a4, x3
    expect a4, 1, 5
    pass
4:  fail 1                              /* queue too small */

    expected_trap_handler

    .data
    .align 12
ring: .zero 8192
    .align 4
buf:  .zero 32
