# QEMU_CPU: rv64,xmipscmov=true,xmipscbop=true,smpmpmt=true
# QEMU_VERSION: >=11.0
# Extensions new in QEMU 11.0 that the CHERI build allows (see
# regressions/cheri-extensions.txt), checked against their specifications
# and for CHERI. The Sail v9 model has none of them, so random TestRIG
# tests never run them.
#  1: XMIPSCMOV  mips.ccmov rd, rs2, rs1, rs3 sets rd = rs2 != 0 ? rs1 : rs3;
#  2:            its result is an integer: writing a register that held a
#                tagged capability clears the tag, and a capability source
#                gives only its address;
#  3: XMIPSCBOP  mips.pref is a hint: it never faults, even outside DDC's
#                bounds or through a DDC without Load permission (CHERI: a
#                prefetch is not an access);
#  4: Smpmpmt    pmpcfg keeps the memory-type field MT (bits 6:5), and a
#                write of the reserved MT = 3 leaves the old MT in place;
#  5:            MT does not change the PMP permissions: a locked read-only
#                entry with MT = 1 still lets M-mode load but makes stores,
#                capability stores included, raise store access faults.
#include "cheri-v9.h"
    .option arch, +xmipscmov, +xmipscbop
    test_start

#define CAUSE_STORE_ACCESS 7
#define PMP_R      0x01
#define PMP_NAPOT  0x18
#define PMP_MT1    0x20
#define PMP_MT3    0x60
#define PMP_L      0x80
/* All permissions except Load, LoadCap */
#define PERMS_NO_LOAD (~0x14)

    la t0, expected_trap
    csrw mtvec, t0
    cspecialr x20, x1                   /* c20 = full DDC */
    la s0, buf

    check 1
    li a1, 1
    li a2, 0x1234
    li a3, 0x5678
    mips.ccmov a0, a1, a2, a3           /* a1 != 0 -> a2 */
    expect a0, 0x1234, 1
    li a1, 0
    mips.ccmov a0, a1, a2, a3           /* a1 == 0 -> a3 */
    expect a0, 0x5678, 1

    check 2
    csetaddr x10, x20, s0               /* c10 (a0) = tagged capability at buf */
    li a1, 1
    mips.ccmov x10, a1, a2, a3          /* overwrite c10 with 0x1234 */
    cgettag a4, x10
    expect a4, 0, 2
    expect a0, 0x1234, 2
    csetaddr x13, x20, s0               /* c13 (a3) = tagged capability at buf */
    mips.ccmov x10, a1, x13, a2         /* from rs1: rd = c13's address */
    cgettag a4, x10
    expect a4, 0, 2
    bne a0, s0, 1f
    li a1, 0
    mips.ccmov x15, a1, a2, x13         /* from rs3 */
    cgettag a4, x15
    expect a4, 0, 2
    beq a5, s0, 2f
1:  fail 2
2:

    check 3
    addi a0, s0, 64
    csetaddr x21, x20, s0               /* DDC = [buf, buf + 64) */
    li t0, 64
    csetbounds x21, x21, t0
    cspecialw x1, x21
    mips.pref 0, 0(a0)
    mips.pref 0, 128(a0)
    li t0, PERMS_NO_LOAD                /* DDC without Load permission */
    candperm x21, x20, t0
    cspecialw x1, x21
    mips.pref 0, 0(s0)
    cspecialw x1, x20

    check 4
    srli t0, s0, 2                      /* pmpaddr0 = buf, 64 bytes NAPOT */
    ori t0, t0, 0x7
    csrw pmpaddr0, t0
    li t0, PMP_MT1 | PMP_NAPOT | PMP_R
    csrw pmpcfg0, t0
    csrr t1, pmpcfg0
    andi t1, t1, 0xff
    bne t1, t0, 1f
    li t2, PMP_MT3 | PMP_NAPOT | PMP_R  /* reserved MT: ignored */
    csrw pmpcfg0, t2
    csrr t1, pmpcfg0
    andi t1, t1, 0xff
    beq t1, t0, 2f
1:  fail 4
2:

    check 5
    li t0, PMP_L | PMP_MT1 | PMP_NAPOT | PMP_R
    csrw pmpcfg0, t0
    ld a1, 0(s0)
    trap_expect CAUSE_STORE_ACCESS, -1, 3f
    sd a1, 0(s0)
    fail 5
3:  trap_expect CAUSE_STORE_ACCESS, -1, 4f
    sc_ddc x20, s0
    fail 5
4:  pass

    expected_trap_handler

    .data
    .align 6
buf: .zero 128
