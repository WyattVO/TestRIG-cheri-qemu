#!/usr/bin/env python3
"""Three-way vote between the Sail CHERI-RISC-V model, CHERI-Alliance QEMU and
the CHERI QEMU under test.

Sail stays the referee for CHERI v9. CHERI-Alliance QEMU (CHERI-Alliance/qemu
main, QEMU 7.2) is a second opinion: comparing it with the QEMU under test
finds traces where the two QEMUs disagree, and replaying each of those on Sail
says which QEMU is the odd one out:

  port-differs     QEMU under test differs from Sail, Alliance agrees with
                   Sail: a bug in the port (gate failure)
  both-differ      both QEMUs differ from Sail: review against the spec
                   (gate failure; Sail is the referee)
  alliance-differs Alliance differs from Sail, the port agrees with Sail:
                   an Alliance bug or a fix the port already has (reported)
  no-difference    every pair agrees on replay (reported; a flaky trace)

The traces come from random QuickCheckVEngine tests of Alliance against the
port (-n, saved with --save-dir) and/or from an existing directory (--traces).
Traces are grouped by their first mismatching instruction and fields.

Usage: three-way-vote.py --port QEMU --alliance QEMU --out DIR
                         [-n TESTS [--seed N] [--test-include-regex RE]]
                         [--traces DIR]
Exits 1 if any trace is port-differs or both-differ.
"""
import argparse
import collections
import os
import re
import shutil
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
args = parser.parse_args()


def run(a, b, extra):
    """Run runTestRIG.py with Sail or a QEMU as A and B; return its output."""
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
    p = sub.run(cmd + extra, stdout=sub.PIPE, stderr=sub.STDOUT, text=True)
    return p.stdout


def replay(a, b, tracedir):
    """Replay every trace in tracedir; return {file name: passed}."""
    out = run(a, b, ["--no-save", "--no-shrink", "-d", tracedir])
    result, current = {}, None
    for line in out.splitlines():
        m = re.match(r"Reading trace from (.*\.S)$", line)
        if m:
            current = os.path.basename(m.group(1))
        elif current and line in ("Failure.", "No Failure."):
            result[current] = line == "No Failure."
            current = None
    return result


def signature(path):
    """First mismatching instruction and the fields that differ."""
    insn = None
    with open(path) as f:
        for line in f:
            m = re.search(r"Trap:.*\((\S+)", line)
            if m:
                insn = m.group(1).rstrip(")")
            m = re.search(r"mismatch in (.*)", line)
            if m:
                fields = sorted(set(re.findall(r"field (\w+)", m.group(1))))
                return "%s: %s" % (insn, ",".join(fields))
    return "(no mismatch annotation)"


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
    log = run(ALLIANCE, PORT, extra)
    with open(os.path.join(args.out, "alliance-vs-port.log"), "w") as f:
        f.write(log)
    seed = re.search(r"Random seed: (\d+)", log)
    print("Alliance against the port: %d disagreements saved (seed %s)"
          % (len(os.listdir(traces)), seed.group(1) if seed else "?"))
if args.traces:
    for name in os.listdir(args.traces):
        if name.endswith(".S"):
            shutil.copy(os.path.join(args.traces, name), traces)

if not any(n.endswith(".S") for n in os.listdir(traces)):
    print("THREE-WAY VOTE: PASS (no traces where the QEMUs disagree)")
    sys.exit(0)

port_ok = replay(SAIL, PORT, traces)
alliance_ok = replay(SAIL, ALLIANCE, traces)
groups = collections.defaultdict(list)
for name in sorted(n for n in os.listdir(traces) if n.endswith(".S")):
    p, a = port_ok.get(name), alliance_ok.get(name)
    if p is None or a is None:
        verdict = "not-replayed"
    elif p and not a:
        verdict = "alliance-differs"
    elif a and not p:
        verdict = "port-differs"
    elif not p:
        verdict = "both-differ"
    else:
        verdict = "no-difference"
    groups[(verdict, signature(os.path.join(traces, name)))].append(name)

order = ["port-differs", "both-differ", "not-replayed", "alliance-differs",
         "no-difference"]
lines = []
for verdict in order:
    for (v, sig), names in sorted(groups.items()):
        if v == verdict:
            lines.append("%-16s %4d  %s  (e.g. traces/%s)"
                         % (v, len(names), sig, names[0]))
summary = "\n".join(lines)
with open(os.path.join(args.out, "vote-summary.txt"), "w") as f:
    f.write(summary + "\n")
print(summary)
failed = any(v in ("port-differs", "both-differ", "not-replayed")
             for v, _ in groups)
print("THREE-WAY VOTE: %s" % ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
