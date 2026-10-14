# Under RVFI-DII QEMU reported the virtual address of a load/store through a
# page table, the Sail model the physical one. Sv39 gigapage VA 0 -> PA
# 0x80000000, then a U-mode store and load. Found by TestRIG (pte template).
#>QCVENGINE_TEST_V2.0
#>START_NO_SHRINK
.4byte 0x400f0f13 # addi x30, x30, 1024
.4byte 0x00bf1f13 # slli x30, x30, 11
.4byte 0x008f1f13 # slli x30, x30, 8
.4byte 0x021f0f13 # addi x30, x30, 33  (non-leaf PTE: G, V)
.4byte 0x00208093 # addi x1, x1, 2
.4byte 0x00b09093 # slli x1, x1, 11
.4byte 0x00708093 # addi x1, x1, 7
.4byte 0x00b09093 # slli x1, x1, 11
.4byte 0x7f008093 # addi x1, x1, 2032
.4byte 0x00809093 # slli x1, x1, 8
.4byte 0x01e0b023 # sd x30, 0(x1)
.4byte 0x40000f13 # addi x30, x0, 1024
.4byte 0x00bf1f13 # slli x30, x30, 11
.4byte 0x008f1f13 # slli x30, x30, 8
.4byte 0x0fff0f13 # addi x30, x30, 255
.4byte 0x00200093 # addi x1, x0, 2
.4byte 0x00b09093 # slli x1, x1, 11
.4byte 0x00b09093 # slli x1, x1, 11
.4byte 0x00809093 # slli x1, x1, 8
.4byte 0x01e0b023 # sd x30, 0(x1)
.4byte 0x80000f13 # addi x30, x0, -2048
.4byte 0x00bf1f13 # slli x30, x30, 11
.4byte 0x00bf1f13 # slli x30, x30, 11
.4byte 0x00bf1f13 # slli x30, x30, 11
.4byte 0x001f0f13 # addi x30, x30, 1
.4byte 0x00bf1f13 # slli x30, x30, 11
.4byte 0x003f0f13 # addi x30, x30, 3
.4byte 0x008f1f13 # slli x30, x30, 8
.4byte 0x0fff0f13 # addi x30, x30, 255
.4byte 0x180f1073 # csrrw x0, satp (0x180), x30
.4byte 0x12000073 # sfence.vma 0, 0
.4byte 0x10200073 # sret
.4byte 0x01e13023 # sd x30, 0(x2)
.4byte 0x01013f03 # ld x30, 16(x2)
.4byte 0x00000073 # ecall
.4byte 0x342020f3 # csrrs x1, mcause (0x342), x0
#>END_NO_SHRINK
# Test end
