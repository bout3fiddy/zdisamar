#!/usr/bin/env -S uv run
# pyright: reportMissingTypeStubs=false, reportUnknownMemberType=false

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import replace
import json
from pathlib import Path
import sys
import time
from typing import Literal, TypedDict, cast

import numpy as np
import numpy.typing as npt
import pandas as pd


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

import python.zdisamar as zd
import python.zdisamar.plot as zp
from scripts.testing_harness.python_o2a_validation_spectrum import (
    DEFAULT_LIBRARY,
    build_o2a_validation_scene,
    column_array,
    quantity_metrics,
    require_existing_file,
)


ScatteringMode = Literal["multiple", "single", "none"]
CaseName = Literal["validation", "varied", "cloud"]
QuantityName = Literal["reflectance", "radiance", "irradiance"]

CHEAP_MODES: tuple[ScatteringMode, ...] = ("single", "none")
ALL_MODES: tuple[ScatteringMode, ...] = ("multiple", "single", "none")
QUANTITIES: tuple[QuantityName, ...] = ("reflectance", "radiance", "irradiance")
ANCHOR_STRIDES: tuple[int, ...] = (2, 3, 4, 5, 8, 10, 16, 20, 32, 48, 64)
REFLECTANCE_THRESHOLDS: tuple[float, ...] = (1.0e-11, 1.0e-8, 1.0e-6, 1.0e-4, 1.0e-3, 2.0e-3)
OUTPUT_DIR = REPO_ROOT / "out" / "ci" / "o2a_fewer_rt_solve_probe"


class Timing(TypedDict):
    prepare_o2a_s: float
    forward_model_s: float


class CaseResult(TypedDict):
    case: CaseName
    scattering: ScatteringMode
    timing: Timing
    mean_reflectance: float


class SweepRow(TypedDict):
    case: CaseName
    cheap_scattering: ScatteringMode
    anchor_stride: int
    sample_count: int
    anchor_count: int
    anchor_fraction: float
    full_forward_s: float
    cheap_forward_s: float
    projected_forward_conservative_s: float
    projected_forward_incremental_s: float
    projected_speedup_conservative: float
    projected_speedup_incremental: float
    reflectance_mae: float
    reflectance_rmse: float
    reflectance_max_abs: float
    reflectance_mean_signed: float
    radiance_mae: float
    radiance_rmse: float
    radiance_max_abs: float
    radiance_mean_signed: float
    irradiance_mae: float
    irradiance_rmse: float
    irradiance_max_abs: float
    irradiance_mean_signed: float


class ThresholdRow(TypedDict, total=False):
    case: CaseName
    cheap_scattering: ScatteringMode
    reflectance_max_abs_threshold: float
    feasible: bool
    anchor_stride: int
    anchor_count: int
    projected_forward_incremental_s: float
    projected_speedup_incremental: float
    reflectance_max_abs: float


class Summary(TypedDict):
    cases: list[CaseResult]
    best_by_case_and_mode: list[SweepRow]
    best_under_reflectance_threshold: list[ThresholdRow]
    artifacts: dict[str, str]


def clone_scene(scene: zd.O2AInput) -> zd.O2AInput:
    return zd.O2AInput.from_dict(scene.to_dict())


def with_scattering(scene: zd.O2AInput, scattering: ScatteringMode) -> zd.O2AInput:
    cloned = clone_scene(scene)
    cloned.radiative_transfer = replace(cloned.radiative_transfer, scattering=scattering)
    cloned.metadata = dict(cloned.metadata)
    cloned.metadata["id"] = f"{cloned.metadata['id']}_{scattering}"
    cloned.scene_id = f"{cloned.scene_id}_{scattering}"
    return cloned


def build_varied_scene() -> zd.O2AInput:
    scene = clone_scene(build_o2a_validation_scene())
    scene.metadata = {
        **scene.metadata,
        "id": "o2a_fewer_rt_varied",
        "description": "O2 A probe case with varied geometry, surface, and aerosol loading.",
    }
    scene.scene_id = "o2a_fewer_rt_varied"
    scene.surface = replace(scene.surface, albedo=0.08)
    scene.geometry = replace(
        scene.geometry,
        solar_zenith_deg=42.0,
        viewing_zenith_deg=12.0,
        relative_azimuth_deg=35.0,
    )
    scene.aerosol = replace(
        scene.aerosol,
        optical_depth_550_nm=0.12,
        single_scatter_albedo=0.92,
        asymmetry_factor=0.55,
        angstrom_exponent=1.1,
        layer_center_km=5.1,
        layer_width_km=0.7,
    )
    return scene


def build_cloud_scene() -> zd.O2AInput:
    scene = clone_scene(build_varied_scene())
    scene.metadata = {
        **scene.metadata,
        "id": "o2a_fewer_rt_cloud",
        "description": "O2 A probe case with varied geometry, aerosol, surface, and cloud scattering.",
    }
    scene.scene_id = "o2a_fewer_rt_cloud"
    scene.surface = replace(scene.surface, albedo=0.15)
    scene.cloud = zd.Cloud(
        optical_thickness=0.6,
        single_scatter_albedo=0.99,
        asymmetry_factor=0.82,
        angstrom_exponent=0.0,
        reference_wavelength_nm=550.0,
        placement=zd.AerosolPlacement(
            semantics="explicit_interval_bounds",
            interval_index_1based=2,
            top_pressure_hpa=500.0,
            bottom_pressure_hpa=520.0,
        ),
    )
    return scene


def run_spectrum(scene: zd.O2AInput, library_path: Path) -> tuple[pd.DataFrame, Timing]:
    prepare_start = time.perf_counter()
    with zd.prepare(scene, library_path=library_path) as prepared:
        prepare_s = time.perf_counter() - prepare_start
        forward_start = time.perf_counter()
        with prepared.forward_model() as spectrum:
            forward_s = time.perf_counter() - forward_start
            frame = cast(pd.DataFrame, zp.to_dataframe(spectrum))
    return frame, {"prepare_o2a_s": prepare_s, "forward_model_s": forward_s}


def anchors_for_stride(sample_count: int, stride: int) -> npt.NDArray[np.int64]:
    anchor_values = list(range(0, sample_count, stride))
    if not anchor_values or anchor_values[-1] != sample_count - 1:
        anchor_values.append(sample_count - 1)
    return np.asarray(anchor_values, dtype=np.int64)


def interpolate_correction(
    wavelength_nm: npt.NDArray[np.float64],
    correction: npt.NDArray[np.float64],
    anchor_indices: npt.NDArray[np.int64],
) -> npt.NDArray[np.float64]:
    return np.interp(
        wavelength_nm,
        wavelength_nm[anchor_indices],
        correction[anchor_indices],
    )


def approximation_metrics(
    quantity: QuantityName,
    wavelength_nm: npt.NDArray[np.float64],
    anchor_indices: npt.NDArray[np.int64],
    full: pd.DataFrame,
    cheap: pd.DataFrame,
) -> tuple[float, float, float, float]:
    full_values = column_array(full, quantity)
    cheap_values = column_array(cheap, quantity)
    correction = full_values - cheap_values
    approximated = cheap_values + interpolate_correction(wavelength_nm, correction, anchor_indices)
    metrics = quantity_metrics(approximated, full_values)
    return (
        metrics["mae"],
        metrics["rmse"],
        metrics["max_abs"],
        metrics["mean_signed"],
    )


def array_float(values: npt.NDArray[np.float64], index: int) -> float:
    return float(cast(np.float64, values[index]))


def build_sweep_row(
    case: CaseName,
    cheap_scattering: ScatteringMode,
    stride: int,
    full: pd.DataFrame,
    cheap: pd.DataFrame,
    full_timing: Timing,
    cheap_timing: Timing,
) -> SweepRow:
    wavelength_nm = column_array(full, "wavelength_nm")
    sample_count = int(wavelength_nm.size)
    anchor_indices = anchors_for_stride(sample_count, stride)
    anchor_fraction = float(anchor_indices.size / sample_count)
    full_forward_s = full_timing["forward_model_s"]
    cheap_forward_s = cheap_timing["forward_model_s"]
    conservative_s = cheap_forward_s + full_forward_s * anchor_fraction
    incremental_s = cheap_forward_s + max(full_forward_s - cheap_forward_s, 0.0) * anchor_fraction

    reflectance = approximation_metrics("reflectance", wavelength_nm, anchor_indices, full, cheap)
    radiance = approximation_metrics("radiance", wavelength_nm, anchor_indices, full, cheap)
    irradiance = approximation_metrics("irradiance", wavelength_nm, anchor_indices, full, cheap)

    return {
        "case": case,
        "cheap_scattering": cheap_scattering,
        "anchor_stride": stride,
        "sample_count": sample_count,
        "anchor_count": int(anchor_indices.size),
        "anchor_fraction": anchor_fraction,
        "full_forward_s": full_forward_s,
        "cheap_forward_s": cheap_forward_s,
        "projected_forward_conservative_s": conservative_s,
        "projected_forward_incremental_s": incremental_s,
        "projected_speedup_conservative": full_forward_s / conservative_s,
        "projected_speedup_incremental": full_forward_s / incremental_s,
        "reflectance_mae": reflectance[0],
        "reflectance_rmse": reflectance[1],
        "reflectance_max_abs": reflectance[2],
        "reflectance_mean_signed": reflectance[3],
        "radiance_mae": radiance[0],
        "radiance_rmse": radiance[1],
        "radiance_max_abs": radiance[2],
        "radiance_mean_signed": radiance[3],
        "irradiance_mae": irradiance[0],
        "irradiance_rmse": irradiance[1],
        "irradiance_max_abs": irradiance[2],
        "irradiance_mean_signed": irradiance[3],
    }


def best_rows(rows: Iterable[SweepRow]) -> list[SweepRow]:
    grouped: dict[tuple[CaseName, ScatteringMode], SweepRow] = {}
    for row in rows:
        key = (row["case"], row["cheap_scattering"])
        existing = grouped.get(key)
        if existing is None:
            grouped[key] = row
            continue
        if row["reflectance_max_abs"] <= existing["reflectance_max_abs"]:
            grouped[key] = row
    return sorted(grouped.values(), key=lambda item: (item["case"], item["cheap_scattering"]))


def threshold_rows(rows: list[SweepRow]) -> list[ThresholdRow]:
    group_keys: set[tuple[CaseName, ScatteringMode]] = set()
    for row in rows:
        group_keys.add((row["case"], row["cheap_scattering"]))
    keys = sorted(group_keys)
    result: list[ThresholdRow] = []
    for threshold in REFLECTANCE_THRESHOLDS:
        for case, cheap_scattering in keys:
            feasible_rows = [
                row
                for row in rows
                if row["case"] == case
                and row["cheap_scattering"] == cheap_scattering
                and row["reflectance_max_abs"] <= threshold
            ]
            if not feasible_rows:
                result.append(
                    {
                        "case": case,
                        "cheap_scattering": cheap_scattering,
                        "reflectance_max_abs_threshold": threshold,
                        "feasible": False,
                    }
                )
                continue
            best = max(feasible_rows, key=lambda row: row["projected_speedup_incremental"])
            result.append(
                {
                    "case": case,
                    "cheap_scattering": cheap_scattering,
                    "reflectance_max_abs_threshold": threshold,
                    "feasible": True,
                    "anchor_stride": best["anchor_stride"],
                    "anchor_count": best["anchor_count"],
                    "projected_forward_incremental_s": best["projected_forward_incremental_s"],
                    "projected_speedup_incremental": best["projected_speedup_incremental"],
                    "reflectance_max_abs": best["reflectance_max_abs"],
                }
            )
    return result


def correction_sample_rows(
    case: CaseName,
    cheap_scattering: ScatteringMode,
    full: pd.DataFrame,
    cheap: pd.DataFrame,
) -> list[dict[str, float | str]]:
    wavelength_nm = column_array(full, "wavelength_nm")
    last_index = int(wavelength_nm.size - 1)
    sample_count = min(41, last_index + 1)
    sample_indices = [
        round(index * last_index / max(sample_count - 1, 1))
        for index in range(sample_count)
    ]
    rows: list[dict[str, float | str]] = []
    for index in sample_indices:
        row: dict[str, float | str] = {
            "case": case,
            "cheap_scattering": cheap_scattering,
            "wavelength_nm": array_float(wavelength_nm, index),
        }
        for quantity in QUANTITIES:
            full_value = array_float(column_array(full, quantity), index)
            cheap_value = array_float(column_array(cheap, quantity), index)
            row[f"full_{quantity}"] = full_value
            row[f"cheap_{quantity}"] = cheap_value
            row[f"correction_{quantity}"] = full_value - cheap_value
        rows.append(row)
    return rows


def write_json(path: Path, payload: object) -> None:
    _ = path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def main() -> int:
    library_path = require_existing_file(DEFAULT_LIBRARY, "Native zdisamar library")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    scenes: dict[CaseName, zd.O2AInput] = {
        "validation": build_o2a_validation_scene(),
        "varied": build_varied_scene(),
        "cloud": build_cloud_scene(),
    }
    spectra: dict[tuple[CaseName, ScatteringMode], pd.DataFrame] = {}
    timings: dict[tuple[CaseName, ScatteringMode], Timing] = {}
    case_results: list[CaseResult] = []

    for case, scene in scenes.items():
        for scattering in ALL_MODES:
            spectrum, timing = run_spectrum(with_scattering(scene, scattering), library_path)
            spectra[(case, scattering)] = spectrum
            timings[(case, scattering)] = timing
            case_results.append(
                {
                    "case": case,
                    "scattering": scattering,
                    "timing": timing,
                    "mean_reflectance": float(np.mean(column_array(spectrum, "reflectance"))),
                }
            )
            print(
                "".join(
                    (
                        f"{case}:{scattering} prepare_o2a_s={timing['prepare_o2a_s']:.6f} ",
                        f"forward_model_s={timing['forward_model_s']:.6f}",
                    )
                )
            )

    sweep_rows: list[SweepRow] = []
    sample_rows: list[dict[str, float | str]] = []
    for case in scenes:
        full = spectra[(case, "multiple")]
        full_timing = timings[(case, "multiple")]
        for cheap_scattering in CHEAP_MODES:
            cheap = spectra[(case, cheap_scattering)]
            cheap_timing = timings[(case, cheap_scattering)]
            for stride in ANCHOR_STRIDES:
                sweep_rows.append(
                    build_sweep_row(
                        case,
                        cheap_scattering,
                        stride,
                        full,
                        cheap,
                        full_timing,
                        cheap_timing,
                    )
                )
            sample_rows.extend(correction_sample_rows(case, cheap_scattering, full, cheap))

    anchor_sweep_path = OUTPUT_DIR / "anchor_sweep.csv"
    correction_samples_path = OUTPUT_DIR / "correction_samples.csv"
    summary_path = OUTPUT_DIR / "summary.json"
    pd.DataFrame.from_records(sweep_rows).to_csv(anchor_sweep_path, index=False)
    pd.DataFrame.from_records(sample_rows).to_csv(correction_samples_path, index=False)
    summary: Summary = {
        "cases": case_results,
        "best_by_case_and_mode": best_rows(sweep_rows),
        "best_under_reflectance_threshold": threshold_rows(sweep_rows),
        "artifacts": {
            "anchor_sweep_csv": str(anchor_sweep_path),
            "correction_samples_csv": str(correction_samples_path),
            "summary_json": str(summary_path),
        },
    }
    write_json(summary_path, summary)

    for row in summary["best_by_case_and_mode"]:
        print(
            "".join(
                (
                    f"best {row['case']}:{row['cheap_scattering']} stride={row['anchor_stride']} ",
                    f"projected_forward_incremental_s={row['projected_forward_incremental_s']:.6f} ",
                    f"speedup={row['projected_speedup_incremental']:.3f} ",
                    f"reflectance_max_abs={row['reflectance_max_abs']:.3e}",
                )
            )
        )
    print(f"summary={summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
