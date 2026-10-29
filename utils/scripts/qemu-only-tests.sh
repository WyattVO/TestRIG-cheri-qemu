#!/usr/bin/env bash
# Run the bare-metal tests in regressions/qemu-only on a CHERI QEMU binary.
#
# These check CHERI properties of QEMU features that the Sail model does not
# implement, so TestRIG cannot compare them. Each test exits through the virt
# machine's test device: exit status 0 is a pass, N is failed check N (99 is
# an unexpected trap). A "# QEMU_CPU: <cpu>" line selects the -cpu value
# (default rv64) and "# QEMU_SMP: <n>" the -smp value (default 1),
# "# QEMU_ARGS: <args>" adds QEMU options (e.g. devices). "# QEMU_THREADS:
# single multi" runs the test once per TCG thread mode (-accel
# tcg,thread=...; reported as name[mode]): round-robin and MTTCG. The MTTCG
# runs are optional (BENCH_MTTCG); a QEMU that warns its guest is "not yet
# converted to MTTCG" (no MTTCG for CHERI) reports them as skipped. "# QEMU_VERSION: >=<x.y>" runs the test only on
# QEMU x.y or later (for extensions a QEMU rebase added; older QEMUs report it
# as skipped). A "# XFAIL: <reason>" line marks a known failure: it is
# reported but does not fail the run, and passing is reported as XPASS (then
# remove the line).
#
# Usage: qemu-only-tests.sh <path/to/qemu-system-riscv64xcheri>
#
# Environment:
#   CROSS_CC  RISC-V cross compiler (default: riscv64-linux-gnu-gcc)
#   BENCH_INCLUDE  regex of test names (file name without .S) to run
#   BENCH_EXCLUDE  regex of test names to skip
#   BENCH_MTTCG  whether QEMU_THREADS tests also run under MTTCG: "off"
#             (default) skips the multi runs, "on" runs them (skipped on a
#             QEMU without MTTCG for CHERI), "require" runs them and fails a
#             skipped one (for a QEMU that must support MTTCG)
set -u

case ${BENCH_MTTCG:=off} in
  off|on|require) ;;
  *) echo "error: BENCH_MTTCG must be off, on or require, not $BENCH_MTTCG" >&2; exit 2 ;;
esac

here=$(cd "$(dirname "$0")" && pwd)
dir=$(cd "$here/../../regressions/qemu-only" && pwd)
qemu=${1:?usage: $0 <qemu-system-riscv64xcheri>}
cc=${CROSS_CC:-riscv64-linux-gnu-gcc}

command -v "$cc" >/dev/null || { echo "error: $cc not found (set CROSS_CC)" >&2; exit 2; }
# e.g. "11.0.0" from "QEMU emulator version 11.0.0 (v11.0.0-...)"
qemu_version=$("$qemu" --version | sed -n 's/^QEMU emulator version \([0-9.]*\).*/\1/p')
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

status=0
# run <name> <src> <cpu> <smp> <xfail> <args...>: run one test and report it
run() {
  local name=$1 src=$2 cpu=$3 smp=$4 xfail=$5 rc
  shift 5
  # In a subshell, so a QEMU that aborts is reported in the log, not by bash.
  (timeout 30 "$qemu" -machine virt -smp "${smp:-1}" -cpu "${cpu:-rv64}" -bios none \
    -kernel "$tmp/$(basename "$src" .S).elf" -display none -monitor none \
    -serial none "$@"; exit $?) >"$tmp/$name.log" 2>&1
  rc=$?
  if grep -q "not yet converted to MTTCG" "$tmp/$name.log"; then
    if [ "$BENCH_MTTCG" = require ]; then
      echo "FAIL: $name: this QEMU has no MTTCG for CHERI (BENCH_MTTCG=require)"
      status=1
    else
      echo "skipped: $name (this QEMU has no MTTCG for CHERI)"
    fi
    return
  fi
  if [ -n "$xfail" ]; then
    if [ $rc -eq 0 ]; then
      echo "XPASS: $name passes now; remove its XFAIL line ($xfail)"
    else
      echo "xfail: $name (exit $rc: $xfail)"
    fi
    return
  fi
  case $rc in
    0)   echo "ok: $name" ;;
    124) echo "FAIL: $name timed out"; status=1 ;;
    99)  echo "FAIL: $name took an unexpected trap"; status=1 ;;
    *)   echo "FAIL: $name failed check $rc"; sed 's/^/  /' "$tmp/$name.log"
         status=1 ;;
  esac
}

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
  threads=$(sed -n 's/^# QEMU_THREADS: *//p' "$src" | head -1)
  min=$(sed -n 's/^# QEMU_VERSION: *>= *//p' "$src" | head -1)
  if [ -n "$min" ] &&
     [ "$(printf '%s\n' "$min" "$qemu_version" | sort -V | head -1)" != "$min" ]; then
    echo "skipped: $name (needs QEMU $min or later, this is $qemu_version)"
    continue
  fi
  if ! "$cc" -march=rv64gc -mabi=lp64 -nostdlib -nostartfiles -static \
      -I "$dir" -T "$dir/link.ld" -o "$tmp/$name.elf" "$src"; then
    echo "FAIL: $name does not assemble"; status=1; continue
  fi
  if [ -z "$threads" ]; then
    # shellcheck disable=SC2086  # QEMU_ARGS is a word list
    run "$name" "$src" "$cpu" "$smp" "$xfail" $args
  else
    for mode in $threads; do
      if [ "$mode" = multi ] && [ "$BENCH_MTTCG" = off ]; then
        echo "skipped: $name[multi] (MTTCG runs off, set BENCH_MTTCG=on)"
        continue
      fi
      # shellcheck disable=SC2086
      run "$name[$mode]" "$src" "$cpu" "$smp" "$xfail" -accel "tcg,thread=$mode" $args
    done
  fi
done
exit $status
