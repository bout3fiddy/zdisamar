#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "altair>=5.5",
#   "vl-convert-python>=1.7",
#   "numpy>=2.2",
#   "pandas>=2.2",
# ]
# ///

"""Validate retained fast-mode spectra outputs."""

import copy
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import altair as alt
import numpy as np
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

from zdisamar import rtm  # noqa: E402
from zdisamar.plot.properties import PLOT  # noqa: E402
from zdisamar.wavelength_bands import o2a  # noqa: E402

from validation.common.paths import stable_repo_path, write_json  # noqa: E402
from validation.o2a import baseline as oe_baseline  # noqa: E402
from validation.o2a.case import build_o2a_case  # noqa: E402
from validation.o2a.measurement_noise import components_from_spectrum  # noqa: E402
from validation.optimal_estimation import setup as oe_setup  # noqa: E402
from validation.spectra.residuals import residual_metrics  # noqa: E402

OUTPUTS_DIR = REPO_ROOT / "validation" / "outputs" / "spectra"
PLOT_PATH = OUTPUTS_DIR / "o2a_fast_mode_spectra.png"
DATA_PATH = OUTPUTS_DIR / "o2a_fast_mode_spectra_data.csv"
METRICS_PATH = OUTPUTS_DIR / "o2a_fast_mode_spectra_metrics.json"

CANONICAL_COMMAND = "uv run validation/spectra/validate_fast_mode_spectra.py"
FAST_MODE_REFLECTANCE_THRESHOLD = 5.0e-4


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

    fast_case = copy.deepcopy(case)
    fast_case.optimisation.fastmode.enabled = True

    return fast_case


def evaluate_spectrum(case: Any) -> SpectrumRun:

    start = time.perf_counter()
    spectrum = rtm.spectrum(case)
    wavelength_nm = np.asarray(spectrum.wavelength_nm, dtype=np.float64).copy()
    reflectance = np.asarray(spectrum.reflectance, dtype=np.float64).copy()
    radiance = np.asarray(spectrum.radiance, dtype=np.float64).copy()
    irradiance = np.asarray(spectrum.irradiance, dtype=np.float64).copy()

    return SpectrumRun(
        wavelength_nm=wavelength_nm,
        reflectance=reflectance,
        radiance=radiance,
        irradiance=irradiance,
        elapsed_s=time.perf_counter() - start,
    )


def run_cases() -> list[SceneResult]:

    base = build_o2a_case(o2a)
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


def fast_mode_overrides() -> dict[str, object]:

    base = build_o2a_case(o2a)
    oe_baseline.configure_case(base)
    fast_case = copy.deepcopy(base)
    fast_case.optimisation.fastmode.enabled = True
    resolved = fast_case.optimisation.fastmode.resolved_dict(fast_case.measurement_wavelengths_nm)

    return {
        "radiative_transfer": resolved["radiative_transfer"],
        "adaptive_reference_grid": resolved["adaptive_reference_grid"],
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
                "reference_rtm_s": result.reference.elapsed_s,
                "fast_rtm_s": result.fast.elapsed_s,
                "rtm_speedup_s": result.reference.elapsed_s - result.fast.elapsed_s,
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

    metric_by_scene = {str(metric["scene"]): metric for metric in metrics}
    rows = []

    for result in results:
        residual = result.fast.reflectance - result.reference.reflectance
        normalized = residual_over_noise(residual, result.noise)
        metric = metric_by_scene[result.label]
        frame = pd.DataFrame(
            {
                "wavelength_nm": np.tile(result.reference.wavelength_nm, 2),
                "reflectance": np.concatenate(
                    [result.reference.reflectance, result.fast.reflectance]
                ),
                "mode": ["reference thresholds"] * len(result.reference.wavelength_nm)
                + ["fast thresholds"] * len(result.fast.wavelength_nm),
            }
        )
        residual_frame = pd.DataFrame(
            {
                "wavelength_nm": result.reference.wavelength_nm,
                "fast_minus_reference": residual,
                "fast_minus_reference_over_noise": normalized,
            }
        )
        x = alt.X(
            "wavelength_nm:Q",
            title="Wavelength [nm]",
            scale=alt.Scale(
                domain=[oe_baseline.WAVELENGTH_START_NM, oe_baseline.WAVELENGTH_END_NM],
                zero=False,
            ),
        )
        values = (
            alt.Chart(frame)
            .mark_line()
            .encode(
                x=x,
                y=alt.Y("reflectance:Q", title="Reflectance", scale=alt.Scale(zero=False)),
                color=alt.Color(
                    "mode:N",
                    title=None,
                    scale=alt.Scale(
                        domain=["reference thresholds", "fast thresholds"],
                        range=[PLOT.colors["blue"], PLOT.colors["orange"]],
                    ),
                ),
                strokeDash=alt.StrokeDash(
                    "mode:N",
                    title=None,
                    scale=alt.Scale(
                        domain=["reference thresholds", "fast thresholds"],
                        range=[[1, 0], [5, 4]],
                    ),
                ),
                tooltip=[
                    alt.Tooltip("wavelength_nm:Q", title="Wavelength [nm]", format=".4f"),
                    alt.Tooltip("mode:N", title="Mode"),
                    alt.Tooltip("reflectance:Q", title="Reflectance", format=".8g"),
                ],
            )
            .properties(
                width=620,
                height=190,
                title=f"{result.label}: {describe_scene(result.scene)}",
            )
        )
        zero = (
            alt.Chart(pd.DataFrame({"zero": [0.0]}))
            .mark_rule(color=PLOT.colors["black"], strokeDash=[4, 3], strokeWidth=0.75)
            .encode(y="zero:Q")
        )
        raw_residual = (
            alt.Chart(residual_frame)
            .mark_line(color=PLOT.colors["black"], strokeWidth=1.05)
            .encode(
                x=x,
                y=alt.Y(
                    "fast_minus_reference:Q",
                    title="Fast - reference",
                    axis=alt.Axis(format=".3e"),
                    scale=alt.Scale(zero=False),
                ),
                tooltip=[
                    alt.Tooltip("wavelength_nm:Q", title="Wavelength [nm]", format=".4f"),
                    alt.Tooltip(
                        "fast_minus_reference:Q",
                        title="Fast - reference",
                        format=".8g",
                    ),
                ],
            )
        )
        normalized_residual = (
            alt.Chart(residual_frame)
            .mark_line(color=PLOT.colors["red"], opacity=0.45, strokeWidth=0.9)
            .encode(
                x=x,
                y=alt.Y(
                    "fast_minus_reference_over_noise:Q",
                    title="Residual / noise",
                    axis=alt.Axis(format=".3g", orient="right"),
                    scale=alt.Scale(zero=False),
                ),
                tooltip=[
                    alt.Tooltip("wavelength_nm:Q", title="Wavelength [nm]", format=".4f"),
                    alt.Tooltip(
                        "fast_minus_reference_over_noise:Q",
                        title="Residual / noise",
                        format=".6g",
                    ),
                ],
            )
        )
        residual_chart = (
            alt.layer(zero, raw_residual, normalized_residual)
            .resolve_scale(y="independent")
            .properties(
                width=500,
                height=190,
                title=(
                    f"max |residual|={float(metric['max_abs_residual']):.2e}; "
                    f"max |residual/noise|={float(metric['max_abs_residual_over_noise']):.2e}; "
                    f"speedup={float(metric['rtm_speedup_s']):+.3f}s"
                ),
            )
        )
        rows.append(alt.hconcat(values, residual_chart, spacing=28))

    chart = alt.vconcat(*rows, spacing=18).properties(
        title="O2A Fast-Mode Spectra: Reference Thresholds vs Fast Thresholds"
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    chart.save(output_path, scale_factor=4.0)


def write_metrics(metrics: list[dict[str, Any]], output_path: Path) -> None:

    payload = {
        "schema_version": 1,
        "canonical_command": CANONICAL_COMMAND,
        "fast_mode": {
            "method": "case.optimisation.fastmode.enabled = True",
            "overrides": fast_mode_overrides(),
            "note": (
                "Fast mode preserves each scene's physical configuration and output "
                "wavelength grid, "
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


def validate_metrics(metrics: list[dict[str, Any]]) -> None:

    failures = []

    for metric in metrics:
        residual = float(metric["max_abs_residual"])

        if residual > FAST_MODE_REFLECTANCE_THRESHOLD:
            failures.append(
                f"{metric['scene']} max_abs_residual {residual:.3e} exceeds "
                f"{FAST_MODE_REFLECTANCE_THRESHOLD:.3e}"
            )

    if failures:
        details = "; ".join(failures)
        raise SystemExit(f"fast-mode spectra validation failed: {details}")


def main() -> None:

    OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)
    results = run_cases()
    data, metrics = result_records(results)
    validate_metrics(metrics)
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
