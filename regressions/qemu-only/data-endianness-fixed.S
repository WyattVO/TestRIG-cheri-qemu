# QEMU_CPU: rv64
# Capabilities have one in-memory format (little-endian, with the tag kept
# beside the 16 bytes), so a CHERI hart must stay little-endian: the
# mstatus MBE (37), SBE (36) and UBE (6) bits must stay 0 and data accesses
# must stay little-endian.
# QEMU 11 implements these bits (56db2b7eac "Implement runtime data
# endianness via MSTATUS bits", plus a "big-endian" CPU property); the rebase
# must keep them read-only on CHERI CPUs (the gate's policy stage also checks
# that big-endian=true is not accepted).
#include "cheri-v9.h"
    test_start

#define MSTATUS_BE ((1 << 37) | (1 << 36) | (1 << 6))
    li t0, MSTATUS_BE
    csrs mstatus, t0
    csrr t1, mstatus
    and t1, t1, t0
    expect t1, 0, 1

    li t0, 1 << 6                       /* sstatus.UBE */
    csrs sstatus, t0
    csrr t1, sstatus
    and t1, t1, t0
    expect t1, 0, 2

    la s0, buf
    li t0, 0x0102030405060708
    sd t0, 0(s0)
    lbu t1, 0(s0)
    expect t1, 0x08, 3

    /* A capability round-trips with its tag and address. */
    cspecialr x20, x1
    sc_ddc x20, s0
    lc_ddc x3, s0
    cgettag a4, x3
    expect a4, 1, 4
    pass

    .data
    .align 4
buf: .zero 16
