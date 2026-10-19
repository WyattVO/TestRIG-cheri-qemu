#>QCVENGINE_TEST_V2.0
# The CHERI check of a store-conditional comes before the reservation check:
# an SC without a reservation to an address outside DDC must raise a CHERI
# length fault (mtval 0x421), not fail quietly and not take an access fault
# from probing memory. QEMU 11 adds a write probe for failed SCs
# (d107b74807 "Generate access fault if sc comparison fails"); it must run
# after, and be authorized by, the CHERI check. In-bounds SCs without a
# reservation still just fail (rd = 1) and a reserved one succeeds.
.4byte 0x00100093 # addi x1, x0, 1
.4byte 0x01f09093 # slli x1, x1, 31             (x1 = 0x80000000)
.4byte 0x0210015b # cspecialrw x2, ddc, x0      (c2 = DDC)
.4byte 0x201101db # csetaddr x3, x2, x1
.4byte 0x00100293 # addi x5, x0, 1
.4byte 0x00c29293 # slli x5, x5, 12
.4byte 0x105181db # csetbounds x3, x3, x5       (c3 = [0x80000000, +4 KiB))
.4byte 0x0211805b # cspecialrw x0, ddc, x3      (DDC = c3)
.4byte 0x01000313 # addi x6, x0, 16             (outside DDC, unmapped)
.4byte 0x180323af # sc.w x7, x0, (x6)           (CHERI length fault)
.4byte 0x34202473 # csrrs x8, mcause, x0        (0x1c)
.4byte 0x34302473 # csrrs x8, mtval, x0         (0x421)
.4byte 0x1800b3af # sc.d x7, x0, (x1)           (no reservation: rd = 1)
.4byte 0x1000a4af # lr.w x9, (x1)
.4byte 0x1800a3af # sc.w x7, x0, (x1)           (reserved: rd = 0)
.4byte 0x080323af # amoswap.w x7, x0, (x6)      (CHERI length fault)
.4byte 0x34202473 # csrrs x8, mcause, x0
.4byte 0x34302473 # csrrs x8, mtval, x0
# Test end
