# QEMU_CPU: rv64
# Feature: CHERI exceptions delegated to S-mode (how CheriBSD sees them).
#
# A purecap user program runs in U-mode, capability mode. When it violates a
# capability (here: a load past the end of its capability) the CPU raises a
# CHERI exception (cause 28). With medeleg bit 28 set, the kernel's S-mode
# handler must get it, not M-mode, with everything it needs to report or
# recover: scause, stval (which register and which CHERI cause) and the
# full faulting PCC in SEPCC. TestRIG runs everything in M-mode, so it never
# checks delegation.
#  1: medeleg bit 28 is writable (CHERI exceptions can be delegated);
#  2: the fault goes to S-mode (an M-mode trap fails with this check), with
#     scause = 28;
#  3: stval = c9 (register 9) << 5 | length violation (0x01);
#  4: SEPCC is the user PCC: tagged, capability mode, address of the
#     faulting load;
#  5: the handler ran in S-mode integer mode (STCC), and sret returns to the
#     user program in capability mode, which then reaches its ecall (8).
#include "cheri-v9.h"
    test_start

#define CAUSE_U_ECALL 8
#define CAUSE_S_ECALL 9
#define CSETFLAGS(cd, cs1, rs2) .insn r 0x5b, 0, 0x0e, cd, cs1, rs2
    .macro cgetflags rd, cs1
    .insn r 0x5b, 0, 0x7f, \rd, \cs1, x7
    .endm
    .macro cgetaddr rd, cs1
    .insn r 0x5b, 0, 0x7f, \rd, \cs1, x15
    .endm

    la t0, mtrap
    csrw mtvec, t0
    li t0, -1                           /* PMP: allow S and U everything */
    csrw pmpaddr0, t0
    li t0, 0x1f
    csrw pmpcfg0, t0

    /* 1: delegate CHERI exceptions and U-mode ecalls to S-mode. */
    li s8, 1
    li t0, (1 << CAUSE_CHERI) | (1 << CAUSE_U_ECALL)
    csrs medeleg, t0
    csrr t1, medeleg
    and t1, t1, t0
    bne t1, t0, mfail
    la t0, strap
    csrw stvec, t0

    /* c9 = 16-byte capability [buf, buf + 16), address buf + 16 (just past
     * its end); c22 = user PCC: [ucode, ucode_end), capability mode. */
    cspecialr x20, x1
    la t0, buf
    csetaddr x9, x20, t0
    li t1, 16
    csetbounds x9, x9, t1
    addi t0, t0, 16
    csetaddr x9, x9, t0
    cspecialr x22, x0
    lla t0, ucode
    csetaddr x22, x22, t0
    lla t1, ucode_end
    sub t1, t1, t0
    csetbounds x22, x22, t1
    li t0, 1
    CSETFLAGS(x22, x22, x5)

    /* Enter U-mode, capability mode: MEPCC = c22, MPP = U. */
    cspecialw x31, x22
    li t0, 3 << 11
    csrc mstatus, t0
    li s8, 2
    li s7, 0                            /* set by the S handler */
    mret

    .balign 64
ucode:
    .option push
    .option norvc                       /* 4-byte load: the handler skips 4 */
    ld a1, 0(s1)                        /* (c9) is out of bounds: fault */
    ecall                               /* reached after sret: cause 8 */
    .option pop
    .balign 64
ucode_end:

    /* S-mode handler (runs with STCC, integer mode). */
    .align 2
strap:
    csrr t0, scause
    li t1, CAUSE_U_ECALL
    beq t0, t1, uecall
    li t1, CAUSE_CHERI
    bne t0, t1, sfail                   /* 2: scause must be 28 */
    li s8, 3
    csrr t0, stval
    li t1, (9 << 5) | 0x01
    bne t0, t1, sfail
    li s8, 4
    cspecialr x17, x15                  /* SEPCC */
    cgettag t0, x17
    beqz t0, sfail
    cgetflags t0, x17
    beqz t0, sfail
    cgetaddr t0, x17
    lla t1, ucode
    bne t0, t1, sfail
    csrr t0, sepc
    bne t0, t1, sfail
    li s8, 5
    cspecialr x17, x0                   /* handler PCC: integer mode */
    cgetflags t0, x17
    bnez t0, sfail
    li s7, 1
    addi t0, t1, 4                      /* skip the faulting load */
    csrw sepc, t0
    sret
uecall:
    beqz s7, sfail                      /* the CHERI fault was handled */
    ecall                               /* S -> M: done */
sfail:
    ecall                               /* report check s8 from M-mode */

    .align 2
mtrap:
    csrr t0, mcause
    li t1, CAUSE_S_ECALL
    bne t0, t1, mfail                   /* e.g. CHERI fault not delegated */
    li t1, 1
    bne s7, t1, mfail
    csrr t0, mepc
    lla t1, uecall
    addi t1, t1, 4                      /* the "done" ecall */
    bne t0, t1, mfail
    pass
mfail:
    fail_reg s8

    .data
    .align 4
buf: .zero 16
