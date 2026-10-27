#!/usr/bin/env bash
# Run upstream QEMU's own RISC-V tests against the CHERI QEMU port.
#
# The tests come from an unmodified upstream QEMU build (the release the port
# is based on, v10.2.0 or v11.0.0, configured
# with --cross-prefix-riscv64 and built with "make check-tcg"), so they are
# upstream's expectations, not the port's copy of them:
#   1. tests/tcg/riscv64 system tests (check-tcg): each must exit 0 on the
#      port, and the plugin-instrumented ones must give the same plugin output
#      as on upstream. Both QEMUs boot upstream's OpenSBI (the CHERI build's
#      default firmware is a CHERI BBL).
#   2. qtests for riscv64 (QOM, QMP, HMP, devices, CSRs, ...). qtest takes the
#      target from the binary's name, so the port runs through a symlink
#      named qemu-system-riscv64.
# A test in EXPECTED_FAIL below is reported but does not fail.
#
# Usage: upstream-tests.sh <upstream build dir> <port qemu-system-riscv64xcheri>
#   The port binary needs TCG plugins (configure --enable-plugins, the default
#   without --enable-rvfi-dii).
set -u

up=$(cd "${1:?usage: $0 <upstream build dir> <port qemu>}" && pwd)
port=${2:?usage: $0 <upstream build dir> <port qemu>}
[ -x "$up/qemu-system-riscv64" ] || { echo "error: no qemu-system-riscv64 in $up" >&2; exit 2; }
[ -x "$port" ] || { echo "error: $port is not executable" >&2; exit 2; }
plugins=$(dirname "$port")/tests/tcg/plugins
bios=$up/../pc-bios/opensbi-riscv64-generic-fw_dynamic.bin

# test: reason it cannot pass on a CHERI v9 CPU
declare -A EXPECTED_FAIL=(
  [bios-tables-test]="needs CPU rva22s64, whose Svpbmt/Svnapot PTE bits are CHERI bits in v9"
)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
status=0

result() { # result <name> <ok?> <detail>
  if [ "$2" = ok ]; then
    echo "ok: $1"
  elif [ -n "${EXPECTED_FAIL[$1]:-}" ]; then
    echo "expected: $1 fails (${EXPECTED_FAIL[$1]})"
  else
    echo "FAIL: $1 $3"; status=1
  fi
}

echo "--- upstream tests/tcg/riscv64 (check-tcg)"
tcg=$up/tests/tcg/riscv64-softmmu
if [ ! -x "$tcg/issue1060" ]; then
  make -C "$up" check-tcg >"$tmp/check-tcg.log" 2>&1 ||
    { echo "FAIL: make check-tcg on upstream"; tail -5 "$tmp/check-tcg.log"; exit 1; }
fi
for t in issue1060 test-mepc-masking doubletrap interruptedmemory; do
  plugin=()
  case $t in doubletrap|interruptedmemory)
    plugin=(-plugin "$plugins/libdiscons.so" -d plugin -D "$tmp/$t.pout") ;;
  esac
  (cd "$tcg" && timeout 60 "$port" -bios "$bios" "${plugin[@]}" -M virt -display none \
    -semihosting -device "loader,file=$t") >"$tmp/$t.log" 2>&1
  rc=$?
  if [ $rc -ne 0 ]; then
    result "tcg/$t" fail "(exit $rc: $(grep -v 'Disabling extension' "$tmp/$t.log" | tail -1))"
  elif [ ${#plugin[@]} -gt 0 ] && ! cmp -s "$tcg/$t.pout" "$tmp/$t.pout"; then
    result "tcg/$t" fail "(plugin output differs from upstream's $tcg/$t.pout)"
  else
    result "tcg/$t" ok
  fi
done

echo "--- upstream qtests (riscv64)"
mkdir "$tmp/bin"
ln -s "$(cd "$(dirname "$port")" && pwd)/$(basename "$port")" "$tmp/bin/qemu-system-riscv64"
for t in bios-tables-test qom-test device-introspect-test cdrom-test test-hmp \
    qmp-cmd-test qos-test riscv-csr-test machine-none-test qmp-test \
    readconfig-test netdev-socket; do
  (cd "$up" && QTEST_QEMU_BINARY="$tmp/bin/qemu-system-riscv64" \
    QTEST_QEMU_IMG="$up/qemu-img" \
    QTEST_QEMU_STORAGE_DAEMON_BINARY="$up/storage-daemon/qemu-storage-daemon" \
    PYTHON="$up/pyvenv/bin/python3" timeout 900 "tests/qtest/$t" --tap -k) \
    >"$tmp/$t.log" 2>&1
  rc=$?
  if [ $rc -eq 0 ] && ! grep -q '^not ok' "$tmp/$t.log"; then
    result "qtest/$t" ok
  else
    EXPECTED_FAIL[qtest/$t]=${EXPECTED_FAIL[$t]:-}
    result "qtest/$t" fail "(exit $rc: $(grep -vE 'Disabling extension|Broken pipe' "$tmp/$t.log" |
      grep -E 'not ok|ERROR|qemu-system|\.c:[0-9]+:' | head -1))"
  fi
done

[ $status -eq 0 ] && echo "UPSTREAM TESTS: PASS" || echo "UPSTREAM TESTS: FAIL"
exit $status
