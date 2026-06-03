import argparse
import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import polars as pl

REPO_ROOT = Path(__file__).resolve().parents[4]
SCAFFOLDING_OUTPUT_ROOT = REPO_ROOT / "out" / "scaffolding"
TELEMETRY_DATA_ROOT = SCAFFOLDING_OUTPUT_ROOT / "telemetry" / "data"
DEFAULT_OUTPUT_ROOT = TELEMETRY_DATA_ROOT / "full-spectrum-758-770-ms"
CAPTURE_SCRIPT = "scaffolding/instrumentation/telemetry/capture/generate_calculation_parquet.py"

COMMON_ARGS = {
    "sample_count": 401,
    "start_nm": 758.0,
    "end_nm": 770.0,
    "high_resolution_step_nm": 0.1,
}

SCENES: list[dict[str, float | str]] = [
    {
        "scene_id": "sza45_vza00_raa000_dark_clean",
        "surface_albedo": 0.05,
        "aerosol_optical_depth": 0.08,
        "aerosol_single_scatter_albedo": 1.0,
        "aerosol_asymmetry_factor": 0.62,
        "solar_zenith_deg": 45.0,
        "viewing_zenith_deg": 0.0,
        "relative_azimuth_deg": 0.0,
    },
    {
        "scene_id": "sza45_vza00_raa000_mid_hazy",
        "surface_albedo": 0.20,
        "aerosol_optical_depth": 0.80,
        "aerosol_single_scatter_albedo": 0.94,
        "aerosol_asymmetry_factor": 0.78,
        "solar_zenith_deg": 45.0,
        "viewing_zenith_deg": 0.0,
        "relative_azimuth_deg": 0.0,
    },
    {
        "scene_id": "sza45_vza00_raa000_bright_dense",
        "surface_albedo": 0.45,
        "aerosol_optical_depth": 1.50,
        "aerosol_single_scatter_albedo": 0.90,
        "aerosol_asymmetry_factor": 0.82,
        "solar_zenith_deg": 45.0,
        "viewing_zenith_deg": 0.0,
        "relative_azimuth_deg": 0.0,
    },
    {
        "scene_id": "sza60_vza30_raa120_dark_clean",
        "surface_albedo": 0.05,
        "aerosol_optical_depth": 0.08,
        "aerosol_single_scatter_albedo": 1.0,
        "aerosol_asymmetry_factor": 0.62,
        "solar_zenith_deg": 60.0,
        "viewing_zenith_deg": 30.0,
        "relative_azimuth_deg": 120.0,
    },
    {
        "scene_id": "sza60_vza30_raa120_mid_reference",
        "surface_albedo": 0.20,
        "aerosol_optical_depth": 0.30,
        "aerosol_single_scatter_albedo": 1.0,
        "aerosol_asymmetry_factor": 0.70,
        "solar_zenith_deg": 60.0,
        "viewing_zenith_deg": 30.0,
        "relative_azimuth_deg": 120.0,
    },
    {
        "scene_id": "sza60_vza30_raa120_bright_hazy",
        "surface_albedo": 0.45,
        "aerosol_optical_depth": 0.80,
        "aerosol_single_scatter_albedo": 0.94,
        "aerosol_asymmetry_factor": 0.78,
        "solar_zenith_deg": 60.0,
        "viewing_zenith_deg": 30.0,
        "relative_azimuth_deg": 120.0,
    },
    {
        "scene_id": "sza70_vza50_raa060_dark_hazy",
        "surface_albedo": 0.05,
        "aerosol_optical_depth": 0.80,
        "aerosol_single_scatter_albedo": 0.94,
        "aerosol_asymmetry_factor": 0.78,
        "solar_zenith_deg": 70.0,
        "viewing_zenith_deg": 50.0,
        "relative_azimuth_deg": 60.0,
    },
    {
        "scene_id": "sza70_vza50_raa060_mid_dense",
        "surface_albedo": 0.20,
        "aerosol_optical_depth": 1.50,
        "aerosol_single_scatter_albedo": 0.90,
        "aerosol_asymmetry_factor": 0.82,
        "solar_zenith_deg": 70.0,
        "viewing_zenith_deg": 50.0,
        "relative_azimuth_deg": 60.0,
    },
    {
        "scene_id": "sza70_vza50_raa060_bright_clean",
        "surface_albedo": 0.45,
        "aerosol_optical_depth": 0.08,
        "aerosol_single_scatter_albedo": 1.0,
        "aerosol_asymmetry_factor": 0.62,
        "solar_zenith_deg": 70.0,
        "viewing_zenith_deg": 50.0,
        "relative_azimuth_deg": 60.0,
    },
    {
        "scene_id": "sza35_vza20_raa170_dark_dense",
        "surface_albedo": 0.05,
        "aerosol_optical_depth": 1.50,
        "aerosol_single_scatter_albedo": 0.90,
        "aerosol_asymmetry_factor": 0.82,
        "solar_zenith_deg": 35.0,
        "viewing_zenith_deg": 20.0,
        "relative_azimuth_deg": 170.0,
    },
    {
        "scene_id": "sza35_vza20_raa170_mid_clean",
        "surface_albedo": 0.20,
        "aerosol_optical_depth": 0.08,
        "aerosol_single_scatter_albedo": 1.0,
        "aerosol_asymmetry_factor": 0.62,
        "solar_zenith_deg": 35.0,
        "viewing_zenith_deg": 20.0,
        "relative_azimuth_deg": 170.0,
    },
    {
        "scene_id": "sza35_vza20_raa170_bright_reference",
        "surface_albedo": 0.45,
        "aerosol_optical_depth": 0.30,
        "aerosol_single_scatter_albedo": 1.0,
        "aerosol_asymmetry_factor": 0.70,
        "solar_zenith_deg": 35.0,
        "viewing_zenith_deg": 20.0,
        "relative_azimuth_deg": 170.0,
    },
]


def main() -> None:

    args = parse_args()
    output_root = args.output_root.resolve()
    output_root.mkdir(parents=True, exist_ok=True)

    selected_scenes = SCENES[: args.limit] if args.limit else SCENES
    records: list[dict[str, Any]] = []

    for scene in selected_scenes:
        scene_id = str(scene["scene_id"])
        scene_dir = output_root / scene_id

        if args.resume and (scene_dir / "run.json").exists():
            print(f"keeping existing scene {scene_id}")
        else:
            run_scene(scene_dir, scene)

        records.append(scene_record(output_root, scene_dir, scene))

    write_scene_catalog(output_root, records)
    write_sweep_manifest(output_root, records)
    print(f"wrote full-spectrum sweep to {display_path(output_root)}")


def parse_args() -> argparse.Namespace:

    parser = argparse.ArgumentParser(
        description="Run the 12-scene full-spectrum calculation telemetry sweep.",
    )
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--limit", type=int)

    return parser.parse_args()


def run_scene(scene_dir: Path, scene: dict[str, float | str]) -> None:

    command = [
        "uv",
        "run",
        "python",
        CAPTURE_SCRIPT,
        "--run-id",
        str(scene["scene_id"]),
        "--output-dir",
        display_path(scene_dir),
        "--scene-id",
        str(scene["scene_id"]),
        "--sample-count",
        str(COMMON_ARGS["sample_count"]),
        "--start-nm",
        str(COMMON_ARGS["start_nm"]),
        "--end-nm",
        str(COMMON_ARGS["end_nm"]),
        "--high-resolution-step-nm",
        str(COMMON_ARGS["high_resolution_step_nm"]),
        "--surface-albedo",
        str(scene["surface_albedo"]),
        "--aerosol-optical-depth",
        str(scene["aerosol_optical_depth"]),
        "--aerosol-single-scatter-albedo",
        str(scene["aerosol_single_scatter_albedo"]),
        "--aerosol-asymmetry-factor",
        str(scene["aerosol_asymmetry_factor"]),
        "--solar-zenith-deg",
        str(scene["solar_zenith_deg"]),
        "--viewing-zenith-deg",
        str(scene["viewing_zenith_deg"]),
        "--relative-azimuth-deg",
        str(scene["relative_azimuth_deg"]),
        "--multiple-scattering",
    ]

    print(f"running scene {scene['scene_id']}", flush=True)
    subprocess.run(command, cwd=REPO_ROOT, check=True)


def scene_record(
    output_root: Path,
    scene_dir: Path,
    scene: dict[str, float | str],
) -> dict[str, Any]:

    run = read_json(scene_dir / "run.json")
    summary = run["capture_summary"]
    row_counts = run["row_counts"]
    parquet_bytes = sum((scene_dir / f"{name}.parquet").stat().st_size for name in row_counts)

    return {
        **scene,
        "output_dir": display_path(scene_dir),
        "relative_output_dir": str(scene_dir.relative_to(output_root)),
        "multiple_scattering": True,
        "sample_count": COMMON_ARGS["sample_count"],
        "start_nm": COMMON_ARGS["start_nm"],
        "end_nm": COMMON_ARGS["end_nm"],
        "high_resolution_step_nm": COMMON_ARGS["high_resolution_step_nm"],
        "prepare_s": summary["prepare_s"],
        "forward_wall_s": summary["forward_wall_s"],
        "scalar_rows": row_counts["scalar_expression_rows"],
        "reduction_rows": row_counts["reduction_expression_rows"],
        "decision_rows": row_counts["decision_rows"],
        "total_event_rows": (
            row_counts["scalar_expression_rows"]
            + row_counts["reduction_expression_rows"]
            + row_counts["decision_rows"]
        ),
        "parquet_bytes": parquet_bytes,
    }


def write_scene_catalog(output_root: Path, records: list[dict[str, Any]]) -> None:

    pl.DataFrame(records).write_parquet(
        output_root / "scene_catalog.parquet",
        compression="zstd",
        statistics=True,
    )


def write_sweep_manifest(output_root: Path, records: list[dict[str, Any]]) -> None:

    manifest = {
        "generated_at_utc": datetime.now(UTC).isoformat(),
        "scene_count": len(records),
        "common_args": COMMON_ARGS,
        "multiple_scattering": True,
        "total_event_rows": sum(record["total_event_rows"] for record in records),
        "total_parquet_bytes": sum(record["parquet_bytes"] for record in records),
        "scenes": records,
    }

    (output_root / "sweep_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


def read_json(path: Path) -> Any:

    return json.loads(path.read_text())


def display_path(path: Path) -> str:

    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        sys.exit(exc.returncode)
