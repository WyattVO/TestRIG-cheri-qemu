#!/usr/bin/env python3
"""Tests for stray_qemu (run: python3 test_stray_qemu.py)."""
import contextlib
import io
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

import stray_qemu
from stray_qemu import age_seconds, alive, find_strays, reap


def procfs(entries, exe_target):
    """A directory shaped like /proc.

    entries maps a pid to the argv of that process, or to None for a process
    whose exe link cannot be read (a kernel thread, or one owned by someone
    else). A pid whose argv[0] is not exe_target gets its own exe target, so
    a tree can hold both matching and non-matching processes.
    """
    root = tempfile.mkdtemp()
    for pid, argv in entries.items():
        d = os.path.join(root, str(pid))
        os.mkdir(d)
        if argv is None:
            continue
        target = exe_target if argv[0] == exe_target else argv[0]
        os.symlink(target, os.path.join(d, "exe"))
        with open(os.path.join(d, "cmdline"), "wb") as f:
            f.write(b"\0".join(a.encode() for a in argv) + b"\0")
    # Entries that are not pids at all; /proc is full of them.
    for name in ("self", "cpuinfo", "sys"):
        os.mkdir(os.path.join(root, name))
    return root


class TestFindStrays(unittest.TestCase):
    def setUp(self):
        self.qemu = self.a_file("-qemu")
        self.other = self.a_file("-other")

    def a_file(self, suffix):
        fd, path = tempfile.mkstemp(suffix=suffix)
        os.close(fd)
        self.addCleanup(os.unlink, path)
        return path

    def test_finds_a_process_running_the_qemu_under_test(self):
        root = procfs({91234: [self.qemu, "-M", "virt", "-S"]}, self.qemu)
        self.assertEqual(find_strays(self.qemu, procfs=root),
                         [(91234, [self.qemu, "-M", "virt", "-S"])])

    def test_ignores_a_different_binary(self):
        root = procfs({4242: [self.other, "-M", "virt"]}, self.qemu)
        self.assertEqual(find_strays(self.qemu, procfs=root), [])

    def test_ignores_non_pid_entries_and_unreadable_processes(self):
        root = procfs({777: None}, self.qemu)
        self.assertEqual(find_strays(self.qemu, procfs=root), [])

    def test_excludes_pids_the_caller_owns(self):
        # The gate's own QEMU must not be reported as a leftover.
        root = procfs({10: [self.qemu, "-S"], 11: [self.qemu, "-S"]}, self.qemu)
        self.assertEqual([pid for pid, _ in
                          find_strays(self.qemu, procfs=root, exclude=(10,))],
                         [11])

    def test_resolves_the_path_before_comparing(self):
        # The gate is given build-mttcg/qemu-...; /proc/<pid>/exe is absolute.
        link = self.qemu + "-link"
        os.symlink(self.qemu, link)
        self.addCleanup(os.unlink, link)
        root = procfs({55: [self.qemu, "-S"]}, self.qemu)
        self.assertEqual([pid for pid, _ in find_strays(link, procfs=root)],
                         [55])

    def test_reports_every_stray_in_pid_order(self):
        root = procfs({300: [self.qemu, "-S"], 100: [self.qemu, "-S"],
                       200: [self.other, "-S"]}, self.qemu)
        self.assertEqual([pid for pid, _ in find_strays(self.qemu, procfs=root)],
                         [100, 300])

    def test_no_strays_is_the_normal_case(self):
        self.assertEqual(find_strays(self.qemu, procfs=procfs({}, self.qemu)), [])


def spawn(body):
    """A short-lived child process running body, killed when the test ends."""
    return subprocess.Popen([sys.executable, "-I", "-c", body],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)


def state(pid):
    """The process state letter from /proc/<pid>/stat, or None if it is gone."""
    try:
        with open("/proc/%d/stat" % pid) as f:
            return f.read().rpartition(")")[2].split()[0]
    except (OSError, IndexError):
        return None


SLEEP = "import time; time.sleep(60)"
IGNORE_SIGTERM = ("import signal, time; "
                  "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                  "print('ready', flush=True); time.sleep(60)")


class TestAlive(unittest.TestCase):
    def test_a_zombie_is_not_alive(self):
        # An exited child that nobody has collected keeps its pid, so
        # os.kill(pid, 0) still succeeds on it. Reporting that as alive made
        # reap wait out its whole timeout and then deny it had killed it.
        p = spawn("pass")
        self.addCleanup(p.wait)
        # Wait for the kernel to mark it Z, without calling poll()/wait():
        # either of those collects the child and the zombie disappears.
        end = time.time() + 5
        while time.time() < end and state(p.pid) != "Z":
            time.sleep(0.02)
        self.assertEqual(state(p.pid), "Z", "expected an uncollected child")
        self.assertFalse(alive(p.pid))

    def test_a_running_process_is_alive(self):
        p = spawn(SLEEP)
        self.addCleanup(lambda: (p.kill(), p.wait()))
        self.assertTrue(alive(p.pid))

    def test_a_pid_that_does_not_exist_is_not_alive(self):
        self.assertFalse(alive(2 ** 22 - 1))


class TestReap(unittest.TestCase):
    def kill_later(self, p):
        self.addCleanup(lambda: (p.kill(), p.wait()) if p.poll() is None else None)
        return p

    def test_sigterm_is_enough_for_a_normal_process(self):
        p = self.kill_later(spawn(SLEEP))
        self.assertTrue(reap(p.pid, timeout=5))
        self.assertIsNotNone(p.wait(timeout=5))

    def test_escalates_to_sigkill_when_sigterm_is_ignored(self):
        # The case that matters: a wedged QEMU that does not answer SIGTERM
        # must still be reaped, or the gate reports a stray it cannot clear.
        p = self.kill_later(subprocess.Popen(
            [sys.executable, "-I", "-c", IGNORE_SIGTERM],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL))
        assert p.stdout is not None
        self.addCleanup(p.stdout.close)
        self.assertEqual(p.stdout.readline().strip(), b"ready")
        self.assertTrue(reap(p.pid, timeout=1))
        self.assertEqual(p.wait(timeout=5), -signal.SIGKILL)

    def test_a_process_that_is_already_gone_counts_as_reaped(self):
        p = spawn("pass")
        p.wait(timeout=5)
        # The pid is still unreaped by us but the process is a zombie/gone;
        # os.kill on a zombie succeeds, so use a pid that cannot exist.
        self.assertTrue(reap(2 ** 22 - 1, timeout=0.2))

    def test_reports_failure_when_the_signal_is_refused(self):
        # A process owned by someone else: os.kill raises PermissionError and
        # reap must say so rather than claim success.
        with mock.patch("os.kill", side_effect=PermissionError):
            self.assertFalse(reap(1234, timeout=0.2))


class TestAgeSeconds(unittest.TestCase):
    def test_reports_the_age_of_a_live_process(self):
        p = spawn(SLEEP)
        self.addCleanup(lambda: (p.kill(), p.wait()))
        age = age_seconds(p.pid)
        self.assertIsNotNone(age)
        self.assertGreaterEqual(age, 0)
        self.assertLess(age, 60)

    def test_unknown_for_a_process_that_does_not_exist(self):
        self.assertIsNone(age_seconds(2 ** 22 - 1))


class TestMain(unittest.TestCase):
    def run_main(self, argv, strays):
        out = io.StringIO()
        with mock.patch.object(stray_qemu, "find_strays", return_value=strays), \
                contextlib.redirect_stdout(out):
            rc = stray_qemu._main(argv)
        return rc, out.getvalue()

    def test_clean_host_is_silent_and_succeeds(self):
        rc, out = self.run_main(["/path/to/qemu"], [])
        self.assertEqual((rc, out), (0, ""))

    def test_reports_strays_and_fails_without_kill(self):
        rc, out = self.run_main(["/q"], [(91234, ["/q", "-S"])])
        self.assertEqual(rc, 1)
        self.assertIn("pid 91234", out)
        self.assertIn("--kill", out)

    def test_kill_reaps_and_succeeds(self):
        with mock.patch.object(stray_qemu, "reap", return_value=True) as r:
            rc, out = self.run_main(["/q", "--kill"], [(5, ["/q"])])
        self.assertEqual(rc, 0)
        self.assertIn("killed", out)
        r.assert_called_once_with(5)

    def test_kill_that_fails_is_reported_as_failure(self):
        with mock.patch.object(stray_qemu, "reap", return_value=False):
            rc, out = self.run_main(["/q", "--kill"], [(5, ["/q"])])
        self.assertEqual(rc, 1)
        self.assertIn("could not kill", out)

    def test_bad_usage_exits_rather_than_guessing(self):
        with self.assertRaises(SystemExit):
            stray_qemu._main([])
        with self.assertRaises(SystemExit):
            stray_qemu._main(["/q", "--bogus"])


if __name__ == "__main__":
    unittest.main()
