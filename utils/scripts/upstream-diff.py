#!/usr/bin/env python3
"""Compare the CHERI QEMU port with unmodified upstream QEMU on non-CHERI code.

Every riscv-arch-test program in the selected RV64 suites is assembled once
(utils/upstream-diff/model_test.h, link.ld) and run on both QEMUs with the
execlog plugin. For each test the two runs must produce

  1. the same signature (printed on the UART by RVMODEL_HALT), and
  2. the same instruction trace: PC, opcode, disassembly, memory accesses and
     writes to the GPRs, FPRs, FP status and main M-mode CSRs.

Upstream QEMU is the reference here: outside capability mode, with the
default (almighty) DDC and PCC, a CHERI CPU must run plain RISC-V code exactly
as upstream does. A difference listed in utils/upstream-diff/expected.txt
(with its reason) is reported but does not fail.

Trace normalisation: the vCPU number and the disassembly are dropped (the
port's disassembler names some encodings differently, e.g. Zimop ones after
the CHERI or Zfa instructions sharing their opcode space; the opcode is
compared), so are the register deltas on the first instruction (upstream
reads the initial mstatus before reset), misa.X (bit 23: Xcheri is a
non-standard extension) is cleared in values read from misa, and the trace
ends at the store to the exit device (the final "j ." loop runs until the
device stops QEMU).

Usage: upstream-diff.py --upstream QEMU --port QEMU --arch-test DIR --out DIR
                        [--suites I,M,...] [--jobs N]
Each QEMU's execlog plugin is taken from <qemu dir>/contrib/plugins.
Exits 1 on an unexpected difference or a test that runs on upstream only.
"""
import argparse
import concurrent.futures
import glob
import os
import re
import subprocess as sub
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, "..", "upstream-diff")

# suite: (-march for the assembler, extra -cpu properties for both QEMUs)
SUITES = {
    "I":         ("rv64i_zicsr", ""),
    "M":         ("rv64im_zicsr", ""),
    "A":         ("rv64ia_zicsr", ""),
    "C":         ("rv64imc_zicsr_zcb_zba_zbb", "zcb=true,zba=true,zbb=true"),
    "F":         ("rv64ifd_zicsr", ""),
    "D":         ("rv64ifd_zicsr", ""),
    "F_Zfa":     ("rv64ifd_zicsr_zfa", "zfa=true"),
    "D_Zfa":     ("rv64ifd_zicsr_zfa", "zfa=true"),
    "Zfh":       ("rv64ifd_zicsr_zfh", "zfh=true"),
    "B":         ("rv64i_zicsr_zba_zbb_zbc_zbs",
                  "zba=true,zbb=true,zbc=true,zbs=true"),
    "K":         ("rv64i_zicsr_zbkb_zbkc_zbkx_zknd_zkne_zknh_zksed_zksh",
                  "zbkb=true,zbkc=true,zbkx=true,zknd=true,zkne=true,"
                  "zknh=true,zksed=true,zksh=true"),
    "CMO":       ("rv64i_zicsr_zicbom_zicboz_zicbop",
                  "zicbom=true,zicboz=true,zicbop=true"),
    "Zicond":    ("rv64i_zicsr_zicond", "zicond=true"),
    "Zacas":     ("rv64ia_zicsr_zacas", "zacas=true"),
    "Zimop":     ("rv64i_zicsr_zimop", "zimop=true"),
    "Zcmop":     ("rv64ic_zicsr_zcmop", "zcmop=true"),
    "Zifencei":  ("rv64i_zicsr_zifencei", ""),
    "privilege": ("rv64ic_zicsr", ""),
}
REGS = ("ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 s2 s3 s4 s5 s6 s7 "
        "s8 s9 s10 s11 t3 t4 t5 t6 ft0 ft1 ft2 ft3 ft4 ft5 ft6 ft7 fs0 fs1 "
        "fa0 fa1 fa2 fa3 fa4 fa5 fa6 fa7 fs2 fs3 fs4 fs5 fs6 fs7 fs8 fs9 fs10 "
        "fs11 ft8 ft9 ft10 ft11 fflags frm fcsr mstatus mcause mepc mtval "
        "mscratch mtvec").split()
# Tests that trap on purpose need the suite's M-mode trap handler; the others
# declare their own trap signature area and must not get it.
TRAPPING = r"/(c?ebreak|ecall|misalign)[^/]*\.S$"
TRAP_HANDLER = ["-Drvtest_mtrap_routine=True"]
CSR_READS = (0x1073, 0x2073, 0x3073, 0x5073, 0x6073, 0x7073)  # csrrw ... csrrci
CSR_MISA = 0x301
MISA_X = 1 << 23
EXIT_DEVICE = 0x100000  # RVMODEL_TEST_EXIT in model_test.h
# Not "reg=*": upstream 10.2's execlog asserts on registers it cannot read
# (trigger and hypervisor CSRs).

parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
parser.add_argument("--upstream", required=True)
parser.add_argument("--port", required=True)
parser.add_argument("--arch-test", required=True, help="riscv-arch-test checkout")
parser.add_argument("--out", required=True)
parser.add_argument("--suites", default=",".join(SUITES))
parser.add_argument("--jobs", type=int, default=os.cpu_count())
parser.add_argument("--cc", default=os.environ.get("CROSS_CC", "riscv64-linux-gnu-gcc"))
parser.add_argument("--timeout", type=int, default=30)
args = parser.parse_args()


def read_expected():
    expected = {}
    path = os.path.join(MODEL, "expected.txt")
    if os.path.exists(path):
        with open(path) as f:
            for line in f:
                line = line.split("#", 1)[0].strip()
                if line:
                    name, reason = line.split(None, 1)
                    expected[name] = reason
    return expected


def run_qemu(qemu, elf, cpu, base):
    plugin = os.path.join(os.path.dirname(qemu), "contrib", "plugins", "libexeclog.so")
    plugin += "".join(",reg=" + r for r in REGS)
    # thread=single: under MTTCG the plugin reads its registers before the
    # vCPU is reset, when a CHERI PCC has no ASR permission and the CSR
    # reads fail (execlog then asserts). The tests use one hart either way.
    cmd = [qemu, "-M", "virt", "-accel", "tcg,thread=single", "-cpu", cpu,
           "-bios", "none", "-kernel", elf,
           "-display", "none", "-monitor", "none", "-serial", "file:" + base + ".sig",
           "-plugin", plugin, "-d", "plugin", "-D", base + ".trace"]
    try:
        p = sub.run(cmd, stdout=sub.DEVNULL, stderr=sub.PIPE, text=True,
                    timeout=args.timeout)
    except sub.TimeoutExpired:
        return "timeout"
    return "ok" if p.returncode == 0 else "exit %d: %s" % (
        p.returncode, p.stderr.strip().splitlines()[-1] if p.stderr.strip() else "")


def normalised_trace(path):
    lines = []
    with open(path) as f:
        for n, line in enumerate(f):
            # "vcpu, pc, opcode, "disassembly"[, accesses and register deltas]"
            _, pc, opcode, rest = line.rstrip("\n").split(", ", 3)
            effects = rest.split('", ', 1)[1] if '", ' in rest else ""
            if n == 0:
                effects = ""
            op = int(opcode, 16)
            if op & 0x707f in CSR_READS and op >> 20 == CSR_MISA:
                effects = re.sub(r"-> 0x([0-9a-f]+)", lambda m: "-> 0x%016x" % (
                    int(m.group(1), 16) & ~MISA_X), effects, count=1)
            lines.append("%s, %s, %s" % (pc, opcode, effects))
            if "store, 0x%08x" % EXIT_DEVICE in effects:
                break
    return lines


def compare(suite, src):
    march, extra = SUITES[suite]
    name = "%s/%s" % (suite, os.path.basename(src)[:-2])
    base = os.path.join(args.out, suite, os.path.basename(src)[:-2])
    elf = base + ".elf"
    cc = sub.run([args.cc, "-march=" + march, "-mabi=lp64", "-static",
                  "-mcmodel=medany", "-fno-pic", "-no-pie", "-nostdlib", "-nostartfiles",
                  "-T", os.path.join(MODEL, "link.ld"), "-I", MODEL,
                  "-I", os.path.join(args.arch_test, "riscv-test-suite", "env"),
                  "-DXLEN=64", "-DFLEN=64", "-DTEST_CASE_1=True", src, "-o", elf]
                 + TRAP_HANDLER * bool(re.search(TRAPPING, src)),
                 stdout=sub.PIPE, stderr=sub.STDOUT, text=True)
    if cc.returncode != 0:
        return name, "not-built", cc.stdout.strip().splitlines()[-1]
    # The port refuses H on CHERI CPUs; with H, upstream's misa sends the
    # suite's trap handler down its hypervisor path.
    cpu = "rv64,h=false" + ("," + extra if extra else "")
    up = run_qemu(args.upstream, elf, cpu, base + ".upstream")
    port = run_qemu(args.port, elf, cpu, base + ".port")
    if up != "ok":
        return name, "upstream-fails", up
    if port != "ok":
        return name, "port-fails", port
    with open(base + ".upstream.sig") as a, open(base + ".port.sig") as b:
        if a.read() != b.read():
            return name, "signature-differs", ""
    ta, tb = normalised_trace(base + ".upstream.trace"), normalised_trace(base + ".port.trace")
    for i, (la, lb) in enumerate(zip(ta, tb)):
        if la != lb:
            return name, "trace-differs", "line %d:\n  upstream: %s\n  port:     %s" % (i, la, lb)
    if len(ta) != len(tb):
        return name, "trace-differs", "length %d vs %d" % (len(ta), len(tb))
    for ext in (".upstream.trace", ".port.trace", ".elf"):
        os.remove(base + ext)  # keep the evidence of differences only
    return name, "same", ""


jobs = []
for suite in args.suites.split(","):
    os.makedirs(os.path.join(args.out, suite), exist_ok=True)
    for src in sorted(glob.glob(os.path.join(args.arch_test, "riscv-test-suite",
                                             "rv64i_m", suite, "src", "*.S"))):
        jobs.append((suite, src))

expected = read_expected()
counts, status = {}, 0
with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
    results = sorted(pool.map(lambda j: compare(*j), jobs))
for name, verdict, detail in results:
    suite = name.split("/")[0]
    counts.setdefault(suite, {}).setdefault(verdict, 0)
    counts[suite][verdict] += 1
    if verdict == "same":
        continue
    reason = expected.get(name) or expected.get(suite + "/*")
    if reason:
        print("expected: %s %s (%s)" % (name, verdict, reason))
    elif verdict == "not-built":
        print("skipped: %s does not assemble (%s)" % (name, detail))
    else:
        print("FAIL: %s %s %s" % (name, verdict, detail))
        status = 1
for suite in args.suites.split(","):
    print("%-10s %s" % (suite, ", ".join("%s %d" % kv for kv in sorted(counts.get(suite, {}).items()))))
print("UPSTREAM DIFF: %s" % ("FAIL" if status else "PASS"))
sys.exit(status)
