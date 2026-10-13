#!/usr/bin/env bash
# TestRIG regression gate for CHERI QEMU (RISC-V, Xcheri v9).
#
# Compares a QEMU build against the Sail CHERI-RISC-V golden model over
# RVFI-DII, in two stages:
#   1. Replay every saved counter-example under regressions/ (bugs that were
#      found and fixed must stay fixed).
#   2. Run every QuickCheckVEngine template with fresh random tests.
# Exits non-zero if either stage reports a mismatch.
#
# Usage: testrig-gate.sh <path/to/qemu-system-riscv64xcheri> [tests-per-template]
#
# Environment:
#   EXCLUDE   regex of templates to skip (default: ^cclear$, see regressions/README.md)
#   ARCH      TestRIG architecture string (default: rv64imcxcheri)
#   QCVENGINE path to the QCVEngine binary (default: newest cabal build)
set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
qemu=${1:?usage: $0 <qemu-system-riscv64xcheri> [tests-per-template]}
ntests=${2:-100}
arch=${ARCH:-rv64imcxcheri}
exclude=${EXCLUDE:-^cclear\$}
qcv=${QCVENGINE:-$(find "$root/vengines/QuickCheckVEngine/dist-newstyle" -type f \
    -name QCVEngine -perm -u+x 2>/dev/null | head -1)}

[ -x "$qemu" ] || { echo "error: $qemu is not executable" >&2; exit 2; }
[ -n "$qcv" ] && [ -x "$qcv" ] || { echo "error: QCVEngine not built (cabal build)" >&2; exit 2; }

run() {
  python3 "$here/runTestRIG.py" -a sail -b qemu --path-to-qemu "$qemu" \
    --path-to-QCVEngine "$qcv" -r "$arch" --support-misaligned --no-save -s 2 "$@"
}

status=0
for dir in "$root"/regressions/*/; do
  echo "=== Replaying saved regressions: ${dir#$root/}"
  run -d "$dir" || status=1
done

echo "=== Random tests: $ntests per template (excluding: $exclude)"
run -n "$ntests" --test-exclude-regex "$exclude" || status=1

if [ $status -eq 0 ]; then
  echo "TESTRIG GATE: PASS"
else
  echo "TESTRIG GATE: FAIL"
fi
exit $status
