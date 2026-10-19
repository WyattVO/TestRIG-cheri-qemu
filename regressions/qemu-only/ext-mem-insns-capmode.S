# QEMU_CPU: rv64,zcb=true,zfh=true,zacas=true,zabha=true,zicbom=true,zicboz=true
# Capability mode (what purecap CheriBSD runs in): the address register of a
# load/store is a capability and is its authority, not DDC. Same instructions
# as ext-mem-insns-cheri.S (extensions the Sail v9 model lacks):
#  1:     in bounds of the address capability they work, and a store into a
#         stored capability clears its tag;
#  10-24: through c9 = [buf, buf + 64) with address buf + 64 they raise a
#         CHERI length violation on c9 (mtval 9 << 5 | 0x01);
#  30-35: through c10, which lacks Store permission, stores and cache-block
#         operations raise PermitStore on c10 (mtval 10 << 5 | 0x13).
# DDC stays a full capability, so a DDC-authorized access would not fault.
# The test ends with ecall (pass/fail write the test device with an integer
# address, which capability mode would reject); a check that does not fault
# hits a tag fault in "fail", which the handler reports as that check.
#include "cheri-v9.h"
    .option arch, +zcb, +zfh, +zacas, +zabha, +zicbom, +zicboz
    test_start

#define TVAL_S1_LENGTH ((9 << 5) | 0x01)
#define TVAL_A0_STORE  ((10 << 5) | 0x13)
#define CSETFLAGS(cd, cs1, rs2) .insn r 0x5b, 0, 0x0e, cd, cs1, rs2

    la t0, trap
    csrw mtvec, t0
    li t0, 1 << 13                      /* mstatus.FS = Initial */
    csrs mstatus, t0
    cspecialr x20, x1                   /* c20 = full DDC */
    la t1, buf
    sc_ddc x20, t1                      /* a tagged capability in buf */

    /* c8 = [buf, buf + 64) at buf; c9 = the same at buf + 64 */
    csetaddr x8, x20, t1
    li t0, 64
    csetbounds x8, x8, t0
    addi t2, t1, 64
    csetaddr x9, x8, t2
    /* c10 = full DDC at buf without Store permission */
    li t0, PERMS_NO_STORE
    candperm x10, x20, t0
    csetaddr x10, x10, t1
    li a1, 0x5a
    li a2, 0
    li a3, 0
    li a4, 0
    li a5, 0
    fmv.h.x fa0, a1

    /* Enter capability mode: jump to a PCC copy with the mode flag set. */
    cspecialr x22, x0
    lla t0, capmode
    csetaddr x22, x22, t0
    li t0, 1
    CSETFLAGS(x22, x22, x5)
    li s8, 98
    li s10, -1
    cjalr x0, x22

capmode:
    check 1
    c.lbu a1, 0(s0)
    flh fa0, 0(s0)
    amocas.q a2, a4, (s0)
    cbo.clean (s0)
    c.sb a1, 0(s0)                      /* into the stored capability */
    lc_ddc x3, t1
    cgettag a4, x3
    expect a4, 0, 1

    .macro faults n, tval, insn:vararg
    check \n
    trap_expect CAUSE_CHERI, \tval, 4f
    \insn
    fail \n
4:
    .endm
    faults 10, TVAL_S1_LENGTH, c.lbu a1, 0(s1)
    faults 11, TVAL_S1_LENGTH, c.lhu a1, 0(s1)
    faults 12, TVAL_S1_LENGTH, c.sb a1, 0(s1)
    faults 13, TVAL_S1_LENGTH, c.sh a1, 0(s1)
    faults 14, TVAL_S1_LENGTH, flh fa0, 0(s1)
    faults 15, TVAL_S1_LENGTH, fsh fa0, 0(s1)
    faults 16, TVAL_S1_LENGTH, amocas.w a2, a1, (s1)
    faults 17, TVAL_S1_LENGTH, amocas.d a2, a1, (s1)
    faults 18, TVAL_S1_LENGTH, amocas.q a2, a4, (s1)
    faults 19, TVAL_S1_LENGTH, amoadd.b a2, a1, (s1)
    faults 20, TVAL_S1_LENGTH, amoswap.h a2, a1, (s1)
    faults 21, TVAL_S1_LENGTH, cbo.clean 0(s1)
    faults 22, TVAL_S1_LENGTH, cbo.flush 0(s1)
    faults 23, TVAL_S1_LENGTH, cbo.zero 0(s1)
    faults 24, TVAL_S1_LENGTH, lr.w a2, (s1)

    faults 30, TVAL_A0_STORE, c.sb a1, 0(a0)
    faults 31, TVAL_A0_STORE, fsh fa0, 0(a0)
    faults 32, TVAL_A0_STORE, amocas.d a2, a1, (a0)
    faults 33, TVAL_A0_STORE, amoadd.b a2, a1, (a0)
    faults 34, TVAL_A0_STORE, cbo.zero 0(a0)
    faults 35, TVAL_A0_STORE, cbo.clean 0(a0)
    ecall

    .align 2
trap:
    csrr t0, mcause
    li t2, 11                           /* ecall from M: done */
    beq t0, t2, 3f
    bne t0, s10, 2f
    csrr t0, mtval
    bne t0, s9, 2f
    li s10, -1
    csrw mepc, s11                      /* keeps MEPCC's mode and bounds */
    mret
2:  fail_reg s8
3:  pass

    .data
    .align 6
buf: .zero 128
