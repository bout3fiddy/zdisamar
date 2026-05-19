#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "numpy>=2.2",
# ]
# ///

import statistics
import sys
import time
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
OUTPUTS_DIR = REPO_ROOT / "validation" / "outputs" / "optimal_estimation"
BENCHMARK_PATH = OUTPUTS_DIR / "zdisamar_o2a_slow_rtm_jacobian_benchmark.json"

sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

from zdisamar import rtm  # noqa: E402
from zdisamar.inverse_method import optimal_estimation  # noqa: E402
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

PROBE_RUNS = 5
SLOW_CASE_INDEX = 71


def slow_case_row() -> dict[str, Any]:

    return oe_cases.case_rows(count=SLOW_CASE_INDEX)[SLOW_CASE_INDEX - 1]


def build_case() -> o2a.O2ACase:

    base = build_o2a_case(o2a, jacobian_reference_layer=True)
    oe_baseline.configure_case(base)

    return oe_setup.build_scene(
        base,
        index=SLOW_CASE_INDEX,
        id_prefix="o2a_oe_slow_rtm_jacobian_validation",
        scene=oe_cases.scene_from_row(slow_case_row()),
    )


def build_state_vector(
    case: o2a.O2ACase,
    profile: optimal_estimation.PressureAltitudeProfile,
) -> optimal_estimation.StateVector:

    initial = oe_cases.initial_from_row(slow_case_row())

    return oe_setup.aerosol_two_state_vector(
        initial=initial,
        profile=profile,
        surface_pressure_hpa=case.surface.pressure_hpa,
        interval_index_1based=case.aerosol.placement.interval_index_1based,
    )


def run_retrieval(
    case: o2a.O2ACase,
    state_vector: optimal_estimation.StateVector,
    measurement: optimal_estimation.Measurement,
    cache: rtm.SessionCache,
) -> optimal_estimation.Result:

    return o2a_oe.disamar_oe(
        case=case,
        measurement=measurement,
        state_vector=state_vector,
        controls=oe_setup.retrieval_controls(),
        cache=cache,
    )


def retrieval_record(result: optimal_estimation.Result, wall_s: float) -> dict[str, Any]:

    rtm_s = sum(timing.rtm_and_jacobian_s for timing in result.timing)
    solver_s = sum(timing.solver_update_s for timing in result.timing)

    return {
        "wall_s": wall_s,
        "rtm_and_jacobian_s": rtm_s,
        "solver_update_s": solver_s,
        "other_retrieval_s": wall_s - rtm_s - solver_s,
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
                "rtm_and_jacobian_s": timing.rtm_and_jacobian_s,
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


def stats(values: list[float]) -> dict[str, float]:

    return {
        "min": min(values),
        "median": statistics.median(values),
        "mean": statistics.fmean(values),
        "max": max(values),
    }


def probe_rtm_calls(
    cache: rtm.SessionCache,
    case: o2a.O2ACase,
    state_vector: optimal_estimation.StateVector,
) -> dict[str, Any]:

    state_case = o2a_oe.case_for_state(case, state_vector.prior_state(), state_vector)

    def radiance_reflectance_only() -> None:

        spectrum = rtm.spectrum(state_case, cache=cache)
        _ = list(spectrum.reflectance)

    def radiance_reflectance_and_jacobian() -> None:

        evaluation = o2a_oe.evaluate_reflectance(
            state_case,
            state_vector.jacobian_names,
            cache=cache,
        )
        _ = o2a_oe.scale_reflectance_jacobian(
            evaluation,
            state_vector.jacobian_scales(state_vector.prior_state()),
        )

    rtm_only_s = [time_call(radiance_reflectance_only) for _ in range(PROBE_RUNS)]
    rtm_and_jacobian_s = [time_call(radiance_reflectance_and_jacobian) for _ in range(PROBE_RUNS)]

    return {
        "probe_runs": PROBE_RUNS,
        "rtm_only_s": stats(rtm_only_s),
        "rtm_and_jacobian_s": stats(rtm_and_jacobian_s),
        "jacobian_increment_s": stats(
            [rtm_and_jacobian_s[index] - rtm_only_s[index] for index in range(PROBE_RUNS)]
        ),
    }


def main() -> int:

    case = build_case()
    profile = o2a_oe.pressure_altitude_profile_from_case(case)
    state_vector = build_state_vector(case, profile)

    measurement_start = time.perf_counter()
    measurement = measurement_from_o2a_baseline_noise(case)
    measurement_s = time.perf_counter() - measurement_start

    cache_setup_start = time.perf_counter()
    cache = rtm.SessionCache(case)
    cache_setup_s = time.perf_counter() - cache_setup_start

    try:
        retrieval_start = time.perf_counter()
        result = run_retrieval(case, state_vector, measurement, cache)
        retrieval_s = time.perf_counter() - retrieval_start

        lazy_final_start = time.perf_counter()
        _ = result.final_evaluation
        lazy_final_evaluation_s = time.perf_counter() - lazy_final_start
        probe = probe_rtm_calls(cache, case, state_vector)
    finally:
        cache.close()

    report = {
        "validation_case": "zdisamar_o2a_slow_rtm_jacobian_latency",
        "source": "Slow retained scene from shared DISAMAR OE reference sweep case 71.",
        "reference_cases": oe_cases.manifest_path(),
        "reference_case": SLOW_CASE_INDEX,
        "scene": slow_case_row(),
        "measurement_build_s": measurement_s,
        "cache": {
            "setup_s": cache_setup_s,
            "reused_retrieval": retrieval_record(result, retrieval_s)
            | {"retrieval_plus_lazy_final_evaluation_s": retrieval_s + lazy_final_evaluation_s},
            "first_use_retrieval_s": cache_setup_s + retrieval_s,
        },
        "lazy_final_evaluation_s": lazy_final_evaluation_s,
        "direct_rtm_call_probe": probe,
    }
    write_json(BENCHMARK_PATH, report)

    print("Slow RTM+jacobian latency benchmark:")
    print(f"  measurement build: {measurement_s:.6f} s")
    print(
        "  cache reused retrieval: "
        f"{report['cache']['reused_retrieval']['wall_s']:.6f} s total, "
        f"{report['cache']['reused_retrieval']['rtm_and_jacobian_s']:.6f} s RTM+jacobian"
    )
    print(f"  lazy final evaluation: {lazy_final_evaluation_s:.6f} s when requested")
    print(
        "  RTM probe median: "
        f"{probe['rtm_only_s']['median']:.6f} s RTM only, "
        f"{probe['rtm_and_jacobian_s']['median']:.6f} s RTM+jacobian"
    )
    print(f"  JSON: {stable_repo_path(BENCHMARK_PATH)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
