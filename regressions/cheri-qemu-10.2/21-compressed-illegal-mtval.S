#>QCVENGINE_TEST_V2.0
# An illegal compressed instruction (c.fsdsp without F/D) must report only its
# 16 bits in mtval; QEMU reported the whole injected 32-bit word.
.4byte 0x19bea2ca # low half 0xa2ca is c.fsdsp
.4byte 0x343e32f3 # csrrc x5, mtval (0x343), x28
.4byte 0x342020f3 # csrrs x1, mcause (0x342), x0
# Test end
