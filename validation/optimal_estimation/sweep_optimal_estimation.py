#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "numpy>=2.2",
# ]
# ///

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

from zdisamar import rtm  # noqa: E402
from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe  # noqa: E402
from zdisamar.wavelength_bands import o2a  # noqa: E402

from validation.common.paths import stable_repo_path, write_json  # noqa: E402
from validation.o2a import baseline as oe_baseline  # noqa: E402
from validation.o2a.case import build_o2a_case  # noqa: E402
from validation.o2a.measurement_noise import (  # noqa: E402
    measurement_from_o2a_baseline_noise,
)
from validation.optimal_estimation import reference_cases as oe_cases  # noqa: E402
from validation.optimal_estimation import setup as oe_setup  # noqa: E402

RUN_COUNT = 5


def retrieve_scene(
    case: o2a.O2ACase,
    truth: dict[str, float],
    initial: dict[str, float],
):

    measurement = measurement_from_o2a_baseline_noise(case)
    profile = o2a_oe.pressure_altitude_profile_from_case(case)

    state_vector = oe_setup.aerosol_two_state_vector(
        initial=initial,
        profile=profile,
        surface_pressure_hpa=truth["surface_pressure_hpa"],
    )

    with rtm.SessionCache(case) as cache:
        return o2a_oe.disamar_oe(
            case=case,
            measurement=measurement,
            state_vector=state_vector,
            controls=oe_setup.retrieval_controls(),
            cache=cache,
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

    base = build_o2a_case(o2a, jacobian_reference_layer=True)
    oe_baseline.configure_case(base)
    rows: list[dict[str, Any]] = []
    start = time.perf_counter()

    for row in oe_cases.case_rows(count=RUN_COUNT):
        index = int(row["case"])
        truth = oe_cases.scene_from_row(row)
        case = oe_setup.build_scene(base, index=index, id_prefix="o2a_oe_sweep", scene=truth)
        initial = oe_cases.initial_from_row(row)
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
        "reference_cases": oe_cases.manifest_path(),
        "seed": oe_cases.seed(),
        "scene_sample_count": oe_cases.scene_sample_count(),
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
            "aerosol_layer_thickness_hpa": oe_baseline.LAYER_THICKNESS_HPA,
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


def validate_sweep_success(summary: dict[str, Any]) -> list[str]:

    run_count = int(summary["run_count"])
    ok_count = int(summary["ok_count"])
    converged_count = int(summary["converged_count"])
    failures = []

    if ok_count != run_count:
        failures.append(f"{run_count - ok_count} retrievals returned error rows")

    if converged_count != run_count:
        failures.append(f"{run_count - converged_count} retrievals did not converge")

    return failures


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
    failures = validate_sweep_success(summary)

    if failures:
        print("; ".join(failures), file=sys.stderr)

        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
