#>QCVENGINE_TEST_V2.0
.4byte 0x40004837 # lui x16, 262148
.4byte 0x00181813 # slli x16, x16, 1
.4byte 0x004820a3 # sw x4, x16[1]
.4byte 0x002800a3 # sb x2, x16[1]
.4byte 0x01489123 # sh x20, x17[2]
# Test end
