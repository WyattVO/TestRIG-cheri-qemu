# QEMU_CPU: rv64,zacas=true,zabha=true
# An amocas with rd = x0 compares against zero and discards the old memory
# value (Zacas, Zabha). QEMU's translator gave the shared constant-zero
# temporary to the cmpxchg as its result, which corrupts TCG's register
# allocation: later uses of x0 in the same translation block can read
# another value, e.g. "sd x0" stored a nonzero one (upstream QEMU 10.2 and
# 11.x; found by upstream-diff.py on riscv-arch-test amocas.w-01, whose
# signature store of x0 wrote the swap value).
# Each check fails the compare (memory is non-zero), stores x0 in the same
# block and, in a new block (the jump ends it; inside the old one "li t2, 0"
# can read the same bad x0), expects the stored doubleword to be 0:
#   1 amocas.w   2 amocas.d   3 amocas.b   4 amocas.h   5 amocas.q
#include "cheri-v9.h"
    .option arch, +zacas, +zabha
    test_start

    la sp, buf
    la s0, out
    li a2, 0x55

    .macro check_cas insn, n
    \insn x0, a2, (sp)
    sd x0, 0(s0)
    j 1f
1:  ld a4, 0(s0)
    expect a4, 0, \n
    .endm

    check_cas amocas.w, 1
    check_cas amocas.d, 2
    check_cas amocas.b, 3
    check_cas amocas.h, 4
    check_cas amocas.q, 5
    pass

    .data
    .align 4
buf: .dword 0x1122334455667788, 0x99aabbccddeeff00
out: .dword -1
