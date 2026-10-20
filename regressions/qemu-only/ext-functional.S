# QEMU_CPU: rv64,zbb=true,zicond=true,zfh=true,zfa=true,zcb=true,zbkb=true,zimop=true,zcmop=true,zawrs=true,sstc=true,zicbop=true,zihintpause=true
# Feature: QEMU 10.2 extensions that the Sail v9 model lacks still compute
# the right results in the CHERI build.
#
# TestRIG compares instructions only when Sail implements them, so a port
# that broke the decoding or the result of one of these extensions would
# pass the gate. Each check runs a few instructions and compares the result
# with the value the extension's specification gives.
#  1: Zicond   czero.eqz/czero.nez select a value or zero;
#  2: Zfh      half-precision convert, add and multiply (3 + 5, 3 * 5);
#  3: Zfa      fli loads constants (0.5 double, 2.0 single);
#  4: Zcb      c.zext.b, c.sext.h (with Zbb), c.not, c.mul;
#  5: Zbkb     pack and brev8;
#  6: Zimop    mop.r.0 / mop.rr.0 / c.mop.1 write zero (or nothing);
#  7: Zawrs, Zihintpause  wrs.nto, wrs.sto and pause complete without a trap;
#  8: Sstc     stimecmp = 0 makes the supervisor timer pending
#              (mip.STIP), stimecmp = -1 clears it;
#  9: Zicbop   prefetch hints never fault, even outside DDC's bounds (CHERI:
#              a prefetch is not an access);
#  10: Zicntr  time and instret count up.
#include "cheri-v9.h"
    .option arch, +zbb, +zicond, +zfh, +zfa, +zcb, +zbkb, +zimop, +zcmop, +zawrs, +zicbop, +zihintpause
    test_start

    la t0, expected_trap                /* any trap fails the current check */
    csrw mtvec, t0
    li t0, 1 << 13                      /* mstatus.FS = Initial */
    csrs mstatus, t0
    cspecialr x20, x1

    check 1
    li a1, 0x1234
    li a2, 0
    czero.eqz a0, a1, a2                /* a2 == 0 -> 0 */
    expect a0, 0, 1
    li a2, 5
    czero.eqz a0, a1, a2                /* a2 != 0 -> a1 */
    expect a0, 0x1234, 1
    czero.nez a0, a1, a2                /* a2 != 0 -> 0 */
    expect a0, 0, 1

    check 2
    li t3, 3
    li t4, 5
    fcvt.h.w fa1, t3
    fcvt.h.w fa2, t4
    fadd.h fa3, fa1, fa2
    fmv.x.h a0, fa3
    expect a0, 0x4800, 2                /* 8.0 in binary16 */
    fmul.h fa3, fa1, fa2
    fmv.x.h a0, fa3
    expect a0, 0x4b80, 2                /* 15.0 */

    check 3
    fli.d fa0, 0.5
    fmv.x.d a0, fa0
    expect a0, 0x3fe0000000000000, 3
    fli.s fa0, 2.0
    fmv.x.w a0, fa0
    expect a0, 0x40000000, 3

    check 4                             /* compressed: registers x8-x15 */
    li a1, 0x1ff
    c.zext.b a1
    expect a1, 0xff, 4
    li a1, 0x18000
    c.sext.h a1
    expect a1, 0xffffffffffff8000, 4
    li a1, 0
    c.not a1
    expect a1, -1, 4
    li a1, 6
    li a2, 7
    c.mul a1, a2
    expect a1, 42, 4

    check 5
    li a1, 0x11112222
    li a2, 0x33334444
    pack a0, a1, a2                     /* rs2[31:0] : rs1[31:0] */
    expect a0, 0x3333444411112222, 5
    li a1, 0x0102
    brev8 a0, a1                        /* reverse the bits of each byte */
    expect a0, 0x8040, 5

    check 6
    li a0, 99
    mop.r.0 a0, a1
    expect a0, 0, 6
    li a0, 99
    mop.rr.0 a0, a1, a2
    expect a0, 0, 6
    li a1, 7
    c.mop.1                             /* no register written */
    expect a1, 7, 6

    check 7
    wrs.nto
    wrs.sto
    pause

    check 8
    li t0, 1 << 63                      /* menvcfg.STCE */
    csrs menvcfg, t0
    csrw stimecmp, zero
    csrr a0, mip
    andi a0, a0, 1 << 5
    expect a0, 1 << 5, 8
    li t0, -1
    csrw stimecmp, t0
    csrr a0, mip
    andi a0, a0, 1 << 5
    expect a0, 0, 8

    check 9                             /* DDC = [buf, buf + 64) */
    la s0, buf
    csetaddr x21, x20, s0
    li t0, 64
    csetbounds x21, x21, t0
    cspecialw x1, x21
    li a0, 0x1000                       /* far outside DDC */
    prefetch.r 0(a0)
    prefetch.w 0(a0)
    prefetch.i 0(a0)
    cspecialw x1, x20

    check 10
    rdtime a0
    rdinstret a2
    li t0, 1000
1:  addi t0, t0, -1
    bnez t0, 1b
    rdtime a1
    rdinstret a3
    bltu a1, a0, 4f
    bgeu a2, a3, 4f
    pass
4:  fail 10

    expected_trap_handler

    .data
    .align 6
buf: .zero 64
