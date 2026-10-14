# Under RVFI-DII QEMU gave every instruction fetch a fake 1:1 mapping, so
# it never took an instruction page or access fault. Here U-mode runs at
# VA 0 with Sv39 and a root page table at PA 0 (outside RAM): the walk must
# raise an instruction access fault. Found by TestRIG (pte template).
#>QCVENGINE_TEST_V2.0
#>START_NO_SHRINK
.4byte 0x00100293 # addi x5, x0, 1
.4byte 0x01f29293 # slli x5, x5, 31
.4byte 0x01f29293 # slli x5, x5, 31
.4byte 0x00129293 # slli x5, x5, 1
.4byte 0x18029073 # csrrw x0, satp (0x180), x5
.4byte 0x12000073 # sfence.vma 0, 0
.4byte 0x10200073 # sret
.4byte 0x00018193 # addi x3, x3, 0
.4byte 0x342020f3 # csrrs x1, mcause (0x342), x0
.4byte 0x343020f3 # csrrs x1, mtval (0x343), x0
#>END_NO_SHRINK
# Test end
