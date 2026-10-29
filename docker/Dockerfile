# The CHERI QEMU 10.2 port with its TestRIG gate and every reference the gate
# compares against, built from the pinned commits below (the 10.2 baseline of
# 2026-10-23, reports/baseline-10.2 in the CAPSTONE tree). See README.md.
#
#   docker build -t cheri-qemu-gate:10.2 docker/
#
# The layout under /home/researcher/Projects/CAPSTONE is the one
# utils/gate-profiles/full.conf expects, so the gate runs unchanged.
FROM ubuntu:26.04@sha256:c098726dd9b9733f3e885f8de0ef375206a311b0a317eadc40d347b1115fb944

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential git ca-certificates curl xz-utils bzip2 unzip rsync patch \
      python3 python3-venv python3-pip ninja-build pkg-config flex bison \
      libglib2.0-dev libpixman-1-dev zlib1g-dev libfdt-dev \
      gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu \
      opam m4 z3 libgmp-dev libffi-dev libncurses-dev libnuma-dev \
    && rm -rf /var/lib/apt/lists/*

# The image's own uid-1000 user is replaced by one with the expected home.
RUN userdel -r ubuntu 2>/dev/null; useradd -m -s /bin/bash -u 1000 researcher
COPY fetch-rev.sh /usr/local/bin/fetch-rev
USER researcher
ENV C=/home/researcher/Projects/CAPSTONE
WORKDIR /home/researcher

# Toolchains (the versions the baseline was run with).
RUN curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | \
      BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_MINIMAL=1 sh \
    && . ~/.ghcup/env && ghcup install ghc 9.6.7 && ghcup install cabal 3.16.1.0 \
    && ghcup set cabal 3.16.1.0 && ghcup gc --cache --tmpdirs
RUN opam init -y --bare --disable-sandboxing \
    && opam switch create -y sail ocaml-base-compiler.5.2.1 \
    && opam install -y --switch=sail sail.0.18 \
    && opam clean -y -a -c -s --logs
# meson 1.2.3 for the QEMU 7.x builds; pytest for the Morello harness.
RUN python3 -m venv --system-site-packages $C/.venv \
    && $C/.venv/bin/pip install --no-cache-dir meson==1.2.3 pytest==9.0.2 pytest-xdist

# TestRIG gate, QuickCheckVEngine and the Sail CHERI-RISC-V model.
ARG TESTRIG_REV=10305796c054cf7a6ab47d112f211b30a3b13cb1
RUN fetch-rev https://github.com/WyattVO/TestRIG-cheri-qemu.git $TESTRIG_REV $C/TestRig-AI/TestRIG-cheri-qemu \
    && cd $C/TestRig-AI/TestRIG-cheri-qemu \
    && git submodule update --init --recursive --depth 1 \
         vengines/QuickCheckVEngine riscv-implementations/sail-cheri-riscv
COPY --chown=researcher QCVEngine.cabal.project.freeze \
     $C/TestRig-AI/TestRIG-cheri-qemu/vengines/QuickCheckVEngine/cabal.project.freeze
RUN cd $C/TestRig-AI/TestRIG-cheri-qemu/vengines/QuickCheckVEngine \
    && . ~/.ghcup/env && cabal update && cabal build -w ghc-9.6.7 \
    && rm -rf ~/.cache/cabal/packages
RUN cd $C/TestRig-AI/TestRIG-cheri-qemu \
    && git -C riscv-implementations/sail-cheri-riscv apply ../../utils/patches/sail-riscv-rvfi-reset-reservation.patch \
    && eval $(opam env --switch=sail) \
    && make -j$(nproc) -C riscv-implementations/sail-cheri-riscv C_WARNINGS=-std=gnu17 c_emulator/cheri_riscv_rvfi_RV64

ARG QEMU_FLAGS="--disable-werror --disable-docs --disable-vnc --disable-sdl --disable-gtk \
  --disable-opengl --disable-kvm --disable-xen --disable-capstone \
  --disable-linux-user --disable-bsd-user --disable-slirp"

# The CHERI QEMU 10.2 port: RISC-V with RVFI-DII (the QEMU under test) and Morello.
ARG PORT_REV=da1a391963420237c6bc992fe9ca47d593d24c10
RUN fetch-rev https://github.com/WyattVO/cheri-qemu-port.git $PORT_REV $C/cheri-qemu-AI/cheri-qemu-10.2 \
    && cd $C/cheri-qemu-AI/cheri-qemu-10.2 \
    && mkdir build && cd build \
    && ../configure --target-list=riscv64xcheri-softmmu,riscv64cheristd-softmmu \
         --enable-rvfi-dii --disable-rust $QEMU_FLAGS && ninja \
    && mkdir ../build-morello && cd ../build-morello \
    && ../configure --target-list=morello-softmmu --disable-rust $QEMU_FLAGS && ninja

# The port's MTTCG branch (cheri-10.2-mttcg: the lock_tag series, RISC-V only),
# tested with utils/gate-profiles/full-mttcg.conf (capstone-gate --mttcg).
ARG MTTCG_REV=adb99fe38d4ed8adbd30d4a0a1164c2ccc9ec399
RUN fetch-rev https://github.com/WyattVO/cheri-qemu-port.git $MTTCG_REV $C/cheri-qemu-AI/cheri-qemu-10.2-mttcg \
    && cd $C/cheri-qemu-AI/cheri-qemu-10.2-mttcg \
    && mkdir build && cd build \
    && ../configure --target-list=riscv64xcheri-softmmu \
         --enable-rvfi-dii --disable-rust $QEMU_FLAGS && ninja

# CHERI-QEMU 7.1 with RVFI-DII, for the gate self-test (stage 2b).
ARG SELFTEST_REV=744bf35150bd33f09f4b9857b903cef5f14bc862
RUN fetch-rev https://github.com/WyattVO/cheri-qemu-port.git $SELFTEST_REV $C/cheri-qemu-AI/cheri-qemu-port \
    && cd $C/cheri-qemu-AI/cheri-qemu-port \
    && git submodule update --init --depth 1 dtc meson ui/keycodemapdb \
         tests/fp/berkeley-softfloat-3 tests/fp/berkeley-testfloat-3 \
    && mkdir build && cd build \
    && ../configure --meson=$C/.venv/bin/meson --target-list=riscv64xcheri-softmmu,riscv64cheristd-softmmu \
         --enable-rvfi-dii --disable-rdma $QEMU_FLAGS && ninja

# CHERI-Alliance QEMU main (7.2) with RVFI-DII, the second CHERI reference (stage 4b).
ARG ALLIANCE_REV=937b306b8b1288d0dd16e04be85ffa29ceb0c6d3
RUN fetch-rev https://github.com/CHERI-Alliance/qemu.git $ALLIANCE_REV $C/refs/alliance-qemu \
    && cd $C/refs/alliance-qemu \
    && git submodule update --init --depth 1 dtc meson ui/keycodemapdb \
         tests/fp/berkeley-softfloat-3 tests/fp/berkeley-testfloat-3 \
    && mkdir build && cd build \
    && ../configure --meson=$C/.venv/bin/meson --target-list=riscv64xcheri-softmmu \
         --enable-rvfi-dii --disable-rdma $QEMU_FLAGS && ninja

# Upstream QEMU v10.2.0 with plugins and its RISC-V check-tcg tests (stage 6).
ARG UPSTREAM_REV=698104725efad4b29079d857dfdebbd804e34c99
RUN fetch-rev https://github.com/qemu/qemu.git $UPSTREAM_REV $C/refs/upstream-qemu-10.2 \
    && cd $C/refs/upstream-qemu-10.2 \
    && mkdir build && cd build \
    && ../configure --target-list=riscv64-softmmu --enable-plugins --disable-rust \
         --cross-prefix-riscv64=riscv64-linux-gnu- $QEMU_FLAGS \
    && ninja && ninja contrib-plugins && make check-tcg

# Test suites: riscv-arch-test 3.9.1 (stage 6) and the Morello generated tests.
RUN fetch-rev https://github.com/riscv-non-isa/riscv-arch-test.git \
      eb66181dd27ff7847e2c3a010705b13490b0bf75 $C/refs/riscv-arch-test \
    && fetch-rev https://github.com/rems-project/morello-generated-tests.git \
      e30a1c6f1db43d32ea684fe51498d31de2e5d97e $C/refs/morello-generated-tests

ENV PATH=/home/researcher/.ghcup/bin:$PATH
# Last, so that changing them does not rebuild everything above.
COPY capstone-gate capstone-morello /usr/local/bin/
RUN mkdir -p /home/researcher/results
WORKDIR /home/researcher/results
CMD ["bash"]
