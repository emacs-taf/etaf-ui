#!/usr/bin/env python3
"""Measure the displayed Gallery through an existing native Emacs server."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import statistics
import subprocess
import tempfile
import time


def summarize(report):
    """Report every route and distinguish completion from passing latency."""
    groups = defaultdict(list)
    invalid = slow = hard = 0
    for sample in report.get("samples", []):
        groups[(sample["label"], sample["method"])].append(sample)
        valid = (sample.get("correct") is True
                 and sample.get("environment_stable") is True
                 and not sample.get("error"))
        if report.get("foreground_required"):
            valid = (valid and sample["before"]["foreground"] is True
                     and sample["after"]["foreground"] is True)
        invalid += not valid
        slow += sample["wall_ms"] > sample["target_ms"]
        hard += sample["wall_ms"] > sample["hard_limit_ms"]
    for (label, method), samples in groups.items():
        values = [s["wall_ms"] for s in samples]
        print(f"{label:22} {method:8} n={len(values)} "
              f"p50={statistics.median(values):8.1f}ms max={max(values):8.1f}ms")
    count = sum(map(len, groups.values()))
    print(f"status={report.get('status')} samples={count} invalid={invalid} "
          f"over_target={slow} over_500ms={hard} trace={bool(report.get('trace'))}")
    if report.get("error"):
        print(report["error"])
    combinations = {(s["label"], s["method"], s["set"])
                    for s in report.get("samples", [])}
    if (report.get("status") != "completed" or invalid
            or count != 36 or len(combinations) != 36):
        return 2
    if report.get("trace"):
        print("Instrumented diagnostic pass; timings are not acceptance samples.")
        return 0
    print("Three fresh mounts per route; this is an input-path screening gate.")
    return int(bool(slow or hard))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emacsclient", default="emacsclient")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--summarize", type=Path)
    parser.add_argument("--trace", action="store_true")
    parser.add_argument("--allow-background", action="store_true")
    parser.add_argument("--timeout", type=float, default=300.0)
    args = parser.parse_args()
    if args.summarize:
        return summarize(json.loads(args.summarize.read_text()))
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    output = (args.output or Path(tempfile.mkdtemp(prefix="gallery-input-")) / "result.json").resolve()
    if output.exists():
        parser.error(f"output already exists: {output}")
    root = Path(__file__).resolve().parents[1]
    tool = root / "benchmarks/gallery-input-benchmark.el"
    form = (f'(progn (load {json.dumps(str(tool))} nil t t) '
            f'(gallery-input-benchmark-start {json.dumps(str(output))} '
            f'{"t" if args.trace else "nil"} '
            f'{"t" if args.allow_background else "nil"}))')
    result = subprocess.run([args.emacsclient, "--eval", form],
                            capture_output=True, text=True, timeout=15)
    if result.returncode or "scheduled" not in result.stdout:
        print(result.stdout + result.stderr)
        return 2
    print(f"Evidence: {output}", flush=True)
    print("Keep the existing Emacs window in front; sampling pauses in background.", flush=True)
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        try:
            report = json.loads(output.read_text())
            if report.get("status") != "running":
                return summarize(report)
        except (FileNotFoundError, json.JSONDecodeError):
            pass
        time.sleep(0.25)
    print("Run is incomplete; use gallery-input-benchmark-cancel through emacsclient to stop it.")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
