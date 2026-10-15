# QEMU_CPU: rv64
# CHERI v9 PTE bits must keep working once the page is in QEMU's TLB:
#  - CR = 0 (and CRM = 0): capability loads return untagged values
#    (PAGE_LC_CLEAR).
#  - CD = 0 with CW = 1: the first tagged capability store must set CD in the
#    PTE (or trap), even if an ordinary access filled the TLB entry first
#    (PAGE_SC_TRAP forces the re-walk).
# QEMU 10.x stored these flags in an 8-bit TLB field and dropped them. The
# Sail model has neither CD updates nor CRM, so TestRIG cannot check this.
#
# M-mode maps three Sv39 gigapages and runs the checks in S-mode:
#   VA 0x00000000 -> PA 0x00000000  (test device)
#   VA 0x80000000 -> PA 0x80000000  CR = CW = CD = 1 (code and data)
#   VA 0xc0000000 -> PA 0x80000000  CR = 0, CRM = 0 (alias)
#   VA 0x100000000 -> PA 0x80000000 CR = CW = 1, CD = 0 (alias)
#include "cheri-v9.h"
    test_start

#define PTE_VRWXAD 0xcf
#define PTE_CW  (1 << 63)
#define PTE_CR  (1 << 62)
#define PTE_CD  (1 << 61)

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
    li t1, ((0x80000000 >> 2) | PTE_VRWXAD | PTE_CW | PTE_CD)
    sd t1, 24(t0)                               /* VPN2 3: CR = 0 */
    li t1, ((0x80000000 >> 2) | PTE_VRWXAD | PTE_CW | PTE_CR)
    sd t1, 32(t0)                               /* VPN2 4: CD = 0 */
    srli t0, t0, 12
    li t1, 8 << 60
    or t0, t0, t1
    csrw satp, t0
    sfence.vma

    cspecialr x20, x1                           /* c20 = DDC (tagged) */
    li s10, -1

    li t0, 1 << 11                              /* MPP = S */
    csrw mstatus, t0
    la t0, smode
    csrw mepc, t0
    mret

smode:
    la s0, buf                                  /* VA 0x80000000 + off */
    li t0, 0x40000000
    add s1, s0, t0                              /* alias, CR = 0 */
    add s2, s1, t0                              /* alias, CD = 0 */
    sc_ddc x20, s0

    /* 1: plain load fills the TLB, then a capability load drops the tag */
    ld t0, 0(s1)
    lc_ddc x3, s1
    cgettag a4, x3
    expect a4, 0, 1

    /* 2: plain load fills the TLB, then a tagged store must set CD */
    ld t0, 16(s2)
    addi t1, s2, 16
    li s10, 27
    la s11, check2
    sc_ddc x20, t1
check2:
    li s10, -1
    la t0, root
    ld t0, 32(t0)
    srli t0, t0, 61
    andi t0, t0, 1
    beqz t0, cd_clear
    pass
cd_clear:
    /* No CD update is fine only if the store trapped (s11 path, s9 set) */
    expect s9, 1, 2
    pass

    .align 2
trap:
    csrr t0, mcause
    bne t0, s10, unexpected
    li s9, 1
    csrw mepc, s11
    mret
unexpected:
    fail 99

    .data
    .align 12
root: .zero 4096
    .align 4
buf: .zero 32
