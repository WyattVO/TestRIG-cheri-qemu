#>QCVENGINE_TEST_V2.0
# fpclear q, m (CHERI v9) zeroes FP register 8*q+i for each set bit i of m
# when the FPU is enabled. QEMU had it commented out of its v9 decoder and
# raised an illegal instruction (CHERI-Alliance QEMU still does); implemented
# 2026-10-22. TestRIG cannot compare FP register values, so this only checks
# that fpclear no longer traps; qemu-only/fpclear-registers.S checks the
# values and the mstatus.FS rules.
#>START_SHRINK_SCOPE
#>START_NO_SHRINK
.4byte 0x000020b7 # lui x1, 2
.4byte 0x3000a073 # csrrs x0, mstatus (0x300), x1
.4byte 0x00302073 # csrrs x0, fcsr (0x3), x0
.4byte 0xf0000053 # fmv.w.x f0, x0
.4byte 0xf00000d3 # fmv.w.x f1, x0
.4byte 0xf0000153 # fmv.w.x f2, x0
.4byte 0xf00001d3 # fmv.w.x f3, x0
.4byte 0xf0000253 # fmv.w.x f4, x0
.4byte 0xf2000853 # fmv.d.x f16, x0
.4byte 0xf20008d3 # fmv.d.x f17, x0
.4byte 0xf2000953 # fmv.d.x f18, x0
.4byte 0xf20009d3 # fmv.d.x f19, x0
.4byte 0xf2000a53 # fmv.d.x f20, x0
#>END_NO_SHRINK
.4byte 0xff0f0edb # fpclear 221, 3
#>END_SHRINK_SCOPE
