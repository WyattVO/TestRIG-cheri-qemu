# QEMU_CPU: rv64
# A CHERI build has a fixed (RV64) capability format, so mstatus.UXL and
# sstatus.UXL must stay RV64 (2): M-mode could set RV32 or the reserved
# value 3.
#include "cheri-v9.h"
    test_start
#define UXL_SHIFT 32
    .macro try_uxl csr, v, n
    li t0, 3 << UXL_SHIFT
    csrc \csr, t0
    li t0, \v << UXL_SHIFT
    csrs \csr, t0
    csrr t0, \csr
    srli t0, t0, UXL_SHIFT
    andi t0, t0, 3
    expect t0, 2, \n
    .endm
    try_uxl mstatus, 1, 1
    try_uxl mstatus, 3, 2
    try_uxl sstatus, 1, 3
    try_uxl sstatus, 3, 4
    pass
