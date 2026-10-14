#>QCVENGINE_TEST_V2.0
# CSR 0x416 is the standard's ddc CSR. In v9 DDC is only reachable with
# cspecialrw, so a CSR instruction naming it is an illegal instruction.
.4byte 0x4160b973 # csrrc x18, 0x416, x1
.4byte 0x342020f3 # csrrs x1, mcause (0x342), x0
.4byte 0x343020f3 # csrrs x1, mtval (0x343), x0
.4byte 0xa80a50f3 # csrrwi x1, 0xa80 (vstid), 20  (xTIDC are SCRs in v9, not CSRs)
.4byte 0x342020f3 # csrrs x1, mcause (0x342), x0
# Test end
