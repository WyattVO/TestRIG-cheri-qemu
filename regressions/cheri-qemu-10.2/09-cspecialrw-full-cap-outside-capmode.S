#>QCVENGINE_TEST_V2.0
.4byte 0x03c000db # cspecialrw x1, mtcc (28), x0  (read outside capability mode)
.4byte 0xfe40815b # cgettag x2, x1                  (Sail v9: full capability, tag 1)
# Test end
