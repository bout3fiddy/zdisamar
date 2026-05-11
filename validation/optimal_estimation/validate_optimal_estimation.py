#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "numpy>=2.2",
# ]
# ///

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
from zdisamar.inverse_method.optimal_estimation.diagnostics import (  # noqa: E402
    final_diagnostics,
)

from validation.common import o2a_optimal_estimation_setup as oe_setup  # noqa: E402
from validation.common import o2a_retrieval_baseline as oe_baseline  # noqa: E402
from validation.common.o2a_measurement_noise import (  # noqa: E402
    measurement_from_o2a_baseline_noise,
)
from validation.common.o2a_reference_case import build_o2a_case  # noqa: E402
from validation.common.paths import write_json  # noqa: E402
from validation.common.timing import PhaseTimer  # noqa: E402

JsonObject = dict[str, Any]


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
                float(prior["aerosol_layer_mid_pressure_hpa"]) + 2.0,
            ]
        ),
        state_vector,
    )
    # The pressure state is written back as contiguous pressure boundaries. This
    # catches broken interval updates before the retrieval can hide them behind a
    # plausible-looking spectrum.
    assert (
        moved_case.atmosphere.intervals[0].bottom_pressure_hpa
        == moved_case.atmosphere.intervals[1].top_pressure_hpa
    )
    assert (
        moved_case.atmosphere.intervals[1].bottom_pressure_hpa
        == moved_case.atmosphere.intervals[2].top_pressure_hpa
    )


def assert_mid_pressure_jacobian_matches_finite_difference(
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

    eps_hpa = 0.5
    plus_state = np.array(state, copy=True)
    plus_state[1] += eps_hpa
    minus_state = np.array(state, copy=True)
    minus_state[1] -= eps_hpa
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

    finite_difference = (plus.reflectance - minus.reflectance) / (2.0 * eps_hpa)
    mid_pressure_index = state_vector.names.index("aerosol_layer_mid_pressure_hpa")
    scaled_jacobian = (
        evaluation.reflectance_jacobian[:, mid_pressure_index]
        * state_vector.jacobian_scales(state)[mid_pressure_index]
    )
    max_abs_residual = np.max(np.abs(scaled_jacobian - finite_difference))
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
        max_change_transformed_state=100.0,
    )
    assert np.allclose(step.posterior_precision, np.array([[5.0, 0.0], [0.0, 1.0]]))
    diagnostics = final_diagnostics(
        posterior_precision=step.posterior_precision,
        jacobian=np.array([[2.0, 0.0]], dtype=np.float64),
        measurement_variance=np.array([1.0], dtype=np.float64),
    )
    assert np.allclose(diagnostics.posterior_covariance, np.array([[0.2, 0.0], [0.0, 1.0]]))


def build_measurement(
    case: zd.O2AInput,
    reference: JsonObject,
) -> optimal_estimation.Measurement:
    # The measurement is simulated once from the truth scene. The inverse pass
    # only sees this spectrum plus retained O2 A baseline covariance, so a wrong
    # retrieval trajectory cannot be excused by regenerating the target at each
    # state.
    _ = reference
    with zd.prepare(case) as prepared:
        return measurement_from_o2a_baseline_noise(prepared)


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
        controls=oe_setup.retrieval_controls(),
    )


def iteration_records(
    result: optimal_estimation.Result,
) -> list[dict[str, float | int | bool | None]]:
    return [
        {
            "index": iteration.index,
            "aerosol_optical_depth": float(iteration.state[0]),
            "aerosol_layer_mid_pressure_hpa": float(iteration.state[1]),
            "state_vector_convergence": iteration.state_vector_convergence,
            "chi2_reflectance": iteration.chi2_reflectance,
            "chi2_state_vector": iteration.chi2_state_vector,
            "snr_normal": iteration.snr_normal,
        }
        for iteration in result.history
    ]


def build_retrieved_state(
    result: optimal_estimation.Result,
    layer_thickness: float,
) -> dict[str, float]:
    mid_pressure = result.value("aerosol_layer_mid_pressure_hpa")
    top_pressure = mid_pressure - 0.5 * layer_thickness
    bottom_pressure = mid_pressure + 0.5 * layer_thickness
    return {
        "aerosol_optical_depth": result.value("aerosol_optical_depth"),
        "aerosol_layer_top_pressure_hpa": top_pressure,
        "aerosol_layer_bottom_pressure_hpa": bottom_pressure,
        "aerosol_layer_mid_pressure_hpa": mid_pressure,
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
        if "aerosol_layer_mid_pressure_hpa" in expected and not within_tolerance(
            float(actual["aerosol_layer_mid_pressure_hpa"]),
            float(expected["aerosol_layer_mid_pressure_hpa"]),
            float(state_tolerances["aerosol_layer_mid_pressure_hpa"]),
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
    forward_model_and_jacobian_s = sum(
        timing.forward_model_and_jacobian_s for timing in result.timing
    )
    return {
        "phases_s": phase_timings,
        "retrieval": {
            "setup_s": phase_timings["session_create_s"],
            "retrieval_s": phase_timings["retrieval_s"],
            "first_use_retrieval_s": phase_timings["session_create_s"]
            + phase_timings["retrieval_s"],
            "forward_model_and_jacobian_s": forward_model_and_jacobian_s,
            "iterations": result.iterations,
        },
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


def print_retrieval_timing(report: JsonObject) -> None:
    retrieval = report["retrieval"]
    print("Fast session-backed retrieval timing:")
    print(
        "  Retrieval loop: "
        f"{retrieval['retrieval_s']:.6f} s total, "
        f"{retrieval['forward_model_and_jacobian_s']:.6f} s forward+jacobian, "
        f"{retrieval['iterations']} iterations"
    )
    print(
        "  First use including setup/warm: "
        f"{retrieval['first_use_retrieval_s']:.6f} s "
        f"= {retrieval['setup_s']:.6f} s setup/warm + "
        f"{retrieval['retrieval_s']:.6f} s retrieval loop"
    )


def build_summary(
    reference: JsonObject,
    result: optimal_estimation.Result,
    layer_thickness: float,
) -> JsonObject:
    retrieved = reference.get("truth", reference["retrieved"])
    tolerances = reference["tolerances"]
    retrieved_state = build_retrieved_state(result, layer_thickness)
    aod_abs_diff = abs(
        retrieved_state["aerosol_optical_depth"] - float(retrieved["aerosol_optical_depth"])
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
    truth_passed = bool(
        iteration_match and aod_match and top_pressure_match and pressure_match and result.converged
    )
    fixture_passed = bool(truth_passed and history_match and final_diagnostics_match)

    return {
        "validation_case": "disamar_o2a_two_state_optimal_estimation",
        "state_names": list(result.state_names),
        "iterations": result.iterations,
        "converged": result.converged,
        "expected_iterations": reference["expected_iterations"],
        "iteration_match": iteration_match,
        "history_match": history_match,
        "final_diagnostics_match": final_diagnostics_match,
        "passes_two_state_truth": truth_passed,
        "retrieved": retrieved_state,
        "reference": retrieved,
        "history": history,
        "reference_history": reference["iterations"],
        "absolute_differences": {
            "aerosol_optical_depth": aod_abs_diff,
            "aerosol_layer_top_pressure_hpa": top_pressure_abs_diff,
            "aerosol_layer_mid_pressure_hpa": pressure_abs_diff,
        },
        "tolerances": tolerances,
        "posterior_covariance": np.asarray(result.posterior_covariance).tolist(),
        "averaging_kernel": np.asarray(result.averaging_kernel).tolist(),
        "passes_disamar_two_state_fixture": fixture_passed,
    }


def main() -> int:
    timer = PhaseTimer()

    with timer.phase("load_reference_s"):
        reference = json.loads(REFERENCE_PATH.read_text())

    with timer.phase("build_case_s"):
        case = build_o2a_case(zd, jacobian_reference_layer=True)
        oe_baseline.configure_case(case)

    with timer.phase("build_pressure_altitude_profile_s"):
        profile = o2a_optimal_estimation.pressure_altitude_profile_from_prepared_grid(case)

    with timer.phase("build_state_vector_s"):
        state_vector = oe_setup.reference_two_state_vector(
            case=case,
            reference=reference,
            profile=profile,
        )
        assert_mid_pressure_jacobian_matches_finite_difference(case, state_vector)
        assert_gauss_newton_retains_prior_precision_nullspace()

    with timer.phase("boundary_contiguity_check_s"):
        assert_layer_boundaries_are_contiguous(case, state_vector, reference["a_priori"])

    with timer.phase("build_measurement_s"):
        measurement = build_measurement(case, reference)

    with timer.phase("session_create_s"):
        session = zd.o2a_forward_session(case)
    try:
        with timer.phase("retrieval_s"):
            result = run_retrieval(
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
        summary = build_summary(reference, result, layer_thickness)

    with timer.phase("write_summary_s"):
        write_json(SUMMARY_PATH, summary)
    phase_timings = timer.finish()
    timing = timing_report(phase_timings, result)
    write_json(TIMING_PATH, timing)
    print_retrieval_timing(timing)
    assert summary["passes_two_state_truth"], json.dumps(summary, indent=2, sort_keys=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
