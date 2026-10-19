# QEMU_CPU: rv64,svinval=true
# QEMU caches the CHERI PTE bits in its TLB, so changing them must take
# effect after the architectural flush, and not before a stale entry is
# dropped (this is how CheriBSD revokes capability load/store rights):
#  1: CR = 1: a capability load keeps its tag (fills the TLB);
#  2: CR -> 0, then sfence.vma for that address: the tag is now cleared;
#  3: CW = 1: a tagged capability store works (fills the TLB);
#  4: CW -> 0, then Svinval (sfence.w.inval, sinval.vma, sfence.inval.ir):
#     the store raises a capability store page fault (cause 27);
#  5: CW -> 1 again with sfence.vma (all): the store works again.
# Sv39 gigapages: VPN2 0 -> test device, VPN2 2 -> RAM (code and data),
# VPN2 3 -> the same RAM (the alias whose bits are changed).
#include "cheri-v9.h"
    .option arch, +svinval
    test_start

#define PTE_VRWXAD 0xcf
#define PTE_CW  (1 << 63)
#define PTE_CR  (1 << 62)
#define PTE_CD  (1 << 61)
#define ALIAS   ((0x80000000 >> 2) | PTE_VRWXAD)

    la t0, expected_trap
    csrw mtvec, t0
    cspecialr x20, x1
    li t0, -1
    csrw pmpaddr0, t0
    li t0, 0x1f
    csrw pmpcfg0, t0

    la s2, root                         /* S-mode writes the PTEs itself */
    li t1, PTE_VRWXAD
    sd t1, 0(s2)
    li t1, ((0x80000000 >> 2) | PTE_VRWXAD | PTE_CW | PTE_CR | PTE_CD)
    sd t1, 16(s2)
    li t1, (ALIAS | PTE_CW | PTE_CR | PTE_CD)
    sd t1, 24(s2)
    srli t0, s2, 12
    li t1, 8 << 60
    or t0, t0, t1
    csrw satp, t0
    sfence.vma

    li t0, 1 << 11                      /* MPP = S */
    csrw mstatus, t0
    la t0, smode
    csrw mepc, t0
    li s8, 99
    li s10, -1
    mret

smode:
    la s0, buf
    sc_ddc x20, s0                      /* a tagged capability in buf */
    li t0, 0x40000000
    add s1, s0, t0                      /* alias VA */

    check 1
    lc_ddc x3, s1
    cgettag a4, x3
    expect a4, 1, 1

    check 2
    li t1, (ALIAS | PTE_CW | PTE_CD)    /* CR = 0, CRM = 0 */
    sd t1, 24(s2)
    sfence.vma s1, zero
    lc_ddc x3, s1
    cgettag a4, x3
    expect a4, 0, 2

    check 3
    li t1, (ALIAS | PTE_CW | PTE_CR | PTE_CD)
    sd t1, 24(s2)
    sfence.vma
    addi s3, s1, 16
    sc_ddc x20, s3

    check 4
    li t1, (ALIAS | PTE_CR | PTE_CD)    /* CW = 0 */
    sd t1, 24(s2)
    sfence.w.inval
    sinval.vma s1, zero
    sfence.inval.ir
    trap_expect 27, -1, 4f
    sc_ddc x20, s3
    fail 4
4:
    check 5
    li t1, (ALIAS | PTE_CW | PTE_CR | PTE_CD)
    sd t1, 24(s2)
    sfence.vma
    sc_ddc x20, s3
    lc_ddc x3, s3
    cgettag a4, x3
    expect a4, 1, 5
    pass

    expected_trap_handler

    .data
    .align 12
root: .zero 4096
    .align 4
buf: .zero 32
