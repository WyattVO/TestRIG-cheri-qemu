#>QCVENGINE_TEST_V2.0
# CGetTop (Sail since 2022) was missing from QEMU, which raised an illegal
# instruction. Read the top of the null capability (2^64, saturated to
# 2^64-1) and of a capability bounded to [0x100, 0x140).
# Found by TestRIG (unstructured).
.4byte 0xff8000db # cgettop x1, c0
.4byte 0x0210015b # cspecialrw c2, ddc, c0
.4byte 0x1001115b # cincoffsetimm c2, c2, 0x100
.4byte 0x0401215b # csetboundsimm c2, c2, 0x40
.4byte 0xff8101db # cgettop x3, c2
# Test end
