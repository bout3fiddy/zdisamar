#!/usr/bin/env -S uv run
# pyright: reportMissingTypeStubs=false, reportUnknownMemberType=false, reportAny=false

from __future__ import annotations

import json
import sys
import time
from pathlib import Path
from typing import TypedDict, cast

import altair as alt
import numpy as np
import numpy.typing as npt
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
import python.zdisamar as zd  # noqa: E402
import python.zdisamar.plot as zp  # noqa: E402

DEFAULT_OUTPUT_DIR = REPO_ROOT / "out" / "ci" / "o2a_validation_spectrum"
DEFAULT_REFERENCE = REPO_ROOT / "validation" / "data" / "o2a_with_cia_disamar_reference.csv"
LIBRARY_NAME = "libzdisamar_c.dylib" if sys.platform == "darwin" else "libzdisamar_c.so"
DEFAULT_LIBRARY = REPO_ROOT / "zig-out" / "lib" / LIBRARY_NAME
MARKERS_NM = (755.0, 760.76, 776.0)


class QuantityMetrics(TypedDict):
    mae: float
    rmse: float
    max_abs: float
    mean_signed: float


class ValidationMetrics(TypedDict):
    sample_count: int
    wavelength_min_nm: float
    wavelength_max_nm: float
    reflectance: QuantityMetrics
    radiance: QuantityMetrics
    irradiance: QuantityMetrics


class Timing(TypedDict):
    prepare_o2a_s: float
    forward_model_s: float


class Artifacts(TypedDict):
    generated_spectrum_csv: str
    reference_resampled_csv: str
    plot_png: str
    summary_json: str


class RunSummary(TypedDict):
    case_id: str
    timing: Timing
    metrics: ValidationMetrics
    artifacts: Artifacts


_theme_enabler = cast(object, alt.data_transformers.disable_max_rows())
zp.use_theme("validation")


def require_existing_file(path: Path, label: str) -> Path:
    if not path.exists():
        raise FileNotFoundError(f"{label} does not exist: {path}")
    return path


def asset(id: str, path: str, format: str) -> zd.ReferenceAsset:
    return zd.ReferenceAsset(id=id, path=path, format=format)


def build_o2a_validation_scene() -> zd.O2AInput:
    return zd.O2AInput(
        metadata={
            "id": "disamar_reference_o2a",
            "storage": "disamar-reference-o2a",
            "description": "DISAMAR O2 A reference case for Python and validation.",
        },
        plan={
            "model_family": "disamar_standard",
            "transport_solver": "dispatcher",
            "execution_solver_mode": "scalar",
            "execution_derivative_mode": "none",
        },
        reference_assets=zd.ReferenceAssets(
            atmosphere_profile=asset(
                "atmosphere_profile",
                "data/reference_data/climatologies/vendor_config_o2a_profile.csv",
                "profile_csv",
            ),
            vendor_reference_csv=asset(
                "vendor_reference_csv",
                "validation/spectra/data/o2a_with_cia_disamar_reference.csv",
                "disamar_o2a_reference_csv",
            ),
            raw_solar_reference=asset(
                "raw_solar_reference",
                "data/reference_data/solar/o2a_solar_reference_753_778.csv",
                "solar_reference_csv",
            ),
            airmass_factor_lut=asset(
                "airmass_factor_lut",
                "data/reference_data/luts/airmass_factor_nadir_demo.csv",
                "csv",
            ),
        ),
        scene_id="o2a_disamar_reference_python",
        spectral_grid=zd.SpectralGrid(start_nm=755.0, end_nm=776.0, sample_count=701),
        atmosphere=zd.Atmosphere(
            layer_count=3,
            sublayer_divisions=4,
            fit_interval_index_1based=2,
            intervals=[
                zd.VerticalInterval(
                    index_1based=1,
                    top_pressure_hpa=0.3,
                    bottom_pressure_hpa=500.0,
                    altitude_divisions=28,
                ),
                zd.VerticalInterval(
                    index_1based=2,
                    top_pressure_hpa=500.0,
                    bottom_pressure_hpa=520.0,
                    altitude_divisions=6,
                ),
                zd.VerticalInterval(
                    index_1based=3,
                    top_pressure_hpa=520.0,
                    bottom_pressure_hpa=1013.25,
                    altitude_divisions=8,
                ),
            ],
        ),
        surface=zd.Surface(albedo=0.2, pressure_hpa=1013.25),
        geometry=zd.Geometry(
            model="pseudo_spherical",
            solar_zenith_deg=60.0,
            viewing_zenith_deg=30.0,
            relative_azimuth_deg=120.0,
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
                top_pressure_hpa=500.0,
                bottom_pressure_hpa=520.0,
            ),
        ),
        instrument_response=zd.InstrumentResponse(
            instrument_name="disamar-o2a-compare",
            regime="nadir",
            sampling="native",
            noise_model="none",
            instrument_line_fwhm_nm=0.38,
            builtin_line_shape="flat_top_n4",
            high_resolution_step_nm=0.01,
            high_resolution_half_span_nm=1.14,
            adaptive_reference_grid={
                "points_per_fwhm": 20,
                "strong_line_min_divisions": 8,
                "strong_line_max_divisions": 40,
            },
            solar_reference_asset_id="raw_solar_reference",
        ),
        o2_lines=zd.O2LineByLine(
            line_list_asset=asset(
                "o2_hitran",
                "vendor/disamar-fortran/RefSpec/07_HIT08_TROPOMI.par",
                "hitran_par_o2a",
            ),
            line_mixing_asset=asset(
                "o2_line_mixing",
                "data/reference_data/cross_sections/o2a_lisa_rmf.dat",
                "lisa_rmf",
            ),
            strong_lines_asset=asset(
                "o2_strong_lines",
                "data/reference_data/cross_sections/o2a_lisa_sdf.dat",
                "lisa_sdf",
            ),
            line_mixing_factor=1.0,
            isotopes_sim=[1, 2, 3],
            threshold_line_sim=3.0e-5,
            cutoff_sim_cm1=200.0,
        ),
        collision_induced_absorption=zd.OxygenCollisionInducedAbsorption(
            enabled=True,
            cross_section_asset=asset(
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
            stokes_dimension=1,
        ),
        outputs=[],
        validation={
            "strict_unknown_fields": True,
            "require_resolved_assets": True,
            "require_resolved_stage_references": True,
        },
    )


def resample_reference(reference: pd.DataFrame, spectrum: pd.DataFrame) -> pd.DataFrame:
    wavelength_nm = column_array(spectrum, "wavelength_nm")
    reference_wavelength_nm = column_array(reference, "wavelength_nm")
    if (
        wavelength_nm[0] < reference_wavelength_nm[0]
        or wavelength_nm[-1] > reference_wavelength_nm[-1]
    ):
        raise ValueError("Generated spectrum grid extends outside the reference spectrum grid")

    return pd.DataFrame(
        {
            "wavelength_nm": wavelength_nm,
            "reflectance": np.interp(
                wavelength_nm,
                reference_wavelength_nm,
                column_array(reference, "reflectance"),
            ),
            "radiance": np.interp(
                wavelength_nm,
                reference_wavelength_nm,
                column_array(reference, "radiance"),
            ),
            "irradiance": np.interp(
                wavelength_nm,
                reference_wavelength_nm,
                column_array(reference, "irradiance"),
            ),
        }
    )


def column_array(frame: pd.DataFrame, column: str) -> npt.NDArray[np.float64]:
    return np.asarray(frame.loc[:, column], dtype=np.float64)


def quantity_metrics(
    current: npt.NDArray[np.float64], expected: npt.NDArray[np.float64]
) -> QuantityMetrics:
    residual = current - expected
    return {
        "mae": float(np.mean(np.abs(residual))),
        "rmse": float(np.sqrt(np.mean(np.square(residual)))),
        "max_abs": float(np.max(np.abs(residual))),
        "mean_signed": float(np.mean(residual)),
    }


def validation_metrics(spectrum: pd.DataFrame, reference: pd.DataFrame) -> ValidationMetrics:
    wavelength_nm = column_array(spectrum, "wavelength_nm")
    return {
        "sample_count": int(len(spectrum)),
        "wavelength_min_nm": float(np.min(wavelength_nm)),
        "wavelength_max_nm": float(np.max(wavelength_nm)),
        "reflectance": quantity_metrics(
            column_array(spectrum, "reflectance"),
            column_array(reference, "reflectance"),
        ),
        "radiance": quantity_metrics(
            column_array(spectrum, "radiance"), column_array(reference, "radiance")
        ),
        "irradiance": quantity_metrics(
            column_array(spectrum, "irradiance"), column_array(reference, "irradiance")
        ),
    }


def build_validation_plot(spectrum: pd.DataFrame, reference: pd.DataFrame) -> alt.TopLevelMixin:
    return zp.spectrum.with_full_sample_spectrum(
        zp.validation.overlay(
            spectrum,
            reference,
            quantity=zp.fields.REFLECTANCE,
            reference_label="Vendored DISAMAR reference",
            current_label="Current zdisamar",
        )
        & zp.validation.residual(
            spectrum,
            reference,
            quantity=zp.fields.REFLECTANCE,
        ),
        spectrum,
        quantity=zp.fields.REFLECTANCE,
        markers_nm=MARKERS_NM,
    )


def run_once(library_path: Path, reference_path: Path, output_dir: Path) -> RunSummary:
    case = build_o2a_validation_scene()

    prepare_start = time.perf_counter()
    with zd.prepare(case, library_path=library_path) as prepared:
        prepare_s = time.perf_counter() - prepare_start
        forward_start = time.perf_counter()
        with prepared.forward_model() as spectrum:
            forward_s = time.perf_counter() - forward_start
            spectrum_frame = cast(pd.DataFrame, zp.to_dataframe(spectrum))

    reference_frame = resample_reference(pd.read_csv(reference_path), spectrum_frame)
    metrics = validation_metrics(spectrum_frame, reference_frame)

    output_dir.mkdir(parents=True, exist_ok=True)
    spectrum_path = output_dir / "generated_spectrum.csv"
    reference_resampled_path = output_dir / "reference_resampled.csv"
    plot_path = output_dir / "reflectance_against_reference.png"
    summary_path = output_dir / "summary.json"

    spectrum_frame.to_csv(spectrum_path, index=False)
    reference_frame.to_csv(reference_resampled_path, index=False)
    chart = build_validation_plot(spectrum_frame, reference_frame)
    zp.save(chart, plot_path, scale=1.35)

    summary: RunSummary = {
        "case_id": str(case.metadata["id"]),
        "timing": {
            "prepare_o2a_s": prepare_s,
            "forward_model_s": forward_s,
        },
        "metrics": metrics,
        "artifacts": {
            "generated_spectrum_csv": str(spectrum_path),
            "reference_resampled_csv": str(reference_resampled_path),
            "plot_png": str(plot_path),
            "summary_json": str(summary_path),
        },
    }
    _ = summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return summary


def main() -> int:
    summary = run_once(
        require_existing_file(DEFAULT_LIBRARY, "Native zdisamar library"),
        require_existing_file(DEFAULT_REFERENCE, "Reference spectrum"),
        DEFAULT_OUTPUT_DIR,
    )
    print(
        (
            "forward_model_s={forward:.6f} prepare_o2a_s={prepare:.6f} "
            "samples={samples} plot={plot}"
        ).format(
            forward=summary["timing"]["forward_model_s"],
            prepare=summary["timing"]["prepare_o2a_s"],
            samples=summary["metrics"]["sample_count"],
            plot=summary["artifacts"]["plot_png"],
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
