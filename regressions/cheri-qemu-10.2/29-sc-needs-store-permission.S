#>QCVENGINE_TEST_V2.0
# A store-conditional is a store: its authority (DDC here, the capability in
# capability mode) needs Store permission. QEMU checked SC addresses with the
# load check (get_capmode_dependent_load_addr in trans_rva.c.inc), so with a
# DDC that has Load but not Store permission a reserved sc.w/sc.d succeeded
# and wrote memory. Sail raises a CHERI PermitStore fault (mcause 0x1c, mtval
# 0x433 = DDC, cause 0x13). Same code in CHERI-QEMU 7.1. The explicit
# sc.*.ddc/.cap forms (not in Sail) are checked by qemu-only/sc-store-permission.S.
.4byte 0x00100093 # addi x1, x0, 1
.4byte 0x01f09093 # slli x1, x1, 31
.4byte 0x10008093 # addi x1, x1, 0x100          (x1 = 0x80000100)
.4byte 0xf9700293 # addi x5, x0, -105           (~(Store|StoreCap|StoreLocalCap))
.4byte 0x0210015b # cspecialrw x2, ddc, x0      (c2 = DDC)
.4byte 0x1a5101db # candperm x3, x2, x5         (c3 = DDC without store permissions)
.4byte 0x0211805b # cspecialrw x0, ddc, x3      (DDC = c3)
.4byte 0x1000a32f # lr.w x6, (x1)               (allowed: DDC has Load)
.4byte 0x1800a3af # sc.w x7, x0, (x1)           (must raise a PermitStore CHERI fault)
.4byte 0x34202473 # csrrs x8, mcause, x0
.4byte 0x34302473 # csrrs x8, mtval, x0
.4byte 0x1000b32f # lr.d x6, (x1)
.4byte 0x1800b3af # sc.d x7, x0, (x1)
.4byte 0x34202473 # csrrs x8, mcause, x0
# Test end
