# QEMU_CPU: rv64,svadu=true
# XFAIL: QEMU 10.2 and 11.0.0 update PTEs without a PMP check; fixed upstream after v11.0.0 (fa2cf74883)
# With Svadu (menvcfg.ADUE) the page walker sets PTE bits itself; on CHERI v9
# the first tagged capability store to a CW = 1, CD = 0 page also sets CD.
# That PTE write is a supervisor store and must pass PMP: if the page table
# is read-only to S-mode, the capability store must raise a store access
# fault (cause 7) and leave CD clear. Upstream adds this check after v11.0.0
# ("Check PMP before updating PTE"); a rebase onto a QEMU with it must keep it
# on the path that sets CD.
#
# Sv39 gigapages: VPN2 0 -> test device, VPN2 2 -> RAM (all bits set),
# VPN2 3 -> RAM with CW = CR = 1, A = D = 1, CD = 0.
#include "cheri-v9.h"
    test_start

#define PTE_VRWXAD 0xcf
#define PTE_CW  (1 << 63)
#define PTE_CR  (1 << 62)
#define PTE_CD  (1 << 61)
#define MENVCFG_ADUE (1 << 61)

    la t0, trap
    csrw mtvec, t0
    cspecialr x20, x1
    li t0, MENVCFG_ADUE
    csrs menvcfg, t0
    csrr t1, menvcfg
    and t1, t1, t0
    expect t1, MENVCFG_ADUE, 1

    la s2, root
    li t1, PTE_VRWXAD
    sd t1, 0(s2)
    li t1, ((0x80000000 >> 2) | PTE_VRWXAD | PTE_CW | PTE_CR | PTE_CD)
    sd t1, 16(s2)
    li t1, ((0x80000000 >> 2) | PTE_VRWXAD | PTE_CW | PTE_CR)
    sd t1, 24(s2)

    /* pmp0: NAPOT 4 KiB over the page table, read-only; pmp1: all. */
    srli t0, s2, 2
    ori t0, t0, 0x1ff
    csrw pmpaddr0, t0
    li t0, -1
    csrw pmpaddr1, t0
    li t0, (0x1f << 8) | 0x19
    csrw pmpcfg0, t0

    srli t0, s2, 12
    li t1, 8 << 60
    or t0, t0, t1
    csrw satp, t0
    sfence.vma

    li t0, 1 << 11                      /* MPP = S */
    csrw mstatus, t0
    la t0, smode
    csrw mepc, t0
    li s10, -1
    mret

smode:
    la s0, buf
    li t0, 0x40000000
    add s1, s0, t0                      /* alias with CD = 0 */
    li s10, 7                           /* store access fault */
    lla s11, 4f
    sc_ddc x20, s1
    fail 2                              /* CD was set through a read-only PMP */
4:  ecall

mcheck:
    csrw pmpcfg0, zero
    ld t0, 24(s2)
    srli t0, t0, 61
    andi t0, t0, 1
    expect t0, 0, 3                     /* CD still clear */
    pass

    .align 2
trap:
    csrr t0, mcause
    li t1, 9                            /* ecall from S */
    beq t0, t1, mcheck
    bne t0, s10, 3f
    li s10, -1
    csrw mepc, s11
    mret
3:  fail 99

    .data
    .align 12
root: .zero 4096
    .align 4
buf: .zero 16
