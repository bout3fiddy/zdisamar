#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "numpy>=2.2",
# ]
# ///

"""Run the fast zdisamar benchmark canary."""

import json
import os
import sys
from pathlib import Path
from typing import Any

FORWARD_REPEATS = 3
RETRIEVAL_REPEATS = 2
OE_SWEEP_CASE_INDICES = (1, 3)
FAST_SCENE_LABELS = ("baseline", "oblique aerosol")
WORKER_LIMIT = 2
WORKER_LIMIT_ENV = "ZDISAMAR_WORKER_LIMIT"

REPO_ROOT = Path(__file__).resolve().parents[1]
PYTHON_ROOT = REPO_ROOT / "python"
sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

from suite import config, native, report  # noqa: E402
from suite.db import BenchmarkDb  # noqa: E402
from suite.progress import Progress  # noqa: E402
from suite.timing import elapsed_since, timing_start  # noqa: E402

WP5_RETRIEVAL_ERRORS = (
    "UnsupportedOptimalEstimation",
    "UnsupportedOptimalEstimationCorrection",
    "UnsupportedOptimalEstimationBatch",
    "UnsupportedFastmodeOptimalEstimationBatch",
)


def configure_runtime_defaults() -> None:

    config.BENCHMARK_NAME = "zdisamar_fast"
    config.COMMAND = "uv run benchmark/run_benchmark_fast.py"
    config.DB_PATH = config.RUNS_DIR / "benchmark_fast.sqlite"
    config.RESULTS_PATH = config.FAST_RESULTS_PATH
    config.FORWARD_REPEATS = FORWARD_REPEATS
    config.RETRIEVAL_REPEATS = RETRIEVAL_REPEATS
    config.SWEEP_COUNT = len(OE_SWEEP_CASE_INDICES)
    config.SWEEP_CASE_INDICES = OE_SWEEP_CASE_INDICES
    config.FAST_SCENE_LABELS = FAST_SCENE_LABELS
    config.WORKER_LIMIT_ENV = WORKER_LIMIT_ENV
    config.WORKER_LIMIT = WORKER_LIMIT
    host_cpu_count = os.cpu_count() or 1
    config.HOST_CPU_COUNT = host_cpu_count
    config.EFFECTIVE_WORKER_CAP = min(WORKER_LIMIT, host_cpu_count)
    os.environ[WORKER_LIMIT_ENV] = str(WORKER_LIMIT)


def main() -> int:

    configure_runtime_defaults()

    config.DB_PATH.unlink(missing_ok=True)
    db = BenchmarkDb(config.DB_PATH)
    run_id = db.create_run(git=report.git_metadata(), command=config.COMMAND)
    progress = Progress(db, run_id)
    progress.log("benchmark-fast", f"run {run_id} start")
    progress.log(
        "benchmark-fast",
        f"worker cap {config.EFFECTIVE_WORKER_CAP} of {config.HOST_CPU_COUNT} host CPUs",
    )

    try:
        progress.log("native", "sync ReleaseFast binding")
        native_payload = native.sync_release_fast()
        db.summary(run_id, "native_binding", native_payload)
        progress.log("native", f"complete {native_payload['elapsed_s']:.3f}s")

        from suite import forward, retrieval

        started = timing_start()
        forward_result = forward.run(db, progress, run_id)
        retrieval_result = run_retrieval_or_skip(db, progress, run_id, retrieval)
        total_timing = elapsed_since(started)
        db.finish_run(run_id, "complete")
        results = build_fast_results(total_timing, forward_result, retrieval_result)
        write_json_atomic(config.RESULTS_PATH, results)
        progress.log("benchmark-fast", f"wrote {config.RESULTS_PATH.relative_to(config.REPO_ROOT)}")

        return 0
    except BaseException:
        db.finish_run(run_id, "error")
        raise
    finally:
        db.close()


def run_retrieval_or_skip(
    db: BenchmarkDb,
    progress: Progress,
    run_id: str,
    retrieval_module: Any,
) -> dict[str, Any] | None:

    try:
        return retrieval_module.run(db, progress, run_id)
    except RuntimeError as exc:
        reason = str(exc)
        if reason not in WP5_RETRIEVAL_ERRORS:
            raise

        payload = {
            "status": "skipped",
            "reason": reason,
            "owner": "WP5",
        }
        db.summary(run_id, "retrieval_skipped", payload)
        progress.log("retrieval", f"skipped until WP5: {reason}")
        return None


def build_fast_results(
    total_timing: Any,
    forward_result: dict[str, Any],
    retrieval_result: dict[str, Any] | None,
) -> dict[str, Any]:

    no_session = forward_result["no_session"]
    session = forward_result["session"]
    fast_forward = forward_result["fast_mode"]

    session_delta = session["residuals"]["vs_no_session"]
    fast_forward_residuals = fast_forward["residuals"]
    retrieval_cases: dict[str, Any] = {
        "oe_session": {
            "status": "skipped",
            "reason": "WP5 retrieval path not run",
        },
        "oe_sweep": {
            "status": "skipped",
            "reason": "WP5 retrieval path not run",
        },
    }
    if retrieval_result is not None:
        retrieval_session = retrieval_result["single"]["session"]
        retrieval_sweep = retrieval_result["sweep"]
        sweep_delta = retrieval_sweep["fast_minus_session"]
        retrieval_cases = {
            "oe_session": {
                "n": retrieval_session["timing_s"]["retrieval_s"]["runs"],
                "median_retrieval_s": rounded(
                    retrieval_session["timing_s"]["retrieval_s"]["median"]
                ),
                "aod_abs_diff": retrieval_session["residuals"][
                    "aerosol_optical_depth_abs_diff"
                ],
            },
            "oe_sweep": {
                "cases": list(OE_SWEEP_CASE_INDICES),
                "session_total_s": rounded(
                    retrieval_sweep["session"]["timing_s"]["retrieval_s"]["total"]
                ),
                "fast_total_s": rounded(
                    retrieval_sweep["fast_mode"]["timing_s"]["retrieval_s"]["total"]
                ),
                "fast_vs_session_aod_max_abs": sweep_delta["aerosol_optical_depth_delta"][
                    "max_abs"
                ],
            },
        }

    return {
        "schema": 1,
        "benchmark": "zdisamar_fast",
        "status": "complete",
        "worker_cap": config.EFFECTIVE_WORKER_CAP,
        "wall_s": rounded(total_timing.wall_s),
        "cpu_s": rounded(total_timing.process_cpu_s),
        "cases": {
            "forward_no_session": {
                "n": no_session["timing_s"]["runs"],
                "median_s": rounded(no_session["timing_s"]["median"]),
                "residual_max_abs": no_session["residuals"]["disamar_reference"][
                    "worst_interior_max_abs"
                ],
            },
            "forward_session": {
                "n": session["timing_s"]["cached_run_s"]["runs"],
                "median_s": rounded(session["timing_s"]["cached_run_s"]["median"]),
                "vs_no_session_max_abs": max(float(value) for value in session_delta.values()),
            },
            "forward_fast_mode": {
                "scenes": list(fast_forward_residuals["scenes"].keys()),
                "median_total_s": rounded(
                    fast_forward["timing_s"]["four_scene_fast_total_s"]["median"]
                ),
                "worst_residual_max_abs": fast_forward_residuals["worst_scene"]["max_abs_residual"],
            },
            **retrieval_cases,
        },
    }


def rounded(value: float) -> float:

    return round(float(value), 9)


def write_json_atomic(path: Path, payload: dict[str, Any]) -> None:

    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(payload, indent=2) + "\n")
    temporary.replace(path)


if __name__ == "__main__":
    raise SystemExit(main())
