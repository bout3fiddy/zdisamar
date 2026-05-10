#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "matplotlib>=3.10",
#   "numpy>=2.2",
#   "pandas>=2.2",
# ]
# ///
# ruff: noqa: E402, I001

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from validation.common import o2a_retrieval_baseline as oe_baseline  # noqa: E402
import plot_validation  # noqa: E402


def main() -> int:
    for path in (
        plot_validation.PLOT_PATH,
        plot_validation.DATA_PATH,
        plot_validation.METRICS_PATH,
        plot_validation.MANIFEST_PATH,
    ):
        assert path.exists(), f"missing {path}"

    metrics_payload = json.loads(plot_validation.METRICS_PATH.read_text())
    metrics = metrics_payload["series"]
    assert metrics_payload["passes_reflectance_threshold"] is True
    assert metrics_payload["sample_count"] == oe_baseline.SAMPLE_COUNT
    assert len(metrics) == 3
    assert [metric["series"] for metric in metrics] == [
        "forward reflectance",
        "dR/d aerosol optical depth",
        "dR/d aerosol layer mid pressure",
    ]
    assert all(
        float(metric["max_abs_residual"]) <= plot_validation.REFLECTANCE_THRESHOLD
        for metric in metrics
    )

    manifest = json.loads(plot_validation.MANIFEST_PATH.read_text())
    assert manifest["canonical_command"] == plot_validation.CANONICAL_COMMAND
    assert manifest["tracked_outputs"] == [
        "validation/outputs/spectra/o2a_validation.png",
        "validation/outputs/spectra/o2a_validation_data.csv",
        "validation/outputs/spectra/comparison_metrics.json",
        "validation/outputs/spectra/bundle_manifest.json",
    ]
    assert "/Users/" not in plot_validation.MANIFEST_PATH.read_text()
    assert "/Users/" not in plot_validation.METRICS_PATH.read_text()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
