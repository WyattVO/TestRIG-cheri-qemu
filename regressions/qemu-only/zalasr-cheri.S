# QEMU_CPU: rv64,zalasr=true
# QEMU_VERSION: >=11.0
# Zalasr (load-acquire/store-release, new in QEMU 11.0) under CHERI v9. The
# Sail v9 model lacks Zalasr, so random TestRIG tests never run it, and its
# upstream translation used raw addresses (no DDC check). The port routes
# integer-mode accesses through DDC and reserves them in capability mode,
# because CHERI v9 defines no capability form of them.
#  1:     ld.aq/sd.rl and the narrower forms store and load the right values;
#  2:     lw.aq into x0 leaves x0 zero (x0 must not take the loaded value,
#         even later in the same translation block);
#  3-6:   sb.rl/sh.rl/sw.rl/sd.rl into a stored capability clear its tag;
#  10-17: with DDC = [buf, buf + 64), an access at buf + 64 raises a CHERI
#         length violation (mtval 0x421) instead of touching memory;
#  20-23: stores through a DDC without Store permission raise a CHERI
#         PermitStore violation (mtval 0x433);
#  30-31: in capability mode lw.aq and sw.rl are illegal instructions.
#include "cheri-v9.h"
    test_start

/* The assembler has no Zalasr: AMO opcode, funct5 00110 (load, aq = 1) or
 * 00111 (store, rl = 1), funct3 = width. */
    .macro l_aq w, rd, rs1
    .insn r 0x2f, \w, 0x1a, \rd, \rs1, x0
    .endm
    .macro s_rl w, rs2, rs1
    .insn r 0x2f, \w, 0x1d, x0, \rs1, \rs2
    .endm
#define CSETFLAGS(cd, cs1, rs2) .insn r 0x5b, 0, 0x0e, cd, cs1, rs2
#define CAUSE_ILLEGAL 2

    la t0, trap
    csrw mtvec, t0
    cspecialr x20, x1                   /* c20 = full DDC */
    la s0, buf
    addi a0, s0, 64                     /* just past the narrowed DDC */

    check 1
    li a1, 0x1122334455667788
    s_rl 3, a1, s0                      /* sd.rl */
    l_aq 3, a2, s0                      /* ld.aq */
    bne a2, a1, 1f
    l_aq 2, a2, s0                      /* lw.aq: sign-extended low word */
    li t0, 0x55667788
    bne a2, t0, 1f
    li a1, -2
    s_rl 1, a1, s0                      /* sh.rl 0xfffe */
    l_aq 1, a2, s0                      /* lh.aq */
    bne a2, a1, 1f
    l_aq 0, a2, s0                      /* lb.aq */
    bne a2, a1, 1f
    li a1, 0x7f
    s_rl 0, a1, s0                      /* sb.rl */
    l_aq 0, a2, s0
    beq a2, a1, 2f
1:  fail 1
2:

    check 2
    li a1, 0x1234
    sd a1, 0(s0)
    l_aq 2, x0, s0                      /* lw.aq x0 */
    add a2, x0, x0                      /* same translation block */
    expect a2, 0, 2

    .macro clears_tag n, w
    check \n
    sc_ddc x20, s0
    li a1, 0x5a
    s_rl \w, a1, s0
    lc_ddc x3, s0
    cgettag a4, x3
    expect a4, 0, \n
    .endm
    clears_tag 3, 0
    clears_tag 4, 1
    clears_tag 5, 2
    clears_tag 6, 3

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
    /* Run insn under the given DDC and expect a trap with mtval tval.
     * The trap handler restores the full DDC. */
    .macro faults n, ddc, cause, tval, insn:vararg
    check \n
    \ddc
    trap_expect \cause, \tval, 4f
    \insn
    fail \n
4:
    .endm
    faults 10, narrow_ddc, CAUSE_CHERI, TVAL_DDC_LENGTH, l_aq 0, a1, a0
    faults 11, narrow_ddc, CAUSE_CHERI, TVAL_DDC_LENGTH, l_aq 1, a1, a0
    faults 12, narrow_ddc, CAUSE_CHERI, TVAL_DDC_LENGTH, l_aq 2, a1, a0
    faults 13, narrow_ddc, CAUSE_CHERI, TVAL_DDC_LENGTH, l_aq 3, a1, a0
    faults 14, narrow_ddc, CAUSE_CHERI, TVAL_DDC_LENGTH, s_rl 0, a1, a0
    faults 15, narrow_ddc, CAUSE_CHERI, TVAL_DDC_LENGTH, s_rl 1, a1, a0
    faults 16, narrow_ddc, CAUSE_CHERI, TVAL_DDC_LENGTH, s_rl 2, a1, a0
    faults 17, narrow_ddc, CAUSE_CHERI, TVAL_DDC_LENGTH, s_rl 3, a1, a0

    faults 20, nostore_ddc, CAUSE_CHERI, TVAL_DDC_STORE, s_rl 0, a1, s0
    faults 21, nostore_ddc, CAUSE_CHERI, TVAL_DDC_STORE, s_rl 1, a1, s0
    faults 22, nostore_ddc, CAUSE_CHERI, TVAL_DDC_STORE, s_rl 2, a1, s0
    faults 23, nostore_ddc, CAUSE_CHERI, TVAL_DDC_STORE, s_rl 3, a1, s0

    /* Enter capability mode: jump to a PCC copy with the mode flag set.
     * c8 = full DDC at buf, so a capability-mode access would succeed. */
    csetaddr x8, x20, s0
    cspecialr x22, x0
    lla t0, capmode
    csetaddr x22, x22, t0
    li t0, 1
    CSETFLAGS(x22, x22, x5)
    check 98
    cjalr x0, x22

capmode:
    /* The trap handler resumes at mepc = s11, keeping MEPCC's mode. */
    faults 30, , CAUSE_ILLEGAL, -1, l_aq 2, a1, x8
    faults 31, , CAUSE_ILLEGAL, -1, s_rl 2, a1, x8
    ecall                               /* done; "fail" can't run here */

    /* Like expected_trap_handler, but ecall from M-mode ends the test
     * (capability mode can't write the test device with an integer
     * address). */
    .align 2
trap:
    cspecialw x1, x20
    csrr t0, mcause
    li t1, 11
    beq t0, t1, 3f
    bne t0, s10, 1f
    li t1, -1
    beq s9, t1, 2f
    csrr t0, mtval
    bne t0, s9, 1f
2:  li s10, -1
    csrw mepc, s11
    mret
1:  fail_reg s8
3:  pass

    .data
    .align 6
buf: .zero 128
