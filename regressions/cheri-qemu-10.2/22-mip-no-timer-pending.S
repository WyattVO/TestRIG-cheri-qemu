# QEMU's ACLINT left MTIMECMP at 0 after each RVFI-DII reset, so mip.MTIP
# (bit 7) read as 1 while the Sail model reports no pending interrupt.
# Found by a write-form probe of every CSR.
#>QCVENGINE_TEST_V2.0
.4byte 0x344532f3 # csrrc x5, mip (0x344), x10
.4byte 0x344022f3 # csrrs x5, mip (0x344), x0
.4byte 0x144022f3 # csrrs x5, sip (0x144), x0
# Test end
