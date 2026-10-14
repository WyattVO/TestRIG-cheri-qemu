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

## CHERI extension policy

QEMU refuses to start a CHERI CPU with an extension that bypasses capability
checks when it is requested explicitly (e.g. `v=true`), and disables it with a
warning when a CPU model enables it implicitly (e.g. `-cpu max`). The gate checks
this before replaying traces. Currently disabled: vector (`v`, `zve*`, `zv*`:
vector loads/stores use raw addresses), pointer masking (`smmpm`, `smnpm`,
`ssnpm`, `sspm`, `supm`), `svrsw60t59b` (PTE bits 59-60 are CHERI permission
bits), `zcmt` (jump table reads are not checked against PCC/DDC) and `smrnmi`
(`mnret` does not restore PCC).

## Gate configuration

The gate runs `rv64imacZifencei_Xcheri` and passes `zba,zbb,zbc,zbs` to QEMU
because the Sail model always implements the B extensions and cannot turn them
off. The `unstructured` template does not generate CSR instructions on
`mhpmevent3`-`31` (the privileged spec requires them and QEMU has them, but the
Sail model does not), on `misa` (Sail always reports its full ISA there,
including V and F/D), on the counters (`mcycle`, `minstret`, `time`, ...,
whose values depend on timing and on how each implementation counts), or on the
debug trigger CSRs (0x7a0-0x7af) and `mconfigptr`, which QEMU implements and the
Sail model does not. Reading all 4096 CSR numbers in both implementations found
no other differences.

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
