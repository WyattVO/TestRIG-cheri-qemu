#>QCVENGINE_TEST_V2.0
# CCopyType with an unsealed (reserved otype) cs2 must give an untagged result.
# With cd == cs1 QEMU updated the register in place and dropped the cleared tag.
.4byte 0x3d4181db # ccopytype x3, x3, x20
.4byte 0xfe4181db # cgettag x3, x3
# Test end
