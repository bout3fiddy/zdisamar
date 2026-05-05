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

import copy
import json
import math
from pathlib import Path
import sys

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.ticker import ScalarFormatter


plt.rcParams.update(
    {
        "axes.edgecolor": "black",
        "axes.linewidth": 0.8,
        "figure.facecolor": "white",
        "font.family": "monospace",
        "font.monospace": ["DejaVu Sans Mono", "Menlo", "Monaco", "Courier New", "monospace"],
        "grid.color": "#b0b0b0",
        "grid.linewidth": 0.65,
        "mathtext.fontset": "dejavusans",
        "savefig.facecolor": "white",
    }
)

REPO_ROOT = Path(__file__).resolve().parents[1]
PYTHON_ROOT = REPO_ROOT / "python"
LIBRARY_NAME = "libzdisamar_c.dylib" if sys.platform == "darwin" else "libzdisamar_c.so"
LIBRARY_PATH = REPO_ROOT / "zig-out" / "lib" / LIBRARY_NAME
VALIDATION_DIR = REPO_ROOT / "validation"
VALIDATION_DATA_DIR = VALIDATION_DIR / "data"
VALIDATION_PLOTS_DIR = VALIDATION_DIR / "plots"

FORWARD_REFERENCE_PATH = VALIDATION_DATA_DIR / "o2a_jacobian_retrieval_instrument_forward.csv"
REFLECTANCE_JACOBIAN_REFERENCE_PATH = VALIDATION_DATA_DIR / "o2a_jacobian_simulation_instrument_reflectance.csv"

PLOT_PATH = VALIDATION_PLOTS_DIR / "o2a_validation.png"
DATA_PATH = VALIDATION_DATA_DIR / "o2a_validation_data.csv"
METRICS_PATH = VALIDATION_DATA_DIR / "comparison_metrics.json"
MANIFEST_PATH = VALIDATION_DATA_DIR / "bundle_manifest.json"

CANONICAL_COMMAND = "zig build o2a-plot-bundle"
REFLECTANCE_THRESHOLD = 1.0e-13
STATE_NAMES = (
    "surface_albedo",
    "aerosol_optical_depth",
    "aerosol_layer_mid_pressure_hpa",
)
REFERENCE_COLUMNS = {
    "surface_albedo": "surfAlbedo",
    "aerosol_optical_depth": "aerosolTau",
    "aerosol_layer_mid_pressure_hpa": "intervalDP",
}
BLOWUP_REGION_FRACTION = 0.40
BLOWUP_REGION_PADDING_NM = 0.04
BLOWUP_REGION_LIMITS = {
    "forward reflectance": 3,
    "dR/d surface albedo": 3,
    "dR/d aerosol optical depth": 3,
    "dR/d aerosol layer mid pressure": 2,
}
MATPLOTLIB_BLUE = "#1f77b4"
MATPLOTLIB_ORANGE = "#ff7f0e"
MATPLOTLIB_RED = "#d62728"
MATPLOTLIB_GRID = "#b0b0b0"


def import_zdisamar():
    sys.path.insert(0, str(PYTHON_ROOT))
    import zdisamar as zd

    return zd


def asset(zd, id: str, path: str, format: str):
    return zd.ReferenceAsset(id=id, path=path, format=format)


def build_validation_case(zd):
    return zd.O2AInput(
        metadata={
            "id": "disamar_reference_o2a_jacobian_validation",
            "storage": "disamar-reference-o2a-jacobian-validation",
            "description": "Hardcoded DISAMAR O2 A Jacobian validation case.",
        },
        plan={
            "model_family": "disamar_standard",
            "transport_solver": "dispatcher",
            "execution_solver_mode": "scalar",
            "execution_derivative_mode": "none",
        },
        reference_assets=zd.ReferenceAssets(
            atmosphere_profile=asset(
                zd,
                "atmosphere_profile",
                "data/reference_data/climatologies/vendor_config_o2a_profile.csv",
                "profile_csv",
            ),
            vendor_reference_csv=asset(
                zd,
                "vendor_reference_csv",
                "validation/data/o2a_with_cia_disamar_reference.csv",
                "disamar_o2a_reference_csv",
            ),
            raw_solar_reference=asset(
                zd,
                "raw_solar_reference",
                "data/reference_data/solar/o2a_solar_reference_753_778.csv",
                "solar_reference_csv",
            ),
            airmass_factor_lut=asset(
                zd,
                "airmass_factor_lut",
                "data/reference_data/luts/airmass_factor_nadir_demo.csv",
                "csv",
            ),
        ),
        scene_id="o2a_disamar_reference_jacobian_validation",
        spectral_grid=zd.SpectralGrid(start_nm=755.0, end_nm=776.0, sample_count=701),
        atmosphere=zd.Atmosphere(
            layer_count=3,
            sublayer_divisions=4,
            fit_interval_index_1based=2,
            intervals=[
                zd.VerticalInterval(
                    index_1based=1,
                    top_pressure_hpa=0.3,
                    bottom_pressure_hpa=875.0,
                    altitude_divisions=28,
                ),
                zd.VerticalInterval(
                    index_1based=2,
                    top_pressure_hpa=875.0,
                    bottom_pressure_hpa=925.0,
                    altitude_divisions=2,
                ),
                zd.VerticalInterval(
                    index_1based=3,
                    top_pressure_hpa=925.0,
                    bottom_pressure_hpa=1013.25,
                    altitude_divisions=4,
                ),
            ],
        ),
        surface=zd.Surface(albedo=0.2, pressure_hpa=1013.25),
        geometry=zd.Geometry(
            model="pseudo_spherical",
            solar_zenith_deg=60.0,
            viewing_zenith_deg=0.0,
            relative_azimuth_deg=0.0,
        ),
        aerosol=zd.Aerosol(
            optical_depth_550_nm=0.3,
            single_scatter_albedo=1.0,
            asymmetry_factor=0.7,
            angstrom_exponent=0.0,
            reference_wavelength_nm=550.0,
            layer_center_km=5.4,
            layer_width_km=0.4,
            placement=zd.AerosolPlacement(
                semantics="explicit_interval_bounds",
                interval_index_1based=2,
                top_pressure_hpa=875.0,
                bottom_pressure_hpa=925.0,
            ),
        ),
        instrument_response=zd.InstrumentResponse(
            instrument_name="disamar-o2a-jacobian-validation",
            regime="nadir",
            sampling="native",
            noise_model="none",
            instrument_line_fwhm_nm=0.38,
            builtin_line_shape="flat_top_n4",
            high_resolution_step_nm=0.01,
            high_resolution_half_span_nm=1.14,
            adaptive_reference_grid={
                "points_per_fwhm": 12,
                "strong_line_min_divisions": 8,
                "strong_line_max_divisions": 30,
            },
            solar_reference_asset_id="raw_solar_reference",
        ),
        o2_lines=zd.O2LineByLine(
            line_list_asset=asset(
                zd,
                "o2_hitran",
                "vendor/disamar-fortran/RefSpec/07_HIT08_TROPOMI.par",
                "hitran_par_o2a",
            ),
            line_mixing_asset=asset(
                zd,
                "o2_line_mixing",
                "data/reference_data/cross_sections/o2a_lisa_rmf.dat",
                "lisa_rmf",
            ),
            strong_lines_asset=asset(
                zd,
                "o2_strong_lines",
                "data/reference_data/cross_sections/o2a_lisa_sdf.dat",
                "lisa_sdf",
            ),
            line_mixing_factor=1.0,
            isotopes_sim=[1, 2, 3],
            threshold_line_sim=3.0e-5,
            cutoff_sim_cm1=200.0,
        ),
        o2_o2_cia=zd.O2O2CIA(
            enabled=True,
            cia_asset=asset(
                zd,
                "o2o2_cia",
                "data/reference_data/cross_sections/o2o2_bira_o2a.dat",
                "bira_cia",
            ),
        ),
        radiative_transfer=zd.RadiativeTransferControls(
            scattering="multiple",
            n_streams=20,
            use_adding=False,
            num_orders_max=0,
            fourier_floor_scalar=2,
            threshold_conv_first=1.5e-7,
            threshold_conv_mult=1.5e-9,
            threshold_doubl=1.0e-6,
            threshold_mul=1.0e-8,
            use_spherical_correction=True,
            integrate_source_function=True,
            renorm_phase_function=True,
            phase_function_truncation_threshold=1.0e-6,
            stokes_dimension=1,
        ),
        outputs=[],
        validation={
            "strict_unknown_fields": True,
            "require_resolved_assets": True,
            "require_resolved_stage_references": True,
        },
    )


def stable_repo_path(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(REPO_ROOT.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def run_zdisamar_validation(case, library_path: Path) -> dict[str, np.ndarray]:
    zd = import_zdisamar()
    with zd.prepare(case, library_path=str(library_path)) as prepared:
        spectrum = prepared.forward_model(jacobian=True)
        wavelength_nm = spectrum.wavelength_nm.copy()
        reflectance = spectrum.reflectance.copy()
        irradiance = spectrum.irradiance.copy()
        radiance_jacobian = spectrum.radiance_jacobian.copy()
        state_names = spectrum.jacobian_state_names
        spectrum.close()

    if tuple(state_names) != STATE_NAMES:
        raise RuntimeError(f"unexpected Jacobian states: {state_names}")

    mu0 = math.cos(math.radians(case.geometry.solar_zenith_deg))
    reflectance_jacobian = radiance_jacobian / ((mu0 * irradiance / np.pi)[:, None])
    return {
        "wavelength_nm": wavelength_nm,
        "reflectance": reflectance,
        "reflectance_jacobian": reflectance_jacobian,
    }


def build_validation_rows(case, current: dict[str, np.ndarray]) -> tuple[pd.DataFrame, list[dict[str, float | str]]]:
    forward_reference = pd.read_csv(FORWARD_REFERENCE_PATH)
    jacobian_reference = pd.read_csv(REFLECTANCE_JACOBIAN_REFERENCE_PATH)
    wavelength_nm = current["wavelength_nm"]
    mu0 = math.cos(math.radians(case.geometry.solar_zenith_deg))

    rows = [
        {
            "series": "forward reflectance",
            "y_label": "Reflectance",
            "zdisamar": current["reflectance"],
            "reference": np.interp(
                wavelength_nm,
                forward_reference["wavelength_nm"],
                forward_reference["sun_normalized_radiance"],
            )
            * np.pi
            / mu0,
        },
    ]
    jacobian_labels = {
        "surface_albedo": ("dR/d surface albedo", "dR/d surface\nalbedo"),
        "aerosol_optical_depth": ("dR/d aerosol optical depth", "dR/d aerosol\noptical depth"),
        "aerosol_layer_mid_pressure_hpa": (
            "dR/d aerosol layer mid pressure",
            "dR/d aerosol layer\nmid pressure",
        ),
    }
    for state_index, state_name in enumerate(STATE_NAMES):
        series_label, y_label = jacobian_labels[state_name]
        rows.append(
            {
                "series": series_label,
                "y_label": y_label,
                "zdisamar": current["reflectance_jacobian"][:, state_index],
                "reference": np.interp(
                    wavelength_nm,
                    jacobian_reference["wavelength_nm"],
                    jacobian_reference[REFERENCE_COLUMNS[state_name]],
                ),
            }
        )

    records = []
    metrics = []
    for row in rows:
        residual = row["zdisamar"] - row["reference"]
        max_abs_index = int(np.argmax(np.abs(residual)))
        metrics.append(
            {
                "series": row["series"],
                "max_abs_residual": float(np.max(np.abs(residual))),
                "max_abs_wavelength_nm": float(wavelength_nm[max_abs_index]),
                "rmse": float(np.sqrt(np.mean(residual * residual))),
                "mean_signed": float(np.mean(residual)),
                "marked_residual_blowup_regions_nm": residual_blowup_regions(
                    wavelength_nm,
                    residual,
                    str(row["series"]),
                ),
            }
        )
        for wavelength, reference, zdisamar, value_residual in zip(
            wavelength_nm,
            row["reference"],
            row["zdisamar"],
            residual,
        ):
            records.append(
                {
                    "wavelength_nm": float(wavelength),
                    "series": row["series"],
                    "y_label": row["y_label"],
                    "kind": "reference",
                    "value": float(reference),
                    "residual": 0.0,
                }
            )
            records.append(
                {
                    "wavelength_nm": float(wavelength),
                    "series": row["series"],
                    "y_label": row["y_label"],
                    "kind": "zdisamar",
                    "value": float(zdisamar),
                    "residual": float(value_residual),
                }
            )

    return pd.DataFrame.from_records(records), metrics


def sci_formatter() -> ScalarFormatter:
    formatter = ScalarFormatter(useMathText=True)
    formatter.set_powerlimits((-2, 2))
    return formatter


def apply_axis_style(axis) -> None:
    axis.grid(True, color=MATPLOTLIB_GRID, linewidth=0.65, alpha=0.32)
    axis.ticklabel_format(axis="y", style="sci", scilimits=(-2, 2), useMathText=True)
    axis.yaxis.set_major_formatter(sci_formatter())
    axis.tick_params(axis="both", colors="black", direction="out", length=4.0, width=0.8)
    for spine in axis.spines.values():
        spine.set_visible(True)
        spine.set_color("black")
        spine.set_linewidth(0.8)


def residual_blowup_regions(
    wavelength_nm: np.ndarray,
    residual: np.ndarray,
    series: str,
) -> list[dict[str, float]]:
    magnitude = np.abs(residual)
    if magnitude.size == 0:
        return []

    threshold = BLOWUP_REGION_FRACTION * float(np.max(magnitude))
    mask = magnitude >= threshold
    regions: list[dict[str, float]] = []
    start_index: int | None = None
    for index, selected in enumerate(mask):
        if selected and start_index is None:
            start_index = index
        is_last = index == mask.size - 1
        if start_index is not None and (not selected or is_last):
            end_index = index if selected and is_last else index - 1
            region_magnitude = magnitude[start_index : end_index + 1]
            peak_offset = int(np.argmax(region_magnitude))
            peak_index = start_index + peak_offset
            regions.append(
                {
                    "start_nm": max(755.0, float(wavelength_nm[start_index]) - BLOWUP_REGION_PADDING_NM),
                    "end_nm": min(776.0, float(wavelength_nm[end_index]) + BLOWUP_REGION_PADDING_NM),
                    "peak_nm": float(wavelength_nm[peak_index]),
                    "peak_abs_residual": float(magnitude[peak_index]),
                }
            )
            start_index = None

    limit = BLOWUP_REGION_LIMITS[series]
    strongest = sorted(regions, key=lambda region: region["peak_abs_residual"], reverse=True)[:limit]
    return sorted(strongest, key=lambda region: region["start_nm"])


def mark_residual_blowup_regions(value_axis, residual_axis, regions: list[dict[str, float]]) -> None:
    for region in regions:
        for axis in (value_axis, residual_axis):
            axis.axvspan(
                region["start_nm"],
                region["end_nm"],
                color=MATPLOTLIB_RED,
                alpha=0.08,
                linewidth=0.0,
                zorder=0,
            )
            axis.axvline(
                region["peak_nm"],
                color=MATPLOTLIB_RED,
                linewidth=0.75,
                alpha=0.50,
                linestyle=":",
                zorder=1,
            )
        value_axis.plot(
            [region["peak_nm"]],
            [0.985],
            marker="v",
            markersize=4.0,
            color=MATPLOTLIB_RED,
            alpha=0.78,
            transform=value_axis.get_xaxis_transform(),
            clip_on=False,
            zorder=6,
        )


def create_validation_plot(data: pd.DataFrame, output_path: Path) -> None:
    series_order = list(dict.fromkeys(data["series"]))
    fig, axes = plt.subplots(
        len(series_order),
        2,
        figsize=(16.5, 13.0),
        sharex=True,
        constrained_layout=True,
        gridspec_kw={"width_ratios": [1.25, 1.0]},
    )
    fig.suptitle("O2A validation against DISAMAR reference", fontsize=16, fontweight="normal")

    for row_index, series in enumerate(series_order):
        row_data = data[data["series"] == series]
        reference = row_data[row_data["kind"] == "reference"]
        zdisamar = row_data[row_data["kind"] == "zdisamar"]
        y_label = str(zdisamar["y_label"].iloc[0])

        value_axis = axes[row_index, 0]
        residual_axis = axes[row_index, 1]
        value_axis.plot(
            reference["wavelength_nm"],
            reference["value"],
            label="reference",
            color=MATPLOTLIB_BLUE,
            linewidth=1.9,
            zorder=2,
        )
        value_axis.plot(
            zdisamar["wavelength_nm"],
            zdisamar["value"],
            label="zdisamar",
            color=MATPLOTLIB_ORANGE,
            linestyle="--",
            linewidth=1.35,
            zorder=4,
        )
        residual_axis.plot(
            zdisamar["wavelength_nm"],
            zdisamar["residual"],
            color="#111111",
            linewidth=1.15,
            zorder=3,
        )
        residual_axis.axhline(0.0, color="black", linewidth=0.75, linestyle="--", alpha=0.55, zorder=1)
        blowup_regions = residual_blowup_regions(
            zdisamar["wavelength_nm"].to_numpy(dtype=np.float64),
            zdisamar["residual"].to_numpy(dtype=np.float64),
            series,
        )
        mark_residual_blowup_regions(value_axis, residual_axis, blowup_regions)

        value_axis.set_ylabel(y_label, labelpad=12)
        residual_axis.set_ylabel("zdisamar - reference", labelpad=12)
        apply_axis_style(value_axis)
        apply_axis_style(residual_axis)
        value_axis.set_xlim(755.0, 776.0)
        residual_axis.set_xlim(755.0, 776.0)

    axes[-1, 0].set_xlabel("Wavelength (nm)")
    axes[-1, 1].set_xlabel("Wavelength (nm)")
    handles, labels = axes[0, 0].get_legend_handles_labels()
    legend = fig.legend(handles, labels, loc="upper right", bbox_to_anchor=(0.995, 0.995), frameon=True)
    legend.get_frame().set_facecolor("white")
    legend.get_frame().set_edgecolor("#cccccc")
    legend.get_frame().set_linewidth(0.8)
    fig.align_ylabels(axes[:, 0])
    fig.align_ylabels(axes[:, 1])
    fig.savefig(output_path, dpi=180)
    plt.close(fig)


def write_metrics(metrics: list[dict[str, float | str]], output_path: Path) -> None:
    payload = {
        "schema_version": 2,
        "sample_count": 701,
        "wavelength_min_nm": 755.0,
        "wavelength_max_nm": 776.0,
        "reflectance_threshold": REFLECTANCE_THRESHOLD,
        "passes_reflectance_threshold": all(
            float(metric["max_abs_residual"]) <= REFLECTANCE_THRESHOLD for metric in metrics
        ),
        "series": metrics,
        "reference_paths": {
            "forward": stable_repo_path(FORWARD_REFERENCE_PATH),
            "reflectance_jacobian": stable_repo_path(REFLECTANCE_JACOBIAN_REFERENCE_PATH),
        },
    }
    output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def write_manifest(output_path: Path) -> None:
    tracked_outputs = [
        PLOT_PATH,
        DATA_PATH,
        METRICS_PATH,
        MANIFEST_PATH,
    ]
    manifest = {
        "schema_version": 2,
        "canonical_command": CANONICAL_COMMAND,
        "tracked_output_dir": stable_repo_path(VALIDATION_DIR),
        "tracked_outputs": [stable_repo_path(path) for path in tracked_outputs],
        "reference_paths": [
            stable_repo_path(FORWARD_REFERENCE_PATH),
            stable_repo_path(REFLECTANCE_JACOBIAN_REFERENCE_PATH),
        ],
        "policy": {
            "validation_case": "hardcoded_o2a_jacobian_reference",
            "note": "The tracked O2 A validation plot is generated by the Python API and compares zdisamar reflectance plus reflectance Jacobians against committed DISAMAR reference derivatives.",
        },
    }
    output_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def build_bundle(
    output_dir: Path = VALIDATION_DIR,
    library_path: Path = LIBRARY_PATH,
) -> list[dict[str, float | str]]:
    if output_dir != VALIDATION_DIR:
        raise ValueError("plot_validation is intentionally hardwired to validation/")
    zd = import_zdisamar()
    case = build_validation_case(zd)
    current = run_zdisamar_validation(case, library_path)
    data, metrics = build_validation_rows(case, current)

    output_dir.mkdir(parents=True, exist_ok=True)
    VALIDATION_DATA_DIR.mkdir(parents=True, exist_ok=True)
    VALIDATION_PLOTS_DIR.mkdir(parents=True, exist_ok=True)
    data.to_csv(DATA_PATH, index=False)
    create_validation_plot(data, PLOT_PATH)
    write_metrics(metrics, METRICS_PATH)
    write_manifest(MANIFEST_PATH)
    return metrics


def main() -> None:
    metrics = build_bundle()
    worst = max(metrics, key=lambda row: float(row["max_abs_residual"]))
    print(
        "o2a_validation="
        f"{stable_repo_path(PLOT_PATH)} max_abs={float(worst['max_abs_residual']):.3e} "
        f"series={worst['series']}"
    )


if __name__ == "__main__":
    main()
