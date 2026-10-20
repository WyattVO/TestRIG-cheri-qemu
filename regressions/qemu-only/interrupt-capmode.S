# QEMU_CPU: rv64
# Interrupts that arrive while code runs in capability mode with a small
# PCC (as purecap CheriBSD processes do). Trap entry must save the whole PCC
# in xEPCC (tag, capability-mode flag, bounds, address of the interrupted
# instruction) and run the handler with xTCC; xRET must restore it, so the
# interrupted code continues in capability mode with its own bounds.
# TestRIG cannot check this: RVFI-DII never delivers interrupts.
#  M-mode, machine software interrupt (CLINT msip):
#   1: the handler runs in integer mode (MTCC) and MEPCC is tagged, in
#      capability mode, has the code's bounds and the interrupted address;
#   2: after mret the code is still in capability mode (auipc gives a tagged
#      capability) with the same small PCC;
#  S-mode, supervisor software interrupt delegated through mideleg:
#   3: the same for SEPCC/STCC and sret;
#   4: likewise after sret.
#include "cheri-v9.h"
    test_start

#define CLINT_MSIP 0x2000000
#define MIP_SSIP   (1 << 1)
#define MIP_MSIP   (1 << 3)
#define SCR_SEPCC  15
#define SCR_MEPCC  31
#define CSETFLAGS(cd, cs1, rs2) .insn r 0x5b, 0, 0x0e, cd, cs1, rs2
    .macro cgetbase rd, cs1
    .insn r 0x5b, 0, 0x7f, \rd, \cs1, x2
    .endm
    .macro cgetlen rd, cs1
    .insn r 0x5b, 0, 0x7f, \rd, \cs1, x3
    .endm
    .macro cgetflags rd, cs1
    .insn r 0x5b, 0, 0x7f, \rd, \cs1, x7
    .endm
    .macro cgetaddr rd, cs1
    .insn r 0x5b, 0, 0x7f, \rd, \cs1, x15
    .endm
    /* c<cd> = PCC narrowed to [start, end), in capability mode */
    .macro capmode_pcc cd, start, end
    cspecialr \cd, x0
    lla t0, \start
    csetaddr \cd, \cd, t0
    lla t1, \end
    sub t1, t1, t0
    csetbounds \cd, \cd, t1
    li t0, 1
    CSETFLAGS(\cd, \cd, x5)
    .endm
    /* Fail check n unless cap register cs is the expected xEPCC
     * (cs must not be t0-t5: expect and this macro use them). */
    .macro check_epcc cs, start, end, epc, n
    cgettag t3, \cs
    expect t3, 1, \n
    cgetflags t3, \cs
    expect t3, 1, \n
    cgetbase t3, \cs
    lla t4, \start
    bne t3, t4, 5f
    cgetlen t3, \cs
    lla t5, \end
    sub t5, t5, t4
    bne t3, t5, 5f
    cgetaddr t3, \cs
    csrr t4, \epc
    beq t3, t4, 6f
5:  fail \n
6:
    .endm
    /* After xRET: auipc in capability mode gives a tagged capability, and
     * PCC still has the small bounds. Sets a4 = tag, a5 = PCC length. */
    .macro after_return
    auipc x6, 0
    cgettag a4, x6
    cspecialr x7, x0
    cgetlen a5, x7
    .endm

    la t0, mtrap
    csrw mtvec, t0
    li s1, 0

    /* Part 1: M-mode. msip pending, MIE off; enable it in capability mode. */
    check 1
    li t0, MIP_MSIP
    csrw mie, t0
    li t0, CLINT_MSIP
    li t1, 1
    sw t1, 0(t0)
    capmode_pcc x22, mcode, mcode_end
    cjalr x0, x22

    .balign 64
mcode:
    csrsi mstatus, 8                    /* MIE = 1: interrupt here */
    addi s1, s1, 1
    after_return
    ecall                               /* cause 11: to part 2 */
    .balign 64
mcode_end:

    .align 2
mtrap:
    csrr t0, mcause
    li t1, (1 << 63) | 3                /* machine software interrupt */
    beq t0, t1, msi
    li t1, 11
    beq t0, t1, part2
    li t1, 9
    beq t0, t1, done
    fail_reg s8

msi:
    cspecialr x17, x0                   /* handler PCC = MTCC: integer mode */
    cgetflags t3, x17
    expect t3, 0, 1
    cspecialr x17, x31                  /* MEPCC */
    check_epcc x17, mcode, mcode_end, mepc, 1
    li t0, CLINT_MSIP
    sw zero, 0(t0)
    li s1, 100                          /* the handler ran */
    mret

part2:
    check 2
    expect s1, 101, 2
    expect a4, 1, 2
    lla t0, mcode_end
    lla t1, mcode
    sub t0, t0, t1
    bne a5, t0, 4f

    /* Part 2: S-mode, delegated supervisor software interrupt. */
    check 3
    csrci mstatus, 8
    li t0, -1                           /* PMP: allow S-mode everything */
    csrw pmpaddr0, t0
    li t0, 0x1f
    csrw pmpcfg0, t0
    csrw mie, zero
    li t0, MIP_SSIP
    csrw mideleg, t0
    csrw mie, t0
    la t1, strap
    csrw stvec, t1
    csrs mip, t0                        /* SSIP pending, SIE still off */
    li s1, 0
    capmode_pcc x22, scode, scode_end
    cspecialw x31, x22                  /* MEPCC = S code, capability mode */
    li t0, 3 << 11
    csrc mstatus, t0
    li t0, 1 << 11                      /* MPP = S */
    csrs mstatus, t0
    mret
4:  fail 2

    .balign 64
scode:
    csrsi sstatus, 2                    /* SIE = 1: interrupt here */
    addi s1, s1, 1
    after_return
    ecall                               /* cause 9: done */
    .balign 64
scode_end:

    .align 2
strap:
    csrr t0, scause
    li t1, (1 << 63) | 1                /* supervisor software interrupt */
    bne t0, t1, 4b
    cspecialr x17, x0                   /* STCC: integer mode */
    cgetflags t3, x17
    expect t3, 0, 3
    cspecialr x17, x15                  /* SEPCC */
    check_epcc x17, scode, scode_end, sepc, 3
    li t0, MIP_SSIP
    csrc sip, t0
    li s1, 100
    sret

done:
    check 4
    expect s1, 101, 4
    expect a4, 1, 4
    lla t0, scode_end
    lla t1, scode
    sub t0, t0, t1
    beq a5, t0, 7f
    fail 4
7:  pass
