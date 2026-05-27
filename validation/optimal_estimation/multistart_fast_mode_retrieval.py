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

"""Prototype multi-start O2 A fast-mode optimal-estimation retrieval outputs."""

import argparse
import copy
import csv
import math
import os
import statistics
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from typing import Any

import altair as alt
import numpy as np
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
NATIVE_WORKER_LIMIT_ENV = "ZDISAMAR_WORKER_LIMIT"
DEFAULT_NATIVE_WORKER_LIMIT = os.cpu_count() or 1
os.environ.setdefault(NATIVE_WORKER_LIMIT_ENV, str(DEFAULT_NATIVE_WORKER_LIMIT))
sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

from zdisamar import rtm  # noqa: E402
from zdisamar.inverse_method import optimal_estimation  # noqa: E402
from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe  # noqa: E402
from zdisamar.plot.properties import PLOT  # noqa: E402
from zdisamar.wavelength_bands import o2a  # noqa: E402

from validation.common.paths import OUT_VALIDATION_ROOT, stable_repo_path, write_json  # noqa: E402
from validation.o2a import baseline as oe_baseline  # noqa: E402
from validation.o2a.case import build_o2a_case  # noqa: E402
from validation.o2a.measurement_noise import (  # noqa: E402
    measurement_from_o2a_baseline_noise,
)
from validation.optimal_estimation import reference_cases as oe_cases  # noqa: E402
from validation.optimal_estimation import setup as oe_setup  # noqa: E402

OUTPUTS_DIR = REPO_ROOT / "validation" / "outputs" / "optimal_estimation" / "multistart"
SESSION_CACHE_ROOT = OUT_VALIDATION_ROOT / "optimal_estimation" / "multistart_session_cache"
CANONICAL_COMMAND = "uv run validation/optimal_estimation/multistart_fast_mode_retrieval.py"
DEFAULT_SCENE_COUNT = 20
DEFAULT_START_COUNT = 100
START_AOD_RANGE = (0.10, 2.0)
START_PRESSURE_LOWER_HPA = 225.0
TRAJECTORY_AOD_CELLS = 210
TRAJECTORY_PRESSURE_CELLS = 210
TRAJECTORY_GAUSSIAN_RADIUS = 12
TRAJECTORY_GAUSSIAN_SIGMA = 4.2
TRAJECTORY_DENSITY_GAMMA = 0.58
AOD_AXIS_TITLE = "Aerosol optical depth at 550 nm"
PRESSURE_AXIS_TITLE = "Aerosol layer mid pressure [hPa]"
PLOT_SCALE_FACTOR = 2.0


def parse_args() -> argparse.Namespace:

    parser = argparse.ArgumentParser(
        description="Run multi-start fast-mode O2 A optimal-estimation retrievals."
    )
    parser.add_argument("--scene-count", type=int, default=DEFAULT_SCENE_COUNT)
    parser.add_argument(
        "--scene",
        action="append",
        type=int,
        default=None,
        help="1-based reference scene index to run; may be passed more than once",
    )
    parser.add_argument("--start-count", type=int, default=DEFAULT_START_COUNT)
    parser.add_argument("--workers", type=int, default=1)
    parser.add_argument("--native-worker-limit", type=int, default=DEFAULT_NATIVE_WORKER_LIMIT)
    parser.add_argument(
        "--batch-workers",
        type=int,
        default=1,
        help=(
            "Native start-level workers for one scene batch. Use with "
            "--native-worker-limit 1 to avoid nested RTM worker oversubscription."
        ),
    )
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--session-cache-root", type=Path, default=SESSION_CACHE_ROOT)
    parser.add_argument(
        "--session-id",
        type=str,
        default=None,
        help="cache subdirectory for runs.csv, summary.json, and derived plots",
    )
    parser.add_argument(
        "--fast-stage-only",
        action="store_true",
        help="disable the sparse full-physics final correction after the fast OE stage",
    )
    parser.add_argument(
        "--reuse-runs",
        action="store_true",
        help="rebuild the summary and plots from output-dir/runs.csv",
    )

    return parser.parse_args()


def selected_scene_rows(args: argparse.Namespace) -> list[dict[str, Any]]:

    if args.scene is None:
        return oe_cases.case_rows(count=args.scene_count)

    scene_indices = sorted(set(args.scene))

    if any(scene_index <= 0 for scene_index in scene_indices):
        raise SystemExit("--scene values must be positive 1-based indices")

    rows = oe_cases.case_rows(count=max(scene_indices))
    by_index = {int(row["case"]): row for row in rows}

    return [by_index[scene_index] for scene_index in scene_indices]


def default_session_id(
    *,
    scene_rows: list[dict[str, Any]],
    start_count: int,
    fast_stage_only: bool,
) -> str:

    scene_part = "-".join(f"{int(row['case']):03d}" for row in scene_rows)
    correction_part = "fast-stage-only" if fast_stage_only else "fast-plus-correction"

    return f"scene-{scene_part}_starts-{start_count}_prior-start_{correction_part}"


def resolve_output_dir(
    args: argparse.Namespace,
    *,
    scene_rows: list[dict[str, Any]],
) -> Path:

    if args.output_dir is not None:
        return args.output_dir

    session_id = args.session_id or default_session_id(
        scene_rows=scene_rows,
        start_count=args.start_count,
        fast_stage_only=args.fast_stage_only,
    )

    return args.session_cache_root / session_id


def fastmode_case(case: Any, *, fast_stage_only: bool) -> Any:

    fast_case = copy.deepcopy(case)
    fast_case.optimisation.fastmode.enabled = True

    if fast_stage_only:
        fast_case.optimisation.fastmode.oe.final_correction.enabled = False

    return fast_case


def scene_start_values(
    *,
    count: int,
    surface_pressure_hpa: float,
) -> list[dict[str, float]]:

    pressure_upper = surface_pressure_hpa - 100.0

    if pressure_upper <= START_PRESSURE_LOWER_HPA:
        raise ValueError("scene surface pressure does not leave room for ALH starts")

    side = math.isqrt(count)

    if side * side == count:
        aod_values = np.geomspace(START_AOD_RANGE[0], START_AOD_RANGE[1], side)
        pressure_values = np.linspace(START_PRESSURE_LOWER_HPA, pressure_upper, side)

        return [
            {
                "aerosol_optical_depth": float(aod),
                "aerosol_mid_pressure_hpa": float(pressure),
            }
            for pressure in pressure_values
            for aod in aod_values
        ]

    rng = np.random.default_rng(10_000 + count + int(round(surface_pressure_hpa)))
    aod_unit = oe_setup.uniform_lhs(rng, 0.0, 1.0, count)
    pressure_unit = oe_setup.uniform_lhs(rng, 0.0, 1.0, count)
    aod_values = np.exp(
        math.log(START_AOD_RANGE[0])
        + aod_unit * (math.log(START_AOD_RANGE[1]) - math.log(START_AOD_RANGE[0]))
    )
    pressure_values = START_PRESSURE_LOWER_HPA + pressure_unit * (
        pressure_upper - START_PRESSURE_LOWER_HPA
    )

    return [
        {
            "aerosol_optical_depth": float(aod),
            "aerosol_mid_pressure_hpa": float(pressure),
        }
        for aod, pressure in zip(aod_values, pressure_values, strict=True)
    ]


def multistart_state_vector(
    *,
    start: dict[str, float],
    prior: dict[str, float],
    surface_pressure_hpa: float,
) -> optimal_estimation.StateVector:

    return optimal_estimation.StateVector(
        [
            optimal_estimation.AerosolOpticalDepth(
                initial=start["aerosol_optical_depth"],
                prior=prior["aerosol_optical_depth"],
                prior_uncertainty=math.sqrt(0.8),
                lower=0.02,
                upper=5.0,
            ),
            optimal_estimation.AerosolLayerMidPressure(
                initial=start["aerosol_mid_pressure_hpa"],
                prior=prior["aerosol_mid_pressure_hpa"],
                prior_uncertainty=150.0,
                lower=START_PRESSURE_LOWER_HPA,
                upper=surface_pressure_hpa - 100.0,
            ),
        ]
    )


def run_scene(
    scene_row: dict[str, Any],
    *,
    start_count: int,
    fast_stage_only: bool,
    batch_workers: int,
    completed_start_indices: set[int] | None = None,
    checkpoint_path: Path | None = None,
) -> list[dict[str, Any]]:

    base = build_o2a_case(o2a, jacobian_reference_layer=True)
    oe_baseline.configure_case(base)
    scene_index = int(scene_row["case"])
    truth = oe_cases.scene_from_row(scene_row)
    reference_case = oe_setup.build_scene(
        base,
        index=scene_index,
        id_prefix="o2a_fast_mode_multistart",
        scene=truth,
    )
    case = fastmode_case(reference_case, fast_stage_only=fast_stage_only)
    measurement = measurement_from_o2a_baseline_noise(reference_case)
    starts = scene_start_values(
        count=start_count,
        surface_pressure_hpa=truth["surface_pressure_hpa"],
    )
    rows: list[dict[str, Any]] = []
    skip_start_indices = completed_start_indices or set()
    pending = [
        (start_index, start)
        for start_index, start in enumerate(starts, start=1)
        if start_index not in skip_start_indices
    ]

    if not pending:
        print(f"scene {scene_index:03d} already cached", flush=True)

        return rows

    if case.optimisation.fastmode.enabled:
        retrieval_start = time.perf_counter()
        state_vectors = [
            multistart_state_vector(
                start=start,
                prior=start,
                surface_pressure_hpa=truth["surface_pressure_hpa"],
            )
            for _, start in pending
        ]
        retrieval_mode = "native_batch_fast_stage" if fast_stage_only else "native_batch_fastmode"

        try:
            with rtm.SessionCache() as cache:
                result = o2a_oe.retrieve_many(
                    case=case,
                    measurement=measurement,
                    state_vectors=state_vectors,
                    controls=oe_setup.retrieval_controls(),
                    cache=cache,
                    batch_workers=batch_workers,
                )

            batch_s = time.perf_counter() - retrieval_start
            retrieval_s = batch_s / len(pending)
            aod_values = result.value("aerosol_optical_depth")
            pressure_values = result.value("aerosol_layer_mid_pressure_hpa")
            fast_stage_iterations = result.fast_stage_iterations or result.iterations
            fast_stage_converged = result.fast_stage_converged or result.converged
            full_correction_converged = result.full_correction_converged

            for offset, ((start_index, start), converged, iterations) in enumerate(
                zip(pending, result.converged, result.iterations, strict=True)
            ):
                row = retrieval_row(
                    scene_index=scene_index,
                    start_index=start_index,
                    status="ok",
                    error="",
                    converged=converged,
                    iterations=iterations,
                    fast_stage_iterations=fast_stage_iterations[offset],
                    fast_stage_converged=fast_stage_converged[offset],
                    full_correction_converged=(
                        math.nan
                        if full_correction_converged is None
                        else full_correction_converged[offset]
                    ),
                    full_correction_state_vector_convergence=math.nan,
                    retrieval_s=retrieval_s,
                    truth=truth,
                    start=start,
                    retrieved_aod=aod_values[offset],
                    retrieved_pressure=pressure_values[offset],
                    retrieval_mode=retrieval_mode,
                    batch_wall_s=batch_s,
                )
                rows.append(row)

                if checkpoint_path is not None:
                    append_run(checkpoint_path, row)
        except Exception as exc:  # noqa: BLE001 - retained as validation evidence.
            batch_s = time.perf_counter() - retrieval_start
            retrieval_s = batch_s / len(pending)

            for start_index, start in pending:
                row = retrieval_row(
                    scene_index=scene_index,
                    start_index=start_index,
                    status="error",
                    error=str(exc),
                    converged=False,
                    iterations=0,
                    fast_stage_iterations=math.nan,
                    fast_stage_converged=math.nan,
                    full_correction_converged=math.nan,
                    full_correction_state_vector_convergence=math.nan,
                    retrieval_s=retrieval_s,
                    truth=truth,
                    start=start,
                    retrieved_aod=math.nan,
                    retrieved_pressure=math.nan,
                    retrieval_mode=retrieval_mode,
                    batch_wall_s=batch_s,
                )
                rows.append(row)

                if checkpoint_path is not None:
                    append_run(checkpoint_path, row)

        print(
            f"scene {scene_index:03d} batched {len(pending):03d}/{start_count} "
            f"dt={batch_s:.3f}s avg={retrieval_s:.3f}s",
            flush=True,
        )

        return rows

    with rtm.SessionCache() as cache:
        for start_index, start in pending:
            retrieval_start = time.perf_counter()
            state_vector = multistart_state_vector(
                start=start,
                prior=start,
                surface_pressure_hpa=truth["surface_pressure_hpa"],
            )

            try:
                result = o2a_oe.retrieve(
                    case=case,
                    measurement=measurement,
                    state_vector=state_vector,
                    controls=oe_setup.retrieval_controls(),
                    cache=cache,
                )
                retrieval_s = time.perf_counter() - retrieval_start
                retrieved_aod = result.value("aerosol_optical_depth")
                retrieved_pressure = result.value("aerosol_layer_mid_pressure_hpa")
                correction = result.fast_correction
                status = "ok"
                error = ""
                converged = bool(result.converged)
                iterations = int(result.iterations)
                fast_stage_iterations = (
                    math.nan if correction is None else int(correction.fast_iterations)
                )
                fast_stage_converged = (
                    math.nan if correction is None else bool(correction.fast_converged)
                )
                full_correction_converged = (
                    math.nan if correction is None else bool(correction.full_correction_converged)
                )
                full_correction_state_vector_convergence = (
                    math.nan
                    if correction is None
                    else float(correction.full_correction_state_vector_convergence)
                )
            except Exception as exc:  # noqa: BLE001 - retained as validation evidence.
                retrieval_s = time.perf_counter() - retrieval_start
                retrieved_aod = math.nan
                retrieved_pressure = math.nan
                status = "error"
                error = str(exc)
                converged = False
                iterations = 0
                fast_stage_iterations = math.nan
                fast_stage_converged = math.nan
                full_correction_converged = math.nan
                full_correction_state_vector_convergence = math.nan

            row = retrieval_row(
                scene_index=scene_index,
                start_index=start_index,
                status=status,
                error=error,
                converged=converged,
                iterations=iterations,
                fast_stage_iterations=fast_stage_iterations,
                fast_stage_converged=fast_stage_converged,
                full_correction_converged=full_correction_converged,
                full_correction_state_vector_convergence=full_correction_state_vector_convergence,
                retrieval_s=retrieval_s,
                truth=truth,
                start=start,
                retrieved_aod=retrieved_aod,
                retrieved_pressure=retrieved_pressure,
                retrieval_mode="python_loop",
                batch_wall_s=math.nan,
            )
            rows.append(row)

            if checkpoint_path is not None:
                append_run(checkpoint_path, row)

            progress_step = 1 if start_count <= 10 else 10

            if start_index % progress_step == 0 or start_index == start_count:
                print(
                    f"scene {scene_index:03d} start {start_index:03d}/{start_count} "
                    f"dt={retrieval_s:.3f}s status={status}",
                    flush=True,
                )

    return rows


def retrieval_row(
    *,
    scene_index: int,
    start_index: int,
    status: str,
    error: str,
    converged: bool,
    iterations: int,
    fast_stage_iterations: int | float,
    fast_stage_converged: bool | float,
    full_correction_converged: bool | float,
    full_correction_state_vector_convergence: float,
    retrieval_s: float,
    truth: dict[str, float],
    start: dict[str, float],
    retrieved_aod: float,
    retrieved_pressure: float,
    retrieval_mode: str,
    batch_wall_s: float,
) -> dict[str, Any]:

    return {
        "scene": scene_index,
        "start_index": start_index,
        "status": status,
        "error": error,
        "converged": converged,
        "iterations": iterations,
        "fast_stage_iterations": fast_stage_iterations,
        "fast_stage_converged": fast_stage_converged,
        "full_correction_converged": full_correction_converged,
        "full_correction_state_vector_convergence": full_correction_state_vector_convergence,
        "retrieval_s": retrieval_s,
        "batch_wall_s": batch_wall_s,
        "retrieval_mode": retrieval_mode,
        "truth_aerosol_optical_depth": truth["aerosol_optical_depth"],
        "truth_aerosol_mid_pressure_hpa": truth["aerosol_mid_pressure_hpa"],
        "prior_aerosol_optical_depth": start["aerosol_optical_depth"],
        "prior_aerosol_mid_pressure_hpa": start["aerosol_mid_pressure_hpa"],
        "start_aerosol_optical_depth": start["aerosol_optical_depth"],
        "start_aerosol_mid_pressure_hpa": start["aerosol_mid_pressure_hpa"],
        "retrieved_aerosol_optical_depth": retrieved_aod,
        "retrieved_aerosol_mid_pressure_hpa": retrieved_pressure,
        "aerosol_optical_depth_error": retrieved_aod - truth["aerosol_optical_depth"],
        "aerosol_mid_pressure_error_hpa": (retrieved_pressure - truth["aerosol_mid_pressure_hpa"]),
        "solar_zenith_deg": truth["solar_zenith_deg"],
        "viewing_zenith_deg": truth["viewing_zenith_deg"],
        "relative_azimuth_deg": truth["relative_azimuth_deg"],
        "surface_pressure_hpa": truth["surface_pressure_hpa"],
        "surface_albedo": truth["surface_albedo"],
    }


def percentile(values: list[float], q: float) -> float:

    if not values:
        return math.nan

    return float(np.percentile(np.asarray(values, dtype=np.float64), q))


def stats(values: list[float]) -> dict[str, float]:

    finite = [float(value) for value in values if math.isfinite(float(value))]

    return {
        "min": min(finite) if finite else math.nan,
        "median": statistics.median(finite) if finite else math.nan,
        "mean": statistics.fmean(finite) if finite else math.nan,
        "p90": percentile(finite, 90.0),
        "max": max(finite) if finite else math.nan,
    }


def extent(values: list[float], *, positive: bool = False) -> tuple[float, float]:

    finite = [float(value) for value in values if math.isfinite(float(value))]

    if positive:
        finite = [value for value in finite if value > 0.0]

    if not finite:
        return (1.0e-6, 1.0) if positive else (0.0, 1.0)

    lower = min(finite)
    upper = max(finite)

    if lower == upper:
        padding = max(abs(lower) * 0.05, 1.0e-6 if positive else 1.0)

        return lower - padding, upper + padding

    if positive:
        return lower / 1.08, upper * 1.08

    padding = 0.04 * (upper - lower)

    return lower - padding, upper + padding


def gaussian_kernel(*, radius: int, sigma: float) -> np.ndarray:

    offsets = np.arange(-radius, radius + 1, dtype=np.float64)
    kernel = np.exp(-(offsets * offsets) / (2.0 * sigma * sigma))

    return kernel / kernel.sum()


def convolve_axis(values: np.ndarray, kernel: np.ndarray, *, axis: int) -> np.ndarray:

    padding = len(kernel) // 2
    pad_width = [
        (padding, padding) if dimension == axis else (0, 0) for dimension in range(values.ndim)
    ]
    padded = np.pad(values, pad_width, mode="edge")

    return np.apply_along_axis(
        lambda column: np.convolve(column, kernel, mode="valid"),
        axis,
        padded,
    )


def trajectory_density_heatmap_rows(
    data: pd.DataFrame,
    *,
    aod_domain: tuple[float, float],
    pressure_domain: tuple[float, float],
) -> pd.DataFrame:

    ok = data[data["status"] == "ok"].copy()

    if ok.empty:
        return pd.DataFrame.from_records([])

    log_aod_edges = np.linspace(
        math.log10(aod_domain[0]),
        math.log10(aod_domain[1]),
        TRAJECTORY_AOD_CELLS + 1,
    )
    pressure_edges = np.linspace(
        pressure_domain[0],
        pressure_domain[1],
        TRAJECTORY_PRESSURE_CELLS + 1,
    )
    sample_log_aod: list[float] = []
    sample_pressure: list[float] = []

    for row in ok.to_dict("records"):
        start_log_aod = math.log10(float(row["start_aerosol_optical_depth"]))
        start_pressure = float(row["start_aerosol_mid_pressure_hpa"])
        retrieved_log_aod = math.log10(max(float(row["retrieved_aerosol_optical_depth"]), 1.0e-6))
        retrieved_pressure = float(row["retrieved_aerosol_mid_pressure_hpa"])
        length_cells = math.hypot(
            (retrieved_log_aod - start_log_aod) / (log_aod_edges[1] - log_aod_edges[0]),
            (retrieved_pressure - start_pressure) / (pressure_edges[1] - pressure_edges[0]),
        )
        sample_count = int(min(max(length_cells * 2.0, 90.0), 450.0))
        weights = np.linspace(0.0, 1.0, sample_count)
        sample_log_aod.extend(start_log_aod + (retrieved_log_aod - start_log_aod) * weights)
        sample_pressure.extend(start_pressure + (retrieved_pressure - start_pressure) * weights)

    histogram, _, _ = np.histogram2d(
        sample_log_aod,
        sample_pressure,
        bins=[log_aod_edges, pressure_edges],
    )
    kernel = gaussian_kernel(
        radius=TRAJECTORY_GAUSSIAN_RADIUS,
        sigma=TRAJECTORY_GAUSSIAN_SIGMA,
    )
    smoothed = convolve_axis(
        convolve_axis(histogram, kernel, axis=0),
        kernel,
        axis=1,
    )
    normalized = smoothed / smoothed.max() if smoothed.max() > 0.0 else smoothed
    display_density = np.power(normalized, TRAJECTORY_DENSITY_GAMMA)
    aod_lower = 10.0 ** log_aod_edges[:-1]
    aod_upper = 10.0 ** log_aod_edges[1:]
    pressure_lower = pressure_edges[:-1]
    pressure_upper = pressure_edges[1:]

    return pd.DataFrame.from_records(
        {
            "aod_lower": float(aod_lower[x_index]),
            "aod_upper": float(aod_upper[x_index]),
            "pressure_lower_hpa": float(pressure_lower[y_index]),
            "pressure_upper_hpa": float(pressure_upper[y_index]),
            "relative_trajectory_density": float(display_density[x_index, y_index] * 100.0),
        }
        for x_index in range(len(aod_lower))
        for y_index in range(len(pressure_lower))
    )


def scene_domains(data: pd.DataFrame) -> tuple[tuple[float, float], tuple[float, float]]:

    aod_values = (
        data["start_aerosol_optical_depth"].to_list()
        + data["retrieved_aerosol_optical_depth"].to_list()
        + data["truth_aerosol_optical_depth"].to_list()
    )
    pressure_values = (
        data["start_aerosol_mid_pressure_hpa"].to_list()
        + data["retrieved_aerosol_mid_pressure_hpa"].to_list()
        + data["truth_aerosol_mid_pressure_hpa"].to_list()
    )

    aod_domain = extent(aod_values, positive=True)
    pressure_domain = extent(pressure_values)

    return aod_domain, pressure_domain


def movement_rows(data: pd.DataFrame) -> pd.DataFrame:

    rows = []

    for row in data.to_dict("records"):
        if row["status"] != "ok":
            continue

        rows.extend(
            [
                {
                    "start_index": int(row["start_index"]),
                    "state": "start",
                    "aerosol_optical_depth": float(row["start_aerosol_optical_depth"]),
                    "aerosol_mid_pressure_hpa": float(row["start_aerosol_mid_pressure_hpa"]),
                },
                {
                    "start_index": int(row["start_index"]),
                    "state": "retrieved",
                    "aerosol_optical_depth": float(row["retrieved_aerosol_optical_depth"]),
                    "aerosol_mid_pressure_hpa": float(row["retrieved_aerosol_mid_pressure_hpa"]),
                },
            ]
        )

    return pd.DataFrame.from_records(rows)


def marker_rows(data: pd.DataFrame) -> pd.DataFrame:

    first = data.iloc[0]

    return pd.DataFrame.from_records(
        [
            {
                "label": "truth",
                "aerosol_optical_depth": float(first["truth_aerosol_optical_depth"]),
                "aerosol_mid_pressure_hpa": float(first["truth_aerosol_mid_pressure_hpa"]),
            },
        ]
    )


def scene_title(data: pd.DataFrame) -> dict[str, object]:

    first = data.iloc[0]
    ok_count = int((data["status"] == "ok").sum())
    converged_count = int(data["converged"].sum())

    return {
        "text": f"Scene {int(first['scene']):03d} Fast-Mode OE Multi-Start Retrieval",
        "subtitle": (
            f"{ok_count}/{len(data)} retrievals finished, "
            f"{converged_count}/{len(data)} converged; "
            f"truth AOD {first['truth_aerosol_optical_depth']:.4g}, "
            f"truth ALH {first['truth_aerosol_mid_pressure_hpa']:.1f} hPa"
        ),
    }


def save_scene_plot(data: pd.DataFrame, output_path: Path) -> None:

    aod_domain, pressure_domain = scene_domains(data)
    heatmap = trajectory_density_heatmap_rows(
        data,
        aod_domain=aod_domain,
        pressure_domain=pressure_domain,
    )
    ok = data[data["status"] == "ok"].copy()
    starts = ok.rename(
        columns={
            "start_aerosol_optical_depth": "aerosol_optical_depth",
            "start_aerosol_mid_pressure_hpa": "aerosol_mid_pressure_hpa",
        }
    )
    endpoints = ok.rename(
        columns={
            "retrieved_aerosol_optical_depth": "aerosol_optical_depth",
            "retrieved_aerosol_mid_pressure_hpa": "aerosol_mid_pressure_hpa",
        }
    )
    markers = marker_rows(data)
    y_scale = alt.Scale(domain=[pressure_domain[1], pressure_domain[0]], nice=False)
    x_scale = alt.Scale(type="log", domain=list(aod_domain), nice=False)
    x = alt.X(
        "aerosol_optical_depth:Q",
        title=AOD_AXIS_TITLE,
        scale=x_scale,
    )
    y = alt.Y(
        "aerosol_mid_pressure_hpa:Q",
        title=PRESSURE_AXIS_TITLE,
        scale=y_scale,
    )
    heatmap_layer = (
        alt.Chart(heatmap)
        .mark_rect(strokeOpacity=0)
        .encode(
            x=alt.X("aod_lower:Q", title=AOD_AXIS_TITLE, scale=x_scale),
            x2="aod_upper:Q",
            y=alt.Y("pressure_lower_hpa:Q", title=PRESSURE_AXIS_TITLE, scale=y_scale),
            y2="pressure_upper_hpa:Q",
            color=alt.Color(
                "relative_trajectory_density:Q",
                title="Relative trajectory density",
                scale=alt.Scale(
                    domain=[0.0, 100.0],
                    range=[
                        "#fffdf2",
                        "#fee391",
                        "#fec44f",
                        "#fc8d59",
                        "#e34a33",
                        "#b30000",
                    ],
                ),
                legend=alt.Legend(orient="right", format=".0f"),
            ),
            tooltip=[
                alt.Tooltip(
                    "relative_trajectory_density:Q",
                    title="Relative trajectory density",
                    format=".1f",
                ),
            ],
        )
    )
    start_points = (
        alt.Chart(starts)
        .mark_circle(
            size=32,
            fillOpacity=0,
            stroke=PLOT.colors["blue"],
            strokeWidth=1.0,
            opacity=0.45,
        )
        .encode(x=x, y=y)
    )
    endpoint_points = (
        alt.Chart(endpoints)
        .mark_circle(size=13, color=PLOT.colors["black"], opacity=0.58)
        .encode(x=x, y=y)
    )
    truth_marker = (
        alt.Chart(markers)
        .mark_point(
            filled=True,
            size=155,
            stroke=PLOT.colors["black"],
            strokeWidth=1.5,
        )
        .encode(
            x=x,
            y=y,
            shape=alt.Shape(
                "label:N",
                title=None,
                scale=alt.Scale(domain=["truth"], range=["cross"]),
                legend=None,
            ),
            color=alt.Color(
                "label:N",
                title=None,
                scale=alt.Scale(domain=["truth"], range=[PLOT.colors["red"]]),
                legend=None,
            ),
            tooltip=[
                alt.Tooltip("label:N", title="Marker"),
                alt.Tooltip("aerosol_optical_depth:Q", title="AOD", format=".5g"),
                alt.Tooltip(
                    "aerosol_mid_pressure_hpa:Q",
                    title="ALH [hPa]",
                    format=".2f",
                ),
            ],
        )
    )
    title = scene_title(data)
    chart = (
        alt.layer(heatmap_layer, start_points, endpoint_points, truth_marker)
        .properties(
            width=780,
            height=570,
            title={
                **title,
                "subtitle": [
                    title["subtitle"],
                    (
                        "Smoothed density of a priori/start-to-retrieved paths; "
                        "redder means more trajectories pass through or terminate there."
                    ),
                ],
            },
        )
        .configure_axis(
            gridColor=PLOT.colors["grid"],
            gridOpacity=0.25,
        )
        .configure_legend(
            labelLimit=220,
            titleLimit=220,
        )
        .configure_view(stroke=None)
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    chart.save(output_path, scale_factor=PLOT_SCALE_FACTOR)


def write_runs(path: Path, rows: list[dict[str, Any]]) -> None:

    path.parent.mkdir(parents=True, exist_ok=True)

    if not rows:
        raise ValueError("no retrieval rows to write")

    ordered_rows = sorted(rows, key=lambda row: (int(row["scene"]), int(row["start_index"])))
    fieldnames = list(ordered_rows[0])

    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(ordered_rows)


def append_run(path: Path, row: dict[str, Any]) -> None:

    path.parent.mkdir(parents=True, exist_ok=True)
    exists = path.is_file()

    if exists:
        with path.open(newline="") as handle:
            reader = csv.reader(handle)
            fieldnames = next(reader)
    else:
        fieldnames = list(row)

    with path.open("a", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")

        if not exists:
            writer.writeheader()

        writer.writerow(row)


def read_runs(path: Path) -> list[dict[str, Any]]:

    if not path.is_file():
        raise FileNotFoundError(f"cannot reuse missing runs CSV: {stable_repo_path(path)}")

    frame = pd.read_csv(path)

    return frame.to_dict("records")


def merge_rows(
    existing_rows: list[dict[str, Any]],
    new_rows: list[dict[str, Any]],
) -> list[dict[str, Any]]:

    by_key = {
        (int(row["scene"]), int(row["start_index"])): row
        for row in existing_rows
        if "scene" in row and "start_index" in row
    }

    for row in new_rows:
        by_key[(int(row["scene"]), int(row["start_index"]))] = row

    return [by_key[key] for key in sorted(by_key)]


def completed_by_scene(rows: list[dict[str, Any]]) -> dict[int, set[int]]:

    completed: dict[int, set[int]] = {}

    for row in rows:
        try:
            scene = int(row["scene"])
            start_index = int(row["start_index"])
        except KeyError:
            continue
        except TypeError:
            continue
        except ValueError:
            continue

        completed.setdefault(scene, set()).add(start_index)

    return completed


def starts_per_scene(rows: list[dict[str, Any]], fallback: int) -> int:

    if not rows:
        return fallback

    data = pd.DataFrame.from_records(rows)
    counts = data.groupby("scene").size().to_list()

    return int(max(counts)) if counts else fallback


def scene_summary(data: pd.DataFrame, plot_path: Path) -> dict[str, Any]:

    ok = data[data["status"] == "ok"]

    return {
        "scene": int(data["scene"].iloc[0]),
        "rows": int(len(data)),
        "ok": int(len(ok)),
        "converged": int(data["converged"].sum()),
        "plot": stable_repo_path(plot_path),
        "truth": {
            "aerosol_optical_depth": float(data["truth_aerosol_optical_depth"].iloc[0]),
            "aerosol_mid_pressure_hpa": float(data["truth_aerosol_mid_pressure_hpa"].iloc[0]),
        },
        "apriori_start": {
            "aerosol_optical_depth": stats(ok["prior_aerosol_optical_depth"].to_list()),
            "aerosol_mid_pressure_hpa": stats(ok["prior_aerosol_mid_pressure_hpa"].to_list()),
        },
        "retrieval_s": stats(ok["retrieval_s"].to_list()),
        "batch_wall_s": stats(ok["batch_wall_s"].to_list()) if "batch_wall_s" in ok else stats([]),
        "retrieved_aerosol_optical_depth": stats(ok["retrieved_aerosol_optical_depth"].to_list()),
        "retrieved_aerosol_mid_pressure_hpa": stats(
            ok["retrieved_aerosol_mid_pressure_hpa"].to_list()
        ),
        "aerosol_optical_depth_abs_error": stats(ok["aerosol_optical_depth_error"].abs().to_list()),
        "aerosol_mid_pressure_abs_error_hpa": stats(
            ok["aerosol_mid_pressure_error_hpa"].abs().to_list()
        ),
    }


def run_all_scenes(
    scene_rows: list[dict[str, Any]],
    *,
    start_count: int,
    workers: int,
    fast_stage_only: bool,
    batch_workers: int,
    existing_rows: list[dict[str, Any]],
    checkpoint_path: Path | None,
) -> list[dict[str, Any]]:

    completed = completed_by_scene(existing_rows)

    if workers == 1:
        rows: list[dict[str, Any]] = []

        for row in scene_rows:
            rows.extend(
                run_scene(
                    row,
                    start_count=start_count,
                    fast_stage_only=fast_stage_only,
                    batch_workers=batch_workers,
                    completed_start_indices=completed.get(int(row["case"]), set()),
                    checkpoint_path=checkpoint_path,
                )
            )

        return rows

    rows = []

    with ProcessPoolExecutor(max_workers=workers) as executor:
        futures = [
            executor.submit(
                run_scene,
                row,
                start_count=start_count,
                fast_stage_only=fast_stage_only,
                batch_workers=batch_workers,
                completed_start_indices=completed.get(int(row["case"]), set()),
            )
            for row in scene_rows
        ]

        for future in as_completed(futures):
            scene_rows_result = future.result()
            rows.extend(scene_rows_result)
            scene_index = int(scene_rows_result[0]["scene"]) if scene_rows_result else -1
            print(f"scene {scene_index:03d} complete", flush=True)

    rows.sort(key=lambda row: (int(row["scene"]), int(row["start_index"])))

    return rows


def build_summary(
    rows: list[dict[str, Any]],
    *,
    output_dir: Path,
    scene_count: int,
    start_count: int,
    workers: int,
    fast_stage_only: bool,
    native_worker_limit: int,
    batch_workers: int,
    elapsed_s: float,
    reused_runs: bool,
) -> dict[str, Any]:

    data = pd.DataFrame.from_records(rows)
    plot_paths: list[Path] = []
    by_scene = []
    actual_scene_count = int(data["scene"].nunique())

    for scene, scene_data in data.groupby("scene", sort=True):
        plot_path = output_dir / "plots" / f"scene_{int(str(scene)):03d}_multistart_density.png"
        save_scene_plot(scene_data, plot_path)
        plot_paths.append(plot_path)
        by_scene.append(scene_summary(scene_data, plot_path))

    ok = data[data["status"] == "ok"]
    summary = {
        "schema_version": 1,
        "canonical_command": CANONICAL_COMMAND,
        "scene_count": actual_scene_count,
        "starts_per_scene": start_count,
        "row_count": int(len(data)),
        "expected_row_count": actual_scene_count * start_count,
        "ok": int(len(ok)),
        "converged": int(data["converged"].sum()),
        "workers": workers,
        "native_worker_limit_env": NATIVE_WORKER_LIMIT_ENV,
        "native_worker_limit": native_worker_limit,
        "batch_workers": batch_workers,
        "elapsed_s": elapsed_s,
        "reused_runs": reused_runs,
        "reference_cases": oe_cases.manifest_path(),
        "scene_sample_count": oe_cases.scene_sample_count(),
        "seed": oe_cases.seed(),
        "start_grid": {
            "aerosol_optical_depth": list(START_AOD_RANGE),
            "aerosol_mid_pressure_hpa": [
                START_PRESSURE_LOWER_HPA,
                "scene surface_pressure_hpa - 100",
            ],
            "shape": (
                "square tensor grid when start_count is a perfect square; "
                "otherwise deterministic Latin hypercube"
            ),
        },
        "prior_policy": (
            "Each grid point is both the OE a priori state and the optimizer initial state."
        ),
        "batching": {
            "fast_stage_only_uses_native_batch": fast_stage_only,
            "native_start_workers": batch_workers,
            "cache_boundary": (
                "output-dir/runs.csv is reused across reruns; existing scene/start rows are skipped"
            ),
        },
        "fast_mode": {
            "method": "case.optimisation.fastmode.enabled = True",
            "fast_stage_only": fast_stage_only,
            "note": (
                "Uses the case-owned fast-mode OE path, including sparse fast-stage "
                "sampling. The sparse full-physics final correction is disabled only "
                "when --fast-stage-only is passed."
            ),
        },
        "outputs": {
            "runs_csv": stable_repo_path(output_dir / "runs.csv"),
            "summary_json": stable_repo_path(output_dir / "summary.json"),
            "plots": [stable_repo_path(path) for path in plot_paths],
        },
        "plot_style": {
            "kind": "interpolated_start_to_retrieval_trajectory_density",
            "color": "relative_trajectory_density",
            "density_cells": [TRAJECTORY_AOD_CELLS, TRAJECTORY_PRESSURE_CELLS],
            "gaussian_sigma_cells": TRAJECTORY_GAUSSIAN_SIGMA,
        },
        "retrieval_s": stats(ok["retrieval_s"].to_list()),
        "batch_wall_s": stats(ok["batch_wall_s"].to_list()) if "batch_wall_s" in ok else stats([]),
        "by_scene": by_scene,
    }

    return summary


def validate_summary(summary: dict[str, Any]) -> None:

    failures = []

    if summary["row_count"] != summary["expected_row_count"]:
        failures.append(
            f"row_count={summary['row_count']} expected={summary['expected_row_count']}"
        )

    if summary["ok"] != summary["expected_row_count"]:
        failures.append(f"ok={summary['ok']} expected={summary['expected_row_count']}")

    if len(summary["outputs"]["plots"]) != summary["scene_count"]:
        failures.append(
            f"plots={len(summary['outputs']['plots'])} expected={summary['scene_count']}"
        )

    for path in summary["outputs"]["plots"]:
        if not (REPO_ROOT / path).is_file():
            failures.append(f"missing plot {path}")

    if failures:
        raise SystemExit("multi-start fast-mode retrieval failed: " + "; ".join(failures))


def main() -> None:

    args = parse_args()

    if args.scene_count <= 0:
        raise SystemExit("--scene-count must be positive")

    if args.start_count <= 0:
        raise SystemExit("--start-count must be positive")

    if args.workers <= 0:
        raise SystemExit("--workers must be positive")

    if args.native_worker_limit <= 0:
        raise SystemExit("--native-worker-limit must be positive")

    if args.batch_workers <= 0:
        raise SystemExit("--batch-workers must be positive")

    os.environ[NATIVE_WORKER_LIMIT_ENV] = str(args.native_worker_limit)
    scene_rows = selected_scene_rows(args)
    output_dir = resolve_output_dir(args, scene_rows=scene_rows)
    start = time.perf_counter()
    existing_summary_path = output_dir / "summary.json"
    runs_path = output_dir / "runs.csv"

    if args.reuse_runs:
        rows = read_runs(runs_path)
        elapsed_s = time.perf_counter() - start
        reused_runs = True

        if existing_summary_path.is_file():
            import json

            previous = json.loads(existing_summary_path.read_text())
            elapsed_s = float(previous.get("elapsed_s", elapsed_s))
    else:
        existing_rows = read_runs(runs_path) if runs_path.is_file() else []
        new_rows = run_all_scenes(
            scene_rows,
            start_count=args.start_count,
            workers=args.workers,
            fast_stage_only=args.fast_stage_only,
            batch_workers=args.batch_workers,
            existing_rows=existing_rows,
            checkpoint_path=runs_path if args.workers == 1 else None,
        )
        elapsed_s = time.perf_counter() - start
        rows = merge_rows(existing_rows, new_rows)
        write_runs(runs_path, rows)
        reused_runs = bool(existing_rows)

    summary = build_summary(
        rows,
        output_dir=output_dir,
        scene_count=len(scene_rows),
        start_count=starts_per_scene(rows, args.start_count),
        workers=args.workers,
        fast_stage_only=args.fast_stage_only,
        native_worker_limit=args.native_worker_limit,
        batch_workers=args.batch_workers,
        elapsed_s=elapsed_s,
        reused_runs=reused_runs,
    )
    write_json(output_dir / "summary.json", summary)
    validate_summary(summary)
    print(
        f"wrote {summary['row_count']} retrieval rows and "
        f"{len(summary['outputs']['plots'])} plots to {stable_repo_path(output_dir)}",
        flush=True,
    )


if __name__ == "__main__":
    main()
