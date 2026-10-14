#>QCVENGINE_TEST_V2.0
.4byte 0x400040b7 # lui x1, 262148
.4byte 0x00109093 # slli x1, x1, 1
.4byte 0x4c910113 # addi x2, x2, 1225
.4byte 0x0020a623 # sw x2, x1[12]                   (otype bits in the stored pattern)
.4byte 0x0000a10f # lq x2, x1[0]                    (untagged, sealed bit pattern)
.4byte 0x3a21815b # cbuildcap x2, x3, x2            (Sail v9: unsealed and tagged)
.4byte 0xfe4102db # cgettag x5, x2
# Test end
