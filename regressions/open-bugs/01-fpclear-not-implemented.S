# fpclear (CHERI v9, 0x7f/0x10 in the Xcheri quadrant) is not implemented:
# it is commented out of target/riscv/insn32-cheri-v9.decode, so QEMU raises
# an illegal instruction where the Sail model clears the selected FP
# registers. CHERI-Alliance QEMU (7.2) has the same gap (three-way vote:
# both QEMUs differ from Sail). cclear had the same history (trace 11).
# The fpclear template only noticed once it enabled the FPU (mstatus.FS);
# the gate skips that template until this is fixed (EXCLUDE default).
#>QCVENGINE_TEST_V2.0
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
