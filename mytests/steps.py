#!/usr/bin/env python3
"""Turn the output of build/mytests/steps.elf into Markdown tables.

Cycles per call = (timed loop - loop baseline) / n, the formula of
scripts/driver.py. The loop baseline is measured in this ELF, so the "c" and
"asm" rows can differ from make cycles by a fraction of a cycle.
"""
import re
import sys


def main(path):
    rows, checks, order = {}, {}, []
    with open(path) as f:
        for line in f:
            m = re.match(r"@@bench (.*)", line)
            if m:
                kv = dict(x.split("=", 1) for x in m.group(1).split())
                key = kv["fn"]
                n = int(kv["n"])
                per = (int(kv["cycles"]) - int(kv["overhead"])) / n
                if key not in rows:
                    rows[key] = []
                    order.append(key)
                rows[key].append((kv["impl"], per, kv["checksum"]))
                continue
            m = re.match(r"@@check fn=(\S+) impl=(\S+) mismatches=(\d+)", line)
            if m:
                checks[(m.group(1), m.group(2))] = int(m.group(3))
    bad = 0
    for fn in order:
        print(f"\n### {fn}\n")
        print("| step | cycles per call | vs previous | vs C -O2 | sweep |")
        print("|---|---|---|---|---|")
        base = rows[fn][0][1]
        prev = None
        csum = rows[fn][0][2]
        for impl, per, checksum in rows[fn]:
            c = checks.get((fn, impl))
            sweep = "reference" if impl == "c" else (
                "-" if c is None else ("ok" if c == 0 else f"{c} wrong"))
            if checksum != csum:
                sweep += ", checksum differs"
                bad += 1
            if c:
                bad += 1
            vp = "" if prev is None else f"{prev / per:.2f}x"
            print(f"| {impl} | {per:.1f} | {vp} | {base / per:.2f}x | {sweep} |")
            prev = per
    if bad:
        print(f"\n{bad} step(s) disagree with the C version", file=sys.stderr)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
