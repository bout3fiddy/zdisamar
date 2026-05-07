#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# ///

from __future__ import annotations

import csv
import json
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = REPO_ROOT / "validation" / "outputs" / "performance" / "labos-bottleneck"

BENCH_RE = re.compile(r"^(?P<name>[^:]+): .* ns_per_call=(?P<ns>[0-9.]+) ")


def read_counters(path: Path) -> dict[str, int]:
    with path.open(newline="") as handle:
        return {row["counter"]: int(row["count"]) for row in csv.DictReader(handle)}


def read_bench(path: Path) -> dict[str, float]:
    timings: dict[str, float] = {}
    for line in path.read_text().splitlines():
        match = BENCH_RE.match(line)
        if match:
            timings[match.group("name")] = float(match.group("ns"))
    return timings


def main() -> None:
    output_dir = DEFAULT_OUTPUT_DIR
    counters = read_counters(output_dir / "counters.csv")
    bench = read_bench(output_dir / "labos_kernel_bench.txt")
    summary = json.loads((output_dir / "summary.json").read_text())

    operations = [
        (
            "qseries package",
            "matrix_qseries",
            "qseries_nonzero_12x10",
            "qseriesKnownNonzeroProduct; includes the R*R product and "
            "q-series solve path for the benchmark seed",
        ),
        (
            "R*D, T*U, T*D products",
            "matrix_smul_rd+matrix_smul_tu+matrix_smul_td",
            "smul_12x10",
            "three 12x10 matrix products inside every doubling step",
        ),
        (
            "D update",
            "matrix_smul_add_semul3",
            "smulAddSemul3_12",
            "T + Q*diag(E) + Q*T fused update",
        ),
        (
            "U update",
            "matrix_semul_add",
            "semulAdd_12",
            "R*diag(E) + R*D product result",
        ),
        (
            "R_next update",
            "matrix_mat_add_esmul3",
            "matAddEsmul3_12",
            "R + diag(E)*U + T*U product result",
        ),
        (
            "T_next update",
            "matrix_esmul_semul_add",
            "esmulSemulAdd_12",
            "diag(E)*D + T*diag(E) + T*D product result",
        ),
    ]

    rows: list[dict[str, str | int | float]] = []
    for label, counter_expr, bench_name, note in operations:
        count = sum(counters[name] for name in counter_expr.split("+"))
        ns_per_call = bench[bench_name]
        estimated_ns = count * ns_per_call
        rows.append(
            {
                "operation": label,
                "counter": counter_expr,
                "bench_name": bench_name,
                "calls": count,
                "ns_per_call": ns_per_call,
                "estimated_cpu_s": estimated_ns / 1.0e9,
                "estimated_forward_wall_percent": 100.0
                * estimated_ns
                / max(summary["forward_wall_ns"], 1),
                "estimated_labos_cpu_percent": 100.0
                * estimated_ns
                / max(summary["labos_execute_cpu_ns"], 1),
                "note": note,
            }
        )

    rows.append(
        {
            "operation": "scattering-order dot pairs",
            "counter": "dot_gauss_pair_calls",
            "bench_name": "not_benchmarked",
            "calls": counters["dot_gauss_pair_calls"],
            "ns_per_call": "",
            "estimated_cpu_s": "",
            "estimated_forward_wall_percent": "",
            "estimated_labos_cpu_percent": "",
            "note": (
                f"{counters['dot_gauss_pair_terms']} multiply-add terms counted; "
                "kept as an operation count because it is embedded in orders.zig "
                "rather than bench-isolated"
            ),
        }
    )

    primitive_path = output_dir / "primitive_estimates.csv"
    with primitive_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    rollup = {
        "forward_wall_s": summary["forward_wall_s"],
        "labos_execute_cpu_s": summary["labos_execute_cpu_ns"] / 1.0e9,
        "rt_layer_build_cpu_s": summary["rt_layer_build_cpu_ns"] / 1.0e9,
        "orders_cpu_s": summary["orders_cpu_ns"] / 1.0e9,
        "forward_input_cpu_s": summary["forward_input_cpu_ns"] / 1.0e9,
        "primitive_estimated_cpu_s": sum(
            float(row["estimated_cpu_s"])
            for row in rows
            if isinstance(row["estimated_cpu_s"], float)
        ),
        "artifacts": {
            "summary": "summary.json",
            "sections": "sections.csv",
            "counters": "counters.csv",
            "worker_sections": "worker_sections.csv",
            "kernel_bench": "labos_kernel_bench.txt",
            "primitive_estimates": "primitive_estimates.csv",
        },
    }
    (output_dir / "rollup.json").write_text(json.dumps(rollup, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
