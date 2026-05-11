#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "numpy>=2.2",
# ]
# ///

import copy
import dataclasses
import statistics
import sys
import time
from pathlib import Path
from typing import Any, cast

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
OUTPUTS_DIR = REPO_ROOT / "validation" / "outputs" / "optimal_estimation"
BENCHMARK_PATH = OUTPUTS_DIR / "zdisamar_o2a_slow_forward_jacobian_benchmark.json"

sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

import numpy as np  # noqa: E402
import zdisamar as zd  # noqa: E402
from zdisamar.inverse_method import optimal_estimation  # noqa: E402
from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe  # noqa: E402

from validation.common import o2a_retrieval_baseline as oe_baseline  # noqa: E402
from validation.common.o2a_measurement_noise import (  # noqa: E402
    measurement_from_o2a_baseline_noise,
)
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


def run_retrieval(
    case: zd.O2AInput,
    state_vector: optimal_estimation.StateVector,
    measurement: optimal_estimation.Measurement,
    forward_session: zd.O2AForwardSession | None = None,
    trace_records: list[dict[str, Any]] | None = None,
) -> optimal_estimation.Result:
    inverse_model = o2a_oe.O2AInverseForwardModel(case, forward_session=forward_session)
    if trace_records is not None:
        cast(Any, inverse_model).evaluate = tracing_evaluate(
            inverse_model,
            trace_records,
        )
    return o2a_oe.disamar_oe(
        inverse_model=inverse_model,
        measurement=measurement,
        state_vector=state_vector,
        controls=optimal_estimation.RetrievalControls(
            max_iterations=10,
            state_vector_convergence_threshold=1.0,
            max_change_transformed_state=1.0,
            collect_timing=True,
        ),
    )


def tracing_evaluate(
    model: o2a_oe.O2AInverseForwardModel,
    trace_records: list[dict[str, Any]],
):
    def evaluate(
        state,
        state_vector: optimal_estimation.StateVector,
    ) -> optimal_estimation.ForwardEvaluation:
        total_start = time.perf_counter()
        settings_start = time.perf_counter()
        settings = model.settings_for_state(state, state_vector)
        settings_s = time.perf_counter() - settings_start

        if model._forward_session is None:
            return o2a_oe.O2AInverseForwardModel.evaluate(model, state, state_vector)

        prepare_start = time.perf_counter()
        prepared = model._forward_session.prepare(settings)
        prepare_s = time.perf_counter() - prepare_start
        prepare_trace = model._forward_session.last_prepare_trace()

        evaluation, evaluation_trace = evaluate_prepared_reflectance_timed(
            prepared,
            state_vector.jacobian_names,
        )
        scale_start = time.perf_counter()
        scaled = o2a_oe.scale_reflectance_jacobian(
            evaluation,
            state_vector.jacobian_scales(state),
        )
        scale_s = time.perf_counter() - scale_start

        trace_records.append(
            {
                "index": len(trace_records) + 1,
                "settings_for_state_s": settings_s,
                "prepare_total_s": prepare_s,
                "prepare_trace": prepare_trace,
                "forward_evaluation_trace": evaluation_trace,
                "scale_jacobian_s": scale_s,
                "total_evaluate_s": time.perf_counter() - total_start,
            }
        )
        return scaled

    return evaluate


def evaluate_final_state_with_trace(
    case: zd.O2AInput,
    state_vector: optimal_estimation.StateVector,
    state,
    trace_records: list[dict[str, Any]],
) -> optimal_estimation.ForwardEvaluation:
    with zd.o2a_forward_session(case) as session:
        session.enable_prepare_trace()
        model = o2a_oe.O2AInverseForwardModel(case, forward_session=session)
        cast(Any, model).evaluate = tracing_evaluate(model, trace_records)
        return model.evaluate(state, state_vector)


def evaluate_prepared_reflectance_timed(
    prepared,
    state_names: tuple[str, ...],
) -> tuple[optimal_estimation.ForwardEvaluation, dict[str, float]]:
    run_start = time.perf_counter()
    with prepared.forward_model(jacobian=True, jacobian_state_names=state_names) as spectrum:
        native_forward_s = time.perf_counter() - run_start
        copy_start = time.perf_counter()
        wavelength_nm = spectrum.wavelength_nm.copy()
        reflectance = spectrum.reflectance.copy()
        radiance_jacobian = spectrum.radiance_jacobian.copy()
        irradiance = spectrum.irradiance.copy()
        available_state_names = spectrum.jacobian_state_names
        copy_outputs_s = time.perf_counter() - copy_start

    conversion_start = time.perf_counter()
    reflectance_jacobian_all = o2a_oe.reflectance_jacobian_from_radiance_jacobian(
        radiance_jacobian,
        irradiance,
        prepared.input.geometry.solar_mu0,
    )
    conversion_s = time.perf_counter() - conversion_start
    if available_state_names != state_names:
        raise ValueError("Native Jacobian state selection did not preserve requested state order")
    evaluation = optimal_estimation.ForwardEvaluation(
        wavelength_nm=wavelength_nm,
        reflectance=reflectance,
        reflectance_jacobian=reflectance_jacobian_all,
    )
    return evaluation, {
        "native_forward_s": native_forward_s,
        "copy_outputs_s": copy_outputs_s,
        "radiance_to_reflectance_jacobian_s": conversion_s,
    }


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


def add_final_evaluation_accounting(
    record: dict[str, Any],
    final_evaluation_trace: list[dict[str, Any]],
    lazy_final_evaluation_s: float,
    lazy_final_evaluation_cached: bool,
) -> dict[str, Any]:
    traced_final_evaluation_s = sum(
        float(item["total_evaluate_s"]) for item in final_evaluation_trace
    )
    return record | {
        "final_evaluation_mode": "lazy",
        "final_evaluation_in_retrieval_s": 0.0,
        "lazy_final_evaluation_s": lazy_final_evaluation_s,
        "lazy_final_evaluation_trace_s": traced_final_evaluation_s,
        "lazy_final_evaluation_cached": lazy_final_evaluation_cached,
        "retrieval_plus_lazy_final_evaluation_s": record["wall_s"] + lazy_final_evaluation_s,
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


def trace_summary(trace_records: list[dict[str, Any]]) -> dict[str, Any]:
    if not trace_records:
        return {
            "iterations": 0,
            "source": "cached_last_evaluation",
        }

    def phase(path: tuple[str, ...]) -> dict[str, float]:
        values = []
        for record in trace_records:
            value: Any = record
            for key in path:
                value = value[key]
            values.append(float(value))
        return stats(values)

    return {
        "iterations": len(trace_records),
        "settings_for_state_s": phase(("settings_for_state_s",)),
        "prepare_total_s": phase(("prepare_total_s",)),
        "prepare_python_total_s": phase(("prepare_trace", "python_total_s")),
        "prepare_native_call_s": phase(("prepare_trace", "native_call_s")),
        "prepare_parse_json_s": phase(("prepare_trace", "parse_json_s")),
        "prepare_load_inputs_s": phase(("prepare_trace", "load_inputs_s")),
        "prepare_build_scene_s": phase(("prepare_trace", "build_scene_s")),
        "prepare_optical_s": phase(("prepare_trace", "optical_prepare_s")),
        "native_forward_s": phase(("forward_evaluation_trace", "native_forward_s")),
        "copy_outputs_s": phase(("forward_evaluation_trace", "copy_outputs_s")),
        "radiance_to_reflectance_jacobian_s": phase(
            ("forward_evaluation_trace", "radiance_to_reflectance_jacobian_s")
        ),
        "scale_jacobian_s": phase(("scale_jacobian_s",)),
        "total_evaluate_s": phase(("total_evaluate_s",)),
    }


def main() -> int:
    case = build_case()
    profile = o2a_oe.pressure_altitude_profile_from_prepared_grid(case)
    state_vector = build_state_vector(case, profile)

    measurement_start = time.perf_counter()
    with zd.prepare(case) as prepared:
        measurement = measurement_from_o2a_baseline_noise(prepared)
    measurement_s = time.perf_counter() - measurement_start

    session_setup_start = time.perf_counter()
    session = zd.o2a_forward_session(case)
    session.enable_prepare_trace()
    session_setup_s = time.perf_counter() - session_setup_start
    try:
        iteration_trace: list[dict[str, Any]] = []
        session_start = time.perf_counter()
        session_result = run_retrieval(
            case,
            state_vector,
            measurement,
            forward_session=session,
            trace_records=iteration_trace,
        )
        session_reused_s = time.perf_counter() - session_start
        retrieval_iteration_trace = iteration_trace[: session_result.iterations]
        if object.__getattribute__(session_result, "_final_evaluation_factory") is not None:
            final_state = np.array(session_result.state, copy=True)
            session_result = dataclasses.replace(
                session_result,
                final_evaluation=None,
                _final_evaluation_factory=lambda: evaluate_final_state_with_trace(
                    case,
                    state_vector,
                    final_state,
                    iteration_trace,
                ),
            )
        lazy_final_start = time.perf_counter()
        _ = session_result.final_evaluation
        lazy_final_evaluation_s = time.perf_counter() - lazy_final_start
        final_evaluation_trace = iteration_trace[session_result.iterations :]
        trace_count_after_lazy_final = len(iteration_trace)
        _ = session_result.final_evaluation
        lazy_final_evaluation_cached = len(iteration_trace) == trace_count_after_lazy_final
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
        "session": {
            "setup_s": session_setup_s,
            "reused_retrieval": add_final_evaluation_accounting(
                retrieval_record(session_result, session_reused_s),
                final_evaluation_trace,
                lazy_final_evaluation_s,
                lazy_final_evaluation_cached,
            ),
            "reused_retrieval_iteration_trace": retrieval_iteration_trace,
            "reused_retrieval_iteration_trace_summary": trace_summary(retrieval_iteration_trace),
            "final_evaluation_trace": final_evaluation_trace,
            "final_evaluation_trace_summary": trace_summary(final_evaluation_trace),
            "first_use_retrieval_s": session_setup_s + session_reused_s,
        },
        "direct_prepared_call_probe": prepared_probe,
    }
    write_json(BENCHMARK_PATH, report)

    print("Slow forward+jacobian latency benchmark:")
    print(f"  measurement build: {measurement_s:.6f} s")
    print(
        "  session reused retrieval: "
        f"{report['session']['reused_retrieval']['wall_s']:.6f} s total, "
        f"{report['session']['reused_retrieval']['forward_model_and_jacobian_s']:.6f} s "
        "forward+jacobian"
    )
    print(
        "  lazy final evaluation: "
        f"{report['session']['reused_retrieval']['lazy_final_evaluation_s']:.6f} s "
        "when requested"
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
