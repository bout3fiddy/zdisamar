#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "numpy>=2.2",
# ]
# ///

from __future__ import annotations

import json
from pathlib import Path
import sys
from typing import Any

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
SCRIPT_ROOT = REPO_ROOT / "scripts" / "testing_harness"
DATA_DIR = REPO_ROOT / "validation" / "optimal_estimation" / "data"
PROFILE_PATH = REPO_ROOT / "data" / "reference_data" / "climatologies" / "vendor_config_o2a_profile.csv"
REFERENCE_PATH = DATA_DIR / "disamar_o2a_two_state_reference.json"
SUMMARY_PATH = DATA_DIR / "zdisamar_o2a_two_state_summary.json"

sys.path[:0] = [str(PYTHON_ROOT), str(SCRIPT_ROOT)]

import zdisamar as zd
from zdisamar.inverse_method import optimal_estimation
from o2a_python_case import build_o2a_case

JsonObject = dict[str, Any]


def build_state_vector(case: zd.O2AInput, reference: JsonObject, profile):
    prior = reference["a_priori"]
    layer_thickness = (
        case.aerosol.placement.bottom_pressure_hpa
        - case.aerosol.placement.top_pressure_hpa
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


def run_retrieval(case: zd.O2AInput, state_vector):
    inverse_model = optimal_estimation.O2AInverseForwardModel(case)

    # The measurement is simulated once from the truth scene. The inverse pass
    # only sees this spectrum plus covariance, so a wrong retrieval trajectory
    # cannot be excused by regenerating the target at each state.
    with zd.prepare(case) as prepared:
        measurement = optimal_estimation.measurement_from_prepared(
            prepared,
            reflectance_variance=1.0e-8,
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
        retrieved_state["aerosol_optical_depth"]
        - float(retrieved["aerosol_optical_depth"])
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
    passed = bool(
        iteration_match
        and aod_match
        and top_altitude_match
        and top_pressure_match
        and pressure_match
        and result.converged
    )

    return {
        "validation_case": "disamar_o2a_two_state_optimal_estimation",
        "state_names": list(result.state_names),
        "iterations": result.iterations,
        "converged": result.converged,
        "expected_iterations": reference["expected_iterations"],
        "iteration_match": iteration_match,
        "retrieved": retrieved_state,
        "reference": retrieved,
        "history": iteration_records(result),
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
    reference = json.loads(REFERENCE_PATH.read_text())
    case = build_o2a_case(zd, jacobian_reference_layer=True)
    profile = optimal_estimation.PressureAltitudeProfile.from_csv(PROFILE_PATH)
    state_vector = build_state_vector(case, reference, profile)
    assert_layer_boundaries_are_contiguous(case, state_vector, reference["a_priori"])

    result = run_retrieval(case, state_vector)
    layer_thickness = (
        case.aerosol.placement.bottom_pressure_hpa
        - case.aerosol.placement.top_pressure_hpa
    )
    summary = build_summary(reference, result, profile, layer_thickness)
    SUMMARY_PATH.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    assert summary["passes_disamar_two_state_fixture"], json.dumps(
        summary, indent=2, sort_keys=True
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
