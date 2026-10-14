#>QCVENGINE_TEST_V2.0
.4byte 0x021000db # cspecialrw x1, ddc (1), x0      (c1 = DDC, tagged)
.4byte 0x0210015b # cspecialrw x2, ddc (1), x0      (c2 = DDC, tagged)
.4byte 0xfee0035b # cclear 0, 0x06                  (clear c1 and c2)
.4byte 0xfe4081db # cgettag x3, x1
.4byte 0xfe41025b # cgettag x4, x2
.4byte 0xfee000db # cclear 0, 0x01                  (bit 0 of quarter 0 is DDC)
.4byte 0x021002db # cspecialrw x5, ddc (1), x0
.4byte 0xfe42835b # cgettag x6, x5                  (DDC is now NULL: tag 0)
# Test end
