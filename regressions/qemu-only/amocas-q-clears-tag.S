# QEMU_CPU: rv64,zacas=true
# amocas.q (Zacas) is a 128-bit store: when the swap happens it must clear
# the tag of the capability it overwrites, and when the comparison fails
# memory and the tag must stay unchanged. QEMU used the generic 128-bit
# cmpxchg, which never touched tags, so a successful amocas.q forged a
# tagged capability from arbitrary bits. Sail v9 has no Zacas, so TestRIG
# cannot check this.
#include "cheri-v9.h"
    .option arch, +zacas
    test_start

    la sp, buf
    cspecialr x1, x1            /* c1 = DDC (a valid capability) */

    /* Failed compare: memory and tag must be unchanged. */
    sc_ddc x1, sp
    ld a0, 0(sp)
    ld a1, 8(sp)
    not a0, a0                  /* wrong expected value */
    li a2, 0x1234
    li a3, 0x5678
    amocas.q a0, a2, (sp)
    lc_ddc x3, sp
    cgettag a4, x3
    expect a4, 1, 1

    /* Successful compare: the tag must be cleared. */
    ld a0, 0(sp)
    ld a1, 8(sp)
    li a2, 0x1234
    mv a3, a1
    amocas.q a0, a2, (sp)
    ld a5, 0(sp)
    expect a5, 0x1234, 2
    lc_ddc x3, sp
    cgettag a4, x3
    expect a4, 0, 3

    pass

    .data
    .align 4
buf: .zero 16
