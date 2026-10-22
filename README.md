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
runs five stages and fails if any of them fails:

| Stage | What it checks |
|---|---|
| 1. CHERI extension policy | QEMU refuses extensions that bypass capability checks (vector, hypervisor, pointer masking, Zicfiss/Zicfilp, big-endian, ...) and still starts the normal CPUs; every extension it offers is listed as reviewed in `regressions/cheri-extensions.txt`, and no CPU model crashes it |
| 2. Saved regression traces | All 30 traces in `regressions/cheri-qemu-10.2/` (bugs that were found and fixed) and `regressions/cheri-guards/` replay without a difference from Sail. Traces of open bugs in `regressions/open-bugs/` must still fail |
| 3. QEMU-only bare-metal tests | 28 tests in `regressions/qemu-only/` for CHERI behaviour the Sail model lacks (CW/CD/CRM/CRG page bits and TLB flushes, PMP, `amocas`/Zabha/Zcb/Zfh/Zicbo* and T-Head instructions in integer and capability mode, PCC bounds in cached code, interrupts in capability mode, two-hart tag consistency, UXL, endianness) |
| 4. Random tests | Every QuickCheckVEngine template, comparing QEMU with Sail (36 templates; 7 that need hardware counters are skipped) |
| 5. CheriBSD (optional) | Boots CheriBSD and runs `cheribsdtest-purecap` and `cheribsdtest-hybrid`; any `FAIL` fails the gate |

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
unmodified.

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
- For stage 5, build CheriBSD with
  [cheribuild](https://github.com/CTSRD-CHERI/cheribuild):
  `./cheribuild.py -d disk-image-riscv64-purecap bbl-baremetal-riscv64-purecap`.
  The output goes to `~/cheri/output`.

**6. Run the gate**

```sh
QEMU=/path/to/cheri-qemu-port/build/qemu-system-riscv64xcheri
utils/scripts/testrig-gate.sh $QEMU 300                                    # stages 1-4
CHERIBSD_OUTPUT=~/cheri/output utils/scripts/testrig-gate.sh $QEMU 300     # plus CheriBSD
```

It ends with `TESTRIG GATE: PASS` or `FAIL`. Don't edit `testrig-gate.sh`
while it runs: bash reads the script as it goes. Environment variables
`EXCLUDE`, `ARCH`, `CSR_EXCLUDE`, `QEMU_CPU_EXTRA`, `QCVENGINE` and `CROSS_CC`
are described at the top of the script. `CHERIBSD_LOG` sets where the
CheriBSD console log is written (default `cheribsd-tests.log`).

### Smaller runs

```sh
QCV=$(find vengines/QuickCheckVEngine/dist-newstyle -type f -name QCVEngine -perm -u+x | head -1)
R="python3 utils/scripts/runTestRIG.py -a sail -b qemu --path-to-qemu $QEMU --path-to-QCVEngine $QCV \
   -r rv64imsafdcZicsr_Zifencei_Xcheri --support-misaligned --no-save -s 2 \
   --qemu-cpu-extra zba=true,zbb=true,zbc=true,zbs=true"
$R -n 50 --test-include-regex '^caparith$'                    # one template
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
