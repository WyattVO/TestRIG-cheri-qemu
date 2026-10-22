#!/usr/bin/env bash
# TestRIG regression gate for CHERI QEMU (RISC-V, Xcheri v9).
#
# Compares a QEMU build against the Sail CHERI-RISC-V golden model over
# RVFI-DII, in four stages, and optionally boots CheriBSD on it:
#   1. Check that QEMU refuses CPU extensions that bypass CHERI protection
#      (see regressions/README.md) and still starts with the default CPUs.
#      Also check that every CPU extension QEMU offers has been reviewed for
#      CHERI (regressions/cheri-extensions.txt, cheri-ext-review.py), so a
#      QEMU rebase cannot enable a new extension silently.
#   2. Replay every saved counter-example under regressions/ (bugs that were
#      found and fixed must stay fixed, cheri-guards/ pins CHERI behaviour a
#      rebase is likely to change). regressions/open-bugs/ holds traces of
#      known, unfixed bugs: each must still fail (reported, not fatal); one
#      that passes is reported as XPASS and should move to cheri-qemu-10.2/.
#   3. Run the bare-metal tests in regressions/qemu-only, which check CHERI
#      properties of QEMU features the Sail model lacks (needs CROSS_CC or
#      riscv64-linux-gnu-gcc; skipped with a warning if missing).
#   4. Run every QuickCheckVEngine template with fresh random tests (seeded;
#      the seed is printed, rerun with SEED=<n>). Failures are shrunk and
#      saved to SAVE_DIR as ready-made regression traces. Then check that
#      the CHERI instructions really ran (coverage-check.py against
#      regressions/coverage-required.txt).
#   4b. If ALLIANCE_QEMU is set, a three-way vote: random tests of
#      CHERI-Alliance QEMU against this QEMU, each disagreement replayed on
#      Sail to find the odd one out (three-way-vote.py).
#   5. If CHERIBSD_OUTPUT is set, boot CheriBSD and run cheribsdtest-purecap
#      and cheribsdtest-hybrid (utils/scripts/cheribsd-tests.py, ~30 min).
#   6. If UPSTREAM_BUILD is set, compare with unmodified upstream QEMU on
#      non-CHERI code: upstream's own check-tcg and qtests run on this QEMU
#      (upstream-tests.sh), and riscv-arch-test (ARCH_TEST) must give the
#      same signatures and instruction traces on both (upstream-diff.py).
# Exits non-zero if any stage fails.
#
# Usage: testrig-gate.sh <path/to/qemu-system-riscv64xcheri> [tests-per-template]
#
# Environment:
#   EXCLUDE   regex of templates to skip (default: fpclear, an open bug:
#             regressions/open-bugs/01-fpclear-not-implemented.S)
#   SEED      seed for the random tests (default: from the clock)
#   SAVE_DIR  where failing random tests are saved (default: random-failures/)
#   ARCH      TestRIG architecture string
#             (default: rv64imsafdcZicsr_Zifencei_Xcheri)
#   CSR_EXCLUDE  regex of CSR names the csr template skips (default: CSRs
#             where the Sail model differs for reasons unrelated to QEMU,
#             see regressions/README.md)
#   QEMU_CPU_EXTRA  extra QEMU -cpu properties (default: the B extensions,
#             which the Sail model always implements)
#   QCVENGINE path to the QCVEngine binary (default: newest cabal build)
#   CROSS_CC  RISC-V cross compiler for the QEMU-only tests
#   CHERIBSD_OUTPUT  cheribuild output directory with a riscv64-purecap
#             CheriBSD disk image (default: unset, stage 5 skipped)
#   CHERIBSD_SMP  number of harts CheriBSD boots with (default: 1)
#   ALLIANCE_QEMU  CHERI-Alliance qemu-system-riscv64xcheri with RVFI-DII
#             (default: unset, stage 4b skipped)
#   VOTE_TESTS  random tests per template in stage 4b (default: tests-per-template)
#   UPSTREAM_BUILD  build directory of upstream QEMU v10.2.0 (riscv64-softmmu,
#             --enable-plugins; default: unset, stage 6 skipped)
#   ARCH_TEST  riscv-arch-test checkout (default: unset, upstream-diff.py skipped)
set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
qemu=${1:?usage: $0 <qemu-system-riscv64xcheri> [tests-per-template]}
ntests=${2:-100}
arch=${ARCH:-rv64imsafdcZicsr_Zifencei_Xcheri}
csr_exclude=${CSR_EXCLUDE-^(misa|mstatus|sstatus|mscratch|sscratch|mip|mie|mideleg|medeleg|sccsr|mhpmevent[0-9]+|m?cycleh?|m?instreth?|timeh?|m?hpmcounter[0-9]+h?|reserved)\$}
exclude=${EXCLUDE-^fpclear\$}
seed=${SEED:-$(( $(date +%s) % 1000000000 ))}
save_dir=${SAVE_DIR:-$root/random-failures}
cpu_extra=${QEMU_CPU_EXTRA-zba=true,zbb=true,zbc=true,zbs=true}
qcv=${QCVENGINE:-$(find "$root/vengines/QuickCheckVEngine/dist-newstyle" -type f \
    -name QCVEngine -perm -u+x 2>/dev/null | head -1)}

[ -x "$qemu" ] || { echo "error: $qemu is not executable" >&2; exit 2; }
[ -n "$qcv" ] && [ -x "$qcv" ] || { echo "error: QCVEngine not built (cabal build)" >&2; exit 2; }

rig() {
  python3 "$here/runTestRIG.py" -a sail -b qemu --path-to-qemu "$qemu" \
    --path-to-QCVEngine "$qcv" -r "$arch" --support-misaligned -s 2 \
    ${cpu_extra:+--qemu-cpu-extra "$cpu_extra"} \
    ${csr_exclude:+--csr-exclude-regex "$csr_exclude"} "$@"
}
run() { rig --no-save "$@"; }

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

# expect <started|refused|rejected|not-started> <cpu> <description>
# ("not-started": refused or rejected, e.g. a property this QEMU lacks)
expect() {
  local got
  got=$(qemu_start "$2")
  if [ "$got" = "$1" ] || { [ "$1" = not-started ] &&
      { [ "$got" = refused ] || [ "$got" = rejected ]; }; }; then
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
# Capabilities have one little-endian memory format; QEMU 11 adds big-endian
# harts (10.2 has no such property and rejects it).
expect not-started "rv64,big-endian=true" "big-endian data accesses"
# New extensions (e.g. QEMU 11's Zalasr, Zilsd, Xmipslsp) fail here until
# they are reviewed for CHERI.
python3 "$here/cheri-ext-review.py" "$qemu" || status=1

for dir in "$root"/regressions/*/; do
  case $(basename "$dir") in qemu-only|open-bugs) continue ;; esac
  echo "=== Replaying saved regressions: ${dir#$root/}"
  # Keep going after a failure so one regression doesn't hide another.
  run -d "$dir" --continue-on-fail || status=1
done

echo "=== Known open bugs (must still fail): regressions/open-bugs"
for trace in "$root"/regressions/open-bugs/*.S; do
  [ -e "$trace" ] || continue
  if run -t "$trace" >/dev/null 2>&1; then
    echo "XPASS: ${trace#$root/} passes now; move it to regressions/cheri-qemu-10.2/"
  else
    echo "xfail: ${trace#$root/}"
  fi
done

echo "=== QEMU-only tests"
if command -v "${CROSS_CC:-riscv64-linux-gnu-gcc}" >/dev/null; then
  "$here/qemu-only-tests.sh" "$qemu" || status=1
else
  echo "WARNING: no RISC-V cross compiler; skipping (set CROSS_CC)"
fi

echo "=== Random tests: $ntests per template (excluding: ${exclude:-none}, seed $seed)"
mkdir -p "$save_dir"
stats=$save_dir/stats-$seed.txt
rig -n "$ntests" --seed "$seed" -S "$save_dir" --continue-on-fail \
  --stats-file "$stats" ${exclude:+--test-exclude-regex "$exclude"} || status=1
if ls "$save_dir"/failure-*.S >/dev/null 2>&1; then
  echo "FAIL: failing random tests saved in ${save_dir#$root/}/ (rerun with SEED=$seed)"
  status=1
fi
echo "=== Coverage of the random tests"
python3 "$here/coverage-check.py" "$stats" || status=1

if [ -n "${ALLIANCE_QEMU:-}" ]; then
  echo "=== Three-way vote: Sail, CHERI-Alliance QEMU, this QEMU (seed $seed)"
  vote_dir=$save_dir/vote-$seed
  rm -rf "$vote_dir"
  python3 "$here/three-way-vote.py" --port "$qemu" --alliance "$ALLIANCE_QEMU" \
    --qcvengine "$qcv" --arch "$arch" --out "$vote_dir" --seed "$seed" \
    -n "${VOTE_TESTS:-$ntests}" ${cpu_extra:+--cpu-extra "$cpu_extra"} \
    ${csr_exclude:+--csr-exclude-regex "$csr_exclude"} \
    ${exclude:+--test-exclude-regex "$exclude"} || status=1
fi

if [ -n "${CHERIBSD_OUTPUT:-}" ]; then
  echo "=== CheriBSD tests"
  python3 "$here/cheribsd-tests.py" "$qemu" "$CHERIBSD_OUTPUT" \
    --smp "${CHERIBSD_SMP:-1}" --log "${CHERIBSD_LOG:-cheribsd-tests.log}" || status=1
fi

if [ -n "${UPSTREAM_BUILD:-}" ]; then
  echo "=== Upstream QEMU: upstream's own tests on this QEMU"
  "$here/upstream-tests.sh" "$UPSTREAM_BUILD" "$qemu" || status=1
  if [ -n "${ARCH_TEST:-}" ]; then
    echo "=== Upstream QEMU: riscv-arch-test signatures and traces"
    python3 "$here/upstream-diff.py" --upstream "$UPSTREAM_BUILD/qemu-system-riscv64" \
      --port "$qemu" --arch-test "$ARCH_TEST" --out "$save_dir/upstream-diff" || status=1
  fi
fi

if [ $status -eq 0 ]; then
  echo "TESTRIG GATE: PASS"
else
  echo "TESTRIG GATE: FAIL"
fi
exit $status
