# QEMU_CPU: rv64
# The CHERI v9 PTE bit CW (63) controls capability stores: storing a tagged
# capability to a page with CW clear must raise a store/AMO capability page
# fault (cause 27), while an untagged one is an ordinary data store. The
# Sail model never enforces CW, so TestRIG cannot check this.
#
# M-mode maps three Sv39 gigapages and runs the checks in S-mode:
#   VA 0x00000000 -> PA 0x00000000  (test device)
#   VA 0x80000000 -> PA 0x80000000  CW = 1 (code and data)
#   VA 0xc0000000 -> PA 0x80000000  CW = 0 (alias of the same memory)
#include "cheri-v9.h"
    test_start

#define PTE_VRWXAD 0xcf
#define PTE_CW (1 << 63)
#define PTE_CD (1 << 61)
#define PTE_CR (1 << 62)

    /* Expected traps: s10 = expected mcause, s11 = where to resume. */
    la t0, trap
    csrw mtvec, t0

    /* Allow S-mode everything in PMP. */
    li t0, -1
    csrw pmpaddr0, t0
    li t0, 0x1f
    csrw pmpcfg0, t0

    la t0, root
    li t1, PTE_VRWXAD                           /* VPN2 0: PA 0 */
    sd t1, 0(t0)
    li t1, ((0x80000000 >> 2) | PTE_VRWXAD | PTE_CW | PTE_CD | PTE_CR)
    sd t1, 16(t0)                               /* VPN2 2: CW = 1 */
    li t1, ((0x80000000 >> 2) | PTE_VRWXAD | PTE_CR)
    sd t1, 24(t0)                               /* VPN2 3: CW = 0 */
    srli t0, t0, 12
    li t1, 8 << 60
    or t0, t0, t1
    csrw satp, t0
    sfence.vma

    cspecialr x20, x1                           /* c20 = DDC (tagged) */
    li x21, 5                                   /* c21: untagged */

    li t0, 1 << 11                              /* MPP = S */
    csrw mstatus, t0
    la t0, smode
    csrw mepc, t0
    mret

smode:
    la s0, buf                                  /* VA 0x80000000 + off */
    li t0, 0x40000000
    add s1, s0, t0                              /* alias in the CW = 0 page */

    /* 1: tagged store to CW = 0 page -> cause 27 */
    li s10, 27
    la s11, check2
    sc_ddc x20, s1
    fail 1
check2:
    /* 2: untagged store to CW = 0 page is allowed */
    li s10, -1
    sc_ddc x21, s1
    /* 3: tagged store to CW = 1 page keeps its tag */
    sc_ddc x20, s0
    lc_ddc x3, s0
    cgettag a4, x3
    expect a4, 1, 3
    pass

    .align 2
trap:
    csrr t0, mcause
    bne t0, s10, unexpected
    csrw mepc, s11
    mret
unexpected:
    fail 99

    .data
    .align 12
root: .zero 4096
    .align 4
buf: .zero 16
