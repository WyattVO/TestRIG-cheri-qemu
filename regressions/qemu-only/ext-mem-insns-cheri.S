# QEMU_CPU: rv64,zcb=true,zfh=true,zacas=true,zabha=true,zicbom=true
# Memory instructions of 10.2 extensions the Sail v9 model lacks (Zcb, Zfh,
# Zacas, Zabha, Zicbom), so random TestRIG tests never compare them. Each
# has its own translation code, so each must be checked on its own:
#  1-5:   a store into a stored capability clears its tag
#         (c.sb, c.sh, fsh, amoadd.b, amoswap.h);
#  10-22: with DDC = [buf, buf + 64), an access at buf + 64 raises a CHERI
#         length violation (mtval 0x421) instead of touching memory;
#  30-35: stores and cache-block operations through a DDC without Store
#         permission raise a CHERI PermitStore violation (mtval 0x433).
#include "cheri-v9.h"
    .option arch, +zcb, +zfh, +zacas, +zabha, +zicbom
    test_start

    la t0, expected_trap
    csrw mtvec, t0
    li t0, 1 << 13                      /* mstatus.FS = Initial */
    csrs mstatus, t0
    cspecialr x20, x1                   /* c20 = full DDC */
    la s0, buf
    addi a0, s0, 64                     /* just past the narrowed DDC */
    li a1, 0x5a
    li a2, 0
    li a3, 0
    li a4, 0
    li a5, 0
    fmv.h.x fa0, a1

    /* A store into a stored capability must clear its tag. */
    .macro clears_tag n, insn:vararg
    check \n
    sc_ddc x20, s0
    \insn
    lc_ddc x3, s0
    cgettag a4, x3
    expect a4, 0, \n
    .endm
    clears_tag 1, c.sb a1, 0(s0)
    clears_tag 2, c.sh a1, 2(s0)
    clears_tag 3, fsh fa0, 4(s0)
    clears_tag 4, amoadd.b a2, a1, (s0)
    clears_tag 5, amoswap.h a2, a1, (s0)

    /* DDC = [buf, buf + 64) */
    .macro narrow_ddc
    csetaddr x21, x20, s0
    li t0, 64
    csetbounds x21, x21, t0
    cspecialw x1, x21
    .endm
    /* DDC without Store permission */
    .macro nostore_ddc
    li t0, PERMS_NO_STORE
    candperm x21, x20, t0
    cspecialw x1, x21
    .endm
    /* Run insn under the given DDC and expect a CHERI fault with mtval tval.
     * The trap handler restores the full DDC. */
    .macro faults n, ddc, tval, insn:vararg
    check \n
    \ddc
    trap_expect CAUSE_CHERI, \tval, 4f
    \insn
    fail \n
4:
    .endm

    /* In-bounds accesses still work with the narrowed DDC. */
    check 9
    narrow_ddc
    c.lbu a1, 0(s0)
    c.sh a1, 0(s0)
    flh fa0, 0(s0)
    amocas.q a2, a4, (s0)
    amoadd.b a2, a1, (s0)
    cbo.clean (s0)
    cspecialw x1, x20

    faults 10, narrow_ddc, TVAL_DDC_LENGTH, c.lbu a1, 0(a0)
    faults 11, narrow_ddc, TVAL_DDC_LENGTH, c.lhu a1, 0(a0)
    faults 12, narrow_ddc, TVAL_DDC_LENGTH, c.sb a1, 0(a0)
    faults 13, narrow_ddc, TVAL_DDC_LENGTH, c.sh a1, 0(a0)
    faults 14, narrow_ddc, TVAL_DDC_LENGTH, flh fa0, 0(a0)
    faults 15, narrow_ddc, TVAL_DDC_LENGTH, fsh fa0, 0(a0)
    faults 16, narrow_ddc, TVAL_DDC_LENGTH, amocas.w a2, a1, (a0)
    faults 17, narrow_ddc, TVAL_DDC_LENGTH, amocas.d a2, a1, (a0)
    faults 18, narrow_ddc, TVAL_DDC_LENGTH, amocas.q a2, a4, (a0)
    faults 19, narrow_ddc, TVAL_DDC_LENGTH, amoadd.b a2, a1, (a0)
    faults 20, narrow_ddc, TVAL_DDC_LENGTH, amoswap.h a2, a1, (a0)
    faults 21, narrow_ddc, TVAL_DDC_LENGTH, cbo.clean 0(a0)
    faults 22, narrow_ddc, TVAL_DDC_LENGTH, cbo.flush 0(a0)

    faults 30, nostore_ddc, TVAL_DDC_STORE, c.sb a1, 0(s0)
    faults 31, nostore_ddc, TVAL_DDC_STORE, fsh fa0, 0(s0)
    faults 32, nostore_ddc, TVAL_DDC_STORE, amocas.d a2, a1, (s0)
    faults 33, nostore_ddc, TVAL_DDC_STORE, amoadd.b a2, a1, (s0)
    faults 34, nostore_ddc, TVAL_DDC_STORE, cbo.clean 0(s0)
    faults 35, nostore_ddc, TVAL_DDC_STORE, cbo.inval 0(s0)
    pass

    expected_trap_handler

    .data
    .align 6
buf: .zero 128
