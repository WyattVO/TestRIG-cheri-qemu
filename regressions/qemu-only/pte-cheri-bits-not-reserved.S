# QEMU_CPU: rv64
# On CHERI v9, PTE bits 59-63 are CRG, CRM, CD, CR and CW. Upstream RISC-V
# gives the same bits to Svrsw60t59b (59-60), Svpbmt (61-62) and Svnapot
# (63), and treats them as reserved when those extensions are off. QEMU 11
# makes PBMT = 3 (bits 61 and 62, i.e. CD = CR = 1, the normal CheriBSD
# mapping) fault unconditionally (3e33da68f1 "fault with reserved PTE.PBMT
# val"), outside the #if that hides the other checks on v9. Every
# combination below must work for ordinary fetches, loads and stores.
# (CRG without CR is a reserved CHERI combination and faults, so it is not
# used.)
#
# M-mode maps Sv39 gigapages of the same memory and runs the checks in
# S-mode (VPN2 2 is the normal code/data mapping):
#   VPN2 3: CR | CD          (PBMT = 3)
#   VPN2 4: CW               (Svnapot N bit)
#   VPN2 5: CW|CR|CD|CRM|CRG (all CHERI bits)
#   VPN2 6: CRM              (Svrsw60t59b bit 60)
#   VPN2 7: none
#include "cheri-v9.h"
    test_start

#define PTE_VRWXAD 0xcf
#define PTE_CW  (1 << 63)
#define PTE_CR  (1 << 62)
#define PTE_CD  (1 << 61)
#define PTE_CRM (1 << 60)
#define PTE_CRG (1 << 59)
#define LEAF(bits) ((0x80000000 >> 2) | PTE_VRWXAD | (bits))
#define GIGA 0x40000000

    la t0, expected_trap
    csrw mtvec, t0
    cspecialr x20, x1
    li t0, -1                           /* PMP: allow S-mode everything */
    csrw pmpaddr0, t0
    li t0, 0x1f
    csrw pmpcfg0, t0

    la t0, root
    li t1, PTE_VRWXAD                   /* VPN2 0: PA 0 (test device) */
    sd t1, 0(t0)
    li t1, LEAF(PTE_CW | PTE_CR | PTE_CD)
    sd t1, 16(t0)
    li t1, LEAF(PTE_CR | PTE_CD)
    sd t1, 24(t0)
    li t1, LEAF(PTE_CW)
    sd t1, 32(t0)
    li t1, LEAF(PTE_CW | PTE_CR | PTE_CD | PTE_CRM | PTE_CRG)
    sd t1, 40(t0)
    li t1, LEAF(PTE_CRM)
    sd t1, 48(t0)
    li t1, LEAF(0)
    sd t1, 56(t0)
    srli t0, t0, 12
    li t1, 8 << 60
    or t0, t0, t1
    csrw satp, t0
    sfence.vma

    li t0, 1 << 11                      /* MPP = S */
    csrw mstatus, t0
    la t0, smode
    csrw mepc, t0
    li s8, 99                           /* trap before the first check */
    li s10, -1
    mret

    /* Check n: load, store and execute through the alias in VPN2 2 + k. */
    .macro alias n, k
    check \n
    la s0, buf
    la s1, f
    li t0, \k * GIGA
    add s0, s0, t0
    add s1, s1, t0
    ld t1, 0(s0)
    sd t1, 0(s0)
    jalr s1
    .endm

smode:
    alias 1, 1
    alias 2, 2
    alias 3, 3
    alias 4, 4
    alias 5, 5
    pass

f:  ret

    expected_trap_handler

    .data
    .align 12
root: .zero 4096
    .align 4
buf: .zero 16
