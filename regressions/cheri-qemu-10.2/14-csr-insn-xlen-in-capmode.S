#>QCVENGINE_TEST_V2.0
# In capability mode a CSR instruction on an extended register (mepc)
# returned the full mepcc capability; v9 CSR instructions only see the address.
.4byte 0x00100d93 # addi x27, x0, 1
.4byte 0x1dbd0d5b # csetflags x26, x26, x27
.4byte 0xfecd005b # jalr_cap x0, x26
.4byte 0x3419b873 # csrrc x16, mepc (0x341), x19
.4byte 0xfe48085b # cgettag x16, x16
# Test end
