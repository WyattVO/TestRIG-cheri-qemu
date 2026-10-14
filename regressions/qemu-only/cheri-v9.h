/*
 * Bare-metal helpers for the QEMU-only tests (CHERI-RISC-V v9, RV64).
 * The stock assembler has no Xcheri, so CHERI instructions are emitted with
 * .insn; capability registers share numbers with the integer registers.
 */
#define TEST_DEVICE 0x100000    /* virt machine sifive_test */

    .macro cspecialr cd, scr
    .insn r 0x5b, 0, 0x01, \cd, x0, \scr
    .endm
    .macro cgettag rd, cs1
    .insn r 0x5b, 0, 0x7f, \rd, \cs1, x4
    .endm
    /* Store/load a capability at an integer address, authorized by DDC. */
    .macro sc_ddc cs2, rs1
    .insn r 0x5b, 0, 0x7c, x4, \rs1, \cs2
    .endm
    .macro lc_ddc cd, rs1
    .insn r 0x5b, 0, 0x7d, \cd, \rs1, x23
    .endm

    /* Exit QEMU: pass, or fail with the given check number. */
    .macro pass
    li t0, TEST_DEVICE
    li t1, 0x5555
    sw t1, 0(t0)
1:  j 1b
    .endm
    .macro fail n
    li t0, TEST_DEVICE
    li t1, (\n << 16) | 0x3333
    sw t1, 0(t0)
1:  j 1b
    .endm

    /* Fail with check number n unless register r holds value v. */
    .macro expect r, v, n
    li t2, \v
    beq \r, t2, 2f
    fail \n
2:
    .endm

    .macro test_start
    .section .text.init
    .globl _start
_start:
    /* Any trap is a failure (check 99). */
    la t0, 9f
    csrw mtvec, t0
    j 8f
    .align 2
9:  fail 99
8:
    .endm
