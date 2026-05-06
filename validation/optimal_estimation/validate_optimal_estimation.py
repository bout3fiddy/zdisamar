#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "numpy>=2.2",
# ]
# ///

from __future__ import annotations

import json
import sys
import time
from pathlib import Path
from typing import Any

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
SCRIPT_ROOT = REPO_ROOT / "scripts" / "testing_harness"
DATA_DIR = REPO_ROOT / "validation" / "optimal_estimation" / "data"
REFERENCE_PATH = DATA_DIR / "disamar_o2a_two_state_reference.json"
SUMMARY_PATH = DATA_DIR / "zdisamar_o2a_two_state_summary.json"

sys.path[:0] = [str(PYTHON_ROOT), str(SCRIPT_ROOT)]

import zdisamar as zd  # noqa: E402
from o2a_python_case import build_o2a_case  # noqa: E402
from zdisamar.inverse_method import optimal_estimation  # noqa: E402
from zdisamar.inverse_method.optimal_estimation import o2a as o2a_optimal_estimation  # noqa: E402

JsonObject = dict[str, Any]


def build_state_vector(
    case: zd.O2AInput,
    reference: JsonObject,
    profile: optimal_estimation.PressureAltitudeProfile,
):
    prior = reference["a_priori"]
    layer_thickness = (
        case.aerosol.placement.bottom_pressure_hpa - case.aerosol.placement.top_pressure_hpa
    )
    return optimal_estimation.StateVector(
        [
            optimal_estimation.AerosolOpticalDepth(
                initial=float(prior["aerosol_optical_depth"]),
                prior=float(prior["aerosol_optical_depth"]),
                variance=1.0,
                lower=0.0,
            ),
            optimal_estimation.AerosolLayerTopAltitude(
                initial=float(prior["aerosol_layer_top_altitude_km"]),
                prior=float(prior["aerosol_layer_top_altitude_km"]),
                variance=float(prior["aerosol_layer_top_altitude_variance_km2"]),
                pressure_thickness_hpa=layer_thickness,
                interval_index_1based=case.aerosol.placement.interval_index_1based,
                pressure_altitude_profile=profile,
            ),
        ]
    )


def assert_layer_boundaries_are_contiguous(
    case: zd.O2AInput,
    state_vector,
    prior: JsonObject,
) -> None:
    inverse_model = optimal_estimation.O2AInverseForwardModel(case)
    moved_case = inverse_model.settings_for_state(
        np.array(
            [
                float(prior["aerosol_optical_depth"]),
                float(prior["aerosol_layer_top_altitude_km"]) + 0.02,
            ]
        ),
        state_vector,
    )
    # The altitude state is written back as pressure boundaries. This check
    # catches broken interval updates before the retrieval can hide them behind
    # a plausible-looking spectrum.
    assert (
        moved_case.atmosphere.intervals[0].bottom_pressure_hpa
        == moved_case.atmosphere.intervals[1].top_pressure_hpa
    )
    assert (
        moved_case.atmosphere.intervals[1].bottom_pressure_hpa
        == moved_case.atmosphere.intervals[2].top_pressure_hpa
    )


def build_measurement(
    case: zd.O2AInput,
    reference: JsonObject,
) -> optimal_estimation.Measurement:
    # The measurement is simulated once from the truth scene. The inverse pass
    # only sees this spectrum plus covariance, so a wrong retrieval trajectory
    # cannot be excused by regenerating the target at each state.
    noise_reference = reference["measurement_noise"]
    with zd.prepare(case) as prepared:
        return o2a_optimal_estimation.measurement_from_sun_normalized_radiance_noise(
            prepared,
            wavelength_nm=np.asarray(
                noise_reference["wavelength_nm"],
                dtype=np.float64,
            ),
            sun_normalized_radiance_noise=np.asarray(
                noise_reference["assumed_noise_sun_normalized_radiance"],
                dtype=np.float64,
            ),
        )


def run_retrieval(
    case: zd.O2AInput,
    state_vector,
    measurement: optimal_estimation.Measurement,
) -> optimal_estimation.Result:
    inverse_model = optimal_estimation.O2AInverseForwardModel(case)
    return optimal_estimation.disamar_oe(
        inverse_model=inverse_model,
        measurement=measurement,
        state_vector=state_vector,
        controls=optimal_estimation.RetrievalControls.from_disamar_retrieval_specs(),
    )


def iteration_records(
    result: optimal_estimation.Result,
) -> list[dict[str, float | int | bool | None]]:
    return [
        {
            "index": iteration.index,
            "aerosol_optical_depth": float(iteration.state[0]),
            "aerosol_layer_top_altitude_km": float(iteration.state[1]),
            "state_vector_convergence": iteration.state_vector_convergence,
            "chi2_reflectance": iteration.chi2_reflectance,
            "chi2_state_vector": iteration.chi2_state_vector,
            "snr_normal": iteration.snr_normal,
        }
        for iteration in result.history
    ]


def build_retrieved_state(
    result: optimal_estimation.Result,
    profile,
    layer_thickness: float,
) -> dict[str, float]:
    top_altitude = result.value("aerosol_layer_top_altitude_km")
    top_pressure = profile.pressure_at_altitude(top_altitude)
    bottom_pressure = top_pressure + layer_thickness
    return {
        "aerosol_optical_depth": result.value("aerosol_optical_depth"),
        "aerosol_layer_top_altitude_km": top_altitude,
        "aerosol_layer_top_pressure_hpa": top_pressure,
        "aerosol_layer_bottom_pressure_hpa": bottom_pressure,
        "aerosol_layer_mid_pressure_hpa": 0.5 * (top_pressure + bottom_pressure),
    }


def within_tolerance(value: float, expected: float, tolerance: float) -> bool:
    return abs(value - expected) <= tolerance


def iteration_matches(
    reference_iterations: list[JsonObject],
    result_iterations: list[dict[str, float | int | bool | None]],
    tolerances: JsonObject,
) -> bool:
    if len(reference_iterations) != len(result_iterations):
        return False
    state_tolerances = tolerances["iteration_state_abs"]
    diagnostic_tolerances = tolerances.get("iteration_diagnostic_abs", {})
    for expected, actual in zip(reference_iterations, result_iterations, strict=True):
        if int(expected["index"]) != int(actual["index"]):
            return False
        if not within_tolerance(
            float(actual["aerosol_optical_depth"]),
            float(expected["aerosol_optical_depth"]),
            float(state_tolerances["aerosol_optical_depth"]),
        ):
            return False
        if not within_tolerance(
            float(actual["aerosol_layer_top_altitude_km"]),
            float(expected["intervalDP_top_altitude_km"]),
            float(state_tolerances["aerosol_layer_top_altitude_km"]),
        ):
            return False
        if "state_vector_convergence" in expected and not within_tolerance(
            float(actual["state_vector_convergence"]),
            float(expected["state_vector_convergence"]),
            float(diagnostic_tolerances["state_vector_convergence"]),
        ):
            return False
        if "snr_normal" in expected and bool(actual["snr_normal"]) != bool(expected["snr_normal"]):
            return False
    return True


def diagnostics_match(
    reference: JsonObject,
    result: optimal_estimation.Result,
    tolerances: JsonObject,
) -> bool:
    if "disamar" not in reference or not result.history:
        return True
    expected = reference["disamar"]
    actual = result.history[-1]
    diagnostic_tolerances = tolerances["final_diagnostic_abs"]
    return (
        within_tolerance(
            float(actual.state_vector_convergence),
            float(expected["state_vector_convergence"]),
            float(diagnostic_tolerances["state_vector_convergence"]),
        )
        and within_tolerance(
            float(actual.chi2_reflectance),
            float(expected["chi2_reflectance"]),
            float(diagnostic_tolerances["chi2_reflectance"]),
        )
        and within_tolerance(
            float(actual.chi2_state_vector),
            float(expected["chi2_state_vector"]),
            float(diagnostic_tolerances["chi2_state_vector"]),
        )
        and bool(result.converged) == bool(expected["solution_has_converged"])
    )


def timing_report(
    phase_timings: dict[str, float],
    result: optimal_estimation.Result,
) -> JsonObject:
    return {
        "phases_s": phase_timings,
        "iterations": [
            {
                "index": timing.index,
                "forward_model_and_jacobian_s": timing.forward_model_and_jacobian_s,
                "solver_update_s": timing.solver_update_s,
                "total_iteration_s": timing.total_iteration_s,
            }
            for timing in result.timing
        ],
    }


def build_summary(
    reference: JsonObject,
    result: optimal_estimation.Result,
    profile,
    layer_thickness: float,
    phase_timings: dict[str, float],
) -> JsonObject:
    retrieved = reference["retrieved"]
    tolerances = reference["tolerances"]
    retrieved_state = build_retrieved_state(result, profile, layer_thickness)
    aod_abs_diff = abs(
        retrieved_state["aerosol_optical_depth"] - float(retrieved["aerosol_optical_depth"])
    )
    top_altitude_abs_diff = abs(
        retrieved_state["aerosol_layer_top_altitude_km"]
        - float(retrieved["aerosol_layer_top_altitude_km"])
    )
    top_pressure_abs_diff = abs(
        retrieved_state["aerosol_layer_top_pressure_hpa"]
        - float(retrieved["aerosol_layer_top_pressure_hpa"])
    )
    pressure_abs_diff = abs(
        retrieved_state["aerosol_layer_mid_pressure_hpa"]
        - float(retrieved["aerosol_layer_mid_pressure_hpa"])
    )
    iteration_match = result.iterations == int(reference["expected_iterations"])
    aod_match = within_tolerance(
        retrieved_state["aerosol_optical_depth"],
        float(retrieved["aerosol_optical_depth"]),
        float(tolerances["aerosol_optical_depth_abs"]),
    )
    top_altitude_match = within_tolerance(
        retrieved_state["aerosol_layer_top_altitude_km"],
        float(retrieved["aerosol_layer_top_altitude_km"]),
        float(tolerances["aerosol_layer_top_altitude_km_abs"]),
    )
    top_pressure_match = within_tolerance(
        retrieved_state["aerosol_layer_top_pressure_hpa"],
        float(retrieved["aerosol_layer_top_pressure_hpa"]),
        float(tolerances["aerosol_layer_top_pressure_hpa_abs"]),
    )
    pressure_match = within_tolerance(
        retrieved_state["aerosol_layer_mid_pressure_hpa"],
        float(retrieved["aerosol_layer_mid_pressure_hpa"]),
        float(tolerances["aerosol_layer_mid_pressure_hpa_abs"]),
    )
    history = iteration_records(result)
    history_match = iteration_matches(reference["iterations"], history, tolerances)
    final_diagnostics_match = diagnostics_match(reference, result, tolerances)
    passed = bool(
        iteration_match
        and aod_match
        and top_altitude_match
        and top_pressure_match
        and pressure_match
        and history_match
        and final_diagnostics_match
        and result.converged
    )

    return {
        "validation_case": "disamar_o2a_two_state_optimal_estimation",
        "state_names": list(result.state_names),
        "iterations": result.iterations,
        "converged": result.converged,
        "expected_iterations": reference["expected_iterations"],
        "iteration_match": iteration_match,
        "history_match": history_match,
        "final_diagnostics_match": final_diagnostics_match,
        "retrieved": retrieved_state,
        "reference": retrieved,
        "history": history,
        "reference_history": reference["iterations"],
        "absolute_differences": {
            "aerosol_optical_depth": aod_abs_diff,
            "aerosol_layer_top_altitude_km": top_altitude_abs_diff,
            "aerosol_layer_top_pressure_hpa": top_pressure_abs_diff,
            "aerosol_layer_mid_pressure_hpa": pressure_abs_diff,
        },
        "tolerances": tolerances,
        "posterior_covariance": np.asarray(result.posterior_covariance).tolist(),
        "averaging_kernel": np.asarray(result.averaging_kernel).tolist(),
        "timing": timing_report(phase_timings, result),
        "passes_disamar_two_state_fixture": passed,
    }


def main() -> int:
    total_start = time.perf_counter()
    phase_timings: dict[str, float] = {}

    phase_start = time.perf_counter()
    reference = json.loads(REFERENCE_PATH.read_text())
    phase_timings["load_reference_s"] = time.perf_counter() - phase_start

    phase_start = time.perf_counter()
    case = build_o2a_case(zd, jacobian_reference_layer=True)
    phase_timings["build_case_s"] = time.perf_counter() - phase_start

    phase_start = time.perf_counter()
    profile = o2a_optimal_estimation.pressure_altitude_profile_from_prepared_grid(case)
    phase_timings["build_pressure_altitude_profile_s"] = time.perf_counter() - phase_start

    phase_start = time.perf_counter()
    state_vector = build_state_vector(case, reference, profile)
    phase_timings["build_state_vector_s"] = time.perf_counter() - phase_start

    phase_start = time.perf_counter()
    assert_layer_boundaries_are_contiguous(case, state_vector, reference["a_priori"])
    phase_timings["boundary_contiguity_check_s"] = time.perf_counter() - phase_start

    phase_start = time.perf_counter()
    measurement = build_measurement(case, reference)
    phase_timings["build_measurement_s"] = time.perf_counter() - phase_start

    phase_start = time.perf_counter()
    result = run_retrieval(case, state_vector, measurement)
    phase_timings["retrieval_s"] = time.perf_counter() - phase_start
    layer_thickness = (
        case.aerosol.placement.bottom_pressure_hpa - case.aerosol.placement.top_pressure_hpa
    )
    phase_start = time.perf_counter()
    summary = build_summary(
        reference,
        result,
        profile,
        layer_thickness,
        phase_timings,
    )
    phase_timings["build_summary_s"] = time.perf_counter() - phase_start

    phase_timings["total_s"] = time.perf_counter() - total_start
    summary["timing"] = timing_report(phase_timings, result)
    write_start = time.perf_counter()
    SUMMARY_PATH.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    phase_timings["write_summary_s"] = time.perf_counter() - write_start
    phase_timings["total_s"] = time.perf_counter() - total_start
    summary["timing"] = timing_report(phase_timings, result)
    SUMMARY_PATH.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    assert summary["passes_disamar_two_state_fixture"], json.dumps(
        summary, indent=2, sort_keys=True
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
