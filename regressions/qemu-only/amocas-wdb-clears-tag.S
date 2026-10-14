# QEMU_CPU: rv64,zacas=true,zabha=true
# A successful amocas.w/amocas.d (Zacas) or amocas.b (Zabha) writes part of
# a stored capability, so it must clear the capability's tag. These went
# through the generic cmpxchg expansion, which never touched tags.
#include "cheri-v9.h"
    .option arch, +zacas, +zabha
    test_start

    la sp, buf
    cspecialr x1, x1            /* c1 = DDC */

    .macro check_cas insn, load, n
    sc_ddc x1, sp
    \load a0, 0(sp)
    li a2, 0x55
    \insn a0, a2, (sp)
    lc_ddc x3, sp
    cgettag a4, x3
    expect a4, 0, \n
    .endm

    check_cas amocas.d, ld, 1
    check_cas amocas.w, lw, 2
    check_cas amocas.b, lb, 3
    pass

    .data
    .align 4
buf: .zero 16
