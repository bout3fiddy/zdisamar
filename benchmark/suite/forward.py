"""Forward-model benchmark phases."""

import time
from typing import Any

from zdisamar import rtm

from . import cases, config, residuals
from .db import BenchmarkDb
from .progress import Progress
from .stats import timing_stats
from .timing import timed


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
        elapsed_s, spectrum = timed(
            lambda: rtm.spectrum(
                case,
                jacobian=True,
                jacobian_state_names=config.FORWARD_STATE_NAMES,
            )
        )
        samples.append((elapsed_s, spectrum))
        db.sample(
            run_id,
            phase="forward",
            mode="no_session",
            case_id="baseline",
            repeat=repeat,
            elapsed_s=elapsed_s,
        )
        progress.log(phase, f"repeat {repeat}/{config.FORWARD_REPEATS} {elapsed_s:.3f}s")

    spectrum = samples[-1][1]
    metrics = residuals.reference_spectrum_metrics(case, spectrum)
    summary = {
        "label": "Forward, no session",
        "kind": "forward",
        "mode": "no_session",
        "timing_s": timing_stats(elapsed_s for elapsed_s, _ in samples),
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
    setup_start = time.perf_counter()

    with rtm.SessionCache(case) as cache:
        setup_s = time.perf_counter() - setup_start
        db.sample(
            run_id,
            phase="forward",
            mode="session_setup",
            case_id="baseline",
            repeat=1,
            elapsed_s=setup_s,
        )
        progress.log(phase, f"setup {setup_s:.3f}s")
        first_elapsed_s, first_sample = timed(
            lambda: cache.spectrum(
                jacobian=True,
                jacobian_state_names=config.FORWARD_STATE_NAMES,
            )
        )
        db.sample(
            run_id,
            phase="forward",
            mode="session_first",
            case_id="baseline",
            repeat=1,
            elapsed_s=first_elapsed_s,
        )
        progress.log(phase, f"first cached run {first_elapsed_s:.3f}s")
        cached = []

        for repeat in range(1, config.FORWARD_REPEATS + 1):
            elapsed_s, _ = timed(
                lambda: cache.spectrum(
                    jacobian=True,
                    jacobian_state_names=config.FORWARD_STATE_NAMES,
                )
            )
            cached.append(elapsed_s)
            db.sample(
                run_id,
                phase="forward",
                mode="session",
                case_id="baseline",
                repeat=repeat,
                elapsed_s=elapsed_s,
            )
            progress.log(
                phase,
                f"cached repeat {repeat}/{config.FORWARD_REPEATS} {elapsed_s:.3f}s",
            )

    summary = {
        "label": "Forward, session",
        "kind": "forward",
        "mode": "session",
        "timing_s": {
            "setup_s": setup_s,
            "first_use_total_s": setup_s + first_elapsed_s,
            "first_cached_run_s": first_elapsed_s,
            "cached_run_s": timing_stats(cached),
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
        elapsed_s, spectrum = timed(lambda case=case: rtm.spectrum(case))
        reference_by_scene[spec.label] = spectrum
        db.sample(
            run_id,
            phase="forward",
            mode="reference",
            case_id=spec.label,
            repeat=1,
            elapsed_s=elapsed_s,
        )
        progress.log(phase, f"reference {spec.label} {elapsed_s:.3f}s")

        if spec.label == "baseline":
            reference_baseline_times.append(elapsed_s)

    repeat_totals = []
    scene_metrics = {}

    for repeat in range(1, config.FORWARD_REPEATS + 1):
        total_s = 0.0

        for spec, case in scene_cases:
            fast_case = cases.fast_case(case)
            elapsed_s, spectrum = timed(lambda fast_case=fast_case: rtm.spectrum(fast_case))
            total_s += elapsed_s
            db.sample(
                run_id,
                phase="forward_fast_mode",
                mode="fast_mode",
                case_id=spec.label,
                repeat=repeat,
                elapsed_s=elapsed_s,
            )

            if spec.label not in scene_metrics:
                scene_metrics[spec.label] = residuals.fast_scene_metrics(
                    spec.label,
                    reference_by_scene[spec.label],
                    spectrum,
                )

        repeat_totals.append(total_s)
        progress.log(
            phase,
            f"repeat {repeat}/{config.FORWARD_REPEATS} four-scene total {total_s:.3f}s",
        )

    worst = max(scene_metrics.values(), key=lambda metric: metric["max_abs_residual"])
    summary = {
        "label": "Forward, fast mode",
        "kind": "forward",
        "mode": "fast_mode",
        "timing_s": {
            "baseline_reference_run_s": timing_stats(reference_baseline_times),
            "four_scene_fast_total_s": timing_stats(repeat_totals),
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
