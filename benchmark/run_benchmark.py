#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "numpy>=2.2",
# ]
# ///

"""Run the consolidated zdisamar benchmark."""

import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PYTHON_ROOT = REPO_ROOT / "python"
sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

from suite import config, native, report  # noqa: E402
from suite.db import BenchmarkDb  # noqa: E402
from suite.progress import Progress  # noqa: E402


def main() -> int:

    db = BenchmarkDb(config.DB_PATH)
    run_id = db.create_run(git=report.git_metadata(), command=config.COMMAND)
    progress = Progress(db, run_id)
    progress.log("benchmark", f"run {run_id} start")

    try:
        progress.log("native", "sync ReleaseFast binding")
        native_payload = native.sync_release_fast()
        db.summary(run_id, "native_binding", native_payload)
        progress.log("native", f"complete {native_payload['elapsed_s']:.3f}s")

        from suite import forward, retrieval

        started = time.perf_counter()
        forward.run(db, progress, run_id)
        retrieval.run(db, progress, run_id)
        db.finish_run(run_id, "complete")
        results = report.build_results(
            db,
            run_id,
            total_benchmark_wall_s=time.perf_counter() - started,
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
