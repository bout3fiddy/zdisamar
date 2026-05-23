from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import polars as pl

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = ROOT / "research" / "data-pipeline" / "data" / "o2a-default"
DEFAULT_STAGING_ROOT = ROOT / "out" / "calculation-telemetry-staging"

CSV_TABLES = {
    "scalar_expression_rows": "scalar_expression_rows.csv",
    "reduction_expression_rows": "reduction_expression_rows.csv",
    "decision_rows": "decision_rows.csv",
}

INDEX_COLUMNS = {
    "layer_index",
    "fourier_index",
    "order_index",
    "state_index",
    "branch",
}
BOOL_COLUMNS = {
    "clamped",
    "skipped",
    "finite",
    "taken",
}

EXPRESSIONS: list[dict[str, Any]] = [
    {
        "expr_id": 1,
        "expr_name": "sampling_kernel_shape",
        "row_table": "reduction_expression_rows",
        "subsystem": "instrument_grid",
        "equation": (
            "integrated_rows = count(enabled radiance/irradiance kernels); "
            "side_samples = count(non-inline integration samples)"
        ),
        "result_name": "side_sample_count",
        "inputs": (
            "row_count,radiance_integrated_rows,irradiance_integrated_rows,"
            "radiance_sample_count,irradiance_sample_count"
        ),
        "units": "count",
        "source_file": "src/forward_model/instrument_grid/grid_calculation/wavelength_sampling.zig",
        "function": "recordWavelengthSamplingPlan",
        "capture_reason": (
            "Find integration kernels that create side storage and extra forward work."
        ),
    },
    {
        "expr_id": 2,
        "expr_name": "forward_miss_reuse",
        "row_table": "reduction_expression_rows",
        "subsystem": "instrument_grid",
        "equation": "unique_fraction = miss_count / sample_index_count",
        "result_name": "unique_fraction",
        "inputs": "sample_index_count,miss_count",
        "units": "fraction",
        "source_file": "src/forward_model/instrument_grid/grid_calculation/wavelength_sampling.zig",
        "function": "buildForwardMissPlan",
        "capture_reason": "Quantify wavelength-cache reuse created by spectral integration.",
    },
    {
        "expr_id": 3,
        "expr_name": "reflectance_assembly",
        "row_table": "reduction_expression_rows",
        "subsystem": "instrument_grid",
        "equation": "rho_i = pi * radiance_i / max(irradiance_i * mu0, 1e-9)",
        "result_name": "max_reflectance",
        "inputs": "sample_count,denominator_clamp_count,min_denominator",
        "units": "reflectance",
        "source_file": "src/forward_model/instrument_grid/grid_calculation/simulate.zig",
        "function": "assembleReflectance",
        "capture_reason": "Detect denominator clamps and reflectance outliers.",
    },
    {
        "expr_id": 4,
        "expr_name": "jacobian_column",
        "row_table": "reduction_expression_rows",
        "subsystem": "instrument_grid",
        "equation": "mean_j = sum_i J_i / N",
        "result_name": "mean_jacobian",
        "inputs": "state_index,column_sum,sample_count",
        "units": "state derivative",
        "source_file": "src/forward_model/instrument_grid/grid_calculation/simulate.zig",
        "function": "processJacobianSamples",
        "capture_reason": "Find derivative columns with negligible or extreme contribution.",
    },
    {
        "expr_id": 10,
        "expr_name": "labos_effective_scattering_depth",
        "row_table": "scalar_expression_rows",
        "subsystem": "labos",
        "equation": "tau_eff = tau * omega0 * max_l(|beta_l| / (2l + 1))",
        "result_name": "effective_scattering_depth",
        "inputs": "optical_depth,single_scatter_albedo,max_beta_eff",
        "units": "optical depth",
        "source_file": "src/forward_model/radiative_transfer/labos/layers.zig",
        "function": "calcRTlayersIntoWithBasis",
        "capture_reason": "Study when LABOS layer-doubling work is physically relevant.",
    },
    {
        "expr_id": 11,
        "expr_name": "labos_doubling_trigger",
        "row_table": "decision_rows",
        "subsystem": "labos",
        "equation": "uses_doubling = tau_eff > threshold_doubl",
        "result_name": "uses_doubling",
        "inputs": "effective_scattering_depth,threshold_doubl",
        "units": "boolean",
        "source_file": "src/forward_model/radiative_transfer/labos/layers.zig",
        "function": "calcRTlayersIntoWithBasis",
        "capture_reason": "Measure threshold margins around expensive layer doubling.",
    },
    {
        "expr_id": 12,
        "expr_name": "labos_qseries_skip",
        "row_table": "decision_rows",
        "subsystem": "labos",
        "equation": "qseries_is_zero = abs(trace(R)^2) <= threshold_mul",
        "result_name": "qseries_is_zero",
        "inputs": "trace_r,threshold_mul",
        "units": "boolean",
        "source_file": "src/forward_model/radiative_transfer/labos/layers.zig",
        "function": "doDouble/doDouble12x10Step",
        "capture_reason": (
            "Identify q-series products whose contribution is below the fast-mode cutoff."
        ),
    },
    {
        "expr_id": 20,
        "expr_name": "orders_convergence",
        "row_table": "decision_rows",
        "subsystem": "labos",
        "equation": "stop_orders = max_outgoing_upward < threshold_conv",
        "result_name": "stop_orders",
        "inputs": "max_outgoing_upward,threshold_conv",
        "units": "boolean",
        "source_file": "src/forward_model/radiative_transfer/labos/orders.zig",
        "function": "ordersScatIntoWithWorkspace",
        "capture_reason": "Study scattering-order convergence margins and iteration caps.",
    },
    {
        "expr_id": 30,
        "expr_name": "fourier_weighted_reflectance",
        "row_table": "scalar_expression_rows",
        "subsystem": "labos",
        "equation": "rho_m_weighted = c_m * rho_m, c_0=1, c_m=2*cos(m*relative_azimuth)",
        "result_name": "weighted_reflectance",
        "inputs": "term_reflectance,fourier_weight",
        "units": "reflectance",
        "source_file": "src/forward_model/radiative_transfer/labos/execute.zig",
        "function": "layerResolvedLabosWithWorkspace",
        "capture_reason": "Find Fourier terms that add no meaningful reflectance.",
    },
    {
        "expr_id": 31,
        "expr_name": "fourier_tail_break",
        "row_table": "decision_rows",
        "subsystem": "labos",
        "equation": (
            "tail_break = m >= fourier_floor_scalar and "
            "abs(rho_m) <= fourier_tail_reflectance_epsilon"
        ),
        "result_name": "tail_break",
        "inputs": "term_reflectance,tail_threshold",
        "units": "boolean",
        "source_file": "src/forward_model/radiative_transfer/labos/execute.zig",
        "function": "layerResolvedLabosWithWorkspace",
        "capture_reason": "Quantify how early Fourier expansion can terminate.",
    },
    {
        "expr_id": 40,
        "expr_name": "labos_reflectance_clamp",
        "row_table": "scalar_expression_rows",
        "subsystem": "labos",
        "equation": "rho_out = clamp(rho_raw, 0, 2)",
        "result_name": "clamped_reflectance",
        "inputs": "raw_reflectance",
        "units": "reflectance",
        "source_file": "src/forward_model/radiative_transfer/labos/execute.zig",
        "function": "layerResolvedLabosWithWorkspace",
        "capture_reason": "Detect physically suspicious raw reflectance values.",
    },
    {
        "expr_id": 41,
        "expr_name": "labos_jacobian_norm1",
        "row_table": "scalar_expression_rows",
        "subsystem": "labos",
        "equation": "jacobian_norm1 = sum_s abs(d rho / d state_s)",
        "result_name": "jacobian_norm1",
        "inputs": "jacobian_vector",
        "units": "reflectance derivative",
        "source_file": "src/forward_model/radiative_transfer/labos/execute.zig",
        "function": "layerResolvedLabosWithWorkspace",
        "capture_reason": "Find forward samples with negligible derivative signal.",
    },
]


def main() -> None:
    args = parse_args()
    run_id = args.run_id
    output_dir = args.output_dir.resolve()
    staging_dir = args.staging_dir.resolve() if args.staging_dir else DEFAULT_STAGING_ROOT / run_id

    output_dir.mkdir(parents=True, exist_ok=True)
    staging_dir.mkdir(parents=True, exist_ok=True)

    capture_cli_args = build_capture_args(args)
    if args.capture:
        run_capture(staging_dir, capture_cli_args)

    parquet_counts = write_parquet(run_id, staging_dir, output_dir)
    manifest = build_manifest(run_id, staging_dir, output_dir, parquet_counts, capture_cli_args)
    (output_dir / "run.json").write_text(json.dumps(manifest, indent=2) + "\n")

    if not args.keep_staging:
        for csv_name in CSV_TABLES.values():
            csv_path = staging_dir / csv_name
            if csv_path.exists():
                csv_path.unlink()

    print(f"wrote calculation parquet data to {output_dir}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Capture O2A calculation telemetry and write analysis-ready Parquet tables.",
    )
    parser.add_argument("--run-id", default="o2a-default")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--staging-dir", type=Path)
    parser.add_argument("--no-capture", action="store_false", dest="capture")
    parser.add_argument("--keep-staging", action="store_true")
    parser.add_argument("--sample-count", type=int)
    parser.add_argument("--start-nm", type=float)
    parser.add_argument("--end-nm", type=float)
    parser.add_argument("--high-resolution-step-nm", type=float)
    parser.add_argument("--jacobian", action="store_true")
    parser.add_argument("--multiple-scattering", action="store_true")
    parser.set_defaults(capture=True)
    return parser.parse_args()


def build_capture_args(args: argparse.Namespace) -> list[str]:
    capture_args: list[str] = []
    if args.sample_count is not None:
        capture_args.extend(["--sample-count", str(args.sample_count)])
    if args.start_nm is not None:
        capture_args.extend(["--start-nm", str(args.start_nm)])
    if args.end_nm is not None:
        capture_args.extend(["--end-nm", str(args.end_nm)])
    if args.high_resolution_step_nm is not None:
        capture_args.extend(["--high-resolution-step-nm", str(args.high_resolution_step_nm)])
    if args.jacobian:
        capture_args.append("--jacobian")
    if args.multiple_scattering:
        capture_args.append("--multiple-scattering")
    return capture_args


def run_capture(staging_dir: Path, capture_args: list[str]) -> None:
    command = [
        "zig",
        "build",
        "calculation-telemetry",
        "-Doptimize=ReleaseFast",
        "--",
        "--output-dir",
        display_path(staging_dir),
        *capture_args,
    ]
    subprocess.run(command, cwd=ROOT, check=True)


def write_parquet(run_id: str, staging_dir: Path, output_dir: Path) -> dict[str, int]:
    counts: dict[str, int] = {}
    catalog = pl.DataFrame(EXPRESSIONS)
    catalog.write_parquet(output_dir / "expression_catalog.parquet", compression="zstd")
    counts["expression_catalog"] = catalog.height

    for table_name, csv_name in CSV_TABLES.items():
        csv_path = staging_dir / csv_name
        if not csv_path.exists():
            raise FileNotFoundError(f"missing telemetry staging file: {csv_path}")
        frame = pl.read_csv(csv_path, null_values=["nan"])
        frame = normalize_frame(frame).with_columns(pl.lit(run_id).alias("run_id"))
        frame = frame.select(
            ["run_id", *[column for column in frame.columns if column != "run_id"]]
        )
        frame.write_parquet(
            output_dir / f"{table_name}.parquet",
            compression="zstd",
            statistics=True,
        )
        counts[table_name] = frame.height

    return counts


def normalize_frame(frame: pl.DataFrame) -> pl.DataFrame:
    expressions: list[pl.Expr] = []
    for column in frame.columns:
        if column in INDEX_COLUMNS:
            expressions.append(
                pl.when(pl.col(column) < 0).then(None).otherwise(pl.col(column)).alias(column)
            )
        elif column in BOOL_COLUMNS:
            expressions.append((pl.col(column) == 1).alias(column))
        else:
            expressions.append(pl.col(column))
    return frame.with_columns(expressions)


def build_manifest(
    run_id: str,
    staging_dir: Path,
    output_dir: Path,
    counts: dict[str, int],
    capture_args: list[str],
) -> dict[str, Any]:
    capture_command = [
        "zig",
        "build",
        "calculation-telemetry",
        "-Doptimize=ReleaseFast",
        "--",
        "--output-dir",
        display_path(staging_dir),
        *capture_args,
    ]
    return {
        "run_id": run_id,
        "generated_at_utc": datetime.now(UTC).isoformat(),
        "git_commit": git_text(["rev-parse", "HEAD"]),
        "git_dirty": bool(git_text(["status", "--short"])),
        "capture_command": capture_command,
        "staging_summary": read_json_if_exists(staging_dir / "run_summary.json"),
        "parquet_files": {
            "expression_catalog": display_path(output_dir / "expression_catalog.parquet"),
            "scalar_expression_rows": display_path(
                output_dir / "scalar_expression_rows.parquet"
            ),
            "reduction_expression_rows": display_path(
                output_dir / "reduction_expression_rows.parquet"
            ),
            "decision_rows": display_path(output_dir / "decision_rows.parquet"),
        },
        "row_counts": counts,
    }


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def git_text(args: list[str]) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    return result.stdout.strip()


def read_json_if_exists(path: Path) -> Any | None:
    if not path.exists():
        return None
    return json.loads(path.read_text())


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        sys.exit(exc.returncode)
