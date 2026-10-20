# QEMU_CPU: rv64,zicbom=true
# Bounds checks of the Zicbom cache-block operations (riscv-cheri spec,
# src/cheri/insns/cbo_exceptions.adoc):
#  - cbo.clean and cbo.flush only need one byte of the 64-byte block inside
#    the authorizing capability's bounds (they neither reveal nor change
#    data);
#  - cbo.inval destroys the block's contents, which can re-expose older data
#    and capabilities, so every byte of the block must be in bounds.
# With DDC = [blk + 8, blk + 16), the block at blk is only partly covered:
#  1: cbo.clean and cbo.flush on it are allowed;
#  2: cbo.inval on it raises a CHERI length violation (mtval 0x421);
#  3: with DDC = [blk, blk + 64), cbo.inval on it is allowed.
#include "cheri-v9.h"
    .option arch, +zicbom
    test_start

    la t0, expected_trap
    csrw mtvec, t0
    cspecialr x20, x1                   /* c20 = full DDC */
    la s0, blk
    addi s1, s0, 8

    /* DDC = [blk + 8, blk + 16) */
    .macro small_ddc
    csetaddr x21, x20, s1
    li t0, 8
    csetbounds x21, x21, t0
    cspecialw x1, x21
    .endm

    check 1
    small_ddc
    cbo.clean (s1)
    cbo.flush (s1)
    cspecialw x1, x20

    check 2
    small_ddc
    trap_expect CAUSE_CHERI, TVAL_DDC_LENGTH, 4f
    cbo.inval (s1)
    fail 2
4:
    check 3
    csetaddr x21, x20, s0
    li t0, 64
    csetbounds x21, x21, t0
    cspecialw x1, x21
    cbo.inval (s0)
    cspecialw x1, x20
    pass

    expected_trap_handler

    .data
    .align 6
blk: .zero 64
