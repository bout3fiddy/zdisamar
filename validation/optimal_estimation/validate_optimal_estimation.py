#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "numpy>=2.2",
# ]
# ///

from __future__ import annotations

import json
import math
from pathlib import Path
import sys
from typing import Any

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
SCRIPT_ROOT = REPO_ROOT / "scripts" / "testing_harness"
DATA_DIR = REPO_ROOT / "validation" / "optimal_estimation" / "data"
REFERENCE_PATH = DATA_DIR / "disamar_o2a_two_state_reference.json"
SUMMARY_PATH = DATA_DIR / "zdisamar_o2a_two_state_summary.json"

sys.path[:0] = [str(PYTHON_ROOT), str(SCRIPT_ROOT)]

import zdisamar as zd
from zdisamar.inverse_method import optimal_estimation
from o2a_python_case import build_o2a_case

JsonObject = dict[str, Any]


def pressure_altitude_profile_from_case(
    case: zd.O2AInput,
) -> optimal_estimation.PressureAltitudeProfile:
    # The fitted interval state is an altitude, but the forward-model settings
    # are pressure boundaries.  The prepared grid is the only pressure-altitude
    # relation that has the same interval subdivision as the spectrum/Jacobian
    # calculation, so using the sparse climatology table here would validate a
    # different inverse problem.
    with zd.prepare(case) as prepared:
        budget = prepared.atmospheric_budget(
            np.array([case.spectral_grid.start_nm], dtype=np.float64)
        )
        table = budget.table

    levels_by_pressure: dict[float, float] = {}
    for row in table:
        levels_by_pressure[round(float(row["top_pressure_hpa"]), 12)] = float(
            row["top_altitude_km"]
        )
        levels_by_pressure[round(float(row["bottom_pressure_hpa"]), 12)] = float(
            row["bottom_altitude_km"]
        )
    levels = sorted(
        (altitude, pressure) for pressure, altitude in levels_by_pressure.items()
    )
    return optimal_estimation.PressureAltitudeProfile(
        altitude_km=np.array([altitude for altitude, _pressure in levels]),
        pressure_hpa=np.array([pressure for _altitude, pressure in levels]),
    )


def build_state_vector(
    case: zd.O2AInput,
    reference: JsonObject,
    profile: optimal_estimation.PressureAltitudeProfile,
):
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


def run_retrieval(case: zd.O2AInput, state_vector, reference: JsonObject):
    inverse_model = optimal_estimation.O2AInverseForwardModel(case)

    # The measurement is simulated once from the truth scene. The inverse pass
    # only sees this spectrum plus covariance, so a wrong retrieval trajectory
    # cannot be excused by regenerating the target at each state.
    with zd.prepare(case) as prepared:
        measurement = optimal_estimation.measurement_from_prepared(
            prepared,
            reflectance_variance=1.0e-8,
        )
    if "measurement_noise" in reference:
        measurement = measurement_with_reference_noise(
            measurement,
            reference["measurement_noise"],
            case,
        )

    return optimal_estimation.disamar_oe(
        inverse_model=inverse_model,
        measurement=measurement,
        state_vector=state_vector,
        controls=optimal_estimation.RetrievalControls.from_disamar_retrieval_specs(),
    )


def measurement_with_reference_noise(
    measurement: optimal_estimation.Measurement,
    noise_reference: JsonObject,
    case: zd.O2AInput,
) -> optimal_estimation.Measurement:
    source_wavelength = np.asarray(noise_reference["wavelength_nm"], dtype=np.float64)
    source_noise = np.asarray(
        noise_reference["assumed_noise_sun_normalized_radiance"],
        dtype=np.float64,
    )
    # The reference precision is attached to sun-normalized radiance.  The
    # retrieval vector here is reflectance R = pi * I / (mu0 * E0), so the
    # covariance has to be converted by the same scale as the measurement.
    mu0 = math.cos(math.radians(case.geometry.solar_zenith_deg))
    reflectance_noise = np.interp(
        measurement.wavelength_nm,
        source_wavelength,
        source_noise,
    ) * (math.pi / mu0)
    return optimal_estimation.Measurement(
        wavelength_nm=measurement.wavelength_nm,
        reflectance=measurement.reflectance,
        variance=reflectance_noise**2,
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
        if "snr_normal" in expected and bool(actual["snr_normal"]) != bool(
            expected["snr_normal"]
        ):
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
    reference = json.loads(REFERENCE_PATH.read_text())
    case = build_o2a_case(zd, jacobian_reference_layer=True)
    profile = pressure_altitude_profile_from_case(case)
    state_vector = build_state_vector(case, reference, profile)
    assert_layer_boundaries_are_contiguous(case, state_vector, reference["a_priori"])

    result = run_retrieval(case, state_vector, reference)
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
