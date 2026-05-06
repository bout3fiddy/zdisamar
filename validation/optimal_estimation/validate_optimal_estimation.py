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

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
SCRIPT_ROOT = REPO_ROOT / "scripts" / "testing_harness"
DATA_DIR = REPO_ROOT / "validation" / "optimal_estimation" / "data"
REFERENCE_PATH = DATA_DIR / "disamar_o2a_two_state_reference.json"
SUMMARY_PATH = DATA_DIR / "zdisamar_o2a_two_state_summary.json"


def import_zdisamar():
    sys.path.insert(0, str(PYTHON_ROOT))
    sys.path.insert(0, str(SCRIPT_ROOT))
    import zdisamar as zd
    from o2a_python_case import build_o2a_case

    return zd, build_o2a_case


def layer_mid_pressure(case) -> float:
    placement = case.aerosol.placement
    return 0.5 * (placement.top_pressure_hpa + placement.bottom_pressure_hpa)


def main() -> int:
    zd, build_o2a_case = import_zdisamar()
    reference = json.loads(REFERENCE_PATH.read_text())
    case = build_o2a_case(zd, jacobian_reference_layer=True)
    optimal_estimation = zd.inverse_method.optimal_estimation
    initial_mid_pressure = layer_mid_pressure(case)
    layer_thickness = (
        case.aerosol.placement.bottom_pressure_hpa
        - case.aerosol.placement.top_pressure_hpa
    )
    state_vector = optimal_estimation.StateVector(
        [
            optimal_estimation.AerosolOpticalDepth(
                initial=case.aerosol.optical_depth_550_nm,
                prior=case.aerosol.optical_depth_550_nm,
                variance=1.0,
                lower=0.0,
            ),
            optimal_estimation.AerosolLayerMidPressure(
                initial=initial_mid_pressure,
                prior=initial_mid_pressure,
                variance=25.0e4,
                thickness_hpa=layer_thickness,
                interval_index_1based=case.aerosol.placement.interval_index_1based,
            ),
        ]
    )
    inverse_model = optimal_estimation.O2AInverseForwardModel(case)
    moved_case = inverse_model.settings_for_state(
        np.array([case.aerosol.optical_depth_550_nm, initial_mid_pressure + 2.0]),
        state_vector,
    )
    assert (
        moved_case.atmosphere.intervals[0].bottom_pressure_hpa
        == moved_case.atmosphere.intervals[1].top_pressure_hpa
    )
    assert (
        moved_case.atmosphere.intervals[1].bottom_pressure_hpa
        == moved_case.atmosphere.intervals[2].top_pressure_hpa
    )

    with zd.prepare(case) as prepared:
        measurement = optimal_estimation.measurement_from_prepared(
            prepared,
            reflectance_variance=1.0e-8,
        )

    result = optimal_estimation.disamar_oe(
        inverse_model=inverse_model,
        measurement=measurement,
        state_vector=state_vector,
        controls=optimal_estimation.RetrievalControls.from_disamar_retrieval_specs(),
    )

    retrieved = reference["retrieved"]
    tolerances = reference["tolerances"]
    aod = result.value("aerosol_optical_depth")
    mid_pressure = result.value("aerosol_layer_mid_pressure_hpa")
    aod_abs_diff = abs(aod - float(retrieved["aerosol_optical_depth"]))
    pressure_abs_diff = abs(mid_pressure - float(retrieved["aerosol_layer_mid_pressure_hpa"]))
    iteration_match = result.iterations == int(reference["expected_iterations"])
    aod_match = aod_abs_diff <= float(tolerances["aerosol_optical_depth_abs"])
    pressure_match = pressure_abs_diff <= float(tolerances["aerosol_layer_mid_pressure_hpa_abs"])
    passed = bool(iteration_match and aod_match and pressure_match and result.converged)

    summary = {
        "validation_case": "disamar_o2a_two_state_optimal_estimation",
        "state_names": list(result.state_names),
        "iterations": result.iterations,
        "converged": result.converged,
        "expected_iterations": reference["expected_iterations"],
        "iteration_match": iteration_match,
        "retrieved": {
            "aerosol_optical_depth": aod,
            "aerosol_layer_mid_pressure_hpa": mid_pressure,
        },
        "reference": retrieved,
        "absolute_differences": {
            "aerosol_optical_depth": aod_abs_diff,
            "aerosol_layer_mid_pressure_hpa": pressure_abs_diff,
        },
        "tolerances": tolerances,
        "posterior_covariance": np.asarray(result.posterior_covariance).tolist(),
        "averaging_kernel": np.asarray(result.averaging_kernel).tolist(),
        "passes_disamar_two_state_fixture": passed,
    }
    SUMMARY_PATH.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    assert passed, json.dumps(summary, indent=2, sort_keys=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
