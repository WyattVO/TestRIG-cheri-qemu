#>QCVENGINE_TEST_V2.0
# Stores from AMOs and successful store-conditionals must clear the tag of a
# capability they overwrite. The QEMU 10.2 port lost this for LR/SC (the
# cmpxchg expansion), so a partially overwritten capability stayed tagged.
# Needs the A extension (gate ARCH includes it).
.4byte 0x400040b7 # lui x1, 262148
.4byte 0x00109093 # slli x1, x1, 1          (x1 = 0x80008000)
.4byte 0x0210015b # cspecialrw x2, ddc, x0  (c2 = DDC, tagged)
.4byte 0x0020c023 # sq x2, 0(x1)            (store a valid capability)
.4byte 0x0000a1af # amoadd.w x3, x0, (x1)   (AMO store into it)
.4byte 0x0000a20f # lq x4, 0(x1)
.4byte 0xfe4202db # cgettag x5, x4          (must be 0)
.4byte 0x0020c023 # sq x2, 0(x1)
.4byte 0x1000a32f # lr.w x6, (x1)
.4byte 0x1800a3af # sc.w x7, x0, (x1)       (successful SC into it)
.4byte 0x0000a20f # lq x4, 0(x1)
.4byte 0xfe4202db # cgettag x5, x4          (must be 0)
# Test end
