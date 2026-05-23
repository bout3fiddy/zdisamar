import argparse
import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, cast

import polars as pl

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = ROOT / "research" / "data-pipeline" / "data" / "o2a-default"

PARQUET_TABLES = (
    "expression_catalog",
    "scalar_expression_rows",
    "reduction_expression_rows",
    "decision_rows",
)


def main() -> None:

    args = parse_args()
    run_id = args.run_id
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    capture_args = build_capture_args(args)

    if args.capture:
        run_capture(output_dir, capture_args)

    counts = read_counts(output_dir)
    manifest = build_manifest(run_id, output_dir, counts, capture_args)
    (output_dir / "run.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"wrote calculation parquet data to {display_path(output_dir)}")


def parse_args() -> argparse.Namespace:

    parser = argparse.ArgumentParser(
        description="Capture O2A calculation telemetry as analysis-ready Parquet tables.",
    )
    parser.add_argument("--run-id", default="o2a-default")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--no-capture", action="store_false", dest="capture")
    parser.add_argument("--scene-id")
    parser.add_argument("--sample-count", type=int)
    parser.add_argument("--start-nm", type=float)
    parser.add_argument("--end-nm", type=float)
    parser.add_argument("--high-resolution-step-nm", type=float)
    parser.add_argument("--surface-albedo", type=float)
    parser.add_argument("--aerosol-optical-depth", type=float)
    parser.add_argument("--aerosol-single-scatter-albedo", type=float)
    parser.add_argument("--aerosol-asymmetry-factor", type=float)
    parser.add_argument("--aerosol-layer-top-pressure-hpa", type=float)
    parser.add_argument("--aerosol-layer-bottom-pressure-hpa", type=float)
    parser.add_argument("--solar-zenith-deg", type=float)
    parser.add_argument("--viewing-zenith-deg", type=float)
    parser.add_argument("--relative-azimuth-deg", type=float)
    parser.add_argument("--jacobian", action="store_true")
    parser.add_argument("--multiple-scattering", action="store_true")
    parser.set_defaults(capture=True)

    return parser.parse_args()


def build_capture_args(args: argparse.Namespace) -> list[str]:

    capture_args: list[str] = []
    optional_values = (
        ("--scene-id", args.scene_id),
        ("--sample-count", args.sample_count),
        ("--start-nm", args.start_nm),
        ("--end-nm", args.end_nm),
        ("--high-resolution-step-nm", args.high_resolution_step_nm),
        ("--surface-albedo", args.surface_albedo),
        ("--aerosol-optical-depth", args.aerosol_optical_depth),
        ("--aerosol-single-scatter-albedo", args.aerosol_single_scatter_albedo),
        ("--aerosol-asymmetry-factor", args.aerosol_asymmetry_factor),
        ("--aerosol-layer-top-pressure-hpa", args.aerosol_layer_top_pressure_hpa),
        ("--aerosol-layer-bottom-pressure-hpa", args.aerosol_layer_bottom_pressure_hpa),
        ("--solar-zenith-deg", args.solar_zenith_deg),
        ("--viewing-zenith-deg", args.viewing_zenith_deg),
        ("--relative-azimuth-deg", args.relative_azimuth_deg),
    )

    for flag, value in optional_values:
        if value is not None:
            capture_args.extend([flag, str(value)])

    if args.jacobian:
        capture_args.append("--jacobian")

    if args.multiple_scattering:
        capture_args.append("--multiple-scattering")

    return capture_args


def run_capture(output_dir: Path, capture_args: list[str]) -> None:

    subprocess.run(capture_command(output_dir, capture_args), cwd=ROOT, check=True)


def capture_command(output_dir: Path, capture_args: list[str]) -> list[str]:

    return [
        "zig",
        "build",
        "calculation-telemetry",
        "-Doptimize=ReleaseFast",
        "--",
        "--output-dir",
        display_path(output_dir),
        *capture_args,
    ]


def read_counts(output_dir: Path) -> dict[str, int]:

    counts: dict[str, int] = {}

    for table in PARQUET_TABLES:
        path = output_dir / f"{table}.parquet"

        if not path.exists():
            raise FileNotFoundError(f"missing telemetry parquet file: {path}")

        count_frame = cast(
            pl.DataFrame,
            pl.scan_parquet(path).select(pl.len().alias("row_count")).collect(),
        )
        counts[table] = int(count_frame.get_column("row_count")[0])

    return counts


def build_manifest(
    run_id: str,
    output_dir: Path,
    counts: dict[str, int],
    capture_args: list[str],
) -> dict[str, Any]:

    return {
        "run_id": run_id,
        "generated_at_utc": datetime.now(UTC).isoformat(),
        "git_commit": git_text(["rev-parse", "HEAD"]),
        "git_dirty": bool(git_text(["status", "--short"])),
        "capture_command": capture_command(output_dir, capture_args),
        "capture_summary": read_json_if_exists(output_dir / "run_summary.json"),
        "parquet_files": {
            table: display_path(output_dir / f"{table}.parquet") for table in PARQUET_TABLES
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
