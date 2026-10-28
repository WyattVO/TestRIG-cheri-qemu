# QEMU_CPU: rv64,zicboz=true
# QEMU_SMP: 2
# QEMU_THREADS: single multi
# smp-tag-consistency with the other ways of overwriting a capability: hart 1
# keeps storing a tagged capability with address MAGIC into a slot, and
# overwrites it alternately with amoswap.d (an AMO: QEMU's CHERI build turns
# it into a locked load/modify/store) and cbo.zero of its 64-byte block (a
# helper that clears four tags). Hart 0 keeps loading the slot as a
# capability:
#  1: a tagged result must always be exactly hart 1's capability (a tag
#     with amoswap's PLAIN or cbo.zero's zero data would be forged);
#  2: both tagged and untagged results are seen (the harts interleaved).
# Under MTTCG (thread=multi) the harts really run at once; a QEMU without
# the lock_tag series fails check 1 there.
#include "cheri-v9.h"
    .option arch, +zicboz

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
    blt s2, t0, 2b
    beqz s3, 8f
    bnez s4, 9f
8:  li t0, MAX
    blt s2, t0, 2b
9:
    li t0, 1
    sd t0, 0(s1)                        /* stop hart 1 */
    bnez s3, 6f
    fail 2
6:  bnez s4, 7f
    fail 2
7:  pass

writer:
    li t0, MAGIC
    csetaddr x21, x20, t0               /* c21: tagged, address MAGIC */
    li t2, PLAIN
    la t0, started
    li t1, 1
    sd t1, 0(t0)
1:  sc_ddc x21, s0
    j 3f                                /* end the translation block, so */
3:  amoswap.d zero, t2, (s0)            /* round-robin TCG can switch harts */
    sc_ddc x21, s0                      /* in either state */
    j 4f
4:  cbo.zero (s0)
    ld t1, 0(s1)
    beqz t1, 1b
2:  wfi
    j 2b

    .align 2
trap:
    fail 99

    .data
    .align 6
slot:    .zero 64
stop:    .dword 0
started: .dword 0
