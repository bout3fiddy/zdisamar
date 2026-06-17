"""Forward-model benchmark phases."""

from typing import Any

from zdisamar import rtm

from . import cases, config, residuals
from .db import BenchmarkDb
from .progress import Progress
from .stats import timing_stats
from .timing import combine, elapsed_since, timed, timing_start


def run(db: BenchmarkDb, progress: Progress, run_id: str) -> dict[str, Any]:

    case = cases.forward_case()
    no_session = run_no_session(db, progress, run_id, case)
    session = run_session(db, progress, run_id, case, no_session["sample"])
    fast_mode = run_fast_mode(db, progress, run_id)

    return {
        "no_session": no_session["summary"],
        "session": session,
        "fast_mode": fast_mode,
    }


def run_no_session(
    db: BenchmarkDb,
    progress: Progress,
    run_id: str,
    case: Any,
) -> dict[str, Any]:

    phase = "forward/no-session"
    progress.log(phase, f"start {config.FORWARD_REPEATS} repeats")
    samples = []

    for repeat in range(1, config.FORWARD_REPEATS + 1):
        timing, spectrum = timed(
            lambda: rtm.spectrum(
                case,
                jacobian=True,
            )
        )
        samples.append((timing, spectrum))
        db.sample(
            run_id,
            phase="forward",
            mode="no_session",
            case_id="baseline",
            repeat=repeat,
            elapsed_s=timing.wall_s,
            payload=timing_payload(timing),
        )
        progress.log(phase, f"repeat {repeat}/{config.FORWARD_REPEATS} {timing.wall_s:.3f}s")

    spectrum = samples[-1][1]
    metrics = residuals.reference_spectrum_metrics(case, spectrum)
    summary = {
        "label": "Forward, no session",
        "kind": "forward",
        "mode": "no_session",
        "timing_s": timing_stats(timing.wall_s for timing, _ in samples),
        "process_cpu_s": timing_stats(timing.process_cpu_s for timing, _ in samples),
        "average_active_cores": timing_stats(timing.average_active_cores for timing, _ in samples),
        "residuals": {
            "disamar_reference": {
                "worst_interior_max_abs": max(
                    metric["max_abs_residual"] for metric in metrics.values()
                ),
                "series": metrics,
            }
        },
    }
    db.summary(run_id, "forward_no_session", summary)
    progress.log(phase, "complete")

    return {"sample": spectrum, "summary": summary}


def run_session(
    db: BenchmarkDb,
    progress: Progress,
    run_id: str,
    case: Any,
    no_session_sample: Any,
) -> dict[str, Any]:

    phase = "forward/session"
    progress.log(phase, "start")
    setup_start = timing_start()

    with rtm.SessionCache(case) as cache:
        setup = elapsed_since(setup_start)
        db.sample(
            run_id,
            phase="forward",
            mode="session_setup",
            case_id="baseline",
            repeat=1,
            elapsed_s=setup.wall_s,
            payload=timing_payload(setup),
        )
        progress.log(phase, f"setup {setup.wall_s:.3f}s")
        first_timing, first_sample = timed(
            lambda: cache.spectrum(
                jacobian=True,
            )
        )
        db.sample(
            run_id,
            phase="forward",
            mode="session_first",
            case_id="baseline",
            repeat=1,
            elapsed_s=first_timing.wall_s,
            payload=timing_payload(first_timing),
        )
        progress.log(phase, f"first cached run {first_timing.wall_s:.3f}s")
        cached = []

        for repeat in range(1, config.FORWARD_REPEATS + 1):
            timing, _ = timed(
                lambda: cache.spectrum(
                    jacobian=True,
                )
            )
            cached.append(timing)
            db.sample(
                run_id,
                phase="forward",
                mode="session",
                case_id="baseline",
                repeat=repeat,
                elapsed_s=timing.wall_s,
                payload=timing_payload(timing),
            )
            progress.log(
                phase,
                f"cached repeat {repeat}/{config.FORWARD_REPEATS} {timing.wall_s:.3f}s",
            )

    first_use = combine([setup, first_timing])
    summary = {
        "label": "Forward, session",
        "kind": "forward",
        "mode": "session",
        "timing_s": {
            "setup_s": setup.wall_s,
            "first_use_total_s": first_use.wall_s,
            "first_cached_run_s": first_timing.wall_s,
            "cached_run_s": timing_stats(timing.wall_s for timing in cached),
        },
        "process_cpu_s": {
            "setup_s": setup.process_cpu_s,
            "first_use_total_s": first_use.process_cpu_s,
            "first_cached_run_s": first_timing.process_cpu_s,
            "cached_run_s": timing_stats(timing.process_cpu_s for timing in cached),
        },
        "average_active_cores": {
            "setup": setup.average_active_cores,
            "first_use_total": first_use.average_active_cores,
            "first_cached_run": first_timing.average_active_cores,
            "cached_run": timing_stats(timing.average_active_cores for timing in cached),
        },
        "residuals": {
            "vs_no_session": residuals.spectrum_delta_metrics(no_session_sample, first_sample)
        },
    }
    db.summary(run_id, "forward_session", summary)
    progress.log(phase, "complete")

    return summary


def run_fast_mode(db: BenchmarkDb, progress: Progress, run_id: str) -> dict[str, Any]:

    phase = "forward/fast-mode"
    scene_cases = cases.scene_cases()
    progress.log(phase, f"start {len(scene_cases)} scenes")
    reference_by_scene = {}
    reference_baseline_times = []

    for spec, case in scene_cases:
        timing, spectrum = timed(lambda case=case: rtm.spectrum(case))
        reference_by_scene[spec.label] = spectrum
        db.sample(
            run_id,
            phase="forward",
            mode="reference",
            case_id=spec.label,
            repeat=1,
            elapsed_s=timing.wall_s,
            payload=timing_payload(timing),
        )
        progress.log(phase, f"reference {spec.label} {timing.wall_s:.3f}s")

        if spec.label == "baseline":
            reference_baseline_times.append(timing)

    repeat_totals = []
    scene_metrics = {}

    for repeat in range(1, config.FORWARD_REPEATS + 1):
        scene_timings = []

        for spec, case in scene_cases:
            fast_case = cases.fast_case(case)
            timing, spectrum = timed(lambda fast_case=fast_case: rtm.spectrum(fast_case))
            scene_timings.append(timing)
            db.sample(
                run_id,
                phase="forward_fast_mode",
                mode="fast_mode",
                case_id=spec.label,
                repeat=repeat,
                elapsed_s=timing.wall_s,
                payload=timing_payload(timing),
            )

            if spec.label not in scene_metrics:
                scene_metrics[spec.label] = residuals.fast_scene_metrics(
                    spec.label,
                    reference_by_scene[spec.label],
                    spectrum,
                )

        total = combine(scene_timings)
        repeat_totals.append(total)
        progress.log(
            phase,
            f"repeat {repeat}/{config.FORWARD_REPEATS} four-scene total {total.wall_s:.3f}s",
        )

    worst = max(scene_metrics.values(), key=lambda metric: metric["max_abs_residual"])
    summary = {
        "label": "Forward, fast mode",
        "kind": "forward",
        "mode": "fast_mode",
        "timing_s": {
            "baseline_reference_run_s": timing_stats(
                timing.wall_s for timing in reference_baseline_times
            ),
            "four_scene_fast_total_s": timing_stats(timing.wall_s for timing in repeat_totals),
        },
        "process_cpu_s": {
            "baseline_reference_run_s": timing_stats(
                timing.process_cpu_s for timing in reference_baseline_times
            ),
            "four_scene_fast_total_s": timing_stats(
                timing.process_cpu_s for timing in repeat_totals
            ),
        },
        "average_active_cores": {
            "baseline_reference_run": timing_stats(
                timing.average_active_cores for timing in reference_baseline_times
            ),
            "four_scene_fast_total": timing_stats(
                timing.average_active_cores for timing in repeat_totals
            ),
        },
        "residuals": {
            "reference": "normal zdisamar forward",
            "baseline_max_abs": scene_metrics["baseline"]["max_abs_residual"],
            "worst_scene": worst,
            "scenes": scene_metrics,
        },
    }
    db.summary(run_id, "forward_fast_mode", summary)
    progress.log(phase, "complete")

    return summary


def timing_payload(timing: Any) -> dict[str, float]:

    return {
        "process_cpu_s": timing.process_cpu_s,
        "average_active_cores": timing.average_active_cores,
    }
