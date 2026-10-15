#>QCVENGINE_TEST_V2.0
.4byte 0x020100db # cspecialrw x1, pcc, x2
.4byte 0x342020f3 # csrrs x1, mcause (0x342), x0
.4byte 0x343020f3 # csrrs x1, mtval (0x343), x0
# Test end
