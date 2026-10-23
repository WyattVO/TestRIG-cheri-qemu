# TestRIG for CHERI-RISC-V QEMU 10.2 (WyattVO/TestRIG-cheri-qemu, branch `testrig-cheri-qemu-10.2`)

This fork of [CTSRD-CHERI/TestRIG](https://github.com/CTSRD-CHERI/TestRIG) is
the regression gate for the QEMU 10.2 CHERI-RISC-V port
([WyattVO/cheri-qemu-port](https://github.com/WyattVO/cheri-qemu-port/tree/cheri-10.2),
branch `cheri-10.2`). It checks QEMU instruction by instruction against the
Sail CHERI-RISC-V reference model, and at system level by booting CheriBSD.
Any change to that QEMU branch, including AI-written ones and future rebases,
is meant to pass this gate first. The original TestRIG README follows after
this section.

## The gate

`utils/scripts/testrig-gate.sh <qemu-system-riscv64xcheri> [tests-per-template]`
runs up to seven stages and fails if any of them fails. Each stage has its
own reference ("oracle"); [TESTBENCH.md](TESTBENCH.md#oracles-what-each-stage-compares-against)
says what each one can and cannot judge.

| Stage | What it checks |
|---|---|
| 1. CHERI extension policy | QEMU refuses extensions that bypass capability checks (vector, hypervisor, pointer masking, Zicfiss/Zicfilp, big-endian, ...) and still starts the normal CPUs; every extension it offers is listed as reviewed in `regressions/cheri-extensions.txt`, and no CPU model crashes it |
| 2. Saved regression traces | All 30 traces in `regressions/cheri-qemu-10.2/` (bugs that were found and fixed) and `regressions/cheri-guards/` replay without a difference from Sail. Traces of open bugs in `regressions/open-bugs/` must still fail |
| 3. QEMU-only bare-metal tests | 29 tests in `regressions/qemu-only/` for CHERI behaviour the Sail model lacks (CW/CD/CRM/CRG page bits and TLB flushes, PMP, `amocas`/Zabha/Zcb/Zfh/Zicbo* and T-Head instructions in integer and capability mode, PCC bounds in cached code, interrupts in capability mode, two-hart tag consistency, UXL, endianness) |
| 4. Random tests | Every QuickCheckVEngine template, comparing QEMU with Sail (30 of 37 run; 7 need hardware counters). Seeded (`SEED=`), failures saved to `random-failures/` as traces, then `coverage-check.py` fails if a CHERI instruction in `regressions/coverage-required.txt` never completed (or never faulted) |
| 4b. Three-way vote (optional, `ALLIANCE_QEMU`) | Random tests of [CHERI-Alliance QEMU](https://github.com/CHERI-Alliance/qemu) `main` against this QEMU; each disagreement is replayed on Sail. Fails if this QEMU is the odd one out, or if both QEMUs differ from Sail; reports Alliance-only differences |
| 5. CheriBSD (optional, `CHERIBSD_OUTPUT`) | Boots CheriBSD and runs `cheribsdtest-purecap` and `cheribsdtest-hybrid`; any `FAIL` fails the gate |
| 6. Upstream QEMU (optional, `UPSTREAM_BUILD`, `ARCH_TEST`) | Unmodified upstream QEMU v10.2.0 is the reference for non-CHERI behaviour: upstream's own check-tcg and qtests run on this QEMU, and every RV64 riscv-arch-test program gives the same signature and instruction trace on both (`upstream-diff.py`, known differences with reasons in `utils/upstream-diff/expected.txt`) |

Last full run on `cheri-10.2` (2026-10-15, 300 tests per template, about 31
minutes): every stage passed. `cheribsdtest-purecap` passed 305 with 10
expected failures, and `cheribsdtest-hybrid` passed 149 with 52.

[TESTBENCH.md](TESTBENCH.md) explains the CHERI test bench (stage 3): what each
test checks, what bad behaviour it catches and how it was proven to fail.
[regressions/README.md](regressions/README.md) lists every trace and the bug it
caught. It also explains each exclusion, where the Sail model and QEMU
legitimately differ, and how the gate was itself checked by reverting fixes.

## Changes in this fork (Wyatt Voigt)

- **Running TestRIG against CHERI QEMU 7.x-10.x** (`runTestRIG.py`):
  - Read QEMU's CPU property names from the binary, so the same runner works
    on 7.1 and 10.2.
  - Add `--qemu-cpu-extra` for extra `-cpu` properties.
  - Give QEMU's test CPU an MMU with Sail's paging behaviour (Sv39/Sv48,
    Svade). Before this, paging was never tested.
- **The gate** (`utils/scripts/testrig-gate.sh`, `qemu-only-tests.sh`,
  `cheribsd-tests.py`): the five stages above. Regressions are replayed with
  `--continue-on-fail`, so one failure can't hide another.
- **Regression traces** `regressions/cheri-qemu-10.2/01`-`28`, plus the
  bare-metal tests in `regressions/qemu-only/`. `.gitignore` used to ignore
  every `.S` file, so saved traces are now exempted.
- **QuickCheckVEngine** points at
  [WyattVO/QuickCheckVEngine](https://github.com/WyattVO/QuickCheckVEngine/tree/cheri-qemu-gate),
  branch `cheri-qemu-gate`. That fork compares only the real bits of compressed
  instructions, generates page tables the Sail model judges correctly, and keeps
  the `unstructured` template off registers that can't be compared (counters,
  `mip`, `seed`, ...) and off SCRs the Sail model lacks.
- **Excluded from comparison**, each traced to a reference-model difference
  rather than a QEMU bug:
  - `misa`, the counters, the debug triggers, `mconfigptr`, `seed`;
  - `mip` (the two timers work differently), `mscratch`/`sscratch`;
  - `utidc`/`stidc`/`mtidc` (thread-ID capability registers Sail lacks);
  - SCRs 0x14-0x17 (they crash the Sail model).

  Details are in `regressions/README.md`.

The Sail model (`riscv-implementations/sail-cheri-riscv`, CTSRD `74a9da1`) is
unmodified. Its C emulator needs one test-harness fix,
`utils/patches/sail-riscv-rvfi-reset-reservation.patch`: it kept the LR
reservation across RVFI-DII test resets, so whether an SC succeeded could
depend on the previous test. Apply it before building (step 3).

## Running it on your machine

Tested on Ubuntu 26.04 with GCC 15 and Python 3.14, without root (GHC, opam
and z3 installed per user). You need the QEMU under test, QuickCheckVEngine,
the Sail CHERI-RISC-V emulator, optionally a RISC-V cross compiler, and
optionally a CheriBSD image.

**1. Clone with the two submodules the gate needs**

```sh
git clone -b testrig-cheri-qemu-10.2 https://github.com/WyattVO/TestRIG-cheri-qemu.git
cd TestRIG-cheri-qemu
git submodule update --init --recursive vengines/QuickCheckVEngine riscv-implementations/sail-cheri-riscv
```

**2. Build QuickCheckVEngine** with GHC 9.6 and cabal 3.4 or newer, both from
[GHCup](https://www.haskell.org/ghcup/). The `stack.yaml` snapshot is too old;
use cabal.

```sh
cd vengines/QuickCheckVEngine && cabal update && cabal build -w ghc-9.6.7 && cd ../..
```

**3. Build the Sail CHERI-RISC-V emulator** with Sail 0.18 from
[opam](https://opam.ocaml.org/) (tested with OCaml 5.2.1) and the
[z3](https://github.com/Z3Prover/z3/releases) solver on `PATH`:

```sh
sudo apt install opam z3 libgmp-dev zlib1g-dev pkg-config   # or a z3 release binary in ~/.local/bin
opam init && opam switch create sail ocaml-base-compiler.5.2.1 && opam install sail.0.18
eval $(opam env --switch=sail)
git -C riscv-implementations/sail-cheri-riscv apply ../../utils/patches/sail-riscv-rvfi-reset-reservation.patch
make -C riscv-implementations/sail-cheri-riscv C_WARNINGS=-std=gnu17 c_emulator/cheri_riscv_rvfi_RV64
```

`C_WARNINGS=-std=gnu17` is needed with GCC 15 or newer, which default to C23.

**4. Build the QEMU under test** with `--enable-rvfi-dii`, as described in the
[cheri-qemu-port README](https://github.com/WyattVO/cheri-qemu-port/tree/cheri-10.2):

```sh
git clone -b cheri-10.2 https://github.com/WyattVO/cheri-qemu-port.git
mkdir cheri-qemu-port/build && cd cheri-qemu-port/build
../configure --target-list=riscv64xcheri-softmmu --enable-rvfi-dii --disable-werror --disable-docs && ninja
```

**5. Optional extras**

- For stage 3, install a RISC-V cross compiler:
  `sudo apt install gcc-riscv64-linux-gnu`, or point `CROSS_CC` at one.
- For stage 4b, build CHERI-Alliance QEMU `main` with RVFI-DII (QEMU 7.2
  needs an external meson, e.g. from a Python venv):
  ```sh
  git clone https://github.com/CHERI-Alliance/qemu.git alliance-qemu
  mkdir alliance-qemu/build && cd alliance-qemu/build
  ../configure --meson=$(which meson) --target-list=riscv64xcheri-softmmu --enable-rvfi-dii \
      --disable-werror --disable-docs --disable-slirp --disable-rdma && ninja
  ```
- For stage 6, build upstream QEMU v10.2.0 with plugins and its RISC-V
  check-tcg tests, and check out riscv-arch-test 3.9.1:
  ```sh
  git clone -b v10.2.0 https://github.com/qemu/qemu.git upstream-qemu-10.2
  mkdir upstream-qemu-10.2/build && cd upstream-qemu-10.2/build
  ../configure --target-list=riscv64-softmmu --enable-plugins \
      --cross-prefix-riscv64=riscv64-linux-gnu- --disable-docs
  ninja && ninja contrib-plugins && make check-tcg
  git clone --depth 1 -b 3.9.1 https://github.com/riscv-non-isa/riscv-arch-test.git
  ```
  The QEMU under test must support TCG plugins (the default).
- For stage 5, build CheriBSD with
  [cheribuild](https://github.com/CTSRD-CHERI/cheribuild):
  `./cheribuild.py -d disk-image-riscv64-purecap bbl-baremetal-riscv64-purecap`.
  The output goes to `~/cheri/output`.

**6. Run the gate**

```sh
QEMU=/path/to/cheri-qemu-port/build/qemu-system-riscv64xcheri
utils/scripts/testrig-gate.sh $QEMU 300                                    # stages 1-4
CHERIBSD_OUTPUT=~/cheri/output utils/scripts/testrig-gate.sh $QEMU 300     # plus CheriBSD
ALLIANCE_QEMU=/path/to/alliance-qemu/build/qemu-system-riscv64xcheri \
UPSTREAM_BUILD=/path/to/upstream-qemu-10.2/build ARCH_TEST=/path/to/riscv-arch-test \
CHERIBSD_OUTPUT=~/cheri/output utils/scripts/testrig-gate.sh $QEMU 100     # every stage
```

It ends with `TESTRIG GATE: PASS` or `FAIL`. Don't edit `testrig-gate.sh`
while it runs: bash reads the script as it goes. Environment variables
`EXCLUDE`, `SEED`, `SAVE_DIR`, `ARCH`, `CSR_EXCLUDE`, `QEMU_CPU_EXTRA`,
`QCVENGINE`, `CROSS_CC`, `VOTE_TESTS` and the optional stages' variables are
described at the top of the script. `CHERIBSD_LOG` sets where the
CheriBSD console log is written (default `cheribsd-tests.log`).

### Turning tests on and off

Every run first prints its plan, one line per stage: `run`, `skip: <why>`,
or `ERROR: <why>` (a stage you asked for that cannot run; the gate stops).
Add `--list` to print only the plan, without running anything.

**Stages.** Name them or use their numbers, comma-separated, in `--only`
(run just these) or `--skip` (run all but these):

| Stage | Name (number) | On by default? | Turn on | Turn off |
|---|---|---|---|---|
| CHERI extension policy | `policy` (1) | yes | - | `--skip policy` |
| Saved regression traces vs Sail | `regressions` (2) | yes | - | `--skip regressions` |
| Bench (QEMU-only tests) | `bench` (3) | yes, if a RISC-V cross compiler is found | `CROSS_CC=...` | `--skip bench` |
| Random tests vs Sail | `random` (4) | yes | - | `--skip random` |
| Coverage of the random tests | `coverage` | yes, unless templates are selected | `--only ...,coverage` | `--skip coverage` |
| Three-way vote with CHERI-Alliance QEMU | `vote` (4b) | when its QEMU is given | `--alliance PATH` | `--skip vote` |
| CheriBSD `cheribsdtest` | `cheribsd` (5) | when its image is given | `--cheribsd DIR` | `--skip cheribsd` |
| Upstream QEMU 10.2 comparison | `upstream` (6) | when its build is given | `--upstream-build DIR` (+ `--arch-test DIR`) | `--skip upstream` |

**References.** `--against sail,alliance,upstream` keeps only the stages
that compare against those references (sail: `regressions`, `random`,
`coverage`; alliance: `vote`; upstream: `upstream`); `policy`, `bench` and
`cheribsd` need no reference and still run unless skipped. A stage named in
`--only` or `--against` whose reference is not given is an error.

**Individual tests** (regular expressions on names):

| What | Run only matching | Skip matching | Names are |
|---|---|---|---|
| Random-test templates (stages 4, 4b) | `--templates RE` | `--exclude RE` | template names, e.g. `caparith`, `fpclear` (the random stage prints each as `<name> -- <description>`) |
| Bench tests (stage 3) | `--bench RE` | `--bench-exclude RE` | files in `regressions/qemu-only/` without `.S` |
| Regression traces (stage 2) | - | `--trace-exclude RE` | file names in `regressions/*/`, e.g. `^31-` |
| riscv-arch-test suites (stage 6) | `--suites I,M,Zacas` | - | directories in `riscv-test-suite/rv64i_m/` |

Skipped tests are printed (`skipped: <name>`), so a filtered run never
looks like a full one. Selecting templates also skips the coverage check,
which would otherwise fail on the instructions the other templates run.

**Examples:**

```sh
G=utils/scripts/testrig-gate.sh
$G --list --config utils/gate-profiles/full.conf $QEMU   # what would run?
$G --only policy,regressions,bench $QEMU                  # fast: no random tests
$G --skip cheribsd,vote $QEMU 100                         # everything else
$G --against sail $QEMU 100                               # only Sail comparisons
$G --against alliance --alliance /path/to/qemu-system-riscv64xcheri $QEMU 50
$G --only random --templates '^cap' --exclude 'caprvc' $QEMU 200
$G --only bench --bench '^pte-' --bench-exclude 'pmp' $QEMU
$G --trace-exclude '^0[1-4]-' $QEMU
$G --only upstream --suites I,M,Zacas --upstream-build ... --arch-test ... $QEMU
```

**Saved setups.** `--config FILE` reads `VAR=value` lines (the environment
variables at the top of `testrig-gate.sh`, e.g. `ONLY=`, `SKIP=`,
`EXCLUDE=`, `ALLIANCE_QEMU=`); options on the command line win, so
`--config full.conf --skip cheribsd` works. `utils/gate-profiles/` has
`quick.conf` (stages 1-3), `sail.conf` (every Sail comparison) and
`full.conf` (every stage, with the references in `~/Projects/CAPSTONE`).
With no options the gate behaves as before: every stage whose reference
is configured runs.

### Smaller runs

```sh
QCV=$(find vengines/QuickCheckVEngine/dist-newstyle -type f -name QCVEngine -perm -u+x | head -1)
R="python3 utils/scripts/runTestRIG.py -a sail -b qemu --path-to-qemu $QEMU --path-to-QCVEngine $QCV \
   -r rv64imsafdcZicsr_Zifencei_Xcheri --support-misaligned --no-save -s 2 \
   --qemu-cpu-extra zba=true,zbb=true,zbc=true,zbs=true"
$R -n 50 --test-include-regex '^caparith$'                    # one template
$R -n 50 --test-include-regex '^caparith$' --seed 12345       # the same tests again
$R -t regressions/cheri-qemu-10.2/27-cgettop.S -v 2           # one trace, every instruction shown
$R -d regressions/cheri-qemu-10.2/ --continue-on-fail         # all saved traces
python3 utils/scripts/cheribsd-tests.py $QEMU ~/cheri/output  # stage 5 only
```

### Reading a failure

- `mismatch in field <name>: A != B` compares Sail (A) with QEMU (B) on the
  first instruction where they differ.
- QuickCheckVEngine shrinks the failing test to a few instructions and prints
  it as a `.S` trace. Replay it with `-t <file> -v 2`.
- If it was a real QEMU bug, add the trace to `regressions/cheri-qemu-10.2/`
  with a comment saying what it checks.
- `Connection reset by peer` or a timeout means one of the two simulators
  crashed.
- `passed N tests; 1 discarded` is fine. A store-conditional may legally
  succeed on one side and fail on the other.
- A random failure prints the run's seed; `SEED=<n>` reruns the same tests,
  and `--seed <n> -I '^<template>$'` reruns one template's tests (template
  seeds depend only on the seed and the template, not on the regexes).
- Stage 4b: `port-differs` is a bug in this QEMU; `both-differ` needs the
  spec (so far: a missing QEMU instruction, a Sail bug, an allowed
  difference); `alliance-differs` is for the upstream bug report. The
  shrunk traces are in `random-failures/vote-<seed>/traces/`.

---

# TestRIG
Framework for testing RISC-V processors with Random Instruction Generation.

## Glorious vision
TestRIG is a framework for RISC-V processor verification using the RVFI-DII (pronounced "rividy") interface.
TestRIG supports two types of components:

1. Vengines (verification engines)
2. Implementations (including models, simulators, and SoCs)

Vengines generate one or more DII streams of instruction traces, and consume one
or more RVFI streams of execution traces. Implementations consume a DII
instruction trace, and generate an RVFI execution trace. A Vengine can, for
example, produce two equivalent DII streams for two implementations and check
that the two generated RVFI streams are equivalent.

<img src="diagram.svg" width="450">

TestRIG eliminates the "test gap" between specification and implementation.
If the specification is an executable model (see Sail, L3, and many other efforts), then TestRIG allows automated verification of any specified property without passing through human interpretation and hand-writing tests.
While TestRIG should require work to construct trace generators for classes of ISA behaviour, new instructions in a class can automatically be included in new traces and will be run in many more variations than hand-written tests would allow.

TestRIG verifies the pipeline as well as specification compliance.
Test suites are designed to test as many aspects of an instruction set specification as possible, but cannot be expected to provide any reasonable verification of complex pipeline behaviour.
TestRIG can verify every register value read in the pipeline under random sequence generation, while a test suite will only report a prescribed test result.

TestRIG greatly increases debugging efficiency.
In-memory test suites require a significant amount of boiler plate in order to construct a valid test state which cannot be automatically reduced without disturbing instruction layout in complex ways.
As TestRIG relies on direct instruction injection, bypassing fetch through PC, a sequence of instructions can easily be shortened by simply eliminating instructions from the trace to see if we still find divergence.
As a result we can expect automatically reduced counterexamples on the order of a handful of instructions.

We hope that TestRIG will prove fertile ground to inspire innovation in instruction trace generation, counterexample reduction, and model construction such that trace-based verification can approach formal verification for many practical purposes with a much friendlier user experience than either test-suite verification or formal verification currently enable.

## Vengines
A vengine typically includes instruction trace (itrace) generators targeting various classes of behaviour.
The vengine then feeds these itraces into both a model and an implementation through two TCP sockets in the RVFI-DII format.
The model and implementation return an RVFI-DII execution trace (etrace) that details the state observation and state change of each instruction.
The vengine compares these two traces and identifies any divergence between the model and the implementation.
Any failure is reported nicely to the user with a means of conveniently replaying the failing itrace for debugging.
A capable vengine will also attempt to reduce the failing trace to a minimal example that diverges.

## Implementations (including Models)
Any implementation that wants to be verified using TestRIG will need to support RVFI-DII itrace format as an instruction source and etrace reporting format.
The implementation should have a mode where instructions are consumed exclusively from the RVFI-DII instruction port, bypassing any actual instruction memory, ignoring the architectural program counter.
An implementation should then deliver a trace report at the end of execution detailing implementation behaviour in response to that instruction in the RVFI-DII format.
The RVFI-DII communication uses a single socket with the itrace consumed and the etrace be delivered over the same socket. Please look at [the RVFI-DII](https://github.com/CTSRD-CHERI/TestRIG/blob/master/RVFI-DII.md) specification for more details

Currently, the provided modules are:
- [BSV-RVFI-DII](https://github.com/CTSRD-CHERI/BSV-RVFI-DII.git)
- [RVBS](https://github.com/CTSRD-CHERI/RVBS.git)
- [CHERI Spike](https://github.com/CTSRD-CHERI/riscv-isa-sim.git)
- [Sail RISC-V model](https://github.com/rems-project/sail-riscv.git)
- [CHERI Sail RISC-V model](https://github.com/CTSRD-CHERI/sail-cheri-riscv.git)
- [Piccolo](https://github.com/CTSRD-CHERI/Piccolo.git)
- [Flute](https://github.com/CTSRD-CHERI/Flute.git)
- [Toooba](https://github.com/CTSRD-CHERI/Toooba.git)
- [Ibex](https://github.com/CTSRD-CHERI/ibex.git)
- [QEMU](https://github.com/CTSRD-CHERI/qemu.git)

## Getting started

In order to get the different submodules provided by **TestRIG**, run the following command:

```sh
$ git submodule update --init --recursive
```

The root makefile can currently build the QuickCheck Verification Engine, Spike, and the Sail implementation. Both Spike and Sail are built without CHERI support by default and Sail is built as a 32-bit version.

### Dependencies
The dependencies for the QuickCheck Verification Engine are `cabal` and `ghc`, both of which you can install using [GHCup](https://www.haskell.org/ghcup/).
For `cabal` you must install version 3.4 or later to use the `list-bin` command.

The dependencies for Spike are:
- `sudo apt-get install device-tree-compiler`

The dependencies for RVBS are the Bluespec compiler `bsc`. You can follow the build instructions on the [B-Lang-org github](https://github.com/B-Lang-org/bsc).

The dependencies for the Sail model can be installed using
[opam](http://opam.ocaml.org/) by following the instructions from the
[Sail wiki](https://github.com/rems-project/sail/blob/sail2/INSTALL.md). You may have to run `opam update` and `opam upgrade` occasionally if sail gets updated.

The dependencies for Ibex are verilator:
- `sudo apt-get install verilator`

Toooba depends on the Bluespec compiler (see the dependencies for RVBS) and verilator. Toooba needs the version of verilator to be greater than: `Verilator 3.922 2018-03-17 rev verilator_3_920-32-gdf3d1a4`

### Default Configuration

You can verify a default configuration by executing:
```sh
$ make
$ utils/scripts/runTestRIG.py
```

## Custom Configurations
Look at the `Makefile` to see different targets to compare against each other. Also use the following command to figure out the different options for running TestRIG:

```sh
$ utils/scripts/runTestRIG.py --help
```

### 64-bit: Sail vs Toooba
Executing the following commands will compare Sail and Toooba with the 64-bit version of the RISC-V instruction set, assuming that you've initialized the submodules and have installed all the dependencies described above.
```sh
$ make vengines
$ make sail-rv64
$ make toooba-rv64
$ utils/scripts/runTestRIG.py -a sail -b toooba -r rv64i
```

### CHERI 32-bit: Sail vs Ibex
Executing the following commands will compare Sail and Ibex with the 32-bit version of the RISC-V instruction set (including compressed) and CHERI extensions enabled, assuming that you've initialized the submodules and have installed all the dependencies described above.
```sh
$ make vengines
$ make sail-rv32-cheri
$ make ibex-rv32ic-cheri
$ utils/scripts/runTestRIG.py -a sail -b ibex -r rv32icxcheri
```
