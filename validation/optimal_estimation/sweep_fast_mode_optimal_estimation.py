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

"""Run retained O2 A fast-mode optimal-estimation sweep outputs."""

import copy
import math
import sys
import time
from collections.abc import Sequence
from pathlib import Path
from typing import Any

import altair as alt
import numpy as np
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe  # noqa: E402
from zdisamar.plot.properties import PLOT  # noqa: E402
from zdisamar.wavelength_bands import o2a  # noqa: E402

from validation.common.paths import stable_repo_path, write_json  # noqa: E402
from validation.o2a import baseline as oe_baseline  # noqa: E402
from validation.o2a.case import build_o2a_case  # noqa: E402
from validation.o2a.measurement_noise import (  # noqa: E402
    measurement_from_o2a_baseline_noise,
)
from validation.optimal_estimation import reference_cases as oe_cases  # noqa: E402
from validation.optimal_estimation import setup as oe_setup  # noqa: E402

OUTPUTS_DIR = REPO_ROOT / "validation" / "outputs" / "optimal_estimation"
PLOT_PATH = OUTPUTS_DIR / "zdisamar_o2a_fast_mode_sweep_comparison.png"
RETRIEVED_FAST_SCATTER_PATH = OUTPUTS_DIR / "paired_oe_retrieved_fast_scatter.png"
PAIRED_LATENCY_PATH = OUTPUTS_DIR / "paired_oe_latency.png"
PAIRED_MANIFEST_PATH = OUTPUTS_DIR / "paired_oe_plot_manifest.json"
DATA_PATH = OUTPUTS_DIR / "zdisamar_o2a_fast_mode_sweep_comparison_runs.csv"
SUMMARY_PATH = OUTPUTS_DIR / "zdisamar_o2a_fast_mode_sweep_comparison_summary.json"

CANONICAL_COMMAND = "uv run validation/optimal_estimation/sweep_fast_mode_optimal_estimation.py"
RUN_COUNT = oe_cases.run_count()
FAST_REFERENCE_MAX_ABS_AOD_DELTA = 1.0e-2
FAST_REFERENCE_MAX_ABS_PRESSURE_DELTA_HPA = 10.0
FAST_ACCURATE_REFERENCE_MAX_ABS_AOD_DELTA = 5.0e-4
FAST_ACCURATE_REFERENCE_MAX_ABS_PRESSURE_DELTA_HPA = 0.5

MODE_LABELS = {
    "reference": "zdisamar reference",
    "fast": "zdisamar fast",
    "fast_accurate": "zdisamar fast-accurate",
}
MODE_COLORS = {
    "reference": PLOT.colors["blue"],
    "fast": PLOT.colors["orange"],
    "fast_accurate": "#2ca02c",
}
MODE_MARKERS = {
    "reference": "o",
    "fast": "x",
    "fast_accurate": "diamond",
}
LATENCY_MODE_LABELS = {
    "disamar_fortran": "DISAMAR Fortran",
    "zdisamar": "zdisamar",
    "zdisamar_fast": "zdisamar-fast",
    "zdisamar_fast_accurate": "zdisamar-fast-accurate",
}
LATENCY_MODE_COLORS = {
    "disamar_fortran": PLOT.colors["blue"],
    "zdisamar": PLOT.colors["orange"],
    "zdisamar_fast": PLOT.colors["red"],
    "zdisamar_fast_accurate": "#2ca02c",
}


def with_fast_thresholds(case: Any) -> Any:

    return copy.deepcopy(case).with_fast_mode()


def run_retrieval(case: Any, measurement, state_vector, *, mode: str) -> tuple[Any, float]:

    start = time.perf_counter()
    controls = oe_setup.retrieval_controls()

    if mode == "fast_accurate":
        result = o2a_oe.disamar_oe_fast(
            case=case,
            measurement=measurement,
            state_vector=state_vector,
            controls=controls,
        )
    else:
        result = o2a_oe.disamar_oe(
            case=case,
            measurement=measurement,
            state_vector=state_vector,
            controls=controls,
        )

    return result, time.perf_counter() - start


def posterior_sigma(result: Any, state_name: str) -> float:

    index = result.state_names.index(state_name)
    variance = float(result.posterior_covariance[index][index])

    return math.sqrt(max(variance, 0.0))


def build_rows() -> list[dict[str, Any]]:

    base = build_o2a_case(o2a, jacobian_reference_layer=True)
    oe_baseline.configure_case(base)
    rows: list[dict[str, Any]] = []

    for row in oe_cases.case_rows(count=RUN_COUNT):
        index = int(row["case"])
        truth = oe_cases.scene_from_row(row)
        reference_case = oe_setup.build_scene(
            base,
            index=index,
            id_prefix="o2a_fast_mode_oe",
            scene=truth,
        )
        initial = oe_cases.initial_from_row(row)

        measurement = measurement_from_o2a_baseline_noise(reference_case)
        profile = o2a_oe.pressure_altitude_profile_from_case(reference_case)

        state_vector = oe_setup.aerosol_two_state_vector(
            initial=initial,
            profile=profile,
            surface_pressure_hpa=truth["surface_pressure_hpa"],
        )

        for mode, retrieval_case in (
            ("reference", reference_case),
            ("fast", with_fast_thresholds(reference_case)),
            ("fast_accurate", reference_case),
        ):
            result, retrieval_s = run_retrieval(
                retrieval_case,
                measurement,
                state_vector,
                mode=mode,
            )
            fast_settings_case = (
                with_fast_thresholds(reference_case) if mode == "fast_accurate" else retrieval_case
            )
            thresholds = fast_settings_case.radiative_transfer.performance_thresholds
            adaptive_grid = fast_settings_case.instrument_response.adaptive_reference_grid
            retrieved_aod = result.value("aerosol_optical_depth")
            retrieved_mid_pressure = result.value("aerosol_layer_mid_pressure_hpa")
            correction = result.fast_correction
            rows.append(
                {
                    "scene": index,
                    "mode": mode,
                    "mode_label": MODE_LABELS[mode],
                    "converged": bool(result.converged),
                    "iterations": int(result.iterations),
                    "fast_stage_iterations": (
                        math.nan if correction is None else int(correction.fast_iterations)
                    ),
                    "fast_stage_converged": (
                        math.nan if correction is None else bool(correction.fast_converged)
                    ),
                    "full_correction_converged": (
                        math.nan
                        if correction is None
                        else bool(correction.full_correction_converged)
                    ),
                    "full_correction_state_vector_convergence": (
                        math.nan
                        if correction is None
                        else float(correction.full_correction_state_vector_convergence)
                    ),
                    "retrieval_s": retrieval_s,
                    "truth_aerosol_optical_depth": truth["aerosol_optical_depth"],
                    "truth_aerosol_mid_pressure_hpa": truth["aerosol_mid_pressure_hpa"],
                    "initial_aerosol_optical_depth": initial["aerosol_optical_depth"],
                    "initial_aerosol_mid_pressure_hpa": initial["aerosol_mid_pressure_hpa"],
                    "retrieved_aerosol_optical_depth": retrieved_aod,
                    "retrieved_aerosol_mid_pressure_hpa": retrieved_mid_pressure,
                    "aerosol_optical_depth_error": (retrieved_aod - truth["aerosol_optical_depth"]),
                    "aerosol_mid_pressure_error_hpa": (
                        retrieved_mid_pressure - truth["aerosol_mid_pressure_hpa"]
                    ),
                    "aerosol_optical_depth_sigma": posterior_sigma(
                        result,
                        "aerosol_optical_depth",
                    ),
                    "aerosol_mid_pressure_sigma_hpa": posterior_sigma(
                        result,
                        "aerosol_layer_mid_pressure_hpa",
                    ),
                    "fourier_order_cap": thresholds.fourier_order_cap,
                    "aerosol_tangent_order_cap": thresholds.aerosol_tangent_order_cap,
                    "fourier_tail_reflectance_epsilon": (
                        thresholds.fourier_tail_reflectance_epsilon
                    ),
                    "threshold_doubl": thresholds.threshold_doubl,
                    "qzero_rd_product_suppression": thresholds.qzero_rd_product_suppression,
                    "qzero_tu_product_suppression": thresholds.qzero_tu_product_suppression,
                    "qzero_td_product_suppression": thresholds.qzero_td_product_suppression,
                    "adaptive_grid_points_per_fwhm": adaptive_grid["points_per_fwhm"],
                    "adaptive_grid_strong_line_min_divisions": adaptive_grid[
                        "strong_line_min_divisions"
                    ],
                    "adaptive_grid_strong_line_max_divisions": adaptive_grid[
                        "strong_line_max_divisions"
                    ],
                    "solar_zenith_deg": truth["solar_zenith_deg"],
                    "viewing_zenith_deg": truth["viewing_zenith_deg"],
                    "relative_azimuth_deg": truth["relative_azimuth_deg"],
                    "surface_pressure_hpa": truth["surface_pressure_hpa"],
                    "surface_albedo": truth["surface_albedo"],
                }
            )

        print(f"{index:03d}/{RUN_COUNT} reference+fast+fast-accurate complete", flush=True)

    return rows


def paired_delta_frame(data: pd.DataFrame, modes: Sequence[str] | None = None) -> pd.DataFrame:

    reference = data[data["mode"] == "reference"].set_index("scene")
    comparison_modes = (
        tuple(modes)
        if modes is not None
        else tuple(mode for mode in MODE_LABELS if mode != "reference")
    )
    rows = []

    for mode in comparison_modes:
        comparison = data[data["mode"] == mode].set_index("scene")

        for scene in sorted(reference.index):
            ref = reference.loc[scene]
            current = comparison.loc[scene]
            rows.append(
                {
                    "scene": int(scene),
                    "mode": mode,
                    "mode_label": MODE_LABELS[mode],
                    "aerosol_optical_depth_delta": (
                        float(current["retrieved_aerosol_optical_depth"])
                        - float(ref["retrieved_aerosol_optical_depth"])
                    ),
                    "aerosol_optical_depth_combined_sigma": math.sqrt(
                        float(ref["aerosol_optical_depth_sigma"]) ** 2
                        + float(current["aerosol_optical_depth_sigma"]) ** 2
                    ),
                    "aerosol_mid_pressure_delta_hpa": (
                        float(current["retrieved_aerosol_mid_pressure_hpa"])
                        - float(ref["retrieved_aerosol_mid_pressure_hpa"])
                    ),
                    "aerosol_mid_pressure_combined_sigma_hpa": math.sqrt(
                        float(ref["aerosol_mid_pressure_sigma_hpa"]) ** 2
                        + float(current["aerosol_mid_pressure_sigma_hpa"]) ** 2
                    ),
                    "retrieval_speedup_s": float(ref["retrieval_s"])
                    - float(current["retrieval_s"]),
                }
            )

    return pd.DataFrame.from_records(rows)


def paired_fast_accurate_fast_frame(data: pd.DataFrame) -> pd.DataFrame:

    fast = data[data["mode"] == "fast"].set_index("scene")
    fast_accurate = data[data["mode"] == "fast_accurate"].set_index("scene")
    rows = []

    for scene in sorted(fast.index):
        fast_row = fast.loc[scene]
        accurate_row = fast_accurate.loc[scene]
        rows.append(
            {
                "scene": int(scene),
                "retrieval_extra_s": float(accurate_row["retrieval_s"])
                - float(fast_row["retrieval_s"]),
                "aerosol_optical_depth_delta": (
                    float(accurate_row["retrieved_aerosol_optical_depth"])
                    - float(fast_row["retrieved_aerosol_optical_depth"])
                ),
                "aerosol_mid_pressure_delta_hpa": (
                    float(accurate_row["retrieved_aerosol_mid_pressure_hpa"])
                    - float(fast_row["retrieved_aerosol_mid_pressure_hpa"])
                ),
                "aerosol_optical_depth_abs_error_improvement": abs(
                    float(fast_row["aerosol_optical_depth_error"])
                )
                - abs(float(accurate_row["aerosol_optical_depth_error"])),
                "aerosol_mid_pressure_abs_error_improvement_hpa": abs(
                    float(fast_row["aerosol_mid_pressure_error_hpa"])
                )
                - abs(float(accurate_row["aerosol_mid_pressure_error_hpa"])),
            }
        )

    return pd.DataFrame.from_records(rows)


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


def stats_from_values(values: list[float]) -> dict[str, float]:

    if not values:
        return {
            "min": math.nan,
            "median": math.nan,
            "mean": math.nan,
            "max": math.nan,
            "max_abs": math.nan,
        }

    series = pd.Series(values, dtype=np.float64)

    return stats(series)


def fast_mode_overrides() -> dict[str, dict[str, float | int | bool | None]]:

    fast = o2a.RadiativeTransferPerformanceThresholds.fast()
    adaptive_grid: dict[str, float | int | bool | None] = dict(
        o2a.O2ACase.FAST_ADAPTIVE_REFERENCE_GRID
    )

    return {
        "radiative_transfer": {
            "fourier_order_cap": fast.fourier_order_cap,
            "aerosol_tangent_order_cap": fast.aerosol_tangent_order_cap,
            "fourier_tail_reflectance_epsilon": fast.fourier_tail_reflectance_epsilon,
            "threshold_doubl": fast.threshold_doubl,
            "qzero_rd_product_suppression": fast.qzero_rd_product_suppression,
            "qzero_tu_product_suppression": fast.qzero_tu_product_suppression,
            "qzero_td_product_suppression": fast.qzero_td_product_suppression,
        },
        "adaptive_reference_grid": adaptive_grid,
    }


def build_summary(data: pd.DataFrame) -> dict[str, Any]:

    fast_delta = paired_delta_frame(data, ("fast",))
    fast_accurate_delta = paired_delta_frame(data, ("fast_accurate",))
    fast_accurate_fast_delta = paired_fast_accurate_fast_frame(data)
    by_mode = {}

    for mode in MODE_LABELS:
        subset = data[data["mode"] == mode]
        payload = {
            "rows": int(len(subset)),
            "converged": int(subset["converged"].sum()),
            "retrieval_s": stats(subset["retrieval_s"]),
            "aerosol_optical_depth_abs_error": stats(subset["aerosol_optical_depth_error"].abs()),
            "aerosol_mid_pressure_abs_error_hpa": stats(
                subset["aerosol_mid_pressure_error_hpa"].abs()
            ),
        }

        if mode == "fast_accurate":
            payload["fast_stage_converged"] = int(subset["fast_stage_converged"].sum())
            payload["full_correction_converged"] = int(subset["full_correction_converged"].sum())
            payload["full_correction_state_vector_convergence"] = stats(
                subset["full_correction_state_vector_convergence"]
            )

        by_mode[mode] = payload

    reference_median_s = float(by_mode["reference"]["retrieval_s"]["median"])
    fast_median_s = float(by_mode["fast"]["retrieval_s"]["median"])
    fast_accurate_median_s = float(by_mode["fast_accurate"]["retrieval_s"]["median"])
    fast_reference_gap_s = reference_median_s - fast_median_s
    latency_position = (
        math.nan
        if fast_reference_gap_s <= 0.0
        else (fast_accurate_median_s - fast_median_s) / fast_reference_gap_s
    )

    return {
        "schema_version": 1,
        "canonical_command": CANONICAL_COMMAND,
        "run_count": RUN_COUNT,
        "reference_cases": oe_cases.manifest_path(),
        "scene_sample_count": oe_cases.scene_sample_count(),
        "seed": oe_cases.seed(),
        "fast_mode": {
            "method": "O2AInput.with_fast_mode()",
            "overrides": fast_mode_overrides(),
            "fast_accurate_correction_window_nm": list(o2a_oe.FULL_CORRECTION_WINDOW_NM),
            "note": (
                "Reference, fast, and fast-accurate rows use the same deterministic "
                "zdisamar O2 A optimal-estimation sweep cases, measurement vectors, "
                "priors, and initial states. Fast rows apply O2AInput.with_fast_mode(). "
                "Fast-accurate rows solve the fast-mode OE problem to convergence, then "
                "apply one full-physics OE correction over the retained correction window."
            ),
        },
        "outputs": {
            "plot": stable_repo_path(PLOT_PATH),
            "paired_style_retrieved_scatter": stable_repo_path(RETRIEVED_FAST_SCATTER_PATH),
            "paired_latency": stable_repo_path(PAIRED_LATENCY_PATH),
            "runs_csv": stable_repo_path(DATA_PATH),
            "summary_json": stable_repo_path(SUMMARY_PATH),
        },
        "by_mode": by_mode,
        "fast_minus_reference": {
            "aerosol_optical_depth_delta": stats(fast_delta["aerosol_optical_depth_delta"]),
            "aerosol_mid_pressure_delta_hpa": stats(fast_delta["aerosol_mid_pressure_delta_hpa"]),
            "retrieval_speedup_s": stats(fast_delta["retrieval_speedup_s"]),
        },
        "fast_accurate_minus_reference": {
            "aerosol_optical_depth_delta": stats(
                fast_accurate_delta["aerosol_optical_depth_delta"]
            ),
            "aerosol_mid_pressure_delta_hpa": stats(
                fast_accurate_delta["aerosol_mid_pressure_delta_hpa"]
            ),
            "retrieval_speedup_s": stats(fast_accurate_delta["retrieval_speedup_s"]),
        },
        "fast_accurate_minus_fast": {
            "retrieval_extra_s": stats(fast_accurate_fast_delta["retrieval_extra_s"]),
            "aerosol_optical_depth_delta": stats(
                fast_accurate_fast_delta["aerosol_optical_depth_delta"]
            ),
            "aerosol_mid_pressure_delta_hpa": stats(
                fast_accurate_fast_delta["aerosol_mid_pressure_delta_hpa"]
            ),
            "aerosol_optical_depth_abs_error_improvement": stats(
                fast_accurate_fast_delta["aerosol_optical_depth_abs_error_improvement"]
            ),
            "aerosol_mid_pressure_abs_error_improvement_hpa": stats(
                fast_accurate_fast_delta["aerosol_mid_pressure_abs_error_improvement_hpa"]
            ),
        },
        "latency_position": {
            "reference_median_s": reference_median_s,
            "fast_median_s": fast_median_s,
            "fast_accurate_median_s": fast_accurate_median_s,
            "fast_reference_gap_s": fast_reference_gap_s,
            "fast_accurate_position_between_fast_and_reference": latency_position,
            "note": (
                "0.0 equals fast median latency and 1.0 equals full reference median latency; "
                "values below 0.5 are closer to fast mode than full reference mode."
            ),
        },
    }


def validate_summary(summary: dict[str, Any]) -> None:

    failures = []

    for mode in MODE_LABELS:
        payload = summary["by_mode"][mode]

        if int(payload["rows"]) != RUN_COUNT:
            failures.append(f"{mode} rows={payload['rows']} expected={RUN_COUNT}")

        if int(payload["converged"]) != RUN_COUNT:
            failures.append(f"{mode} converged={payload['converged']} expected={RUN_COUNT}")

    delta = summary["fast_minus_reference"]
    aod_delta = float(delta["aerosol_optical_depth_delta"]["max_abs"])

    if aod_delta > FAST_REFERENCE_MAX_ABS_AOD_DELTA:
        failures.append(
            f"fast-reference AOD max_abs_delta={aod_delta:.3e} "
            f"exceeds {FAST_REFERENCE_MAX_ABS_AOD_DELTA:.3e}"
        )

    pressure_delta = float(delta["aerosol_mid_pressure_delta_hpa"]["max_abs"])

    if pressure_delta > FAST_REFERENCE_MAX_ABS_PRESSURE_DELTA_HPA:
        failures.append(
            f"fast-reference pressure max_abs_delta={pressure_delta:.3e}hPa "
            f"exceeds {FAST_REFERENCE_MAX_ABS_PRESSURE_DELTA_HPA:.3e}hPa"
        )

    fast_accurate_delta = summary["fast_accurate_minus_reference"]
    fast_accurate_aod_delta = float(fast_accurate_delta["aerosol_optical_depth_delta"]["max_abs"])

    if fast_accurate_aod_delta > FAST_ACCURATE_REFERENCE_MAX_ABS_AOD_DELTA:
        failures.append(
            f"fast-accurate-reference AOD max_abs_delta={fast_accurate_aod_delta:.3e} "
            f"exceeds {FAST_ACCURATE_REFERENCE_MAX_ABS_AOD_DELTA:.3e}"
        )

    fast_accurate_pressure_delta = float(
        fast_accurate_delta["aerosol_mid_pressure_delta_hpa"]["max_abs"]
    )

    if fast_accurate_pressure_delta > FAST_ACCURATE_REFERENCE_MAX_ABS_PRESSURE_DELTA_HPA:
        failures.append(
            "fast-accurate-reference pressure "
            f"max_abs_delta={fast_accurate_pressure_delta:.3e}hPa exceeds "
            f"{FAST_ACCURATE_REFERENCE_MAX_ABS_PRESSURE_DELTA_HPA:.3e}hPa"
        )

    fast = summary["by_mode"]["fast"]
    fast_accurate = summary["by_mode"]["fast_accurate"]
    reference = summary["by_mode"]["reference"]

    if int(fast_accurate["fast_stage_converged"]) != RUN_COUNT:
        failures.append(
            "fast-accurate fast-stage converged="
            f"{fast_accurate['fast_stage_converged']} expected={RUN_COUNT}"
        )

    if float(fast_accurate["aerosol_optical_depth_abs_error"]["max_abs"]) >= float(
        fast["aerosol_optical_depth_abs_error"]["max_abs"]
    ):
        failures.append("fast-accurate AOD max_abs_error did not improve over fast mode")

    if float(fast_accurate["aerosol_mid_pressure_abs_error_hpa"]["max_abs"]) >= float(
        fast["aerosol_mid_pressure_abs_error_hpa"]["max_abs"]
    ):
        failures.append("fast-accurate pressure max_abs_error did not improve over fast mode")

    if float(fast_accurate["retrieval_s"]["median"]) >= float(reference["retrieval_s"]["median"]):
        failures.append("fast-accurate median retrieval time did not beat reference mode")

    latency_position = summary["latency_position"]
    fast_reference_gap_s = float(latency_position["fast_reference_gap_s"])

    if fast_reference_gap_s <= 0.0:
        failures.append("fast median retrieval time did not beat reference mode")

    position = float(latency_position["fast_accurate_position_between_fast_and_reference"])

    if not math.isfinite(position) or position >= 0.5:
        failures.append(
            "fast-accurate median retrieval time was not closer to fast mode than reference mode "
            f"(position={position:.3f})"
        )

    if failures:
        details = "; ".join(failures)
        raise SystemExit(f"fast-mode optimal-estimation validation failed: {details}")


def fast_retrieved_rows(data: pd.DataFrame) -> pd.DataFrame:

    records = []

    for _, row in data.iterrows():
        records.append(
            {
                "scene": int(row["scene"]),
                "mode": row["mode"],
                "mode_label": row["mode_label"],
                "parameter": "Aerosol mid pressure",
                "truth": float(row["truth_aerosol_mid_pressure_hpa"]),
                "retrieved": float(row["retrieved_aerosol_mid_pressure_hpa"]),
            }
        )
        records.append(
            {
                "scene": int(row["scene"]),
                "mode": row["mode"],
                "mode_label": row["mode_label"],
                "parameter": "Aerosol optical depth",
                "truth": float(row["truth_aerosol_optical_depth"]),
                "retrieved": float(row["retrieved_aerosol_optical_depth"]),
            }
        )

    return pd.DataFrame.from_records(records)


def fast_difference_rows(data: pd.DataFrame) -> pd.DataFrame:

    delta = paired_delta_frame(data)
    records = []

    for _, row in delta.iterrows():
        records.extend(
            [
                {
                    "scene": int(row["scene"]),
                    "mode": row["mode"],
                    "mode_label": row["mode_label"],
                    "parameter": "Aerosol optical depth",
                    "difference": float(row["aerosol_optical_depth_delta"]),
                },
                {
                    "scene": int(row["scene"]),
                    "mode": row["mode"],
                    "mode_label": row["mode_label"],
                    "parameter": "Aerosol mid pressure [hPa]",
                    "difference": float(row["aerosol_mid_pressure_delta_hpa"]),
                },
            ]
        )

    return pd.DataFrame.from_records(records)


def signed(value: float, precision: str) -> str:

    if math.isnan(value):
        return "nan"

    return f"{value:+{precision}}"


def difference_subtitle(values: pd.Series, precision: str, unit: str = "") -> str:

    stats_payload = stats(values)
    suffix = f" {unit}" if unit else ""

    return (
        f"median {signed(stats_payload['median'], precision)}{suffix}; "
        f"range {signed(stats_payload['min'], precision)} "
        f"to {signed(stats_payload['max'], precision)}{suffix}"
    )


def _mode_color() -> alt.Color:

    return alt.Color(
        "mode_label:N",
        title=None,
        scale=alt.Scale(
            domain=list(MODE_LABELS.values()),
            range=[MODE_COLORS[mode] for mode in MODE_LABELS],
        ),
    )


def _identity_line(lower: float, upper: float):

    return (
        alt.Chart(pd.DataFrame({"x": [lower, upper], "y": [lower, upper]}))
        .mark_line(color=PLOT.colors["black"], strokeDash=[4, 3], strokeWidth=0.9)
        .encode(x="x:Q", y="y:Q")
    )


def _extent(values: list[float]) -> tuple[float, float]:

    lower = float(min(values))
    upper = float(max(values))
    padding = float(max((upper - lower) * 0.05, np.finfo(np.float64).eps))

    return lower - padding, upper + padding


def scatter_chart(data: pd.DataFrame, *, parameter: str, title: str):

    subset = data[data["parameter"] == parameter]
    lower, upper = _extent(
        subset["truth"].astype(float).to_list() + subset["retrieved"].astype(float).to_list()
    )
    points = (
        alt.Chart(subset)
        .mark_point(filled=True, size=48, opacity=0.78)
        .encode(
            x=alt.X("truth:Q", title="True value", scale=alt.Scale(domain=[lower, upper])),
            y=alt.Y(
                "retrieved:Q",
                title="Retrieved value",
                scale=alt.Scale(domain=[lower, upper]),
            ),
            color=_mode_color(),
            shape=alt.Shape("mode_label:N", title=None),
            tooltip=[
                alt.Tooltip("scene:O", title="Scene"),
                alt.Tooltip("mode_label:N", title="Mode"),
                alt.Tooltip("truth:Q", title="Truth", format=".6g"),
                alt.Tooltip("retrieved:Q", title="Retrieved", format=".6g"),
            ],
        )
    )

    return alt.layer(_identity_line(lower, upper), points).properties(
        width=530, height=330, title=title
    )


def histogram_chart(
    data: pd.DataFrame,
    *,
    parameter: str,
    title: str,
    subtitle: str,
    xlabel: str,
):

    subset = data[data["parameter"] == parameter]
    histogram = (
        alt.Chart(subset)
        .mark_bar(opacity=0.62)
        .encode(
            x=alt.X("difference:Q", bin=alt.Bin(maxbins=45), title=xlabel),
            y=alt.Y("count():Q", title="Count"),
            color=_mode_color(),
            tooltip=[
                alt.Tooltip("count():Q", title="Count"),
                alt.Tooltip("mode_label:N", title="Mode"),
                alt.Tooltip("difference:Q", title="Difference", format=".6g"),
            ],
        )
    )
    zero = (
        alt.Chart(pd.DataFrame({"zero": [0.0]}))
        .mark_rule(color=PLOT.colors["black"], strokeDash=[4, 3], strokeWidth=1)
        .encode(x="zero:Q")
    )

    return alt.layer(histogram, zero).properties(
        width=530,
        height=300,
        title={"text": title, "subtitle": subtitle},
    )


def create_paired_style_retrieved_fast_scatter(
    data: pd.DataFrame,
    output_path: Path,
) -> None:

    retrieved = fast_retrieved_rows(data)
    differences = fast_difference_rows(data)
    top = alt.hconcat(
        scatter_chart(
            retrieved,
            parameter="Aerosol mid pressure",
            title="Aerosol mid pressure",
        ),
        scatter_chart(
            retrieved,
            parameter="Aerosol optical depth",
            title="Aerosol optical depth",
        ),
        spacing=32,
    )
    aod_diff = differences[differences["parameter"] == "Aerosol optical depth"]["difference"]
    pressure_diff = differences[differences["parameter"] == "Aerosol mid pressure [hPa]"][
        "difference"
    ]
    bottom = alt.hconcat(
        histogram_chart(
            differences,
            parameter="Aerosol optical depth",
            title="Aerosol optical depth",
            subtitle=difference_subtitle(aod_diff, ".3e"),
            xlabel="mode - zdisamar reference",
        ),
        histogram_chart(
            differences,
            parameter="Aerosol mid pressure [hPa]",
            title="Aerosol mid pressure [hPa]",
            subtitle=difference_subtitle(pressure_diff, ".4f", "hPa"),
            xlabel="mode - zdisamar reference [hPa]",
        ),
        spacing=32,
    )
    chart = alt.vconcat(top, bottom, spacing=42).properties(
        title={
            "text": "Retrieved State Versus Truth",
            "subtitle": (
                "Top: zdisamar reference, fast, and fast-accurate retrievals against "
                "known synthetic truth. Bottom: paired retrieval difference per scene "
                "relative to zdisamar reference."
            ),
        }
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    chart.save(output_path, scale_factor=4.0)


def paired_manifest_latency_stats() -> dict[str, dict[str, float]]:

    if not PAIRED_MANIFEST_PATH.exists():
        return {}

    import json

    payload = json.loads(PAIRED_MANIFEST_PATH.read_text())
    by_model = payload.get("by_model", {})

    return {
        "disamar_fortran": by_model.get("disamar_fortran", {}).get("retrieval_s", {}),
        "zdisamar": by_model.get("zdisamar", {}).get("retrieval_s", {}),
    }


def create_latency_plot_with_fast(data: pd.DataFrame, output_path: Path) -> None:

    stats_by_model = paired_manifest_latency_stats()
    stats_by_model["zdisamar_fast"] = stats_from_values(
        data[data["mode"] == "fast"]["retrieval_s"].to_list()
    )
    stats_by_model["zdisamar_fast_accurate"] = stats_from_values(
        data[data["mode"] == "fast_accurate"]["retrieval_s"].to_list()
    )
    rows = []

    for model in ("disamar_fortran", "zdisamar", "zdisamar_fast", "zdisamar_fast_accurate"):
        payload = stats_by_model.get(model, {})

        if not payload:
            continue

        rows.append(
            {
                "model": model,
                "model_label": LATENCY_MODE_LABELS[model],
                "minimum": float(payload["min"]),
                "median": float(payload["median"]),
                "mean": float(payload["mean"]),
                "maximum": float(payload["max"]),
            }
        )

    frame = pd.DataFrame.from_records(rows)
    color = alt.Color(
        "model_label:N",
        title=None,
        scale=alt.Scale(
            domain=[LATENCY_MODE_LABELS[key] for key in LATENCY_MODE_LABELS],
            range=[LATENCY_MODE_COLORS[key] for key in LATENCY_MODE_LABELS],
        ),
    )
    span = (
        alt.Chart(frame)
        .mark_rule(size=8, opacity=0.26)
        .encode(
            x=alt.X("model_label:N", title=None),
            y=alt.Y(
                "minimum:Q",
                title="Retrieval wall time [s]",
                scale=alt.Scale(type="log"),
            ),
            y2="maximum:Q",
            color=color,
        )
    )
    median = (
        alt.Chart(frame)
        .mark_tick(thickness=2.6, size=46)
        .encode(x="model_label:N", y="median:Q", color=color)
    )
    mean = (
        alt.Chart(frame)
        .mark_point(filled=True, size=44)
        .encode(
            x="model_label:N",
            y="mean:Q",
            color=color,
            tooltip=[
                alt.Tooltip("model_label:N", title="Model"),
                alt.Tooltip("minimum:Q", title="Min", format=".4g"),
                alt.Tooltip("median:Q", title="Median", format=".4g"),
                alt.Tooltip("mean:Q", title="Mean", format=".4g"),
                alt.Tooltip("maximum:Q", title="Max", format=".4g"),
            ],
        )
    )
    chart = alt.layer(span, median, mean).properties(
        width=620,
        height=410,
        title={
            "text": "Optimal Estimation Retrieval Latency",
            "subtitle": "Line spans min-max; horizontal tick is median; dot is mean.",
        },
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    chart.save(output_path, scale_factor=4.0)


def mode_subset(data: pd.DataFrame, mode: str) -> pd.DataFrame:

    return data[data["mode"] == mode].sort_values("scene")


def truth_chart(
    data: pd.DataFrame,
    *,
    truth_column: str,
    retrieved_column: str,
    sigma_column: str,
    title: str,
    xlabel: str,
    ylabel: str,
):

    frame = data.copy()
    frame["lower"] = frame[retrieved_column] - frame[sigma_column]
    frame["upper"] = frame[retrieved_column] + frame[sigma_column]
    all_x = data[truth_column].to_numpy(dtype=np.float64)
    all_y = data[retrieved_column].to_numpy(dtype=np.float64)
    all_sigma = data[sigma_column].to_numpy(dtype=np.float64)
    lower, upper = _extent(np.concatenate([all_x, all_y - all_sigma, all_y + all_sigma]).tolist())
    x = alt.X(truth_column + ":Q", title=xlabel, scale=alt.Scale(domain=[lower, upper]))
    y = alt.Y(retrieved_column + ":Q", title=ylabel, scale=alt.Scale(domain=[lower, upper]))
    error = (
        alt.Chart(frame)
        .mark_rule(opacity=0.55)
        .encode(x=x, y=alt.Y("lower:Q", title=ylabel), y2="upper:Q", color=_mode_color())
    )
    points = (
        alt.Chart(frame)
        .mark_point(filled=True, size=46, opacity=0.86)
        .encode(
            x=x,
            y=y,
            color=_mode_color(),
            shape=alt.Shape("mode_label:N", title=None),
            tooltip=[
                alt.Tooltip("scene:O", title="Scene"),
                alt.Tooltip("mode_label:N", title="Mode"),
                alt.Tooltip(truth_column + ":Q", title=xlabel, format=".6g"),
                alt.Tooltip(retrieved_column + ":Q", title=ylabel, format=".6g"),
                alt.Tooltip(sigma_column + ":Q", title="Posterior sigma", format=".6g"),
            ],
        )
    )

    return alt.layer(_identity_line(lower, upper), error, points).properties(
        width=560, height=290, title=title
    )


def delta_chart(
    delta: pd.DataFrame,
    *,
    value_column: str,
    sigma_column: str,
    title: str,
    ylabel: str,
):

    frame = delta.copy()
    frame["lower"] = frame[value_column] - frame[sigma_column]
    frame["upper"] = frame[value_column] + frame[sigma_column]
    zero = (
        alt.Chart(pd.DataFrame({"zero": [0.0]}))
        .mark_rule(color=PLOT.colors["black"], strokeDash=[4, 3], strokeWidth=0.8)
        .encode(y="zero:Q")
    )
    error = (
        alt.Chart(frame)
        .mark_rule(opacity=0.55)
        .encode(
            x=alt.X("scene:O", title="Scene"),
            xOffset=alt.XOffset("mode_label:N"),
            y=alt.Y("lower:Q", title=ylabel),
            y2="upper:Q",
            color=_mode_color(),
        )
    )
    points = (
        alt.Chart(frame)
        .mark_point(filled=True, size=46, opacity=0.84)
        .encode(
            x=alt.X("scene:O", title="Scene"),
            xOffset=alt.XOffset("mode_label:N"),
            y=alt.Y(value_column + ":Q", title=ylabel, axis=alt.Axis(format=".3e")),
            color=_mode_color(),
            shape=alt.Shape("mode_label:N", title=None),
            tooltip=[
                alt.Tooltip("scene:O", title="Scene"),
                alt.Tooltip("mode_label:N", title="Mode"),
                alt.Tooltip(value_column + ":Q", title=ylabel, format=".6g"),
                alt.Tooltip(sigma_column + ":Q", title="Combined sigma", format=".6g"),
            ],
        )
    )

    return alt.layer(zero, error, points).properties(width=560, height=250, title=title)


def timing_chart(
    data: pd.DataFrame,
    *,
    value_column: str,
    title: str,
    ylabel: str,
):

    return (
        alt.Chart(data)
        .mark_bar(opacity=0.82)
        .encode(
            x=alt.X("scene:O", title="Scene"),
            xOffset=alt.XOffset("mode_label:N"),
            y=alt.Y(value_column + ":Q", title=ylabel),
            color=_mode_color(),
            tooltip=[
                alt.Tooltip("scene:O", title="Scene"),
                alt.Tooltip("mode_label:N", title="Mode"),
                alt.Tooltip(value_column + ":Q", title=ylabel, format=".6g"),
            ],
        )
        .properties(width=560, height=250, title=title)
    )


def create_plot(data: pd.DataFrame, output_path: Path) -> None:

    delta = paired_delta_frame(data)
    chart = alt.vconcat(
        alt.hconcat(
            truth_chart(
                data,
                truth_column="truth_aerosol_optical_depth",
                retrieved_column="retrieved_aerosol_optical_depth",
                sigma_column="aerosol_optical_depth_sigma",
                title="Retrieved aerosol optical depth",
                xlabel="Truth AOD",
                ylabel="Retrieved AOD",
            ),
            truth_chart(
                data,
                truth_column="truth_aerosol_mid_pressure_hpa",
                retrieved_column="retrieved_aerosol_mid_pressure_hpa",
                sigma_column="aerosol_mid_pressure_sigma_hpa",
                title="Retrieved aerosol mid pressure",
                xlabel="Truth pressure [hPa]",
                ylabel="Retrieved pressure [hPa]",
            ),
            spacing=32,
        ),
        alt.hconcat(
            delta_chart(
                delta,
                value_column="aerosol_optical_depth_delta",
                sigma_column="aerosol_optical_depth_combined_sigma",
                title="Mode - reference retrieved AOD",
                ylabel="Delta AOD",
            ),
            delta_chart(
                delta,
                value_column="aerosol_mid_pressure_delta_hpa",
                sigma_column="aerosol_mid_pressure_combined_sigma_hpa",
                title="Mode - reference retrieved pressure",
                ylabel="Delta pressure [hPa]",
            ),
            spacing=32,
        ),
        alt.hconcat(
            timing_chart(
                data,
                value_column="retrieval_s",
                title="Retrieval wall time",
                ylabel="Wall time [s]",
            ),
            spacing=32,
        ),
        spacing=34,
    ).properties(
        title={
            "text": ("O2A Optimal-Estimation Sweep: zdisamar Reference, Fast, and Fast-Accurate"),
            "subtitle": (
                "Each paired scene uses identical measurements, priors, and initial states; "
                "error bars are posterior 1-sigma for retrieved states and combined "
                "posterior 1-sigma for mode-reference deltas."
            ),
        }
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    chart.save(output_path, scale_factor=4.0)


def main() -> None:

    OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)
    rows = build_rows()
    data = pd.DataFrame.from_records(rows)
    summary = build_summary(data)
    validate_summary(summary)
    data.to_csv(DATA_PATH, index=False)
    create_plot(data, PLOT_PATH)
    create_paired_style_retrieved_fast_scatter(data, RETRIEVED_FAST_SCATTER_PATH)
    create_latency_plot_with_fast(data, PAIRED_LATENCY_PATH)
    write_json(SUMMARY_PATH, summary)
    fast_delta = summary["fast_minus_reference"]
    fast_accurate_delta = summary["fast_accurate_minus_reference"]
    fast_accurate_fast_delta = summary["fast_accurate_minus_fast"]
    latency_position = summary["latency_position"]
    print(
        "zdisamar_o2a_fast_mode_sweep_comparison="
        f"{stable_repo_path(PLOT_PATH)} "
        f"fast_mean_retrieval_speedup={fast_delta['retrieval_speedup_s']['mean']:+.3f}s "
        "fast_accurate_mean_retrieval_speedup="
        f"{fast_accurate_delta['retrieval_speedup_s']['mean']:+.3f}s "
        "fast_accurate_median_extra_vs_fast="
        f"{fast_accurate_fast_delta['retrieval_extra_s']['median']:+.3f}s "
        "fast_accurate_latency_position="
        f"{latency_position['fast_accurate_position_between_fast_and_reference']:.3f} "
        "fast_accurate_max_abs_aod_delta="
        f"{fast_accurate_delta['aerosol_optical_depth_delta']['max_abs']:.3e} "
        "fast_accurate_max_abs_pressure_delta="
        f"{fast_accurate_delta['aerosol_mid_pressure_delta_hpa']['max_abs']:.3e}hPa"
    )


if __name__ == "__main__":
    main()
