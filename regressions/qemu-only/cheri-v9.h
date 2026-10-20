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

    /* Write an SCR (e.g. cspecialw x1, c20 sets DDC). */
    .macro cspecialw scr, cs
    .insn r 0x5b, 0, 0x01, x0, \cs, \scr
    .endm
    .macro csetaddr cd, cs1, rs2
    .insn r 0x5b, 0, 0x10, \cd, \cs1, \rs2
    .endm
    .macro csetbounds cd, cs1, rs2
    .insn r 0x5b, 0, 0x08, \cd, \cs1, \rs2
    .endm
    .macro candperm cd, cs1, rs2
    .insn r 0x5b, 0, 0x0d, \cd, \cs1, \rs2
    .endm
    /* Jump to capability cs1 (installs it as PCC), link in cd. */
    .macro cjalr cd, cs1
    .insn r 0x5b, 0, 0x7f, \cd, \cs1, x12
    .endm

#define CAUSE_CHERI     28
/* mtval of a CHERI fault: capability register index << 5 | CHERI cause */
#define TVAL_PCC_LENGTH 0x401   /* PCC (0x20), length violation (0x01) */
#define TVAL_DDC_LENGTH 0x421   /* DDC (0x21), length violation (0x01) */
#define TVAL_DDC_STORE  0x433   /* DDC (0x21), PermitStore violation (0x13) */
/* All permissions except Store, StoreCap and StoreLocalCap. */
#define PERMS_NO_STORE  (~0x68)

    /*
     * Exit QEMU: pass, or fail with the given check number. fail first sets
     * s10 = -1 (no trap expected): with a restricted DDC its own store to
     * the test device can fault exactly like the access under test, and
     * must not be taken for that expected fault.
     */
    .macro pass
    li t0, TEST_DEVICE
    li t1, 0x5555
    sw t1, 0(t0)
1:  j 1b
    .endm
    .macro fail n
    li s10, -1
    li t0, TEST_DEVICE
    li t1, (\n << 16) | 0x3333
    sw t1, 0(t0)
1:  j 1b
    .endm

    /* Fail with the check number held in register r. */
    .macro fail_reg r
    li t0, TEST_DEVICE
    slli t1, \r, 16
    li t2, 0x3333
    or t1, t1, t2
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

    /*
     * Expected traps, for tests that use expected_trap_handler as mtvec:
     * s8 = number of the current check (reported if anything goes wrong),
     * s10 = expected mcause (-1: no trap expected), s9 = expected mtval
     * (-1: any), s11 = where to resume. c20 must hold a full DDC; the
     * handler restores DDC from it before checking anything.
     */
    .macro check n
    li s8, \n
    li s10, -1
    .endm
    .macro trap_expect cause, tval, resume
    li s10, \cause
    li s9, \tval
    lla s11, \resume        /* no GOT load: DDC may be restricted here */
    .endm
    .macro expected_trap_handler
    .align 2
expected_trap:
    cspecialw x1, x20
    csrr t0, mcause
    bne t0, s10, 1f
    li t1, -1
    beq s9, t1, 2f
    csrr t0, mtval
    bne t0, s9, 1f
2:  li s10, -1
    csrw mepc, s11
    mret
1:  fail_reg s8
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
