# QEMU_CPU: rv64
# QEMU_SMP: 2
# QEMU_THREADS: single multi
# Message passing (the MP litmus test) with capabilities: a capability's tag
# and both halves of its data must become visible together, in the order
# fences give. Hart 1 runs rounds r = 1, 2, ...: it writes slot, then
# fence w,w, then flag = r. Even rounds store a capability with address
# CAPBASE + r, derived from the full DDC (r % 4 == 0) or from a copy without
# the store permissions (r % 4 == 2), so the two halves of the capability
# change together; odd rounds store the plain doubleword PLAINBASE + r over
# its low half (clearing the tag). Hart 0 keeps reading f = flag, fence r,r,
# then slot as a capability, which must come from round f or later:
#  1: tagged, but not an even round's capability (a tag on plain data);
#  2: untagged, but an even round's capability (a capability lost its tag);
#  3: older than round f (the fences did not order slot and flag), or flag
#     went backwards;
#  4: tagged, with the permissions of a different round than its address
#     (a torn capability: halves from two stores);
#  5: neither kind of round (garbage);
#  6: both tagged and untagged results were seen (the harts interleaved).
# On an x86 host (TSO), MTTCG cannot show hardware reordering, so this checks
# that QEMU keeps tag and data together and in order.
#include "cheri-v9.h"

#define CAPHI     0x5a5a5a5a            /* high 32 bits of capability rounds */
#define PLAINHI   0x11111111            /* high 32 bits of plain rounds */
#define ROUNDS    200000                /* at least this many reads */
#define MAX       (1 << 26)             /* give up: harts never interleaved */

    .section .text.init
    .globl _start
_start:
    la t0, trap
    csrw mtvec, t0
    /* Capability registers c20 (s4), c21 (s5), c22 (s6) and c3 (gp): their
       integer names are not used below, which would clear their tags. */
    cspecialr x20, x1                   /* each hart: c20 = full DDC */
    li t0, PERMS_NO_STORE
    candperm x22, x20, t0               /* c22: DDC without store perms */
    la s0, slot
    la s1, flag
    la s2, stop
    csrr a0, mhartid
    bnez a0, writer

reader:
    .insn r 0x5b, 0, 0x7f, a6, x20, x0  /* cgetperm a6, c20: full perms */
    .insn r 0x5b, 0, 0x7f, a7, x22, x0  /* cgetperm a7, c22: reduced */
    li t4, CAPHI
    li t5, PLAINHI
    li s3, 0                            /* reads */
    li s7, 0                            /* tagged results */
    li s8, 0                            /* untagged results */
    li s9, 0                            /* last flag value */
    la t0, started
1:  ld t1, 0(t0)
    beqz t1, 1b

10: ld a1, 0(s1)                        /* f = flag */
    fence r, r
    lc_ddc x3, s0
    bgeu a1, s9, 11f
    fail 3                              /* flag went backwards */
11: mv s9, a1
    cgettag a4, x3
    .insn r 0x5b, 0, 0x7f, a5, x3, x15  /* cgetaddr a5, c3 (low half) */
    srli a2, a5, 32                     /* kind of round */
    slli a3, a5, 32
    srli a3, a3, 32                     /* round number */
    beqz a4, 20f

    /* tagged: an even round's capability, round >= f, matching perms */
    beq a2, t4, 12f
    fail 1
12: andi t0, a3, 1
    beqz t0, 13f
    fail 1
13: bgeu a3, a1, 14f
    fail 3
14: .insn r 0x5b, 0, 0x7f, t1, x3, x0   /* cgetperm t1, c3 */
    andi t0, a3, 2
    mv t2, a6
    beqz t0, 15f
    mv t2, a7
15: beq t1, t2, 16f
    fail 4
16: addi s7, s7, 1
    j 30f

    /* untagged: an odd round's data, round >= f (or still empty) */
20: bne a2, t4, 21f
    fail 2
21: bnez a5, 22f
    beqz a1, 29f                        /* nothing written yet */
    fail 3
22: beq a2, t5, 23f
    fail 5
23: andi t0, a3, 1
    bnez t0, 24f
    fail 5
24: bgeu a3, a1, 29f
    fail 3
29: addi s8, s8, 1

30: addi s3, s3, 1
    li t0, ROUNDS
    blt s3, t0, 10b
    beqz s7, 31f
    bnez s8, 32f
31: li t0, MAX
    blt s3, t0, 10b
    fail 6
32: li t0, 1
    sd t0, 0(s2)                        /* stop hart 1 */
    pass

writer:
    li a1, 0                            /* round */
    li t4, CAPHI
    slli t4, t4, 32
    li t5, PLAINHI
    slli t5, t5, 32
    la t0, started
    li t1, 1
    sd t1, 0(t0)
1:  addi a1, a1, 1
    andi t0, a1, 1
    bnez t0, 3f
    or t1, t4, a1                       /* capability round */
    andi t0, a1, 2
    bnez t0, 2f
    csetaddr x21, x20, t1
    sc_ddc x21, s0
    j 4f
2:  csetaddr x21, x22, t1
    sc_ddc x21, s0
    j 4f
3:  or t1, t5, a1                       /* plain round */
    sd t1, 0(s0)
4:  fence w, w
    sd a1, 0(s1)
    ld t0, 0(s2)
    beqz t0, 1b
5:  wfi
    j 5b

    .align 2
trap:
    fail 99

    .data
    .align 6
slot:    .zero 16
    .align 6
flag:    .dword 0
stop:    .dword 0
started: .dword 0
