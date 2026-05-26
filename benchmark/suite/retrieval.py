"""Optimal-estimation benchmark phases."""

from typing import Any

from zdisamar import rtm
from zdisamar.inverse_method.optimal_estimation import o2a as band_retrieval

from validation.o2a.measurement_noise import measurement_from_o2a_baseline_noise
from validation.optimal_estimation import setup

from . import cases, config, residuals
from .db import BenchmarkDb
from .progress import Progress
from .stats import abs_stats, signed_stats, timing_stats
from .timing import combine, elapsed_since, timing_start


def run(db: BenchmarkDb, progress: Progress, run_id: str) -> dict[str, Any]:

    single = run_single_case(db, progress, run_id)
    sweep = run_sweep(db, progress, run_id)

    return {"single": single, "sweep": sweep}


def run_single_case(db: BenchmarkDb, progress: Progress, run_id: str) -> dict[str, Any]:

    phase = "retrieval/single"
    progress.log(phase, f"start {config.RETRIEVAL_REPEATS} repeats")
    case, reference = cases.retrieval_case()
    state_vector = setup.reference_two_state_vector(
        case=case,
        reference=reference,
    )
    measurement = measurement_from_o2a_baseline_noise(case)
    session_runs = [
        run_once(
            db,
            progress,
            run_id,
            phase=phase,
            mode="session",
            case_id="baseline",
            repeat=repeat,
            case=case,
            measurement=measurement,
            state_vector=state_vector,
        )
        for repeat in range(1, config.RETRIEVAL_REPEATS + 1)
    ]
    fast_case = cases.fast_case(case)
    fast_runs = [
        run_once(
            db,
            progress,
            run_id,
            phase=phase,
            mode="fast_mode",
            case_id="baseline",
            repeat=repeat,
            case=fast_case,
            measurement=measurement,
            state_vector=state_vector,
        )
        for repeat in range(1, config.RETRIEVAL_REPEATS + 1)
    ]
    layer_thickness = (
        case.aerosol.placement.bottom_pressure_hpa - case.aerosol.placement.top_pressure_hpa
    )
    session_result = session_runs[-1]["result"]
    fast_result = fast_runs[-1]["result"]
    session = single_summary(
        "OE, session",
        "session",
        session_runs,
        residuals.truth_residual(reference, session_result, layer_thickness),
    )
    fast = single_summary(
        "OE, fast mode",
        "fast_mode",
        fast_runs,
        residuals.result_delta(fast_result, session_result),
    )
    delta = residuals.result_delta(fast_result, session_result)
    db.summary(run_id, "retrieval_session", session)
    db.summary(run_id, "retrieval_fast_mode", fast)
    db.summary(run_id, "retrieval_fast_minus_session_single_case", delta)
    progress.log(phase, "complete")

    return {"session": session, "fast_mode": fast, "fast_minus_session": delta}


def run_sweep(db: BenchmarkDb, progress: Progress, run_id: str) -> dict[str, Any]:

    phase = "retrieval/sweep"
    sweep_cases = cases.sweep_cases()
    progress.log(phase, f"start {len(sweep_cases)} cases x 2 modes")
    session_rows = []
    fast_rows = []

    for item in sweep_cases:
        measurement = measurement_from_o2a_baseline_noise(item.case)
        state_vector = setup.aerosol_two_state_vector(
            initial=item.initial,
            surface_pressure_hpa=item.truth["surface_pressure_hpa"],
        )
        session = run_once(
            db,
            progress,
            run_id,
            phase=phase,
            mode="session",
            case_id=f"{item.index:03d}",
            repeat=1,
            case=item.case,
            measurement=measurement,
            state_vector=state_vector,
        )
        session_rows.append(sweep_row(item.index, item.truth, session))
        fast = run_once(
            db,
            progress,
            run_id,
            phase=phase,
            mode="fast_mode",
            case_id=f"{item.index:03d}",
            repeat=1,
            case=cases.fast_case(item.case),
            measurement=measurement,
            state_vector=state_vector,
        )
        fast_rows.append(sweep_row(item.index, item.truth, fast))

    session_summary = sweep_summary("OE sweep, session", "session", session_rows)
    fast_summary = sweep_summary("OE sweep, fast mode", "fast_mode", fast_rows)
    delta = sweep_delta(session_rows, fast_rows)
    db.summary(run_id, "retrieval_sweep_session", session_summary)
    db.summary(run_id, "retrieval_sweep_fast_mode", fast_summary)
    db.summary(run_id, "retrieval_sweep_fast_minus_session", delta)
    progress.log(phase, "complete")

    return {
        "session": session_summary,
        "fast_mode": fast_summary,
        "fast_minus_session": delta,
    }


def run_once(
    db: BenchmarkDb,
    progress: Progress,
    run_id: str,
    *,
    phase: str,
    mode: str,
    case_id: str,
    repeat: int,
    case: Any,
    measurement: Any,
    state_vector: Any,
) -> dict[str, Any]:

    setup_start = timing_start()

    with rtm.SessionCache(case) as cache:
        setup_timing = elapsed_since(setup_start)
        retrieval_start = timing_start()
        result = band_retrieval.retrieve(
            case=case,
            measurement=measurement,
            state_vector=state_vector,
            controls=setup.retrieval_controls(),
            cache=cache,
        )
        retrieval_timing = elapsed_since(retrieval_start)

    if not result.converged:
        raise RuntimeError(f"retrieval did not converge: {mode} {case_id}")

    first_use_total = combine([setup_timing, retrieval_timing])
    db.sample(
        run_id,
        phase="retrieval",
        mode=mode,
        case_id=case_id,
        repeat=repeat,
        elapsed_s=first_use_total.wall_s,
        payload={
            "setup_s": setup_timing.wall_s,
            "setup_process_cpu_s": setup_timing.process_cpu_s,
            "setup_average_active_cores": setup_timing.average_active_cores,
            "retrieval_s": retrieval_timing.wall_s,
            "retrieval_process_cpu_s": retrieval_timing.process_cpu_s,
            "retrieval_average_active_cores": retrieval_timing.average_active_cores,
            "first_use_total_process_cpu_s": first_use_total.process_cpu_s,
            "first_use_total_average_active_cores": first_use_total.average_active_cores,
        },
    )
    progress.log(
        phase,
        (
            f"{mode} case {case_id} repeat {repeat} "
            f"total {first_use_total.wall_s:.3f}s retrieval {retrieval_timing.wall_s:.3f}s"
        ),
    )

    return {
        "result": result,
        "setup_s": setup_timing.wall_s,
        "setup_process_cpu_s": setup_timing.process_cpu_s,
        "setup_average_active_cores": setup_timing.average_active_cores,
        "retrieval_s": retrieval_timing.wall_s,
        "retrieval_process_cpu_s": retrieval_timing.process_cpu_s,
        "retrieval_average_active_cores": retrieval_timing.average_active_cores,
        "first_use_total_s": first_use_total.wall_s,
        "first_use_total_process_cpu_s": first_use_total.process_cpu_s,
        "first_use_total_average_active_cores": first_use_total.average_active_cores,
    }


def single_summary(
    label: str,
    mode: str,
    runs: list[dict[str, Any]],
    result_residuals: dict[str, float],
) -> dict[str, Any]:

    return {
        "label": label,
        "kind": "optimal_estimation",
        "mode": mode,
        "timing_s": {
            "setup_s": timing_stats(run["setup_s"] for run in runs),
            "retrieval_s": timing_stats(run["retrieval_s"] for run in runs),
            "first_use_total_s": timing_stats(run["first_use_total_s"] for run in runs),
        },
        "process_cpu_s": {
            "setup_s": timing_stats(run["setup_process_cpu_s"] for run in runs),
            "retrieval_s": timing_stats(run["retrieval_process_cpu_s"] for run in runs),
            "first_use_total_s": timing_stats(run["first_use_total_process_cpu_s"] for run in runs),
        },
        "average_active_cores": {
            "setup": timing_stats(run["setup_average_active_cores"] for run in runs),
            "retrieval": timing_stats(run["retrieval_average_active_cores"] for run in runs),
            "first_use_total": timing_stats(
                run["first_use_total_average_active_cores"] for run in runs
            ),
        },
        "residuals": result_residuals,
    }


def sweep_summary(label: str, mode: str, rows: list[dict[str, Any]]) -> dict[str, Any]:

    return {
        "label": label,
        "kind": "optimal_estimation_sweep",
        "mode": mode,
        "run_count": len(rows),
        "converged_count": sum(1 for row in rows if row["converged"]),
        "timing_s": {
            "total_wall_s": sum(row["first_use_total_s"] for row in rows),
            "first_use_total_s": timing_stats(row["first_use_total_s"] for row in rows),
            "retrieval_s": timing_stats(row["retrieval_s"] for row in rows),
        },
        "process_cpu_s": {
            "total_process_cpu_s": sum(row["first_use_total_process_cpu_s"] for row in rows),
            "first_use_total_s": timing_stats(row["first_use_total_process_cpu_s"] for row in rows),
            "retrieval_s": timing_stats(row["retrieval_process_cpu_s"] for row in rows),
        },
        "average_active_cores": {
            "first_use_total": timing_stats(
                row["first_use_total_average_active_cores"] for row in rows
            ),
            "retrieval": timing_stats(row["retrieval_average_active_cores"] for row in rows),
        },
        "residuals": {
            "truth_aerosol_optical_depth_abs_error": abs_stats(
                row["aerosol_optical_depth_error"] for row in rows
            ),
            "truth_aerosol_mid_pressure_abs_error_hpa": abs_stats(
                row["aerosol_mid_pressure_error_hpa"] for row in rows
            ),
            "worst_aerosol_optical_depth_case": worst_abs_case(
                rows,
                "aerosol_optical_depth_error",
            ),
            "worst_aerosol_mid_pressure_case": worst_abs_case(
                rows,
                "aerosol_mid_pressure_error_hpa",
            ),
        },
    }


def sweep_row(index: int, truth: dict[str, float], run: dict[str, Any]) -> dict[str, Any]:

    result = run["result"]
    retrieved_aod = result.value("aerosol_optical_depth")
    retrieved_mid_pressure = result.value("aerosol_layer_mid_pressure_hpa")

    return {
        "case": index,
        "converged": bool(result.converged),
        "setup_s": run["setup_s"],
        "setup_process_cpu_s": run["setup_process_cpu_s"],
        "retrieval_s": run["retrieval_s"],
        "retrieval_process_cpu_s": run["retrieval_process_cpu_s"],
        "retrieval_average_active_cores": run["retrieval_average_active_cores"],
        "first_use_total_s": run["first_use_total_s"],
        "first_use_total_process_cpu_s": run["first_use_total_process_cpu_s"],
        "first_use_total_average_active_cores": run["first_use_total_average_active_cores"],
        "retrieved_aerosol_optical_depth": retrieved_aod,
        "retrieved_aerosol_mid_pressure_hpa": retrieved_mid_pressure,
        "aerosol_optical_depth_error": retrieved_aod - truth["aerosol_optical_depth"],
        "aerosol_mid_pressure_error_hpa": retrieved_mid_pressure
        - truth["aerosol_mid_pressure_hpa"],
    }


def sweep_delta(
    session_rows: list[dict[str, Any]],
    fast_rows: list[dict[str, Any]],
) -> dict[str, Any]:

    aod_deltas = []
    pressure_deltas = []
    retrieval_savings = []
    first_use_savings = []

    for session, fast in zip(session_rows, fast_rows, strict=True):
        aod_deltas.append(
            fast["retrieved_aerosol_optical_depth"] - session["retrieved_aerosol_optical_depth"]
        )
        pressure_deltas.append(
            fast["retrieved_aerosol_mid_pressure_hpa"]
            - session["retrieved_aerosol_mid_pressure_hpa"]
        )
        retrieval_savings.append(session["retrieval_s"] - fast["retrieval_s"])
        first_use_savings.append(session["first_use_total_s"] - fast["first_use_total_s"])

    return {
        "aerosol_optical_depth_delta": signed_stats(aod_deltas),
        "aerosol_mid_pressure_delta_hpa": signed_stats(pressure_deltas),
        "retrieval_speedup_s": signed_stats(retrieval_savings),
        "first_use_total_speedup_s": signed_stats(first_use_savings),
        "total_retrieval_wall_s_saved": sum(first_use_savings),
    }


def worst_abs_case(rows: list[dict[str, Any]], key: str) -> dict[str, float | int]:

    worst = max(rows, key=lambda row: abs(float(row[key])))

    return {"case": int(worst["case"]), "abs_value": abs(float(worst[key]))}
