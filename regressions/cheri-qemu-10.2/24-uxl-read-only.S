# mstatus.UXL and sstatus.UXL were writable (RV32 or the reserved value 3),
# which is invalid with the fixed RV64 capability format; they are read-only.
# Found by TestRIG (csr template).
#>QCVENGINE_TEST_V2.0
.4byte 0x00100293 # addi x5, x0, 1
.4byte 0x02029293 # slli x5, x5, 32
.4byte 0x3002a073 # csrrs x0, mstatus, x5
.4byte 0x30002373 # csrrs x6, mstatus, x0
.4byte 0x1002a073 # csrrs x0, sstatus, x5
.4byte 0x10002373 # csrrs x6, sstatus, x0
# Test end
