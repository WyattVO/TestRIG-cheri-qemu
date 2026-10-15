#>QCVENGINE_TEST_V2.0
.4byte 0x400042b7 # lui x5, 262148
.4byte 0x00129293 # slli x5, x5, 1
.4byte 0x0052b023 # sd x5, 0(x5)
.4byte 0x0002b283 # ld x5, 0(x5)
# Test end
