#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# ///

"""Run the compact perturbation-sensitivity sweep and refresh its report."""

import argparse
import subprocess
import sys
from pathlib import Path

SCRIPT_PATH = Path(__file__).resolve()
REPO_ROOT = SCRIPT_PATH.parents[4]
PERTURBATION_DATA_ROOT = REPO_ROOT / "out" / "scaffolding" / "perturbation" / "data"
DEFAULT_OUTPUT_DIR = PERTURBATION_DATA_ROOT / "o2a-default"
ANALYZE_SCRIPT = SCRIPT_PATH.parents[1] / "analysis" / "analyze_perturbation_sweep.py"


def parse_args() -> argparse.Namespace:

    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--start-nm", type=float, default=758.0)
    parser.add_argument("--end-nm", type=float, default=770.0)
    parser.add_argument("--sample-count", type=int, default=241)
    parser.add_argument("--max-iterations", type=int, default=3)
    parser.add_argument("--skip-analysis", action="store_true")

    return parser.parse_args()


def main() -> int:

    args = parse_args()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    command = [
        "zig",
        "build",
        "perturbation-sensitivity",
        "-Doptimize=ReleaseFast",
        "--",
        "--output-dir",
        str(output_dir),
        "--start-nm",
        str(args.start_nm),
        "--end-nm",
        str(args.end_nm),
        "--sample-count",
        str(args.sample_count),
        "--max-iterations",
        str(args.max_iterations),
    ]
    subprocess.run(command, cwd=REPO_ROOT, check=True)

    if not args.skip_analysis:
        subprocess.run(
            [
                sys.executable,
                str(ANALYZE_SCRIPT),
                "--summary",
                str(output_dir / "summary.json"),
            ],
            cwd=REPO_ROOT,
            check=True,
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
