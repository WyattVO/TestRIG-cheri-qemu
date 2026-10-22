# fpclear q, m (CHERI v9) zeroes FP register 8*q+i for each set bit i of m.
# The Sail model (FPClear in cheri_insts.sail) requires misa.F and
# mstatus.FS != Off, writes an FLEN-wide zero (not a NaN-boxed single) and,
# like every FP register write, sets FS to Dirty. TestRIG does not compare FP
# register values, so its fpclear traces only see whether it traps; this test
# checks the values.
#   1 with FS = Off, fpclear raises an illegal instruction (cause 2)
#   2 fpclear 0b10100101, 0 clears f0, f2, f5, f7 to exactly 0 (fmv.x.d)
#   3 ... and leaves f1, f3, f4, f6 and f8 alone
#   4 fpclear 0b10000000, 3 clears f31 and leaves f24 alone
#   5 a clearing fpclear sets FS from Initial to Dirty
#   6 fpclear 0, 1 (empty mask) does not trap and leaves FS Initial
#   7 ... and leaves f8..f15 alone
#include "cheri-v9.h"
    test_start

    .macro fpclear m, q
    .word (0x7f << 25) | (0x10 << 20) | ((((\q) << 3) | ((\m) >> 5)) << 15) | (((\m) & 31) << 7) | 0x5b
    .endm

#define MSTATUS_FS      0x6000
#define FS_INITIAL      0x2000

    /* Fill f0..f31 with fN = N + 0x100 (any non-zero value works). */
    .macro fill n
    li t0, 0x100 + \n
    fmv.d.x f\n, t0
    .endm

    /* Check n fails unless fN holds its fill value. */
    .macro kept r, n
    fmv.x.d a4, f\r
    expect a4, 0x100 + \r, \n
    .endm
    .macro cleared r, n
    fmv.x.d a4, f\r
    expect a4, 0, \n
    .endm

    /* Check 1: FS = Off. */
    li t0, MSTATUS_FS
    csrc mstatus, t0
    la t0, illegal
    csrw mtvec, t0
    li s1, 0
    fpclear 0xff, 0
    expect s1, 1, 1
    la t0, 9b               /* any other trap fails again (check 99) */
    csrw mtvec, t0

    li t0, FS_INITIAL
    csrs mstatus, t0
    .irp n, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    fill \n
    .endr

    /* Checks 2-3. */
    fpclear 0b10100101, 0
    cleared 0, 2
    cleared 2, 2
    cleared 5, 2
    cleared 7, 2
    kept 1, 3
    kept 3, 3
    kept 4, 3
    kept 6, 3
    kept 8, 3

    /* Checks 4-5: FS back to Initial first. */
    li t0, MSTATUS_FS
    csrc mstatus, t0
    li t0, FS_INITIAL
    csrs mstatus, t0
    fpclear 0b10000000, 3
    csrr a5, mstatus
    cleared 31, 4
    kept 24, 4
    li t0, MSTATUS_FS
    and a5, a5, t0
    expect a5, MSTATUS_FS, 5

    /* Checks 6-7. */
    li t0, MSTATUS_FS
    csrc mstatus, t0
    li t0, FS_INITIAL
    csrs mstatus, t0
    fpclear 0, 1
    csrr a5, mstatus
    li t0, MSTATUS_FS
    and a5, a5, t0
    expect a5, FS_INITIAL, 6
    .irp n, 8,9,10,11,12,13,14,15
    kept \n, 7
    .endr
    pass

    /* Check 1's handler: expect an illegal instruction, skip it. */
    .align 2
illegal:
    csrr t0, mcause
    li t1, 2
    bne t0, t1, 1f
    li s1, 1
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret
1:  fail 1
