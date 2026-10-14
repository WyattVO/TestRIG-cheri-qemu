#>QCVENGINE_TEST_V2.0
# CCSeal must pass an already sealed cs (here an untagged sentry made from
# NULL) through unchanged before looking at its tag (Sail CHERI-RISC-V v9).
.4byte 0xff100a5b # csealentry x20, x0
.4byte 0x3e4a00db # ccseal x1, x20, x4
.4byte 0xff708a5b # cgethigh x20, x1
# Test end
