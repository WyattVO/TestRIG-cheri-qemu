// riscv-arch-test model for QEMU's virt machine (-bios none -kernel test.elf).
// The test runs in M-mode from 0x80000000. RVMODEL_HALT prints the signature
// as one 32-bit hex word per line on the NS16550 UART, then exits QEMU
// through the SiFive test device. upstream-diff.py compares these signatures
// (and execlog traces) between upstream QEMU and the CHERI port.
#ifndef _MODEL_TEST_H
#define _MODEL_TEST_H

#define RVMODEL_UART_THR   0x10000000
#define RVMODEL_TEST_EXIT  0x100000

#define RVMODEL_DATA_SECTION \
  .pushsection .tohost,"aw",@progbits; \
  .align 8; .global tohost; tohost: .dword 0; \
  .align 8; .global fromhost; fromhost: .dword 0; \
  .popsection;

#define RVMODEL_BOOT

#define RVMODEL_HALT \
  la t0, begin_signature; \
  la t1, end_signature; \
  li t2, RVMODEL_UART_THR; \
1: bgeu t0, t1, 4f; \
  lw t3, 0(t0); \
  li t4, 28; \
2: srl t5, t3, t4; \
  andi t5, t5, 0xf; \
  li t6, 10; \
  blt t5, t6, 3f; \
  addi t5, t5, 'a' - '0' - 10; \
3: addi t5, t5, '0'; \
  sb t5, 0(t2); \
  addi t4, t4, -4; \
  bgez t4, 2b; \
  li t5, '\n'; \
  sb t5, 0(t2); \
  addi t0, t0, 4; \
  j 1b; \
4: li t0, RVMODEL_TEST_EXIT; \
  li t1, 0x5555; \
  sw t1, 0(t0); \
5: j 5b;

#define RVMODEL_DATA_BEGIN \
  RVMODEL_DATA_SECTION \
  .align 4; .global begin_signature; begin_signature:

#define RVMODEL_DATA_END \
  .align 4; .global end_signature; end_signature:

#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_R, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)

#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLEAR_MSW_INT
#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT

#define RVMODEL_CBZ_BLOCKSIZE 64
#define RVMODEL_CMO_BLOCKSIZE 64

#endif
