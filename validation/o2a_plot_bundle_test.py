#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "matplotlib>=3.10",
#   "numpy>=2.2",
# ]
# ///

from __future__ import annotations

import json
from pathlib import Path
import shutil
import tempfile

from o2a_plot_bundle import build_bundle


REPO_ROOT = Path(__file__).resolve().parents[1]
TMP_ROOT = REPO_ROOT / ".zig-cache" / "tmp"


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def read_bytes_map(paths: list[Path]) -> dict[str, bytes]:
    return {path.name: path.read_bytes() for path in paths}


def main() -> int:
    TMP_ROOT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=TMP_ROOT) as tmpdir:
        root = Path(tmpdir)
        current_csv = root / "current.csv"
        vendor_csv = root / "vendor.csv"
        profile_summary = root / "summary.json"
        output_dir = root / "bundle"

        write_text(
            current_csv,
            "\n".join(
                (
                    "wavelength_nm,irradiance,radiance,reflectance",
                    "755.00000000,4.000000000000e+14,1.400000000000e+13,2.200000000000e-01",
                    "755.03000000,4.010000000000e+14,1.410000000000e+13,2.210000000000e-01",
                    "755.06000000,4.020000000000e+14,1.420000000000e+13,2.220000000000e-01",
                )
            )
            + "\n",
        )
        write_text(
            vendor_csv,
            "\n".join(
                (
                    "wavelength_nm,irradiance,radiance,reflectance",
                    "755.00000000,3.990000000000e+14,1.390000000000e+13,2.190000000000e-01",
                    "755.03000000,4.000000000000e+14,1.400000000000e+13,2.200000000000e-01",
                    "755.06000000,4.010000000000e+14,1.410000000000e+13,2.210000000000e-01",
                )
            )
            + "\n",
        )
        profile_summary.write_text(
            json.dumps(
                {
                    "optimize_mode": "ReleaseFast",
                    "repeat_count": 1,
                    "sample_count": 3,
                    "summary_path": "/abs/out/summary.json",
                    "spectrum_path": "/abs/out/generated_spectrum.csv",
                    "runs": [
                        {
                            "run_index": 1,
                            "sample_count": 3,
                            "preparation": {
                                "input_loading_ns": 1,
                                "scene_assembly_ns": 2,
                                "optics_preparation_ns": 3,
                                "plan_preparation_ns": 4,
                            },
                            "forward": {
                                "radiance_integration_ns": 5,
                                "radiance_postprocess_ns": 6,
                                "irradiance_integration_ns": 7,
                                "irradiance_postprocess_ns": 8,
                                "reduction_ns": 9,
                            },
                            "total_prepare_ns": 10,
                            "total_forward_ns": 11,
                            "total_end_to_end_ns": 12,
                        }
                    ],
                    "preparation": {"total_ns": {"mean_ns": 10, "min_ns": 10, "max_ns": 10}},
                    "forward": {"total_ns": {"mean_ns": 11, "min_ns": 11, "max_ns": 11}},
                    "total_prepare_ns": {"mean_ns": 10, "min_ns": 10, "max_ns": 10},
                    "total_forward_ns": {"mean_ns": 11, "min_ns": 11, "max_ns": 11},
                    "total_end_to_end_ns": {"mean_ns": 12, "min_ns": 12, "max_ns": 12},
                },
                indent=2,
            )
            + "\n"
        )

        current_rel = current_csv.relative_to(REPO_ROOT)
        vendor_rel = vendor_csv.relative_to(REPO_ROOT)
        summary_rel = profile_summary.relative_to(REPO_ROOT)
        output_rel = output_dir.relative_to(REPO_ROOT)

        build_bundle(current_rel, summary_rel, vendor_rel, output_rel, "zig build o2a-plots")

        expected_files = [
            output_dir / "bundle_manifest.json",
            output_dir / "comparison_metrics.json",
            output_dir / "current_vs_vendor_reflectance.png",
            output_dir / "current_vs_vendor_radiance.png",
            output_dir / "current_vs_vendor_irradiance.png",
            output_dir / "current_vs_vendor_residuals.png",
            output_dir / "generated_spectrum.csv",
            output_dir / "profile_summary.json",
        ]
        for path in expected_files:
            assert path.exists(), f"missing {path}"

        metrics = json.loads((output_dir / "comparison_metrics.json").read_text())
        assert metrics["sample_count"] == 3
        assert metrics["vendor_reference_path"] == vendor_rel.as_posix()
        assert metrics["generated_spectrum_path"] == f"{output_rel.as_posix()}/generated_spectrum.csv"
        assert metrics["profile_summary_path"] == f"{output_rel.as_posix()}/profile_summary.json"

        manifest = json.loads((output_dir / "bundle_manifest.json").read_text())
        assert manifest["canonical_command"] == "zig build o2a-plots"
        assert manifest["tracked_output_dir"] == output_rel.as_posix()
        assert manifest["tracked_outputs"] == [
            f"{output_rel.as_posix()}/bundle_manifest.json",
            f"{output_rel.as_posix()}/comparison_metrics.json",
            f"{output_rel.as_posix()}/current_vs_vendor_reflectance.png",
            f"{output_rel.as_posix()}/current_vs_vendor_radiance.png",
            f"{output_rel.as_posix()}/current_vs_vendor_irradiance.png",
            f"{output_rel.as_posix()}/current_vs_vendor_residuals.png",
            f"{output_rel.as_posix()}/generated_spectrum.csv",
            f"{output_rel.as_posix()}/profile_summary.json",
        ]

        tracked_summary = json.loads((output_dir / "profile_summary.json").read_text())
        assert tracked_summary["summary_path"] == f"{output_rel.as_posix()}/profile_summary.json"
        assert tracked_summary["spectrum_path"] == f"{output_rel.as_posix()}/generated_spectrum.csv"
        assert "/abs/out" not in (output_dir / "profile_summary.json").read_text()
        assert "/abs/out" not in (output_dir / "bundle_manifest.json").read_text()
        assert "/abs/out" not in (output_dir / "comparison_metrics.json").read_text()

        stable_files = [
            output_dir / "bundle_manifest.json",
            output_dir / "comparison_metrics.json",
            output_dir / "generated_spectrum.csv",
            output_dir / "profile_summary.json",
        ]
        before = read_bytes_map(stable_files)
        build_bundle(current_rel, summary_rel, vendor_rel, output_rel, "zig build o2a-plots")
        after = read_bytes_map(stable_files)
        assert before == after

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
