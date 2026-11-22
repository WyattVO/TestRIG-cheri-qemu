#!/usr/bin/env python3
"""Tell whether a running QEMU is using MTTCG or round-robin TCG.

QEMU names its vCPU threads differently in the two modes, so the mode of a
QEMU that is already running can be read straight out of /proc:

  MTTCG        one thread per hart, named "CPU <n>/TCG"
               (accel/tcg/tcg-accel-ops-mttcg.c, mttcg_start_vcpu_thread)
  round-robin  one thread for all harts, named "ALL CPUs/TCG"
               (accel/tcg/tcg-accel-ops-rr.c, rr_start_vcpu_thread)

This matters because MTTCG is opt-in on the CHERI port: a gate stage that
means to test it has to prove the flag took effect, not just that it was
passed.

QEMU only writes those names into /proc when it is asked to, with
"-name debug-threads=on"; without it every thread is named after the binary
and the mode cannot be read at all. Callers must pass it -- see probe_argv.
"""
import os
import re

VCPU_MTTCG = re.compile(r"^CPU \d+/TCG$")
VCPU_ROUND_ROBIN = re.compile(r"^ALL CPUs/TCG$")


def probe_argv(argv):
    """argv plus what is needed to read the mode off a QEMU we launch.

    "-name debug-threads=on" makes QEMU name its threads (otherwise
    vcpu_thread_mode can only answer "unknown"), and "-S" starts it paused so
    it does not need a payload to reach the point where the vCPU threads
    exist. A caller that already passes -name keeps its own.
    """
    argv = list(argv)
    if "-name" not in argv:
        argv += ["-name", "debug-threads=on"]
    return argv + ["-S"]


def vcpu_thread_mode(task_dir):
    """Return (mode, vcpu_thread_count) for a /proc/<pid>/task directory.

    mode is "multi" when the threads are MTTCG vCPU threads (the count is how
    many, i.e. one per hart), "single" when they are the one round-robin
    thread, and "unknown" when neither is there or the directory cannot be
    read -- which is a different answer from "single", and callers that
    require MTTCG must treat it as such.
    """
    try:
        tids = os.listdir(task_dir)
    except OSError:
        return ("unknown", 0)

    mttcg = 0
    round_robin = 0
    for tid in tids:
        try:
            with open(os.path.join(task_dir, tid, "comm")) as f:
                comm = f.read().strip()
        except OSError:
            # The thread exited while we were looking at it; the threads we
            # did read still tell us the mode.
            continue
        if VCPU_MTTCG.match(comm):
            mttcg += 1
        elif VCPU_ROUND_ROBIN.match(comm):
            round_robin += 1

    if mttcg:
        return ("multi", mttcg)
    if round_robin:
        return ("single", 1)
    return ("unknown", 0)


def _main(argv):
    """Launch a QEMU paused (-S), print "<mode> <count>", and kill it.

    Usage: qemu_mode.py <qemu> [qemu args...]
    """
    import subprocess
    import sys
    import time

    if not argv:
        sys.exit("usage: qemu_mode.py <qemu> [qemu args...]")
    p = subprocess.Popen(probe_argv(argv),
                         stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    task_dir = "/proc/%d/task" % p.pid
    mode, count = ("unknown", 0)
    end = time.time() + 10
    try:
        while time.time() < end:
            mode, count = vcpu_thread_mode(task_dir)
            if mode != "unknown":
                break
            if p.poll() is not None:
                break
            time.sleep(0.1)
    finally:
        p.terminate()
        try:
            p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait()
    print("%s %d" % (mode, count))
    if mode == "unknown":
        err = p.stderr.read().decode(errors="replace").strip() if p.stderr else ""
        if err:
            print(err, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(_main(sys.argv[1:]))
