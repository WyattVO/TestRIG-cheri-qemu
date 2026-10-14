#!/usr/bin/env bash
# TestRIG regression gate for CHERI QEMU (RISC-V, Xcheri v9).
#
# Compares a QEMU build against the Sail CHERI-RISC-V golden model over
# RVFI-DII, in three stages:
#   1. Check that QEMU refuses CPU extensions that bypass CHERI protection
#      (see regressions/README.md) and still starts with the default CPUs.
#   2. Replay every saved counter-example under regressions/ (bugs that were
#      found and fixed must stay fixed).
#   3. Run every QuickCheckVEngine template with fresh random tests.
# Exits non-zero if any stage fails.
#
# Usage: testrig-gate.sh <path/to/qemu-system-riscv64xcheri> [tests-per-template]
#
# Environment:
#   EXCLUDE   regex of templates to skip (default: none)
#   ARCH      TestRIG architecture string (default: rv64imacZifencei_Xcheri)
#   QEMU_CPU_EXTRA  extra QEMU -cpu properties (default: the B extensions,
#             which the Sail model always implements)
#   QCVENGINE path to the QCVEngine binary (default: newest cabal build)
set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
qemu=${1:?usage: $0 <qemu-system-riscv64xcheri> [tests-per-template]}
ntests=${2:-100}
arch=${ARCH:-rv64imacZifencei_Xcheri}
exclude=${EXCLUDE:-}
cpu_extra=${QEMU_CPU_EXTRA-zba=true,zbb=true,zbc=true,zbs=true}
qcv=${QCVENGINE:-$(find "$root/vengines/QuickCheckVEngine/dist-newstyle" -type f \
    -name QCVEngine -perm -u+x 2>/dev/null | head -1)}

[ -x "$qemu" ] || { echo "error: $qemu is not executable" >&2; exit 2; }
[ -n "$qcv" ] && [ -x "$qcv" ] || { echo "error: QCVEngine not built (cabal build)" >&2; exit 2; }

run() {
  python3 "$here/runTestRIG.py" -a sail -b qemu --path-to-qemu "$qemu" \
    --path-to-QCVEngine "$qcv" -r "$arch" --support-misaligned --no-save -s 2 \
    ${cpu_extra:+--qemu-cpu-extra "$cpu_extra"} "$@"
}

# Start QEMU with the given -cpu value for a moment. Prints "started" if it is
# still running after 3 seconds, "refused" if it exited because of the CHERI
# extension policy, and "error" if it exited for any other reason.
qemu_start() {
  local out
  out=$(timeout 3 "$qemu" -machine virt -cpu "$1" -bios none -S -display none \
    -monitor none -serial none 2>&1)
  if [ $? -eq 124 ]; then
    echo started
  elif grep -q "is not supported on CHERI CPUs" <<<"$out"; then
    echo refused
  else
    echo error
  fi
}

status=0
echo "=== CHERI extension policy"
for ext in v zve32x zvbb smnpm ssnpm supm svrsw60t59b zcmt smrnmi; do
  if [ "$(qemu_start "rv64,$ext=true")" = refused ]; then
    echo "ok: $ext=true is refused on a CHERI CPU"
  else
    echo "FAIL: $ext=true was accepted on a CHERI CPU"; status=1
  fi
done
for cpu in rv64 max; do
  if [ "$(qemu_start "$cpu")" = started ]; then
    echo "ok: -cpu $cpu starts (unsafe extensions disabled)"
  else
    echo "FAIL: -cpu $cpu does not start"; status=1
  fi
done

for dir in "$root"/regressions/*/; do
  echo "=== Replaying saved regressions: ${dir#$root/}"
  run -d "$dir" || status=1
done

echo "=== Random tests: $ntests per template (excluding: ${exclude:-none})"
run -n "$ntests" ${exclude:+--test-exclude-regex "$exclude"} || status=1

if [ $status -eq 0 ]; then
  echo "TESTRIG GATE: PASS"
else
  echo "TESTRIG GATE: FAIL"
fi
exit $status
