# Writing mccsr or uccsr raised an instruction access fault; the registers
# only have read-only feature bits and writes are ignored.
# Found by TestRIG (csr template).
#>QCVENGINE_TEST_V2.0
.4byte 0xbc0de1f3 # csrrsi x3, mccsr (0xbc0), 27
.4byte 0xbc0021f3 # csrrs x3, mccsr (0xbc0), x0
.4byte 0x8c0191f3 # csrrw x3, uccsr (0x8c0), x3
.4byte 0x8c0021f3 # csrrs x3, uccsr (0x8c0), x0
# Test end
