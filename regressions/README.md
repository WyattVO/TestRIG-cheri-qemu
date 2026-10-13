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

## Known divergences (not regressions)

These differ between Sail and CHERI QEMU in the same way on the 7.1 code base,
so they are specification disagreements rather than porting bugs:

- `cclear` is not implemented by CHERI QEMU (commented out of the v9 decoder);
  the `cclear` template is excluded by default.
- `cspecialrw` reads of extended SCRs (`mepcc`, `mtcc`, ...) outside capability
  mode return an untagged integer in QEMU (CHERI-Alliance standard rule) but the
  full capability in Sail (CHERI v9). Shows up in `capmisc` and `caprandom`.
- `cbuildcap` with a sealed bit pattern: QEMU tags the result only if it equals
  a canonical derivation; Sail v9 unseals and tags it. Shows up in `capdecode`.
- Unstructured random words whose low half is a compressed instruction: QEMU
  reports the 16-bit instruction in `rvfi_insn`, Sail echoes all 32 injected
  bits. Reporting only. Shows up in `unstructured`.
