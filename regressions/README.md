# TestRIG regression traces

Each `.S` file is a QuickCheckVEngine trace (`#>QCVENGINE_TEST_V2.0`) that once
produced a mismatch between the Sail CHERI-RISC-V model and CHERI QEMU. They are
replayed by `utils/scripts/testrig-gate.sh` so a fixed bug cannot come back
unnoticed. Replay a directory by hand with
`runTestRIG.py -a sail -b qemu ... -d regressions/<dir>`.

## cheri-qemu-10.2

Bugs found while bringing up RVFI-DII on the QEMU 10.2 CHERI port
(WyattVO/cheri-qemu-port, branch `cheri-10.2`):

| Trace | QEMU bug it caught |
|---|---|
| `01-gpr-immediate-write.S` | `gen_set_gpri()` (lui/li) did not report the register write |
| `02-store-tracing.S` | RVFI load/store tracing was dropped in the QEMU 8.x split of `tcg-op.c` |
| `03-load-aliased-address.S` | Load whose destination is also its address register (guards the address copy) |
| `04-misa-preserved-rvc-jump.S` | TestRIG reset zeroed `misa`/`priv_ver`, so jumps to 2-byte-aligned targets trapped |
| `05-page-cross-lookahead.S` | 10.x translator peeked at the next instruction in guest memory near a page end |
| `06-capreg-write-cmove.S` | Capability register writes (`cmove`) were not reported |
| `07-illegal-insn-mtval.S` | Helper-raised illegal instructions left `mtval` 0 (`env->bins` not set) |
| `08-reserved-scr-no-abort.S` | `cspecialrw` on a reserved SCR index aborted QEMU (`assert(false)`); now an illegal instruction |

### Matching Sail CHERI-RISC-V v9

QEMU behaviour changed to match the Sail v9 model. None of these gives a
program authority it could not already get; several remove authority.

| Trace | Change |
|---|---|
| `09-cspecialrw-full-cap-outside-capmode.S` | `cspecialrw` returns the full capability, also outside capability mode |
| `10-cbuildcap-sealed-pattern.S` | `cbuildcap` unseals the requested value (except sentries) before rederiving it |
| `11-cclear.S` | `cclear` implemented (was commented out of the v9 decoder); bit 0 of quarter 0 is DDC |
| `12-compressed-insn-report.S` | QCVEngine compares only the 16 instruction bits of a compressed `rvfi_insn` |
| `13-ddc-bounds-wrap.S` | An access wrapping past the top of a full-address-space DDC/PCC raises a length violation |
| `14-csr-insn-xlen-in-capmode.S` | v9 CSR instructions on `mepc` etc. only access the address, also in capability mode |
| `15-cbuildcap-sentry-no-abort.S` | `cbuildcap` of a sentry pattern whose rederivation loses its tag asserted in `cap_make_sealed_entry()` |
| `16-v9-scr-not-a-csr.S` | CSR instructions on `ddc` (0x416) or `vstid` (0xa80) are illegal on v9: those are SCRs |
| `17-sc-clears-capability-tag.S` | A successful `sc.w` into a stored capability did not clear its tag (lost in the 10.2 port's cmpxchg) |
| `18-ccopytype-reserved-otype-in-place.S` | `ccopytype` with `cd == cs1` dropped the cleared tag when updating the register in place |
| `19-ccseal-passthrough-untagged-sentry.S` | `ccseal` passes an already sealed `cs` through before checking its tag |
| `20-csr-asr-fault-cause.S` | A CSR instruction without ASR in PCC raised a CHERI exception without its cause, which could abort QEMU |
| `21-compressed-illegal-mtval.S` | An illegal compressed instruction reported the whole injected 32-bit word in `mtval` instead of its 16 bits |
| `22-mip-no-timer-pending.S` | The ACLINT left `mtimecmp` at 0 after each RVFI-DII reset, so `mip.MTIP` read as 1 |
| `23-mccsr-write-ignored.S` | Writing `mccsr`/`uccsr` raised an instruction access fault; writes are ignored (read-only feature bits) |
| `24-uxl-read-only.S` | `mstatus.UXL`/`sstatus.UXL` could be set to RV32 or the reserved value 3, invalid with the fixed RV64 capability format |
| `25-fetch-page-fault.S` | RVFI-DII gave every instruction fetch a fake 1:1 mapping, so QEMU never took instruction page/access faults |
| `26-paged-store-physical-address.S` | RVFI-DII reported virtual instead of physical `rvfi_mem_addr` for paged accesses (here a store rewrites its own PTE) |
| `27-cgettop.S` | `cgettop` (in the Sail model since 2022) was not implemented and raised an illegal instruction; QEMU's CHERI templates never generate it |
| `28-sc-b-last-byte.S` | `sc.b` to `0xffffffffffffffff` without a reservation matched QEMU's "no reservation" value (`load_res == -1`) and took a load access fault instead of failing (also in CHERI-QEMU 7.1) |
| `29-sc-needs-store-permission.S` | `sc.w`/`sc.d` (and the explicit `sc.*.ddc`/`sc.*.cap` forms) checked their address with the *load* check, so a reserved SC through a Load-only DDC or capability wrote memory; Sail raises PermitStore (also in CHERI-QEMU 7.1; found by the open-bugs trace 2026-10-19) |
| `30-cap-atomics-store-permissions.S` | `sc.c`/`amoswap.c` required StoreCap even for an untagged value and named the stored register instead of the authority for StoreLocalCap violations (Sail checks both only for tagged values and names the authority; found by the test bench 2026-10-20) |

## cheri-guards

Traces that pass today and pin CHERI behaviour that a change to QEMU's shared
code (or a later QEMU rebase) is likely to break. Replayed like the
regressions above.

| Trace | Property |
|---|---|
| `01-failed-sc-cheri-check-first.S` | An SC without a reservation to an address outside DDC raises a CHERI length fault (the CHERI check comes before the reservation check, as in Sail); in-bounds SCs without a reservation just fail; AMOs outside DDC fault too |

## open-bugs

Traces of known QEMU bugs that are not fixed yet. The gate replays each one
and expects it to fail (`xfail`); it reports `XPASS` once one passes, and the
trace should then move to `cheri-qemu-10.2/`.

None at the moment. The first one, a store-conditional without Store
permission, was fixed and is now `cheri-qemu-10.2/29-sc-needs-store-permission.S`.

## Reviewed CPU extensions

`cheri-extensions.txt` lists every extension property QEMU offers (QMP
expansion of `-cpu max`) as `allowed` or `refused`, with the test that covers
it. Gate stage 1 (`utils/scripts/cheri-ext-review.py`) fails on an extension
that is missing from the list, on a listed one QEMU no longer has, and on a
`refused` one the policy does not refuse. It also starts every CPU model and
fails if one crashes QEMU. A QEMU update that adds extensions (QEMU 11 adds
Zalasr, Zilsd/Zclsd, Smpmpmt, Zvfbfa, Xmipslsp, a big-endian property and
several CPU models) therefore fails the gate until each one is reviewed.

## qemu-only

Bare-metal programs run directly on QEMU by `utils/scripts/qemu-only-tests.sh`
(stage 3 of the gate; needs `riscv64-linux-gnu-gcc` or `CROSS_CC`). They check
CHERI properties of features the Sail model lacks or gets wrong, so TestRIG
cannot compare them. CHERI instructions are written with `.insn` (see
`cheri-v9.h`); a test passes by exiting through the virt test device.

| Test | Property |
|---|---|
| `amocas-q-clears-tag.S` | A successful `amocas.q` clears the overwritten capability's tag; a failed one changes nothing |
| `amocas-wdb-clears-tag.S` | Same for `amocas.d`, `amocas.w` (Zacas) and `amocas.b` (Zabha) |
| `pte-cw-capability-store.S` | Sv39 in S-mode: a tagged capability store to a page with CW clear raises cause 27, an untagged one succeeds, CW set keeps the tag. Sail never enforces CW |
| `smp-tag-consistency.S` | Two harts (`# QEMU_SMP: 2`): while hart 1 alternately stores a capability and plain data into a slot, every tagged capability hart 0 loads from it is hart 1's capability (never a tag on plain data); a plain store from one hart clears the tag of a capability another hart stored |
| `tag-clear-store-widths.S` | Every store width and kind (sb/sh/sw/sd, fsw/fsd, c.sw/c.sd) clears the tag of exactly the capability it writes into; misaligned stores crossing two capabilities clear both; loads and stores outside a capability leave it tagged |
| `uxl-read-only.S` | `mstatus`/`sstatus` UXL stays RV64 |
| `pte-crg-load-generation.S` | A tagged capability load from a CR+CRM page whose CRG differs from `sccsr.SGCLG` raises cause 26, also after the page is in the TLB; untagged and matching-generation loads do not (CheriBSD load-side revocation) |
| `pte-cr-cd-tlb-flags.S` | After an ordinary access fills the TLB, a capability load from a CR = 0 page still drops the tag, and the first tagged store to a CD = 0 page still sets CD (or traps) |
| `pte-cheri-bits-not-reserved.S` | Ordinary fetches, loads and stores work on pages with any valid mix of CW/CR/CD/CRM/CRG, including CR = CD = 1 (Svpbmt's reserved PBMT = 3) and CW alone (Svnapot's N bit): those PTE bits belong to CHERI on v9 |
| `pte-cheri-bits-flush.S` | Clearing CR or CW in a PTE takes effect after `sfence.vma <va>` and after Svinval's `sinval.vma`, even though the old entry was in the TLB; setting CW again restores capability stores |
| `pte-cd-update-pmp.S` | **XFAIL on 10.2.** With Svadu, the PTE write that sets CD must pass PMP: a capability store whose CD update hits a read-only page table raises a store access fault. QEMU 10.2 writes the PTE anyway (fixed upstream in QEMU 11, `fa2cf74883`) |
| `pmp-capability-access.S` | PMP checks all 16 bytes of a capability store/load: one that overlaps a no-access PMP region faults without a partial write or a tag |
| `asr-permission.S` | Without ASR in PCC, privileged CSRs (read and write), privileged SCRs (MTCC), `mret` and `cbo.inval` raise a CHERI ASR fault on PCC (mtval `0x418`) and have no effect; user CSRs, DDC and ordinary memory accesses still work |
| `cheri-fault-delegation.S` | A CHERI fault in a U-mode capability-mode program is delegated to S-mode through `medeleg` bit 28, with the right `scause`, `stval` (register and cause) and the full user PCC in SEPCC; `sret` returns to the program in capability mode |
| `cbo-inval-bounds.S` | `cbo.clean`/`cbo.flush` need only one byte of the block in bounds, but `cbo.inval` needs all of it (riscv-cheri spec, `cbo_exceptions.adoc`): invalidating a partly covered block could re-expose older data and capabilities. QEMU 10.2 only rejected blocks entirely outside the bounds (fixed 2026-10-19) |
| `cbo-zero-cheri.S` | `cbo.zero` (Zicboz) clears the tags of every capability in the 64-byte block, needs Store permission in its authority and the whole block in bounds |
| `debug-trigger-cheri.S` | Sdtrig data triggers fire for capability loads and stores as for ordinary ones (capability stores missed them: the 10.2 port read the TLB slow flags with the unmapped CHERI access type; fixed 2026-10-20), and an execute trigger in capability mode saves a tagged capability-mode MEPCC and resumes there |
| `disabled-ext-inert.S` | On `-cpu max`, every extension the CHERI policy refuses is really off: vector and hypervisor instructions and CSRs are illegal, `mstatus.VS`, the pointer-masking fields (`menvcfg.PMM`, `mseccfg.PMM`) and `menvcfg.LPE/SSE` stay 0, `mnret` is illegal. `mseccfg.PMM` was writable through the Smepmp path (upstream QEMU bug, harmless here because masking is gated on Smmpm; fixed 2026-10-20) |
| `dma-clears-tags.S` | A device writing guest memory by DMA (fw_cfg) clears the tag of the capability it writes into, even partly, and leaves neighbouring capabilities tagged |
| `ext-functional.S` | 10.2 extensions Sail lacks compute spec results in the CHERI build: Zicond, Zfh, Zfa, Zcb, Zbkb, Zimop/Zcmop, Zawrs/Zihintpause, Sstc (`stimecmp` drives `mip.STIP`), Zicbop (prefetches never fault, even outside DDC), Zicntr |
| `ext-mem-insns-cheri.S` | Zcb (`c.lbu`/`c.lhu`/`c.sb`/`c.sh`), Zfh (`flh`/`fsh`), Zacas, Zabha and Zicbom instructions clear the tags they overwrite and obey DDC bounds and Store permission |
| `ext-mem-insns-capmode.S` | The same instructions in capability mode (purecap CheriBSD's mode): the address capability, not DDC, is checked |
| `sc-store-permission.S` | Store-conditionals need Store (not Load) permission: `sc.w` with a Load-only DDC, the explicit `sc.w.ddc`/`sc.w.cap` forms (not in Sail) and `sc.w`/`sc.d` in capability mode raise PermitStore; an SC through a Store-only capability succeeds |
| `virtio-dma-clears-tags.S` | A virtio device (virtio-rng over legacy virtio-mmio, `# QEMU_ARGS`) writing a guest buffer through `address_space_map()` clears the tag of the capability it writes into and leaves its neighbour tagged |
| `xthead-mem-cheri.S` | XTheadMemIdx/XTheadMemPair (accepted on CHERI CPUs) clear tags and obey DDC bounds and Store permission |
| `interrupt-capmode.S` | An interrupt that arrives in capability mode with a small PCC (M-mode MSI, and an SSI delegated to S-mode) saves the whole PCC in MEPCC/SEPCC (tag, mode flag, bounds, address), runs the handler with MTCC/STCC, and `mret`/`sret` return to capability mode with the same PCC. RVFI-DII never delivers interrupts, so TestRIG cannot check this |
| `pcc-bounds-cached-tb.S` | Code first translated under the full PCC still has its fetches checked when later run under a PCC covering one instruction (PCC bounds are part of QEMU's translation cache key) |
| `data-endianness-fixed.S` | `mstatus` MBE/SBE/UBE stay 0 and data accesses stay little-endian (one capability memory format) |

A `# QEMU_SMP: <n>` line runs a test with n harts, and `# QEMU_ARGS: <args>` adds QEMU options (devices). A `# XFAIL: <reason>` line marks a test that is known to fail; it is
reported as `xfail` and does not fail the gate (`XPASS` when it starts
passing). `cheri-v9.h` has shared macros for these tests, including an
expected-trap handler (`check`, `trap_expect`, `expected_trap_handler`).

### SMP and MTTCG

QEMU runs CHERI harts round-robin on one host thread by default (it does not
enable MTTCG for CHERI targets). With `-accel tcg,thread=multi`, QEMU warns
that CHERI tags are not thread-safe, and that is real:
`smp-tag-consistency.S` then fails check 1 every time (hart 0 loads a tagged
capability made of hart 1's plain data, i.e. a forged capability), and any
`cbo.zero` aborts QEMU (an assertion in `do_cbo_zero`). Never run CHERI
guests with MTTCG. `cheribsd-tests.py --smp N` boots CheriBSD with N harts
(round-robin) for the kernel's SMP paths.

Each new test was checked against a deliberately broken QEMU (2026-10-19):
`cbo.zero` without tag invalidation fails `cbo-zero-cheri` check 1, and
upstream QEMU 11's unconditional PBMT check fails `pte-cheri-bits-not-reserved`,
`pte-cheri-bits-flush` and the older PTE tests.

The last two caught QEMU 10.x storing the CHERI page flags in the 8-bit
`CPUTLBEntryFull.prot` (found by `cheribsdtest-purecap`, see below). QEMU 7.1
fails check 2 of `pte-cr-cd-tlb-flags.S`: it never re-walks a cached page to
set CD.

## CHERI extension policy

QEMU refuses to start a CHERI CPU with an extension that bypasses capability
checks when it is requested explicitly (e.g. `v=true`), and disables it with a
warning when a CPU model enables it implicitly (e.g. `-cpu max`). The gate checks
this before replaying traces. Currently disabled: vector (`v`, `zve*`, `zv*`:
vector loads/stores use raw addresses), pointer masking (`smmpm`, `smnpm`,
`ssnpm`, `sspm`, `supm`), `svrsw60t59b` (PTE bits 59-60 are CHERI permission
bits), `zcmt` (jump table reads are not checked against PCC/DDC), `smrnmi`
(`mnret` does not restore PCC), `zicfiss` (shadow stack accesses are not checked
against DDC), `zicfilp` (capability jumps do not set the landing-pad state) and
`h` (the hypervisor extension is not defined for CHERI; `hlvx` aborted QEMU).
Bare and profile CPUs (`rv64i`, `rva23u64`) are checked too, RV32 CPUs are
rejected by the 64-bit CHERI binaries, and `rva22s64`/`rva23s64` do not exist on
v9 (they need Svpbmt/Svnapot, whose PTE bits are CHERI bits).

## Gate configuration

The gate runs `rv64imsafdcZicsr_Zifencei_Xcheri` and passes `zba,zbb,zbc,zbs` to
QEMU because the Sail model always implements the B extensions. `runTestRIG.py`
also gives QEMU's bare CPU an MMU with Sv39/Sv48 and Svade (page fault instead of
hardware A/D updates), like Sail; before this, `satp` writes were ignored and the
`pte` template never exercised paging on QEMU.

Excluded from comparison, each traced to a reference-model difference rather
than a QEMU bug:

- `unstructured` does not generate CSR instructions on `seed` (random by design),
  `misa` (Sail always reports V and F/D), `mhpmevent3`-`31`, the counters
  (timing-dependent), the debug trigger CSRs (0x7a0-0x7af) or `mconfigptr`.
  A read and a write-form access of all 4096 CSR numbers found no other differences.
  It also skips `mip`: bit 7 (MTIP) reflects each implementation's timer. Sail
  advances `mtime` once every 100 instructions with `mtimecmp` left at 0, so
  MTIP goes pending at the 100th instruction of a test, while QEMU's `mtime`
  follows host time and its RVFI-DII mode never lets the timer fire. Masking
  MTIP in the comparison is not enough (the value read lands in a register and
  diverges later), so MTIP is never compared and the other `mip` bits are not
  compared by random tests either; trace 22 still checks `mip` after reset. A
  test that actually takes the timer interrupt would still diverge.
  Finally it skips `cspecialrw` on SCRs the Sail model cannot handle: `utidc`,
  `stidc`, `mtidc` (3, 11, 27; QEMU implements the thread ID capability
  registers, Sail raises illegal instruction) and 0x14-0x17 (missing from
  Sail's `scr_name_map`, so the model aborts and ends the run).
- `csr` (`CSR_EXCLUDE`) skips those plus `mstatus`/`sstatus` (Sail has the vector
  VS field), `mip`/`mie`/`mideleg`/`medeleg` (Sail's legalizers are marked FIXME
  and allow bits QEMU correctly keeps zero), `sccsr` (Sail lacks the
  load-capability generation bits) and unnamed CSRs.
- `pte` only generates PTEs Sail judges correctly: CW = CD = 1, CRM = CRG = 0
  (Sail never enforces CW and has no CD/CRM/CRG), and no A/D/U in non-leaf PTEs
  (reserved since privileged spec 1.13; Sail follows the older spec). The PTE
  construction is not shrunk, so a counter-example cannot turn into one of those.
  CW = 0 is covered by `qemu-only/pte-cw-capability-store.S`; CD/CRM/CRG need a
  newer model (the sail-cheri-riscv `clg` branch has them).
- `mscratch`/`sscratch` are excluded from CSR generation (all templates): QEMU
  aliases them to the address of the `mscratchc`/`sscratchc` SCRs, while in the
  Sail model they are separate registers. **Open question**, not yet changed:
  the alias is long-standing (also in CHERI-Alliance) and grants no authority,
  but it differs from Sail; decide after checking what CheriBSD expects.
- `csc_*`, `bsc_*`, `tsc` and `hpm` need Zihpm counters, which cannot be compared.

A test whose first difference is a store-conditional that succeeded on one
side and failed on the other is discarded rather than failed: the ISA allows
an SC to fail while its reservation is held (e.g. after a store to the
reserved address from the same hart). Sail lets it succeed, QEMU checks that
the reserved value is unchanged.

## Known divergences (not regressions)

- Without the A extension Sail reports a failed store-conditional (`rd` = 1) for
  `sc.*` instead of an illegal instruction, because it checks the reservation
  first. QEMU raises illegal instruction. The gate enables A, so this does not
  occur there.

## Checking the gate itself

A gate that always passes proves nothing, so it was run against a deliberately
broken QEMU (cheri-10.2 with these fixes reverted, 2026-10-14):

| Reverted fix | Caught by |
|---|---|
| `tcg: Clear capability tags and trace stores in CHERI compare-and-swap` | regression `17-sc-clears-capability-tag.S` |
| `tcg: Clear capability tags in the CHERI 128-bit compare-and-swap` | `qemu-only/amocas-q-clears-tag`, `qemu-only/amocas-wdb-clears-tag` |
| `target/cheri-common: Check DDC/PCC accesses that wrap past the top` | regression `13-ddc-bounds-wrap.S` |
| `target/riscv: Apply the CHERI extension policy to bare and profile CPUs` | policy checks `rv64i,v=true` and `rva23u64` |
| `accel/tcg: Don't truncate the CHERI page protection bits in the TLB` (not yet written then; the bug was present) | `qemu-only/pte-crg-load-generation`, `qemu-only/pte-cr-cd-tlb-flags` (added later), and stage 5 (11 `cheri_revoke_*` failures) |

Every mutation failed the gate; the other 24 traces and all policy and
QEMU-only checks still passed. Random tests alone (20 per template) caught
none of them, which is why every fixed bug gets a saved trace or a QEMU-only
test. The regression replay uses `--continue-on-fail`: without it, the first
failing trace (13) skipped the remaining ones and hid trace 17.

## CheriBSD

`cheribsdtest` is the end-to-end check: `utils/scripts/cheribsd-tests.py` (gate
stage 5, enabled with `CHERIBSD_OUTPUT=<cheribuild output dir>`) boots the
CheriBSD disk image built by cheribuild (`riscv64-purecap`, kernel
`CHERI-PURECAP-QEMU`, snapshot mode) on `qemu-system-riscv64xcheri` and runs
`cheribsdtest-purecap -a` and `cheribsdtest-hybrid -a`. Expected failures
(XFAIL) are known CheriBSD limitations; any FAIL fails the gate.

Results on cheri-10.2 (2026-10-14, cheribsd `main-88f39900c329`):

| Suite | Before TLB fix | After |
|---|---|---|
| `cheribsdtest-purecap` | 294 passed, **11 failed**, 10 XFAIL | 305 passed, 10 XFAIL |
| `cheribsdtest-hybrid` | 149 passed, 52 XFAIL | 149 passed, 52 XFAIL |
| `-purecap-mt` / `-dynamic` / `-dynamic-mt` | | 307 / 314 / 316 passed, 10 XFAIL |
| `-hybrid-mt` / `-dynamic` / `-dynamic-mt` | | 150 / 157 / 158 passed, 52 XFAIL |

The 11 failures were all `cheri_revoke_*` (QEMU 7.1 passes them): QEMU 10.x
kept the CHERI page flags in the 8-bit `CPUTLBEntryFull.prot`, so a revoked
capability survived load-side revocation. Fixed by cheri-qemu-port
`accel/tcg: Don't truncate the CHERI page protection bits in the TLB`;
`qemu-only/pte-crg-load-generation.S` and `qemu-only/pte-cr-cd-tlb-flags.S`
now catch it in seconds.
