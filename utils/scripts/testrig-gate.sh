#!/usr/bin/env bash
# TestRIG regression gate for CHERI QEMU (RISC-V, Xcheri v9).
#
# Runs these stages against a QEMU build and fails if any of them fails:
#   1 policy       Check that QEMU refuses CPU extensions that bypass CHERI
#                  protection (see regressions/README.md) and still starts
#                  with the default CPUs, and that every CPU extension QEMU
#                  offers has been reviewed for CHERI
#                  (regressions/cheri-extensions.txt, cheri-ext-review.py).
#   2 regressions  Replay every saved counter-example under regressions/ on
#                  Sail and QEMU (bugs that were found and fixed must stay
#                  fixed; cheri-guards/ pins CHERI behaviour a rebase is
#                  likely to change). regressions/open-bugs/ holds traces of
#                  known, unfixed bugs: each must still fail (reported, not
#                  fatal); one that passes is reported as XPASS.
#   2b selftest    Check the gate itself: replay regressions/cheri-qemu-10.2 on
#                  CHERI-QEMU 7.1 (SELFTEST_QEMU), which still has the bugs
#                  10.2 fixed, and require exactly the verdicts in
#                  utils/gate-selftest/qemu-7.1-expected.txt (needs
#                  ALLIANCE_QEMU too). A change means the gate (or Sail, or
#                  Alliance) now grades differently.
#   3 bench        Run the bare-metal tests in regressions/qemu-only, which
#                  check CHERI properties of QEMU features the Sail model
#                  lacks (needs CROSS_CC or riscv64-linux-gnu-gcc).
#   4 random       Run every QuickCheckVEngine template with fresh random
#                  tests against Sail (seeded; rerun with SEED=<n>). Failures
#                  are shrunk and saved to SAVE_DIR as regression traces.
#     coverage     Check that the random tests really ran the CHERI
#                  instructions (coverage-check.py against
#                  regressions/coverage-required.txt). Skipped when templates
#                  are selected with --templates/--exclude, unless named in
#                  --only.
#   4b vote        Three-way vote: random tests of CHERI-Alliance QEMU
#                  against this QEMU, each disagreement replayed on Sail to
#                  find the odd one out (three-way-vote.py; needs
#                  ALLIANCE_QEMU).
#   5 cheribsd     Boot CheriBSD and run cheribsdtest-purecap and -hybrid
#                  (cheribsd-tests.py, ~30 min; needs CHERIBSD_OUTPUT).
#   6 upstream     Compare with unmodified upstream QEMU on non-CHERI code:
#                  upstream's own check-tcg and qtests on this QEMU
#                  (upstream-tests.sh), and riscv-arch-test signatures and
#                  instruction traces on both (upstream-diff.py; needs
#                  UPSTREAM_BUILD, and ARCH_TEST for the arch tests).
# Every run (not --list) is saved: GATE_LOG_DIR/<date>-<QEMU branch>-<QEMU
# commit>-<profile>.log holds the whole output after a header that says what
# was tested (host, QEMU and TestRIG commits, profile, seed), with the CheriBSD
# console log and the warnings next to it. The run ends with a summary: one
# line per stage with its result, time and notes.
#
# A stage whose reference is not configured is skipped with a note, unless
# it was asked for with --only or --against (then it is an error). The plan
# (what runs, what is skipped and why) is printed first.
#
# Two references for CHERI instructions: with ALLIANCE_QEMU set, every trace
# where stages 2 and 4 find this QEMU differing from Sail is also replayed on
# CHERI-Alliance QEMU (three-way-vote.py --traces), and stage 2 replays every
# trace on all three. Disagreeing with both references is an ERROR (the gate
# fails); disagreeing with one is a WARNING (listed at the end; fatal with
# --warnings-fatal). Without ALLIANCE_QEMU, Sail is the only reference and
# every difference from it is an ERROR. Where Alliance is known to be wrong
# (regressions/alliance-shares-bug.txt: the bugs it shares with CHERI-QEMU
# 7.1), Sail alone judges and every difference is an ERROR.
#
# Usage: testrig-gate.sh [options] <path/to/qemu-system-riscv64xcheri> [tests-per-template]
#
# Choosing what runs (names or numbers above, comma-separated):
#   --only STAGES       run only these stages
#   --skip STAGES       skip these stages
#   --against REFS      run only the stages that compare against these
#                       references: sail (regressions, random, coverage),
#                       alliance (vote, selftest), upstream (upstream); the stages that
#                       need no reference (policy, bench, cheribsd) still run
#                       unless skipped
#   --config FILE       read settings (VAR=value lines, the environment
#                       variables below) from FILE; options given on the
#                       command line win. Examples: utils/gate-profiles/
#   --list              print the plan and exit
#   --warnings-fatal    fail on WARNINGs too (one reference disagrees)
# Turning off individual tests (regular expressions on names):
#   --templates RE      random-test templates to run (stages 4 and 4b)
#   --exclude RE        random-test templates to skip (stages 4 and 4b)
#   --vote-exclude RE   templates to skip in the three-way vote only (4b), e.g.
#                       ones that crash CHERI-Alliance QEMU (full.conf: caprandom)
#   --bench RE          bench tests to run (stage 3, test file name without .S)
#   --bench-exclude RE  bench tests to skip
#   --trace-exclude RE  regression traces to skip (stage 2, file name)
#   --suites LIST       riscv-arch-test suites for stage 6 (default: all)
# Where the references are (instead of the environment variables):
#   --alliance PATH --upstream-build DIR --arch-test DIR --cheribsd DIR
#   --selftest-qemu PATH
#
# Environment (and --config) variables:
#   ONLY, SKIP, AGAINST  as --only, --skip, --against
#   WARNINGS_FATAL=1  as --warnings-fatal
#   TEMPLATES, EXCLUDE   as --templates, --exclude (EXCLUDE default: none)
#   BENCH_INCLUDE, BENCH_EXCLUDE, TRACE_EXCLUDE, UPSTREAM_SUITES  as above
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
#   CROSS_CC  RISC-V cross compiler for the bench tests
#   BENCH_MTTCG  the bench tests' MTTCG runs: "off" (default) skips them,
#             "on" runs them where QEMU supports MTTCG for CHERI, "require"
#             fails them on a QEMU without it (full-mttcg.conf)
#   CHERIBSD_OUTPUT  cheribuild output directory with a riscv64-purecap
#             CheriBSD disk image (stage 5)
#   CHERIBSD_SMP  number of harts CheriBSD boots with (default: 1; QEMU
#             runs them with MTTCG when it supports MTTCG for CHERI)
#   CHERIBSD_LOG  CheriBSD console log (default: next to the run's log)
#   GATE_LOG_DIR  where each run's log is saved (default: gate-logs/)
#   ALLIANCE_QEMU  CHERI-Alliance qemu-system-riscv64xcheri with RVFI-DII
#             (stage 4b)
#   VOTE_TESTS  random tests per template in stage 4b (default: tests-per-template)
#   VOTE_EXCLUDE  as --vote-exclude (default: none)
#   UPSTREAM_BUILD  build directory of the upstream QEMU release the port is
#             based on, v10.2.0 or v11.0.0 (riscv64-softmmu, --enable-plugins,
#             "make check-tcg" run; stage 6)
#   ARCH_TEST  riscv-arch-test checkout (stage 6's arch-test comparison)
#   SELFTEST_QEMU  CHERI-QEMU 7.1 qemu-system-riscv64xcheri with RVFI-DII
#             (stage 2b)
#   SAIL_ONLY  where Sail alone judges (default:
#             regressions/alliance-shares-bug.txt; empty: nowhere)
set -u

cmdline=$(printf '%q ' "$0" "$@")
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
STAGES="policy regressions selftest bench random coverage vote cheribsd upstream"

usage() {
  sed -n 's/^# \{0,1\}//; /^Usage:/,/^Environment/p' "$0" | sed '$d' >&2
  exit 2
}

# Command-line options; they are applied after --config, so they win.
declare -A opt=()
positional=()
config=${GATE_CONFIG:-}
list_only=0
while [ $# -gt 0 ]; do
  case $1 in
    --only) opt[ONLY]=$2; shift ;;
    --skip) opt[SKIP]=$2; shift ;;
    --against) opt[AGAINST]=$2; shift ;;
    --templates) opt[TEMPLATES]=$2; shift ;;
    --exclude) opt[EXCLUDE]=$2; shift ;;
    --bench) opt[BENCH_INCLUDE]=$2; shift ;;
    --bench-exclude) opt[BENCH_EXCLUDE]=$2; shift ;;
    --trace-exclude) opt[TRACE_EXCLUDE]=$2; shift ;;
    --vote-exclude) opt[VOTE_EXCLUDE]=$2; shift ;;
    --suites) opt[UPSTREAM_SUITES]=$2; shift ;;
    --alliance) opt[ALLIANCE_QEMU]=$2; shift ;;
    --upstream-build) opt[UPSTREAM_BUILD]=$2; shift ;;
    --arch-test) opt[ARCH_TEST]=$2; shift ;;
    --cheribsd) opt[CHERIBSD_OUTPUT]=$2; shift ;;
    --selftest-qemu) opt[SELFTEST_QEMU]=$2; shift ;;
    --config) config=$2; shift ;;
    --list) list_only=1 ;;
    --warnings-fatal) opt[WARNINGS_FATAL]=1 ;;
    -h|--help) usage ;;
    -*) echo "error: unknown option $1" >&2; usage ;;
    *) positional+=("$1") ;;
  esac
  shift
done
if [ -n "$config" ]; then
  [ -r "$config" ] || { echo "error: cannot read config $config" >&2; exit 2; }
  # shellcheck source=/dev/null
  . "$config"
fi
for k in "${!opt[@]}"; do printf -v "$k" '%s' "${opt[$k]}"; done

qemu=${positional[0]:-}
ntests=${positional[1]:-100}
[ -n "$qemu" ] || usage
arch=${ARCH:-rv64imsafdcZicsr_Zifencei_Xcheri}
csr_exclude=${CSR_EXCLUDE-^(misa|mstatus|sstatus|mscratch|sscratch|mip|mie|mideleg|medeleg|sccsr|mhpmevent[0-9]+|m?cycleh?|m?instreth?|timeh?|m?hpmcounter[0-9]+h?|reserved)\$}
templates=${TEMPLATES-}
exclude=${EXCLUDE-}
vote_exclude=${VOTE_EXCLUDE-}
if [ -n "$exclude" ] && [ -n "$vote_exclude" ]; then
  vote_exclude="($exclude)|($vote_exclude)"
else
  vote_exclude=$exclude$vote_exclude
fi
seed=${SEED:-$(( $(date +%s) % 1000000000 ))}
save_dir=${SAVE_DIR:-$root/random-failures}
cpu_extra=${QEMU_CPU_EXTRA-zba=true,zbb=true,zbc=true,zbs=true}
qcv=${QCVENGINE:-$(find "$root/vengines/QuickCheckVEngine/dist-newstyle" -type f \
    -name QCVEngine -perm -u+x 2>/dev/null | head -1)}

# Stage names from names or numbers, comma- or space-separated.
stage_names() {
  local s out=
  for s in ${1//,/ }; do
    case $s in
      1) s=policy ;; 2) s=regressions ;; 2b) s=selftest ;; 3) s=bench ;; 4) s=random ;;
      4b) s=vote ;; 5) s=cheribsd ;; 6) s=upstream ;;
    esac
    [[ " $STAGES " == *" $s "* ]] || { echo "error: unknown stage $s (stages: $STAGES)" >&2; exit 2; }
    out+="$s "
  done
  echo "$out"
}
only=$(stage_names "${ONLY-}") || exit 2
skip=$(stage_names "${SKIP-}") || exit 2
against_stages=
AGAINST=${AGAINST-}
for ref in ${AGAINST//,/ }; do
  case $ref in
    sail) against_stages+="regressions random coverage " ;;
    alliance) against_stages+="vote selftest " ;;
    upstream) against_stages+="upstream " ;;
    *) echo "error: unknown reference $ref (sail, alliance, upstream)" >&2; exit 2 ;;
  esac
done

# Second reference for stages 2 and 4 (not with --against lacking alliance).
second_ref=${ALLIANCE_QEMU:-}
[ -n "$AGAINST" ] && [[ ",$AGAINST," != *,alliance,* ]] && second_ref=

# Why a stage does not run ("" if it runs); "error: ..." if it was asked for
# but cannot run.
declare -A why=()
for s in $STAGES; do
  asked=0
  [[ " $only $against_stages " == *" $s "* ]] && asked=1
  need=
  case $s in
    bench) command -v "${CROSS_CC:-riscv64-linux-gnu-gcc}" >/dev/null ||
             need="no RISC-V cross compiler (set CROSS_CC)" ;;
    coverage) [ -n "$templates$exclude" ] && [ $asked -eq 0 ] &&
             need="templates are selected (--only coverage to force it)" ;;
    vote) [ -n "${ALLIANCE_QEMU:-}" ] || need="ALLIANCE_QEMU / --alliance not set" ;;
    selftest) if [ -z "${SELFTEST_QEMU:-}" ]; then need="SELFTEST_QEMU / --selftest-qemu not set"
              elif [ -z "${ALLIANCE_QEMU:-}" ]; then need="ALLIANCE_QEMU / --alliance not set"; fi ;;
    cheribsd) [ -n "${CHERIBSD_OUTPUT:-}" ] || need="CHERIBSD_OUTPUT / --cheribsd not set" ;;
    upstream) [ -n "${UPSTREAM_BUILD:-}" ] || need="UPSTREAM_BUILD / --upstream-build not set" ;;
  esac
  if [[ " $skip " == *" $s "* ]]; then
    why[$s]="--skip"
  elif [ -n "$only" ] && [[ " $only " != *" $s "* ]]; then
    why[$s]="not in --only"
  elif [ -n "${AGAINST-}" ] && [[ " regressions selftest random coverage vote upstream " == *" $s "* ]] &&
       [[ " $against_stages " != *" $s "* ]]; then
    why[$s]="not in --against"
  elif [ -n "$need" ]; then
    if [ $asked -eq 1 ] && [ "$s" != coverage ]; then why[$s]="error: $need"; else why[$s]=$need; fi
  else
    why[$s]=
  fi
done
want() { [ -z "${why[$1]}" ]; }

# git_rev <dir>: "<branch> <short commit>[-dirty]" of the checkout holding dir.
git_rev() {
  local top rev
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || { echo "- unknown"; return; }
  rev=$(git -C "$top" rev-parse --short=10 HEAD)
  git -C "$top" diff --quiet HEAD -- 2>/dev/null || rev+=-dirty
  echo "$(git -C "$top" rev-parse --abbrev-ref HEAD) $rev"
}

# Save the whole run: from here on, output also goes to $log.
log=
if [ $list_only -eq 0 ]; then
  log_dir=${GATE_LOG_DIR:-$root/gate-logs}
  mkdir -p "$log_dir" || exit 2
  read -r qemu_branch qemu_rev <<<"$(git_rev "$(dirname "$qemu")")"
  read -r rig_branch rig_rev <<<"$(git_rev "$root")"
  profile=$(basename "${config:-adhoc}" .conf)
  log_base=$log_dir/$(date +%Y%m%d-%H%M%S)-${qemu_branch//\//_}-$qemu_rev-$profile
  log=$log_base.log
  exec 3>&1 4>&2
  exec > >(tee -a "$log") 2>&1
  tee_pid=$!
  echo "=== TestRIG gate, $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "  command:  $cmdline"
  echo "  profile:  ${config:-none}"
  echo "  QEMU:     $qemu"
  echo "            $("$qemu" --version 2>/dev/null | head -1)"
  echo "            branch $qemu_branch, commit $qemu_rev"
  echo "  TestRIG:  branch $rig_branch, commit $rig_rev"
  echo "  host:     $(uname -srm), $(nproc) CPUs, $(sed -n 's/^model name[^:]*: //p' /proc/cpuinfo | head -1)"
  echo "  seed:     $seed ($ntests tests per template)"
  echo "  settings: BENCH_MTTCG=${BENCH_MTTCG:-off} CHERIBSD_SMP=${CHERIBSD_SMP:-1}"
  echo "  log:      $log"
fi

echo "=== Plan (QEMU ${qemu}, $ntests tests per template)"
plan_error=0
for s in $STAGES; do
  if want "$s"; then
    printf '  %-12s run\n' "$s"
  else
    if [[ ${why[$s]} == error:* ]]; then
      printf '  %-12s ERROR: %s\n' "$s" "${why[$s]#error: }"; plan_error=1
    else
      printf '  %-12s skip: %s\n' "$s" "${why[$s]}"
    fi
  fi
done
[ -n "$templates$exclude" ] && echo "  templates: ${templates:-all}${exclude:+, excluding $exclude}"
[ -n "${VOTE_EXCLUDE-}" ] && echo "  vote templates: excluding $vote_exclude"
[ -n "${BENCH_INCLUDE-}${BENCH_EXCLUDE-}" ] &&
  echo "  bench tests: ${BENCH_INCLUDE:-all}${BENCH_EXCLUDE:+, excluding $BENCH_EXCLUDE}"
[ -n "${TRACE_EXCLUDE-}" ] && echo "  traces: excluding $TRACE_EXCLUDE"
[ -n "${UPSTREAM_SUITES-}" ] && echo "  arch-test suites: $UPSTREAM_SUITES"
if want regressions || want random; then
  if [ -n "$second_ref" ]; then
    echo "  references: Sail and CHERI-Alliance QEMU (ERROR if both disagree, WARNING if one does)"
  else
    echo "  references: Sail only (every difference is an ERROR; --alliance adds a second)"
  fi
fi
[ "${WARNINGS_FATAL:-0}" = 1 ] && echo "  warnings are fatal"
[ $plan_error -eq 0 ] || { echo "error: a stage that was asked for cannot run" >&2; exit 2; }
[ $list_only -eq 0 ] || exit 0

[ -x "$qemu" ] || { echo "error: $qemu is not executable" >&2; exit 2; }
if want regressions || want selftest || want random || want vote; then
  [ -z "$second_ref" ] || [ -x "$second_ref" ] ||
    { echo "error: $second_ref is not executable" >&2; exit 2; }
  [ -n "$qcv" ] && [ -x "$qcv" ] || { echo "error: QCVEngine not built (cabal build)" >&2; exit 2; }
fi

rig() {
  python3 "$here/runTestRIG.py" -a sail -b qemu --path-to-qemu "$qemu" \
    --path-to-QCVEngine "$qcv" -r "$arch" --support-misaligned -s 2 \
    ${cpu_extra:+--qemu-cpu-extra "$cpu_extra"} \
    ${csr_exclude:+--csr-exclude-regex "$csr_exclude"} "$@"
}
run() { rig --no-save "$@"; }
sail_only=${SAIL_ONLY-$root/regressions/alliance-shares-bug.txt}
# judge <label> <out-dir> <trace-dir> [options]: replay the traces on Sail,
# Alliance and this QEMU and grade them (ERROR if both references disagree
# with this QEMU). PORT= replaces this QEMU.
judge() {
  python3 "$here/three-way-vote.py" --port "${PORT:-$qemu}" --alliance "${second_ref:-$ALLIANCE_QEMU}" \
    --qcvengine "$qcv" --arch "$arch" --label "$1" --out "$2" --traces "$3" "${@:4}" \
    ${sail_only:+--sail-only "$sail_only"} ${cpu_extra:+--cpu-extra "$cpu_extra"} \
    ${csr_exclude:+--csr-exclude-regex "$csr_exclude"} \
    $([ "${WARNINGS_FATAL:-0}" = 1 ] && echo --warnings-fatal)
}
template_args=(${templates:+--test-include-regex "$templates"}
               ${exclude:+--test-exclude-regex "$exclude"})

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

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
warnings=$tmp/warnings
status=0

# Each stage records its own result, time and notes for the summary.
declare -A result=() took=() note=()
nwarnings() { if [ -s "$warnings" ]; then wc -l <"$warnings"; else echo 0; fi; }
stage_begin() {
  stage=$1 stage_t0=$SECONDS stage_status=$status status=0 stage_w0=$(nwarnings)
}
stage_end() {
  local nw=$(( $(nwarnings) - stage_w0 ))
  if [ $status -eq 0 ]; then result[$stage]=PASS; else result[$stage]=FAIL; fi
  took[$stage]=$((SECONDS - stage_t0))
  [ $nw -eq 0 ] || note[$stage]+="${note[$stage]:+; }$nw warnings"
  status=$((stage_status | status))
}
hms() { printf '%d:%02d:%02d' $(($1 / 3600)) $(($1 / 60 % 60)) $(($1 % 60)); }

if want policy; then
  stage_begin policy
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
  stage_end
fi

# Print the traces in a directory that --trace-exclude does not remove.
traces_in() {
  local t
  for t in "$1"/*.S; do
    [ -e "$t" ] || continue
    if [ -n "${TRACE_EXCLUDE-}" ] && [[ $(basename "$t") =~ $TRACE_EXCLUDE ]]; then
      echo "skipped: ${t#$root/} (--trace-exclude)" >&2
      continue
    fi
    echo "$t"
  done
}

if want regressions; then
  stage_begin regressions
  for dir in "$root"/regressions/*/; do
    dir=${dir%/}
    case $(basename "$dir") in qemu-only|open-bugs) continue ;; esac
    echo "=== Replaying saved regressions: ${dir#$root/}"
    replay=$dir
    if [ -n "${TRACE_EXCLUDE-}" ]; then
      replay=$tmp/traces-$(basename "$dir")
      mkdir -p "$replay"
      traces_in "$dir" | xargs -r ln -s -t "$replay"
      ls "$replay"/*.S >/dev/null 2>&1 || { echo "(no traces left)"; continue; }
    fi
    if [ -n "$second_ref" ]; then
      # Every trace on all three (a pass needs both references to agree).
      judge "REGRESSIONS $(basename "$dir")" \
        "$save_dir/regressions-$(basename "$dir")" "$replay" --warnings-file "$warnings" || status=1
    else
      # Keep going after a failure so one regression doesn't hide another.
      run -d "$replay" --continue-on-fail || status=1
    fi
  done

  echo "=== Known open bugs (must still fail): regressions/open-bugs"
  for trace in $(traces_in "$root/regressions/open-bugs"); do
    if run -t "$trace" >/dev/null 2>&1; then
      echo "XPASS: ${trace#$root/} passes now; move it to regressions/cheri-qemu-10.2/"
    else
      echo "xfail: ${trace#$root/}"
    fi
  done
  stage_end
fi

if want selftest; then
  stage_begin selftest
  echo "=== Gate self-test: CHERI-QEMU 7.1 must get the expected verdicts"
  expected=$root/utils/gate-selftest/qemu-7.1-expected.txt
  st_dir=$save_dir/selftest
  rm -rf "$st_dir"
  # Every trace, whatever --trace-exclude says, so the verdicts compare.
  PORT=$SELFTEST_QEMU judge "SELFTEST (7.1)" "$st_dir" \
    "$root/regressions/cheri-qemu-10.2" --verdicts "$st_dir/verdicts.txt" \
    >"$tmp/selftest.log" 2>&1
  if [ ! -s "$st_dir/verdicts.txt" ]; then
    echo "FAIL: the self-test gave no verdicts (see $tmp/selftest.log)"
    cat "$tmp/selftest.log"; status=1
  elif diff <(sed 's/#.*//; /^ *$/d; s/  *$//' "$expected" | sort) \
            <(sort "$st_dir/verdicts.txt") >"$tmp/selftest.diff"; then
    echo "ok: $(wc -l <"$st_dir/verdicts.txt") traces, verdicts as expected" \
      "($(grep -c ' \(port-differs\|both-differ\|sail-only-differs\)$' "$st_dir/verdicts.txt") ERRORs on 7.1)"
  else
    echo "FAIL: the gate grades CHERI-QEMU 7.1 differently ('<' expected, '>' now;"
    echo "      a new trace, or a change to the gate, Sail or Alliance):"
    cat "$tmp/selftest.diff"
    echo "      If intended, put the lines of $st_dir/verdicts.txt into ${expected#$root/}"
    status=1
  fi
  stage_end
fi

if want bench; then
  stage_begin bench
  echo "=== QEMU-only tests"
  BENCH_INCLUDE=${BENCH_INCLUDE-} BENCH_EXCLUDE=${BENCH_EXCLUDE-} BENCH_MTTCG=${BENCH_MTTCG-} \
    "$here/qemu-only-tests.sh" "$qemu" | tee "$tmp/bench.out"
  [ "${PIPESTATUS[0]}" -eq 0 ] || status=1
  note[bench]=$(sed -n 's/^bench: //p' "$tmp/bench.out")
  stage_end
fi

if want random; then
  stage_begin random
  echo "=== Random tests: $ntests per template (templates: ${templates:-all}, excluding: ${exclude:-none}, seed $seed)"
  mkdir -p "$save_dir"
  stats=$save_dir/stats-$seed.txt
  ls "$save_dir"/failure-*.S >"$tmp/old-failures" 2>/dev/null
  rig -n "$ntests" --seed "$seed" -S "$save_dir" --continue-on-fail \
    --stats-file "$stats" "${template_args[@]}"
  rig_status=$?
  if [ -z "$second_ref" ]; then
    [ $rig_status -eq 0 ] || status=1
    if ls "$save_dir"/failure-*.S >/dev/null 2>&1; then
      echo "FAIL: failing random tests saved in ${save_dir#$root/}/ (rerun with SEED=$seed)"
      status=1
    fi
  else
    # This run's Sail failures, judged by Alliance as well.
    new=$tmp/new-failures
    mkdir -p "$new"
    ls "$save_dir"/failure-*.S 2>/dev/null | grep -vxF -f "$tmp/old-failures" |
      xargs -r ln -s -t "$new"
    if ls "$new"/*.S >/dev/null 2>&1; then
      echo "Random tests differ from Sail ($(ls "$new" | wc -l) traces); replaying on CHERI-Alliance QEMU (rerun with SEED=$seed)"
      judge "RANDOM vs both references" "$save_dir/random-$seed-judged" "$new" \
        --warnings-file "$warnings" || status=1
    elif [ $rig_status -ne 0 ]; then
      echo "FAIL: the random tests failed without saving a trace (a simulator crashed?)"
      status=1
    fi
  fi
  note[random]="$ntests per template, seed $seed"
  stage_end
fi

if want coverage; then
  stage_begin coverage
  echo "=== Coverage of the random tests"
  stats=$save_dir/stats-$seed.txt
  if [ -e "$stats" ]; then
    python3 "$here/coverage-check.py" "$stats" || status=1
  else
    echo "FAIL: no coverage statistics ($stats); run the random stage with the same SEED"
    status=1
  fi
  stage_end
fi

if want vote; then
  stage_begin vote
  echo "=== Three-way vote: Sail, CHERI-Alliance QEMU, this QEMU (seed $seed)"
  vote_dir=$save_dir/vote-$seed
  rm -rf "$vote_dir"
  python3 "$here/three-way-vote.py" --port "$qemu" --alliance "$ALLIANCE_QEMU" \
    --qcvengine "$qcv" --arch "$arch" --out "$vote_dir" --seed "$seed" \
    -n "${VOTE_TESTS:-$ntests}" ${cpu_extra:+--cpu-extra "$cpu_extra"} \
    ${csr_exclude:+--csr-exclude-regex "$csr_exclude"} \
    ${templates:+--test-include-regex "$templates"} \
    ${vote_exclude:+--test-exclude-regex "$vote_exclude"} \
    ${sail_only:+--sail-only "$sail_only"} --warnings-file "$warnings" \
    $([ "${WARNINGS_FATAL:-0}" = 1 ] && echo --warnings-fatal) || status=1
  stage_end
fi

if want cheribsd; then
  stage_begin cheribsd
  echo "=== CheriBSD tests"
  python3 -u "$here/cheribsd-tests.py" "$qemu" "$CHERIBSD_OUTPUT" \
    --smp "${CHERIBSD_SMP:-1}" --log "${CHERIBSD_LOG:-$log_base.cheribsd.log}" |
    tee "$tmp/cheribsd.out"
  [ "${PIPESTATUS[0]}" -eq 0 ] || status=1
  # e.g. "purecap 305 passed, 10 xfail; hybrid 149 passed, 52 xfail; 4 harts"
  note[cheribsd]="$(sed -nE 's/^cheribsdtest-([a-z]+): passed ([0-9]+), expectedly failed ([0-9]+).*/\1 \2 passed, \3 xfail/p' \
    "$tmp/cheribsd.out" | paste -sd';' | sed 's/;/; /g'); ${CHERIBSD_SMP:-1} harts"
  stage_end
fi

if want upstream; then
  stage_begin upstream
  echo "=== Upstream QEMU: upstream's own tests on this QEMU"
  "$here/upstream-tests.sh" "$UPSTREAM_BUILD" "$qemu" || status=1
  if [ -n "${ARCH_TEST:-}" ]; then
    echo "=== Upstream QEMU: riscv-arch-test signatures and traces"
    python3 "$here/upstream-diff.py" --upstream "$UPSTREAM_BUILD/qemu-system-riscv64" \
      --port "$qemu" --arch-test "$ARCH_TEST" --out "$save_dir/upstream-diff" \
      ${UPSTREAM_SUITES:+--suites "$UPSTREAM_SUITES"} || status=1
  else
    echo "(riscv-arch-test comparison skipped: ARCH_TEST / --arch-test not set)"
    note[upstream]="riscv-arch-test comparison skipped"
  fi
  stage_end
fi

nwarn=$(nwarnings)
{
  echo
  echo "=== Summary ($(hms $SECONDS) in all)"
  printf '  %-12s %-6s %8s  %s\n' stage result time notes
  for s in $STAGES; do
    if want "$s"; then
      printf '  %-12s %-6s %8s  %s\n' "$s" "${result[$s]:-?}" "$(hms "${took[$s]:-0}")" "${note[$s]:-}"
    else
      printf '  %-12s %-6s %8s  %s\n' "$s" - "" "skipped: ${why[$s]}"
    fi
  done
  if [ "$nwarn" -gt 0 ]; then
    cp "$warnings" "$log_base.warnings.txt"
    echo
    echo "  $nwarn warnings: one reference disagrees with this QEMU, the other agrees."
    # e.g. "     35  THREE-WAY VOTE  alliance-differs"
    sed -E 's/^(.*): WARNING +([a-z-]+).*/\1  \2/' "$warnings" | sort | uniq -c | sed 's/^/  /'
    echo "  Each is listed in $log_base.warnings.txt"
  fi
  echo
  echo "  log: $log"
  if [ $status -eq 0 ]; then
    if [ "$nwarn" -gt 0 ]; then echo "TESTRIG GATE: PASS ($nwarn warnings)"; else echo "TESTRIG GATE: PASS"; fi
  else
    echo "TESTRIG GATE: FAIL ($(for s in $STAGES; do [ "${result[$s]:-}" = FAIL ] && printf '%s ' "$s"; done | sed 's/ $//') failed)"
  fi
}
# Let tee finish writing the log before exiting.
exec 1>&3 2>&4 3>&- 4>&-
wait "$tee_pid" 2>/dev/null
exit $status
