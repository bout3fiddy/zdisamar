#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "numpy>=2.2",
# ]
# ///

import copy
import csv
import math
import statistics
import sys
import time
from pathlib import Path
from typing import Any

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
OUTPUTS_DIR = REPO_ROOT / "validation" / "outputs" / "optimal_estimation"
SUMMARY_PATH = OUTPUTS_DIR / "zdisamar_o2a_sweep_summary.json"
CSV_PATH = OUTPUTS_DIR / "zdisamar_o2a_sweep_runs.csv"

sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

import zdisamar as zd  # noqa: E402
from zdisamar.inverse_method import optimal_estimation  # noqa: E402
from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe  # noqa: E402

from validation.common import o2a_retrieval_baseline as oe_baseline  # noqa: E402
from validation.common.o2a_reference_case import build_o2a_case  # noqa: E402
from validation.common.paths import stable_repo_path, write_json  # noqa: E402

RUN_COUNT = 5
RNG_SEED = 20260507
LAYER_THICKNESS_HPA = oe_baseline.LAYER_THICKNESS_HPA


def uniform_lhs(rng: np.random.Generator, low: float, high: float, count: int) -> np.ndarray:
    values = (np.arange(count, dtype=np.float64) + rng.random(count)) / count
    rng.shuffle(values)
    return low + values * (high - low)


def update_layer_pressures(case: zd.O2AInput, mid_pressure_hpa: float) -> None:
    top_pressure = mid_pressure_hpa - 0.5 * LAYER_THICKNESS_HPA
    bottom_pressure = mid_pressure_hpa + 0.5 * LAYER_THICKNESS_HPA
    case.aerosol.placement.top_pressure_hpa = top_pressure
    case.aerosol.placement.bottom_pressure_hpa = bottom_pressure
    for interval in case.atmosphere.intervals:
        if interval.index_1based == 1:
            interval.bottom_pressure_hpa = top_pressure
        elif interval.index_1based == 2:
            interval.top_pressure_hpa = top_pressure
            interval.bottom_pressure_hpa = bottom_pressure
        elif interval.index_1based == 3:
            interval.top_pressure_hpa = bottom_pressure
            interval.bottom_pressure_hpa = case.surface.pressure_hpa


def build_scene(
    base: zd.O2AInput,
    *,
    index: int,
    solar_zenith_deg: float,
    viewing_zenith_deg: float,
    relative_azimuth_deg: float,
    surface_pressure_hpa: float,
    surface_albedo: float,
    aerosol_optical_depth: float,
    aerosol_mid_pressure_hpa: float,
) -> zd.O2AInput:
    case = copy.deepcopy(base)
    case.metadata["id"] = f"o2a_oe_sweep_{index:03d}"
    case.scene_id = f"o2a_oe_sweep_{index:03d}"
    case.geometry.solar_zenith_deg = solar_zenith_deg
    case.geometry.viewing_zenith_deg = viewing_zenith_deg
    case.geometry.relative_azimuth_deg = relative_azimuth_deg
    case.surface.pressure_hpa = surface_pressure_hpa
    case.surface.albedo = surface_albedo
    case.aerosol.optical_depth_550_nm = aerosol_optical_depth
    case.aerosol.single_scatter_albedo = oe_baseline.AEROSOL_SINGLE_SCATTER_ALBEDO
    case.aerosol.asymmetry_factor = oe_baseline.AEROSOL_ASYMMETRY_FACTOR
    case.aerosol.angstrom_exponent = oe_baseline.AEROSOL_ANGSTROM_EXPONENT
    update_layer_pressures(case, aerosol_mid_pressure_hpa)
    return case


def sampled_scenes(count: int, seed: int) -> list[dict[str, float]]:
    rng = np.random.default_rng(seed)
    solar = uniform_lhs(rng, 25.0, 65.0, count)
    view = uniform_lhs(rng, 0.0, 50.0, count)
    azimuth = uniform_lhs(rng, 0.0, 180.0, count)
    surface_pressure = uniform_lhs(rng, 820.0, 1040.0, count)
    surface_albedo = uniform_lhs(rng, 0.05, 0.55, count)
    aerosol_optical_depth = np.exp(uniform_lhs(rng, math.log(0.10), math.log(2.0), count))
    mid_fraction = uniform_lhs(rng, 0.18, 0.78, count)
    scenes: list[dict[str, float]] = []
    for index in range(count):
        mid_min = 225.0
        mid_max = surface_pressure[index] - 100.0
        scenes.append(
            {
                "solar_zenith_deg": float(solar[index]),
                "viewing_zenith_deg": float(view[index]),
                "relative_azimuth_deg": float(azimuth[index]),
                "surface_pressure_hpa": float(surface_pressure[index]),
                "surface_albedo": float(surface_albedo[index]),
                "aerosol_optical_depth": float(aerosol_optical_depth[index]),
                "aerosol_mid_pressure_hpa": float(
                    mid_min + mid_fraction[index] * (mid_max - mid_min)
                ),
            }
        )
    return scenes


def initial_aod(truth: float, index: int) -> float:
    factor = 1.12 if index % 2 == 0 else 0.88
    return min(5.0, max(0.02, truth * factor + 0.01))


def initial_mid_pressure(truth: float, surface_pressure: float, index: int) -> float:
    offset = [-25.0, -15.0, 15.0, 25.0][index % 4]
    return min(surface_pressure - 75.0, max(100.0, truth + offset))


def build_state_vector(
    truth: dict[str, float],
    initial: dict[str, float],
    profile: optimal_estimation.PressureAltitudeProfile,
) -> optimal_estimation.StateVector:
    return optimal_estimation.StateVector(
        [
            optimal_estimation.AerosolOpticalDepth(
                initial=initial["aerosol_optical_depth"],
                prior=initial["aerosol_optical_depth"],
                variance=0.8,
                lower=0.02,
                upper=5.0,
            ),
            optimal_estimation.AerosolLayerMidPressure(
                initial=initial["aerosol_mid_pressure_hpa"],
                prior=initial["aerosol_mid_pressure_hpa"],
                variance=150.0**2,
                thickness_hpa=LAYER_THICKNESS_HPA,
                interval_index_1based=2,
                pressure_altitude_profile=profile,
                lower=225.0,
                upper=truth["surface_pressure_hpa"] - 100.0,
            ),
        ]
    )


def measurement_from_baseline_snr(prepared) -> optimal_estimation.Measurement:
    with prepared.forward_model() as spectrum:
        wavelength_nm = spectrum.wavelength_nm.copy()
        reflectance = spectrum.reflectance.copy()
    reflectance_noise = np.maximum(
        np.abs(reflectance) * oe_baseline.REFLECTANCE_RELATIVE_NOISE,
        1.0e-12,
    )
    return optimal_estimation.Measurement(
        wavelength_nm=wavelength_nm,
        reflectance=reflectance,
        variance=reflectance_noise**2,
    )


def retrieve_scene(
    case: zd.O2AInput,
    truth: dict[str, float],
    initial: dict[str, float],
):
    with zd.prepare(case) as prepared:
        measurement = measurement_from_baseline_snr(prepared)
        profile = o2a_oe.pressure_altitude_profile_from_prepared(prepared)
    state_vector = build_state_vector(truth, initial, profile)
    with zd.o2a_forward_session(case) as session:
        return o2a_oe.disamar_oe(
            inverse_model=optimal_estimation.O2AInverseForwardModel(
                case,
                forward_session=session,
            ),
            measurement=measurement,
            state_vector=state_vector,
            controls=optimal_estimation.RetrievalControls.from_disamar_retrieval_specs(),
        )


def percentile(values: list[float], q: float) -> float:
    if not values:
        return math.nan
    return float(np.percentile(np.asarray(values, dtype=np.float64), q))


def stats(values: list[float]) -> dict[str, float]:
    return {
        "min": min(values) if values else math.nan,
        "median": statistics.median(values) if values else math.nan,
        "mean": statistics.fmean(values) if values else math.nan,
        "p90": percentile(values, 90.0),
        "max": max(values) if values else math.nan,
    }


def run_sweep() -> dict[str, Any]:
    base = build_o2a_case(zd, jacobian_reference_layer=True)
    oe_baseline.configure_case(base)
    rows: list[dict[str, Any]] = []
    start = time.perf_counter()
    for index, truth in enumerate(sampled_scenes(RUN_COUNT, RNG_SEED), start=1):
        case = build_scene(base, index=index, **truth)
        initial = {
            "aerosol_optical_depth": initial_aod(truth["aerosol_optical_depth"], index),
            "aerosol_mid_pressure_hpa": initial_mid_pressure(
                truth["aerosol_mid_pressure_hpa"],
                truth["surface_pressure_hpa"],
                index,
            ),
        }
        run_start = time.perf_counter()
        try:
            result = retrieve_scene(case, truth, initial)
            retrieval_s = time.perf_counter() - run_start
            retrieved_aod = result.value("aerosol_optical_depth")
            retrieved_mid_pressure = result.value("aerosol_layer_mid_pressure_hpa")
            status = "ok"
            error = ""
        except Exception as exc:  # noqa: BLE001 - recorded as validation evidence.
            retrieval_s = time.perf_counter() - run_start
            result = None
            retrieved_aod = math.nan
            retrieved_mid_pressure = math.nan
            status = "error"
            error = str(exc)
        row = {
            "index": index,
            "status": status,
            "error": error,
            **truth,
            "initial_aerosol_optical_depth": initial["aerosol_optical_depth"],
            "initial_aerosol_mid_pressure_hpa": initial["aerosol_mid_pressure_hpa"],
            "retrieved_aerosol_optical_depth": retrieved_aod,
            "retrieved_aerosol_mid_pressure_hpa": retrieved_mid_pressure,
            "aerosol_optical_depth_abs_error": abs(retrieved_aod - truth["aerosol_optical_depth"]),
            "aerosol_mid_pressure_abs_error_hpa": abs(
                retrieved_mid_pressure - truth["aerosol_mid_pressure_hpa"]
            ),
            "converged": bool(result.converged) if result is not None else False,
            "iterations": int(result.iterations) if result is not None else 0,
            "retrieval_s": retrieval_s,
            "forward_model_and_jacobian_s": (
                sum(t.forward_model_and_jacobian_s for t in result.timing)
                if result is not None
                else math.nan
            ),
            "final_state_vector_convergence": (
                result.history[-1].state_vector_convergence
                if result is not None and result.history
                else math.nan
            ),
        }
        rows.append(row)
        print(
            f"{index:03d}/{RUN_COUNT} {status} "
            f"conv={row['converged']} it={row['iterations']} "
            f"dt={retrieval_s:.3f}s "
            f"aod_err={row['aerosol_optical_depth_abs_error']:.3g} "
            f"midp_err={row['aerosol_mid_pressure_abs_error_hpa']:.3g}",
            flush=True,
        )

    ok_rows = [row for row in rows if row["status"] == "ok"]
    converged_rows = [row for row in ok_rows if row["converged"]]
    summary = {
        "case": f"o2a_aerosol_only_optimal_estimation_{RUN_COUNT}_scene_sweep",
        "paper_source": "https://doi.org/10.5194/amt-12-6619-2019",
        "seed": RNG_SEED,
        "parameter_ranges": {
            "solar_zenith_deg": [25.0, 65.0],
            "viewing_zenith_deg": [0.0, 50.0],
            "relative_azimuth_deg": [0.0, 180.0],
            "surface_pressure_hpa": [820.0, 1040.0],
            "surface_albedo": [0.05, 0.55],
            "aerosol_optical_depth": [0.10, 2.0],
            "aerosol_mid_pressure_hpa": (
                "sampled between 225 hPa and surface_pressure_hpa - 100 hPa"
            ),
            "aerosol_layer_thickness_hpa": LAYER_THICKNESS_HPA,
        },
        "run_count": len(rows),
        "ok_count": len(ok_rows),
        "converged_count": len(converged_rows),
        "converged_fraction": len(converged_rows) / len(rows),
        "total_wall_s": time.perf_counter() - start,
        "outputs": {
            "runs_csv": stable_repo_path(CSV_PATH),
            "summary_json": stable_repo_path(SUMMARY_PATH),
        },
        "stats": {
            "retrieval_s": stats([float(row["retrieval_s"]) for row in ok_rows]),
            "iterations": stats([float(row["iterations"]) for row in ok_rows]),
            "aerosol_optical_depth_abs_error": stats(
                [float(row["aerosol_optical_depth_abs_error"]) for row in ok_rows]
            ),
            "aerosol_mid_pressure_abs_error_hpa": stats(
                [float(row["aerosol_mid_pressure_abs_error_hpa"]) for row in ok_rows]
            ),
            "forward_model_and_jacobian_s": stats(
                [float(row["forward_model_and_jacobian_s"]) for row in ok_rows]
            ),
        },
        "worst_aod_abs_error_runs": sorted(
            ok_rows,
            key=lambda row: float(row["aerosol_optical_depth_abs_error"]),
            reverse=True,
        )[:10],
        "worst_mid_pressure_abs_error_runs": sorted(
            ok_rows,
            key=lambda row: float(row["aerosol_mid_pressure_abs_error_hpa"]),
            reverse=True,
        )[:10],
    }
    write_outputs(rows, summary)
    return summary


def write_outputs(rows: list[dict[str, Any]], summary: dict[str, Any]) -> None:
    OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)
    with CSV_PATH.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    write_json(SUMMARY_PATH, summary)


def assert_sweep_success(summary: dict[str, Any]) -> None:
    run_count = int(summary["run_count"])
    ok_count = int(summary["ok_count"])
    converged_count = int(summary["converged_count"])
    failures = []
    if ok_count != run_count:
        failures.append(f"{run_count - ok_count} retrievals returned error rows")
    if converged_count != run_count:
        failures.append(f"{run_count - converged_count} retrievals did not converge")
    if failures:
        raise AssertionError("; ".join(failures))


def main() -> int:
    if RUN_COUNT <= 0:
        raise ValueError("RUN_COUNT must be positive")
    summary = run_sweep()
    print("\nSweep summary:")
    print(f"  runs: {summary['run_count']}")
    print(f"  ok: {summary['ok_count']}")
    print(f"  converged: {summary['converged_count']} ({summary['converged_fraction']:.1%})")
    print(f"  total wall: {summary['total_wall_s']:.3f}s")
    print(f"  retrieval_s stats: {summary['stats']['retrieval_s']}")
    print(f"  AOD abs error stats: {summary['stats']['aerosol_optical_depth_abs_error']}")
    print(
        f"  mid-pressure abs error stats: {summary['stats']['aerosol_mid_pressure_abs_error_hpa']}"
    )
    print(f"  CSV: {stable_repo_path(CSV_PATH)}")
    print(f"  JSON: {stable_repo_path(SUMMARY_PATH)}")
    assert_sweep_success(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
