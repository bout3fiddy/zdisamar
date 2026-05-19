#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "numpy>=2.2",
# ]
# ///

"""Run the consolidated zdisamar benchmark."""

import os
import sys
from pathlib import Path

OE_SWEEP_COUNT = 5
WORKER_LIMIT = 2
WORKER_LIMIT_ENV = "ZDISAMAR_WORKER_LIMIT"

REPO_ROOT = Path(__file__).resolve().parents[1]
PYTHON_ROOT = REPO_ROOT / "python"
sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

from suite import config, layout, memory, native, report  # noqa: E402
from suite.db import BenchmarkDb  # noqa: E402
from suite.progress import Progress  # noqa: E402
from suite.timing import elapsed_since, timing_start  # noqa: E402


def configure_runtime_defaults() -> None:

    config.SWEEP_COUNT = OE_SWEEP_COUNT
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
    memory_probe = memory.start_peak_rss_probe()
    progress = Progress(db, run_id)
    progress.log("benchmark", f"run {run_id} start")
    progress.log(
        "benchmark",
        f"worker cap {config.EFFECTIVE_WORKER_CAP} of {config.HOST_CPU_COUNT} host CPUs",
    )

    try:
        progress.log("native", "sync ReleaseFast binding")
        native_payload = native.sync_release_fast()
        db.summary(run_id, "native_binding", native_payload)
        progress.log("native", f"complete {native_payload['elapsed_s']:.3f}s")

        from suite import forward, retrieval

        started = timing_start()
        forward.run(db, progress, run_id)
        retrieval.run(db, progress, run_id)
        total_timing = elapsed_since(started)
        memory_payload = memory_probe.finish()
        progress.log("layout", "start post-timing memory-layout diagnostics")
        memory_layout = layout.memory_layout_diagnostics()
        db.summary(run_id, "memory_layout", memory_layout)
        progress.log("layout", "complete")
        db.finish_run(run_id, "complete")
        results = report.build_results(
            db,
            run_id,
            total_benchmark_wall_s=total_timing.wall_s,
            total_benchmark_process_cpu_s=total_timing.process_cpu_s,
            memory=memory_payload,
            memory_layout=memory_layout,
        )
        report.write_json_atomic(config.RESULTS_PATH, results)
        progress.log("benchmark", f"wrote {config.RESULTS_PATH.relative_to(config.REPO_ROOT)}")

        return 0
    except BaseException:
        db.finish_run(run_id, "error")
        raise
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
