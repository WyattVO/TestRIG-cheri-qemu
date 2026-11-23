#!/usr/bin/env python3
"""Find and reap QEMU processes left over from an earlier run.

A QEMU started paused ("-S") with "-monitor none -serial none" has no way to
be driven and no way to exit on its own. Every launcher in this tree reaps
its own QEMU -- testrig-gate.sh's qemu_start uses "timeout 3",
runTestRIG.qemu_accepts_cpu and cheri-ext-review.start use subprocess.run
with a timeout, cheribsd-tests.Console.kill sends SIGKILL, and
qemu_mode._main terminates in a finally -- but a QEMU launched by hand, or
by a script that is interrupted before it reaps, is reparented to init and
then runs until someone kills it. One such process was found on 2026-11-22
still holding 120 MB after 4h46m, orphaned to init, with its stdio on
/dev/null.

A leftover is not only wasted memory. The gate's bench stage measures
throughput, so a stray QEMU competing for the host CPU skews the numbers the
gate records, and a stray that was started under MTTCG can have one busy
thread per hart. The gate therefore looks for leftovers before it measures
anything, and says what to do about them.

Used as a script: stray_qemu.py <qemu> [--kill]
  Prints one line per leftover and exits 1 if there are any; --kill reaps
  them first (SIGTERM, then SIGKILL) and exits 0 if they all died.
"""
import os
import signal
import time


def find_strays(qemu_path, procfs="/proc", exclude=()):
    """[(pid, argv)] for every process whose executable is qemu_path.

    Sorted by pid. exclude drops pids the caller knows about -- the gate's
    own QEMU is not a leftover. This process is always excluded. Processes
    whose exe link cannot be read (kernel threads, other users' processes)
    are skipped: a process we cannot identify is not one we should report.
    """
    target = os.path.realpath(qemu_path)
    skip = set(exclude) | {os.getpid()}
    found = []
    try:
        entries = os.listdir(procfs)
    except OSError:
        return found

    for entry in entries:
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid in skip:
            continue
        try:
            exe = os.path.realpath(os.readlink(os.path.join(procfs, entry, "exe")))
        except OSError:
            continue
        if exe != target:
            continue
        try:
            with open(os.path.join(procfs, entry, "cmdline"), "rb") as f:
                argv = [a for a in f.read().decode(errors="replace").split("\0") if a]
        except OSError:
            argv = []
        found.append((pid, argv))
    return sorted(found)


def age_seconds(pid, procfs="/proc"):
    """How long pid has been running, or None if it cannot be told."""
    try:
        return max(0.0, time.time() - os.stat(os.path.join(procfs, str(pid))).st_ctime)
    except OSError:
        return None


def alive(pid, procfs="/proc"):
    """Whether pid is a process that is still running.

    A process that has exited but whose parent has not collected it yet is a
    zombie: it is gone, but it keeps its pid, so os.kill(pid, 0) still
    succeeds on it. Treating that as "still running" would make reap wait out
    its whole timeout and then report failure for a process it did kill. A
    stray reaped by this script is an orphan, so init collects it at once and
    the zombie window is short, but it is not always empty.
    """
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    try:
        with open(os.path.join(procfs, str(pid), "stat")) as f:
            # "pid (comm) state ...", and comm may itself hold ") ".
            return f.read().rpartition(")")[2].split()[0] != "Z"
    except (OSError, IndexError):
        return True


def reap(pid, timeout=5.0):
    """Kill pid: SIGTERM, then SIGKILL if it is still there. True if it died.

    A paused QEMU does answer SIGTERM (verified against
    qemu-system-riscv64xcheri 10.2), so the SIGKILL is only a backstop for
    one that is wedged.
    """
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            return True
        except PermissionError:
            return False
        end = time.time() + timeout
        while time.time() < end:
            if not alive(pid):
                return True
            time.sleep(0.1)
    return not alive(pid)


def _main(argv):
    import sys

    args = [a for a in argv if not a.startswith("--")]
    do_kill = "--kill" in argv
    if len(args) != 1 or set(argv) - set(args) - {"--kill"}:
        sys.exit("usage: stray_qemu.py <qemu> [--kill]")

    strays = find_strays(args[0])
    if not strays:
        return 0

    status = 0
    for pid, cmd in strays:
        age = age_seconds(pid)
        when = "unknown age" if age is None else "%d min old" % (age // 60)
        print("stray QEMU: pid %d, %s: %s" % (pid, when, " ".join(cmd)))
        if do_kill:
            if reap(pid):
                print("  killed")
            else:
                print("  could not kill it")
                status = 1
        else:
            status = 1
    if not do_kill:
        print("These are left over from an earlier run and compete with this "
              "one for the host CPU, which skews the bench stage. Reap them "
              "with: %s %s --kill" % (sys.argv[0], args[0]))
    return status


if __name__ == "__main__":
    import sys

    sys.exit(_main(sys.argv[1:]))
