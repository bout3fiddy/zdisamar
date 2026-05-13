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
REFERENCE_DATA_DIR = REPO_ROOT / "validation" / "reference_data" / "optimal_estimation"
OUTPUTS_DIR = REPO_ROOT / "validation" / "outputs" / "optimal_estimation"
REFERENCE_PATH = REFERENCE_DATA_DIR / "disamar_o2a_two_state_reference.json"
SUMMARY_PATH = OUTPUTS_DIR / "zdisamar_o2a_two_state_summary.json"
TIMING_PATH = OUTPUTS_DIR / "zdisamar_o2a_two_state_benchmark.json"

sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

import zdisamar as zd  # noqa: E402
from zdisamar.inverse_method import optimal_estimation  # noqa: E402
from zdisamar.inverse_method.optimal_estimation import o2a as o2a_optimal_estimation  # noqa: E402

from validation.common.paths import write_json  # noqa: E402
from validation.common.timing import PhaseTimer  # noqa: E402
from validation.o2a import baseline as oe_baseline  # noqa: E402
from validation.o2a.case import build_o2a_case  # noqa: E402
from validation.o2a.measurement_noise import (  # noqa: E402
    measurement_from_o2a_baseline_noise,
)
from validation.optimal_estimation import setup as oe_setup  # noqa: E402
from validation.optimal_estimation.checks import compare_scalar  # noqa: E402

JsonObject = dict[str, Any]


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

        if not compare_scalar(
            "iteration.aerosol_optical_depth",
            float(actual["aerosol_optical_depth"]),
            float(expected["aerosol_optical_depth"]),
            tolerance=float(state_tolerances["aerosol_optical_depth"]),
        ).passed:
            return False

        if "aerosol_layer_mid_pressure_hpa" not in expected:
            return False

        if not compare_scalar(
            "iteration.aerosol_layer_mid_pressure_hpa",
            float(actual["aerosol_layer_mid_pressure_hpa"]),
            float(expected["aerosol_layer_mid_pressure_hpa"]),
            tolerance=float(state_tolerances["aerosol_layer_mid_pressure_hpa"]),
        ).passed:
            return False

        if "state_vector_convergence" in expected:
            convergence_match = compare_scalar(
                "iteration.state_vector_convergence",
                float(actual["state_vector_convergence"]),
                float(expected["state_vector_convergence"]),
                tolerance=float(diagnostic_tolerances["state_vector_convergence"]),
            )

            if not convergence_match.passed:
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
        compare_scalar(
            "final.state_vector_convergence",
            float(actual.state_vector_convergence),
            float(expected["state_vector_convergence"]),
            tolerance=float(diagnostic_tolerances["state_vector_convergence"]),
        ).passed
        and compare_scalar(
            "final.chi2_reflectance",
            float(actual.chi2_reflectance),
            float(expected["chi2_reflectance"]),
            tolerance=float(diagnostic_tolerances["chi2_reflectance"]),
        ).passed
        and compare_scalar(
            "final.chi2_state_vector",
            float(actual.chi2_state_vector),
            float(expected["chi2_state_vector"]),
            tolerance=float(diagnostic_tolerances["chi2_state_vector"]),
        ).passed
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
    comparisons = [
        compare_scalar(
            "iterations",
            result.iterations,
            int(reference["expected_iterations"]),
        ),
        compare_scalar(
            "aerosol_optical_depth",
            retrieved_state["aerosol_optical_depth"],
            float(retrieved["aerosol_optical_depth"]),
            tolerance=float(tolerances["aerosol_optical_depth_abs"]),
        ),
        compare_scalar(
            "aerosol_layer_top_pressure_hpa",
            retrieved_state["aerosol_layer_top_pressure_hpa"],
            float(retrieved["aerosol_layer_top_pressure_hpa"]),
            tolerance=float(tolerances["aerosol_layer_top_pressure_hpa_abs"]),
        ),
        compare_scalar(
            "aerosol_layer_mid_pressure_hpa",
            retrieved_state["aerosol_layer_mid_pressure_hpa"],
            float(retrieved["aerosol_layer_mid_pressure_hpa"]),
            tolerance=float(tolerances["aerosol_layer_mid_pressure_hpa_abs"]),
        ),
        compare_scalar("converged", bool(result.converged), True),
    ]
    aod_match = comparisons[1].passed
    top_pressure_match = comparisons[2].passed
    pressure_match = comparisons[3].passed
    converged_match = comparisons[4].passed
    history = iteration_records(result)
    history_match = iteration_matches(reference["iterations"], history, tolerances)
    final_diagnostics_match = diagnostics_match(reference, result, tolerances)
    truth_passed = bool(
        iteration_match and aod_match and top_pressure_match and pressure_match and converged_match
    )
    fixture_passed = bool(truth_passed and history_match and final_diagnostics_match)

    return {
        "validation_case": "disamar_o2a_two_state_optimal_estimation",
        "reference_path": REFERENCE_PATH.relative_to(REPO_ROOT).as_posix(),
        "state_names": list(result.state_names),
        "iterations": result.iterations,
        "converged": result.converged,
        "expected_iterations": reference["expected_iterations"],
        "comparisons": [comparison.to_json() for comparison in comparisons],
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

    with PhaseTimer() as timer:
        reference = timer.run("load_reference_s", lambda: json.loads(REFERENCE_PATH.read_text()))
        case = timer.run("build_case_s", lambda: build_o2a_case(zd, jacobian_reference_layer=True))
        oe_baseline.configure_case(case)
        profile = timer.run(
            "build_pressure_altitude_profile_s",
            o2a_optimal_estimation.pressure_altitude_profile_from_prepared_grid,
            case,
        )
        state_vector = timer.run(
            "build_state_vector_s",
            oe_setup.reference_two_state_vector,
            case=case,
            reference=reference,
            profile=profile,
        )
        measurement = timer.run("build_measurement_s", build_measurement, case, reference)
        session = timer.run("session_create_s", zd.o2a_forward_session, case)

        try:
            result = timer.run(
                "retrieval_s",
                run_retrieval,
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
        summary = timer.run("build_summary_s", build_summary, reference, result, layer_thickness)
        timer.run("write_summary_s", write_json, SUMMARY_PATH, summary)

    phase_timings = timer.finish()
    timing = timing_report(phase_timings, result)
    write_json(TIMING_PATH, timing)
    print_retrieval_timing(timing)

    if not summary["passes_two_state_truth"]:
        print(json.dumps(summary, indent=2, sort_keys=True), file=sys.stderr)

        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
