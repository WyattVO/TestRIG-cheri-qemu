#!/usr/bin/env python3
"""Boot CheriBSD on a CHERI QEMU and run cheribsdtest.

Boots the riscv64-purecap disk image built by cheribuild, logs in as root on
the serial console and runs `cheribsdtest-purecap -a` and
`cheribsdtest-hybrid -a`. Exits 0 only if both suites report no unexpected
failures (expected failures, XFAIL, are fine). The disk image is opened with
snapshot=on, so it is never modified.

Usage: cheribsd-tests.py <qemu-system-riscv64xcheri> <cheribuild-output-dir>
                         [--log FILE] [--suite NAME ...]

<cheribuild-output-dir> is cheribuild's output root (it contains
cheribsd-riscv64-purecap.img, rootfs-riscv64-purecap/ and sdk/).
"""
import argparse
import os
import pty
import re
import select
import sys
import time

PROMPT = rb"root@[^:]*:~ # $"


class Console:
    def __init__(self, argv, log):
        self.log = log
        self.buf = b""
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.execv(argv[0], argv)

    def expect(self, pattern, timeout):
        """Wait for pattern; return the output before the match."""
        end = time.time() + timeout
        while time.time() < end:
            ready, _, _ = select.select([self.fd], [], [], 1)
            if ready:
                try:
                    data = os.read(self.fd, 65536)
                except OSError:
                    raise SystemExit("error: QEMU exited")
                self.log.write(data)
                self.buf += data
                m = re.search(pattern, self.buf, re.M)
                if m:
                    before = self.buf[:m.start()]
                    self.buf = self.buf[m.end():]
                    return before
            if os.waitpid(self.pid, os.WNOHANG)[0]:
                raise SystemExit("error: QEMU exited")
        raise SystemExit("error: timed out waiting for %r" % pattern)

    def run(self, cmd, timeout):
        """Run a shell command; return its output."""
        os.write(self.fd, cmd.encode() + b"; echo @@RC=$?@@\r")
        out = self.expect(rb"@@RC=\d+@@", timeout)
        self.expect(PROMPT, 60)
        return out.decode(errors="replace").replace("\r", "")

    def kill(self):
        try:
            os.kill(self.pid, 9)
        except ProcessLookupError:
            pass


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("qemu")
    p.add_argument("output", help="cheribuild output directory")
    p.add_argument("--log", default="cheribsd-tests.log",
                   help="console log (default: %(default)s)")
    p.add_argument("--suite", action="append",
                   help="cheribsdtest binary to run (default: purecap and hybrid)")
    args = p.parse_args()
    suites = args.suite or ["cheribsdtest-purecap", "cheribsdtest-hybrid"]

    out = args.output
    files = {
        "bios": os.path.join(out, "sdk/bbl/riscv64-purecap/bbl"),
        "kernel": os.path.join(out, "rootfs-riscv64-purecap/boot/kernel/kernel"),
        "disk": os.path.join(out, "cheribsd-riscv64-purecap.img"),
    }
    for name, path in files.items():
        if not os.path.exists(path):
            sys.exit("error: %s not found: %s" % (name, path))

    argv = [args.qemu, "-M", "virt", "-m", "2048", "-nographic",
            "-bios", files["bios"], "-kernel", files["kernel"],
            "-drive", "if=none,file=%s,id=drv,format=raw,snapshot=on" % files["disk"],
            "-device", "virtio-blk-device,drive=drv",
            "-device", "virtio-rng-pci"]
    status = 0
    with open(args.log, "wb", buffering=0) as log:
        con = Console(argv, log)
        try:
            con.expect(rb"login: ", 3600)
            os.write(con.fd, b"root\r")
            con.expect(PROMPT, 600)
            for suite in suites:
                text = con.run("%s -a > /root/out.txt 2>&1; "
                               "grep -E '^FAIL|SUMMARY' /root/out.txt" % suite,
                               4 * 3600)
                summary = re.search(r"SUMMARY: (.*)", text)
                fails = re.findall(r"^FAIL: .*", text, re.M)
                print("%s: %s" % (suite, summary.group(1) if summary
                                  else "no summary (did it crash?)"))
                for line in fails:
                    print("  " + line)
                if not summary or fails:
                    status = 1
            os.write(con.fd, b"shutdown -p now\r")
            try:
                con.expect(rb"(Powering off|Uptime:)", 600)
            except SystemExit:
                pass
        finally:
            con.kill()
    print("CHERIBSD TESTS: %s" % ("PASS" if status == 0 else "FAIL"))
    return status


if __name__ == "__main__":
    sys.exit(main())
