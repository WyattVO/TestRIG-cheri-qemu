# QEMU_CPU: rv64
# Load-side revocation (CheriBSD's cheri_revoke): a page with CR and CRM set
# gates capability loads on its CRG bit. Loading a tagged capability while
# CRG differs from sccsr.SGCLG (supervisor pages) must raise a load
# capability page fault (cause 26); untagged loads and matching generations
# load normally. Writing sccsr must flush cached translations. The Sail model
# has no CRM/CRG, so TestRIG cannot check this.
#
# M-mode maps two Sv39 gigapages and runs the checks in S-mode:
#   VA 0x00000000 -> PA 0x00000000  (test device)
#   VA 0x80000000 -> PA 0x80000000  CR = 1 (code and data)
#   VA 0xc0000000 -> PA 0x80000000  CR = CRM = 1, CRG = 0 (alias)
#include "cheri-v9.h"
    test_start

#define PTE_VRWXAD 0xcf
#define PTE_CW  (1 << 63)
#define PTE_CR  (1 << 62)
#define PTE_CD  (1 << 61)
#define PTE_CRM (1 << 60)
#define SCCSR_SGCLG 4                   /* sccsr is CSR 0x9c0 */

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
    sd t1, 16(t0)                               /* VPN2 2: plain */
    li t1, ((0x80000000 >> 2) | PTE_VRWXAD | PTE_CW | PTE_CD | PTE_CR | PTE_CRM)
    sd t1, 24(t0)                               /* VPN2 3: CRG = 0 */
    srli t0, t0, 12
    li t1, 8 << 60
    or t0, t0, t1
    csrw satp, t0
    sfence.vma

    cspecialr x20, x1                           /* c20 = DDC (tagged) */
    li x21, 5                                   /* c21: untagged */
    li s10, -1

    li t0, 1 << 11                              /* MPP = S */
    csrw mstatus, t0
    la t0, smode
    csrw mepc, t0
    mret

smode:
    la s0, buf                                  /* VA 0x80000000 + off */
    li t0, 0x40000000
    add s1, s0, t0                              /* alias in the CRM page */
    sc_ddc x20, s0                              /* buf[0]: tagged */
    addi t0, s0, 16
    sc_ddc x21, t0                              /* buf[1]: untagged */

    /* 1: SGCLG = CRG = 0: tagged load succeeds (and fills the TLB) */
    csrci 0x9c0, SCCSR_SGCLG
    lc_ddc x3, s1
    cgettag a4, x3
    expect a4, 1, 1

    /* 2: SGCLG = 1 != CRG: tagged load traps, despite the cached entry */
    csrsi 0x9c0, SCCSR_SGCLG
    li s10, 26
    la s11, check3
    lc_ddc x3, s1
    fail 2
check3:
    /* 3: untagged load with a stale generation does not trap */
    li s10, -1
    addi t0, s1, 16
    lc_ddc x3, t0
    cgettag a4, x3
    expect a4, 0, 3

    /* 4: generations match again: tagged load succeeds */
    csrci 0x9c0, SCCSR_SGCLG
    lc_ddc x3, s1
    cgettag a4, x3
    expect a4, 1, 4
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
buf: .zero 32
