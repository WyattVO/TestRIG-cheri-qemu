#!/usr/bin/env bash
# Run the bare-metal tests in regressions/qemu-only on a CHERI QEMU binary.
#
# These check CHERI properties of QEMU features that the Sail model does not
# implement, so TestRIG cannot compare them. Each test exits through the virt
# machine's test device: exit status 0 is a pass, N is failed check N (99 is
# an unexpected trap). A "# QEMU_CPU: <cpu>" line selects the -cpu value
# (default rv64) and "# QEMU_SMP: <n>" the number of harts (default 1; the
# harts run round-robin, QEMU's default for CHERI), "# QEMU_ARGS: <args>" adds
# QEMU options (e.g. devices). A "# XFAIL: <reason>" line marks a known failure: it is
# reported but does not fail the run, and passing is reported as XPASS (then
# remove the line).
#
# Usage: qemu-only-tests.sh <path/to/qemu-system-riscv64xcheri>
#
# Environment:
#   CROSS_CC  RISC-V cross compiler (default: riscv64-linux-gnu-gcc)
#   BENCH_INCLUDE  regex of test names (file name without .S) to run
#   BENCH_EXCLUDE  regex of test names to skip
set -u

here=$(cd "$(dirname "$0")" && pwd)
dir=$(cd "$here/../../regressions/qemu-only" && pwd)
qemu=${1:?usage: $0 <qemu-system-riscv64xcheri>}
cc=${CROSS_CC:-riscv64-linux-gnu-gcc}

command -v "$cc" >/dev/null || { echo "error: $cc not found (set CROSS_CC)" >&2; exit 2; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

status=0
for src in "$dir"/*.S; do
  name=$(basename "$src" .S)
  if { [ -n "${BENCH_INCLUDE:-}" ] && ! [[ $name =~ $BENCH_INCLUDE ]]; } ||
     { [ -n "${BENCH_EXCLUDE:-}" ] && [[ $name =~ $BENCH_EXCLUDE ]]; }; then
    echo "skipped: $name"
    continue
  fi
  cpu=$(sed -n 's/^# QEMU_CPU: *//p' "$src" | head -1)
  xfail=$(sed -n 's/^# XFAIL: *//p' "$src" | head -1)
  smp=$(sed -n 's/^# QEMU_SMP: *//p' "$src" | head -1)
  args=$(sed -n 's/^# QEMU_ARGS: *//p' "$src" | head -1)
  if ! "$cc" -march=rv64gc -mabi=lp64 -nostdlib -nostartfiles -static \
      -I "$dir" -T "$dir/link.ld" -o "$tmp/$name.elf" "$src"; then
    echo "FAIL: $name does not assemble"; status=1; continue
  fi
  timeout 30 "$qemu" -machine virt -smp "${smp:-1}" -cpu "${cpu:-rv64}" -bios none \
    -kernel "$tmp/$name.elf" -display none -monitor none -serial none $args \
    >"$tmp/$name.log" 2>&1
  rc=$?
  if [ -n "$xfail" ]; then
    if [ $rc -eq 0 ]; then
      echo "XPASS: $name passes now; remove its XFAIL line ($xfail)"
    else
      echo "xfail: $name (exit $rc: $xfail)"
    fi
    continue
  fi
  case $rc in
    0)   echo "ok: $name" ;;
    124) echo "FAIL: $name timed out"; status=1 ;;
    99)  echo "FAIL: $name took an unexpected trap"; status=1 ;;
    *)   echo "FAIL: $name failed check $rc"; sed 's/^/  /' "$tmp/$name.log"
         status=1 ;;
  esac
done
exit $status
