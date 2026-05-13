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

"""Validate O2 A fast-mode optimal-estimation outputs."""

import copy
import math
import sys
import time
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.ticker import MaxNLocator

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

import zdisamar as zd  # noqa: E402
from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe  # noqa: E402
from zdisamar.plot.properties import PLOT  # noqa: E402

from validation.common import o2a_oe_reference_cases as oe_cases  # noqa: E402
from validation.common import o2a_optimal_estimation_setup as oe_setup  # noqa: E402
from validation.common import o2a_retrieval_baseline as oe_baseline  # noqa: E402
from validation.common.o2a_measurement_noise import (  # noqa: E402
    measurement_from_o2a_baseline_noise,
)
from validation.common.o2a_reference_case import build_o2a_case  # noqa: E402
from validation.common.paths import stable_repo_path, write_json  # noqa: E402
from validation.common.plot_style import (  # noqa: E402
    prepare_matplotlib,
    save_figure,
    style_axis,
    style_legend,
)

OUTPUTS_DIR = REPO_ROOT / "validation" / "outputs" / "optimal_estimation"
PLOT_PATH = OUTPUTS_DIR / "zdisamar_o2a_fast_mode_sweep_comparison.png"
RETRIEVED_FAST_SCATTER_PATH = OUTPUTS_DIR / "paired_oe_retrieved_fast_scatter.png"
PAIRED_LATENCY_PATH = OUTPUTS_DIR / "paired_oe_latency.png"
PAIRED_MANIFEST_PATH = OUTPUTS_DIR / "paired_oe_plot_manifest.json"
DATA_PATH = OUTPUTS_DIR / "zdisamar_o2a_fast_mode_sweep_comparison_runs.csv"
SUMMARY_PATH = OUTPUTS_DIR / "zdisamar_o2a_fast_mode_sweep_comparison_summary.json"

CANONICAL_COMMAND = "uv run validation/optimal_estimation/validate_fast_mode_optimal_estimation.py"
RUN_COUNT = oe_cases.run_count()

MODE_LABELS = {
    "reference": "zdisamar reference",
    "fast": "zdisamar fast",
}
MODE_COLORS = {
    "reference": PLOT.colors["blue"],
    "fast": PLOT.colors["orange"],
}
MODE_MARKERS = {
    "reference": "o",
    "fast": "x",
}
LATENCY_MODE_LABELS = {
    "disamar_fortran": "DISAMAR Fortran",
    "zdisamar": "zdisamar",
    "zdisamar_fast": "zdisamar-fast",
}
LATENCY_MODE_COLORS = {
    "disamar_fortran": PLOT.colors["blue"],
    "zdisamar": PLOT.colors["orange"],
    "zdisamar_fast": PLOT.colors["red"],
}


def with_fast_thresholds(case: Any) -> Any:
    return copy.deepcopy(case).with_fast_mode()


def run_retrieval(case: Any, measurement, state_vector) -> tuple[Any, float]:
    start = time.perf_counter()
    with zd.o2a_forward_session(case) as session:
        result = o2a_oe.disamar_oe(
            inverse_model=o2a_oe.O2AInverseForwardModel(
                case,
                forward_session=session,
            ),
            measurement=measurement,
            state_vector=state_vector,
            controls=oe_setup.retrieval_controls(),
        )
    return result, time.perf_counter() - start


def posterior_sigma(result: Any, state_name: str) -> float:
    index = result.state_names.index(state_name)
    variance = float(result.posterior_covariance[index, index])
    return math.sqrt(max(variance, 0.0))


def build_rows() -> list[dict[str, Any]]:
    base = build_o2a_case(zd, jacobian_reference_layer=True)
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
        with zd.prepare(reference_case) as prepared:
            measurement = measurement_from_o2a_baseline_noise(prepared)
            profile = o2a_oe.pressure_altitude_profile_from_prepared(prepared)
        state_vector = oe_setup.aerosol_two_state_vector(
            initial=initial,
            profile=profile,
            surface_pressure_hpa=truth["surface_pressure_hpa"],
        )

        for mode, retrieval_case in (
            ("reference", reference_case),
            ("fast", with_fast_thresholds(reference_case)),
        ):
            result, retrieval_s = run_retrieval(retrieval_case, measurement, state_vector)
            thresholds = retrieval_case.radiative_transfer.performance_thresholds
            adaptive_grid = retrieval_case.instrument_response.adaptive_reference_grid
            retrieved_aod = result.value("aerosol_optical_depth")
            retrieved_mid_pressure = result.value("aerosol_layer_mid_pressure_hpa")
            rows.append(
                {
                    "scene": index,
                    "mode": mode,
                    "mode_label": MODE_LABELS[mode],
                    "converged": bool(result.converged),
                    "iterations": int(result.iterations),
                    "retrieval_s": retrieval_s,
                    "forward_model_and_jacobian_s": sum(
                        timing.forward_model_and_jacobian_s for timing in result.timing
                    ),
                    "solver_update_s": sum(timing.solver_update_s for timing in result.timing),
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
                    "fourier_tail_reflectance_epsilon": (
                        thresholds.fourier_tail_reflectance_epsilon
                    ),
                    "threshold_doubl": thresholds.threshold_doubl,
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
        print(f"{index:03d}/{RUN_COUNT} reference+fast complete", flush=True)
    return rows


def paired_delta_frame(data: pd.DataFrame) -> pd.DataFrame:
    reference = data[data["mode"] == "reference"].set_index("scene")
    fast = data[data["mode"] == "fast"].set_index("scene")
    rows = []
    for scene in sorted(reference.index):
        ref = reference.loc[scene]
        fst = fast.loc[scene]
        rows.append(
            {
                "scene": int(scene),
                "aerosol_optical_depth_delta": (
                    float(fst["retrieved_aerosol_optical_depth"])
                    - float(ref["retrieved_aerosol_optical_depth"])
                ),
                "aerosol_optical_depth_combined_sigma": math.sqrt(
                    float(ref["aerosol_optical_depth_sigma"]) ** 2
                    + float(fst["aerosol_optical_depth_sigma"]) ** 2
                ),
                "aerosol_mid_pressure_delta_hpa": (
                    float(fst["retrieved_aerosol_mid_pressure_hpa"])
                    - float(ref["retrieved_aerosol_mid_pressure_hpa"])
                ),
                "aerosol_mid_pressure_combined_sigma_hpa": math.sqrt(
                    float(ref["aerosol_mid_pressure_sigma_hpa"]) ** 2
                    + float(fst["aerosol_mid_pressure_sigma_hpa"]) ** 2
                ),
                "retrieval_speedup_s": float(ref["retrieval_s"]) - float(fst["retrieval_s"]),
                "forward_jacobian_speedup_s": (
                    float(ref["forward_model_and_jacobian_s"])
                    - float(fst["forward_model_and_jacobian_s"])
                ),
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


def build_summary(data: pd.DataFrame) -> dict[str, Any]:
    delta = paired_delta_frame(data)
    by_mode = {}
    for mode in MODE_LABELS:
        subset = data[data["mode"] == mode]
        by_mode[mode] = {
            "rows": int(len(subset)),
            "converged": int(subset["converged"].sum()),
            "retrieval_s": stats(subset["retrieval_s"]),
            "forward_model_and_jacobian_s": stats(subset["forward_model_and_jacobian_s"]),
            "aerosol_optical_depth_abs_error": stats(subset["aerosol_optical_depth_error"].abs()),
            "aerosol_mid_pressure_abs_error_hpa": stats(
                subset["aerosol_mid_pressure_error_hpa"].abs()
            ),
        }
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
            "note": (
                "Reference rows and fast rows use the same deterministic zdisamar O2 A "
                "optimal-estimation sweep cases, measurement vectors, priors, and initial "
                "states. Fast rows apply O2AInput.with_fast_mode()."
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
            "aerosol_optical_depth_delta": stats(delta["aerosol_optical_depth_delta"]),
            "aerosol_mid_pressure_delta_hpa": stats(delta["aerosol_mid_pressure_delta_hpa"]),
            "retrieval_speedup_s": stats(delta["retrieval_speedup_s"]),
            "forward_jacobian_speedup_s": stats(delta["forward_jacobian_speedup_s"]),
        },
    }


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
    return pd.DataFrame.from_records(
        [
            {
                "scene": int(row["scene"]),
                "parameter": "Aerosol optical depth",
                "difference": float(row["aerosol_optical_depth_delta"]),
            }
            for _, row in delta.iterrows()
        ]
        + [
            {
                "scene": int(row["scene"]),
                "parameter": "Aerosol mid pressure [hPa]",
                "difference": float(row["aerosol_mid_pressure_delta_hpa"]),
            }
            for _, row in delta.iterrows()
        ]
    )


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


def scatter_panel(
    axis,
    data: pd.DataFrame,
    *,
    parameter: str,
    title: str,
) -> None:
    subset = data[data["parameter"] == parameter]
    for mode in MODE_LABELS:
        mode_subset = subset[subset["mode"] == mode]
        axis.scatter(
            mode_subset["truth"],
            mode_subset["retrieved"],
            s=34,
            alpha=0.78,
            label=MODE_LABELS[mode],
            color=MODE_COLORS[mode],
            marker=MODE_MARKERS[mode],
        )
    min_value = float(min(subset["truth"].min(), subset["retrieved"].min()))
    max_value = float(max(subset["truth"].max(), subset["retrieved"].max()))
    padding = max((max_value - min_value) * 0.04, np.finfo(np.float64).eps)
    lower = min_value - padding
    upper = max_value + padding
    axis.plot(
        [lower, upper],
        [lower, upper],
        color="black",
        linestyle=(0, (4, 3)),
        linewidth=1,
    )
    axis.set_xlim(lower, upper)
    axis.set_ylim(lower, upper)
    axis.set_title(title, fontsize=20, pad=16)
    axis.set_xlabel("True value", fontsize=15, labelpad=14)
    axis.set_ylabel("Retrieved value", fontsize=15, labelpad=12, fontweight="bold")
    axis.tick_params(labelsize=12, pad=6)
    style_axis(axis)


def histogram_panel(
    axis,
    data: pd.DataFrame,
    *,
    parameter: str,
    title: str,
    subtitle: str,
    xlabel: str,
    bins: int = 45,
) -> None:
    subset = data[data["parameter"] == parameter]
    axis.hist(
        subset["difference"],
        bins=min(bins, max(len(subset), 1)),
        color=PLOT.colors["blue"],
        alpha=0.78,
    )
    axis.axvline(0.0, color="black", linestyle=(0, (4, 3)), linewidth=1)
    axis.set_title(f"{title}\n{subtitle}", fontsize=16, pad=16)
    axis.set_xlabel(xlabel, fontsize=13, labelpad=14, fontweight="bold")
    axis.set_ylabel("Count", fontsize=15, labelpad=12, fontweight="bold")
    axis.tick_params(labelsize=12, pad=6)
    axis.xaxis.set_major_locator(MaxNLocator(nbins=5))
    axis.yaxis.set_major_locator(MaxNLocator(nbins=6, integer=True))
    axis.minorticks_off()
    style_axis(axis)


def create_paired_style_retrieved_fast_scatter(
    data: pd.DataFrame,
    output_path: Path,
) -> None:
    prepare_matplotlib()
    retrieved = fast_retrieved_rows(data)
    differences = fast_difference_rows(data)
    fig, axes = plt.subplots(2, 2, figsize=(14, 11), dpi=180)
    fig.suptitle("Retrieved State Versus Truth", fontsize=24, y=0.982)
    fig.text(
        0.5,
        0.948,
        (
            "Top: zdisamar reference and zdisamar fast retrievals against known "
            "synthetic truth.\nBottom: paired retrieval difference per scene "
            "(zdisamar fast - zdisamar reference)."
        ),
        ha="center",
        va="top",
        fontsize=11,
        family="monospace",
    )
    scatter_panel(
        axes[0, 0],
        retrieved,
        parameter="Aerosol mid pressure",
        title="Aerosol mid pressure",
    )
    scatter_panel(
        axes[0, 1],
        retrieved,
        parameter="Aerosol optical depth",
        title="Aerosol optical depth",
    )
    aod_diff = differences[differences["parameter"] == "Aerosol optical depth"]["difference"]
    pressure_diff = differences[differences["parameter"] == "Aerosol mid pressure [hPa]"][
        "difference"
    ]
    histogram_panel(
        axes[1, 0],
        differences,
        parameter="Aerosol optical depth",
        title="Aerosol optical depth",
        subtitle=difference_subtitle(aod_diff, ".3e"),
        xlabel="zdisamar fast - zdisamar reference",
    )
    histogram_panel(
        axes[1, 1],
        differences,
        parameter="Aerosol mid pressure [hPa]",
        title="Aerosol mid pressure [hPa]",
        subtitle=difference_subtitle(pressure_diff, ".4f", "hPa"),
        xlabel="zdisamar fast - zdisamar reference [hPa]",
    )
    handles, labels = axes[0, 0].get_legend_handles_labels()
    legend = fig.legend(
        handles,
        labels,
        loc="upper center",
        bbox_to_anchor=(0.5, 0.902),
        ncols=2,
        frameon=True,
        fontsize=12,
    )
    style_legend(legend)
    fig.subplots_adjust(
        left=0.08,
        right=0.985,
        top=0.77,
        bottom=0.115,
        hspace=0.64,
        wspace=0.32,
    )
    save_figure(fig, output_path)


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
    prepare_matplotlib()
    stats_by_model = paired_manifest_latency_stats()
    stats_by_model["zdisamar_fast"] = stats_from_values(
        data[data["mode"] == "fast"]["retrieval_s"].to_list()
    )

    fig, axis = plt.subplots(figsize=(7.8, 5.2), dpi=180)
    x_positions = {
        "disamar_fortran": 1,
        "zdisamar": 2,
        "zdisamar_fast": 3,
    }
    for model, x_position in x_positions.items():
        payload = stats_by_model.get(model, {})
        if not payload:
            continue
        color = LATENCY_MODE_COLORS[model]
        minimum = float(payload["min"])
        median = float(payload["median"])
        mean = float(payload["mean"])
        maximum = float(payload["max"])
        axis.vlines(x_position, minimum, maximum, color=color, linewidth=6, alpha=0.26)
        axis.scatter(
            [x_position],
            [median],
            marker="_",
            s=520,
            color=color,
            linewidths=2.6,
            label=f"{LATENCY_MODE_LABELS[model]} median",
        )
        axis.scatter(
            [x_position],
            [mean],
            marker="o",
            s=32,
            color=color,
            edgecolor="white",
            linewidth=0.8,
            zorder=3,
        )
    axis.set_yscale("log")
    axis.set_xticks(list(x_positions.values()))
    axis.set_xticklabels([LATENCY_MODE_LABELS[model] for model in x_positions])
    axis.set_ylabel("Retrieval wall time [s]")
    axis.set_title("Optimal Estimation Retrieval Latency", fontsize=16, pad=14)
    axis.text(
        0.5,
        0.97,
        "Line spans min-max; horizontal tick is median; dot is mean.",
        transform=axis.transAxes,
        ha="center",
        va="top",
        fontsize=8.8,
    )
    style_axis(axis)
    save_figure(fig, output_path, dpi=180)


def mode_subset(data: pd.DataFrame, mode: str) -> pd.DataFrame:
    return data[data["mode"] == mode].sort_values("scene")


def truth_panel(
    axis,
    data: pd.DataFrame,
    *,
    truth_column: str,
    retrieved_column: str,
    sigma_column: str,
    title: str,
    xlabel: str,
    ylabel: str,
) -> None:
    all_x = data[truth_column].to_numpy(dtype=np.float64)
    all_y = data[retrieved_column].to_numpy(dtype=np.float64)
    all_sigma = data[sigma_column].to_numpy(dtype=np.float64)
    lower = float(np.min(np.concatenate([all_x, all_y - all_sigma])))
    upper = float(np.max(np.concatenate([all_x, all_y + all_sigma])))
    padding = max((upper - lower) * 0.05, np.finfo(np.float64).eps)
    lower -= padding
    upper += padding
    axis.plot(
        [lower, upper],
        [lower, upper],
        color="black",
        linestyle=(0, (4, 3)),
        linewidth=0.9,
        alpha=0.72,
    )
    for mode in MODE_LABELS:
        subset = mode_subset(data, mode)
        axis.errorbar(
            subset[truth_column],
            subset[retrieved_column],
            yerr=subset[sigma_column],
            fmt=MODE_MARKERS[mode],
            color=MODE_COLORS[mode],
            markersize=5.5,
            elinewidth=0.85,
            capsize=2.5,
            alpha=0.86,
            label=MODE_LABELS[mode],
        )
    axis.set_xlim(lower, upper)
    axis.set_ylim(lower, upper)
    axis.set_title(title, fontsize=12.5, loc="left", pad=10)
    axis.set_xlabel(xlabel)
    axis.set_ylabel(ylabel)
    style_axis(axis)


def delta_panel(
    axis,
    delta: pd.DataFrame,
    *,
    value_column: str,
    sigma_column: str,
    title: str,
    ylabel: str,
) -> None:
    axis.axhline(0.0, color="black", linewidth=0.8, linestyle=(0, (4, 3)), alpha=0.72)
    axis.errorbar(
        delta["scene"],
        delta[value_column],
        yerr=delta[sigma_column],
        fmt="o",
        color=PLOT.colors["red"],
        markersize=5.5,
        elinewidth=0.85,
        capsize=2.8,
        alpha=0.84,
    )
    axis.set_title(title, fontsize=12.5, loc="left", pad=10)
    axis.set_xlabel("Scene")
    axis.set_ylabel(ylabel)
    axis.xaxis.set_major_locator(MaxNLocator(integer=True))
    style_axis(axis, scientific_y=True)


def timing_panel(
    axis,
    data: pd.DataFrame,
    *,
    value_column: str,
    title: str,
    ylabel: str,
) -> None:
    width = 0.34
    scenes = sorted(data["scene"].unique())
    offsets = {"reference": -0.5 * width, "fast": 0.5 * width}
    for mode in MODE_LABELS:
        subset = mode_subset(data, mode)
        axis.bar(
            subset["scene"] + offsets[mode],
            subset[value_column],
            width=width,
            color=MODE_COLORS[mode],
            alpha=0.82,
            label=MODE_LABELS[mode],
        )
    axis.set_title(title, fontsize=12.5, loc="left", pad=10)
    axis.set_xlabel("Scene")
    axis.set_ylabel(ylabel)
    axis.set_xticks(scenes)
    style_axis(axis)


def create_plot(data: pd.DataFrame, output_path: Path) -> None:
    prepare_matplotlib()
    delta = paired_delta_frame(data)
    fig, axes = plt.subplots(3, 2, figsize=(16.4, 14.6), constrained_layout=False)
    fig.suptitle(
        "O2A Optimal-Estimation Sweep: zdisamar Reference vs zdisamar Fast",
        fontsize=18,
        fontweight="normal",
        y=0.985,
    )
    fig.text(
        0.5,
        0.953,
        (
            "Each paired scene uses identical measurements, priors, and initial states; "
            "fast mode applies the validated Fourier cap, Fourier-tail, layer-doubling, "
            "and adaptive-grid settings.\n"
            "Error bars are posterior 1-sigma for retrieved states and combined "
            "posterior 1-sigma for fast-reference deltas."
        ),
        ha="center",
        va="top",
        fontsize=10.2,
    )
    truth_panel(
        axes[0, 0],
        data,
        truth_column="truth_aerosol_optical_depth",
        retrieved_column="retrieved_aerosol_optical_depth",
        sigma_column="aerosol_optical_depth_sigma",
        title="Retrieved aerosol optical depth",
        xlabel="Truth AOD",
        ylabel="Retrieved AOD",
    )
    truth_panel(
        axes[0, 1],
        data,
        truth_column="truth_aerosol_mid_pressure_hpa",
        retrieved_column="retrieved_aerosol_mid_pressure_hpa",
        sigma_column="aerosol_mid_pressure_sigma_hpa",
        title="Retrieved aerosol mid pressure",
        xlabel="Truth pressure [hPa]",
        ylabel="Retrieved pressure [hPa]",
    )
    delta_panel(
        axes[1, 0],
        delta,
        value_column="aerosol_optical_depth_delta",
        sigma_column="aerosol_optical_depth_combined_sigma",
        title="Fast - reference retrieved AOD",
        ylabel="Delta AOD",
    )
    delta_panel(
        axes[1, 1],
        delta,
        value_column="aerosol_mid_pressure_delta_hpa",
        sigma_column="aerosol_mid_pressure_combined_sigma_hpa",
        title="Fast - reference retrieved pressure",
        ylabel="Delta pressure [hPa]",
    )
    timing_panel(
        axes[2, 0],
        data,
        value_column="retrieval_s",
        title="Retrieval wall time",
        ylabel="Wall time [s]",
    )
    timing_panel(
        axes[2, 1],
        data,
        value_column="forward_model_and_jacobian_s",
        title="Forward model + Jacobian time",
        ylabel="Time [s]",
    )
    handles, labels = axes[0, 0].get_legend_handles_labels()
    legend = fig.legend(
        handles,
        labels,
        loc="upper center",
        bbox_to_anchor=(0.5, 0.912),
        ncols=2,
    )
    style_legend(legend)
    fig.subplots_adjust(
        left=0.075,
        right=0.985,
        top=0.825,
        bottom=0.065,
        hspace=0.62,
        wspace=0.26,
    )
    save_figure(fig, output_path)


def main() -> None:
    OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)
    rows = build_rows()
    data = pd.DataFrame.from_records(rows)
    data.to_csv(DATA_PATH, index=False)
    create_plot(data, PLOT_PATH)
    create_paired_style_retrieved_fast_scatter(data, RETRIEVED_FAST_SCATTER_PATH)
    create_latency_plot_with_fast(data, PAIRED_LATENCY_PATH)
    summary = build_summary(data)
    write_json(SUMMARY_PATH, summary)
    delta = summary["fast_minus_reference"]
    print(
        "zdisamar_o2a_fast_mode_sweep_comparison="
        f"{stable_repo_path(PLOT_PATH)} "
        f"mean_retrieval_speedup={delta['retrieval_speedup_s']['mean']:+.3f}s "
        f"max_abs_aod_delta={delta['aerosol_optical_depth_delta']['max_abs']:.3e} "
        f"max_abs_pressure_delta={delta['aerosol_mid_pressure_delta_hpa']['max_abs']:.3e}hPa"
    )


if __name__ == "__main__":
    main()
