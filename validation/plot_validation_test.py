#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "matplotlib>=3.10",
#   "numpy>=2.2",
#   "pandas>=2.2",
# ]
# ///

from __future__ import annotations

import json

import plot_validation


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
    assert metrics_payload["sample_count"] == 701
    assert len(metrics) == 4
    assert [metric["series"] for metric in metrics] == [
        "forward reflectance",
        "dR/d surface albedo",
        "dR/d aerosol optical depth",
        "dR/d aerosol layer mid pressure",
    ]
    assert all(float(metric["max_abs_residual"]) <= plot_validation.REFLECTANCE_THRESHOLD for metric in metrics)

    manifest = json.loads(plot_validation.MANIFEST_PATH.read_text())
    assert manifest["canonical_command"] == plot_validation.CANONICAL_COMMAND
    assert manifest["tracked_outputs"] == [
        "validation/plots/o2a_validation.png",
        "validation/data/o2a_validation_data.csv",
        "validation/data/comparison_metrics.json",
        "validation/data/bundle_manifest.json",
    ]
    assert "/Users/" not in plot_validation.MANIFEST_PATH.read_text()
    assert "/Users/" not in plot_validation.METRICS_PATH.read_text()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
