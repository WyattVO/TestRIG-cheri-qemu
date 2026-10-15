#!/usr/bin/env bash
# TestRIG regression gate for CHERI QEMU (RISC-V, Xcheri v9).
#
# Compares a QEMU build against the Sail CHERI-RISC-V golden model over
# RVFI-DII, in four stages:
#   1. Check that QEMU refuses CPU extensions that bypass CHERI protection
#      (see regressions/README.md) and still starts with the default CPUs.
#   2. Replay every saved counter-example under regressions/ (bugs that were
#      found and fixed must stay fixed).
#   3. Run the bare-metal tests in regressions/qemu-only, which check CHERI
#      properties of QEMU features the Sail model lacks (needs CROSS_CC or
#      riscv64-linux-gnu-gcc; skipped with a warning if missing).
#   4. Run every QuickCheckVEngine template with fresh random tests.
# Exits non-zero if any stage fails.
#
# Usage: testrig-gate.sh <path/to/qemu-system-riscv64xcheri> [tests-per-template]
#
# Environment:
#   EXCLUDE   regex of templates to skip (default: none)
#   ARCH      TestRIG architecture string
#             (default: rv64imsafdcZicsr_Zifencei_Xcheri)
#   CSR_EXCLUDE  regex of CSR names the csr template skips (default: CSRs
#             where the Sail model differs for reasons unrelated to QEMU,
#             see regressions/README.md)
#   QEMU_CPU_EXTRA  extra QEMU -cpu properties (default: the B extensions,
#             which the Sail model always implements)
#   QCVENGINE path to the QCVEngine binary (default: newest cabal build)
#   CROSS_CC  RISC-V cross compiler for the QEMU-only tests
set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
qemu=${1:?usage: $0 <qemu-system-riscv64xcheri> [tests-per-template]}
ntests=${2:-100}
arch=${ARCH:-rv64imsafdcZicsr_Zifencei_Xcheri}
csr_exclude=${CSR_EXCLUDE-^(misa|mstatus|sstatus|mscratch|sscratch|mip|mie|mideleg|medeleg|sccsr|mhpmevent[0-9]+|m?cycleh?|m?instreth?|timeh?|m?hpmcounter[0-9]+h?|reserved)\$}
exclude=${EXCLUDE:-}
cpu_extra=${QEMU_CPU_EXTRA-zba=true,zbb=true,zbc=true,zbs=true}
qcv=${QCVENGINE:-$(find "$root/vengines/QuickCheckVEngine/dist-newstyle" -type f \
    -name QCVEngine -perm -u+x 2>/dev/null | head -1)}

[ -x "$qemu" ] || { echo "error: $qemu is not executable" >&2; exit 2; }
[ -n "$qcv" ] && [ -x "$qcv" ] || { echo "error: QCVEngine not built (cabal build)" >&2; exit 2; }

run() {
  python3 "$here/runTestRIG.py" -a sail -b qemu --path-to-qemu "$qemu" \
    --path-to-QCVEngine "$qcv" -r "$arch" --support-misaligned --no-save -s 2 \
    ${cpu_extra:+--qemu-cpu-extra "$cpu_extra"} \
    ${csr_exclude:+--csr-exclude-regex "$csr_exclude"} "$@"
}

# Start QEMU with the given -cpu value for a moment. Prints "started" if it is
# still running after 3 seconds, "refused" if it exited because of the CHERI
# extension policy, "rejected" if it exited with any other error message, and
# "crashed" if it died from a signal (e.g. a failed assertion).
qemu_start() {
  local out rc
  out=$(timeout 3 "$qemu" -machine virt -cpu "$1" -bios none -S -display none \
    -monitor none -serial none 2>&1)
  rc=$?
  if [ $rc -eq 124 ]; then
    echo started
  elif [ $rc -gt 128 ]; then
    echo crashed
  elif grep -q "is not supported on CHERI CPUs" <<<"$out"; then
    echo refused
  else
    echo rejected
  fi
}

# expect <started|refused|rejected> <cpu> <description>
expect() {
  local got
  got=$(qemu_start "$2")
  if [ "$got" = "$1" ]; then
    echo "ok: -cpu $2 $1 ($3)"
  else
    echo "FAIL: -cpu $2 $got, expected $1 ($3)"; status=1
  fi
}

status=0
echo "=== CHERI extension policy"
for ext in v h zve32x zvbb smnpm ssnpm supm svrsw60t59b zcmt smrnmi zicfiss \
    zicfilp; do
  expect refused "rv64,$ext=true" "bypasses capability checks"
done
# Bare and profile CPUs set up CHERI late; the policy must still apply.
expect refused "rv64i,v=true" "bare CPU"
expect refused rva23u64 "profile requires vector"
for cpu in rv64 max rva22u64 codasip-a730; do
  expect started "$cpu" "unsafe extensions disabled"
done
# 128-bit capabilities are RV64-only.
for cpu in rv32 codasip-l730; do
  expect rejected "$cpu" "RV32 CPU in a 64-bit CHERI build"
done

for dir in "$root"/regressions/*/; do
  [ "$(basename "$dir")" = qemu-only ] && continue
  echo "=== Replaying saved regressions: ${dir#$root/}"
  # Keep going after a failure so one regression doesn't hide another.
  run -d "$dir" --continue-on-fail || status=1
done

echo "=== QEMU-only tests"
if command -v "${CROSS_CC:-riscv64-linux-gnu-gcc}" >/dev/null; then
  "$here/qemu-only-tests.sh" "$qemu" || status=1
else
  echo "WARNING: no RISC-V cross compiler; skipping (set CROSS_CC)"
fi

echo "=== Random tests: $ntests per template (excluding: ${exclude:-none})"
run -n "$ntests" ${exclude:+--test-exclude-regex "$exclude"} || status=1

if [ $status -eq 0 ]; then
  echo "TESTRIG GATE: PASS"
else
  echo "TESTRIG GATE: FAIL"
fi
exit $status
