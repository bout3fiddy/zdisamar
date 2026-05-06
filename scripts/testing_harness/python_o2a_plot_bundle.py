#!/usr/bin/env -S uv run

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import sys

import numpy as np
import pandas as pd


REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
DEFAULT_OUTPUT_DIR = REPO_ROOT / "out" / "plots" / "python_plotting"
DEFAULT_REFERENCE = REPO_ROOT / "validation" / "data" / "o2a_with_cia_disamar_reference.csv"
MARKERS_NM = (755.0, 760.76, 776.0)
RESIDUAL_THRESHOLD = 1.0e-14


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate real core-backed O2 A plotting data and PNG plots.")
    parser.add_argument("--library", required=True, help="Path to the native zdisamar C shared library.")
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR), help="Output directory for data and PNGs.")
    parser.add_argument("--reference", default=str(DEFAULT_REFERENCE), help="Reference implementation spectrum CSV.")
    return parser.parse_args()


def import_runtime():
    sys.path.insert(0, str(PYTHON_ROOT))
    import altair as alt
    import zdisamar as zd
    import zdisamar.plot as zp

    alt.data_transformers.disable_max_rows()
    return zd, zp


def clean_output_dir(output_dir: Path) -> None:
    if output_dir.exists():
        shutil.rmtree(output_dir)
    (output_dir / "data").mkdir(parents=True, exist_ok=True)


def validation_grid(case) -> np.ndarray:
    return np.linspace(
        case.spectral_grid.start_nm,
        case.spectral_grid.end_nm,
        case.spectral_grid.sample_count,
        dtype=np.float64,
    )


def nearest_grid_values(grid: np.ndarray, targets_nm: tuple[float, ...]) -> np.ndarray:
    indexes = np.unique([int(np.argmin(np.abs(grid - target))) for target in targets_nm])
    return grid[indexes]


def instrument_grid_values(grid: np.ndarray) -> np.ndarray:
    sampled = grid[::35]
    anchors = nearest_grid_values(grid, MARKERS_NM)
    return np.unique(np.concatenate([sampled, anchors]))


def resample_reference(reference: pd.DataFrame, spectrum: pd.DataFrame) -> pd.DataFrame:
    wavelength_nm = spectrum["wavelength_nm"].to_numpy(dtype=float)
    output = {"wavelength_nm": wavelength_nm}
    for quantity in ("reflectance", "radiance", "irradiance"):
        output[quantity] = np.interp(
            wavelength_nm,
            reference["wavelength_nm"].to_numpy(dtype=float),
            reference[quantity].to_numpy(dtype=float),
        )
    return pd.DataFrame(output)


def reflectance_residuals(spectrum: pd.DataFrame, reference: pd.DataFrame) -> pd.DataFrame:
    residual = spectrum["reflectance"].to_numpy(dtype=float) - reference["reflectance"].to_numpy(dtype=float)
    return pd.DataFrame(
        {
            "wavelength_nm": spectrum["wavelength_nm"],
            "zig_implementation": spectrum["reflectance"],
            "reference_implementation": reference["reflectance"],
            "residual": residual,
            "abs_residual": np.abs(residual),
            "above_threshold": np.abs(residual) > RESIDUAL_THRESHOLD,
        }
    )


def validation_metrics(spectrum: pd.DataFrame, reference: pd.DataFrame) -> dict[str, object]:
    metrics: dict[str, object] = {
        "sample_count": int(len(spectrum)),
        "wavelength_min_nm": float(spectrum["wavelength_nm"].min()),
        "wavelength_max_nm": float(spectrum["wavelength_nm"].max()),
    }
    for quantity in ("reflectance", "radiance", "irradiance"):
        residual = spectrum[quantity].to_numpy(dtype=float) - reference[quantity].to_numpy(dtype=float)
        metrics[quantity] = {
            "mae": float(np.mean(np.abs(residual))),
            "rmse": float(np.sqrt(np.mean(np.square(residual)))),
            "max_abs": float(np.max(np.abs(residual))),
            "mean_signed": float(np.mean(residual)),
            "max_abs_wavelength_nm": float(spectrum["wavelength_nm"].iloc[int(np.argmax(np.abs(residual)))]),
        }
    return metrics


def write_csv(path: Path, frame: pd.DataFrame) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)


def write_json(path: Path, payload: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def progress(message: str) -> None:
    print(f"[python-o2a-plot-bundle] {message}", flush=True)


def collect_core_outputs(zd, zp, library_path: str, reference_path: Path):
    progress("loading native validation case")
    case = zd.o2a_disamar_reference_input(library_path)
    grid = validation_grid(case)
    selected_wavelengths = nearest_grid_values(grid, MARKERS_NM)
    response_wavelengths = instrument_grid_values(grid)

    with zd.prepare(case, library_path=library_path) as prepared:
        progress("running full forward model")
        with prepared.forward_model() as spectrum:
            spectrum_frame = zp.to_dataframe(spectrum)
            reference = resample_reference(pd.read_csv(reference_path), spectrum_frame)

            progress("collecting atmospheric budget")
            with prepared.atmosphere.budget(wavelengths_nm=grid) as budget:
                budget_frame = budget.to_pandas()
            progress("collecting O2-O2 collision-induced absorption diagnostics")
            with prepared.collision_induced_absorption.diagnostics(wavelengths_nm=grid) as collision_induced_absorption:
                collision_induced_absorption_frame = collision_induced_absorption.to_pandas()
            progress("collecting instrument-response diagnostics")
            with prepared.instrument_response.sampling_table(wavelengths_nm=response_wavelengths) as response:
                response_frame = response.to_pandas()
            progress("collecting radiative-transfer diagnostics")
            with prepared.radiative_transfer.diagnostics(wavelengths_nm=grid, spectrum=spectrum) as rt:
                rt_frame = rt.to_pandas()

    return {
        "case": case,
        "grid": grid,
        "selected_wavelengths": selected_wavelengths,
        "response_wavelengths": response_wavelengths,
        "spectrum": spectrum_frame,
        "reference": reference,
        "residuals": reflectance_residuals(spectrum_frame, reference),
        "metrics": validation_metrics(spectrum_frame, reference),
        "budget": budget_frame,
        "collision_induced_absorption": collision_induced_absorption_frame,
        "response": response_frame,
        "rt": rt_frame,
    }


def write_data_bundle(output_dir: Path, bundle: dict[str, object]) -> None:
    data_dir = output_dir / "data"
    write_csv(data_dir / "generated_spectrum.csv", bundle["spectrum"])
    write_csv(data_dir / "reference_resampled.csv", bundle["reference"])
    write_csv(data_dir / "reflectance_residuals.csv", bundle["residuals"])
    write_json(data_dir / "validation_metrics.json", bundle["metrics"])
    write_csv(data_dir / "atmospheric_budget.csv", bundle["budget"])
    write_csv(data_dir / "collision_induced_absorption_diagnostics.csv", bundle["collision_induced_absorption"])
    write_csv(data_dir / "instrument_response.csv", bundle["response"])
    write_csv(data_dir / "radiative_transfer_diagnostics.csv", bundle["rt"])


def wavelength_slug(wavelength_nm: float) -> str:
    return f"{float(wavelength_nm):08.5f}".replace(".", "_") + "_nm"


def build_plots(zp, bundle: dict[str, object]) -> dict[str, object]:
    spectrum = bundle["spectrum"]
    reference = bundle["reference"]
    selected_wavelengths = [float(value) for value in bundle["selected_wavelengths"]]

    charts: dict[str, object] = {
        "validation/full_sampled_reflectance": zp.validation.residual_highlight_spectrum(
            spectrum,
            reference,
            quantity=zp.fields.REFLECTANCE,
            residual_threshold=RESIDUAL_THRESHOLD,
        ),
        "validation/reflectance_residual_histogram": zp.validation.residual_histogram(
            spectrum,
            reference,
            quantity=zp.fields.REFLECTANCE,
        ),
        "validation/reflectance_residual_by_wavelength": zp.validation.residual_by_wavelength(
            spectrum,
            reference,
            quantity=zp.fields.REFLECTANCE,
            residual_threshold=RESIDUAL_THRESHOLD,
        ),
        "validation/radiance_against_reference": zp.validation.overlay(
            spectrum,
            reference,
            quantity=zp.fields.RADIANCE,
            reference_label="Reference implementation",
            current_label="Zig implementation",
        ),
        "validation/validation_metrics": zp.validation.metrics_bar(spectrum, reference),
        "atmosphere/total_optical_depth_heatmap": zp.atmosphere.optical_depth_heatmap(
            bundle["budget"],
            quantity=zp.fields.TOTAL_OPTICAL_DEPTH,
            markers_nm=MARKERS_NM,
        ),
        "atmosphere/optical_depth_component_stack": zp.atmosphere.component_stack(bundle["budget"]),
        "collision_induced_absorption/share_spectrum": zp.collision_induced_absorption.share_spectrum(bundle["collision_induced_absorption"]),
        "instrument_response/isrf_" + wavelength_slug(760.76): zp.instrument_response.isrf(
            bundle["response"],
            nominal_wavelength_nm=760.76,
        ),
    }
    for wavelength_nm in selected_wavelengths:
        suffix = wavelength_slug(wavelength_nm)
        charts[f"atmosphere/total_optical_depth_profile_{suffix}"] = zp.atmosphere.optical_depth_profile(
            bundle["budget"],
            quantity=zp.fields.TOTAL_OPTICAL_DEPTH,
            wavelengths_nm=(wavelength_nm,),
        )
        charts[f"atmosphere/single_scatter_albedo_profile_{suffix}"] = zp.atmosphere.single_scatter_albedo_profile(
            bundle["budget"],
            wavelengths_nm=(wavelength_nm,),
        )
        charts[f"collision_induced_absorption/share_profile_{suffix}"] = zp.collision_induced_absorption.share_profile(
            bundle["collision_induced_absorption"],
            wavelength_nm=wavelength_nm,
        )
        charts[f"collision_induced_absorption/optical_depth_profile_{suffix}"] = zp.collision_induced_absorption.optical_depth_profile(
            bundle["collision_induced_absorption"],
            wavelength_nm=wavelength_nm,
        )
        charts[f"collision_induced_absorption/cross_section_temperature_{suffix}"] = zp.collision_induced_absorption.cross_section_temperature(
            bundle["collision_induced_absorption"],
            wavelength_nm=wavelength_nm,
        )
    return charts


def save_plots(zp, output_dir: Path, charts: dict[str, object]) -> list[str]:
    outputs: list[str] = []
    for stem, chart in charts.items():
        path = output_dir / f"{stem}.png"
        path.parent.mkdir(parents=True, exist_ok=True)
        chart.to_dict()
        zp.save(chart, path, scale=1.35)
        outputs.append(str(path.relative_to(output_dir)))
    return outputs


def write_manifest(output_dir: Path, bundle: dict[str, object], plots: list[str]) -> None:
    data_dir = output_dir / "data"
    data_sources = {
        "generated_spectrum.csv": "core",
        "reference_resampled.csv": "reference_resampled",
        "reflectance_residuals.csv": "core_reference_comparison",
        "validation_metrics.json": "core_reference_comparison",
        "atmospheric_budget.csv": "core",
        "collision_induced_absorption_diagnostics.csv": "core",
        "instrument_response.csv": "core",
        "radiative_transfer_diagnostics.csv": "core",
    }
    manifest = {
        "schema_version": 1,
        "source": "core",
        "case_id": bundle["case"].metadata["id"],
        "sample_count": int(len(bundle["spectrum"])),
        "residual_threshold": RESIDUAL_THRESHOLD,
        "selected_wavelengths_nm": [float(value) for value in bundle["selected_wavelengths"]],
        "instrument_response_wavelength_count": int(len(bundle["response_wavelengths"])),
        "data_sources": data_sources,
        "data_outputs": sorted(str(path.relative_to(output_dir)) for path in data_dir.iterdir()),
        "plot_outputs": sorted(plots),
    }
    write_json(output_dir / "manifest.json", manifest)


def main() -> int:
    args = parse_args()
    output_dir = Path(args.output_dir)
    reference_path = Path(args.reference)
    clean_output_dir(output_dir)

    zd, zp = import_runtime()
    zp.use_theme("validation")
    bundle = collect_core_outputs(zd, zp, args.library, reference_path)
    write_data_bundle(output_dir, bundle)
    charts = build_plots(zp, bundle)
    plots = save_plots(zp, output_dir, charts)
    write_manifest(output_dir, bundle, plots)

    print(f"wrote {len(plots)} real core-backed plot files under {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
