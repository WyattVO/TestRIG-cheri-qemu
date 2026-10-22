# CHERI-QEMU 10.2 test bench

TestRIG answers one question: does QEMU do what the Sail CHERI-RISC-V model
does? That leaves three kinds of bug it cannot see:

1. **Features Sail does not model**: newer extensions (Zcb, Zfh, Zacas,
   Zabha, Zicbo*, Zicond, Sstc, T-Head, ...), interrupts, devices and DMA,
   SMP, PMP, and QEMU's own machinery (TLB flags, translation cache).
2. **Bugs where Sail and QEMU agree, or where Sail has no opinion**: the
   `cbo.inval` bounds bug was invisible to TestRIG because Sail has no
   Zicbom.
3. **System-level CHERI properties**: "a device write clears tags", "a CHERI
   fault in user mode reaches the kernel", "tags stay consistent between
   harts".

The test bench is the second oracle: self-checking bare-metal programs whose
expected results come from the specifications (CHERI ISA v9, riscv-cheri,
the RISC-V ISA manuals), not from QEMU's code. That matters most when code
is written or ported by an AI: plausible code that compiles but gets a corner
wrong is exactly what an independent, spec-derived check catches.

Gate stage 3 runs the bench (`utils/scripts/qemu-only-tests.sh`); each test
is in `regressions/qemu-only/` and starts with a comment explaining every
numbered check. Sail-compared traces (stage 2) and random tests (stage 4)
cover the base CHERI ISA; CheriBSD (stage 5) covers the whole system.

## Oracles: what each stage compares against

No single reference is right about everything, so each one judges what it
is good at:

| Oracle | Judges | Stage | Blind spots |
|---|---|---|---|
| Sail CHERI-RISC-V model (CHERI v9) | every base CHERI instruction, through RVFI-DII | 2, 4 | features it lacks (above); its own bugs (`LoadResCapCap`, the reservation it kept across test resets) |
| CHERI-Alliance QEMU (`main`, QEMU 7.2) | second opinion on the same random tests: a disagreement replayed on Sail says which QEMU is the odd one out | 4b | shares CHERI-QEMU's history (it has traces 28/29's bugs and lacks `fpclear`), no Zacas/Zabha; never the referee |
| This bench (specifications) | features Sail lacks, system properties | 3 | only what a test was written for |
| Upstream QEMU v10.2.0 | non-CHERI behaviour: a CHERI CPU outside capability mode must run plain RISC-V exactly as upstream does (riscv-arch-test signatures and instruction traces; upstream's own check-tcg and qtests) | 6 | upstream's own bugs (`amocas` with rd = x0); nothing about CHERI |
| CheriBSD `cheribsdtest` | the whole system | 5 | slow; finds, does not locate |

A disagreement is only a bug once the spec says who is right: all three
first differences the three-way vote found (2026-10-22) were "both QEMUs
differ from Sail", and the answers were a missing QEMU instruction
(`fpclear`), a Sail bug (`lr.c.cap`) and a difference the RISC-V spec allows
(SC after an LR of another width). The upstream diff's only real difference
was an upstream bug.

## Coverage by feature

| Area | Feature | Tests | Bad behaviour it catches |
|---|---|---|---|
| Tags | Ordinary stores clear tags | `tag-clear-store-widths` | a store width, FP or compressed store, or a misaligned split that leaves a tag on non-capability bytes |
| Tags | Device / DMA writes clear tags | `dma-clears-tags` (address_space_write), `virtio-dma-clears-tags` (map/unmap, as virtio disks and network) | a device-written buffer keeping a tag (forged capability) |
| Tags | Atomics and CAS clear tags | `amocas-q-clears-tag`, `amocas-wdb-clears-tag`, `ext-mem-insns-*`, trace 17 | `amocas`, Zabha, SC overwriting a capability without clearing its tag |
| 10.2 extensions | `amocas` with rd = x0 | `amocas-rd-x0` | the old memory value leaking into later uses of x0 (upstream QEMU bug; the port's CHERI cmpxchg avoided it by luck, fixed properly 2026-10-22) |
| Tags | Cache-block zero | `cbo-zero-cheri` | `cbo.zero` keeping tags |
| Tags | Two harts | `smp-tag-consistency` | a torn capability (tag on another hart's plain data) |
| Permissions | Store-conditional needs Store | `sc-store-permission`, traces 29, 30 | SC/`sc.c`/`amoswap.c` checking the wrong permission |
| Permissions | DDC and capability authority for extension instructions | `ext-mem-insns-cheri`, `ext-mem-insns-capmode`, `xthead-mem-cheri`, `cbo-zero-cheri`, `cbo-inval-bounds` | an extension's load/store bypassing bounds or Store permission, in integer or capability mode |
| Permissions | ASR | `asr-permission`, trace 20 | privileged CSRs/SCRs, `mret`, `cbo.inval` usable without ASR |
| Control flow | PCC bounds and translation cache | `pcc-bounds-cached-tb` | code running past PCC bounds because a cached translation was reused |
| Traps | Interrupts in capability mode | `interrupt-capmode` | MEPCC/SEPCC losing the tag, mode or bounds; xRET not restoring capability mode |
| Traps | Delegation to S-mode | `cheri-fault-delegation` | CHERI faults going to M-mode, wrong `stval`, SEPCC not the user PCC |
| MMU | CHERI PTE bits are not reserved bits | `pte-cheri-bits-not-reserved` | Svpbmt/Svnapot-style reserved-bit checks faulting normal CHERI mappings |
| MMU | CW, CR, CD, CRM, CRG enforcement | `pte-cw-capability-store`, `pte-cr-cd-tlb-flags`, `pte-crg-load-generation` | capability store/load rules ignored (CheriBSD revocation) |
| MMU | TLB flushes of CHERI bits | `pte-cheri-bits-flush`, `pte-cr-cd-tlb-flags` | stale CHERI bits after `sfence.vma`/Svinval |
| MMU | PTE updates honour PMP | `pte-cd-update-pmp` (XFAIL on 10.2) | the walker setting CD through a read-only page table |
| PMP | 16-byte capability accesses | `pmp-capability-access` | half of a capability access escaping PMP |
| Config | Extension policy and review | gate stage 1, `cheri-extensions.txt` | an unreviewed or unsafe extension enabled on a CHERI CPU |
| Config | Refused extensions are really off | `disabled-ext-inert` (on `-cpu max`) | a refused extension still decoded, or its CSR bits still writable |
| Debug | Sdtrig triggers | `debug-trigger-cheri` | data triggers missing capability loads/stores; execute triggers in capability mode losing PCC |
| Config | Fixed formats | `uxl-read-only`, `data-endianness-fixed` | RV32 or big-endian state changing the capability format |
| 10.2 extensions | Functional results | `ext-functional` | a port breaking Zicond, Zfh, Zfa, Zcb, Zbkb, Zimop, Zawrs, Sstc, Zicbop, Zicntr |
| System | Whole OS | stage 5: `cheribsdtest` purecap and hybrid, `CHERIBSD_SMP=N` for SMP | anything above, end to end |

## How each test was proven to work

A test that has only ever passed proves nothing. Each bench test was run
against a QEMU where the behaviour it checks is broken, and failed:

- real bugs found by the bench failed before the fix and passed after
  (`sc-store-permission`, `cbo-inval-bounds`, trace 30, `debug-trigger-cheri`,
  `disabled-ext-inert`);
- deliberate mutations: `cbo.zero` without tag clearing, QEMU 11's
  unconditional PBMT check, the 8-bit TLB `prot` field;
- a wrong expected value in a copy of the test (e.g. `ext-functional`,
  `tag-clear-store-widths`, `dma-clears-tags`, `cheri-fault-delegation`)
  fails at exactly that check;
- `smp-tag-consistency` fails under MTTCG, where CHERI tags are known to tear;
- `amocas-rd-x0` fails on upstream QEMU 10.2, which has the bug: each of its
  five checks alone exits with its own number there.

## Writing a bench test (rules that caught real mistakes)

1. Take the expected behaviour from the specification, never from QEMU's
   source. Note the spec section in the header comment.
2. Number every check and explain it in the header; the test exits with the
   failed check's number.
3. Use `check n` / `trap_expect cause, mtval, label` / `expected_trap_handler`
   from `cheri-v9.h` for expected faults; `fail` clears the expected trap
   first, so a check whose instruction did *not* fault can never pass by
   faulting inside `fail`.
4. Prove the test can fail: run it on a QEMU with the behaviour broken, or on
   a copy with a wrong expected value.
5. Watch register clashes: `t0`-`t2` are used by `expect`/`fail`, `t0`
   is `x5`, `t2` is `x7`; keep capabilities in other registers (`c17`-`c24`).
6. Use `lla` (not `la`) while DDC is restricted (`la` loads from the GOT), and
   `.option norvc` where a handler skips a fixed number of bytes.
7. When the bug under test can corrupt translator state, check the result in
   a new translation block (a jump ends the block): `expect` loads its
   expected value with `li t2, ...`, which reads x0, and in `amocas-rd-x0`
   the corrupted x0 made the wrong value compare equal to itself.
8. In shell loops, read `$?` before any `$(...)`: `echo "$(basename $q)
   rc=$?"` prints basename's status, which once made a failing test look
   like a pass.

## Known gaps

- `fpclear` is not implemented (open-bugs trace 01); its random template is
  excluded until it is.
- `cgettop` cannot be generated by QuickCheckVEngine (trace 27 only), and
  `lr.c.cap` is not generated while the Sail model mishandles it
  (`regressions/coverage-required.txt` lists every coverage gap).

- MTTCG: CHERI tags are not thread-safe across host threads; use the default
  round-robin TCG for SMP (QEMU warns otherwise).
- `riscv64cheristd` (CHERI 0.9.3 standard) has no bench or CheriBSD run.
- Vector and hypervisor are refused on CHERI; `disabled-ext-inert` checks they
  stay off. Testing them for real needs a CHERI-aware implementation first.
- IOMMU (`riscv-iommu`): device DMA through an IOMMU ends in the same
  physmem write paths the two DMA tests cover; an IOMMU-specific test needs a
  bare-metal IOMMU driver (device directory, page tables) and is not written.
- `riscv64cheristd` (CHERI 0.9.3 standard): the bench uses v9 encodings and
  v9 semantics; a 0.9.3 bench would need its own `cheri-std.h` and a
  CheriBSD built for it.
- MTTCG: not a test gap but a design limit of CHERI tags (see SMP above).
