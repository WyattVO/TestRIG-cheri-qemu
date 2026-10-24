#!/usr/bin/env python3
"""Three-way vote between the Sail CHERI-RISC-V model, CHERI-Alliance QEMU and
the CHERI QEMU under test.

The QEMU under test is checked against two references: Sail (CHERI v9) and
CHERI-Alliance QEMU (CHERI-Alliance/qemu main, QEMU 7.2). Every trace is
replayed on all three pairs, and the port is judged by how many references it
disagrees with:

  ERROR (the vote fails): the port disagrees with both references
    port-differs     Sail and Alliance agree; the port is the odd one out
    both-differ      all three differ: review against the spec
    not-replayed     a replay gave no answer (e.g. a QEMU crashed), so the
                     port could not be cleared
    sail-only-differs the port differs from Sail on a trace or instruction
                     where Alliance is known to be wrong (--sail-only FILE,
                     regressions/alliance-shares-bug.txt): Sail alone judges
  WARNING (reported; fatal only with --warnings-fatal): one reference disagrees
    sail-disagrees   both QEMUs agree, Sail differs: a bug the QEMUs share, or
                     a Sail bug or allowed difference
    alliance-differs the port agrees with Sail, Alliance differs: an Alliance
                     bug or a fix the port already has
  no-difference      all three agree on replay (reported; a flaky trace, or a
                     --traces trace that passes)
  sail-only-agrees   as sail-only-differs, but the port agrees with Sail

The traces come from random QuickCheckVEngine tests of Alliance against the
port (-n, saved with --save-dir) and/or from an existing directory (--traces;
the gate passes its saved regressions and the random tests' Sail failures this
way). Traces are grouped by their first mismatching instruction and fields.

Each runTestRIG.py run is killed after --timeout seconds (it, its QEMUs and
QCVEngine), so a hung implementation cannot stall the gate; a timeout fails
the vote. If an implementation dies, QCVEngine skips the remaining templates;
the vote lists them.

Usage: three-way-vote.py --port QEMU --alliance QEMU --out DIR
                         [-n TESTS [--seed N] [--test-include-regex RE]]
                         [--traces DIR] [--timeout SECONDS]
                         [--warnings-file FILE] [--warnings-fatal]
                         [--sail-only FILE] [--verdicts FILE]
Exits 1 if any trace is an ERROR, or a run timed out.
"""
import argparse
import collections
import os
import re
import shutil
import signal
import subprocess as sub
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RUN = os.path.join(HERE, "runTestRIG.py")

parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
parser.add_argument("--port", required=True, help="QEMU under test")
parser.add_argument("--alliance", required=True, help="CHERI-Alliance QEMU")
parser.add_argument("--out", required=True, help="output directory")
parser.add_argument("--qcvengine", required=True, help="QCVEngine binary")
parser.add_argument("--arch", default="rv64imsafdcZicsr_Zifencei_Xcheri")
parser.add_argument("--cpu-extra", default="zba=true,zbb=true,zbc=true,zbs=true",
                    help="-cpu properties for both QEMUs")
# Sail has no PMP entries; with QEMU's default 16 unconfigured entries,
# Alliance (unlike the port's RVFI-DII reset) denies every U-mode access.
parser.add_argument("--alliance-cpu-extra", default="pmp=false",
                    help="-cpu properties for Alliance only")
parser.add_argument("--csr-exclude-regex", default=None)
parser.add_argument("-n", "--number-of-tests", type=int, default=0,
                    help="random tests per template, Alliance against the port")
parser.add_argument("--seed", type=int, default=None)
parser.add_argument("--test-include-regex", default=None)
parser.add_argument("--test-exclude-regex", default=None)
parser.add_argument("--traces", default=None,
                    help="directory of existing traces to classify as well")
# The longest vote so far (100 tests per template) took about 2 hours.
parser.add_argument("--timeout", type=int, default=4 * 3600,
                    help="seconds before a runTestRIG.py run is killed")
parser.add_argument("--warnings-file", default=None,
                    help="append one line per WARNING group to this file")
parser.add_argument("--warnings-fatal", action="store_true",
                    help="fail on WARNINGs too")
parser.add_argument("--sail-only", default=None,
                    help="file of traces and instructions where Sail alone judges")
parser.add_argument("--verdicts", default=None,
                    help="write '<trace> <verdict>' lines to this file")
parser.add_argument("--label", default="THREE-WAY VOTE",
                    help="name printed with the result")
args = parser.parse_args()
timed_out = []


def run(a, b, extra, log):
    """Run runTestRIG.py with Sail or a QEMU as A and B; return its output.
    The output also goes to log as it is produced (tail -f it to follow)."""
    cmd = [sys.executable, RUN, "-a", a[0], "-b", b[0],
           "--path-to-QCVEngine", args.qcvengine, "-r", args.arch,
           "--support-misaligned", "-s", "2", "--continue-on-fail"]
    for side, (name, path, cpu) in (("A", a), ("B", b)):
        if name == "qemu":
            cmd += ["--path-to-qemu-" + side, path]
            if cpu:
                cmd += ["--qemu-cpu-extra-" + side, cpu]
    if args.cpu_extra:
        cmd += ["--qemu-cpu-extra", args.cpu_extra]
    if args.csr_exclude_regex:
        cmd += ["--csr-exclude-regex", args.csr_exclude_regex]
    with open(log, "w") as f:
        # Own process group, so a timeout also kills the QEMUs and QCVEngine.
        p = sub.Popen(cmd + extra, stdout=f, stderr=sub.STDOUT,
                      start_new_session=True)
        try:
            p.wait(timeout=args.timeout)
        except sub.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)
            p.wait()
            timed_out.append(os.path.basename(log))
            print("Timed out after %d s: %s" % (args.timeout, log))
    with open(log) as f:
        return f.read()


def replay(a, b, tracedir):
    """Replay every trace in tracedir; return {file name: passed}.
    A trace that kills or hangs an implementation makes QCVEngine discard the
    rest, so the remaining traces are replayed again in a fresh run."""
    name = "replay-%s-vs-%s" % ("sail" if a is SAIL else "alliance",
                                "port" if b is PORT else "alliance")
    todo = sorted(n for n in os.listdir(tracedir) if n.endswith(".S"))
    result, attempt = {}, 0
    while todo:
        attempt += 1
        d = tracedir
        if attempt > 1:
            d = os.path.join(args.out, "%s-%d" % (name, attempt))
            shutil.rmtree(d, ignore_errors=True)
            os.makedirs(d)
            for n in todo:
                os.symlink(os.path.abspath(os.path.join(tracedir, n)),
                           os.path.join(d, n))
        out = run(a, b, ["--no-save", "--no-shrink", "-d", d],
                  os.path.join(args.out, "%s%s.log" % (
                      name, "" if attempt == 1 else "-%d" % attempt)))
        current, got = None, 0
        for line in out.splitlines():
            m = re.match(r"Reading trace from (.*\.S)$", line)
            if m:
                current = os.path.basename(m.group(1))
            elif current and line in ("Failure.", "No Failure."):
                result[current] = line == "No Failure."
                current, got = None, got + 1
        todo = [n for n in todo if n not in result]
        if not got:
            break   # no progress: leave the rest not-replayed
        if todo:
            print("%s stopped early; replaying the %d traces left"
                  % (name, len(todo)))
    return result


def signature(path):
    """First mismatching instruction (None if unknown) and a group name:
    the instruction and the fields that differ."""
    insn = None
    with open(path) as f:
        for line in f:
            m = re.search(r"Trap:.*\((\S+)", line)
            if m:
                insn = m.group(1).rstrip(")")
            m = re.search(r"mismatch in (.*)", line)
            if m:
                fields = sorted(set(re.findall(r"field (\w+)", m.group(1))))
                return insn, "%s: %s" % (insn, ",".join(fields))
    # Saved regression traces have no annotation: one group per trace.
    return None, os.path.basename(path)


sail_only = {"trace": set(), "insn": set()}
if args.sail_only:
    with open(args.sail_only) as f:
        for line in f:
            words = line.split("#")[0].split()
            if words:
                if words[0] not in sail_only or len(words) < 2:
                    sys.exit("%s: bad line: %s" % (args.sail_only, line.strip()))
                sail_only[words[0]].add(words[1])


SAIL = ("sail", None, None)
PORT = ("qemu", args.port, None)
ALLIANCE = ("qemu", args.alliance, args.alliance_cpu_extra)

traces = os.path.join(args.out, "traces")
os.makedirs(traces, exist_ok=True)
if args.number_of_tests:
    extra = ["-n", str(args.number_of_tests), "-S", traces,
             "--stats-file", os.path.join(args.out, "stats.txt")]
    if args.seed is not None:
        extra += ["--seed", str(args.seed)]
    if args.test_include_regex:
        extra += ["--test-include-regex", args.test_include_regex]
    if args.test_exclude_regex:
        extra += ["--test-exclude-regex", args.test_exclude_regex]
    log = run(ALLIANCE, PORT, extra, os.path.join(args.out, "alliance-vs-port.log"))
    seed = re.search(r"Random seed: (\d+)", log)
    if not seed and not timed_out:
        # QCVEngine prints the seed first; without it nothing was compared
        # (e.g. a QEMU failed to start) and zero disagreements mean nothing.
        # (A killed QCVEngine may not have flushed it, hence the timeout case.)
        print("Alliance against the port: the random tests did not run "
              "(see alliance-vs-port.log)")
        print("%s: FAIL (random tests did not run)" % args.label)
        sys.exit(1)
    print("Alliance against the port: %d disagreements saved (seed %s)"
          % (len(os.listdir(traces)), seed.group(1) if seed else "?"))
    skipped = re.findall(r"Skipping (\S+): an implementation has died", log)
    if skipped:
        print("An implementation died; templates not voted on: %s"
              % ", ".join(skipped))
if args.traces:
    for name in os.listdir(args.traces):
        if name.endswith(".S"):
            shutil.copy(os.path.join(args.traces, name), traces)

if not any(n.endswith(".S") for n in os.listdir(traces)):
    if timed_out:
        print("%s: FAIL (timed out)" % args.label)
        sys.exit(1)
    print("%s: PASS (no traces where the QEMUs disagree)" % args.label)
    sys.exit(0)

port_ok = replay(SAIL, PORT, traces)
alliance_ok = replay(SAIL, ALLIANCE, traces)
qemus_agree = replay(ALLIANCE, PORT, traces)
groups = collections.defaultdict(list)
verdicts = []
for name in sorted(n for n in os.listdir(traces) if n.endswith(".S")):
    p, a, q = port_ok.get(name), alliance_ok.get(name), qemus_agree.get(name)
    insn, sig = signature(os.path.join(traces, name))
    if name in sail_only["trace"] or insn in sail_only["insn"]:
        verdict = ("not-replayed" if p is None else
                   "sail-only-agrees" if p else "sail-only-differs")
    elif p is None or q is None:
        verdict = "not-replayed"
    elif p and q:
        verdict = "no-difference"
    elif p:
        verdict = "alliance-differs"
    elif q:
        verdict = "sail-disagrees"
    elif a is None:
        verdict = "not-replayed"
    elif a:
        verdict = "port-differs"
    else:
        verdict = "both-differ"
    groups[(verdict, sig)].append(name)
    verdicts.append("%s %s" % (name, verdict))
if args.verdicts:
    with open(args.verdicts, "w") as f:
        f.write("".join(v + "\n" for v in verdicts))

ERRORS = ("port-differs", "both-differ", "sail-only-differs", "not-replayed")
WARNINGS = ("sail-disagrees", "alliance-differs")
order = ERRORS + WARNINGS + ("sail-only-agrees", "no-difference")
lines, warnings = [], []
for verdict in order:
    level = ("ERROR" if verdict in ERRORS else
             "WARNING" if verdict in WARNINGS else "ok")
    for (v, sig), names in sorted(groups.items()):
        if v == verdict:
            line = "%-7s %-16s %4d  %s  (e.g. %s)" % (
                level, v, len(names), sig, os.path.join(traces, names[0]))
            lines.append(line)
            if level == "WARNING":
                warnings.append(line)
summary = "\n".join(lines)
with open(os.path.join(args.out, "vote-summary.txt"), "w") as f:
    f.write(summary + "\n")
print(summary)
if args.warnings_file and warnings:
    with open(args.warnings_file, "a") as f:
        f.write("".join("%s: %s\n" % (args.label, w) for w in warnings))
failed = any(v in ERRORS for v, _ in groups)
if args.warnings_fatal and warnings:
    failed = True
if timed_out:
    print("Timed out: %s" % ", ".join(timed_out))
    failed = True
print("%s: %s%s" % (args.label, "FAIL" if failed else "PASS",
                    " (%d warning groups)" % len(warnings) if warnings else ""))
sys.exit(1 if failed else 0)
