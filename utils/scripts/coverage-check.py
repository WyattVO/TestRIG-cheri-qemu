#!/usr/bin/env python3
"""Check that the random tests actually ran the CHERI instructions.

QuickCheckVEngine counts every instruction it compared, split into "notrap"
(completed) and "trap" (raised an exception), and writes the table to its
stats file. A template can silently stop exercising an instruction (operands
that always fault, a filter added for a model difference, a template the
architecture string skips), and the gate would still pass. This script fails
if an instruction listed in regressions/coverage-required.txt ran fewer times
than required, and lists the known gaps and the share of the run spent on
illegal encodings and register setup.

regressions/coverage-required.txt lines:
  <mnemonic> <min notrap> [<min trap>]   required coverage
  gap <mnemonic> <reason>                known gap, reported only

Usage: coverage-check.py <stats file> [required list]
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
stats_path = sys.argv[1]
req_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    HERE, "..", "..", "regressions", "coverage-required.txt")

rows = {}
with open(stats_path) as f:
    for line in f:
        m = re.match(r"\|\s*(\S+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|", line)
        if m:
            rows[m.group(1)] = (int(m.group(2)), int(m.group(3)))
if not rows:
    sys.exit("error: no coverage table in %s" % stats_path)

status = 0
with open(req_path) as f:
    for n, line in enumerate(f, 1):
        line = line.split("#", 1)[0].split()
        if not line:
            continue
        if line[0] == "gap":
            notrap, trap = rows.get(line[1], (0, 0))
            print("gap: %s (ran %d, trapped %d): %s"
                  % (line[1], notrap, trap, " ".join(line[2:])))
            continue
        name, need = line[0], [int(x) for x in line[1:3]]
        notrap, trap = rows.get(name, (0, 0))
        short = []
        if notrap < need[0]:
            short.append("completed %d times, need %d" % (notrap, need[0]))
        if len(need) > 1 and trap < need[1]:
            short.append("trapped %d times, need %d" % (trap, need[1]))
        if short:
            print("FAIL: %s %s" % (name, "; ".join(short)))
            status = 1

total = sum(a + b for a, b in rows.values())
for label, keys in (("illegal or unknown encodings", ("reserved", "Unknown")),
                    ("register setup (lui/slli/addi)", ("lui", "slli", "addi"))):
    count = sum(sum(rows.get(k, (0, 0))) for k in keys)
    print("%s: %.1f%% of %d instructions" % (label, 100.0 * count / total, total))
print("COVERAGE: %s" % ("FAIL" if status else "PASS"))
sys.exit(status)
