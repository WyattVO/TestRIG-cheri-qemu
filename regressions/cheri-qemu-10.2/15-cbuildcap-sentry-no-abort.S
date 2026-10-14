#>QCVENGINE_TEST_V2.0
# cbuildcap of an untagged sentry pattern whose rederivation from the
# authority loses its tag: QEMU asserted in cap_make_sealed_entry().
.4byte 0x400040b7 # lui x1, 262148
.4byte 0x00109093 # slli x1, x1, 1
.4byte 0xd5120137 # lui x2, 872736
.4byte 0x46d10113 # addi x2, x2, 1133
.4byte 0x0020a023 # sw x2, x1[0]
.4byte 0xe73e6137 # lui x2, 947174
.4byte 0x09710113 # addi x2, x2, 151
.4byte 0x0020a223 # sw x2, x1[4]
.4byte 0x09b87137 # lui x2, 39815
.4byte 0x44510113 # addi x2, x2, 1093
.4byte 0x0020a423 # sw x2, x1[8]
.4byte 0xf14d2137 # lui x2, 988370
.4byte 0x0020a623 # sw x2, x1[12]
.4byte 0x0000a10f # lq x2, x1[0]
.4byte 0x3a21815b # cbuildcap x2, x3, x2
.4byte 0xfe11025b # cgettype x4, x2
.4byte 0xfe4102db # cgettag x5, x2
# Test end
