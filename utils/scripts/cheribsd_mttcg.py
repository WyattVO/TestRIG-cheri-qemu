#!/usr/bin/env python3
"""The CHERIBSD_MTTCG setting: ask QEMU for MTTCG, and prove it got it.

MTTCG is opt-in on the CHERI port, so a CheriBSD stage that means to test it
has to pass -accel tcg,thread=multi *and* show in the log that the mode took
effect. Otherwise CHERIBSD_SMP=4 boots four harts round-robin and reports a
pass, which reads as MTTCG coverage without being any.

The three settings match BENCH_MTTCG's:
  off      do not ask for MTTCG (the default), and do not judge what ran
  on       ask for it, report what ran, never fail
  require  ask for it, and fail the stage unless it really ran
"""

SETTINGS = ("off", "on", "require")


def qemu_accel_args(setting):
    """QEMU options that request MTTCG, for a CHERIBSD_MTTCG setting."""
    if setting == "off":
        return []
    return ["-accel", "tcg,thread=multi"]


def check_mode(setting, mode, count, smp):
    """Judge an observed thread mode. Returns (ok, message).

    mode and count come from qemu_mode.vcpu_thread_mode. "unknown" is not
    "single": it means the mode could not be read at all, which under
    "require" is a failure rather than a silent pass.
    """
    if setting == "off":
        return (True, "")

    caveat = ""
    if smp < 2:
        # need_concurrent_tags() also requires max_cpus > 1, so lock_tag is
        # inactive at one hart however the accelerator is threaded.
        caveat = ("; note: tags are not concurrent at %d hart, so this run "
                  "does not exercise lock_tag" % smp)

    if mode == "multi" and count == smp:
        return (True, "multi, %d vCPU threads%s" % (count, caveat))

    if mode == "single":
        detail = "round-robin (one thread for all %d harts)" % smp
    elif mode == "unknown":
        detail = ("could not tell which mode QEMU used (no named vCPU "
                  "threads; is -name debug-threads=on set?)")
    else:
        detail = ("multi, but %d vCPU threads for %d harts"
                  % (count, smp))

    if setting == "require":
        return (False, "%s -- CHERIBSD_MTTCG=require" % detail)
    return (True, detail)
