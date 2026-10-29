# QEMU_CPU: rv64
# QEMU_SMP: 2
# QEMU_ARGS: -global virtio-mmio.force-legacy=true -device virtio-rng-device
# QEMU_THREADS: multi
# A device write must never leave a tag on the bytes it wrote, not even for a
# moment. QEMU writes a device's data first and clears the tags after
# (invalidate_and_set_dirty, address_space_unmap); a hart that loads the
# capability in between gets a tagged capability made of device bytes, i.e.
# a forged one, and keeps it in its register.
#
# Hart 1 is a minimal virtio-rng driver (as in virtio-dma-clears-tags.S): it
# posts the 16 bytes of slot as a device-writable buffer, ROUNDS times, and
# the device fills them with random bytes. Hart 0 meanwhile keeps storing a
# capability with address MAGIC into slot and loading it back:
#  1: virtio-rng is present (hart 1);
#  2: a request did not complete (hart 1);
#  3: a loaded capability is tagged but its address is not MAGIC (forged);
#  4: the device's bytes were seen (untagged results), i.e. the harts did
#     interleave with the device.
# MTTCG only: round-robin TCG runs the harts holding QEMU's global lock,
# which this device needs, so they never overlap. The port's lock_tag
# series failed check 3 within 200 requests; the port now writes device data
# under the tag locks and gives devices bounce buffers for writable mappings
# of tagged RAM.
#include "cheri-v9.h"

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
#define MAGIC         0x5a5a00c0ffee0000
#define ROUNDS        20000             /* device writes */

    .section .text.init
    .globl _start
_start:
    la t0, trap
    csrw mtvec, t0
    cspecialr x20, x1                   /* each hart: c20 = full DDC (s4) */
    la s0, slot
    la s1, done
    csrr a0, mhartid
    bnez a0, driver

cpu:
    li t0, MAGIC
    csetaddr x21, x20, t0               /* c21 (s5): tagged, address MAGIC */
    li t4, MAGIC
    li s3, 0                            /* untagged results */
    la t0, started
1:  ld t1, 0(t0)
    beqz t1, 1b
2:  sc_ddc x21, s0
    lc_ddc x3, s0
    cgettag a4, x3
    beqz a4, 3f
    .insn r 0x5b, 0, 0x7f, a5, x3, x15  /* cgetaddr a5, c3 */
    beq a5, t4, 4f
    fail 3
3:  addi s3, s3, 1
4:  ld t0, 0(s1)
    beqz t0, 2b
    bnez s3, 5f
    fail 4
5:  pass

driver:
    /* Find virtio-rng (device ID 4) among the eight transports. */
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
3:  /* Reset, ACKNOWLEDGE | DRIVER, no features, legacy queue 0. */
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
    bgeu t0, t1, 4f
    fail 1
4:  sw t1, R_QUEUE_NUM(s2)
    li t0, 4096
    sw t0, R_QUEUE_ALIGN(s2)
    la s3, ring
    srli t0, s3, 12
    sw t0, R_QUEUE_PFN(s2)
    li t0, 7                            /* ... | DRIVER_OK */
    sw t0, R_STATUS(s2)
    /* Descriptor 0: all of slot, device-writable. */
    sd s0, 0(s3)
    li t0, 16
    sw t0, 8(s3)
    li t0, 2                            /* VIRTQ_DESC_F_WRITE */
    sh t0, 12(s3)
    sh zero, 14(s3)
    addi s5, s3, 16 * QSIZE             /* available ring */
    li t0, USED_OFF
    add s6, s3, t0                      /* used ring */

    la t0, started
    li t1, 1
    sd t1, 0(t0)
    li s7, 0                            /* requests completed */
5:  /* avail.ring[idx % QSIZE] = descriptor 0, then idx + 1 */
    andi t0, s7, QSIZE - 1
    slli t0, t0, 1
    add t0, t0, s5
    sh zero, 4(t0)
    addi s7, s7, 1
    fence
    sh s7, 2(s5)
    fence
    sw zero, R_NOTIFY(s2)
    li t3, 10000000
6:  fence
    lhu t0, 2(s6)
    slli t1, s7, 48
    srli t1, t1, 48
    beq t0, t1, 7f
    addi t3, t3, -1
    bnez t3, 6b
    fail 2
7:  li t0, ROUNDS
    blt s7, t0, 5b
    li t0, 1
    sd t0, 0(s1)                        /* tell hart 0 */
8:  wfi
    j 8b

    .align 2
trap:
    fail 99

    .data
    .align 12
ring:    .zero 8192
    .align 6
slot:    .zero 16
    .align 6
done:    .dword 0
started: .dword 0
