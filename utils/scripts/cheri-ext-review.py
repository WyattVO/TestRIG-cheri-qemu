#!/usr/bin/env python3
"""Check that every RISC-V CPU extension and CPU model a CHERI QEMU offers
has been reviewed for CHERI.

Every extension that touches memory, addresses, control flow or privileged
state can bypass capability checks, so a rebase onto a newer QEMU (which adds
extensions and CPU models) must not enable one silently. This script

  1. asks QEMU (QMP query-cpu-model-expansion of the "max" CPU) for every
     extension property and fails on any that regressions/cheri-extensions.txt
     does not list (an unreviewed extension), or that is listed but gone;
  2. starts QEMU with each extension listed as "refused" and fails unless the
     CHERI extension policy refuses it;
  3. starts every CPU model in "-cpu help" and fails if one crashes QEMU.

Usage: cheri-ext-review.py <qemu-system-riscv64xcheri>
"""
import json
import os
import subprocess as sub
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIST = os.path.join(HERE, "..", "..", "regressions", "cheri-extensions.txt")
STATUSES = ("allowed", "refused")


def read_list():
    exts = {}
    with open(LIST) as f:
        for n, line in enumerate(f, 1):
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            name, status = line.split()[:2]
            if status not in STATUSES:
                sys.exit("%s:%d: unknown status %r" % (LIST, n, status))
            exts[name] = status
    return exts


def qemu_ext_props(qemu):
    qmp = ('{"execute":"qmp_capabilities"}\n'
           '{"execute":"query-cpu-model-expansion","arguments":'
           '{"type":"full","model":{"name":"max"}}}\n'
           '{"execute":"quit"}\n')
    out = sub.run([qemu, "-M", "none", "-display", "none", "-qmp", "stdio"],
                  input=qmp, capture_output=True, text=True, timeout=30).stdout
    for line in out.splitlines():
        ret = json.loads(line).get("return") if line.startswith("{") else None
        if isinstance(ret, dict) and "model" in ret:
            return {k for k, v in ret["model"]["props"].items()
                    if isinstance(v, bool)}
    sys.exit("error: could not query the CPU properties of " + qemu)


def start(qemu, cpu):
    """'started', 'refused', 'rejected' or 'crashed' (like testrig-gate.sh)."""
    try:
        p = sub.run([qemu, "-machine", "virt", "-cpu", cpu, "-bios", "none",
                     "-S", "-display", "none", "-monitor", "none",
                     "-serial", "none"], capture_output=True, text=True,
                    timeout=3)
    except sub.TimeoutExpired:
        return "started"
    if p.returncode < 0 or p.returncode > 128:
        return "crashed"
    if "is not supported on CHERI CPUs" in p.stderr:
        return "refused"
    return "rejected"


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    qemu = sys.argv[1]
    status = 0
    listed = read_list()
    props = qemu_ext_props(qemu)

    for name in sorted(props - set(listed)):
        print("FAIL: extension %s is not reviewed for CHERI: decide whether it "
              "can bypass capability checks, then list it in "
              "regressions/cheri-extensions.txt (refused, or allowed with a "
              "test)" % name)
        status = 1
    for name in sorted(set(listed) - props):
        print("FAIL: %s is listed in regressions/cheri-extensions.txt but this "
              "QEMU has no such extension (renamed or removed?)" % name)
        status = 1
    for name in sorted(n for n, s in listed.items() if s == "refused"):
        if name not in props:
            continue
        got = start(qemu, "rv64,%s=true" % name)
        if got != "refused":
            print("FAIL: -cpu rv64,%s=true %s, expected refused" % (name, got))
            status = 1
    print("ok: %d extensions reviewed (%d refused)" %
          (len(props & set(listed)),
           sum(1 for n in props if listed.get(n) == "refused")))

    out = sub.run([qemu, "-cpu", "help"], capture_output=True, text=True,
                  timeout=30).stdout
    models = out.replace("Available CPUs:", "").split()
    crashed = [m for m in models if start(qemu, m) == "crashed"]
    for m in crashed:
        print("FAIL: -cpu %s crashes QEMU" % m)
        status = 1
    print("ok: %d CPU models start or are rejected cleanly" %
          (len(models) - len(crashed)))
    return status


if __name__ == "__main__":
    sys.exit(main())
