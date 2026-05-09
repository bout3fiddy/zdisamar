#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "numpy>=2.2",
# ]
# ///

import copy
import statistics
import sys
import time
from pathlib import Path
from typing import Any

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
OUTPUTS_DIR = REPO_ROOT / "validation" / "outputs" / "optimal_estimation"
BENCHMARK_PATH = OUTPUTS_DIR / "zdisamar_o2a_slow_forward_jacobian_benchmark.json"

sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

import zdisamar as zd  # noqa: E402
from zdisamar.inverse_method import optimal_estimation  # noqa: E402
from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe  # noqa: E402

from validation.common import o2a_retrieval_baseline as oe_baseline  # noqa: E402
from validation.common.o2a_reference_case import build_o2a_case  # noqa: E402
from validation.common.paths import stable_repo_path, write_json  # noqa: E402

PROBE_RUNS = 5


def build_case() -> zd.O2AInput:
    case = build_o2a_case(zd, jacobian_reference_layer=True)
    oe_baseline.configure_case(case)
    oe_baseline.configure_slow_validation_scene(case)
    return case


def build_state_vector(
    case: zd.O2AInput,
    profile: optimal_estimation.PressureAltitudeProfile,
) -> optimal_estimation.StateVector:
    scene = oe_baseline.SLOW_VALIDATION_SCENE
    return optimal_estimation.StateVector(
        [
            optimal_estimation.AerosolOpticalDepth(
                initial=scene["initial_aerosol_optical_depth"],
                prior=scene["initial_aerosol_optical_depth"],
                variance=0.8,
                lower=0.02,
                upper=5.0,
            ),
            optimal_estimation.AerosolLayerMidPressure(
                initial=scene["initial_aerosol_mid_pressure_hpa"],
                prior=scene["initial_aerosol_mid_pressure_hpa"],
                variance=150.0**2,
                thickness_hpa=oe_baseline.LAYER_THICKNESS_HPA,
                interval_index_1based=case.aerosol.placement.interval_index_1based,
                pressure_altitude_profile=profile,
                lower=225.0,
                upper=case.surface.pressure_hpa - 100.0,
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


def run_retrieval(
    case: zd.O2AInput,
    state_vector: optimal_estimation.StateVector,
    measurement: optimal_estimation.Measurement,
    forward_session: zd.O2AForwardSession | None = None,
) -> optimal_estimation.Result:
    return o2a_oe.disamar_oe(
        inverse_model=optimal_estimation.O2AInverseForwardModel(
            case,
            forward_session=forward_session,
        ),
        measurement=measurement,
        state_vector=state_vector,
        controls=optimal_estimation.RetrievalControls.from_disamar_retrieval_specs(),
    )


def retrieval_record(result: optimal_estimation.Result, wall_s: float) -> dict[str, Any]:
    forward_s = sum(timing.forward_model_and_jacobian_s for timing in result.timing)
    solver_s = sum(timing.solver_update_s for timing in result.timing)
    return {
        "wall_s": wall_s,
        "forward_model_and_jacobian_s": forward_s,
        "solver_update_s": solver_s,
        "other_retrieval_s": wall_s - forward_s - solver_s,
        "iterations": result.iterations,
        "converged": result.converged,
        "state_names": list(result.state_names),
        "retrieved": {
            "aerosol_optical_depth": result.value("aerosol_optical_depth"),
            "aerosol_layer_mid_pressure_hpa": result.value("aerosol_layer_mid_pressure_hpa"),
        },
        "iterations_detail": [
            {
                "index": timing.index,
                "forward_model_and_jacobian_s": timing.forward_model_and_jacobian_s,
                "solver_update_s": timing.solver_update_s,
                "total_iteration_s": timing.total_iteration_s,
            }
            for timing in result.timing
        ],
    }


def time_call(callable_object) -> float:
    start = time.perf_counter()
    callable_object()
    return time.perf_counter() - start


def probe_prepared_calls(
    session: zd.O2AForwardSession,
    case: zd.O2AInput,
    state_vector: optimal_estimation.StateVector,
) -> dict[str, Any]:
    inverse_model = optimal_estimation.O2AInverseForwardModel(case, forward_session=session)
    state_case = inverse_model.settings_for_state(state_vector.prior_state(), state_vector)
    prepared = session.prepare(state_case)

    def forward_only() -> None:
        with prepared.forward_model() as spectrum:
            _ = spectrum.reflectance.copy()

    def forward_and_jacobian() -> None:
        evaluation = o2a_oe.evaluate_prepared_reflectance(prepared, state_vector.jacobian_names)
        _ = o2a_oe.scale_reflectance_jacobian(
            evaluation,
            state_vector.jacobian_scales(state_vector.prior_state()),
        )

    forward_only_s = [time_call(forward_only) for _ in range(PROBE_RUNS)]
    forward_and_jacobian_s = [time_call(forward_and_jacobian) for _ in range(PROBE_RUNS)]
    return {
        "probe_runs": PROBE_RUNS,
        "forward_only_s": stats(forward_only_s),
        "forward_and_jacobian_s": stats(forward_and_jacobian_s),
        "jacobian_increment_s": stats(
            [forward_and_jacobian_s[index] - forward_only_s[index] for index in range(PROBE_RUNS)]
        ),
    }


def stats(values: list[float]) -> dict[str, float]:
    return {
        "min": min(values),
        "median": statistics.median(values),
        "mean": statistics.fmean(values),
        "max": max(values),
    }


def main() -> int:
    case = build_case()
    profile = o2a_oe.pressure_altitude_profile_from_prepared_grid(case)
    state_vector = build_state_vector(case, profile)

    measurement_start = time.perf_counter()
    with zd.prepare(case) as prepared:
        measurement = measurement_from_baseline_snr(prepared)
    measurement_s = time.perf_counter() - measurement_start

    non_session_start = time.perf_counter()
    non_session_result = run_retrieval(case, state_vector, measurement)
    non_session_s = time.perf_counter() - non_session_start

    session_setup_start = time.perf_counter()
    session = zd.o2a_forward_session(case)
    session_setup_s = time.perf_counter() - session_setup_start
    try:
        session_start = time.perf_counter()
        session_result = run_retrieval(case, state_vector, measurement, forward_session=session)
        session_reused_s = time.perf_counter() - session_start
        prepared_probe = probe_prepared_calls(session, case, state_vector)
    finally:
        session.close()

    report = {
        "validation_case": "zdisamar_o2a_slow_forward_jacobian_latency",
        "source": (
            "Slow retained scene from out/validation/optimal_estimation/"
            "paired_disamar_zdisamar/paired_retrieval_runs.parquet case 71."
        ),
        "scene": copy.deepcopy(oe_baseline.SLOW_VALIDATION_SCENE),
        "measurement_build_s": measurement_s,
        "non_session": retrieval_record(non_session_result, non_session_s),
        "session": {
            "setup_s": session_setup_s,
            "reused_retrieval": retrieval_record(session_result, session_reused_s),
            "first_use_retrieval_s": session_setup_s + session_reused_s,
        },
        "direct_prepared_call_probe": prepared_probe,
        "session_matches_non_session_result": bool(
            non_session_result.converged == session_result.converged
            and non_session_result.iterations == session_result.iterations
            and np.array_equal(non_session_result.state, session_result.state)
        ),
    }
    write_json(BENCHMARK_PATH, report)

    print("Slow forward+jacobian latency benchmark:")
    print(f"  measurement build: {measurement_s:.6f} s")
    print(
        "  non-session retrieval: "
        f"{report['non_session']['wall_s']:.6f} s total, "
        f"{report['non_session']['forward_model_and_jacobian_s']:.6f} s forward+jacobian"
    )
    print(
        "  session reused retrieval: "
        f"{report['session']['reused_retrieval']['wall_s']:.6f} s total, "
        f"{report['session']['reused_retrieval']['forward_model_and_jacobian_s']:.6f} s "
        "forward+jacobian"
    )
    print(
        "  prepared probe median: "
        f"{prepared_probe['forward_only_s']['median']:.6f} s forward only, "
        f"{prepared_probe['forward_and_jacobian_s']['median']:.6f} s forward+jacobian"
    )
    print(f"  JSON: {stable_repo_path(BENCHMARK_PATH)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
