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
from pathlib import Path
from typing import Any

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
DATA_DIR = REPO_ROOT / "validation" / "optimal_estimation" / "data"
REFERENCE_DATA_DIR = DATA_DIR / "reference"
OUTPUTS_DIR = REPO_ROOT / "validation" / "outputs" / "optimal_estimation"
REFERENCE_PATH = REFERENCE_DATA_DIR / "disamar_o2a_two_state_reference.json"
SUMMARY_PATH = OUTPUTS_DIR / "zdisamar_o2a_two_state_summary.json"
TIMING_PATH = OUTPUTS_DIR / "zdisamar_o2a_two_state_benchmark.json"

sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

import zdisamar as zd  # noqa: E402
from zdisamar.inverse_method import optimal_estimation  # noqa: E402
from zdisamar.inverse_method.optimal_estimation import o2a as o2a_optimal_estimation  # noqa: E402
from zdisamar.inverse_method.optimal_estimation.covariance_space import (  # noqa: E402
    build_covariance_space,
)

from validation.common.o2a_reference_case import build_o2a_case  # noqa: E402
from validation.common.paths import write_json  # noqa: E402
from validation.common.timing import PhaseTimer  # noqa: E402

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


def assert_altitude_jacobian_matches_finite_difference(
    case: zd.O2AInput,
    state_vector,
) -> None:
    inverse_model = optimal_estimation.O2AInverseForwardModel(case)
    state = state_vector.prior_state()
    with zd.prepare(inverse_model.settings_for_state(state, state_vector)) as prepared:
        evaluation = o2a_optimal_estimation.evaluate_prepared_reflectance(
            prepared,
            state_vector.jacobian_names,
        )

    eps_km = 1.0e-2
    plus_state = np.array(state, copy=True)
    plus_state[1] += eps_km
    minus_state = np.array(state, copy=True)
    minus_state[1] -= eps_km
    with zd.prepare(inverse_model.settings_for_state(plus_state, state_vector)) as prepared:
        plus = o2a_optimal_estimation.evaluate_prepared_reflectance(
            prepared,
            state_vector.jacobian_names,
        )
    with zd.prepare(inverse_model.settings_for_state(minus_state, state_vector)) as prepared:
        minus = o2a_optimal_estimation.evaluate_prepared_reflectance(
            prepared,
            state_vector.jacobian_names,
        )

    finite_difference = (plus.reflectance - minus.reflectance) / (2.0 * eps_km)
    altitude_index = state_vector.names.index("aerosol_layer_top_altitude_km")
    max_abs_residual = np.max(
        np.abs(evaluation.reflectance_jacobian[:, altitude_index] - finite_difference)
    )
    assert max_abs_residual <= 5.0e-5


def assert_gauss_newton_retains_prior_precision_nullspace() -> None:
    problem = build_covariance_space(
        previous=np.zeros(2, dtype=np.float64),
        prior=np.zeros(2, dtype=np.float64),
        residual=np.array([1.0], dtype=np.float64),
        jacobian=np.array([[2.0, 0.0]], dtype=np.float64),
        prior_covariance=np.eye(2, dtype=np.float64),
        measurement_variance=np.array([1.0], dtype=np.float64),
    )
    step = optimal_estimation.gauss_newton_step(
        problem,
        prior=np.zeros(2, dtype=np.float64),
        jacobian=np.array([[2.0, 0.0]], dtype=np.float64),
        measurement_variance=np.array([1.0], dtype=np.float64),
        max_change_transformed_state=100.0,
    )
    assert np.allclose(step.posterior_precision, np.array([[5.0, 0.0], [0.0, 1.0]]))
    assert np.allclose(step.posterior_covariance, np.array([[0.2, 0.0], [0.0, 1.0]]))


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
    forward_session: zd.O2AForwardSession | None = None,
) -> optimal_estimation.Result:
    inverse_model = optimal_estimation.O2AInverseForwardModel(
        case,
        forward_session=forward_session,
    )
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
    result_iterations: list[JsonObject],
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
    session_result: optimal_estimation.Result | None = None,
) -> JsonObject:
    report: JsonObject = {
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
    if session_result is not None:
        baseline_forward_s = sum(timing.forward_model_and_jacobian_s for timing in result.timing)
        session_forward_s = sum(
            timing.forward_model_and_jacobian_s for timing in session_result.timing
        )
        report["session_reuse"] = {
            "forward_model_and_jacobian_s": session_forward_s,
            "baseline_forward_model_and_jacobian_s": baseline_forward_s,
            "forward_model_and_jacobian_speedup_pct": (
                100.0 * (baseline_forward_s - session_forward_s) / baseline_forward_s
                if baseline_forward_s
                else 0.0
            ),
            "iterations": [
                {
                    "index": timing.index,
                    "forward_model_and_jacobian_s": timing.forward_model_and_jacobian_s,
                    "solver_update_s": timing.solver_update_s,
                    "total_iteration_s": timing.total_iteration_s,
                }
                for timing in session_result.timing
            ],
        }
    return report


def retrieval_mode_timing(
    phase_timings: dict[str, float],
    result: optimal_estimation.Result,
    session_result: optimal_estimation.Result,
) -> JsonObject:
    non_session_retrieval_s = phase_timings["retrieval_s"]
    session_setup_s = phase_timings["session_create_s"]
    session_reused_retrieval_s = phase_timings["session_reuse_retrieval_s"]
    session_first_use_retrieval_s = session_setup_s + session_reused_retrieval_s
    non_session_forward_s = sum(timing.forward_model_and_jacobian_s for timing in result.timing)
    session_forward_s = sum(timing.forward_model_and_jacobian_s for timing in session_result.timing)
    return {
        "non_session": {
            "retrieval_s": non_session_retrieval_s,
            "forward_model_and_jacobian_s": non_session_forward_s,
            "iterations": result.iterations,
        },
        "session": {
            "setup_s": session_setup_s,
            "reused_retrieval_s": session_reused_retrieval_s,
            "first_use_retrieval_s": session_first_use_retrieval_s,
            "forward_model_and_jacobian_s": session_forward_s,
            "iterations": session_result.iterations,
        },
        "speedup_pct": {
            "session_reused_forward_vs_non_session_forward": (
                100.0 * (non_session_forward_s - session_forward_s) / non_session_forward_s
                if non_session_forward_s
                else 0.0
            ),
            "session_first_use_retrieval_vs_non_session_retrieval": (
                100.0
                * (non_session_retrieval_s - session_first_use_retrieval_s)
                / non_session_retrieval_s
                if non_session_retrieval_s
                else 0.0
            ),
        },
    }


def print_retrieval_mode_timing(report: JsonObject) -> None:
    modes = report["retrieval_modes"]
    non_session = modes["non_session"]
    session = modes["session"]
    speedup = modes["speedup_pct"]
    print("Retrieval mode timing:")
    print(
        "  Non-session retrieval: "
        f"{non_session['retrieval_s']:.6f} s total, "
        f"{non_session['forward_model_and_jacobian_s']:.6f} s forward+jacobian, "
        f"{non_session['iterations']} iterations"
    )
    print(
        "  Session first use: "
        f"{session['first_use_retrieval_s']:.6f} s total "
        f"= {session['setup_s']:.6f} s setup/warm + "
        f"{session['reused_retrieval_s']:.6f} s retrieval loop"
    )
    print(
        "  Session reused retrieval loop: "
        f"{session['reused_retrieval_s']:.6f} s total, "
        f"{session['forward_model_and_jacobian_s']:.6f} s forward+jacobian, "
        f"{session['iterations']} iterations"
    )
    print(
        "  Session reused forward+jacobian speedup vs non-session: "
        f"{speedup['session_reused_forward_vs_non_session_forward']:.2f}%"
    )
    print(
        "  Session first-use retrieval speedup vs non-session retrieval: "
        f"{speedup['session_first_use_retrieval_vs_non_session_retrieval']:.2f}%"
    )


def session_matches_result(
    baseline: optimal_estimation.Result,
    session_result: optimal_estimation.Result,
) -> bool:
    return bool(
        baseline.converged == session_result.converged
        and baseline.iterations == session_result.iterations
        and baseline.state_names == session_result.state_names
        and np.array_equal(baseline.state, session_result.state)
        and np.array_equal(baseline.posterior_covariance, session_result.posterior_covariance)
        and np.array_equal(baseline.averaging_kernel, session_result.averaging_kernel)
        and iteration_records(baseline) == iteration_records(session_result)
    )


def build_summary(
    reference: JsonObject,
    result: optimal_estimation.Result,
    profile,
    layer_thickness: float,
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
        "passes_disamar_two_state_fixture": passed,
    }


def main() -> int:
    timer = PhaseTimer()

    with timer.phase("load_reference_s"):
        reference = json.loads(REFERENCE_PATH.read_text())

    with timer.phase("build_case_s"):
        case = build_o2a_case(zd, jacobian_reference_layer=True)

    with timer.phase("build_pressure_altitude_profile_s"):
        profile = o2a_optimal_estimation.pressure_altitude_profile_from_prepared_grid(case)

    with timer.phase("build_state_vector_s"):
        state_vector = build_state_vector(case, reference, profile)
        assert_altitude_jacobian_matches_finite_difference(case, state_vector)
        assert_gauss_newton_retains_prior_precision_nullspace()

    with timer.phase("boundary_contiguity_check_s"):
        assert_layer_boundaries_are_contiguous(case, state_vector, reference["a_priori"])

    with timer.phase("build_measurement_s"):
        measurement = build_measurement(case, reference)

    with timer.phase("retrieval_s"):
        result = run_retrieval(case, state_vector, measurement)
    with timer.phase("session_create_s"):
        session = zd.o2a_forward_session(case)
    try:
        with timer.phase("session_reuse_retrieval_s"):
            session_result = run_retrieval(
                case,
                state_vector,
                measurement,
                forward_session=session,
            )
    finally:
        session.close()
    layer_thickness = (
        case.aerosol.placement.bottom_pressure_hpa - case.aerosol.placement.top_pressure_hpa
    )
    with timer.phase("build_summary_s"):
        summary = build_summary(reference, result, profile, layer_thickness)
        session_summary = build_summary(reference, session_result, profile, layer_thickness)
        summary["session_reuse"] = {
            "passes_disamar_two_state_fixture": session_summary["passes_disamar_two_state_fixture"],
            "matches_baseline_result": session_matches_result(result, session_result),
            "iterations": session_result.iterations,
            "converged": session_result.converged,
            "retrieved": session_summary["retrieved"],
            "absolute_differences": session_summary["absolute_differences"],
        }

    with timer.phase("write_summary_s"):
        write_json(SUMMARY_PATH, summary)
    phase_timings = timer.finish()
    timing = timing_report(phase_timings, result, session_result)
    timing["retrieval_modes"] = retrieval_mode_timing(phase_timings, result, session_result)
    write_json(TIMING_PATH, timing)
    print_retrieval_mode_timing(timing)
    assert summary["passes_disamar_two_state_fixture"], json.dumps(
        summary, indent=2, sort_keys=True
    )
    assert summary["session_reuse"]["passes_disamar_two_state_fixture"], json.dumps(
        summary["session_reuse"], indent=2, sort_keys=True
    )
    assert summary["session_reuse"]["matches_baseline_result"], json.dumps(
        summary["session_reuse"], indent=2, sort_keys=True
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
