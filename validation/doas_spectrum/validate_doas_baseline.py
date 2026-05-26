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

"""Build retained evidence for the DOAS-like O2 A spectrum baseline."""

import copy
import math
import sys
import time
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import altair as alt
import numpy as np
import pandas as pd
from numpy.typing import NDArray

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

from zdisamar import rtm  # noqa: E402
from zdisamar.input.instrument import SpectralGrid  # noqa: E402
from zdisamar.inverse_method import optimal_estimation  # noqa: E402
from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe  # noqa: E402
from zdisamar.plot.properties import PLOT  # noqa: E402
from zdisamar.wavelength_bands import o2a  # noqa: E402

from validation.common.paths import stable_repo_path, write_json  # noqa: E402
from validation.o2a import baseline as oe_baseline  # noqa: E402
from validation.o2a.case import build_o2a_case  # noqa: E402
from validation.o2a.measurement_noise import (  # noqa: E402
    components_from_spectrum,
    measurement_from_o2a_baseline_noise,
)
from validation.optimal_estimation import reference_cases as oe_cases  # noqa: E402
from validation.optimal_estimation import setup as oe_setup  # noqa: E402
from validation.spectra.residuals import residual_metrics  # noqa: E402

OUTPUTS_DIR = REPO_ROOT / "validation" / "outputs" / "doas_spectrum"
SPECTRUM_PLOT_PATH = OUTPUTS_DIR / "doas_spectrum_residuals.png"
SPECTRUM_DATA_PATH = OUTPUTS_DIR / "doas_spectrum_residuals.csv"
OE_PLOT_PATH = OUTPUTS_DIR / "doas_oe_comparison.png"
OE_DATA_PATH = OUTPUTS_DIR / "doas_oe_comparison_runs.csv"
SUMMARY_PATH = OUTPUTS_DIR / "doas_baseline_summary.json"

CANONICAL_COMMAND = "uv run validation/doas_spectrum/validate_doas_baseline.py"
SMOOTH_DEGREE = 4
SPECTRUM_SUPPORT_MAX = 33
OE_SUPPORT_MAX = 17
OE_WAVELENGTH_COUNT = 81
OE_CASE_COUNT = 2
OE_MAX_ITERATIONS = 5
LOG_REFLECTANCE_MIN = -745.0
LOG_REFLECTANCE_MAX = 80.0
STATE_NAMES = (
    "aerosol_optical_depth",
    "aerosol_layer_mid_pressure_hpa",
)

FloatArray = NDArray[np.float64]


@dataclass(frozen=True)
class SceneSpec:
    label: str
    scene: dict[str, float]


@dataclass(frozen=True)
class DoasSettings:
    smooth_degree: int
    max_support_wavelengths: int


@dataclass(frozen=True)
class SpectrumRun:
    wavelength_nm: FloatArray
    reflectance: FloatArray
    radiance: FloatArray
    irradiance: FloatArray
    elapsed_s: float


@dataclass(frozen=True)
class OpticalDepthProxy:
    gas_vertical_tau: FloatArray
    cia_vertical_tau: FloatArray
    gas_smooth_tau: FloatArray
    gas_diff_tau: FloatArray
    slant_diff_tau: FloatArray
    geometric_amf: float
    elapsed_s: float


@dataclass(frozen=True)
class ApproxSpectrum:
    wavelength_nm: FloatArray
    reflectance: FloatArray
    support_wavelength_nm: FloatArray
    support_reflectance: FloatArray
    optical_depth: OpticalDepthProxy
    support_spectrum_s: float
    reconstruction_s: float
    support_source: str

    @property
    def runtime_proxy_s(self) -> float:

        return self.support_spectrum_s + self.reconstruction_s

    @property
    def diagnostic_total_s(self) -> float:

        return self.optical_depth.elapsed_s + self.runtime_proxy_s


@dataclass(frozen=True)
class DoasIteration:
    index: int
    state_before: FloatArray
    state_after: FloatArray
    chi2_reflectance: float
    chi2_state_vector: float
    state_vector_convergence: float
    elapsed_s: float


@dataclass(frozen=True)
class DoasRetrieval:
    state: FloatArray
    iterations: tuple[DoasIteration, ...]
    converged: bool
    posterior_covariance: FloatArray
    final_approx: ApproxSpectrum
    elapsed_s: float

    @property
    def iteration_count(self) -> int:

        return len(self.iterations)


def spectrum_scene_specs() -> list[SceneSpec]:

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
    ]


def evaluate_spectrum(case: Any) -> SpectrumRun:

    start = time.perf_counter()
    spectrum = rtm.spectrum(case)

    return SpectrumRun(
        wavelength_nm=np.asarray(spectrum.wavelength_nm, dtype=np.float64).copy(),
        reflectance=np.asarray(spectrum.reflectance, dtype=np.float64).copy(),
        radiance=np.asarray(spectrum.radiance, dtype=np.float64).copy(),
        irradiance=np.asarray(spectrum.irradiance, dtype=np.float64).copy(),
        elapsed_s=time.perf_counter() - start,
    )


def case_with_wavelengths(case: Any, wavelength_nm: Sequence[float]) -> Any:

    wavelengths = np.asarray(wavelength_nm, dtype=np.float64)

    if wavelengths.ndim != 1 or wavelengths.size < 2:
        raise ValueError("wavelength grid must contain at least two samples")

    if not np.all(np.isfinite(wavelengths)):
        raise ValueError("wavelength grid must contain finite values")

    if not np.all(np.diff(wavelengths) > 0.0):
        raise ValueError("wavelength grid must be strictly increasing")

    copied = copy.copy(case)
    copied.instrument_response = copy.copy(case.instrument_response)
    copied.spectral_grid = SpectralGrid(
        start_nm=float(wavelengths[0]),
        end_nm=float(wavelengths[-1]),
        sample_count=int(wavelengths.size),
    )
    copied.instrument_response.measured_wavelengths_nm = tuple(
        float(wavelength) for wavelength in wavelengths
    )

    return copied


def uniform_wavelength_case(case: Any, sample_count: int) -> Any:

    wavelengths = np.linspace(
        float(case.spectral_grid.start_nm),
        float(case.spectral_grid.end_nm),
        sample_count,
        dtype=np.float64,
    )

    return case_with_wavelengths(case, wavelengths)


def scaled_legendre_axis(
    wavelength_nm: FloatArray,
    domain: tuple[float, float],
) -> FloatArray:

    start_nm, end_nm = domain

    if end_nm <= start_nm:
        raise ValueError("Legendre domain must be increasing")

    return 2.0 * (wavelength_nm - start_nm) / (end_nm - start_nm) - 1.0


def legendre_fit(
    wavelength_nm: FloatArray,
    values: FloatArray,
    degree: int,
    domain: tuple[float, float],
) -> FloatArray:

    safe_degree = min(int(degree), int(wavelength_nm.size) - 1)

    if safe_degree < 0:
        raise ValueError("Legendre fit needs at least one sample")

    x = scaled_legendre_axis(wavelength_nm, domain)

    return np.asarray(np.polynomial.legendre.legfit(x, values, safe_degree), dtype=np.float64)


def legendre_eval(
    wavelength_nm: FloatArray,
    coefficients: FloatArray,
    domain: tuple[float, float],
) -> FloatArray:

    x = scaled_legendre_axis(wavelength_nm, domain)

    return np.asarray(np.polynomial.legendre.legval(x, coefficients), dtype=np.float64)


def geometric_airmass_factor(case: Any) -> float:

    mu0 = float(case.geometry.solar_mu0)
    mu = math.cos(math.radians(float(case.geometry.viewing_zenith_deg)))

    if mu0 <= 0.0 or mu <= 0.0:
        raise ValueError("DOAS baseline needs positive solar and viewing cosines")

    return 1.0 / mu0 + 1.0 / mu


def optical_depth_proxy(case: Any, wavelength_nm: FloatArray, degree: int) -> OpticalDepthProxy:

    start = time.perf_counter()
    budget = rtm.atmospheric_budget(case, wavelength_nm.tolist())
    rows = budget.to_rows()
    gas_by_wavelength = {round(float(wavelength), 12): 0.0 for wavelength in wavelength_nm}
    cia_by_wavelength = {round(float(wavelength), 12): 0.0 for wavelength in wavelength_nm}

    for row in rows:
        if float(row["path_length_cm"]) <= 0.0:
            continue

        key = round(float(row["wavelength_nm"]), 12)
        gas_by_wavelength[key] = gas_by_wavelength.get(key, 0.0) + float(
            row["gas_absorption_optical_depth"]
        )
        cia_by_wavelength[key] = cia_by_wavelength.get(key, 0.0) + float(row["cia_optical_depth"])

    gas_tau = np.asarray(
        [gas_by_wavelength[round(float(wavelength), 12)] for wavelength in wavelength_nm],
        dtype=np.float64,
    )
    cia_tau = np.asarray(
        [cia_by_wavelength[round(float(wavelength), 12)] for wavelength in wavelength_nm],
        dtype=np.float64,
    )
    domain = (float(wavelength_nm[0]), float(wavelength_nm[-1]))
    smooth_coefficients = legendre_fit(wavelength_nm, gas_tau, degree, domain)
    gas_smooth_tau = legendre_eval(wavelength_nm, smooth_coefficients, domain)
    gas_diff_tau = gas_tau - gas_smooth_tau
    amf = geometric_airmass_factor(case)

    return OpticalDepthProxy(
        gas_vertical_tau=gas_tau,
        cia_vertical_tau=cia_tau,
        gas_smooth_tau=gas_smooth_tau,
        gas_diff_tau=gas_diff_tau,
        slant_diff_tau=gas_diff_tau * amf,
        geometric_amf=amf,
        elapsed_s=time.perf_counter() - start,
    )


def zero_crossings(wavelength_nm: FloatArray, values: FloatArray) -> FloatArray:

    crossings: list[float] = []

    for index in range(wavelength_nm.size - 1):
        left = float(values[index])
        right = float(values[index + 1])

        if left == 0.0:
            crossings.append(float(wavelength_nm[index]))

        if left * right < 0.0:
            fraction = abs(left) / (abs(left) + abs(right))
            crossings.append(
                float(wavelength_nm[index])
                + fraction * float(wavelength_nm[index + 1] - wavelength_nm[index])
            )

    if float(values[-1]) == 0.0:
        crossings.append(float(wavelength_nm[-1]))

    return np.unique(np.asarray(crossings, dtype=np.float64))


def evenly_spaced_support(wavelength_nm: FloatArray, count: int) -> FloatArray:

    return np.linspace(
        float(wavelength_nm[0]),
        float(wavelength_nm[-1]),
        count,
        dtype=np.float64,
    )


def select_support_wavelengths(
    wavelength_nm: FloatArray,
    tau_diff: FloatArray,
    *,
    degree: int,
    max_support: int,
) -> tuple[FloatArray, str]:

    minimum = max(degree + 1, 5)
    crossings = zero_crossings(wavelength_nm, tau_diff)
    endpoints = np.asarray([wavelength_nm[0], wavelength_nm[-1]], dtype=np.float64)

    if crossings.size >= minimum:
        candidates = np.unique(np.concatenate([endpoints, crossings]))
        source = "tau-diff zero crossings"
    else:
        support_count = min(max_support, max(minimum, crossings.size + 2))
        candidates = evenly_spaced_support(wavelength_nm, support_count)
        source = "fallback evenly spaced wavelengths"

    if candidates.size > max_support:
        retained = np.linspace(0, candidates.size - 1, max_support)
        candidates = np.unique(candidates[np.rint(retained).astype(np.int64)])

    if candidates.size < minimum:
        candidates = evenly_spaced_support(wavelength_nm, min(max_support, minimum))
        source = "fallback evenly spaced wavelengths"

    return np.asarray(candidates, dtype=np.float64), source


def approximate_spectrum(
    case: Any,
    settings: DoasSettings,
    wavelength_nm: FloatArray,
) -> ApproxSpectrum:

    start = time.perf_counter()
    optical_depth = optical_depth_proxy(case, wavelength_nm, settings.smooth_degree)
    support_wavelengths, support_source = select_support_wavelengths(
        wavelength_nm,
        optical_depth.gas_diff_tau,
        degree=settings.smooth_degree,
        max_support=settings.max_support_wavelengths,
    )
    support_case = case_with_wavelengths(case, support_wavelengths)
    support_spectrum = evaluate_spectrum(support_case)
    domain = (float(wavelength_nm[0]), float(wavelength_nm[-1]))
    log_support = np.log(np.maximum(support_spectrum.reflectance, np.finfo(np.float64).tiny))
    smooth_coefficients = legendre_fit(
        support_spectrum.wavelength_nm,
        log_support,
        settings.smooth_degree,
        domain,
    )
    log_smooth = legendre_eval(wavelength_nm, smooth_coefficients, domain)
    log_reconstructed = np.clip(
        log_smooth - optical_depth.slant_diff_tau,
        LOG_REFLECTANCE_MIN,
        LOG_REFLECTANCE_MAX,
    )
    reflectance = np.exp(log_reconstructed)

    return ApproxSpectrum(
        wavelength_nm=wavelength_nm.copy(),
        reflectance=reflectance,
        support_wavelength_nm=support_spectrum.wavelength_nm,
        support_reflectance=support_spectrum.reflectance,
        optical_depth=optical_depth,
        support_spectrum_s=support_spectrum.elapsed_s,
        reconstruction_s=time.perf_counter() - start - optical_depth.elapsed_s,
        support_source=support_source,
    )


def residual_over_noise(residual: FloatArray, noise: FloatArray) -> FloatArray:

    return residual / np.maximum(noise, np.finfo(np.float64).tiny)


def stats(values: pd.Series) -> dict[str, float]:

    if values.empty:
        return {
            "min": math.nan,
            "median": math.nan,
            "mean": math.nan,
            "max": math.nan,
            "max_abs": math.nan,
        }

    return {
        "min": float(values.min()),
        "median": float(values.median()),
        "mean": float(values.mean()),
        "max": float(values.max()),
        "max_abs": float(values.abs().max()),
    }


def spectrum_records() -> tuple[pd.DataFrame, list[dict[str, Any]]]:

    base = build_o2a_case(o2a)
    oe_baseline.configure_case(base)
    settings = DoasSettings(
        smooth_degree=SMOOTH_DEGREE,
        max_support_wavelengths=SPECTRUM_SUPPORT_MAX,
    )
    records: list[dict[str, Any]] = []
    metrics: list[dict[str, Any]] = []

    for index, spec in enumerate(spectrum_scene_specs(), start=1):
        reference_case = oe_setup.build_scene(
            base,
            index=index,
            id_prefix="o2a_doas_spectrum",
            scene=spec.scene,
        )
        reference = evaluate_spectrum(reference_case)
        approximate = approximate_spectrum(
            reference_case,
            settings,
            reference.wavelength_nm,
        )
        residual = approximate.reflectance - reference.reflectance
        noise = components_from_spectrum(
            wavelength_nm=reference.wavelength_nm,
            radiance=reference.radiance,
            irradiance=reference.irradiance,
            reflectance=reference.reflectance,
        ).reflectance_noise
        normalized = residual_over_noise(residual, noise)
        residual_metric = residual_metrics(reference.wavelength_nm, residual)
        metrics.append(
            {
                "scene": spec.label,
                "max_abs_residual": residual_metric["max_abs_residual"],
                "max_abs_residual_wavelength_nm": residual_metric["max_abs_wavelength_nm"],
                "rmse": residual_metric["rmse"],
                "mean_signed": residual_metric["mean_signed"],
                "max_abs_residual_over_noise": float(np.max(np.abs(normalized))),
                "median_abs_residual_over_noise": float(np.median(np.abs(normalized))),
                "reference_spectrum_s": reference.elapsed_s,
                "doas_runtime_proxy_s": approximate.runtime_proxy_s,
                "doas_diagnostic_total_s": approximate.diagnostic_total_s,
                "doas_runtime_proxy_speedup": reference.elapsed_s / approximate.runtime_proxy_s,
                "doas_diagnostic_total_speedup": reference.elapsed_s
                / approximate.diagnostic_total_s,
                "support_wavelength_count": int(approximate.support_wavelength_nm.size),
                "support_source": approximate.support_source,
                "geometric_amf": approximate.optical_depth.geometric_amf,
                "max_gas_vertical_tau": float(np.max(approximate.optical_depth.gas_vertical_tau)),
                "max_cia_vertical_tau": float(np.max(approximate.optical_depth.cia_vertical_tau)),
                "scene_parameters": spec.scene,
            }
        )

        for wavelength, reference_value, doas_value, value_residual, noise_value in zip(
            reference.wavelength_nm,
            reference.reflectance,
            approximate.reflectance,
            residual,
            noise,
            strict=True,
        ):
            records.append(
                {
                    "analysis": "spectrum",
                    "scene": spec.label,
                    "wavelength_nm": float(wavelength),
                    "reference_reflectance": float(reference_value),
                    "doas_reflectance": float(doas_value),
                    "doas_minus_reference": float(value_residual),
                    "reflectance_noise_1sigma": float(noise_value),
                    "doas_minus_reference_over_noise": float(value_residual / noise_value),
                }
            )

        support_rows = pd.DataFrame(
            {
                "analysis": "spectrum_support",
                "scene": spec.label,
                "wavelength_nm": approximate.support_wavelength_nm,
                "reference_reflectance": approximate.support_reflectance,
                "doas_reflectance": approximate.support_reflectance,
                "doas_minus_reference": np.zeros_like(approximate.support_wavelength_nm),
                "reflectance_noise_1sigma": np.full(
                    approximate.support_wavelength_nm.shape,
                    math.nan,
                    dtype=np.float64,
                ),
                "doas_minus_reference_over_noise": np.full(
                    approximate.support_wavelength_nm.shape,
                    math.nan,
                    dtype=np.float64,
                ),
            }
        )
        records.extend(support_rows.to_dict(orient="records"))
        print(f"spectrum {spec.label} complete", flush=True)

    return pd.DataFrame.from_records(records), metrics


def spectrum_plot(data: pd.DataFrame, metrics: list[dict[str, Any]], output_path: Path) -> None:

    metric_by_scene = {str(metric["scene"]): metric for metric in metrics}
    rows = []

    for scene in [spec.label for spec in spectrum_scene_specs()]:
        scene_data = data[(data["analysis"] == "spectrum") & (data["scene"] == scene)]
        support_data = data[(data["analysis"] == "spectrum_support") & (data["scene"] == scene)]
        long = pd.DataFrame(
            {
                "wavelength_nm": np.tile(scene_data["wavelength_nm"].to_numpy(), 2),
                "reflectance": np.concatenate(
                    [
                        scene_data["reference_reflectance"].to_numpy(),
                        scene_data["doas_reflectance"].to_numpy(),
                    ]
                ),
                "mode": ["full physics"] * len(scene_data)
                + ["DOAS-like reconstruction"] * len(scene_data),
            }
        )
        metric = metric_by_scene[scene]
        title = (
            f"{scene}: max |residual| {metric['max_abs_residual']:.3e}, "
            f"proxy speedup {metric['doas_runtime_proxy_speedup']:.2f}x"
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
            alt.Chart(long)
            .mark_line(clip=True)
            .encode(
                x=x,
                y=alt.Y(
                    "reflectance:Q",
                    title="Reflectance",
                    scale=alt.Scale(domain=[0.0, 1.0], clamp=True),
                ),
                color=alt.Color(
                    "mode:N",
                    title=None,
                    scale=alt.Scale(
                        domain=["full physics", "DOAS-like reconstruction"],
                        range=[PLOT.colors["blue"], PLOT.colors["orange"]],
                    ),
                ),
            )
            .properties(width=900, height=145, title=title)
        )
        support = (
            alt.Chart(support_data)
            .mark_point(filled=True, size=18, opacity=0.75, color=PLOT.colors["red"])
            .encode(
                x=x,
                y=alt.Y(
                    "reference_reflectance:Q",
                    title="Reflectance",
                    scale=alt.Scale(zero=False),
                ),
            )
        )
        residual = (
            alt.Chart(scene_data)
            .mark_line(color=PLOT.colors["red"])
            .encode(
                x=x,
                y=alt.Y(
                    "doas_minus_reference:Q",
                    title="DOAS - full physics",
                    scale=alt.Scale(type="symlog", constant=1.0e-3),
                ),
                tooltip=[
                    alt.Tooltip("wavelength_nm:Q", title="Wavelength", format=".4f"),
                    alt.Tooltip("doas_minus_reference:Q", title="Residual", format=".3e"),
                    alt.Tooltip(
                        "doas_minus_reference_over_noise:Q",
                        title="Residual/noise",
                        format=".3e",
                    ),
                ],
            )
            .properties(width=900, height=110)
        )
        zero = (
            alt.Chart(pd.DataFrame({"zero": [0.0]}))
            .mark_rule(color=PLOT.colors["black"], strokeDash=[4, 3], strokeWidth=0.8)
            .encode(y="zero:Q")
        )
        rows.append(alt.vconcat(values + support, residual + zero, spacing=6))

    chart = alt.vconcat(*rows, spacing=20).configure_axis(labelFontSize=11, titleFontSize=12)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    chart.save(str(output_path), scale_factor=1.0)


def measurement_arrays(
    measurement: optimal_estimation.Measurement,
) -> tuple[FloatArray, FloatArray, FloatArray]:

    return (
        np.asarray(measurement.wavelength_nm, dtype=np.float64),
        np.asarray(measurement.reflectance, dtype=np.float64),
        np.asarray(measurement.variance, dtype=np.float64),
    )


def finite_difference_step(state: FloatArray, state_index: int) -> float:

    if STATE_NAMES[state_index] == "aerosol_optical_depth":
        return max(2.0e-3, abs(float(state[state_index])) * 5.0e-3)

    return 2.0


def approximate_for_state(
    template: Any,
    state: FloatArray,
    state_vector: optimal_estimation.StateVector,
    settings: DoasSettings,
    wavelength_nm: FloatArray,
) -> ApproxSpectrum:

    state_case = o2a_oe.case_for_state(template, state.tolist(), state_vector)

    return approximate_spectrum(state_case, settings, wavelength_nm)


def finite_difference_jacobian(
    template: Any,
    state: FloatArray,
    state_vector: optimal_estimation.StateVector,
    settings: DoasSettings,
    wavelength_nm: FloatArray,
) -> FloatArray:

    jacobian = np.empty((wavelength_nm.size, state.size), dtype=np.float64)

    for state_index in range(state.size):
        step = finite_difference_step(state, state_index)
        plus = state.copy()
        minus = state.copy()
        plus[state_index] += step
        minus[state_index] -= step
        plus = np.asarray(state_vector.clip_to_bounds(plus), dtype=np.float64)
        minus = np.asarray(state_vector.clip_to_bounds(minus), dtype=np.float64)
        denominator = float(plus[state_index] - minus[state_index])

        if abs(denominator) <= np.finfo(np.float64).eps:
            raise ValueError(
                f"finite-difference denominator vanished for {STATE_NAMES[state_index]}"
            )

        plus_reflectance = approximate_for_state(
            template,
            plus,
            state_vector,
            settings,
            wavelength_nm,
        ).reflectance
        minus_reflectance = approximate_for_state(
            template,
            minus,
            state_vector,
            settings,
            wavelength_nm,
        ).reflectance
        jacobian[:, state_index] = (plus_reflectance - minus_reflectance) / denominator

    return jacobian


def inverse_or_pseudo_inverse(matrix: FloatArray) -> FloatArray:

    try:
        return np.linalg.inv(matrix)
    except np.linalg.LinAlgError:
        return np.linalg.pinv(matrix)


def solve_or_lstsq(matrix: FloatArray, vector: FloatArray) -> FloatArray:

    try:
        return np.linalg.solve(matrix, vector)
    except np.linalg.LinAlgError:
        return np.linalg.lstsq(matrix, vector, rcond=None)[0]


def run_doas_like_oe(
    *,
    case: Any,
    measurement: optimal_estimation.Measurement,
    state_vector: optimal_estimation.StateVector,
    controls: optimal_estimation.RetrievalControls,
    settings: DoasSettings,
) -> DoasRetrieval:

    wavelength_nm, observed, variance = measurement_arrays(measurement)
    variance = np.maximum(variance, np.finfo(np.float64).tiny)
    state = np.asarray(state_vector.initial_state(), dtype=np.float64)
    prior = np.asarray(state_vector.prior_state(), dtype=np.float64)
    prior_covariance = np.asarray(state_vector.prior_covariance(), dtype=np.float64)
    prior_variance = np.maximum(np.diag(prior_covariance), np.finfo(np.float64).tiny)
    prior_inverse = 1.0 / prior_variance
    measurement_inverse = 1.0 / variance
    iterations: list[DoasIteration] = []
    posterior_covariance = prior_covariance.copy()
    converged = False
    start = time.perf_counter()

    for iteration_index in range(1, controls.max_iterations + 1):
        iteration_start = time.perf_counter()
        evaluation = approximate_for_state(
            case,
            state,
            state_vector,
            settings,
            wavelength_nm,
        )
        jacobian = finite_difference_jacobian(
            case,
            state,
            state_vector,
            settings,
            wavelength_nm,
        )
        residual = observed - evaluation.reflectance
        normal_matrix = jacobian.T @ (measurement_inverse[:, None] * jacobian)
        normal_matrix += np.diag(prior_inverse)
        right_hand_side = jacobian.T @ (measurement_inverse * residual)
        right_hand_side -= prior_inverse * (state - prior)
        update = solve_or_lstsq(normal_matrix, right_hand_side)
        normalized_update = update / np.sqrt(prior_variance)
        largest_update = float(np.max(np.abs(normalized_update)))

        if largest_update > controls.max_change_transformed_state:
            update *= controls.max_change_transformed_state / largest_update

        next_state = np.asarray(state_vector.clip_to_bounds(state + update), dtype=np.float64)
        actual_update = next_state - state
        state_vector_convergence = float(np.sum((actual_update**2) * prior_inverse))
        state_offset = state - prior
        chi2_reflectance = float(np.sum((residual**2) * measurement_inverse))
        chi2_state_vector = float(np.sum((state_offset**2) * prior_inverse))
        posterior_covariance = inverse_or_pseudo_inverse(normal_matrix)
        iterations.append(
            DoasIteration(
                index=iteration_index,
                state_before=state.copy(),
                state_after=next_state.copy(),
                chi2_reflectance=chi2_reflectance,
                chi2_state_vector=chi2_state_vector,
                state_vector_convergence=state_vector_convergence,
                elapsed_s=time.perf_counter() - iteration_start,
            )
        )
        state = next_state

        if state_vector_convergence < controls.state_vector_convergence_threshold:
            converged = True
            break

    final_approx = approximate_for_state(case, state, state_vector, settings, wavelength_nm)

    return DoasRetrieval(
        state=state,
        iterations=tuple(iterations),
        converged=converged,
        posterior_covariance=posterior_covariance,
        final_approx=final_approx,
        elapsed_s=time.perf_counter() - start,
    )


def run_reference_oe(
    *,
    case: Any,
    measurement: optimal_estimation.Measurement,
    state_vector: optimal_estimation.StateVector,
    controls: optimal_estimation.RetrievalControls,
) -> tuple[optimal_estimation.Result, float]:

    start = time.perf_counter()
    result = o2a_oe.disamar_oe(
        case=case,
        measurement=measurement,
        state_vector=state_vector,
        controls=controls,
    )

    return result, time.perf_counter() - start


def posterior_sigma_from_matrix(
    covariance: Sequence[Sequence[float]] | FloatArray,
    state_index: int,
) -> float:

    array = np.asarray(covariance, dtype=np.float64)

    return math.sqrt(max(float(array[state_index, state_index]), 0.0))


def exact_reflectance_for_state(
    case: Any,
    state: Sequence[float],
    state_vector: optimal_estimation.StateVector,
) -> FloatArray:

    state_case = o2a_oe.case_for_state(case, state, state_vector)

    return evaluate_spectrum(state_case).reflectance


def oe_records() -> tuple[pd.DataFrame, list[dict[str, Any]]]:

    base = build_o2a_case(o2a, jacobian_reference_layer=True)
    oe_baseline.configure_case(base)
    settings = DoasSettings(smooth_degree=SMOOTH_DEGREE, max_support_wavelengths=OE_SUPPORT_MAX)
    controls = optimal_estimation.RetrievalControls(
        max_iterations=OE_MAX_ITERATIONS,
        state_vector_convergence_threshold=1.0,
        max_change_transformed_state=1.0,
    )
    rows: list[dict[str, Any]] = []
    deltas: list[dict[str, Any]] = []

    for row in oe_cases.case_rows(count=OE_CASE_COUNT):
        index = int(row["case"])
        truth = oe_cases.scene_from_row(row)
        initial = oe_cases.initial_from_row(row)
        full_case = oe_setup.build_scene(
            base,
            index=index,
            id_prefix="o2a_doas_oe",
            scene=truth,
        )
        reference_case = uniform_wavelength_case(full_case, OE_WAVELENGTH_COUNT)
        measurement = measurement_from_o2a_baseline_noise(reference_case)
        profile = o2a_oe.pressure_altitude_profile_from_case(reference_case)
        state_vector = oe_setup.aerosol_two_state_vector(
            initial=initial,
            profile=profile,
            surface_pressure_hpa=truth["surface_pressure_hpa"],
        )
        reference_result, reference_s = run_reference_oe(
            case=reference_case,
            measurement=measurement,
            state_vector=state_vector,
            controls=controls,
        )
        doas_result = run_doas_like_oe(
            case=reference_case,
            measurement=measurement,
            state_vector=state_vector,
            controls=controls,
            settings=settings,
        )
        wavelength_nm, observed, variance = measurement_arrays(measurement)
        noise = np.sqrt(variance)
        reference_exact = exact_reflectance_for_state(
            reference_case,
            reference_result.state,
            state_vector,
        )
        doas_exact = exact_reflectance_for_state(
            reference_case,
            doas_result.state.tolist(),
            state_vector,
        )
        reference_residual = reference_exact - observed
        doas_final_residual = doas_exact - observed
        reference_residual_metrics = residual_metrics(wavelength_nm, reference_residual)
        doas_residual_metrics = residual_metrics(wavelength_nm, doas_final_residual)
        reference_state = np.asarray(reference_result.state, dtype=np.float64)
        doas_state = doas_result.state
        delta = doas_state - reference_state
        deltas.append(
            {
                "scene": index,
                "doas_minus_reference_aerosol_optical_depth": float(delta[0]),
                "doas_minus_reference_aerosol_mid_pressure_hpa": float(delta[1]),
                "doas_retrieval_speedup_s": reference_s - doas_result.elapsed_s,
                "doas_retrieval_speedup_ratio": reference_s / doas_result.elapsed_s,
                "reference_final_full_physics_rmse": reference_residual_metrics["rmse"],
                "doas_final_full_physics_rmse": doas_residual_metrics["rmse"],
                "doas_final_full_physics_rmse_over_reference": doas_residual_metrics["rmse"]
                / max(reference_residual_metrics["rmse"], np.finfo(np.float64).tiny),
            }
        )

        for mode, state, elapsed_s, converged, iterations, covariance in (
            (
                "full_physics",
                reference_state,
                reference_s,
                bool(reference_result.converged),
                int(reference_result.iterations),
                reference_result.posterior_covariance,
            ),
            (
                "doas_like",
                doas_state,
                doas_result.elapsed_s,
                doas_result.converged,
                doas_result.iteration_count,
                doas_result.posterior_covariance,
            ),
        ):
            rows.append(
                {
                    "analysis": "oe_state",
                    "scene": index,
                    "mode": mode,
                    "converged": bool(converged),
                    "iterations": int(iterations),
                    "retrieval_s": float(elapsed_s),
                    "truth_aerosol_optical_depth": truth["aerosol_optical_depth"],
                    "truth_aerosol_mid_pressure_hpa": truth["aerosol_mid_pressure_hpa"],
                    "initial_aerosol_optical_depth": initial["aerosol_optical_depth"],
                    "initial_aerosol_mid_pressure_hpa": initial["aerosol_mid_pressure_hpa"],
                    "retrieved_aerosol_optical_depth": float(state[0]),
                    "retrieved_aerosol_mid_pressure_hpa": float(state[1]),
                    "aerosol_optical_depth_error": (
                        float(state[0]) - truth["aerosol_optical_depth"]
                    ),
                    "aerosol_mid_pressure_error_hpa": (
                        float(state[1]) - truth["aerosol_mid_pressure_hpa"]
                    ),
                    "aerosol_optical_depth_sigma": posterior_sigma_from_matrix(covariance, 0),
                    "aerosol_mid_pressure_sigma_hpa": posterior_sigma_from_matrix(
                        covariance,
                        1,
                    ),
                    "solar_zenith_deg": truth["solar_zenith_deg"],
                    "viewing_zenith_deg": truth["viewing_zenith_deg"],
                    "relative_azimuth_deg": truth["relative_azimuth_deg"],
                    "surface_pressure_hpa": truth["surface_pressure_hpa"],
                    "surface_albedo": truth["surface_albedo"],
                }
            )

        for wavelength, ref_residual, doas_residual, noise_value in zip(
            wavelength_nm,
            reference_residual,
            doas_final_residual,
            noise,
            strict=True,
        ):
            rows.append(
                {
                    "analysis": "oe_spectrum_residual",
                    "scene": index,
                    "mode": "full_physics",
                    "wavelength_nm": float(wavelength),
                    "doas_minus_reference": math.nan,
                    "reference_final_minus_measurement": float(ref_residual),
                    "doas_final_minus_measurement": math.nan,
                    "residual_over_noise": float(ref_residual / noise_value),
                }
            )
            rows.append(
                {
                    "analysis": "oe_spectrum_residual",
                    "scene": index,
                    "mode": "doas_like",
                    "wavelength_nm": float(wavelength),
                    "doas_minus_reference": float(doas_residual - ref_residual),
                    "reference_final_minus_measurement": math.nan,
                    "doas_final_minus_measurement": float(doas_residual),
                    "residual_over_noise": float(doas_residual / noise_value),
                }
            )

        print(f"OE case {index}/{OE_CASE_COUNT} complete", flush=True)

    return pd.DataFrame.from_records(rows), deltas


def oe_state_rows(data: pd.DataFrame) -> pd.DataFrame:

    state_data = data[data["analysis"] == "oe_state"]
    records: list[dict[str, Any]] = []

    for _, row in state_data.iterrows():
        records.append(
            {
                "scene": int(row["scene"]),
                "mode": row["mode"],
                "parameter": "Aerosol optical depth",
                "truth": float(row["truth_aerosol_optical_depth"]),
                "retrieved": float(row["retrieved_aerosol_optical_depth"]),
            }
        )
        records.append(
            {
                "scene": int(row["scene"]),
                "mode": row["mode"],
                "parameter": "Aerosol mid pressure [hPa]",
                "truth": float(row["truth_aerosol_mid_pressure_hpa"]),
                "retrieved": float(row["retrieved_aerosol_mid_pressure_hpa"]),
            }
        )

    return pd.DataFrame.from_records(records)


def oe_delta_rows(deltas: list[dict[str, Any]]) -> pd.DataFrame:

    records: list[dict[str, Any]] = []

    for row in deltas:
        records.extend(
            [
                {
                    "scene": int(row["scene"]),
                    "quantity": "AOD delta",
                    "difference": float(row["doas_minus_reference_aerosol_optical_depth"]),
                },
                {
                    "scene": int(row["scene"]),
                    "quantity": "Mid-pressure delta [hPa]",
                    "difference": float(row["doas_minus_reference_aerosol_mid_pressure_hpa"]),
                },
                {
                    "scene": int(row["scene"]),
                    "quantity": "Retrieval speedup [s]",
                    "difference": float(row["doas_retrieval_speedup_s"]),
                },
                {
                    "scene": int(row["scene"]),
                    "quantity": "Final exact-spectrum RMSE ratio",
                    "difference": float(row["doas_final_full_physics_rmse_over_reference"]),
                },
            ]
        )

    return pd.DataFrame.from_records(records)


def oe_plot(data: pd.DataFrame, deltas: list[dict[str, Any]], output_path: Path) -> None:

    states = oe_state_rows(data)
    delta_frame = oe_delta_rows(deltas)
    residuals = data[data["analysis"] == "oe_spectrum_residual"]
    colors = alt.Scale(
        domain=["full_physics", "doas_like"],
        range=[PLOT.colors["blue"], PLOT.colors["orange"]],
    )
    scatter = (
        alt.Chart(states)
        .mark_point(filled=True, size=75, opacity=0.82)
        .encode(
            x=alt.X("truth:Q", title="Truth"),
            y=alt.Y("retrieved:Q", title="Retrieved"),
            color=alt.Color("mode:N", title=None, scale=colors),
            shape=alt.Shape("mode:N", title=None),
            facet=alt.Facet("parameter:N", columns=2, title=None),
            tooltip=[
                alt.Tooltip("scene:O", title="Scene"),
                alt.Tooltip("mode:N", title="Mode"),
                alt.Tooltip("truth:Q", title="Truth", format=".6g"),
                alt.Tooltip("retrieved:Q", title="Retrieved", format=".6g"),
            ],
        )
        .properties(width=330, height=260, title="Retrieved OE state")
        .resolve_scale(x="independent", y="independent")
    )
    delta_charts = []

    for quantity in delta_frame["quantity"].drop_duplicates():
        subset = delta_frame[delta_frame["quantity"] == quantity]
        bars = (
            alt.Chart(subset)
            .mark_bar(opacity=0.78, color=PLOT.colors["orange"])
            .encode(
                x=alt.X("scene:O", title="Scene"),
                y=alt.Y("difference:Q", title="DOAS-like - full physics"),
                tooltip=[
                    alt.Tooltip("scene:O", title="Scene"),
                    alt.Tooltip("difference:Q", title="Difference", format=".6g"),
                ],
            )
        )
        zero = (
            alt.Chart(pd.DataFrame({"zero": [0.0]}))
            .mark_rule(color=PLOT.colors["black"], strokeDash=[4, 3], strokeWidth=0.8)
            .encode(y="zero:Q")
        )
        delta_charts.append((bars + zero).properties(width=180, height=230, title=quantity))

    deltas_chart = alt.hconcat(*delta_charts, spacing=28).properties(
        title="Paired output differences"
    )
    residual_line = (
        alt.Chart(residuals)
        .mark_line()
        .encode(
            x=alt.X("wavelength_nm:Q", title="Wavelength [nm]", scale=alt.Scale(zero=False)),
            y=alt.Y("residual_over_noise:Q", title="Final residual / noise"),
            color=alt.Color("mode:N", title=None, scale=colors),
            row=alt.Row("scene:O", title="Scene"),
            tooltip=[
                alt.Tooltip("scene:O", title="Scene"),
                alt.Tooltip("mode:N", title="Mode"),
                alt.Tooltip("wavelength_nm:Q", title="Wavelength", format=".4f"),
                alt.Tooltip("residual_over_noise:Q", title="Residual/noise", format=".3e"),
            ],
        )
        .properties(width=850, height=95, title="Final-state exact-spectrum residuals")
    )
    chart = alt.vconcat(scatter, deltas_chart, residual_line, spacing=28).configure_axis(
        labelFontSize=11,
        titleFontSize=12,
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    chart.save(str(output_path), scale_factor=2.0)


def build_summary(
    spectrum_metrics: list[dict[str, Any]],
    oe_data: pd.DataFrame,
    oe_deltas: list[dict[str, Any]],
) -> dict[str, Any]:

    oe_states = oe_data[oe_data["analysis"] == "oe_state"]
    full = oe_states[oe_states["mode"] == "full_physics"]
    doas = oe_states[oe_states["mode"] == "doas_like"]
    delta_frame = pd.DataFrame.from_records(oe_deltas)

    return {
        "schema_version": 1,
        "canonical_command": CANONICAL_COMMAND,
        "method": {
            "smooth_degree": SMOOTH_DEGREE,
            "spectrum_support_max": SPECTRUM_SUPPORT_MAX,
            "oe_support_max": OE_SUPPORT_MAX,
            "oe_wavelength_count": OE_WAVELENGTH_COUNT,
            "oe_case_count": OE_CASE_COUNT,
            "oe_max_iterations": OE_MAX_ITERATIONS,
            "optical_depth_proxy": (
                "sum gas_absorption_optical_depth over positive-path atmospheric-budget rows; "
                "CIA is reported but not included in tau_diff"
            ),
            "amf": "geometric 1/mu0 + 1/mu",
            "runtime_note": (
                "runtime_proxy_s counts sparse full-physics support spectra plus algebraic "
                "reconstruction. diagnostic_total_s also includes the current Python budget "
                "query used to derive tau_diff; a production port would precompute or prepare "
                "this optical-depth input instead of treating the diagnostics query as the "
                "steady-state DOAS cost."
            ),
            "oe_note": (
                "The DOAS-like OE lane is a validation-side finite-difference solver. It is "
                "intended to expose state-output differences and residual structure before "
                "native Jacobian or production wiring work."
            ),
        },
        "outputs": {
            "spectrum_plot": stable_repo_path(SPECTRUM_PLOT_PATH),
            "spectrum_csv": stable_repo_path(SPECTRUM_DATA_PATH),
            "oe_plot": stable_repo_path(OE_PLOT_PATH),
            "oe_csv": stable_repo_path(OE_DATA_PATH),
            "summary_json": stable_repo_path(SUMMARY_PATH),
        },
        "spectrum": {
            "scene_count": len(spectrum_metrics),
            "max_abs_residual": stats(
                pd.Series([metric["max_abs_residual"] for metric in spectrum_metrics])
            ),
            "rmse": stats(pd.Series([metric["rmse"] for metric in spectrum_metrics])),
            "max_abs_residual_over_noise": stats(
                pd.Series([metric["max_abs_residual_over_noise"] for metric in spectrum_metrics])
            ),
            "runtime_proxy_speedup": stats(
                pd.Series([metric["doas_runtime_proxy_speedup"] for metric in spectrum_metrics])
            ),
            "diagnostic_total_speedup": stats(
                pd.Series([metric["doas_diagnostic_total_speedup"] for metric in spectrum_metrics])
            ),
            "support_wavelength_count": stats(
                pd.Series([metric["support_wavelength_count"] for metric in spectrum_metrics])
            ),
            "per_scene": spectrum_metrics,
        },
        "optimal_estimation": {
            "full_physics": {
                "rows": int(len(full)),
                "converged": int(full["converged"].sum()),
                "retrieval_s": stats(full["retrieval_s"]),
                "aerosol_optical_depth_abs_error": stats(full["aerosol_optical_depth_error"].abs()),
                "aerosol_mid_pressure_abs_error_hpa": stats(
                    full["aerosol_mid_pressure_error_hpa"].abs()
                ),
            },
            "doas_like": {
                "rows": int(len(doas)),
                "converged": int(doas["converged"].sum()),
                "retrieval_s": stats(doas["retrieval_s"]),
                "aerosol_optical_depth_abs_error": stats(doas["aerosol_optical_depth_error"].abs()),
                "aerosol_mid_pressure_abs_error_hpa": stats(
                    doas["aerosol_mid_pressure_error_hpa"].abs()
                ),
            },
            "doas_minus_full_physics": {
                "aerosol_optical_depth": stats(
                    delta_frame["doas_minus_reference_aerosol_optical_depth"]
                ),
                "aerosol_mid_pressure_hpa": stats(
                    delta_frame["doas_minus_reference_aerosol_mid_pressure_hpa"]
                ),
                "retrieval_speedup_s": stats(delta_frame["doas_retrieval_speedup_s"]),
                "retrieval_speedup_ratio": stats(delta_frame["doas_retrieval_speedup_ratio"]),
                "final_exact_spectrum_rmse_ratio": stats(
                    delta_frame["doas_final_full_physics_rmse_over_reference"]
                ),
            },
            "per_scene_deltas": oe_deltas,
        },
    }


def validate_finite_summary(summary: dict[str, Any]) -> None:

    failures = []
    spectrum = summary["spectrum"]
    oe_summary = summary["optimal_estimation"]

    if int(spectrum["scene_count"]) == 0:
        failures.append("spectrum scene_count is zero")

    if int(oe_summary["full_physics"]["rows"]) != OE_CASE_COUNT:
        failures.append("full-physics OE row count does not match OE_CASE_COUNT")

    if int(oe_summary["doas_like"]["rows"]) != OE_CASE_COUNT:
        failures.append("DOAS-like OE row count does not match OE_CASE_COUNT")

    if int(oe_summary["full_physics"]["converged"]) != OE_CASE_COUNT:
        failures.append("full-physics OE did not converge for every validation case")

    if failures:
        raise SystemExit("DOAS baseline validation failed: " + "; ".join(failures))


def main() -> None:

    spectrum_data, spectrum_metric_rows = spectrum_records()
    oe_data, oe_deltas = oe_records()
    OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)
    spectrum_data.to_csv(SPECTRUM_DATA_PATH, index=False)
    oe_data.to_csv(OE_DATA_PATH, index=False)
    spectrum_plot(spectrum_data, spectrum_metric_rows, SPECTRUM_PLOT_PATH)
    oe_plot(oe_data, oe_deltas, OE_PLOT_PATH)
    summary = build_summary(spectrum_metric_rows, oe_data, oe_deltas)
    validate_finite_summary(summary)
    write_json(SUMMARY_PATH, summary)
    print(f"wrote {stable_repo_path(SUMMARY_PATH)}", flush=True)


if __name__ == "__main__":
    main()
