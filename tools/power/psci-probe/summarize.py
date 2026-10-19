#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Summarize an experiment; nonzero exit means insufficient/invalid evidence."""
import argparse
import collections
import json
import pathlib
import re
import sys
import time


def fields(line):
    return {k: int(v, 0) for k, v in re.findall(r"(\w+)=(-?0x[0-9a-f]+|-?\d+)", line)}


def parse_probe(text):
    lines = text.splitlines()
    if not lines or not lines[0].startswith("format=1 "):
        raise ValueError("Missing or unsupported probe report header")
    header = fields(lines[0])
    cpus = [fields(line) for line in lines if line.startswith("cpu=")]
    returns = collections.Counter()
    hist = [collections.Counter(), collections.Counter()]
    for line in lines:
        if line.startswith("return "):
            f = fields(line)
            returns[f["code"]] += f["count"]
        elif line.startswith("hist "):
            f = fields(line)
            hist[f["sampled"]][f["fls_ticks"]] += f["count"]
    return header, cpus, returns, hist


def calibrate(path):
    def read():
        ticks, hz = map(int, path.read_text().split())
        return ticks, hz, time.monotonic_ns()
    before, hz, t0 = read()
    time.sleep(0.25)
    after, hz1, t1 = read()
    seconds = (t1 - t0) / 1e9
    ratio = (after - before) / hz / seconds if hz else 0
    valid = hz > 0 and hz == hz1 and after > before and 0.9 < ratio < 1.1
    print(json.dumps(dict(before=before, after=after, hz=hz, awake_seconds=seconds,
                          counter_to_monotonic_ratio=ratio, valid=valid), indent=2))
    return 0 if valid else 1


def read_count(path):
    match = re.search(r"^Count:\s*(\d+)", path.read_text(), re.M)
    if not match:
        raise ValueError(f"No Count field: {path}")
    return int(match[1])


def domain_count(path):
    rows = path.read_text().splitlines()
    if not rows or rows[0].split()[-1] != "S2idle":
        raise ValueError(f"Unexpected system-domain table: {path}")
    return sum(int(row.split()[-1]) for row in rows[1:] if row.strip())


def report(directory):
    errors = []
    for name in ("aosd", "cxsd", "ddr"):
        before = read_count(directory / "before" / f"{name}.txt")
        after = read_count(directory / "after" / f"{name}.txt")
        print(f"{name}: {before} -> {after} (delta {after - before})")
        if after < before:
            errors.append(f"{name} counter went backwards")
    before = domain_count(directory / "before/system-domain.txt")
    after = domain_count(directory / "after/system-domain.txt")
    span = float((directory / "end-wall.txt").read_text()) - float(
        (directory / "start-wall.txt").read_text()
    )
    print(f"System-domain s2idle entries: {after - before}; wall interval including transitions: {span:.3f} s")
    if after < before or span <= 0:
        errors.append("System-domain count or wall interval went backwards")
    for phase in ("before", "after"):
        success, fail = map(int, (directory / phase / "suspend-counts.txt").read_text().split())
        if phase == "before":
            success0, fail0 = success, fail
    if success - success0 != 1 or fail != fail0:
        errors.append("Expected exactly one successful suspend and no failed attempts")
    probe_file = directory / "probe.txt"
    mode_match = re.search(r"^mode=(\w+)$", (directory / "metadata.txt").read_text(), re.M)
    if not mode_match:
        raise ValueError("Missing run mode in metadata")
    mode = mode_match[1]
    if not probe_file.exists():
        if mode != "baseline":
            errors.append(f"Missing probe report for {mode} run")
        else:
            print("Baseline: no probe loaded. Compare entry rate and counter deltas with the other runs.")
    else:
        header, cpus, returns, hist = parse_probe(probe_file.read_text())
        hz = header["counter_hz"]
        if hz <= 0:
            raise ValueError("Invalid counter frequency")
        if header["state"] != 0x0200c354:
            errors.append("Unexpected PSCI state")
        if header["loops"] != 1:
            errors.append("Expected one observed s2idle_loop")
        for key in ("smc_nmissed", "smc_kp_nmissed", "loop_nmissed", "loop_kp_nmissed"):
            if header[key]:
                errors.append(f"{key}={header[key]}: probe lost events")
        entered = sum(c["entered"] for c in cpus)
        returned = sum(c["returned"] for c in cpus)
        sampled = sum(c["sampled"] for c in cpus)
        if not returned or entered != returned:
            errors.append(f"Unpaired or absent target calls: {entered} entries, {returned} returns")
        if sum(returns.values()) != returned:
            errors.append("Return histogram does not account for every returned call")
        if sum(map(lambda h: sum(h.values()), hist)) != returned:
            errors.append("Latency histogram does not account for every returned call")
        if header["sample_every"] and not sampled:
            errors.append("No register samples; test longer or inspect per-CPU call counts")
        for c in cpus:
            if c["backwards"] or c["migrated"]:
                errors.append(f"CPU {c['cpu']}: backwards counter or cross-CPU return")
            if c["returned"] and c["last_tick"] <= c["first_tick"]:
                errors.append(f"CPU {c['cpu']}: counter did not advance")
        loop_seconds = header["loop_ticks"] / hz
        print(f"Counter: {hz} Hz; measured s2idle loop: {loop_seconds:.6f} s")
        print("Compare that duration with an EXTERNAL stopwatch (~30 s); awake calibration alone cannot validate suspend timing.")
        if loop_seconds <= 0 or loop_seconds > span + 2:
            errors.append("Counter-derived sleep duration is inconsistent with the enclosing wall interval")
        print(f"Target calls: {entered} entered, {returned} returned; register samples: {sampled}")
        if loop_seconds > 0:
            print(f"Target calls per measured s2idle second: {returned / loop_seconds:.1f}")
        if returned:
            mean = sum(c["total_ticks"] for c in cpus) / returned / hz * 1e6
            print(f"Mean wrapper latency including probe overhead: {mean:.3f} us")
        labels = {0: "SUCCESS", -1: "NOT_SUPPORTED", -2: "INVALID_PARAMETERS",
                  -3: "DENIED", -9: "INVALID_ADDRESS", 999: "OTHER"}
        for code, count in sorted(returns.items()):
            print(f"Raw PSCI return {code} ({labels.get(code, 'other PSCI error')}): {count}")
        for sampled_flag, buckets in enumerate(hist):
            if not buckets:
                continue
            print(f"Latency histogram ({'register-sampled' if sampled_flag else 'timing-only'} calls):")
            for bucket, count in sorted(buckets.items()):
                lo, hi = (0, 0) if bucket == 0 else (1 << (bucket - 1), (1 << bucket) - 1)
                print(f"  {lo / hz * 1e6:.3f}..{hi / hz * 1e6:.3f} us: {count}")
        if sampled:
            pre = sum(c["pre_none_enabled"] for c in cpus)
            post = sum(c["post_none_enabled"] for c in cpus)
            print(f"Samples with no visible pending+enabled GIC IRQ: pre {pre}/{sampled}; post {post}/{sampled}")
            print("This does not exclude secure interrupts, PDC wake signals, or changes after the snapshot.")
        if sum(c["zero_ticks"] for c in cpus):
            errors.append("Zero-duration calls: do not interpret latency until counter/probe behavior is understood")
    for error in errors:
        print(f"INVALID/INCOMPLETE: {error}")
    return bool(errors)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("calibrate", "report"))
    parser.add_argument("path", type=pathlib.Path)
    args = parser.parse_args()
    try:
        return calibrate(args.path) if args.action == "calibrate" else report(args.path)
    except (OSError, ValueError, KeyError, IndexError) as e:
        print(f"INVALID/INCOMPLETE: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
