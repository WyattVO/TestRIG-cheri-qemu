# QEMU_CPU: rv64
# QEMU caches translated code (TBs) keyed by the CPU state that affects
# translation; CHERI adds PCC's bounds and flags to that key. If they were
# lost, code first translated under a large PCC would later run under a small
# one without its fetch bounds being checked. Here f runs twice with the full
# PCC (so its TB is cached), then through cjalr with a PCC covering only f's
# first instruction: that instruction runs, the next fetch must raise a CHERI
# PCC length violation at f + 4.
# QEMU 11 moves the RISC-V extra TB flags into tb->cs_base (1c88ab9e77) and
# keys big-endian/altfmt state there; the rebase must keep CHERI's PCC key.
#include "cheri-v9.h"
    test_start

    la t0, trap
    csrw mtvec, t0
    li s1, 0
    call f
    call f
    expect s1, 2, 1

    cspecialr x22, x0                   /* c22 = PCC */
    la t0, f
    csetaddr x22, x22, t0
    li t1, 4
    csetbounds x22, x22, t1             /* c22 = [f, f + 4) */
    cjalr x1, x22
    fail 2                              /* f returned: fetch not checked */

    .align 2
trap:
    csrr t0, mcause
    expect t0, CAUSE_CHERI, 3
    csrr t0, mtval
    expect t0, TVAL_PCC_LENGTH, 4
    csrr t0, mepc
    la t1, f
    addi t1, t1, 4
    beq t0, t1, 3f
    fail 5
3:  expect s1, 3, 6                     /* f's first instruction ran */
    pass

    .option push
    .option norvc
    .align 4
f:
    addi s1, s1, 1
    addi s1, s1, 0                      /* outside the small PCC */
    ret
    .option pop
