# QEMU_CPU: rv64,zicboz=true
# QEMU_SMP: 2
# QEMU_THREADS: single multi
# Faults must not leak a tag lock. Under MTTCG, generated code takes a
# capability's tag lock around each store that may meet it, and a fault
# leaves the translation block by longjmp; the lock_tag series releases
# held locks there (cheri_tag_locks_exception_thrown). A lock left held
# would hang every later access to that capability; a faulting store that
# still wrote its tag or data would change memory it may not write.
#
# Hart 1 locks a PMP entry (L bit, so it binds M-mode) that makes the 16
# bytes at slot read-only for itself only (PMP is per hart), then keeps
# writing slot: a capability store, amoswap.d, cbo.zero of its block and a
# misaligned capability store over it, each of which faults; its handler
# counts the fault and skips the instruction. Hart 0, unrestricted, keeps
# using the same slot meanwhile:
#  1: a capability it stored loads back tagged with its address (MAGIC, not
#     hart 1's OTHER);
#  2: after its amoswap.d of PLAIN, slot loads untagged with PLAIN;
#  3: after its cbo.zero, slot loads untagged and zero;
#  4: hart 1 took only store faults (mcause 6 or 7).
# Hart 0 then waits until hart 1 has faulted ROUNDS times too. A leaked lock
# hangs one hart or the other: the bench reports a timeout.
#include "cheri-v9.h"
    .option arch, +zicboz

#define MAGIC   0x5a5a00c0ffee0000
#define OTHER   0x0bad0bad0bad0000
#define PLAIN   0x1111222233334444
#define ROUNDS  20000                  /* hart 0's rounds, hart 1's faults */

    .section .text.init
    .globl _start
_start:
    cspecialr x20, x1                   /* each hart: c20 = full DDC */
    la s0, slot
    la s1, stop
    la s2, faults
    csrr a0, mhartid
    bnez a0, writer

reader:
    la t0, fail_trap
    csrw mtvec, t0
    li t0, MAGIC
    csetaddr x21, x20, t0               /* c21: tagged, address MAGIC */
    li t2, PLAIN
    li t4, MAGIC                        /* not s4/s5: x20/x21 hold caps */
    la t0, started
1:  ld t1, 0(t0)
    beqz t1, 1b
    li s3, 0                            /* rounds done */
2:  sc_ddc x21, s0
    lc_ddc x3, s0
    cgettag a4, x3
    bnez a4, 3f
    fail 1
3:  .insn r 0x5b, 0, 0x7f, a5, x3, x15  /* cgetaddr a5, c3 */
    beq a5, t4, 4f
    fail 1
4:  amoswap.d zero, t2, (s0)
    lc_ddc x3, s0
    cgettag a4, x3
    beqz a4, 5f
    fail 2
5:  ld a5, 0(s0)
    beq a5, t2, 6f
    fail 2
6:  cbo.zero (s0)
    lc_ddc x3, s0
    cgettag a4, x3
    beqz a4, 7f
    fail 3
7:  ld a5, 0(s0)
    ld a6, 8(s0)
    or a5, a5, a6
    beqz a5, 8f
    fail 3
8:  addi s3, s3, 1
    li t0, ROUNDS
    blt s3, t0, 2b
    /* Wait for hart 1 to have faulted ROUNDS times as well. */
    li t0, ROUNDS
9:  ld a5, 0(s2)
    bltu a5, t0, 9b
    li t0, 1
    sd t0, 0(s1)                        /* stop hart 1 */
    pass

writer:
    la t0, fault_trap
    csrw mtvec, t0
    /* pmp0: NAPOT, the 16 bytes at slot, read-only, locked (binds M-mode). */
    srli t0, s0, 2
    ori t0, t0, 1
    csrw pmpaddr0, t0
    li t0, 0x80 | 0x18 | 0x01
    csrw pmpcfg0, t0
    li t0, OTHER
    csetaddr x21, x20, t0               /* c21: tagged, address OTHER */
    li t2, 0x0bad
    addi t5, s0, 8                      /* misaligned, overlaps slot */
    li s3, 0                            /* faults taken */
    la t0, started
    li t1, 1
    sd t1, 0(t0)
1:  sc_ddc x21, s0                      /* each of these faults */
    amoswap.d zero, t2, (s0)
    cbo.zero (s0)
    sc_ddc x21, t5
    ld t1, 0(s1)
    beqz t1, 1b
2:  wfi
    j 2b

    .align 2
fault_trap:
    csrr t0, mcause
    addi t0, t0, -6
    li t1, 1
    bleu t0, t1, 2f
    fail 4                              /* (fail defines label 1) */
2:  addi s3, s3, 1
    sd s3, 0(s2)
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret

    .align 2
fail_trap:
    fail 99

    .data
    .align 6
slot:    .zero 64
    .align 3
stop:    .dword 0
started: .dword 0
faults:  .dword 0
