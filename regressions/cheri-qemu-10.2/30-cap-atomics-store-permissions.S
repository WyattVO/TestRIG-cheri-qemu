#>QCVENGINE_TEST_V2.0
# Capability atomics (sc.c, amoswap.c) need StoreCap and StoreLocalCap in
# their authority only when the stored value is tagged (as for csc), and a
# StoreLocalCap violation names the authority, not the stored register.
# QEMU required StoreCap even for untagged values (sc.c and amoswap.c of an
# integer faulted) and reported the value register for StoreLocalCap.
# amoswap.c also needs Load permission (it returns the old value).
.4byte 0x00100093 # addi x1, x0, 1
.4byte 0x01f09093 # slli x1, x1, 31
.4byte 0x10008093 # addi x1, x1, 0x100          (x1 = 0x80000100)
.4byte 0x0210015b # cspecialrw x2, ddc, x0      (c2 = DDC, tagged, global)
.4byte 0xfdf00293 # addi x5, x0, -33            (~StoreCap)
.4byte 0x1a5101db # candperm x3, x2, x5
.4byte 0x0211805b # cspecialrw x0, ddc, x3      (DDC without StoreCap)
.4byte 0x1000c32f # lr.c c6, (x1)
.4byte 0x1800c3af # sc.c x7, c0, (x1)           (untagged value: succeeds, rd = 0)
.4byte 0x0800c42f # amoswap.c c8, c0, (x1)      (untagged value: allowed)
.4byte 0x1000c32f # lr.c c6, (x1)
.4byte 0x1820c3af # sc.c x7, c2, (x1)           (tagged value: PermitStoreCap)
.4byte 0x342024f3 # csrrs x9, mcause, x0        (0x1c)
.4byte 0x343024f3 # csrrs x9, mtval, x0         (0x435: DDC, PermitStoreCap)
.4byte 0xffb00293 # addi x5, x0, -5             (~Load)
.4byte 0x1a5101db # candperm x3, x2, x5
.4byte 0x0211805b # cspecialrw x0, ddc, x3      (DDC without Load)
.4byte 0x0820c42f # amoswap.c c8, c2, (x1)      (PermitLoad)
.4byte 0x342024f3 # csrrs x9, mcause, x0
.4byte 0x343024f3 # csrrs x9, mtval, x0         (0x432)
.4byte 0xffe00293 # addi x5, x0, -2             (~Global)
.4byte 0x1a51055b # candperm x10, x2, x5        (c10 = local capability)
.4byte 0xfbf00293 # addi x5, x0, -65            (~StoreLocalCap)
.4byte 0x1a5101db # candperm x3, x2, x5
.4byte 0x0211805b # cspecialrw x0, ddc, x3      (DDC without StoreLocalCap)
.4byte 0x1000c32f # lr.c c6, (x1)
.4byte 0x18a0c3af # sc.c x7, c10, (x1)          (local value: PermitStoreLocalCap)
.4byte 0x342024f3 # csrrs x9, mcause, x0
.4byte 0x343024f3 # csrrs x9, mtval, x0         (0x436: DDC, not c10)
.4byte 0x08a0c42f # amoswap.c c8, c10, (x1)     (same)
.4byte 0x343024f3 # csrrs x9, mtval, x0
.4byte 0x0820c42f # amoswap.c c8, c2, (x1)      (global value: allowed)
# Test end
