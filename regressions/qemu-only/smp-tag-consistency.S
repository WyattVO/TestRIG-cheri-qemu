# QEMU_CPU: rv64
# QEMU_SMP: 2
# QEMU_THREADS: single multi
# Two harts share a 16-byte slot. Hart 1 keeps storing a tagged capability
# with address MAGIC into it, then plain data over it (which must clear the
# tag). Hart 0 keeps loading the slot as a capability:
#  1: a tagged result must always be exactly hart 1's capability: a tag
#     combined with the plain data (a torn capability) would be a forged
#     capability;
#  2: both tagged and untagged results are seen (the harts interleaved;
#     with round-robin TCG this takes a few time slices).
#  3: after hart 1 stops, an ordinary store by hart 0 clears the tag of a
#     capability hart 1 stored (tags are per memory location, not per hart).
# It runs under round-robin TCG and under MTTCG, where the harts really run
# at once: a QEMU without the lock_tag series fails check 1 there every time
# (CHERI-QEMU 10.2 before it, forced with thread=multi).
#include "cheri-v9.h"

#define MAGIC   0x5a5a00c0ffee0000
#define PLAIN   0x1111222233334444
#define ROUNDS  200000                 /* at least this many loads */
#define MAX     (1 << 28)              /* give up: harts never interleaved */

    .section .text.init
    .globl _start
_start:
    la t0, trap
    csrw mtvec, t0
    cspecialr x20, x1                   /* each hart: c20 = full DDC */
    la s0, slot
    la s1, stop
    csrr a0, mhartid
    bnez a0, writer

reader:
    li s2, 0                            /* loads done */
    li s3, 0                            /* tagged results */
    li s4, 0                            /* untagged results */
    li s5, MAGIC
    /* wait until hart 1 is running */
    la t0, started
1:  ld t1, 0(t0)
    beqz t1, 1b
2:  lc_ddc x3, s0
    cgettag a4, x3
    beqz a4, 3f
    addi s3, s3, 1
    .insn r 0x5b, 0, 0x7f, a5, x3, x15  /* cgetaddr a5, c3 */
    beq a5, s5, 4f
    fail 1                              /* tagged, but not the capability */
3:  addi s4, s4, 1
4:  addi s2, s2, 1
    li t0, ROUNDS
    blt s2, t0, 2b                      /* at least ROUNDS loads, */
    beqz s3, 8f                         /* then until both kinds seen */
    bnez s4, 9f
8:  li t0, MAX
    blt s2, t0, 2b
9:

    li t0, 1
    sd t0, 0(s1)                        /* stop hart 1 */
    la t0, stopped
5:  ld t1, 0(t0)
    beqz t1, 5b
    bnez s3, 6f
    fail 2
6:  bnez s4, 7f
    fail 2
7:  lc_ddc x3, s0                       /* hart 1 left a capability there */
    cgettag a4, x3
    expect a4, 1, 3
    sd zero, 8(s0)
    lc_ddc x3, s0
    cgettag a4, x3
    expect a4, 0, 3
    pass

writer:
    li t0, MAGIC
    csetaddr x21, x20, t0               /* c21: tagged, address MAGIC */
    li t2, PLAIN
    la t0, started
    li t1, 1
    sd t1, 0(t0)
1:  sc_ddc x21, s0
    j 3f                                /* end the translation block here, */
3:  sd t2, 0(s0)                        /* so round-robin TCG can switch harts
                                           in either state; plain data
                                           clears the tag */
    sd t2, 8(s0)
    ld t1, 0(s1)
    beqz t1, 1b
    sc_ddc x21, s0                      /* leave a capability for check 3 */
    la t0, stopped
    li t1, 1
    sd t1, 0(t0)
2:  wfi
    j 2b

    .align 2
trap:
    fail 99

    .data
    .align 4
slot:    .zero 16
stop:    .dword 0
started: .dword 0
stopped: .dword 0
