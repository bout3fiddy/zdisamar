#!/usr/bin/env -S uv run
# pyright: reportMissingTypeStubs=false, reportUnknownMemberType=false, reportUnknownVariableType=false

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import replace
import json
from pathlib import Path
import sys
import time
from typing import TypedDict, cast

import altair as alt
import pandas as pd


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

import python.zdisamar as zd
import python.zdisamar.plot as zp
from scripts.testing_harness.python_o2a_validation_spectrum import (
    DEFAULT_LIBRARY,
    MARKERS_NM,
    build_o2a_validation_scene,
    column_array,
    quantity_metrics,
    require_existing_file,
)


OUTPUT_DIR = REPO_ROOT / "out" / "ci" / "o2a_accuracy_target_sweep"
ACCURACY_TARGETS = (1.0e-12, 1.0e-11, 1.0e-10, 1.0e-9, 1.0e-6)
PLOT_TARGET = 1.0e-11
QUANTITIES = ("reflectance", "radiance", "irradiance")


class QuantityMetrics(TypedDict):
    mae: float
    rmse: float
    max_abs: float
    mean_signed: float


class RunTiming(TypedDict):
    prepare_o2a_s: float
    forward_model_s: float


class CaseRun(TypedDict):
    case_id: str
    accuracy_target: float | None
    timing: RunTiming
    generated_spectrum_csv: str


class TargetComparison(TypedDict):
    case_id: str
    accuracy_target: float
    speedup_vs_exact: float
    metrics_vs_exact: dict[str, QuantityMetrics]
    generated_spectrum_csv: str
    residual_plot_png: str | None


class SweepSummary(TypedDict):
    exact_runs: list[CaseRun]
    target_runs: list[TargetComparison]


_theme_enabler = cast(object, alt.data_transformers.disable_max_rows())
zp.use_theme("validation")


def clone_scene(scene: zd.O2AInput) -> zd.O2AInput:
    return zd.O2AInput.from_dict(scene.to_dict())


def scene_with_accuracy_target(scene: zd.O2AInput, accuracy_target: float | None) -> zd.O2AInput:
    cloned = clone_scene(scene)
    cloned.radiative_transfer = replace(cloned.radiative_transfer, accuracy_target=accuracy_target)
    return cloned


def build_varied_scene() -> zd.O2AInput:
    scene = clone_scene(build_o2a_validation_scene())
    scene.metadata = {
        **scene.metadata,
        "id": "o2a_accuracy_target_varied",
        "description": "Varied O2 A scene for accuracy_target validation.",
    }
    scene.scene_id = "o2a_accuracy_target_varied_python"
    scene.geometry = zd.Geometry(
        model="pseudo_spherical",
        solar_zenith_deg=42.0,
        viewing_zenith_deg=12.0,
        relative_azimuth_deg=35.0,
    )
    scene.surface = zd.Surface(albedo=0.08, pressure_hpa=1013.25)
    scene.aerosol = replace(
        scene.aerosol,
        optical_depth_550_nm=0.12,
        single_scatter_albedo=0.92,
        asymmetry_factor=0.55,
        angstrom_exponent=1.1,
        layer_center_km=5.1,
        layer_width_km=0.7,
    )
    return scene


def spectrum_frame(scene: zd.O2AInput, library_path: Path) -> tuple[pd.DataFrame, RunTiming]:
    prepare_start = time.perf_counter()
    with zd.prepare(scene, library_path=library_path) as prepared:
        prepare_s = time.perf_counter() - prepare_start
        forward_start = time.perf_counter()
        with prepared.forward_model() as spectrum:
            forward_s = time.perf_counter() - forward_start
            frame = cast(pd.DataFrame, zp.to_dataframe(spectrum))
    return frame, {"prepare_o2a_s": prepare_s, "forward_model_s": forward_s}


def metrics_against(current: pd.DataFrame, reference: pd.DataFrame) -> dict[str, QuantityMetrics]:
    return {
        quantity: quantity_metrics(column_array(current, quantity), column_array(reference, quantity))
        for quantity in QUANTITIES
    }


def write_spectrum(output_dir: Path, case_id: str, label: str, frame: pd.DataFrame) -> Path:
    path = output_dir / f"{case_id}_{label}.csv"
    frame.to_csv(path, index=False)
    return path


def residual_plot(current: pd.DataFrame, reference: pd.DataFrame, accuracy_target: float) -> alt.TopLevelMixin:
    panels = [
        zp.validation.residual(
            current,
            reference,
            quantity=quantity,
            tolerance=accuracy_target if quantity == "reflectance" else None,
        )
        for quantity in QUANTITIES
    ]
    return zp.spectrum.with_full_sample_spectrum(
        alt.vconcat(*panels).resolve_scale(x="shared"),
        current,
        quantity=zp.fields.REFLECTANCE,
        markers_nm=MARKERS_NM,
    )


def nearest_target(targets: Iterable[float], requested: float) -> float:
    return min(targets, key=lambda target: abs(target - requested))


def run_sweep(library_path: Path, output_dir: Path) -> SweepSummary:
    output_dir.mkdir(parents=True, exist_ok=True)
    scenes = [build_o2a_validation_scene(), build_varied_scene()]
    exact_runs: list[CaseRun] = []
    target_runs: list[TargetComparison] = []
    plot_target = nearest_target(ACCURACY_TARGETS, PLOT_TARGET)

    for scene in scenes:
        case_id = cast(str, scene.metadata["id"])
        exact_scene = scene_with_accuracy_target(scene, None)
        exact_frame, exact_timing = spectrum_frame(exact_scene, library_path)
        exact_path = write_spectrum(output_dir, case_id, "exact", exact_frame)
        exact_runs.append(
            {
                "case_id": case_id,
                "accuracy_target": None,
                "timing": exact_timing,
                "generated_spectrum_csv": str(exact_path),
            }
        )

        for accuracy_target in ACCURACY_TARGETS:
            target_scene = scene_with_accuracy_target(scene, accuracy_target)
            target_frame, target_timing = spectrum_frame(target_scene, library_path)
            target_path = write_spectrum(output_dir, case_id, f"target_{accuracy_target:.0e}", target_frame)
            plot_path: Path | None = None
            if accuracy_target == plot_target:
                plot_path = output_dir / f"{case_id}_target_{accuracy_target:.0e}_residuals.png"
                zp.save(residual_plot(target_frame, exact_frame, accuracy_target), plot_path, scale=1.35)

            target_runs.append(
                {
                    "case_id": case_id,
                    "accuracy_target": accuracy_target,
                    "speedup_vs_exact": exact_timing["forward_model_s"] / target_timing["forward_model_s"],
                    "metrics_vs_exact": metrics_against(target_frame, exact_frame),
                    "generated_spectrum_csv": str(target_path),
                    "residual_plot_png": None if plot_path is None else str(plot_path),
                }
            )

    summary: SweepSummary = {"exact_runs": exact_runs, "target_runs": target_runs}
    _ = (output_dir / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return summary


def main() -> int:
    summary = run_sweep(require_existing_file(DEFAULT_LIBRARY, "Native zdisamar library"), OUTPUT_DIR)
    for run in summary["target_runs"]:
        reflectance = run["metrics_vs_exact"]["reflectance"]
        print(
            (
                "case={case} target={target:.0e} speedup={speedup:.3f}x "
                "reflectance_max_abs={max_abs:.3e}"
            ).format(
                case=run["case_id"],
                target=run["accuracy_target"],
                speedup=run["speedup_vs_exact"],
                max_abs=reflectance["max_abs"],
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
