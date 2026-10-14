#>QCVENGINE_TEST_V2.0
.4byte 0xffd00913 # addi x18, x0, -3
.4byte 0x00493023 # sd x4, x18[0]                   (8 bytes from 2^64-3 wrap past DDC top)
.4byte 0x34202a73 # csrrs x20, mcause (0x342), x0   (Sail: CHERI exception 0x1c)
.4byte 0x342020f3 # csrrs x1, mcause (0x342), x0
.4byte 0x343020f3 # csrrs x1, mtval (0x343), x0     (0x421: DDC length violation)
.4byte 0xbc0020f3 # csrrs x1, mccsr (0xbc0), x0
# Test end
