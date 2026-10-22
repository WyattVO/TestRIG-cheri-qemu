# QEMU_CPU: rv64
# Feature: Sdtrig debug triggers (hardware breakpoints/watchpoints) with
# CHERI accesses.
#
# A debugger (or a kernel using triggers) must see every access to a watched
# address, including capability loads and stores, which go through CHERI's
# own helpers rather than the normal load/store path, and an execute
# breakpoint must work in capability mode and save the full PCC.
# QEMU implements data triggers as watchpoints checked on the TLB path; a
# CHERI access path that skipped them would silently miss the trigger.
# Trigger 0 is an mcontrol (type 2) trigger for M-mode (bit 6), action 0
# (breakpoint exception, cause 3), matching tdata2 exactly.
#  1: load trigger on A: ld from A raises a breakpoint, mtval = A;
#  2: load trigger on A: a capability load (lc.ddc) from A also does;
#  3: store trigger on A: sd to A raises a breakpoint;
#  4: store trigger on A: a capability store (sc.ddc) to A also does;
#  5: execute trigger on X, reached in capability mode: breakpoint with
#     mepc = X and MEPCC tagged and in capability mode; mret resumes there.
#include "cheri-v9.h"
    test_start

#define CAUSE_BREAKPOINT 3
#define MCONTROL(bits) ((2 << 60) | (1 << 6) | (bits))
#define LOAD  1
#define STORE 2
#define EXEC  4
/* Disarm: an mcontrol with no modes and no access bits never fires. QEMU
 * ignores writes of tdata1 = 0 (type 0), so 0 cannot be used. */
#define DISARMED (2 << 60)
#define CSETFLAGS(cd, cs1, rs2) .insn r 0x5b, 0, 0x0e, cd, cs1, rs2
    .macro cgetflags rd, cs1
    .insn r 0x5b, 0, 0x7f, \rd, \cs1, x7
    .endm

    la t0, expected_trap
    csrw mtvec, t0
    cspecialr x20, x1
    la s0, wbuf                         /* A, 16-byte aligned */
    sc_ddc x20, s0
    csrw tselect, zero
    csrw tdata2, s0

    /* Arm trigger 0 with the given access bits, run insn, expect a
     * breakpoint with mtval = A, then disarm. */
    .macro watch n, bits, insn:vararg
    check \n
    li t3, MCONTROL(\bits)
    csrw tdata1, t3
    trap_expect CAUSE_BREAKPOINT, -1, 4f
    mv s9, s0                           /* expected mtval: A */
    \insn
    fail \n
4:  li t3, DISARMED
    csrw tdata1, t3
    .endm

    watch 1, LOAD, ld a0, 0(s0)
    watch 2, LOAD, lc_ddc x3, s0
    watch 3, STORE, sd a0, 0(s0)
    watch 4, STORE, sc_ddc x20, s0

    /* 5: execute breakpoint in capability mode. */
    check 5
    la t0, trap5
    csrw mtvec, t0
    lla t0, xpoint
    csrw tdata2, t0
    li t3, MCONTROL(EXEC)
    csrw tdata1, t3
    cspecialr x21, x0                   /* c21: PCC at intback, integer mode */
    lla t0, intback
    csetaddr x21, x21, t0
    cspecialr x22, x0                   /* c22: PCC at capcode, cap mode */
    lla t0, capcode
    csetaddr x22, x22, t0
    li t0, 1
    CSETFLAGS(x22, x22, x5)
    li s7, 0
    cjalr x0, x22

capcode:
    nop
xpoint:
    addi s7, s7, 1                      /* breakpoint here, then resumes */
    auipc x6, 0                         /* tagged: still capability mode */
    cgettag a4, x6
    cjalr x0, x21
intback:
    expect s7, 1, 5                     /* xpoint ran once, after the trap */
    expect a4, 1, 5
    pass

    .align 2
trap5:
    li t3, DISARMED
    csrw tdata1, t3
    li s8, 5
    csrr t3, mcause
    li t4, CAUSE_BREAKPOINT
    bne t3, t4, 1f
    csrr t3, mepc
    lla t4, xpoint
    bne t3, t4, 1f
    bnez s7, 1f                         /* trapped before executing */
    cspecialr x17, x31                  /* MEPCC */
    cgettag t3, x17
    beqz t3, 1f
    cgetflags t3, x17
    beqz t3, 1f
    mret                                /* re-executes xpoint, no trigger */
1:  fail_reg s8

    expected_trap_handler

    .data
    .align 4
wbuf: .zero 16
