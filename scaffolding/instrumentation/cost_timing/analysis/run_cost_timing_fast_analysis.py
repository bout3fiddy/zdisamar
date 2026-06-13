#!/usr/bin/env python3
"""Fast cost-timing analysis gate for the enabled O2 A forward smoke."""

from __future__ import annotations

import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


MAX_ELAPSED_SECONDS = 20.0
EXPECTED_SAMPLES = 2
REQUIRED_COUNTERS = (
    "execute",
    "optics_assembly",
    "spectroscopy_sigma",
    "partition_interp",
    "profile_interp",
    "quadrature_build",
)


@dataclass(frozen=True)
class Counter:
    ns: int = 0
    count: int = 0


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: run_cost_timing_fast_analysis.py <cost-timing-forward-smoke>", file=sys.stderr)
        return 2

    executable = Path(sys.argv[1])
    if not executable.exists():
        print(f"cost_timing_fast_analysis status=fail reason=missing_executable path={executable}", file=sys.stderr)
        return 2

    started = time.monotonic()
    completed = subprocess.run(
        [str(executable)],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    elapsed_s = time.monotonic() - started
    output = completed.stdout

    if completed.returncode != 0:
        print(output, end="")
        print(
            f"cost_timing_fast_analysis status=fail reason=smoke_exit code={completed.returncode}",
            file=sys.stderr,
        )
        return completed.returncode

    row = first_cost_timing_row(output)
    if row is None:
        print(output, end="")
        print("cost_timing_fast_analysis status=fail reason=missing_cost_timing_row", file=sys.stderr)
        return 1

    counters = parse_counters(row)
    samples = parse_samples(output)
    failures = gate_failures(counters, samples, elapsed_s)
    if failures:
        print(output, end="")
        print(
            "cost_timing_fast_analysis status=fail "
            f"elapsed_s={elapsed_s:.3f} reason={','.join(failures)}",
            file=sys.stderr,
        )
        return 1

    print(row)
    print(
        "cost_timing_fast_analysis "
        f"status=pass elapsed_s={elapsed_s:.3f} samples={samples} "
        f"profile_interp.count={counters['profile_interp'].count} "
        f"partition_interp.count={counters['partition_interp'].count}"
    )
    print_top_elapsed(counters)
    print_findings(counters)
    return 0


def first_cost_timing_row(output: str) -> str | None:
    for line in output.splitlines():
        if line.startswith("cost_timing "):
            return line
    return None


def parse_counters(row: str) -> dict[str, Counter]:
    values: dict[str, dict[str, int]] = {}
    for name, suffix, value in re.findall(r"([a-z0-9_]+)\.(ns|count)=(\d+)", row):
        fields = values.setdefault(name, {})
        fields[suffix] = int(value)
    return {
        name: Counter(ns=fields.get("ns", 0), count=fields.get("count", 0))
        for name, fields in values.items()
    }


def parse_samples(output: str) -> int | None:
    match = re.search(r"cost_timing_forward_smoke samples=(\d+)", output)
    if match is None:
        return None
    return int(match.group(1))


def gate_failures(counters: dict[str, Counter], samples: int | None, elapsed_s: float) -> list[str]:
    failures: list[str] = []
    if samples != EXPECTED_SAMPLES:
        failures.append("unexpected_sample_count")
    if elapsed_s > MAX_ELAPSED_SECONDS:
        failures.append("slow_gate")
    for name in REQUIRED_COUNTERS:
        counter = counters.get(name)
        if counter is None or counter.count == 0:
            failures.append(f"missing_{name}")
    return failures


def print_top_elapsed(counters: dict[str, Counter]) -> None:
    elapsed = sorted(
        (
            (name, counter)
            for name, counter in counters.items()
            if counter.ns > 0 and name not in {"execute"}
        ),
        key=lambda item: item[1].ns,
        reverse=True,
    )
    print("cost_timing_top_elapsed")
    for name, counter in elapsed[:6]:
        print(f"  {name} ns={counter.ns} count={counter.count}")


def print_findings(counters: dict[str, Counter]) -> None:
    profile_count = max(counters["profile_interp"].count, 1)
    partition_count = counters["partition_interp"].count
    spectroscopy_count = counters["spectroscopy_sigma"].count
    optics_count = counters["optics_assembly"].count
    quadrature_count = counters["quadrature_build"].count

    print("cost_timing_findings")
    if partition_count >= profile_count * 4:
        ratio = partition_count / profile_count
        print(
            "  action=cache_partition_ratios "
            f"partition_interp.count={partition_count} profile_interp.count={profile_count} ratio={ratio:.1f} "
            "candidate=cache Q(T0)/Q(T) by isotopologue and profile temperature during profile-line setup"
        )
    if spectroscopy_count >= profile_count * 8:
        ratio = spectroscopy_count / profile_count
        print(
            "  action=separate_profile_line_cache_miss_cost "
            f"spectroscopy_sigma.count={spectroscopy_count} profile_interp.count={profile_count} ratio={ratio:.1f} "
            "candidate=measure cache-hit forward separately from profile-line cache rebuilds"
        )
    if optics_count == profile_count and quadrature_count == profile_count:
        print(
            "  action=keep_optics_reduction_on_watchlist "
            f"optics_assembly.count={optics_count} quadrature_build.count={quadrature_count} "
            "candidate=after spectroscopy caching, check whether per-wavelength support-to-layer reduction is visible"
        )


if __name__ == "__main__":
    raise SystemExit(main())
