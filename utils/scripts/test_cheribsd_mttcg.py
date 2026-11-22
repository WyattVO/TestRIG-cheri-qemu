#!/usr/bin/env python3
"""Tests for cheribsd_mttcg (run: python3 test_cheribsd_mttcg.py)."""
import unittest

from cheribsd_mttcg import check_mode, qemu_accel_args


class TestAccelArgs(unittest.TestCase):
    def test_off_adds_nothing(self):
        self.assertEqual(qemu_accel_args("off"), [])

    def test_on_and_require_ask_for_multi(self):
        self.assertEqual(qemu_accel_args("on"), ["-accel", "tcg,thread=multi"])
        self.assertEqual(qemu_accel_args("require"),
                         ["-accel", "tcg,thread=multi"])


class TestCheckMode(unittest.TestCase):
    # check_mode(setting, mode, count, smp) -> (ok: bool, message: str)
    def test_require_passes_when_mttcg_ran_on_every_hart(self):
        ok, msg = check_mode("require", "multi", 4, 4)
        self.assertTrue(ok)
        self.assertIn("multi", msg)

    def test_require_fails_on_round_robin(self):
        ok, msg = check_mode("require", "single", 1, 4)
        self.assertFalse(ok)
        self.assertIn("round-robin", msg)

    def test_require_fails_distinctly_when_mode_is_unknown(self):
        ok, msg = check_mode("require", "unknown", 0, 4)
        self.assertFalse(ok)
        self.assertIn("could not tell", msg)

    def test_require_fails_when_threads_do_not_cover_every_hart(self):
        ok, msg = check_mode("require", "multi", 2, 4)
        self.assertFalse(ok)
        self.assertIn("4", msg)

    def test_on_does_not_fail_on_round_robin(self):
        ok, _ = check_mode("on", "single", 1, 4)
        self.assertTrue(ok)

    def test_off_never_fails_and_never_checks(self):
        for mode, count in [("single", 1), ("unknown", 0), ("multi", 4)]:
            self.assertTrue(check_mode("off", mode, count, 4)[0])

    def test_single_hart_warns_that_tags_are_not_concurrent(self):
        ok, msg = check_mode("require", "multi", 1, 1)
        self.assertTrue(ok)
        self.assertIn("not concurrent", msg)


if __name__ == "__main__":
    unittest.main()
