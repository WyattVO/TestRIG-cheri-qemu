#>QCVENGINE_TEST_V2.0
# QEMU uses load_res == -1 for "no reservation". A byte SC to the last byte of
# the address space is aligned, matched that value, and so accessed memory
# (load access fault) instead of failing. It must fail (rd = 1). Then an
# LR.B/SC.B pair in RAM must still succeed (rd = 0).
# Found by TestRIG (unstructured).
.4byte 0xfff00a13 # addi x20, x0, -1
.4byte 0x196a0daf # sc.b x27, x22, (x20)
.4byte 0x342020f3 # csrrs x1, mcause, x0
.4byte 0x343020f3 # csrrs x1, mtval, x0
.4byte 0x00100a13 # addi x20, x0, 1
.4byte 0x01fa1a13 # slli x20, x20, 31
.4byte 0x100a0a13 # addi x20, x20, 0x100
.4byte 0x100a02af # lr.b x5, (x20)
.4byte 0x196a0daf # sc.b x27, x22, (x20)
# Test end
