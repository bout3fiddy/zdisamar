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

from validation.common.native_binding import sync_release_fast_binding  # noqa: E402

sync_release_fast_binding(REPO_ROOT)

from zdisamar import rtm  # noqa: E402
from zdisamar.optimal_estimation import o2a as o2a_oe  # noqa: E402
from zdisamar.wavelength_bands import o2a  # noqa: E402

from validation.common.paths import write_json  # noqa: E402
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


def probe_rtm_calls(probe_case: o2a.Scene) -> dict[str, Any]:

    # Cold no-session forwards: a warm SessionCache fully memoizes the forward
    # result, so repeated identical calls would measure cache hits, not RTM
    # cost. Each call here recomputes the full forward for the slow scene.
    def radiance_reflectance_only() -> None:

        spectrum = rtm.spectrum(probe_case)
        _ = list(spectrum.reflectance)

    def radiance_reflectance_and_jacobian() -> None:

        spectrum = rtm.spectrum(probe_case, jacobian=True)
        _ = list(spectrum.reflectance)

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

    base = build_o2a_case(o2a, jacobian_reference_layer=True)
    oe_baseline.configure_case(base)

    row = slow_case_row()
    truth = oe_cases.scene_from_row(row)
    initial = oe_cases.initial_from_row(row)

    case = oe_setup.build_scene(
        base, index=SLOW_CASE_INDEX, id_prefix="o2a_oe_slow_rtm_jacobian_validation", scene=truth
    )
    state_vector = oe_setup.aerosol_two_state_vector(
        initial=initial,
        surface_pressure_hpa=truth["surface_pressure_hpa"],
    )

    # Probe scene fixes the aerosol state at the retrieval starting point so the
    # direct RTM/Jacobian probe measures the working state, not the truth state.
    probe_scene = dict(truth)
    probe_scene["aerosol_optical_depth"] = initial["aerosol_optical_depth"]
    probe_scene["aerosol_mid_pressure_hpa"] = initial["aerosol_mid_pressure_hpa"]
    probe_case = oe_setup.build_scene(
        base, index=SLOW_CASE_INDEX, id_prefix="o2a_oe_slow_rtm_jacobian_probe", scene=probe_scene
    )

    measurement_start = time.perf_counter()
    measurement = measurement_from_o2a_baseline_noise(case)
    measurement_s = time.perf_counter() - measurement_start

    cache_setup_start = time.perf_counter()
    cache = rtm.SessionCache(case)
    cache_setup_s = time.perf_counter() - cache_setup_start

    try:
        retrieval_start = time.perf_counter()
        result = o2a_oe.retrieve(
            scene=case,
            measurement=measurement,
            state_vector=state_vector,
            controls=oe_setup.retrieval_controls(),
            cache=cache,
        )
        retrieval_s = time.perf_counter() - retrieval_start

        lazy_final_start = time.perf_counter()
        _ = result.final_evaluation
        lazy_final_evaluation_s = time.perf_counter() - lazy_final_start

        probe = probe_rtm_calls(probe_case)
    finally:
        cache.close()

    report = {
        "validation_case": "zdisamar_o2a_slow_rtm_jacobian_latency",
        "source": "Slow retained scene from shared DISAMAR OE reference sweep case 71.",
        "regime": (
            "Baseline per-wavelength noise; two-state aerosol retrieval "
            "(AOD, mid-pressure); retrieval_controls(); reused SessionCache for "
            "the retrieval; cold no-session forwards for direct_rtm_call_probe."
        ),
        "reference_cases": oe_cases.manifest_path(),
        "reference_case": SLOW_CASE_INDEX,
        "scene": row,
        "measurement_build_s": measurement_s,
        "cache": {
            "setup_s": cache_setup_s,
            "reused_retrieval": {
                "wall_s": retrieval_s,
                "iterations": result.iterations,
                "converged": result.converged,
                "state_names": list(result.state_names),
                "retrieved": {
                    "aerosol_optical_depth": result.value("aerosol_optical_depth"),
                    "aerosol_layer_mid_pressure_hpa": result.value(
                        "aerosol_layer_mid_pressure_hpa"
                    ),
                },
                "retrieval_plus_lazy_final_evaluation_s": retrieval_s + lazy_final_evaluation_s,
            },
            "first_use_retrieval_s": cache_setup_s + retrieval_s,
        },
        "lazy_final_evaluation_s": lazy_final_evaluation_s,
        "lazy_final_evaluation_cached": True,
        "direct_rtm_call_probe": probe,
    }

    write_json(BENCHMARK_PATH, report)

    probe = report["direct_rtm_call_probe"]
    reused = report["cache"]["reused_retrieval"]
    print(f"wrote {BENCHMARK_PATH}")
    print(f"direct RTM-only median           {probe['rtm_only_s']['median']:.6f} s")
    print(f"direct RTM+jacobian median       {probe['rtm_and_jacobian_s']['median']:.6f} s")
    print(f"jacobian increment median        {probe['jacobian_increment_s']['median']:.6f} s")
    print(f"session reused retrieval wall     {reused['wall_s']:.6f} s")
    print(f"lazy final evaluation            {report['lazy_final_evaluation_s']:.6f} s")
    print(f"iterations                       {reused['iterations']}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
