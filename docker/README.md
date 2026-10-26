# CHERI QEMU 10.2 gate in a container

This image holds the CHERI QEMU 10.2 port and everything the TestRIG gate
compares it against. Each part is built from a pinned commit:

| Part | Commit | Gate stage |
|---|---|---|
| CHERI QEMU 10.2 port, RISC-V with RVFI-DII and Morello ([cheri-qemu-port](https://github.com/WyattVO/cheri-qemu-port/tree/cheri-10.2)) | `da1a391963` | under test |
| TestRIG gate ([TestRIG-cheri-qemu](https://github.com/WyattVO/TestRIG-cheri-qemu/tree/testrig-cheri-qemu-10.2)), QuickCheckVEngine `3fdf0a91bf` | `1fc4b27` | all |
| Sail CHERI-RISC-V model `74a9da1f78` (Sail 0.18, OCaml 5.2.1), with `utils/patches/sail-riscv-rvfi-reset-reservation.patch` | | 2, 4 |
| CHERI-QEMU 7.1, the gate self-test | `744bf35150` | 2b |
| CHERI-Alliance QEMU main (7.2) | `937b306b8b` | 2, 4, 4b |
| Upstream QEMU v10.2.0 | `698104725e` | 6 |
| riscv-arch-test 3.9.1 | `eb66181` | 6 |
| morello-generated-tests | `e30a1c6` | Morello |

These are the commits of the 10.2 baseline, which passed every stage on
2026-10-23. CheriBSD (stage 5) is not part of the image because it is 13 GB.
To run stage 5, mount a cheribuild output directory (see below).

The image takes 16 GB of disk (about 3.3 GB of content) and about 25
minutes to build on 16 cores.
It is x86-64 only, because GHCup and the GHC binaries are downloaded for
x86-64.

## Build

From a clone of TestRIG-cheri-qemu:

    docker build -t cheri-qemu-gate:10.2 docker/

You can build a different commit of any part with `--build-arg`, for example
`--build-arg PORT_REV=<commit>`. The names are `TESTRIG_REV`, `PORT_REV`,
`SELFTEST_REV`, `ALLIANCE_REV` and `UPSTREAM_REV`.

## Run the gate

    mkdir results
    docker run --rm -it -v "$PWD/results:/home/researcher/results" \
        cheri-qemu-gate:10.2 capstone-gate

`capstone-gate` runs `utils/scripts/testrig-gate.sh` with
`utils/gate-profiles/full.conf` on the 10.2 port, at 100 tests per template.
It writes the logs and any failing tests into `results/`. With the baseline
seed, a full run takes several hours:

    docker run ... cheri-qemu-gate:10.2 env SEED=20261023 capstone-gate

`capstone-gate` accepts every option of the gate script (`capstone-gate
--help`). Some useful ones:

    capstone-gate --list                     # print which stages run, and exit
    capstone-gate --only policy,regressions,bench    # the quick stages
    capstone-gate --skip upstream <qemu>     # another QEMU, without stage 6

Below about 100 tests per template the coverage check can fail just because
the random tests never generated a rare instruction. At 10 tests,
`cinvoke completed 0 times` is typical. Add `--skip coverage` for short
runs.

The gate prints `TESTRIG GATE: PASS` or `FAIL`. A CHERI result counts as an
ERROR when this QEMU disagrees with both Sail and Alliance QEMU. It counts as
a WARNING when it disagrees with only one of them. The repository's
`README.md` and `TESTBENCH.md` explain every stage and test.

### With CheriBSD (stage 5)

Build CheriBSD for riscv64-purecap with
[cheribuild](https://github.com/CTSRD-CHERI/cheribuild), at commit
`88f39900c3` for the baseline. Then mount its output directory:

    docker run ... -v ~/cheri/output:/home/researcher/Projects/CAPSTONE/cheri/output:ro \
        cheri-qemu-gate:10.2 capstone-gate

The disk image is opened with `snapshot=on`, so a read-only mount works.
Without the mount, `capstone-gate` skips stage 5 and says so.

## Run the Morello tests

    docker run --rm cheri-qemu-gate:10.2 capstone-morello

The baseline result is 3393 passed and 2 skipped.

## Test your own QEMU

The image has every build dependency installed. Mount your QEMU source and
build it inside the container with `--enable-rvfi-dii`:

    docker run --rm -it -v "$PWD/my-qemu:/home/researcher/my-qemu" \
        -v "$PWD/results:/home/researcher/results" cheri-qemu-gate:10.2 bash
    cd ~/my-qemu && mkdir -p build && cd build
    ../configure --target-list=riscv64xcheri-softmmu --enable-rvfi-dii --disable-werror --disable-docs
    ninja
    cd ~/results && capstone-gate ~/my-qemu/build/qemu-system-riscv64xcheri 100

The container user has uid 1000. If your own uid is different, add
`--user $(id -u):$(id -g)` so that you can write to the mounted directories.

## Layout

Everything is under `/home/researcher/Projects/CAPSTONE`, in the layout
`full.conf` expects:

    TestRig-AI/TestRIG-cheri-qemu/        the gate, with QuickCheckVEngine and Sail built
    cheri-qemu-AI/cheri-qemu-10.2/build   the port (RISC-V), build-morello (Morello)
    cheri-qemu-AI/cheri-qemu-port/build   CHERI-QEMU 7.1
    refs/alliance-qemu/build              CHERI-Alliance QEMU
    refs/upstream-qemu-10.2/build         upstream QEMU v10.2.0
    refs/riscv-arch-test, refs/morello-generated-tests
    cheri/output                          CheriBSD, when mounted
