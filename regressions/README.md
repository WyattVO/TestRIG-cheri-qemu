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
| `uxl-read-only.S` | `mstatus`/`sstatus` UXL stays RV64 |
| `pte-crg-load-generation.S` | A tagged capability load from a CR+CRM page whose CRG differs from `sccsr.SGCLG` raises cause 26, also after the page is in the TLB; untagged and matching-generation loads do not (CheriBSD load-side revocation) |
| `pte-cr-cd-tlb-flags.S` | After an ordinary access fills the TLB, a capability load from a CR = 0 page still drops the tag, and the first tagged store to a CD = 0 page still sets CD (or traps) |

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
