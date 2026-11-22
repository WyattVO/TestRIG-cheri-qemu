#!/usr/bin/env python3
"""Tests for qemu_mode.vcpu_thread_mode (run: python3 test_qemu_mode.py)."""
import os
import tempfile
import unittest

from qemu_mode import probe_argv, vcpu_thread_mode


def task_dir(names):
    """A directory shaped like /proc/<pid>/task, one subdir per thread name."""
    d = tempfile.mkdtemp()
    for i, name in enumerate(names):
        os.mkdir(os.path.join(d, str(100 + i)))
        with open(os.path.join(d, str(100 + i), "comm"), "w") as f:
            f.write(name + "\n")
    return d


class TestVcpuThreadMode(unittest.TestCase):
    def test_mttcg_reports_multi_and_counts_harts(self):
        d = task_dir(["qemu-system-risc", "CPU 0/TCG", "CPU 1/TCG",
                      "CPU 2/TCG", "CPU 3/TCG", "IO mon_iothread"])
        self.assertEqual(vcpu_thread_mode(d), ("multi", 4))

    def test_round_robin_reports_single(self):
        d = task_dir(["qemu-system-risc", "ALL CPUs/TCG", "IO mon_iothread"])
        self.assertEqual(vcpu_thread_mode(d), ("single", 1))

    def test_no_vcpu_thread_reports_unknown(self):
        self.assertEqual(vcpu_thread_mode(task_dir(["qemu-system-risc"])),
                         ("unknown", 0))

    def test_missing_directory_reports_unknown(self):
        self.assertEqual(vcpu_thread_mode("/nonexistent/task"), ("unknown", 0))

    def test_lookalike_name_is_not_a_vcpu_thread(self):
        d = task_dir(["notCPU 0/TCG", "CPU 0/TCGx"])
        self.assertEqual(vcpu_thread_mode(d), ("unknown", 0))


class TestProbeArgv(unittest.TestCase):
    def test_asks_qemu_to_name_its_threads(self):
        # Without debug-threads=on QEMU leaves every thread named after the
        # binary, so vcpu_thread_mode can only ever answer "unknown".
        self.assertEqual(
            probe_argv(["qemu-system-riscv64xcheri", "-M", "virt"]),
            ["qemu-system-riscv64xcheri", "-M", "virt",
             "-name", "debug-threads=on", "-S"])

    def test_does_not_add_a_second_name_option(self):
        got = probe_argv(["qemu", "-name", "guest=x,debug-threads=on"])
        self.assertEqual(got.count("-name"), 1)
        self.assertIn("-S", got)


if __name__ == "__main__":
    unittest.main()
