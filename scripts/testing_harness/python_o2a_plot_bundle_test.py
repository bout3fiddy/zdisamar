#!/usr/bin/env -S uv run

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd


DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parents[2] / "out" / "plots" / "python_plotting"

REQUIRED_DATA = {
    "generated_spectrum.csv",
    "reference_resampled.csv",
    "reflectance_residuals.csv",
    "validation_metrics.json",
    "atmospheric_budget.csv",
    "o2_o2_cia_diagnostics.csv",
    "instrument_response.csv",
    "radiative_transfer_diagnostics.csv",
}

REQUIRED_PLOTS = {
    "validation/full_sampled_reflectance.png",
    "validation/reflectance_residual_histogram.png",
    "validation/reflectance_residual_by_wavelength.png",
    "validation/radiance_against_reference.png",
    "validation/validation_metrics.png",
    "atmosphere/total_optical_depth_heatmap.png",
    "atmosphere/optical_depth_component_stack.png",
    "atmosphere/total_optical_depth_profile_755_00000_nm.png",
    "atmosphere/total_optical_depth_profile_760_76000_nm.png",
    "atmosphere/total_optical_depth_profile_776_00000_nm.png",
    "atmosphere/single_scatter_albedo_profile_755_00000_nm.png",
    "atmosphere/single_scatter_albedo_profile_760_76000_nm.png",
    "atmosphere/single_scatter_albedo_profile_776_00000_nm.png",
    "cia/cia_share_spectrum.png",
    "cia/cia_share_profile_755_00000_nm.png",
    "cia/cia_share_profile_760_76000_nm.png",
    "cia/cia_share_profile_776_00000_nm.png",
    "cia/cia_optical_depth_profile_755_00000_nm.png",
    "cia/cia_optical_depth_profile_760_76000_nm.png",
    "cia/cia_optical_depth_profile_776_00000_nm.png",
    "cia/cia_cross_section_temperature_755_00000_nm.png",
    "cia/cia_cross_section_temperature_760_76000_nm.png",
    "cia/cia_cross_section_temperature_776_00000_nm.png",
    "instrument_response/isrf_760_76000_nm.png",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify the real O2 A Python plotting bundle outputs.")
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR))
    return parser.parse_args()


def require_non_empty(path: Path) -> None:
    if not path.exists():
        raise AssertionError(f"missing output: {path}")
    if path.stat().st_size <= 0:
        raise AssertionError(f"empty output: {path}")


def assert_rows(path: Path, *, expected: int | None = None) -> pd.DataFrame:
    frame = pd.read_csv(path)
    if frame.empty:
        raise AssertionError(f"{path} has no rows")
    if expected is not None and len(frame) != expected:
        raise AssertionError(f"{path} row count {len(frame)} != {expected}")
    return frame


def main() -> int:
    args = parse_args()
    output_dir = Path(args.output_dir)
    data_dir = output_dir / "data"
    manifest_path = output_dir / "manifest.json"

    require_non_empty(manifest_path)
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("source") != "core":
        raise AssertionError("manifest source must be core")
    for name, source in manifest.get("data_sources", {}).items():
        if "synthetic" in source:
            raise AssertionError(f"{name} has synthetic source marker")

    for name in REQUIRED_DATA:
        require_non_empty(data_dir / name)
    for name in REQUIRED_PLOTS:
        require_non_empty(output_dir / name)
    top_level_pngs = sorted(path.name for path in output_dir.glob("*.png"))
    if top_level_pngs:
        raise AssertionError(f"plots must be foldered, found top-level PNGs: {top_level_pngs}")

    spectrum = assert_rows(data_dir / "generated_spectrum.csv", expected=701)
    reference = assert_rows(data_dir / "reference_resampled.csv", expected=701)
    if not spectrum["wavelength_nm"].equals(reference["wavelength_nm"]):
        raise AssertionError("reference grid does not match generated spectrum grid")

    assert_rows(data_dir / "reflectance_residuals.csv", expected=701)
    assert_rows(data_dir / "atmospheric_budget.csv")
    assert_rows(data_dir / "o2_o2_cia_diagnostics.csv")
    assert_rows(data_dir / "instrument_response.csv")
    assert_rows(data_dir / "radiative_transfer_diagnostics.csv")

    print(f"verified real core-backed plotting bundle under {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
