# QEMU_CPU: rv64
# A store-conditional is a store: its authority needs Store permission, not
# Load permission. QEMU checked SC addresses with the load check, so through a
# Load-only DDC or capability a reserved SC succeeded and wrote memory
# (trace cheri-qemu-10.2/29 compares the mode-dependent sc.w/sc.d with Sail;
# Sail has no explicit .ddc/.cap forms, so those are checked here):
#  1: sc.w with a Load-only DDC                 -> PermitStore on DDC;
#  2: sc.w.ddc with a Load-only DDC             -> PermitStore on DDC;
#  3: sc.w.cap through Load-only c21            -> PermitStore on c21;
#  4: sc.w.cap through Store-only c22 succeeds (Load is not needed) and
#     writes memory;
#  5: capability mode, sc.w/sc.d through Load-only c8 -> PermitStore on c8.
#include "cheri-v9.h"
    test_start

    /* Explicit-authority LR/SC (rd of sc is its data register rs2). */
    .macro lr_w_ddc rd, rs1
    .insn r 0x5b, 0, 0x7d, \rd, \rs1, x18
    .endm
    .macro sc_w_ddc rs2, rs1
    .insn r 0x5b, 0, 0x7c, x18, \rs1, \rs2
    .endm
    .macro sc_w_cap rs2, cs1
    .insn r 0x5b, 0, 0x7c, x26, \cs1, \rs2
    .endm
#define CSETFLAGS(cd, cs1, rs2) .insn r 0x5b, 0, 0x0e, cd, cs1, rs2
#define TVAL_STORE(r) (((r) << 5) | 0x13)
#define PERMS_NO_LOAD (~0x14)           /* all but Load and LoadCap */

    la t0, trap
    csrw mtvec, t0
    cspecialr x20, x1                   /* c20 = full DDC */
    la s0, buf
    li t0, PERMS_NO_STORE
    candperm x23, x20, t0               /* c23 = Load-only DDC */

    check 1
    cspecialw x1, x23
    lr.w a0, (s0)
    trap_expect CAUSE_CHERI, TVAL_DDC_STORE, 4f
    sc.w a1, zero, (s0)
    fail 1
4:  check 2
    cspecialw x1, x23
    lr_w_ddc a0, s0
    li a1, 0
    trap_expect CAUSE_CHERI, TVAL_DDC_STORE, 4f
    sc_w_ddc a1, s0
    fail 2
4:  check 3
    csetaddr x21, x23, s0               /* c21 = Load-only cap at buf */
    lr.w a0, (s0)
    li a1, 0
    trap_expect CAUSE_CHERI, TVAL_STORE(21), 4f
    sc_w_cap a1, x21
    fail 3
4:  check 4
    li t0, PERMS_NO_LOAD
    candperm x22, x20, t0
    csetaddr x22, x22, s0               /* c22 = Store-only cap at buf */
    lr.w a0, (s0)
    li a1, 0x77
    sc_w_cap a1, x22
    expect a1, 0, 4                     /* succeeded */
    lw a2, 0(s0)
    expect a2, 0x77, 4

    /* 5: capability mode; c8 = Load-only cap at buf. */
    check 5
    csetaddr x8, x23, s0
    cspecialr x24, x0
    lla t0, capmode
    csetaddr x24, x24, t0
    li t0, 1
    CSETFLAGS(x24, x24, x5)
    cjalr x0, x24
capmode:
    lr.w a0, (s0)
    trap_expect CAUSE_CHERI, TVAL_STORE(8), 4f
    sc.w a1, zero, (s0)
    fail 5
4:  lr.d a0, (s0)
    trap_expect CAUSE_CHERI, TVAL_STORE(8), 4f
    sc.d a1, zero, (s0)
    fail 5
4:  ecall                               /* done (see ext-mem-insns-capmode.S) */

    .align 2
trap:
    cspecialw x1, x20
    csrr t0, mcause
    li t2, 11
    beq t0, t2, 3f
    bne t0, s10, 2f
    csrr t0, mtval
    bne t0, s9, 2f
    li s10, -1
    csrw mepc, s11
    mret
2:  fail_reg s8
3:  pass

    .data
    .align 4
buf: .zero 16
