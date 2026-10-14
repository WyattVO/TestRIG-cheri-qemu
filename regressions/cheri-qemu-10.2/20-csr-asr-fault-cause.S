#>QCVENGINE_TEST_V2.0
# A CSR instruction executed without Access_System_Registers in PCC (here in a
# trap handler whose PCC lacks ASR) must raise a CHERI ASR violation on PCC.
# QEMU 10.2's riscv_csrr()/riscv_csrrw() returned RISCV_EXCP_CHERI without
# recording the CHERI cause, so the trap used stale state and could abort QEMU.
.4byte 0xbff00193 # addi x3, x0, -1025              (all permissions except ASR)
.4byte 0x1a3888db # candperm x17, x17, x3
.4byte 0x03c8805b # cspecialrw x0, mtcc, x17        (trap vector without ASR)
.4byte 0xfec008db # jalr_cap x17, x0                (fault -> handler)
.4byte 0x342020f3 # csrrs x1, mcause (0x342), x0    (no ASR -> CHERI fault)
.4byte 0x342020f3 # csrrs x1, mcause (0x342), x0
# Test end
