#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "altair>=5.5",
#   "matplotlib>=3.10",
#   "numpy>=2.2",
#   "pandas>=2.2",
# ]
# ///

"""Generate retained O2 A fast-mode spectra diagnostics."""

import copy
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

import zdisamar as zd  # noqa: E402
from zdisamar.plot.properties import PLOT  # noqa: E402

from validation.common import o2a_optimal_estimation_setup as oe_setup  # noqa: E402
from validation.common import o2a_retrieval_baseline as oe_baseline  # noqa: E402
from validation.common.o2a_measurement_noise import components_from_spectrum  # noqa: E402
from validation.common.o2a_reference_case import build_o2a_case  # noqa: E402
from validation.common.paths import stable_repo_path, write_json  # noqa: E402
from validation.common.plot_style import (  # noqa: E402
    prepare_matplotlib,
    save_figure,
    style_axis,
    style_legend,
)
from validation.common.residuals import residual_metrics  # noqa: E402

LIBRARY_NAME = "libzdisamar_c.dylib" if sys.platform == "darwin" else "libzdisamar_c.so"
LIBRARY_PATH = REPO_ROOT / "zig-out" / "lib" / LIBRARY_NAME
OUTPUTS_DIR = REPO_ROOT / "validation" / "outputs" / "spectra"
PLOT_PATH = OUTPUTS_DIR / "o2a_fast_mode_spectra.png"
DATA_PATH = OUTPUTS_DIR / "o2a_fast_mode_spectra_data.csv"
METRICS_PATH = OUTPUTS_DIR / "o2a_fast_mode_spectra_metrics.json"

CANONICAL_COMMAND = "zig build validation-o2a-fast-mode-spectra"


@dataclass(frozen=True)
class SceneSpec:
    label: str
    scene: dict[str, float]


@dataclass(frozen=True)
class SpectrumRun:
    wavelength_nm: np.ndarray
    reflectance: np.ndarray
    radiance: np.ndarray
    irradiance: np.ndarray
    elapsed_s: float


@dataclass(frozen=True)
class SceneResult:
    label: str
    scene: dict[str, float]
    reference: SpectrumRun
    fast: SpectrumRun
    noise: np.ndarray


def scene_specs() -> list[SceneSpec]:
    return [
        SceneSpec(
            label="baseline",
            scene={
                "solar_zenith_deg": 60.0,
                "viewing_zenith_deg": 30.0,
                "relative_azimuth_deg": 120.0,
                "surface_pressure_hpa": 1013.25,
                "surface_albedo": 0.20,
                "aerosol_optical_depth": 0.30,
                "aerosol_mid_pressure_hpa": 510.0,
            },
        ),
        SceneSpec(
            label="bright surface",
            scene={
                "solar_zenith_deg": 35.0,
                "viewing_zenith_deg": 12.0,
                "relative_azimuth_deg": 150.0,
                "surface_pressure_hpa": 1013.25,
                "surface_albedo": 0.55,
                "aerosol_optical_depth": 0.12,
                "aerosol_mid_pressure_hpa": 720.0,
            },
        ),
        SceneSpec(
            label="oblique aerosol",
            scene={
                "solar_zenith_deg": 53.76029607719826,
                "viewing_zenith_deg": 45.71214389158657,
                "relative_azimuth_deg": 7.0232796692031245,
                "surface_pressure_hpa": 896.819424951348,
                "surface_albedo": 0.19528921533381227,
                "aerosol_optical_depth": 1.9681905891962788,
                "aerosol_mid_pressure_hpa": 329.192074869615,
            },
        ),
        SceneSpec(
            label="low sun dark surface",
            scene={
                "solar_zenith_deg": 65.0,
                "viewing_zenith_deg": 42.0,
                "relative_azimuth_deg": 25.0,
                "surface_pressure_hpa": 950.0,
                "surface_albedo": 0.08,
                "aerosol_optical_depth": 1.45,
                "aerosol_mid_pressure_hpa": 410.0,
            },
        ),
    ]


def make_case(base: Any, spec: SceneSpec, index: int) -> Any:
    return oe_setup.build_scene(
        base,
        index=index,
        id_prefix="o2a_fast_mode_spectra",
        scene=spec.scene,
    )


def with_fast_thresholds(case: Any) -> Any:
    return copy.deepcopy(case).with_fast_mode()


def evaluate_spectrum(case: Any) -> SpectrumRun:
    start = time.perf_counter()
    with (
        zd.prepare(case, library_path=str(LIBRARY_PATH)) as prepared,
        prepared.forward_model() as spectrum,
    ):
        wavelength_nm = spectrum.wavelength_nm.copy()
        reflectance = spectrum.reflectance.copy()
        radiance = spectrum.radiance.copy()
        irradiance = spectrum.irradiance.copy()
    return SpectrumRun(
        wavelength_nm=wavelength_nm,
        reflectance=reflectance,
        radiance=radiance,
        irradiance=irradiance,
        elapsed_s=time.perf_counter() - start,
    )


def run_cases() -> list[SceneResult]:
    base = build_o2a_case(zd)
    oe_baseline.configure_case(base)
    results = []
    for index, spec in enumerate(scene_specs(), start=1):
        reference_case = make_case(base, spec, index)
        fast_case = with_fast_thresholds(reference_case)
        reference = evaluate_spectrum(reference_case)
        fast = evaluate_spectrum(fast_case)
        if not np.array_equal(reference.wavelength_nm, fast.wavelength_nm):
            raise ValueError(f"wavelength grid changed for scene {spec.label}")
        noise = components_from_spectrum(
            wavelength_nm=reference.wavelength_nm,
            radiance=reference.radiance,
            irradiance=reference.irradiance,
            reflectance=reference.reflectance,
        ).reflectance_noise
        results.append(
            SceneResult(
                label=spec.label,
                scene=spec.scene,
                reference=reference,
                fast=fast,
                noise=noise,
            )
        )
    return results


def residual_over_noise(residual: np.ndarray, noise: np.ndarray) -> np.ndarray:
    return residual / np.maximum(noise, np.finfo(np.float64).tiny)


def fast_mode_overrides() -> dict[str, dict[str, float | int | None]]:
    fast = zd.RadiativeTransferPerformanceThresholds.fast()
    adaptive_grid: dict[str, float | int | None] = dict(zd.O2AInput.FAST_ADAPTIVE_REFERENCE_GRID)
    return {
        "radiative_transfer": {
            "fourier_order_cap": fast.fourier_order_cap,
            "fourier_tail_reflectance_epsilon": fast.fourier_tail_reflectance_epsilon,
            "threshold_doubl": fast.threshold_doubl,
        },
        "adaptive_reference_grid": adaptive_grid,
    }


def result_records(results: list[SceneResult]) -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    records: list[dict[str, Any]] = []
    metrics: list[dict[str, Any]] = []
    for result in results:
        residual = result.fast.reflectance - result.reference.reflectance
        normalized = residual_over_noise(residual, result.noise)
        residual_metric = residual_metrics(result.reference.wavelength_nm, residual)
        metrics.append(
            {
                "scene": result.label,
                "max_abs_residual": residual_metric["max_abs_residual"],
                "max_abs_residual_wavelength_nm": residual_metric["max_abs_wavelength_nm"],
                "rmse": residual_metric["rmse"],
                "max_abs_residual_over_noise": float(np.max(np.abs(normalized))),
                "median_abs_residual_over_noise": float(np.median(np.abs(normalized))),
                "reference_forward_s": result.reference.elapsed_s,
                "fast_forward_s": result.fast.elapsed_s,
                "forward_speedup_s": result.reference.elapsed_s - result.fast.elapsed_s,
                "scene_parameters": result.scene,
            }
        )
        for wavelength, reference, fast, value_residual, noise, normalized_value in zip(
            result.reference.wavelength_nm,
            result.reference.reflectance,
            result.fast.reflectance,
            residual,
            result.noise,
            normalized,
            strict=True,
        ):
            records.append(
                {
                    "scene": result.label,
                    "wavelength_nm": float(wavelength),
                    "reference_reflectance": float(reference),
                    "fast_reflectance": float(fast),
                    "fast_minus_reference": float(value_residual),
                    "reflectance_noise_1sigma": float(noise),
                    "fast_minus_reference_over_noise": float(normalized_value),
                }
            )
    return pd.DataFrame.from_records(records), metrics


def describe_scene(scene: dict[str, float]) -> str:
    return (
        f"SZA {scene['solar_zenith_deg']:.1f}, VZA {scene['viewing_zenith_deg']:.1f}, "
        f"RAA {scene['relative_azimuth_deg']:.1f}, "
        f"AOD {scene['aerosol_optical_depth']:.2f}, albedo {scene['surface_albedo']:.2f}"
    )


def create_plot(
    results: list[SceneResult],
    metrics: list[dict[str, Any]],
    output_path: Path,
) -> None:
    prepare_matplotlib()
    fig, axes = plt.subplots(
        len(results),
        2,
        figsize=(16.5, 13.8),
        sharex=True,
        constrained_layout=True,
        gridspec_kw={"width_ratios": [1.22, 1.0]},
    )
    fig.suptitle(
        "O2A Fast-Mode Spectra: Reference Thresholds vs Fast Thresholds",
        fontsize=18,
        fontweight="normal",
    )

    metric_by_scene = {str(metric["scene"]): metric for metric in metrics}
    for row_index, result in enumerate(results):
        residual = result.fast.reflectance - result.reference.reflectance
        normalized = residual_over_noise(residual, result.noise)
        metric = metric_by_scene[result.label]
        value_axis = axes[row_index, 0]
        residual_axis = axes[row_index, 1]

        value_axis.plot(
            result.reference.wavelength_nm,
            result.reference.reflectance,
            label="reference thresholds",
            color=PLOT.colors["blue"],
            linewidth=1.85,
        )
        value_axis.plot(
            result.fast.wavelength_nm,
            result.fast.reflectance,
            label="fast thresholds",
            color=PLOT.colors["orange"],
            linewidth=1.35,
            linestyle="--",
        )
        residual_axis.plot(
            result.reference.wavelength_nm,
            residual,
            color=PLOT.colors["black"],
            linewidth=1.05,
            label="fast - reference",
        )
        residual_axis.axhline(0.0, color="black", linewidth=0.75, linestyle=(0, (4, 3)))
        residual_axis_2 = residual_axis.twinx()
        residual_axis_2.plot(
            result.reference.wavelength_nm,
            normalized,
            color=PLOT.colors["red"],
            alpha=0.42,
            linewidth=0.9,
            label="residual / 1-sigma noise",
        )
        residual_axis_2.set_ylabel("residual / noise", color=PLOT.colors["red"], labelpad=10)
        residual_axis_2.tick_params(axis="y", colors=PLOT.colors["red"], labelsize=9)
        residual_axis_2.spines["right"].set_color(PLOT.colors["red"])
        residual_axis_2.spines["right"].set_linewidth(0.8)

        value_axis.set_title(
            f"{result.label}: {describe_scene(result.scene)}",
            loc="left",
            fontsize=11.5,
            pad=8,
        )
        residual_axis.set_title(
            (
                f"max |residual|={float(metric['max_abs_residual']):.2e}; "
                f"max |residual/noise|={float(metric['max_abs_residual_over_noise']):.2e}; "
                f"speedup={float(metric['forward_speedup_s']):+.3f}s"
            ),
            loc="left",
            fontsize=10.5,
            pad=8,
        )
        value_axis.set_ylabel("Reflectance", labelpad=12)
        residual_axis.set_ylabel("Fast - reference", labelpad=12)
        style_axis(value_axis)
        style_axis(residual_axis, scientific_y=True)
        value_axis.set_xlim(oe_baseline.WAVELENGTH_START_NM, oe_baseline.WAVELENGTH_END_NM)
        residual_axis.set_xlim(oe_baseline.WAVELENGTH_START_NM, oe_baseline.WAVELENGTH_END_NM)

    axes[-1, 0].set_xlabel("Wavelength [nm]")
    axes[-1, 1].set_xlabel("Wavelength [nm]")
    handles, labels = axes[0, 0].get_legend_handles_labels()
    legend = fig.legend(handles, labels, loc="upper right", bbox_to_anchor=(0.995, 0.995))
    style_legend(legend)
    save_figure(fig, output_path)


def write_metrics(metrics: list[dict[str, Any]], output_path: Path) -> None:
    payload = {
        "schema_version": 1,
        "canonical_command": CANONICAL_COMMAND,
        "fast_mode": {
            "method": "O2AInput.with_fast_mode()",
            "overrides": fast_mode_overrides(),
            "note": (
                "Fast mode preserves each case's physical scene and output wavelength grid, "
                "then applies validated radiative-transfer and adaptive-reference-grid "
                "performance overrides."
            ),
        },
        "outputs": {
            "plot": stable_repo_path(PLOT_PATH),
            "data": stable_repo_path(DATA_PATH),
            "metrics": stable_repo_path(METRICS_PATH),
        },
        "scenes": metrics,
    }
    write_json(output_path, payload)


def main() -> None:
    OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)
    results = run_cases()
    data, metrics = result_records(results)
    data.to_csv(DATA_PATH, index=False)
    create_plot(results, metrics, PLOT_PATH)
    write_metrics(metrics, METRICS_PATH)
    worst = max(metrics, key=lambda row: float(row["max_abs_residual"]))
    print(
        "o2a_fast_mode_spectra="
        f"{stable_repo_path(PLOT_PATH)} worst_scene={worst['scene']} "
        f"max_abs={float(worst['max_abs_residual']):.3e} "
        f"max_abs_over_noise={float(worst['max_abs_residual_over_noise']):.3e}"
    )


if __name__ == "__main__":
    main()
