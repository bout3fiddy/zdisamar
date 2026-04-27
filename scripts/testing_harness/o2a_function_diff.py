#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "matplotlib>=3.10",
#   "numpy>=2.2",
# ]
# ///

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
from dataclasses import dataclass
from typing import Iterable

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "validation"))

from o2a_plot_bundle import create_plots, stable_repo_path

DEFAULT_WAVELENGTHS_NM = (761.75,)
DEFAULT_TRACE_ROOT = REPO_ROOT / "out" / "analysis" / "o2a" / "function_diff"
PARITY_CASE_YAML = REPO_ROOT / "data" / "examples" / "vendor_o2a_parity.yaml"
VENDOR_SOURCE_ROOT = REPO_ROOT / "vendor" / "disamar-fortran"
VENDOR_CONFIG_SOURCE = VENDOR_SOURCE_ROOT / "InputFiles" / "Config_O2_with_CIA.in"
FORTRAN_TRACE_ASSET_DIR = REPO_ROOT / "scripts" / "testing_harness" / "vendor_o2a_function_trace"
FORTRAN_TRACE_MODULE = FORTRAN_TRACE_ASSET_DIR / "o2aFunctionTraceModule.f90"
ZIG_TRACE_CLI = REPO_ROOT / "scripts" / "testing_harness" / "o2a_function_trace.zig"
ZIG_BUILD_OPTIONS = REPO_ROOT / "scripts" / "testing_harness" / "build_options_test_support.zig"
EXPECTED_CSVS = (
    "line_catalog.csv",
    "strong_state.csv",
    "spectroscopy_summary.csv",
    "dense_profile.csv",
    "hydrostatic_terms.csv",
    "sublayer_optics.csv",
    "interval_bounds.csv",
    "adaptive_grid.csv",
    "kernel_samples.csv",
    "transport_samples.csv",
    "transport_summary.csv",
    "irradiance_contributions.csv",
    "fourier_terms.csv",
    "transport_layers.csv",
    "transport_layer_accumulation.csv",
    "transport_source_terms.csv",
    "transport_attenuation_terms.csv",
    "transport_pseudo_spherical_samples.csv",
    "transport_radiance_contributions.csv",
    "transport_order_surface.csv",
    "transport_rt_probe.csv",
    "transport_rt_build_probe.csv",
    "transport_rt_double_probe.csv",
    "transport_zplus_terms.csv",
    "transport_source_components.csv",
    "transport_source_angle_components.csv",
    "transport_pseudo_spherical_terms.csv",
    "transport_optical_depth_components.csv",
)
STAGE_ORDER = EXPECTED_CSVS
PAIRWISE_DIFFS = (("vendor", "yaml"),)
WEAK_LINE_CONTRIBUTOR_FILE = "weak_line_contributors.csv"


@dataclass(frozen=True)
class CsvSpec:
    key_columns: tuple[str, ...]
    numeric_columns: tuple[str, ...]


@dataclass(frozen=True)
class NumericMismatch:
    file_name: str
    row_index_1based: int
    row_key: tuple[object, ...]
    column: str
    left_value: float
    right_value: float
    absolute_delta: float


@dataclass(frozen=True)
class FileComparison:
    lines: list[str]
    first_numeric_mismatch: NumericMismatch | None
    aligned_numeric_mismatch: NumericMismatch | None
    keys_aligned: bool


CSV_SPECS: dict[str, CsvSpec] = {
    "line_catalog.csv": CsvSpec(
        key_columns=(
            "gas_index",
            "isotope_number",
            "center_wavelength_nm",
            "lower_state_energy_cm1",
            "branch_ic1",
            "branch_ic2",
            "rotational_nf",
        ),
        numeric_columns=(
            "gas_index",
            "isotope_number",
            "center_wavelength_nm",
            "center_wavenumber_cm1",
            "line_strength_cm2_per_molecule",
            "air_half_width_nm",
            "temperature_exponent",
            "lower_state_energy_cm1",
            "pressure_shift_nm",
            "line_mixing_coefficient",
            "branch_ic1",
            "branch_ic2",
            "rotational_nf",
        ),
    ),
    "strong_state.csv": CsvSpec(
        key_columns=("pressure_hpa", "temperature_k", "center_wavelength_nm", "strong_index"),
        numeric_columns=(
            "pressure_hpa",
            "temperature_k",
            "strong_index",
            "center_wavelength_nm",
            "center_wavenumber_cm1",
            "sig_moy_cm1",
            "population_t",
            "dipole_t",
            "mod_sig_cm1",
            "half_width_cm1_at_t",
            "line_mixing_coefficient",
        ),
    ),
    "spectroscopy_summary.csv": CsvSpec(
        key_columns=("pressure_hpa", "temperature_k", "wavelength_nm"),
        numeric_columns=(
            "pressure_hpa",
            "temperature_k",
            "wavelength_nm",
            "weak_sigma_cm2_per_molecule",
            "strong_sigma_cm2_per_molecule",
            "line_mixing_sigma_cm2_per_molecule",
            "total_sigma_cm2_per_molecule",
        ),
    ),
    "dense_profile.csv": CsvSpec(
        key_columns=("row_index",),
        numeric_columns=(
            "row_index",
            "pressure_hpa",
            "lnpressure",
            "altitude_km",
            "temperature_k",
            "number_density_cm3",
            "scale_height_km",
        ),
    ),
    "hydrostatic_terms.csv": CsvSpec(
        key_columns=("iteration", "pressure_index", "gauss_index"),
        numeric_columns=(
            "iteration",
            "pressure_index",
            "gauss_index",
            "lnpressure_gp",
            "weight_gp",
            "altitude_gp_km",
            "temperature_gp_k",
            "gravity_mps2",
            "scale_height_gp_km",
            "increment_km",
            "cumulative_altitude_km",
        ),
    ),
    "sublayer_optics.csv": CsvSpec(
        key_columns=("wavelength_nm", "global_sublayer_index"),
        numeric_columns=(
            "wavelength_nm",
            "global_sublayer_index",
            "interval_index_1based",
            "altitude_km",
            "support_weight_km",
            "pressure_hpa",
            "temperature_k",
            "number_density_cm3",
            "oxygen_number_density_cm3",
            "line_cross_section_cm2_per_molecule",
            "line_mixing_cross_section_cm2_per_molecule",
            "cia_sigma_cm5_per_molecule2",
            "gas_absorption_optical_depth",
            "gas_scattering_optical_depth",
            "cia_optical_depth",
            "path_length_cm",
            "aerosol_optical_depth",
            "aerosol_scattering_optical_depth",
            "cloud_optical_depth",
            "cloud_scattering_optical_depth",
            "total_scattering_optical_depth",
            "total_optical_depth",
            "combined_phase_coef_0",
            "combined_phase_coef_1",
            "combined_phase_coef_2",
            "combined_phase_coef_3",
            "combined_phase_coef_10",
            "combined_phase_coef_20",
            "combined_phase_coef_39",
        ),
    ),
    "interval_bounds.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "boundary_index_0based"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "boundary_index_0based",
            "interval_index_1based",
            "pressure_hpa",
            "altitude_km",
        ),
    ),
    "adaptive_grid.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "interval_kind", "interval_start_nm", "interval_end_nm", "division_count"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "source_center_wavelength_nm",
            "interval_start_nm",
            "interval_end_nm",
            "division_count",
        ),
    ),
    "kernel_samples.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm"),
        numeric_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm", "weight"),
    ),
    "transport_samples.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "radiance",
            "irradiance",
            "weight",
        ),
    ),
    "transport_summary.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm",),
        numeric_columns=("nominal_wavelength_nm", "final_radiance", "final_irradiance", "final_reflectance"),
    ),
    "fourier_terms.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm", "fourier_index"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "fourier_index",
            "refl_fc",
            "source_refl_fc",
            "surface_refl_fc",
            "surface_e_view",
            "surface_u_view_solar",
            "fourier_weight",
            "weighted_refl",
        ),
    ),
    "transport_layers.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm", "layer_index"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "layer_index",
            "optical_depth",
            "scattering_optical_depth",
            "single_scatter_albedo",
            "phase_coef_0",
            "phase_coef_1",
            "phase_coef_2",
            "phase_coef_3",
            "phase_coef_10",
            "phase_coef_20",
            "phase_coef_39",
        ),
    ),
    "transport_layer_accumulation.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm", "layer_index"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "layer_index",
            "babs",
            "bsca",
            "babs_gas",
            "bsca_gas",
            "babs_particles",
            "bsca_particles",
            "optical_depth",
            "scattering_optical_depth",
            "single_scatter_albedo",
        ),
    ),
    "transport_source_terms.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm", "fourier_index", "level_index"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "fourier_index",
            "level_index",
            "rtm_weight",
            "ksca",
            "source_contribution",
            "weighted_source_contribution",
        ),
    ),
    "transport_attenuation_terms.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm", "direction_kind", "level_index"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "direction_index",
            "level_index",
            "sumkext",
            "attenuation_top_to_level",
            "grid_valid",
        ),
    ),
    "transport_pseudo_spherical_samples.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm", "global_sample_index"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "global_sample_index",
            "altitude_km",
            "support_weight_km",
            "optical_depth",
            "radius_weighted_optical_depth",
            "grid_valid",
        ),
    ),
    "transport_radiance_contributions.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "reflectance",
            "irradiance",
            "radiance",
            "weighted_radiance_contribution",
        ),
    ),
    "irradiance_contributions.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "irradiance",
            "weighted_irradiance_contribution",
            "cumulative_irradiance",
        ),
    ),
    "transport_order_surface.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm", "fourier_index", "order_index"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "fourier_index",
            "order_index",
            "max_value",
            "surface_u_order",
            "surface_u_accumulated",
            "surface_d_order",
            "surface_e_view",
            "probe_level",
            "probe_angle_index",
            "probe_d_order",
            "probe_d_accumulated",
            "probe_u_order",
            "probe_u_accumulated",
        ),
    ),
    "transport_rt_probe.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm", "fourier_index", "layer_index"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "fourier_index",
            "layer_index",
            "row_angle_index",
            "solar_column_index",
            "optical_depth",
            "scattering_optical_depth",
            "single_scatter_albedo",
            "rt_t_value",
            "attenuation_top_to_layer",
            "first_order_d_local",
        ),
    ),
    "transport_rt_build_probe.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm", "fourier_index", "layer_index"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "fourier_index",
            "layer_index",
            "row_angle_index",
            "solar_column_index",
            "max_phase_index",
            "max_beta_eff",
            "a_eff",
            "use_doubling",
            "b_start",
            "ndouble",
            "zplus_value",
            "e_row",
            "e_col",
            "eet",
            "dmu_min",
            "single_t_value",
            "final_t_value",
        ),
    ),
    "transport_rt_double_probe.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm", "fourier_index", "layer_index", "iteration"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "fourier_index",
            "layer_index",
            "iteration",
            "b_before",
            "q_value",
            "d_value",
            "u_value",
            "t_before",
            "t_after",
        ),
    ),
    "transport_zplus_terms.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm", "fourier_index", "layer_index", "coefficient_index"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "fourier_index",
            "layer_index",
            "row_angle_index",
            "solar_column_index",
            "coefficient_index",
            "phase_coefficient",
            "plm_row",
            "plm_col",
            "contribution",
            "cumulative_zplus",
        ),
    ),
    "transport_source_components.csv": CsvSpec(
        key_columns=("nominal_wavelength_nm", "sample_index", "sample_wavelength_nm", "fourier_index", "level_index"),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "fourier_index",
            "level_index",
            "e_view",
            "pmin_ed",
            "pplusst_u",
            "source_over_ksca",
            "source_contribution",
            "weighted_source_contribution",
        ),
    ),
    "transport_source_angle_components.csv": CsvSpec(
        key_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "fourier_index",
            "level_index",
            "component_kind",
            "angle_index",
        ),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "fourier_index",
            "level_index",
            "angle_index",
            "phase_value",
            "field_value",
            "angle_contribution",
            "weighted_angle_contribution",
        ),
    ),
    "transport_pseudo_spherical_terms.csv": CsvSpec(
        key_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "direction_kind",
            "level_index",
            "global_sample_index",
        ),
        numeric_columns=(
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "direction_index",
            "level_index",
            "global_sample_index",
            "level_altitude_km",
            "level_radius_km",
            "sample_altitude_km",
            "sample_radius_km",
            "numerator",
            "denominator",
            "contribution",
            "cumulative_sumkext",
            "grid_valid",
        ),
    ),
    "transport_optical_depth_components.csv": CsvSpec(
        key_columns=("wavelength_nm", "global_sublayer_index"),
        numeric_columns=(
            "wavelength_nm",
            "global_sublayer_index",
            "interval_index_1based",
            "line_absorption_optical_depth",
            "cia_optical_depth",
            "gas_scattering_optical_depth",
            "aerosol_optical_depth",
            "cloud_optical_depth",
            "total_absorption_optical_depth",
            "total_scattering_optical_depth",
            "total_optical_depth",
        ),
    ),
}

WEAK_LINE_CONTRIBUTOR_SPEC = CsvSpec(
    key_columns=(
        "pressure_hpa",
        "temperature_k",
        "wavelength_nm",
        "center_wavenumber_cm1",
        "line_strength_cm2_per_molecule",
        "lower_state_energy_cm1",
        "air_half_width_nm",
        "temperature_exponent",
        "pressure_shift_nm",
        "isotope_number",
        "gas_index",
    ),
    numeric_columns=(
        "pressure_hpa",
        "temperature_k",
        "wavelength_nm",
        "sample_wavelength_nm",
        "source_row_index",
        "gas_index",
        "isotope_number",
        "center_wavelength_nm",
        "center_wavenumber_cm1",
        "shifted_center_wavenumber_cm1",
        "line_strength_cm2_per_molecule",
        "air_half_width_nm",
        "temperature_exponent",
        "lower_state_energy_cm1",
        "pressure_shift_nm",
        "line_mixing_coefficient",
        "branch_ic1",
        "branch_ic2",
        "rotational_nf",
        "matched_strong_index",
        "weak_line_sigma_cm2_per_molecule",
    ),
)


def main() -> int:
    args = parse_args()
    wavelengths_nm = parse_wavelengths(args.wavelengths)
    trace_root = resolve_trace_root(args.trace_root)
    vendor_workspace = trace_root / "vendor_workspace"
    vendor_root = trace_root / "vendor"
    yaml_root = trace_root / "yaml"
    diff_root = trace_root / "diff"

    if trace_root.exists():
        shutil.rmtree(trace_root)
    for path in (trace_root, vendor_root, yaml_root, diff_root):
        path.mkdir(parents=True, exist_ok=True)

    copy_vendor_workspace(vendor_workspace)
    try:
        prepare_vendor_workspace(vendor_workspace)
        build_vendor_workspace(vendor_workspace)
        run_vendor_trace(vendor_workspace, vendor_root, wavelengths_nm)
        merge_fortran_spectroscopy_summary(vendor_root)
        merge_fortran_sublayer_optics(vendor_root)
        run_zig_trace(trace_root, wavelengths_nm, args.zig_optimize)
        annotate_transport_support_rows(vendor_root, expand_overlapping_supports=True)
        annotate_transport_support_rows(yaml_root)
        derive_granular_transport_traces(vendor_root)
        derive_granular_transport_traces(yaml_root)
        canonicalize_side(vendor_root)
        verify_expected_csvs(vendor_root, "vendor")
        canonicalize_side(yaml_root)
        verify_expected_csvs(yaml_root, "yaml")
        canonicalize_optional_csv(vendor_root, WEAK_LINE_CONTRIBUTOR_FILE, WEAK_LINE_CONTRIBUTOR_SPEC)
        canonicalize_optional_csv(yaml_root, WEAK_LINE_CONTRIBUTOR_FILE, WEAK_LINE_CONTRIBUTOR_SPEC)
        align_sublayer_optics_to_yaml(vendor_root, yaml_root)
        derive_optical_depth_components(vendor_root)
        derive_optical_depth_components(yaml_root)
        canonicalize_optional_csv(
            vendor_root,
            "transport_optical_depth_components.csv",
            CSV_SPECS["transport_optical_depth_components.csv"],
        )
        canonicalize_optional_csv(
            yaml_root,
            "transport_optical_depth_components.csv",
            CSV_SPECS["transport_optical_depth_components.csv"],
        )
        write_diff_summaries(trace_root, diff_root, wavelengths_nm)
        write_weak_line_contributor_summary(trace_root, diff_root, wavelengths_nm)
        write_granular_contributor_summaries(trace_root, diff_root, wavelengths_nm)
        write_function_diff_plot_bundle(trace_root, diff_root, wavelengths_nm)
        write_irradiance_support_diagnostic(diff_root, wavelengths_nm)
        update_latest_trace_root(trace_root)
    finally:
        if not args.keep_vendor_workspace and vendor_workspace.exists():
            shutil.rmtree(vendor_workspace)

    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare minimal O2A function outputs between vendored DISAMAR and zdisamar.")
    parser.add_argument("--wavelengths", default=",".join(str(value) for value in DEFAULT_WAVELENGTHS_NM))
    parser.add_argument("--trace-root", default=None)
    parser.add_argument(
        "--zig-optimize",
        choices=("Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall"),
        default="ReleaseFast",
        help="Optimization mode for the Zig trace CLI. Use ReleaseFast for a practical full transport trace run.",
    )
    parser.add_argument("--keep-vendor-workspace", action="store_true")
    return parser.parse_args()


def parse_wavelengths(raw: str) -> list[float]:
    values: list[float] = []
    for part in raw.split(","):
        text = part.strip()
        if not text:
            continue
        values.append(float(text))
    return values or list(DEFAULT_WAVELENGTHS_NM)


def resolve_trace_root(raw: str | None) -> Path:
    if raw:
        return Path(raw).expanduser().resolve()
    run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return DEFAULT_TRACE_ROOT / run_id


def load_parity_irradiance_support() -> tuple[Path, float]:
    raw_solar_path: Path | None = None
    half_span_nm: float | None = None
    in_raw_solar_block = False
    for raw_line in PARITY_CASE_YAML.read_text(encoding="utf-8").splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped == "raw_solar_reference:":
            in_raw_solar_block = True
            continue
        if in_raw_solar_block and stripped.startswith("path:"):
            raw_solar_path = (REPO_ROOT / stripped.split(":", 1)[1].strip()).resolve()
            in_raw_solar_block = False
            continue
        if stripped.endswith(":") and not stripped.startswith("path:"):
            in_raw_solar_block = False
        if stripped.startswith("high_resolution_half_span_nm:"):
            half_span_nm = float(stripped.split(":", 1)[1].strip())
    if raw_solar_path is None or half_span_nm is None:
        raise RuntimeError("Failed to resolve parity solar support configuration")
    return raw_solar_path, half_span_nm


def write_irradiance_support_diagnostic(diff_root: Path, wavelengths_nm: list[float]) -> None:
    solar_path, half_span_nm = load_parity_irradiance_support()
    rows = read_csv_rows(solar_path)
    if not rows:
        raise RuntimeError(f"Missing solar support rows in {solar_path}")
    solar_start_nm = parse_float(rows[0]["wavelength_nm"])
    solar_end_nm = parse_float(rows[-1]["wavelength_nm"])

    per_wavelength: list[dict[str, object]] = []
    lines = [
        "irradiance_hr_support",
        f"solar_path={solar_path}",
        f"solar_range_nm={solar_start_nm:.12f}..{solar_end_nm:.12f}",
        f"half_span_nm={half_span_nm:.12f}",
    ]
    for wavelength_nm in wavelengths_nm:
        support_start_nm = wavelength_nm - half_span_nm
        support_end_nm = wavelength_nm + half_span_nm
        covered = support_start_nm >= solar_start_nm and support_end_nm <= solar_end_nm
        per_wavelength.append(
            {
                "wavelength_nm": wavelength_nm,
                "support_start_nm": support_start_nm,
                "support_end_nm": support_end_nm,
                "covered": covered,
            }
        )
        lines.append(
            "wavelength_nm="
            f"{wavelength_nm:.12f} support_nm={support_start_nm:.12f}..{support_end_nm:.12f} covered={'yes' if covered else 'no'}"
        )

    summary = {
        "solar_path": str(solar_path),
        "solar_start_nm": solar_start_nm,
        "solar_end_nm": solar_end_nm,
        "half_span_nm": half_span_nm,
        "per_wavelength": per_wavelength,
    }
    (diff_root / "irradiance_support_summary.txt").write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    (diff_root / "irradiance_support_summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def copy_vendor_workspace(destination: Path) -> None:
    if not VENDOR_SOURCE_ROOT.exists():
        raise RuntimeError(f"Missing vendored DISAMAR source tree at {VENDOR_SOURCE_ROOT}")
    shutil.copytree(VENDOR_SOURCE_ROOT, destination)


def prepare_vendor_workspace(vendor_workspace: Path) -> None:
    shutil.copy2(FORTRAN_TRACE_MODULE, vendor_workspace / "src" / FORTRAN_TRACE_MODULE.name)
    patch_makefile(vendor_workspace / "src" / "makefile")
    patch_hitran_module(vendor_workspace / "src" / "HITRANModule.f90")
    patch_disamar_module(vendor_workspace / "src" / "DISAMARModule.f90")
    patch_labos_module(vendor_workspace / "src" / "LabosModule.f90")
    patch_radiance_module(vendor_workspace / "src" / "radianceIrradianceModule.f90")
    patch_prop_atmosphere_module(vendor_workspace / "src" / "propAtmosphere.f90")
    shutil.copy2(VENDOR_CONFIG_SOURCE, vendor_workspace / "Config.in")


def build_vendor_workspace(vendor_workspace: Path) -> None:
    run_command(["make", "install"], cwd=vendor_workspace / "src")


def run_vendor_trace(vendor_workspace: Path, fortran_root: Path, wavelengths_nm: list[float]) -> None:
    env = os.environ.copy()
    env["ZDISAMAR_O2A_TRACE_ROOT"] = str(fortran_root)
    env["ZDISAMAR_O2A_TRACE_WAVELENGTHS_NM"] = ",".join(format_wavelength(value) for value in wavelengths_nm)
    run_command([str(vendor_workspace / "Disamar.exe")], cwd=vendor_workspace, env=env)


def run_zig_trace(trace_root: Path, wavelengths_nm: list[float], zig_optimize: str) -> None:
    command = [
        "zig",
        "run",
        "-O",
        zig_optimize,
        "--dep",
        "zdisamar",
        "--dep",
        "zdisamar_internal",
        f"-Mroot={ZIG_TRACE_CLI}",
        "--dep",
        "zdisamar",
        "--dep",
        "zdisamar_internal",
        "--dep",
        "build_options",
        f"-Mzdisamar={REPO_ROOT / 'src' / 'root.zig'}",
        f"-Mbuild_options={ZIG_BUILD_OPTIONS}",
        "--dep",
        "zdisamar",
        f"-Mzdisamar_internal={REPO_ROOT / 'src' / 'internal.zig'}",
        "--",
        "--trace-root",
        str(trace_root),
        "--wavelengths",
        ",".join(format_wavelength(value) for value in wavelengths_nm),
    ]
    run_command(command, cwd=REPO_ROOT)


def merge_fortran_spectroscopy_summary(fortran_root: Path) -> None:
    weak_path = fortran_root / "spectroscopy_weak_raw.csv"
    strong_path = fortran_root / "spectroscopy_strong_raw.csv"
    output_path = fortran_root / "spectroscopy_summary.csv"
    if not weak_path.exists() or not strong_path.exists():
        raise RuntimeError("Missing raw Fortran spectroscopy trace files")

    merged: dict[tuple[str, str, str], dict[str, str]] = {}
    for row in read_csv_rows(weak_path):
        key = (row["pressure_hpa"], row["temperature_k"], row["wavelength_nm"])
        merged[key] = {
            "pressure_hpa": row["pressure_hpa"],
            "temperature_k": row["temperature_k"],
            "wavelength_nm": row["wavelength_nm"],
            "weak_sigma_cm2_per_molecule": row["weak_sigma_cm2_per_molecule"],
            "strong_sigma_cm2_per_molecule": "0.0",
            "line_mixing_sigma_cm2_per_molecule": "0.0",
            "total_sigma_cm2_per_molecule": row["weak_sigma_cm2_per_molecule"],
        }

    for row in read_csv_rows(strong_path):
        key = (row["pressure_hpa"], row["temperature_k"], row["wavelength_nm"])
        record = merged.setdefault(
            key,
            {
                "pressure_hpa": row["pressure_hpa"],
                "temperature_k": row["temperature_k"],
                "wavelength_nm": row["wavelength_nm"],
                "weak_sigma_cm2_per_molecule": "0.0",
                "strong_sigma_cm2_per_molecule": "0.0",
                "line_mixing_sigma_cm2_per_molecule": "0.0",
                "total_sigma_cm2_per_molecule": "0.0",
            },
        )
        record["strong_sigma_cm2_per_molecule"] = row["strong_sigma_cm2_per_molecule"]
        record["line_mixing_sigma_cm2_per_molecule"] = row["line_mixing_sigma_cm2_per_molecule"]
        total = parse_float(record["weak_sigma_cm2_per_molecule"]) + parse_float(row["strong_sigma_cm2_per_molecule"]) + parse_float(row["line_mixing_sigma_cm2_per_molecule"])
        record["total_sigma_cm2_per_molecule"] = repr(total)

    fieldnames = list(CSV_SPECS["spectroscopy_summary.csv"].numeric_columns)
    rows = list(merged.values())
    sort_rows(rows, CSV_SPECS["spectroscopy_summary.csv"])
    write_csv_rows(output_path, fieldnames, rows)
    weak_path.unlink()
    strong_path.unlink()


def merge_fortran_sublayer_optics(fortran_root: Path) -> None:
    raw_optics_path = fortran_root / "sublayer_optics_raw.csv"
    optics_path = fortran_root / "sublayer_optics.csv"
    if not raw_optics_path.exists():
        raise RuntimeError("Missing raw Fortran sublayer optics trace file")

    spectroscopy_rows = read_csv_rows(fortran_root / "spectroscopy_summary.csv")

    canonical_rows: dict[tuple[str, str, str], dict[str, str]] = {}
    for row in read_csv_rows(raw_optics_path):
        key = (row["wavelength_nm"], row["global_sublayer_index"], row["interval_index_1based"])
        current_best = canonical_rows.get(key)
        if current_best is None:
            canonical_rows[key] = row
            continue
        current_delta = abs(parse_float(current_best["actual_wavelength_nm"]) - parse_float(current_best["wavelength_nm"]))
        candidate_delta = abs(parse_float(row["actual_wavelength_nm"]) - parse_float(row["wavelength_nm"]))
        if candidate_delta < current_delta:
            canonical_rows[key] = row

    fieldnames = list(dict.fromkeys((*CSV_SPECS["sublayer_optics.csv"].key_columns, *CSV_SPECS["sublayer_optics.csv"].numeric_columns)))
    optics_rows = list(canonical_rows.values())
    for row in optics_rows:
        row.pop("actual_wavelength_nm", None)
        spectroscopy_row = nearest_spectroscopy_row(spectroscopy_rows, row)
        if spectroscopy_row is None:
            row["line_cross_section_cm2_per_molecule"] = "nan"
            row["line_mixing_cross_section_cm2_per_molecule"] = "nan"
            continue
        weak_sigma = parse_float(spectroscopy_row["weak_sigma_cm2_per_molecule"])
        strong_sigma = parse_float(spectroscopy_row["strong_sigma_cm2_per_molecule"])
        row["line_cross_section_cm2_per_molecule"] = repr(weak_sigma + strong_sigma)
        row["line_mixing_cross_section_cm2_per_molecule"] = spectroscopy_row[
            "line_mixing_sigma_cm2_per_molecule"
        ]
    write_csv_rows(optics_path, fieldnames, optics_rows)
    raw_optics_path.unlink()


def align_sublayer_optics_to_yaml(vendor_root: Path, yaml_root: Path) -> None:
    vendor_path = vendor_root / "sublayer_optics.csv"
    yaml_path = yaml_root / "sublayer_optics.csv"
    vendor_rows = read_csv_rows(vendor_path)
    yaml_rows = read_csv_rows(yaml_path)
    if not vendor_rows or not yaml_rows:
        return

    backup_path = vendor_root / "sublayer_optics_physical.csv"
    shutil.copy2(vendor_path, backup_path)

    vendor_groups: dict[str, list[dict[str, str]]] = {}
    for row in vendor_rows:
        key = aligned_sublayer_group_key(row)
        vendor_groups.setdefault(key, []).append(row)
    for group_rows in vendor_groups.values():
        group_rows.sort(key=lambda row: (-parse_float(row["pressure_hpa"]), parse_float(row["global_sublayer_index"])))

    aligned_vendor_rows: list[dict[str, str]] = []
    yaml_groups: dict[str, list[dict[str, str]]] = {}
    group_order: list[str] = []
    for row in yaml_rows:
        key = aligned_sublayer_group_key(row)
        if key not in yaml_groups:
            yaml_groups[key] = []
            group_order.append(key)
        yaml_groups[key].append(row)

    for key in group_order:
        yaml_group = yaml_groups[key]
        vendor_group = vendor_groups.get(key)
        if not vendor_group:
            continue
        representative_indices = representative_vendor_indices_for_yaml(vendor_group, yaml_group)
        for yaml_row, vendor_index in zip(yaml_group, representative_indices, strict=False):
            aligned_row = dict(vendor_group[vendor_index])
            aligned_row["global_sublayer_index"] = yaml_row["global_sublayer_index"]
            aligned_vendor_rows.append(aligned_row)

    if not aligned_vendor_rows:
        return
    write_csv_rows(vendor_path, list(yaml_rows[0].keys()), aligned_vendor_rows)


def annotate_transport_support_rows(side_root: Path, expand_overlapping_supports: bool = False) -> None:
    kernel_path = side_root / "kernel_samples.csv"
    if not kernel_path.exists():
        return

    support_by_wavelength: dict[tuple[str, str], dict[str, str]] = {}
    support_by_sample_wavelength: dict[str, list[dict[str, str]]] = {}
    for row in read_csv_rows(kernel_path):
        support_by_wavelength[support_join_key(row["nominal_wavelength_nm"], row["sample_wavelength_nm"])] = row
        support_by_sample_wavelength.setdefault(sample_support_key(row["sample_wavelength_nm"]), []).append(row)
    for file_name in (
        "fourier_terms.csv",
        "transport_layers.csv",
        "transport_layer_accumulation.csv",
        "transport_source_terms.csv",
        "transport_order_surface.csv",
        "transport_rt_probe.csv",
        "transport_rt_build_probe.csv",
        "transport_rt_double_probe.csv",
        "transport_zplus_terms.csv",
        "transport_source_angle_components.csv",
        "transport_attenuation_terms.csv",
        "transport_pseudo_spherical_samples.csv",
    ):
        path = side_root / file_name
        if not path.exists():
            continue
        headers = read_csv_headers(path)
        rows = read_csv_rows(path)
        fieldnames = [
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
        ] + [
            header
            for header in headers
            if header
            not in {
                "nominal_wavelength_nm",
                "sample_index",
                "sample_wavelength_nm",
                "kernel_weight",
            }
        ]

        annotated_rows: list[dict[str, str]] = []
        for row in rows:
            if expand_overlapping_supports:
                support_rows = support_by_sample_wavelength.get(sample_support_key(row["sample_wavelength_nm"]), [])
            else:
                support_row = support_by_wavelength.get(
                    support_join_key(row["nominal_wavelength_nm"], row["sample_wavelength_nm"])
                )
                support_rows = [] if support_row is None else [support_row]
            if not support_rows:
                continue
            for support_row in support_rows:
                annotated_row = dict(row)
                annotated_row["nominal_wavelength_nm"] = support_row["nominal_wavelength_nm"]
                annotated_row["sample_index"] = support_row["sample_index"]
                annotated_row["sample_wavelength_nm"] = support_row["sample_wavelength_nm"]
                annotated_row["kernel_weight"] = support_row["weight"]
                annotated_rows.append(annotated_row)
        write_csv_rows(path, fieldnames, annotated_rows)


def derive_granular_transport_traces(side_root: Path) -> None:
    derive_radiance_contributions(side_root)
    derive_source_components(side_root)
    derive_empty_trace(
        side_root / "transport_order_surface.csv",
        [
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "fourier_index",
            "order_index",
            "stop_reason",
            "max_value",
            "surface_u_order",
            "surface_u_accumulated",
            "surface_d_order",
            "surface_e_view",
        ],
    )
    derive_empty_trace(
        side_root / "transport_layer_accumulation.csv",
        [
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "layer_index",
            "babs",
            "bsca",
            "babs_gas",
            "bsca_gas",
            "babs_particles",
            "bsca_particles",
            "optical_depth",
            "scattering_optical_depth",
            "single_scatter_albedo",
        ],
    )
    derive_empty_trace(
        side_root / "transport_rt_probe.csv",
        [
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "fourier_index",
            "layer_index",
            "row_angle_index",
            "solar_column_index",
            "optical_depth",
            "scattering_optical_depth",
            "single_scatter_albedo",
            "rt_t_value",
            "attenuation_top_to_layer",
            "first_order_d_local",
        ],
    )
    derive_empty_trace(
        side_root / "transport_rt_build_probe.csv",
        [
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "fourier_index",
            "layer_index",
            "row_angle_index",
            "solar_column_index",
            "max_phase_index",
            "max_beta_eff",
            "a_eff",
            "use_doubling",
            "b_start",
            "ndouble",
            "zplus_value",
            "e_row",
            "e_col",
            "eet",
            "dmu_min",
            "single_t_value",
            "final_t_value",
        ],
    )
    derive_empty_trace(
        side_root / "transport_rt_double_probe.csv",
        [
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "fourier_index",
            "layer_index",
            "iteration",
            "b_before",
            "q_value",
            "d_value",
            "u_value",
            "t_before",
            "t_after",
        ],
    )
    derive_empty_trace(
        side_root / "transport_zplus_terms.csv",
        [
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "fourier_index",
            "layer_index",
            "row_angle_index",
            "solar_column_index",
            "coefficient_index",
            "phase_coefficient",
            "plm_row",
            "plm_col",
            "contribution",
            "cumulative_zplus",
        ],
    )
    derive_empty_trace(
        side_root / "transport_source_angle_components.csv",
        [
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "fourier_index",
            "level_index",
            "component_kind",
            "angle_index",
            "phase_value",
            "field_value",
            "angle_contribution",
            "weighted_angle_contribution",
        ],
    )
    derive_pseudo_spherical_terms(side_root)
    derive_optical_depth_components(side_root)


def derive_empty_trace(path: Path, fieldnames: list[str]) -> None:
    if path.exists():
        return
    write_csv_rows(path, fieldnames, [])


def derive_radiance_contributions(side_root: Path) -> None:
    source_path = side_root / "transport_samples.csv"
    target_path = side_root / "transport_radiance_contributions.csv"
    fieldnames = [
        "nominal_wavelength_nm",
        "sample_index",
        "sample_wavelength_nm",
        "kernel_weight",
        "reflectance",
        "irradiance",
        "radiance",
        "weighted_radiance_contribution",
    ]
    if not source_path.exists():
        write_csv_rows(target_path, fieldnames, [])
        return

    rows: list[dict[str, str]] = []
    for row in read_csv_rows(source_path):
        radiance = parse_float(row["radiance"])
        irradiance = parse_float(row["irradiance"])
        weight = parse_float(row["weight"])
        rows.append(
            {
                "nominal_wavelength_nm": row["nominal_wavelength_nm"],
                "sample_index": row["sample_index"],
                "sample_wavelength_nm": row["sample_wavelength_nm"],
                "kernel_weight": row["weight"],
                "reflectance": repr(radiance / max(irradiance, 1.0e-12)),
                "irradiance": row["irradiance"],
                "radiance": row["radiance"],
                "weighted_radiance_contribution": repr(weight * radiance),
            }
        )
    write_csv_rows(target_path, fieldnames, rows)


def derive_source_components(side_root: Path) -> None:
    source_path = side_root / "transport_source_terms.csv"
    target_path = side_root / "transport_source_components.csv"
    fieldnames = [
        "nominal_wavelength_nm",
        "sample_index",
        "sample_wavelength_nm",
        "kernel_weight",
        "fourier_index",
        "level_index",
        "e_view",
        "pmin_ed",
        "pplusst_u",
        "source_over_ksca",
        "source_contribution",
        "weighted_source_contribution",
    ]
    if not source_path.exists():
        write_csv_rows(target_path, fieldnames, [])
        return

    rows: list[dict[str, str]] = []
    for row in read_csv_rows(source_path):
        ksca = parse_float(row["ksca"])
        contribution = parse_float(row["source_contribution"])
        rows.append(
            {
                "nominal_wavelength_nm": row["nominal_wavelength_nm"],
                "sample_index": row["sample_index"],
                "sample_wavelength_nm": row["sample_wavelength_nm"],
                "kernel_weight": row["kernel_weight"],
                "fourier_index": row["fourier_index"],
                "level_index": row["level_index"],
                "e_view": "nan",
                "pmin_ed": "nan",
                "pplusst_u": "nan",
                "source_over_ksca": repr(contribution / ksca) if ksca > 0.0 else "nan",
                "source_contribution": row["source_contribution"],
                "weighted_source_contribution": row["weighted_source_contribution"],
            }
        )
    write_csv_rows(target_path, fieldnames, rows)


def derive_pseudo_spherical_terms(side_root: Path) -> None:
    sample_path = side_root / "transport_pseudo_spherical_samples.csv"
    attenuation_path = side_root / "transport_attenuation_terms.csv"
    target_path = side_root / "transport_pseudo_spherical_terms.csv"
    fieldnames = [
        "nominal_wavelength_nm",
        "sample_index",
        "sample_wavelength_nm",
        "kernel_weight",
        "direction_kind",
        "direction_index",
        "level_index",
        "global_sample_index",
        "level_altitude_km",
        "level_radius_km",
        "sample_altitude_km",
        "sample_radius_km",
        "numerator",
        "denominator",
        "contribution",
        "cumulative_sumkext",
        "grid_valid",
    ]
    if not sample_path.exists() or not attenuation_path.exists():
        write_csv_rows(target_path, fieldnames, [])
        return

    samples_by_support: dict[tuple[str, str, str], list[dict[str, str]]] = {}
    for row in read_csv_rows(sample_path):
        key = (row["nominal_wavelength_nm"], row["sample_index"], row["sample_wavelength_nm"])
        samples_by_support.setdefault(key, []).append(row)

    rows: list[dict[str, str]] = []
    earth_radius_km = 6371.0
    for attenuation_row in read_csv_rows(attenuation_path):
        key = (
            attenuation_row["nominal_wavelength_nm"],
            attenuation_row["sample_index"],
            attenuation_row["sample_wavelength_nm"],
        )
        level_index = int(float(attenuation_row["level_index"]))
        support_rows = samples_by_support.get(key, [])
        if not support_rows:
            continue
        sample_row = support_rows[min(level_index, len(support_rows) - 1)]
        sample_altitude = parse_float(sample_row["altitude_km"])
        sample_radius = earth_radius_km + sample_altitude
        contribution = parse_float(attenuation_row["sumkext"])
        rows.append(
            {
                "nominal_wavelength_nm": attenuation_row["nominal_wavelength_nm"],
                "sample_index": attenuation_row["sample_index"],
                "sample_wavelength_nm": attenuation_row["sample_wavelength_nm"],
                "kernel_weight": attenuation_row["kernel_weight"],
                "direction_kind": attenuation_row["direction_kind"],
                "direction_index": attenuation_row["direction_index"],
                "level_index": attenuation_row["level_index"],
                "global_sample_index": sample_row["global_sample_index"],
                "level_altitude_km": sample_row["altitude_km"],
                "level_radius_km": repr(sample_radius),
                "sample_altitude_km": sample_row["altitude_km"],
                "sample_radius_km": repr(sample_radius),
                "numerator": sample_row["radius_weighted_optical_depth"],
                "denominator": "nan",
                "contribution": repr(contribution),
                "cumulative_sumkext": attenuation_row["sumkext"],
                "grid_valid": attenuation_row["grid_valid"],
            }
        )
    write_csv_rows(target_path, fieldnames, rows)


def derive_optical_depth_components(side_root: Path) -> None:
    source_path = side_root / "sublayer_optics.csv"
    target_path = side_root / "transport_optical_depth_components.csv"
    fieldnames = [
        "wavelength_nm",
        "global_sublayer_index",
        "interval_index_1based",
        "line_absorption_optical_depth",
        "cia_optical_depth",
        "gas_scattering_optical_depth",
        "aerosol_optical_depth",
        "cloud_optical_depth",
        "total_absorption_optical_depth",
        "total_scattering_optical_depth",
        "total_optical_depth",
    ]
    if not source_path.exists():
        write_csv_rows(target_path, fieldnames, [])
        return

    rows: list[dict[str, str]] = []
    for row in read_csv_rows(source_path):
        total = parse_float(row["total_optical_depth"])
        scattering = parse_float(row["total_scattering_optical_depth"])
        rows.append(
            {
                "wavelength_nm": row["wavelength_nm"],
                "global_sublayer_index": row["global_sublayer_index"],
                "interval_index_1based": row["interval_index_1based"],
                "line_absorption_optical_depth": row["gas_absorption_optical_depth"],
                "cia_optical_depth": row["cia_optical_depth"],
                "gas_scattering_optical_depth": row["gas_scattering_optical_depth"],
                "aerosol_optical_depth": row["aerosol_optical_depth"],
                "cloud_optical_depth": row["cloud_optical_depth"],
                "total_absorption_optical_depth": repr(total - scattering),
                "total_scattering_optical_depth": row["total_scattering_optical_depth"],
                "total_optical_depth": row["total_optical_depth"],
            }
        )
    write_csv_rows(target_path, fieldnames, rows)


def support_join_key(nominal_wavelength_nm: str, sample_wavelength_nm: str) -> tuple[str, str]:
    return (normalized_float_key(nominal_wavelength_nm), normalized_float_key(sample_wavelength_nm))


def sample_support_key(sample_wavelength_nm: str) -> str:
    return normalized_float_key(sample_wavelength_nm)


def aligned_sublayer_group_key(row: dict[str, str]) -> str:
    return f"{parse_float(row['wavelength_nm']):.12f}"


def representative_vendor_indices_for_yaml(
    vendor_rows: list[dict[str, str]],
    yaml_rows: list[dict[str, str]],
) -> list[int]:
    vendor_count = len(vendor_rows)
    target_count = len(yaml_rows)
    if target_count <= 0 or vendor_count <= 0:
        return []
    if vendor_count == target_count:
        return list(range(vendor_count))

    indices: list[int] = []
    lower_bound = 0
    for target_index in range(target_count):
        upper_bound = vendor_count - (target_count - target_index) + 1
        desired_pressure = parse_float(yaml_rows[target_index]["pressure_hpa"])
        best_index = lower_bound
        best_delta = abs(parse_float(vendor_rows[best_index]["pressure_hpa"]) - desired_pressure)
        for vendor_index in range(lower_bound, upper_bound):
            delta = abs(parse_float(vendor_rows[vendor_index]["pressure_hpa"]) - desired_pressure)
            if delta < best_delta:
                best_index = vendor_index
                best_delta = delta
        indices.append(best_index)
        lower_bound = best_index + 1
    return indices


def nearest_spectroscopy_row(
    spectroscopy_rows: list[dict[str, str]],
    optics_row: dict[str, str],
) -> dict[str, str] | None:
    best_row: dict[str, str] | None = None
    best_score: tuple[float, float, float] | None = None
    optics_pressure = parse_float(optics_row["pressure_hpa"])
    optics_temperature = parse_float(optics_row["temperature_k"])
    optics_wavelength = parse_float(optics_row["wavelength_nm"])
    for spectroscopy_row in spectroscopy_rows:
        score = (
            abs(parse_float(spectroscopy_row["wavelength_nm"]) - optics_wavelength),
            abs(parse_float(spectroscopy_row["pressure_hpa"]) - optics_pressure),
            abs(parse_float(spectroscopy_row["temperature_k"]) - optics_temperature),
        )
        if best_score is None or score < best_score:
            best_score = score
            best_row = spectroscopy_row
    return best_row


def canonicalize_side(side_root: Path) -> None:
    for file_name in EXPECTED_CSVS:
        path = side_root / file_name
        spec = CSV_SPECS[file_name]
        rows = read_csv_rows(path)
        sort_rows(rows, spec)
        if file_name in {
            "adaptive_grid.csv",
            "kernel_samples.csv",
            "transport_samples.csv",
            "irradiance_contributions.csv",
            "interval_bounds.csv",
        }:
            rows = dedupe_exact_rows(rows)
        write_csv_rows(path, list(rows[0].keys()) if rows else read_csv_headers(path), rows)


def canonicalize_optional_csv(side_root: Path, file_name: str, spec: CsvSpec) -> None:
    path = side_root / file_name
    if not path.exists():
        return
    rows = read_csv_rows(path)
    sort_rows(rows, spec)
    write_csv_rows(path, list(rows[0].keys()) if rows else read_csv_headers(path), rows)


def dedupe_exact_rows(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    if not rows:
        return rows
    deduped: list[dict[str, str]] = [rows[0]]
    for row in rows[1:]:
        if row == deduped[-1]:
            continue
        deduped.append(row)
    return deduped


def verify_expected_csvs(side_root: Path, label: str) -> None:
    missing = [name for name in EXPECTED_CSVS if not (side_root / name).exists()]
    if missing:
        raise RuntimeError(f"Missing {label} CSVs: {', '.join(missing)}")


def write_diff_summaries(trace_root: Path, diff_root: Path, wavelengths_nm: list[float]) -> None:
    combined_lines: list[str] = []
    for left_label, right_label in PAIRWISE_DIFFS:
        summary = summarize_pairwise_diff(
            trace_root / left_label,
            trace_root / right_label,
            left_label,
            right_label,
            wavelengths_nm,
        )
        summary_lines = summary["lines"]
        summary_path = diff_root / f"{left_label}_vs_{right_label}.txt"
        summary_path.write_text("\n".join(summary_lines).rstrip() + "\n", encoding="utf-8")
        summary_json_path = diff_root / f"{left_label}_vs_{right_label}.json"
        summary_json_path.write_text(
            json.dumps(summary["json"], indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        if combined_lines:
            combined_lines.append("")
        combined_lines.extend(summary_lines)

    if combined_lines:
        (diff_root / "summary.txt").write_text(
            "\n".join(combined_lines).rstrip() + "\n",
            encoding="utf-8",
        )
    if len(PAIRWISE_DIFFS) == 1:
        summary = summarize_pairwise_diff(
            trace_root / PAIRWISE_DIFFS[0][0],
            trace_root / PAIRWISE_DIFFS[0][1],
            PAIRWISE_DIFFS[0][0],
            PAIRWISE_DIFFS[0][1],
            wavelengths_nm,
        )
        (diff_root / "summary.json").write_text(
            json.dumps(summary["json"], indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )


def write_weak_line_contributor_summary(trace_root: Path, diff_root: Path, wavelengths_nm: list[float]) -> None:
    vendor_path = trace_root / "vendor" / WEAK_LINE_CONTRIBUTOR_FILE
    yaml_path = trace_root / "yaml" / WEAK_LINE_CONTRIBUTOR_FILE
    if not vendor_path.exists() or not yaml_path.exists():
        return

    vendor_rows = read_csv_rows(vendor_path)
    yaml_rows = read_csv_rows(yaml_path)
    lines = ["weak_line_contributors"]
    summary_json: dict[str, object] = {"wavelengths_nm": list(wavelengths_nm), "per_wavelength": []}

    for wavelength_nm in wavelengths_nm:
        vendor_aggregates = aggregate_weak_line_contributors(vendor_rows, wavelength_nm)
        yaml_aggregates = aggregate_weak_line_contributors(yaml_rows, wavelength_nm)
        all_keys = set(vendor_aggregates) | set(yaml_aggregates)
        ranked: list[dict[str, object]] = []
        vendor_total = 0.0
        yaml_total = 0.0
        for key in all_keys:
            vendor_record = vendor_aggregates.get(key)
            yaml_record = yaml_aggregates.get(key)
            vendor_value = 0.0 if vendor_record is None else vendor_record["total"]
            yaml_value = 0.0 if yaml_record is None else yaml_record["total"]
            vendor_total += vendor_value
            yaml_total += yaml_value
            metadata = (vendor_record or yaml_record)["metadata"]
            ranked.append(
                {
                    "metadata": metadata,
                    "vendor_total": vendor_value,
                    "yaml_total": yaml_value,
                    "absolute_delta": abs(vendor_value - yaml_value),
                }
            )
        ranked.sort(key=lambda row: row["absolute_delta"], reverse=True)
        top_ranked = ranked[:12]
        lines.append(f"wavelength_nm={format_wavelength(wavelength_nm)}")
        lines.append(
            "  "
            f"vendor_total={vendor_total:.16e} "
            f"yaml_total={yaml_total:.16e} "
            f"abs_delta={abs(vendor_total - yaml_total):.16e} "
            f"vendor_only={sum(1 for row in ranked if row['vendor_total'] != 0.0 and row['yaml_total'] == 0.0)} "
            f"yaml_only={sum(1 for row in ranked if row['yaml_total'] != 0.0 and row['vendor_total'] == 0.0)}"
        )
        if not top_ranked:
            lines.append("  no contributor rows")
        else:
            for index, row in enumerate(top_ranked, start=1):
                metadata = row["metadata"]
                lines.append(
                    "  "
                    f"{index}. center_cm1={metadata['center_wavenumber_cm1']} "
                    f"center_nm={metadata['center_wavelength_nm']} "
                    f"isotope={metadata['isotope_number']} "
                    f"strength={metadata['line_strength_cm2_per_molecule']} "
                    f"elow={metadata['lower_state_energy_cm1']} "
                    f"vendor_total={row['vendor_total']:.16e} "
                    f"yaml_total={row['yaml_total']:.16e} "
                    f"abs_delta={row['absolute_delta']:.16e}"
                )
        summary_json["per_wavelength"].append(
            {
                "wavelength_nm": wavelength_nm,
                "vendor_total": vendor_total,
                "yaml_total": yaml_total,
                "absolute_delta": abs(vendor_total - yaml_total),
                "top_ranked_contributors": top_ranked,
            }
        )
        lines.append("")

    (diff_root / "weak_line_contributors_summary.txt").write_text(
        "\n".join(lines).rstrip() + "\n",
        encoding="utf-8",
    )
    (diff_root / "weak_line_contributors_summary.json").write_text(
        json.dumps(summary_json, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def write_granular_contributor_summaries(trace_root: Path, diff_root: Path, wavelengths_nm: list[float]) -> None:
    write_ranked_delta_summary(
        trace_root,
        diff_root,
        "transport_radiance_contributions.csv",
        "radiance_contributor_summary",
        ["weighted_radiance_contribution", "radiance", "reflectance"],
        wavelengths_nm,
        min_activity_column="weighted_radiance_contribution",
        primary_column="weighted_radiance_contribution",
    )
    write_ranked_delta_summary(
        trace_root,
        diff_root,
        "transport_source_components.csv",
        "labos_m0_summary",
        ["weighted_source_contribution", "source_contribution", "source_over_ksca"],
        wavelengths_nm,
        m0_only=True,
        min_activity_column="weighted_source_contribution",
    )
    write_ranked_delta_summary(
        trace_root,
        diff_root,
        "transport_pseudo_spherical_terms.csv",
        "attenuation_contributor_summary",
        ["contribution", "cumulative_sumkext", "numerator"],
        wavelengths_nm,
        min_activity_column="contribution",
    )
    write_ranked_delta_summary(
        trace_root,
        diff_root,
        "transport_optical_depth_components.csv",
        "optical_depth_component_summary",
        [
            "total_optical_depth",
            "line_absorption_optical_depth",
            "cia_optical_depth",
            "gas_scattering_optical_depth",
            "total_scattering_optical_depth",
            "total_absorption_optical_depth",
        ],
        wavelengths_nm,
        wavelength_column="wavelength_nm",
        min_activity_column="total_optical_depth",
    )


def write_function_diff_plot_bundle(trace_root: Path, diff_root: Path, wavelengths_nm: list[float]) -> None:
    vendor_path = trace_root / "vendor" / "transport_summary.csv"
    yaml_path = trace_root / "yaml" / "transport_summary.csv"
    if not vendor_path.exists() or not yaml_path.exists():
        return

    vendor_rows = summary_rows_by_wavelength(read_csv_rows(vendor_path))
    yaml_rows = summary_rows_by_wavelength(read_csv_rows(yaml_path))
    common_wavelengths = [
        wavelength_nm
        for wavelength_nm in wavelengths_nm
        if f"{wavelength_nm:.12e}" in vendor_rows and f"{wavelength_nm:.12e}" in yaml_rows
    ]
    if not common_wavelengths:
        return

    plot_dir = diff_root / "function_diff_plots"
    plot_dir.mkdir(parents=True, exist_ok=True)

    vendor_spectrum = spectrum_from_summary_rows(vendor_rows, common_wavelengths)
    yaml_spectrum = spectrum_from_summary_rows(yaml_rows, common_wavelengths)
    wavelength_array = np.array(common_wavelengths, dtype=float)
    write_spectrum_csv(plot_dir / "vendor_trace_spectrum.csv", vendor_spectrum)
    write_spectrum_csv(plot_dir / "yaml_trace_spectrum.csv", yaml_spectrum)

    create_plots(plot_dir, wavelength_array, yaml_spectrum, vendor_spectrum)
    metrics = {
        "sample_count": int(len(common_wavelengths)),
        "wavelength_min_nm": float(wavelength_array.min()),
        "wavelength_max_nm": float(wavelength_array.max()),
        "vendor_trace_spectrum_path": stable_repo_path(plot_dir / "vendor_trace_spectrum.csv"),
        "yaml_trace_spectrum_path": stable_repo_path(plot_dir / "yaml_trace_spectrum.csv"),
        "reflectance": function_diff_metric_block(
            wavelength_array,
            yaml_spectrum["reflectance"],
            vendor_spectrum["reflectance"],
        ),
        "radiance": function_diff_metric_block(wavelength_array, yaml_spectrum["radiance"], vendor_spectrum["radiance"]),
        "irradiance": function_diff_metric_block(
            wavelength_array,
            yaml_spectrum["irradiance"],
            vendor_spectrum["irradiance"],
        ),
    }
    (plot_dir / "comparison_metrics.json").write_text(json.dumps(metrics, indent=2, sort_keys=True) + "\n")


def function_diff_metric_block(wavelength_nm: np.ndarray, yaml_values: np.ndarray, vendor_values: np.ndarray) -> dict[str, float]:
    residual = yaml_values - vendor_values
    correlation = math.nan
    if len(wavelength_nm) > 1 and np.std(yaml_values) > 0.0 and np.std(vendor_values) > 0.0:
        correlation = float(np.corrcoef(yaml_values, vendor_values)[0, 1])
    return {
        "mae": float(np.mean(np.abs(residual))),
        "rmse": float(np.sqrt(np.mean(residual**2))),
        "max_abs": float(np.max(np.abs(residual))),
        "max_abs_wavelength_nm": float(wavelength_nm[np.argmax(np.abs(residual))]),
        "correlation": correlation,
        "mean_signed": float(np.mean(residual)),
    }


def summary_rows_by_wavelength(rows: list[dict[str, str]]) -> dict[str, dict[str, str]]:
    return {f"{parse_float(row['nominal_wavelength_nm']):.12e}": row for row in rows}


def spectrum_from_summary_rows(
    rows_by_wavelength: dict[str, dict[str, str]],
    wavelengths_nm: list[float],
) -> dict[str, np.ndarray]:
    rows = [rows_by_wavelength[f"{wavelength_nm:.12e}"] for wavelength_nm in wavelengths_nm]
    return {
        "wavelength_nm": np.array(wavelengths_nm, dtype=float),
        "reflectance": np.array([parse_float(row["final_reflectance"]) for row in rows], dtype=float),
        "radiance": np.array([parse_float(row["final_radiance"]) for row in rows], dtype=float),
        "irradiance": np.array([parse_float(row["final_irradiance"]) for row in rows], dtype=float),
    }


def write_spectrum_csv(path: Path, spectrum: dict[str, np.ndarray]) -> None:
    fieldnames = ["wavelength_nm", "reflectance", "radiance", "irradiance"]
    rows = []
    for index in range(len(spectrum["wavelength_nm"])):
        rows.append({field: repr(float(spectrum[field][index])) for field in fieldnames})
    write_csv_rows(path, fieldnames, rows)


def write_ranked_delta_summary(
    trace_root: Path,
    diff_root: Path,
    file_name: str,
    output_stem: str,
    columns: list[str],
    wavelengths_nm: list[float],
    *,
    wavelength_column: str = "nominal_wavelength_nm",
    m0_only: bool = False,
    min_activity_column: str | None = None,
    primary_column: str | None = None,
) -> None:
    vendor_path = trace_root / "vendor" / file_name
    yaml_path = trace_root / "yaml" / file_name
    spec = CSV_SPECS[file_name]
    lines = [output_stem]
    output_json: dict[str, object] = {"file": file_name, "wavelengths_nm": list(wavelengths_nm), "ranked": []}
    if not vendor_path.exists() or not yaml_path.exists():
        lines.append("  missing input")
        write_summary_files(diff_root, output_stem, lines, output_json)
        return

    vendor_rows = rows_by_key(read_csv_rows(vendor_path), spec)
    yaml_rows = rows_by_key(read_csv_rows(yaml_path), spec)
    ranked: list[dict[str, object]] = []
    for key in sorted(set(vendor_rows) | set(yaml_rows), key=str):
        vendor_row = vendor_rows.get(key)
        yaml_row = yaml_rows.get(key)
        row = vendor_row or yaml_row
        if row is None:
            continue
        if m0_only and row.get("fourier_index") not in {None, "0", "0.0"}:
            continue
        if not row_matches_wavelength(row, wavelengths_nm, wavelength_column):
            continue
        if min_activity_column is not None:
            vendor_activity = abs(parse_float_or_zero(vendor_row, min_activity_column))
            yaml_activity = abs(parse_float_or_zero(yaml_row, min_activity_column))
            if max(vendor_activity, yaml_activity) <= 1.0e-24:
                continue
        for column in columns:
            vendor_value = parse_float_or_zero(vendor_row, column)
            yaml_value = parse_float_or_zero(yaml_row, column)
            delta = vendor_value - yaml_value
            if delta == 0.0 or math.isnan(delta):
                continue
            ranked.append(
                {
                    "column": column,
                    "key": list(key),
                    "signed_delta": delta,
                    "abs_delta": abs(delta),
                    "vendor": vendor_value,
                    "yaml": yaml_value,
                }
            )

    ranked.sort(
        key=lambda item: (
            0 if primary_column is not None and item["column"] == primary_column else 1,
            -float(item["abs_delta"]),
        )
    )
    signed_total = sum(float(item["signed_delta"]) for item in ranked)
    total_abs = sum(float(item["abs_delta"]) for item in ranked)
    cumulative_abs = 0.0
    for item in ranked[:25]:
        cumulative_abs += float(item["abs_delta"])
        item["cumulative_abs_share"] = cumulative_abs / total_abs if total_abs > 0.0 else 0.0
        item["signed_total_share"] = (
            float(item["signed_delta"]) / signed_total if abs(signed_total) > 1.0e-300 else math.nan
        )

    if not ranked:
        lines.append("  no active signed deltas")
    else:
        for item in ranked[:10]:
            lines.append(
                "  "
                f"column={item['column']} "
                f"key={item['key']!r} "
                f"signed_delta={item['signed_delta']:.12e} "
                f"abs_delta={item['abs_delta']:.12e} "
                f"cumulative_abs_share={item.get('cumulative_abs_share', 0.0):.6f}"
            )
    output_json["ranked"] = ranked[:25]
    output_json["signed_total"] = signed_total
    output_json["total_abs"] = total_abs
    write_summary_files(diff_root, output_stem, lines, output_json)


def write_summary_files(diff_root: Path, stem: str, lines: list[str], payload: dict[str, object]) -> None:
    (diff_root / f"{stem}.txt").write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    (diff_root / f"{stem}.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def rows_by_key(rows: list[dict[str, str]], spec: CsvSpec) -> dict[tuple[str, ...], dict[str, str]]:
    return {
        tuple(normalized_summary_key_value(row.get(column, "")) for column in spec.key_columns): row
        for row in rows
    }


def normalized_summary_key_value(raw: str) -> str:
    try:
        value = parse_float(raw)
    except ValueError:
        return raw
    if math.isnan(value):
        return "nan"
    return f"{value:.12e}"


def parse_float_or_zero(row: dict[str, str] | None, column: str) -> float:
    if row is None:
        return 0.0
    try:
        value = parse_float(row.get(column, "0.0"))
    except ValueError:
        return 0.0
    if math.isnan(value):
        return 0.0
    return value


def row_matches_wavelength(row: dict[str, str], wavelengths_nm: list[float], column: str) -> bool:
    if column not in row:
        return True
    row_wavelength = parse_float(row[column])
    return any(abs(row_wavelength - wavelength_nm) <= 1.5e-2 for wavelength_nm in wavelengths_nm)


def aggregate_weak_line_contributors(
    rows: list[dict[str, str]],
    wavelength_nm: float,
) -> dict[tuple[str, ...], dict[str, object]]:
    aggregates: dict[tuple[str, ...], dict[str, object]] = {}
    target_wavelength = f"{wavelength_nm:.12e}"
    for row in rows:
        if f"{parse_float(row['wavelength_nm']):.12e}" != target_wavelength:
            continue
        contribution_kind = row.get("contribution_kind", "weak_included").strip()
        if contribution_kind == "strong_sidecar":
            continue
        contribution = parse_float(row["weak_line_sigma_cm2_per_molecule"])
        if contribution == 0.0:
            continue
        key = weak_line_contributor_key(row)
        record = aggregates.setdefault(
            key,
            {
                "total": 0.0,
                "metadata": {
                    "center_wavenumber_cm1": row["center_wavenumber_cm1"],
                    "center_wavelength_nm": row["center_wavelength_nm"],
                    "isotope_number": row["isotope_number"],
                    "line_strength_cm2_per_molecule": row["line_strength_cm2_per_molecule"],
                    "lower_state_energy_cm1": row["lower_state_energy_cm1"],
                },
            },
        )
        record["total"] += contribution
    return aggregates


def weak_line_contributor_key(row: dict[str, str]) -> tuple[str, ...]:
    return (
        normalized_float_key(row["gas_index"]),
        normalized_float_key(row["isotope_number"]),
        normalized_float_key(row["center_wavenumber_cm1"]),
        normalized_float_key(row["line_strength_cm2_per_molecule"]),
        normalized_float_key(row["lower_state_energy_cm1"]),
        normalized_float_key(row["air_half_width_nm"]),
        normalized_float_key(row["temperature_exponent"]),
        normalized_float_key(row["pressure_shift_nm"]),
    )


def normalized_float_key(raw: str) -> str:
    value = parse_float(raw)
    if math.isnan(value):
        return "nan"
    return f"{value:.12e}"


def summarize_pairwise_diff(
    left_root: Path,
    right_root: Path,
    left_label: str,
    right_label: str,
    wavelengths_nm: list[float],
) -> dict[str, object]:
    first_divergence: NumericMismatch | None = None
    first_aligned_divergence: NumericMismatch | None = None
    per_file: list[tuple[str, FileComparison]] = []
    lines = [f"{left_label}_vs_{right_label}", "first_divergence"]
    for file_name in STAGE_ORDER:
        comparison = compare_csv_files_with_details(
            left_root / file_name,
            right_root / file_name,
            CSV_SPECS[file_name],
            file_name=file_name,
            left_label=left_label,
            right_label=right_label,
        )
        per_file.append((file_name, comparison))
        if first_divergence is None and comparison.first_numeric_mismatch is not None:
            first_divergence = comparison.first_numeric_mismatch
        if first_aligned_divergence is None and comparison.aligned_numeric_mismatch is not None:
            first_aligned_divergence = comparison.aligned_numeric_mismatch

    if first_divergence is None:
        lines.append("  none")
    else:
        lines.append(
            "  "
            f"file={first_divergence.file_name} "
            f"row_key={first_divergence.row_key!r} "
            f"column={first_divergence.column} "
            f"{left_label}={first_divergence.left_value!r} "
            f"{right_label}={first_divergence.right_value!r} "
            f"abs_delta={first_divergence.absolute_delta!r}"
        )
    lines.append("")
    lines.append("first_aligned_physics_divergence")
    if first_aligned_divergence is None:
        lines.append("  none")
    else:
        lines.append(
            "  "
            f"file={first_aligned_divergence.file_name} "
            f"row_key={first_aligned_divergence.row_key!r} "
            f"column={first_aligned_divergence.column} "
            f"{left_label}={first_aligned_divergence.left_value!r} "
            f"{right_label}={first_aligned_divergence.right_value!r} "
            f"abs_delta={first_aligned_divergence.absolute_delta!r}"
        )
    lines.append("")

    for file_name, comparison in per_file:
        lines.append(file_name)
        for line in comparison.lines:
            lines.append(f"  {line}")
        lines.append("")
    return {
        "lines": lines,
        "json": {
            "left_label": left_label,
            "right_label": right_label,
            "wavelengths_nm": list(wavelengths_nm),
            "first_mismatching_file": None if first_divergence is None else first_divergence.file_name,
            "first_mismatching_row_key": None if first_divergence is None else [serialize_key_value(value) for value in first_divergence.row_key],
            "first_mismatching_numeric_column": None if first_divergence is None else first_divergence.column,
            "first_aligned_mismatching_file": None if first_aligned_divergence is None else first_aligned_divergence.file_name,
            "first_aligned_mismatching_row_key": None if first_aligned_divergence is None else [serialize_key_value(value) for value in first_aligned_divergence.row_key],
            "first_aligned_mismatching_numeric_column": None if first_aligned_divergence is None else first_aligned_divergence.column,
            left_label: None if first_divergence is None else serialize_float(first_divergence.left_value),
            right_label: None if first_divergence is None else serialize_float(first_divergence.right_value),
            "absolute_delta": None if first_divergence is None else serialize_float(first_divergence.absolute_delta),
            f"{left_label}_aligned": None if first_aligned_divergence is None else serialize_float(first_aligned_divergence.left_value),
            f"{right_label}_aligned": None if first_aligned_divergence is None else serialize_float(first_aligned_divergence.right_value),
            "aligned_absolute_delta": None if first_aligned_divergence is None else serialize_float(first_aligned_divergence.absolute_delta),
        },
    }


def compare_csv_files(
    left_path: Path,
    right_path: Path,
    spec: CsvSpec,
    *,
    left_label: str = "vendor",
    right_label: str = "yaml",
) -> list[str]:
    return compare_csv_files_with_details(
        left_path,
        right_path,
        spec,
        file_name=left_path.name,
        left_label=left_label,
        right_label=right_label,
    ).lines


def compare_csv_files_with_details(
    left_path: Path,
    right_path: Path,
    spec: CsvSpec,
    *,
    file_name: str,
    left_label: str = "vendor",
    right_label: str = "yaml",
) -> FileComparison:
    left_headers = read_csv_headers(left_path)
    right_headers = read_csv_headers(right_path)
    if left_headers != right_headers:
        raise RuntimeError(f"Schema mismatch for {left_path.name}: {left_headers} != {right_headers}")

    left_rows = read_csv_rows(left_path)
    right_rows = read_csv_rows(right_path)
    output = [f"rows: {left_label}={len(left_rows)} {right_label}={len(right_rows)}"]
    if len(left_rows) != len(right_rows):
        output.append("row-count mismatch")

    paired_count = min(len(left_rows), len(right_rows))
    first_key_mismatch = None
    for index in range(paired_count):
        if row_key(left_rows[index], spec) != row_key(right_rows[index], spec):
            first_key_mismatch = index
            break
    if first_key_mismatch is not None:
        output.append(
            "first key mismatch at row "
            f"{first_key_mismatch + 1}: "
            f"{left_label}={row_key(left_rows[first_key_mismatch], spec)} "
            f"{right_label}={row_key(right_rows[first_key_mismatch], spec)}"
        )
    else:
        output.append("keys/order: match")
    keys_aligned = len(left_rows) == len(right_rows) and first_key_mismatch is None
    output.append(f"alignment: {'aligned' if keys_aligned else 'misaligned'}")

    first_nonzero_delta = None
    first_aligned_delta = None
    for column in spec.numeric_columns:
        max_abs_diff = 0.0
        first_numeric_mismatch = None
        for index in range(paired_count):
            left = parse_float(left_rows[index][column])
            right = parse_float(right_rows[index][column])
            diff = numeric_difference(left, right)
            if diff > max_abs_diff:
                max_abs_diff = diff
            if first_numeric_mismatch is None and diff > 0.0:
                first_numeric_mismatch = (index, left, right)
            if first_nonzero_delta is None and diff > 0.0:
                first_nonzero_delta = NumericMismatch(
                    file_name=file_name,
                    row_index_1based=index + 1,
                    row_key=readable_row_key(left_rows[index], spec),
                    column=column,
                    left_value=left,
                    right_value=right,
                    absolute_delta=diff,
                )
            if first_aligned_delta is None and keys_aligned and diff > 0.0:
                first_aligned_delta = NumericMismatch(
                    file_name=file_name,
                    row_index_1based=index + 1,
                    row_key=readable_row_key(left_rows[index], spec),
                    column=column,
                    left_value=left,
                    right_value=right,
                    absolute_delta=diff,
                )
        if first_numeric_mismatch is None:
            output.append(f"{column}: max_abs_diff=0.0 first_diff=none")
        else:
            index, left, right = first_numeric_mismatch
            output.append(
                f"{column}: max_abs_diff={max_abs_diff:.12e} "
                f"first_diff_row={index + 1} {left_label}={left!r} {right_label}={right!r}"
            )
    if first_nonzero_delta is None:
        output.append("first_nonzero_delta: none")
    else:
        output.append(
            f"first_nonzero_delta: column={first_nonzero_delta.column} "
            f"row={first_nonzero_delta.row_index_1based} "
            f"{left_label}={first_nonzero_delta.left_value!r} "
            f"{right_label}={first_nonzero_delta.right_value!r}"
        )
    return FileComparison(
        lines=output,
        first_numeric_mismatch=first_nonzero_delta,
        aligned_numeric_mismatch=first_aligned_delta,
        keys_aligned=keys_aligned,
    )


def sort_rows(rows: list[dict[str, str]], spec: CsvSpec) -> None:
    rows.sort(key=lambda row: tuple(sortable_value(row[column]) for column in spec.key_columns))


def row_key(row: dict[str, str], spec: CsvSpec) -> tuple[object, ...]:
    return tuple(sortable_value(row[column]) for column in spec.key_columns)


def readable_row_key(row: dict[str, str], spec: CsvSpec) -> tuple[str, ...]:
    return tuple(row[column] for column in spec.key_columns)


def sortable_value(raw: str) -> object:
    try:
        value = parse_float(raw)
    except ValueError:
        return (0, raw)
    if math.isnan(value):
        return (1, 0.0)
    return (0, value)


def parse_float(raw: str) -> float:
    text = raw.strip()
    if text.lower() == "nan":
        return math.nan
    return float(text)


def numeric_difference(left: float, right: float) -> float:
    if math.isnan(left) and math.isnan(right):
        return 0.0
    if math.isnan(left) or math.isnan(right):
        return math.inf
    return abs(left - right)


def serialize_float(value: float) -> float | str:
    if math.isnan(value):
        return "nan"
    if math.isinf(value):
        return "inf" if value > 0 else "-inf"
    return value


def serialize_key_value(value: object) -> object:
    if not isinstance(value, tuple) or len(value) != 2:
        return value
    tag, payload = value
    if isinstance(payload, float):
        return serialize_float(payload)
    return payload


def read_csv_headers(path: Path) -> list[str]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle)
        return next(reader)


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv_rows(path: Path, fieldnames: list[str], rows: Iterable[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def patch_makefile(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "    dataStructures.f90 \\\n    staticDataModule.f90 \\\n",
        "    dataStructures.f90 \\\n    o2aFunctionTraceModule.f90 \\\n    staticDataModule.f90 \\\n",
        path,
    )
    text = replace_once(
        text,
        "    dataStructures.o \\\n    staticDataModule.o \\\n",
        "    dataStructures.o \\\n    o2aFunctionTraceModule.o \\\n    staticDataModule.o \\\n",
        path,
    )
    text = replace_once(
        text,
        "dataStructures.o: dataStructures.f90\n\t$(F90) -c $(F90FLAGS) dataStructures.f90 -o dataStructures.o\n\n",
        "dataStructures.o: dataStructures.f90\n\t$(F90) -c $(F90FLAGS) dataStructures.f90 -o dataStructures.o\n\n"
        "o2aFunctionTraceModule.o: o2aFunctionTraceModule.f90\n\t$(F90) -c $(F90FLAGS) o2aFunctionTraceModule.f90 -o o2aFunctionTraceModule.o\n\n",
        path,
    )
    text = replace_once(
        text,
        "HITRANModule.o: HITRANModule.f90 \\\n                 dataStructures.o\n",
        "HITRANModule.o: HITRANModule.f90 \\\n                 dataStructures.o \\\n                 o2aFunctionTraceModule.o\n",
        path,
    )
    text = replace_once(
        text,
        "radianceIrradianceModule.o: radianceIrradianceModule.f90 \\\n                          dataStructures.o \\\n",
        "radianceIrradianceModule.o: radianceIrradianceModule.f90 \\\n                          dataStructures.o \\\n                          o2aFunctionTraceModule.o \\\n",
        path,
    )
    text = replace_once(
        text,
        "LabosModule.o: LabosModule.f90 \\\n              mathToolsModule.o \\\n              dataStructures.o \\\n              addingToolsModule.o\n",
        "LabosModule.o: LabosModule.f90 \\\n              mathToolsModule.o \\\n              dataStructures.o \\\n              addingToolsModule.o \\\n              o2aFunctionTraceModule.o\n",
        path,
    )
    text = replace_once(
        text,
        "DISAMARModule.o: DISAMARModule.f90 \\\n              dataStructures.o \\\n",
        "DISAMARModule.o: DISAMARModule.f90 \\\n              dataStructures.o \\\n              o2aFunctionTraceModule.o \\\n",
        path,
    )
    text = replace_once(
        text,
        "propAtmosphere.o: propAtmosphere.f90 \\\n                mathToolsModule.o \\\n                dataStructures.o \\\n                readModule.o \\\n                ramanspecsModule_v2.o\n",
        "propAtmosphere.o: propAtmosphere.f90 \\\n                mathToolsModule.o \\\n                dataStructures.o \\\n                readModule.o \\\n                ramanspecsModule_v2.o \\\n                o2aFunctionTraceModule.o\n",
        path,
    )
    path.write_text(text, encoding="utf-8")


def patch_hitran_module(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "  use mathTools\n",
        "  use mathTools\n  use o2aFunctionTraceModule, only: o2a_trace_line_catalog_row, o2a_trace_convtp_state, o2a_trace_weak_spectroscopy, o2a_trace_strong_spectroscopy, o2a_trace_weak_line_contributor, o2a_trace_wavelength_count_value, o2a_trace_wavelength_nm_value\n",
        path,
    )
    text = replace_once(
        text,
        "          hitranS%delt(i)    = delt_read\n\n          i = i + 1\n",
        "          hitranS%delt(i)    = delt_read\n"
        "          if ( filterStrongLinesO2A .and. (gasIndex_read == 7) ) then\n"
        "            call o2a_trace_line_catalog_row(i, gasIndex_read, isotope_read, Sig_read, S_read, gam_read, E_read, bet_read, delt_read, ic1_read, ic2_read, Nf_read)\n"
        "          end if\n\n"
        "          i = i + 1\n",
        path,
    )
    text = replace_once(
        text,
        "      ! Computation of the first order line-coupling coefficients\n"
        "      do iLine = 1, SDFS%nLines\n"
        "        YY=0.D0\n"
        "        do iLineP = 1, SDFS%nLines\n"
        "          if (iLine.ne.iLineP.and.SDFS%modSigLines(iLine).ne.SDFS%modSigLines(iLineP)) then\n"
        "            YY = YY + 2*SDFS%Dipo(iLineP)/SDFS%Dipo(iLine)* WW0(iLineP,iLine) &\n"
        "              /(SDFS%modSigLines(iLine) - SDFS%modSigLines(iLineP))\n"
        "          endif\n"
        "        end do\n"
        "        SDFS%YT(iLine) = P*YY\n"
        "      end do\n\n"
        "    end subroutine ConvTP\n",
        "      ! Computation of the first order line-coupling coefficients\n"
        "      do iLine = 1, SDFS%nLines\n"
        "        YY=0.D0\n"
        "        do iLineP = 1, SDFS%nLines\n"
        "          if (iLine.ne.iLineP.and.SDFS%modSigLines(iLine).ne.SDFS%modSigLines(iLineP)) then\n"
        "            YY = YY + 2*SDFS%Dipo(iLineP)/SDFS%Dipo(iLine)* WW0(iLineP,iLine) &\n"
        "              /(SDFS%modSigLines(iLine) - SDFS%modSigLines(iLineP))\n"
        "          endif\n"
        "        end do\n"
        "        SDFS%YT(iLine) = P*YY\n"
        "      end do\n\n"
        "      call o2a_trace_convtp_state(T, P, SigMoy, SDFS%nLines, SDFS%sigLines, SDFS%PopuT, SDFS%Dipo, SDFS%modSigLines, SDFS%HWT, SDFS%YT)\n\n"
        "    end subroutine ConvTP\n",
        path,
    )
    text = replace_once(
        text,
        "      integer :: status, indexMinloc(1)\n"
        "      integer :: startSig, endSig\n",
        "      integer :: status, indexMinloc(1)\n"
        "      integer :: startSig, endSig\n"
        "      integer :: trace_index, trace_match_count\n"
        "      integer :: trace_wave_index(16)\n",
        path,
    )
    text = replace_once(
        text,
        "      waveNumber(:) = 1.0d7 / wavel(:)\n\n"
        "      do iso= 1, hitranS%nISO\n",
        "      waveNumber(:) = 1.0d7 / wavel(:)\n"
        "      trace_match_count = o2a_trace_wavelength_count_value()\n"
        "      do trace_index = 1, trace_match_count\n"
        "        indexMinloc = minloc(abs(wavel(:) - o2a_trace_wavelength_nm_value(trace_index)))\n"
        "        trace_wave_index(trace_index) = indexMinloc(1)\n"
        "      end do\n\n"
        "      do iso= 1, hitranS%nISO\n",
        path,
    )
    text = replace_once(
        text,
        "      do iLine = 1, nLines\n"
        "        HWT  = hitranS%gam(iLine) * (T0/T)**hitranS%bet(iLine)\n"
        "        Lsig = hitranS%sig(iLine)+ hitranS%delt(iLine) * P\n"
        "! JdH turn off pressure shift\n"
        "!       Lsig = hitranS%sig(iLine)\n"
        "        LS   = hitranS%S(iLine) * rapQ(hitranS%isotope(iLine)) &\n"
        "              * exp(hc_kB * hitranS%E(iLine) * (1/T0-1/T) ) / Lsig\n"
        "        LS   = LS * 0.1013d0 / k_Boltzmann / T &\n"
        "              /( 1.0d0 - exp( -hc_kB * Lsig /T0 ) )\n"
        "        indexMinloc = minloc(abs(waveNumber(:) - Lsig - cutoff))\n"
        "        startSig    = indexMinloc(1)\n"
        "        indexMinloc = minloc(abs(waveNumber(:) - Lsig + cutoff))\n"
        "        endSig   = indexMinloc(1)\n"
        "        GamD    = DopplerWidth(T, Lsig, hitranS%molWeight(hitranS%isotope(iLine)))\n"
        "        Cte     = sqrt(log(2.0d0))/GamD\n"
        "        Cte1    = Cte/sqrt(pi)\n"
        "        do iSig = startSig, endSig\n"
        "          SigC = waveNumber(iSig)\n"
        "          Cte2=SigC*(1.0d0-exp(-hc_kB*SigC/T))\n"
        "          ! Complex Probability Function for the \"Real\" Q-Lines\n"
        "          XX = ( LSig - SigC ) * Cte\n"
        "          YY = HWT * P * Cte\n"
        "          Call CPF(errS, XX,YY,WR,WI)\n"
        "          if (errorCheck(errS)) return\n"
        "          ! Voigt absorption coefficient\n"
        "          aa = Cte1 * P * LS * WR * Cte2               ! aa is the volume absorption coefficient\n"
        "                                                       ! for a volume mixing ratio of 1.0\n"
        "          aa = aa * T * 1.380658d-19 / P / 1013.25d0   ! aa is now the absorption cross section in cm2/molecule\n"
        "          absXsec(iSig) = absXsec(iSig) + aa\n"
        "        end do ! iSig\n"
        "      end do ! iLine\n\n"
        "    end subroutine CalculatAbsXsec\n",
        "      do iLine = 1, nLines\n"
        "        HWT  = hitranS%gam(iLine) * (T0/T)**hitranS%bet(iLine)\n"
        "        Lsig = hitranS%sig(iLine)+ hitranS%delt(iLine) * P\n"
        "! JdH turn off pressure shift\n"
        "!       Lsig = hitranS%sig(iLine)\n"
        "        LS   = hitranS%S(iLine) * rapQ(hitranS%isotope(iLine)) &\n"
        "              * exp(hc_kB * hitranS%E(iLine) * (1/T0-1/T) ) / Lsig\n"
        "        LS   = LS * 0.1013d0 / k_Boltzmann / T &\n"
        "              /( 1.0d0 - exp( -hc_kB * Lsig /T0 ) )\n"
        "        indexMinloc = minloc(abs(waveNumber(:) - Lsig - cutoff))\n"
        "        startSig    = indexMinloc(1)\n"
        "        indexMinloc = minloc(abs(waveNumber(:) - Lsig + cutoff))\n"
        "        endSig   = indexMinloc(1)\n"
        "        GamD    = DopplerWidth(T, Lsig, hitranS%molWeight(hitranS%isotope(iLine)))\n"
        "        Cte     = sqrt(log(2.0d0))/GamD\n"
        "        Cte1    = Cte/sqrt(pi)\n"
        "        do iSig = startSig, endSig\n"
        "          SigC = waveNumber(iSig)\n"
        "          Cte2=SigC*(1.0d0-exp(-hc_kB*SigC/T))\n"
        "          ! Complex Probability Function for the \"Real\" Q-Lines\n"
        "          XX = ( LSig - SigC ) * Cte\n"
        "          YY = HWT * P * Cte\n"
        "          Call CPF(errS, XX,YY,WR,WI)\n"
        "          if (errorCheck(errS)) return\n"
        "          ! Voigt absorption coefficient\n"
        "          aa = Cte1 * P * LS * WR * Cte2               ! aa is the volume absorption coefficient\n"
        "                                                       ! for a volume mixing ratio of 1.0\n"
        "          aa = aa * T * 1.380658d-19 / P / 1013.25d0   ! aa is now the absorption cross section in cm2/molecule\n"
        "          absXsec(iSig) = absXsec(iSig) + aa\n"
        "          do trace_index = 1, trace_match_count\n"
        "            if (iSig /= trace_wave_index(trace_index)) cycle\n"
        "            call o2a_trace_weak_line_contributor(T, P, o2a_trace_wavelength_nm_value(trace_index), wavel(iSig), iLine, hitranS%gasIndex, hitranS%isotope(iLine), hitranS%sig(iLine), Lsig, hitranS%S(iLine), hitranS%gam(iLine), hitranS%bet(iLine), hitranS%E(iLine), hitranS%delt(iLine), aa)\n"
        "          end do\n"
        "        end do ! iSig\n"
        "      end do ! iLine\n\n"
        "      call o2a_trace_weak_spectroscopy(T, P, size(wavel), wavel, absXsec)\n\n"
        "    end subroutine CalculatAbsXsec\n",
        path,
    )
    text = replace_once(
        text,
        "       nO2 = 1013.25 * P / T / 1.380658d-19  ! in molecules cm-3; assumed vmr = 1.0\n"
        "       Xsec(:)    =  abs_no_LM(:) / nO2\n"
        "       Xsec_LM(:) = ( abs_with_LM(:) - abs_no_LM(:) ) / nO2\n\n"
        "    end subroutine CalculateLineMixingXsec\n",
        "       nO2 = 1013.25 * P / T / 1.380658d-19  ! in molecules cm-3; assumed vmr = 1.0\n"
        "       Xsec(:)    =  abs_no_LM(:) / nO2\n"
        "       Xsec_LM(:) = ( abs_with_LM(:) - abs_no_LM(:) ) / nO2\n\n"
        "       call o2a_trace_strong_spectroscopy(T, P, size(waveNumbers), waveNumbers, Xsec, Xsec_LM)\n\n"
        "    end subroutine CalculateLineMixingXsec\n",
        path,
    )
    path.write_text(text, encoding="utf-8")


def patch_disamar_module(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "  use ramansspecs,              only: NumberRamanLines, RamanLinesScatWavel\n",
        "  use ramansspecs,              only: NumberRamanLines, RamanLinesScatWavel\n"
        "  use o2aFunctionTraceModule,   only: o2a_trace_store_intervals\n",
        path,
    )
    text = replace_once(
        text,
        "     real(8), allocatable :: wavelBand(:)        ! (nwavel) full band - not accounting for excluded parts\n"
        "     real(8), allocatable :: wavelBandWeight(:)  ! (nwavel) weights for full band - not accounting for excluded parts\n\n"
        "     integer              :: iwave, nlines, iinterval, index, ipair\n"
        "     integer              :: iGauss, nGauss, nGaussMax, nGaussMin\n"
        "     integer              :: iTrace\n",
        "     real(8), allocatable :: wavelBand(:)        ! (nwavel) full band - not accounting for excluded parts\n"
        "     real(8), allocatable :: wavelBandWeight(:)  ! (nwavel) weights for full band - not accounting for excluded parts\n"
        "     logical, allocatable :: intervalIsStrong(:)\n"
        "     real(8), allocatable :: intervalSourceCenter(:)\n"
        "     integer, allocatable :: intervalDivisionCount(:)\n\n"
        "     integer              :: iwave, nlines, iinterval, index, ipair\n"
        "     integer              :: iGauss, nGauss, nGaussMax, nGaussMin\n"
        "     integer              :: iTrace\n"
        "     logical              :: intervalAddedFromStrong\n"
        "     real(8)              :: intervalStrongCenter\n",
        path,
    )
    text = replace_once(
        text,
        "     allocate ( intervalBoundaries(0:nlines), STAT = allocStatus )\n"
        "     if ( allocStatus /= 0 ) then\n"
        "       call logDebug('FATAL ERROR: allocation failed')\n"
        "       call logDebug('for intervalBoundaries')\n"
        "       call logDebug('in subroutine setupHRWavelengthGrid')\n"
        "       call logDebug('in program DISAMAR - file main_DISAMAR.f90')\n"
        "       call mystop(errS, 'stopped because allocation failed')\n"
        "       if (errorCheck(errS)) return\n"
        "     end if\n\n"
        "     ! fill values\n",
        "     allocate ( intervalBoundaries(0:nlines), STAT = allocStatus )\n"
        "     if ( allocStatus /= 0 ) then\n"
        "       call logDebug('FATAL ERROR: allocation failed')\n"
        "       call logDebug('for intervalBoundaries')\n"
        "       call logDebug('in subroutine setupHRWavelengthGrid')\n"
        "       call logDebug('in program DISAMAR - file main_DISAMAR.f90')\n"
        "       call mystop(errS, 'stopped because allocation failed')\n"
        "       if (errorCheck(errS)) return\n"
        "     end if\n"
        "     allocStatus = 0\n"
        "     allocate ( intervalIsStrong(1:nlines), intervalSourceCenter(1:nlines), intervalDivisionCount(1:nlines), STAT = allocStatus )\n"
        "     if ( allocStatus /= 0 ) then\n"
        "       call logDebug('FATAL ERROR: allocation failed')\n"
        "       call logDebug('for interval trace arrays')\n"
        "       call logDebug('in subroutine setupHRWavelengthGrid')\n"
        "       call logDebug('in program DISAMAR - file main_DISAMAR.f90')\n"
        "       call mystop(errS, 'stopped because allocation failed')\n"
        "       if (errorCheck(errS)) return\n"
        "     end if\n"
        "     intervalIsStrong(:) = .false.\n"
        "     intervalSourceCenter(:) = 0.0d0\n"
        "     intervalDivisionCount(:) = 0\n\n"
        "     ! fill values\n",
        path,
    )
    text = replace_once(
        text,
        "     do\n"
        "       nlines = nlines + 1\n"
        "       newWavel = wavel + FWHM\n"
        "       do iTrace = 1, nTrace\n"
        "         do iwave = 1,  boundariesTraceS(iTrace)%numBoundaries\n"
        "           if ( ( boundariesTraceS(iTrace)%boundaries(iwave) > wavel    ) .and.  &\n"
        "                ( boundariesTraceS(iTrace)%boundaries(iwave) < newWavel ) ) then\n"
        "              newWavel = boundariesTraceS(iTrace)%boundaries(iwave)\n"
        "           end if\n"
        "         end do ! iwave\n"
        "       end do ! iTrace\n"
        "       wavel = newWavel\n"
        "       intervalBoundaries(nlines) = wavel\n"
        "       if ( wavel > waveEnd ) exit\n"
        "     end do\n",
        "     do\n"
        "       nlines = nlines + 1\n"
        "       intervalAddedFromStrong = .false.\n"
        "       intervalStrongCenter = 0.0d0\n"
        "       newWavel = wavel + FWHM\n"
        "       do iTrace = 1, nTrace\n"
        "         do iwave = 1,  boundariesTraceS(iTrace)%numBoundaries\n"
        "           if ( ( boundariesTraceS(iTrace)%boundaries(iwave) > wavel    ) .and.  &\n"
        "                ( boundariesTraceS(iTrace)%boundaries(iwave) < newWavel ) ) then\n"
        "              newWavel = boundariesTraceS(iTrace)%boundaries(iwave)\n"
        "              intervalAddedFromStrong = .true.\n"
        "              intervalStrongCenter = boundariesTraceS(iTrace)%boundaries(iwave)\n"
        "           end if\n"
        "         end do ! iwave\n"
        "       end do ! iTrace\n"
        "       wavel = newWavel\n"
        "       intervalBoundaries(nlines) = wavel\n"
        "       intervalIsStrong(nlines) = intervalAddedFromStrong\n"
        "       intervalSourceCenter(nlines) = intervalStrongCenter\n"
        "       if ( wavel > waveEnd ) exit\n"
        "     end do\n",
        path,
    )
    text = replace_once(
        text,
        "       nGauss = max( nGaussMin, nint( nGaussMax * dw / maxInterval ) )\n"
        "       if (nGauss >  nGaussMax ) nGauss =  nGaussMax\n"
        "       do iGauss = 1, nGauss\n"
        "         index = index + 1\n"
        "       end do\n",
        "       nGauss = max( nGaussMin, nint( nGaussMax * dw / maxInterval ) )\n"
        "       if (nGauss >  nGaussMax ) nGauss =  nGaussMax\n"
        "       intervalDivisionCount(iinterval) = nGauss\n"
        "       do iGauss = 1, nGauss\n"
        "         index = index + 1\n"
        "       end do\n",
        path,
    )
    text = replace_once(
        text,
        "     if ( verbose ) then\n",
        "     call o2a_trace_store_intervals(size(intervalBoundaries) - 1, intervalBoundaries, intervalIsStrong, intervalSourceCenter, intervalDivisionCount)\n\n"
        "     if ( verbose ) then\n",
        path,
    )
    text = replace_once(
        text,
        "     deallocate( intervalBoundaries, x0, w0, wavelBand, wavelBandWeight, STAT = deallocStatus )\n",
        "     deallocate( intervalBoundaries, x0, w0, wavelBand, wavelBandWeight, intervalIsStrong, intervalSourceCenter, intervalDivisionCount, STAT = deallocStatus )\n",
        path,
    )
    path.write_text(text, encoding="utf-8")


def patch_radiance_module(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "  use ramansspecs,          only: ConvoluteSpecRaman, ConvoluteSpecRamanMS, TotalRamanXsecScatWavel, RayXsec\n",
        "  use ramansspecs,          only: ConvoluteSpecRaman, ConvoluteSpecRamanMS, TotalRamanXsecScatWavel, RayXsec\n"
        "  use o2aFunctionTraceModule, only: o2a_trace_emit_kernel_and_transport, o2a_trace_transport_summary, &\n"
        "    o2a_trace_irradiance_contribution\n",
        path,
    )
    text = replace_once(
        text,
        "        do index = startIndex, endIndex\n"
        "          ! multiply with gaussian weights for integration\n"
        "          slitfunctionValues(index) = wavelHRS%weight(index) * slitfunctionValues(index)\n"
        "          irradiance = irradiance + slitfunctionValues(index) * solarIrradianceS%solIrrHR(index)\n"
        "        end do\n"
        "        solarIrradianceS%solIrr(iwave) = irradiance\n",
        "        do index = startIndex, endIndex\n"
        "          ! multiply with gaussian weights for integration\n"
        "          slitfunctionValues(index) = wavelHRS%weight(index) * slitfunctionValues(index)\n"
        "          irradiance = irradiance + slitfunctionValues(index) * solarIrradianceS%solIrrHR(index)\n"
        "          call o2a_trace_irradiance_contribution(wavelInstrS%wavel(iwave), index - startIndex, wavelHRS%wavel(index), &\n"
        "            slitfunctionValues(index), solarIrradianceS%solIrrHR(index), &\n"
        "            slitfunctionValues(index) * solarIrradianceS%solIrrHR(index), irradiance)\n"
        "        end do\n"
        "        solarIrradianceS%solIrr(iwave) = irradiance\n",
        path,
    )
    text = replace_once(
        text,
        "        do index = startIndex, endIndex\n"
        "          slitfunctionValues(index) = wavelHRS%weight(index) * slitfunctionValues(index)\n"
        "        end do\n"
        "        do iSV = 1, dimSV\n",
        "        do index = startIndex, endIndex\n"
        "          slitfunctionValues(index) = wavelHRS%weight(index) * slitfunctionValues(index)\n"
        "        end do\n"
        "        call o2a_trace_emit_kernel_and_transport(wavelInstrS%wavel(iwave), startIndex, endIndex, wavelHRS%wavel, slitfunctionValues, earthRadianceS%rad_HR(1,:), solarIrradianceS%solIrrHR)\n"
        "        do iSV = 1, dimSV\n",
        path,
    )
    text = replace_once(
        text,
        "        retrS%reflMeas(index)  = earthRadianceSimS  (iband)%rad_meas(1,iwave) &\n"
        "                               / solarIrradianceSimS(iband)%solIrrMeas(iwave)\n"
        "        retrS%reflNoiseError(index) = retrS%reflMeas(index) * sqrt(  &\n",
        "        retrS%reflMeas(index)  = earthRadianceSimS  (iband)%rad_meas(1,iwave) &\n"
        "                               / solarIrradianceSimS(iband)%solIrrMeas(iwave)\n"
        "        call o2a_trace_transport_summary(wavelInstrSimS(iband)%wavel(iwave), earthRadianceSimS(iband)%rad_meas(1,iwave), solarIrradianceSimS(iband)%solIrrMeas(iwave), retrS%reflMeas(index))\n"
        "        retrS%reflNoiseError(index) = retrS%reflMeas(index) * sqrt(  &\n",
        path,
    )
    path.write_text(text, encoding="utf-8")


def patch_labos_module(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "  use mathTools,   only : GaussDivPoints, LU_decomposition, locate, solve_lin_system_LU_based\n",
        "  use mathTools,   only : GaussDivPoints, LU_decomposition, locate, solve_lin_system_LU_based\n"
        "  use o2aFunctionTraceModule, only: o2a_trace_fourier_term, o2a_trace_transport_layer, &\n"
        "    o2a_trace_transport_source_term, o2a_trace_transport_attenuation_term, &\n"
        "    o2a_trace_transport_pseudo_spherical_sample, o2a_trace_transport_order_surface, &\n"
        "    o2a_trace_transport_rt_probe, o2a_trace_transport_rt_build_probe, o2a_trace_transport_rt_double_probe, &\n"
        "    o2a_trace_transport_zplus_term, &\n"
        "    o2a_trace_transport_source_angle_component, o2a_trace_set_fourier_index\n",
        path,
    )
    text = replace_once(
        text,
        "      integer    :: ilFrom, ilTo, ilayer, imu, index\n",
        "      integer    :: ilFrom, ilTo, ilayer, imu, index\n"
        "      integer    :: trace_sample_index\n",
        path,
    )
    text = replace_once(
        text,
        "      real(8) :: sumIntField(nmuextra), sumIntField_prev(nmuextra)\n"
        "      real(8) :: eigenvalue(nmuextra)\n"
        "      real(8) :: maxValue\n",
        "      real(8) :: sumIntField(nmuextra), sumIntField_prev(nmuextra)\n"
        "      real(8) :: eigenvalue(nmuextra)\n"
        "      real(8) :: maxValue\n"
        "      integer :: trace_surface_ind\n",
        path,
    )
    text = replace_once(
        text,
        "      real(8) :: beta_eff(0:maxExpCoef), max_beta_eff\n\n"
        "      real(8) :: E(dimSV_fc*nmutot)\n",
        "      real(8) :: beta_eff(0:maxExpCoef), max_beta_eff\n"
        "      real(8) :: trace_b_start, trace_e_row, trace_e_col, trace_eet, trace_single_t\n"
        "      real(8) :: trace_zplus_cumulative, trace_zplus_contribution\n"
        "      integer :: trace_row_ind, trace_col_ind\n\n"
        "      real(8) :: E(dimSV_fc*nmutot)\n",
        path,
    )
    text = replace_once(
        text,
        "          doubling = .false.\n\n"
        "          ! determine effective expansion coefficient for the current Fourier term\n",
        "          doubling = .false.\n"
        "          bstart = b\n"
        "          ndouble = 0\n\n"
        "          ! determine effective expansion coefficient for the current Fourier term\n",
        path,
    )
    text = replace_once(
        text,
        "            R = Rsingle(dimSV_fc, nmutot, a, E, Zmin, DmuPlus)\n\n"
        "            T = Tsingle(dimSV_fc, nmutot, a, bstart, E, Zplus, DmuMin, geometryS)\n",
        "            trace_b_start = bstart\n"
        "            trace_row_ind = 1 + min(4, nGauss - 1) * dimSV_fc\n"
        "            trace_col_ind = dimSV_fc * nGauss + 1 + dimSV_fc\n"
        "            trace_e_row = E(trace_row_ind)\n"
        "            trace_e_col = E(trace_col_ind)\n"
        "            if (abs(geometryS%u(1 + min(4, nGauss - 1)) - geometryS%u(nGauss + 2)) < 1.0d-6) then\n"
        "              trace_eet = trace_b_start * trace_e_row\n"
        "            else\n"
        "              trace_eet = trace_e_row - trace_e_col\n"
        "            end if\n"
        "            R = Rsingle(dimSV_fc, nmutot, a, E, Zmin, DmuPlus)\n\n"
        "            T = Tsingle(dimSV_fc, nmutot, a, bstart, E, Zplus, DmuMin, geometryS)\n",
        path,
    )
    text = replace_once(
        text,
        "            R = Rsingle(dimSV_fc, nmutot, a, E, Zmin, DmuPlus)\n"
        "            T = Tsingle(dimSV_fc, nmutot, a, b, E, Zplus, DmuMin, geometryS )\n",
        "            trace_b_start = b\n"
        "            trace_row_ind = 1 + min(4, nGauss - 1) * dimSV_fc\n"
        "            trace_col_ind = dimSV_fc * nGauss + 1 + dimSV_fc\n"
        "            trace_e_row = E(trace_row_ind)\n"
        "            trace_e_col = E(trace_col_ind)\n"
        "            if (abs(geometryS%u(1 + min(4, nGauss - 1)) - geometryS%u(nGauss + 2)) < 1.0d-6) then\n"
        "              trace_eet = trace_b_start * trace_e_row\n"
        "            else\n"
        "              trace_eet = trace_e_row - trace_e_col\n"
        "            end if\n"
        "            R = Rsingle(dimSV_fc, nmutot, a, E, Zmin, DmuPlus)\n"
        "            T = Tsingle(dimSV_fc, nmutot, a, b, E, Zplus, DmuMin, geometryS )\n",
        path,
    )
    text = replace_once(
        text,
        "          end if ! doubling\n\n"
        "          ! fill data structure\n",
        "          end if ! doubling\n\n"
        "          if (iFourier == 0 .and. ilayer == min(15, RTMnlayer)) then\n"
        "            trace_row_ind = 1 + min(4, nGauss - 1) * dimSV_fc\n"
        "            trace_col_ind = dimSV_fc * nGauss + 1 + dimSV_fc\n"
        "            trace_zplus_cumulative = 0.0d0\n"
        "            do iCoef = iFourier, optPropRTMGridS%maxExpCoefLay(ilayer)\n"
        "              trace_zplus_contribution = optPropRTMGridS%phasefCoefLay(1,1,iCoef,ilayer) &\n"
        "                * fcCoef(iCoef)%PlmPlus(trace_row_ind) * fcCoef(iCoef)%PlmPlus(trace_col_ind)\n"
        "              trace_zplus_cumulative = trace_zplus_cumulative + trace_zplus_contribution\n"
        "              call o2a_trace_transport_zplus_term(iFourier, min(14, RTMnlayer - 1), min(4, nGauss - 1), 1, &\n"
        "                iCoef, optPropRTMGridS%phasefCoefLay(1,1,iCoef,ilayer), &\n"
        "                fcCoef(iCoef)%PlmPlus(trace_row_ind), fcCoef(iCoef)%PlmPlus(trace_col_ind), &\n"
        "                trace_zplus_contribution, trace_zplus_cumulative)\n"
        "            end do\n"
        "            trace_single_t = a * Zplus(trace_row_ind, trace_col_ind) * trace_eet * DmuMin(1 + min(4, nGauss - 1), nGauss + 2)\n"
        "            call o2a_trace_transport_rt_build_probe(iFourier, min(14, RTMnlayer - 1), min(4, nGauss - 1), 1, &\n"
        "              optPropRTMGridS%maxExpCoefLay(ilayer), max_beta_eff, aeff, merge(1, 0, doubling), trace_b_start, ndouble, &\n"
        "              Zplus(trace_row_ind, trace_col_ind), trace_e_row, trace_e_col, trace_eet, &\n"
        "              DmuMin(1 + min(4, nGauss - 1), nGauss + 2), &\n"
        "              trace_single_t, T(trace_row_ind, trace_col_ind))\n"
        "          end if\n\n"
        "          ! fill data structure\n",
        path,
    )
    text = replace_once(
        text,
        "            call double(errS, ndouble, dimSV_fc, nmutot, nGauss, controlS%thresholdMul, geometryS, &\n"
        "                        bstart, E, R, T)\n",
        "            call double(errS, ndouble, dimSV_fc, nmutot, nGauss, controlS%thresholdMul, geometryS, &\n"
        "                        bstart, E, R, T, iFourier, ilayer)\n",
        path,
    )
    text = replace_once(
        text,
        "    subroutine double(errS, ndouble, dimSV_fc, nmutot, nGauss, thresholdMul, geometryS, b, E, R, T)\n",
        "    subroutine double(errS, ndouble, dimSV_fc, nmutot, nGauss, thresholdMul, geometryS, b, E, R, T, iFourierTrace, ilayerTrace)\n",
        path,
    )
    text = replace_once(
        text,
        "      integer,            intent(in)     :: dimSV_fc, nmutot, nGauss\n",
        "      integer,            intent(in)     :: dimSV_fc, nmutot, nGauss\n"
        "      integer,            intent(in)     :: iFourierTrace, ilayerTrace\n",
        path,
    )
    text = replace_once(
        text,
        "      integer :: idouble, imu, iSV, ind\n",
        "      integer :: idouble, imu, iSV, ind, trace_row_ind, trace_col_ind\n"
        "      real(8) :: trace_b_before, trace_t_before\n",
        path,
    )
    text = replace_once(
        text,
        "      do idouble = 1, ndouble \n"
        "        Rst  = transform_top_bottom(dimSV_fc, nmutot, R)\n",
        "      trace_row_ind = 1 + min(4, nGauss - 1) * dimSV_fc\n"
        "      trace_col_ind = dimSV_fc * nGauss + 1 + dimSV_fc\n"
        "      do idouble = 1, ndouble \n"
        "        trace_b_before = b\n"
        "        trace_t_before = T(trace_row_ind, trace_col_ind)\n"
        "        Rst  = transform_top_bottom(dimSV_fc, nmutot, R)\n",
        path,
    )
    text = replace_once(
        text,
        "        T    = esmul(dimSV_fc*nmutot, E, D) + semul(dimSV_fc*nmutot, T, E) &\n"
        "             + smul(dimSV_fc*nmutot, dimSV_fc*nGauss, thresholdMul, T, D)\n",
        "        T    = esmul(dimSV_fc*nmutot, E, D) + semul(dimSV_fc*nmutot, T, E) &\n"
        "             + smul(dimSV_fc*nmutot, dimSV_fc*nGauss, thresholdMul, T, D)\n"
        "        if (iFourierTrace == 0 .and. ilayerTrace == 15) then\n"
        "          call o2a_trace_transport_rt_double_probe(iFourierTrace, min(14, ilayerTrace - 1), idouble, &\n"
        "            trace_b_before, Q(trace_row_ind, trace_col_ind), D(trace_row_ind, trace_col_ind), &\n"
        "            U(trace_row_ind, trace_col_ind), trace_t_before, T(trace_row_ind, trace_col_ind))\n"
        "        end if\n",
        path,
    )
    text = replace_once(
        text,
        "      integer :: ilevel, maxExpCoefLevel\n"
        "      integer :: is, imu, imu0, iSV, jSV, ind, ind0\n"
        "      real(8) :: sumRefl(dimSV_fc)\n",
        "      integer :: ilevel, maxExpCoefLevel\n"
        "      integer :: is, imu, imu0, iSV, jSV, ind, ind0\n"
        "      real(8) :: sumRefl(dimSV_fc)\n"
        "      real(8) :: trace_angle_contribution\n",
        path,
    )
    text = replace_once(
        text,
        "        numerator = optPropRTMGridS%RTMweightSub * x &\n"
        "                  * ( optPropRTMGridS%kextSubGas + optPropRTMGridS%kextSubAer + optPropRTMGridS%kextSubCld )\n\n"
        "        ! slant optical distances for the levels with standard geometry at level ilTo\n",
        "        numerator = optPropRTMGridS%RTMweightSub * x &\n"
        "                  * ( optPropRTMGridS%kextSubGas + optPropRTMGridS%kextSubAer + optPropRTMGridS%kextSubCld )\n\n"
        "        trace_sample_index = 0\n"
        "        do index = 0, optPropRTMGridS%RTMnlayerSub\n"
        "          if (optPropRTMGridS%RTMweightSub(index) > 0.0d0) then\n"
        "            call o2a_trace_transport_pseudo_spherical_sample(trace_sample_index, optPropRTMGridS%RTMaltitudeSub(index), &\n"
        "              optPropRTMGridS%RTMweightSub(index), optPropRTMGridS%RTMweightSub(index) &\n"
        "              * (optPropRTMGridS%kextSubGas(index) + optPropRTMGridS%kextSubAer(index) + optPropRTMGridS%kextSubCld(index)), &\n"
        "              numerator(index), 1)\n"
        "            trace_sample_index = trace_sample_index + 1\n"
        "          end if\n"
        "        end do\n\n"
        "        ! slant optical distances for the levels with standard geometry at level ilTo\n",
        path,
    )
    text = replace_once(
        text,
        "        do imu = 1, nmutot\n"
        "          sin2theta = 1.0d0 - u(imu)**2\n"
        "          do ilTo = RTMnlayer - 1, 0, -1\n",
        "        do imu = 1, nmutot\n"
        "          sin2theta = 1.0d0 - u(imu)**2\n"
        "          if (imu == geometryS%nGauss + 1) &\n"
        "            call o2a_trace_transport_attenuation_term('view', imu - 1, RTMnlayer, 0.0d0, atten(imu, RTMnlayer, RTMnlayer), 1)\n"
        "          if (imu == geometryS%nGauss + 2) &\n"
        "            call o2a_trace_transport_attenuation_term('solar', imu - 1, RTMnlayer, 0.0d0, atten(imu, RTMnlayer, RTMnlayer), 1)\n"
        "          do ilTo = RTMnlayer - 1, 0, -1\n",
        path,
    )
    text = replace_once(
        text,
        "            atten(imu, RTMnlayer, ilTo) = exp(-sumkext)\n"
        "          end do ! ilTo loop\n",
        "            atten(imu, RTMnlayer, ilTo) = exp(-sumkext)\n"
        "            if (imu == geometryS%nGauss + 1) &\n"
        "              call o2a_trace_transport_attenuation_term('view', imu - 1, ilTo, sumkext, atten(imu, RTMnlayer, ilTo), 1)\n"
        "            if (imu == geometryS%nGauss + 2) &\n"
        "              call o2a_trace_transport_attenuation_term('solar', imu - 1, ilTo, sumkext, atten(imu, RTMnlayer, ilTo), 1)\n"
        "          end do ! ilTo loop\n",
        path,
    )
    text = replace_once(
        text,
        "      if ( maxValue  < controlS%thresholdConv_first) then\n\n"
        "        if ( verbose )  write(intermediateFileUnit,'(A, I4)') 'numorders= ', numorders\n\n"
        "      else ! higher orders of scattering\n",
        "      trace_surface_ind = 1 + nGauss * dimSV_fc\n"
        "      if ( maxValue  < controlS%thresholdConv_first) then\n\n"
        "        call o2a_trace_transport_order_surface(0, numorders, 'first_converged', maxValue, &\n"
        "          UDorde_fc(startLevel)%U(trace_surface_ind, 2), UD_fc(startLevel)%U(trace_surface_ind, 2), &\n"
        "          UDorde_fc(startLevel)%D(trace_surface_ind, 2), UD_fc(startLevel)%E(trace_surface_ind), &\n"
        "          min(14,endLevel), 4, UDorde_fc(min(14,endLevel))%D(1 + 4*dimSV_fc, 2), &\n"
        "          UD_fc(min(14,endLevel))%D(1 + 4*dimSV_fc, 2), UDorde_fc(min(14,endLevel))%U(1 + 4*dimSV_fc, 2), &\n"
        "          UD_fc(min(14,endLevel))%U(1 + 4*dimSV_fc, 2))\n"
        "        if ( verbose )  write(intermediateFileUnit,'(A, I4)') 'numorders= ', numorders\n\n"
        "      else ! higher orders of scattering\n"
        "        call o2a_trace_transport_order_surface(0, numorders, 'accumulated', maxValue, &\n"
        "          UDorde_fc(startLevel)%U(trace_surface_ind, 2), UD_fc(startLevel)%U(trace_surface_ind, 2), &\n"
        "          UDorde_fc(startLevel)%D(trace_surface_ind, 2), UD_fc(startLevel)%E(trace_surface_ind), &\n"
        "          min(14,endLevel), 4, UDorde_fc(min(14,endLevel))%D(1 + 4*dimSV_fc, 2), &\n"
        "          UD_fc(min(14,endLevel))%D(1 + 4*dimSV_fc, 2), UDorde_fc(min(14,endLevel))%U(1 + 4*dimSV_fc, 2), &\n"
        "          UD_fc(min(14,endLevel))%U(1 + 4*dimSV_fc, 2))\n",
        path,
    )
    text = replace_once(
        text,
        "          if ( (maxValue  < controlS%thresholdConv_mult) .or. (numorders == numOrdersMax) ) then\n"
        "             if ( verbose )  write(intermediateFileUnit,*) 'numorders= ', numorders\n"
        "            exit ! exit loop over orders of scattering\n"
        "          end if\n",
        "          if ( (maxValue  < controlS%thresholdConv_mult) .or. (numorders == numOrdersMax) ) then\n"
        "            if (numorders == numOrdersMax) then\n"
        "              call o2a_trace_transport_order_surface(0, numorders, 'max_orders', maxValue, &\n"
        "                UDorde_fc(startLevel)%U(trace_surface_ind, 2), UD_fc(startLevel)%U(trace_surface_ind, 2), &\n"
        "                UDorde_fc(startLevel)%D(trace_surface_ind, 2), UD_fc(startLevel)%E(trace_surface_ind), &\n"
        "                min(14,endLevel), 4, UDorde_fc(min(14,endLevel))%D(1 + 4*dimSV_fc, 2), &\n"
        "                UD_fc(min(14,endLevel))%D(1 + 4*dimSV_fc, 2), UDorde_fc(min(14,endLevel))%U(1 + 4*dimSV_fc, 2), &\n"
        "                UD_fc(min(14,endLevel))%U(1 + 4*dimSV_fc, 2))\n"
        "            else\n"
        "              call o2a_trace_transport_order_surface(0, numorders, 'multiple_converged', maxValue, &\n"
        "                UDorde_fc(startLevel)%U(trace_surface_ind, 2), UD_fc(startLevel)%U(trace_surface_ind, 2), &\n"
        "                UDorde_fc(startLevel)%D(trace_surface_ind, 2), UD_fc(startLevel)%E(trace_surface_ind), &\n"
        "                min(14,endLevel), 4, UDorde_fc(min(14,endLevel))%D(1 + 4*dimSV_fc, 2), &\n"
        "                UD_fc(min(14,endLevel))%D(1 + 4*dimSV_fc, 2), UDorde_fc(min(14,endLevel))%U(1 + 4*dimSV_fc, 2), &\n"
        "                UD_fc(min(14,endLevel))%U(1 + 4*dimSV_fc, 2))\n"
        "            end if\n"
        "             if ( verbose )  write(intermediateFileUnit,*) 'numorders= ', numorders\n"
        "            exit ! exit loop over orders of scattering\n"
        "          end if\n",
        path,
    )
    text = replace_once(
        text,
        "              UDsumLocal_fc(ilevel)%D   = UDsumLocal_fc(ilevel)%D + UDLocal_fc(ilevel)%D\n"
        "            end do\n"
        "            \n"
        "          end if ! numorders == numOrdersMax\n",
        "              UDsumLocal_fc(ilevel)%D   = UDsumLocal_fc(ilevel)%D + UDLocal_fc(ilevel)%D\n"
        "            end do\n"
        "            call o2a_trace_transport_order_surface(0, numorders, 'accumulated', maxValue, &\n"
        "              UDorde_fc(startLevel)%U(trace_surface_ind, 2), UD_fc(startLevel)%U(trace_surface_ind, 2), &\n"
        "              UDorde_fc(startLevel)%D(trace_surface_ind, 2), UD_fc(startLevel)%E(trace_surface_ind), &\n"
        "              min(14,endLevel), 4, UDorde_fc(min(14,endLevel))%D(1 + 4*dimSV_fc, 2), &\n"
        "              UD_fc(min(14,endLevel))%D(1 + 4*dimSV_fc, 2), UDorde_fc(min(14,endLevel))%U(1 + 4*dimSV_fc, 2), &\n"
        "              UD_fc(min(14,endLevel))%U(1 + 4*dimSV_fc, 2))\n"
        "            \n"
        "          end if ! numorders == numOrdersMax\n",
        path,
    )
    text = replace_once(
        text,
        "      real(8) :: factor \n",
        "      real(8) :: factor \n"
        "      real(8) :: trace_surface_e_view\n"
        "      real(8) :: trace_surface_u_view_solar\n"
        "      real(8) :: trace_surface_refl\n",
        path,
    )
    text = replace_once(
        text,
        "        call CalcRTlayers(errS, fcCoef, iFourier, maxExpCoef, RTMnlevelCloud, RTMnlayer, dimSV, dimSV_fc, nmutot, &\n"
        "                          nGauss, controlS, geometryS, optPropRTMGridS, RT_fc)\n"
        "        if (errorCheck(errS)) return\n\n"
        "        call fillsurface(errS, iFourier, dimSV_fc, nmutot, albedo, geometryS, RT_fc(RTMnlevelCloud)%R,     &\n",
        "        call CalcRTlayers(errS, fcCoef, iFourier, maxExpCoef, RTMnlevelCloud, RTMnlayer, dimSV, dimSV_fc, nmutot, &\n"
        "                          nGauss, controlS, geometryS, optPropRTMGridS, RT_fc)\n"
        "        if (errorCheck(errS)) return\n\n"
        "        if (iFourier == 0) then\n"
        "          do ilevel = 1, RTMnlayer\n"
        "            call o2a_trace_transport_layer(ilevel - 1, optPropRTMGridS%opticalThicknLay(ilevel), &\n"
        "              optPropRTMGridS%opticalThicknLay(ilevel) * optPropRTMGridS%ssaLay(ilevel), optPropRTMGridS%ssaLay(ilevel), &\n"
        "              optPropRTMGridS%phasefCoefLay(1,1,0,ilevel), optPropRTMGridS%phasefCoefLay(1,1,1,ilevel), &\n"
        "              optPropRTMGridS%phasefCoefLay(1,1,2,ilevel), optPropRTMGridS%phasefCoefLay(1,1,3,ilevel), &\n"
        "              optPropRTMGridS%phasefCoefLay(1,1,10,ilevel), optPropRTMGridS%phasefCoefLay(1,1,20,ilevel), &\n"
        "              optPropRTMGridS%phasefCoefLay(1,1,39,ilevel))\n"
        "          end do\n"
        "          call o2a_trace_transport_rt_probe(iFourier, min(14, RTMnlayer - 1), min(4, nGauss - 1), 1, &\n"
        "            optPropRTMGridS%opticalThicknLay(min(15, RTMnlayer)), &\n"
        "            optPropRTMGridS%opticalThicknLay(min(15, RTMnlayer)) * optPropRTMGridS%ssaLay(min(15, RTMnlayer)), &\n"
        "            optPropRTMGridS%ssaLay(min(15, RTMnlayer)), &\n"
        "            RT_fc(min(15, RTMnlayer))%T(1 + min(4, nGauss - 1) * dimSV_fc, dimSV_fc * nGauss + 1 + dimSV_fc), &\n"
        "            atten(nGauss + 2, RTMnlayer, min(15, RTMnlayer)), &\n"
        "            RT_fc(min(15, RTMnlayer))%T(1 + min(4, nGauss - 1) * dimSV_fc, dimSV_fc * nGauss + 1 + dimSV_fc) &\n"
        "              * atten(nGauss + 2, RTMnlayer, min(15, RTMnlayer)))\n"
        "        end if\n\n"
        "        call fillsurface(errS, iFourier, dimSV_fc, nmutot, albedo, geometryS, RT_fc(RTMnlevelCloud)%R,     &\n",
        path,
    )
    text = replace_once(
        text,
        "          call ordersScat(errS, controlS, geometryS, numOrdersMax, RTMnlevelCloud, &\n"
        "                          RTMnlayer, atten, dimSV_fc, nmutot, nmuextra, nGauss,    &\n"
        "                          RT_fc, UDsumLocal_fc, UDLocal_fc, UDorde_fc, UD_fc)\n"
        "          if (errorCheck(errS)) return\n",
        "          call o2a_trace_set_fourier_index(iFourier)\n"
        "          call ordersScat(errS, controlS, geometryS, numOrdersMax, RTMnlevelCloud, &\n"
        "                          RTMnlayer, atten, dimSV_fc, nmutot, nmuextra, nGauss,    &\n"
        "                          RT_fc, UDsumLocal_fc, UDLocal_fc, UDorde_fc, UD_fc)\n"
        "          if (errorCheck(errS)) return\n",
        path,
    )
    text = replace_once(
        text,
        "          call ordersScat(errS, controlS, geometryS, numOrdersMax, RTMnlevelCloud, &\n"
        "                          RTMnlayer, atten, dimSV_fc, nmutot, nmuextra, nGauss,    &\n"
        "                          RT_fc, UDsumLocal_fc, UDLocal_fc, UDorde_fc, UD_fc)\n"
        "          if (errorCheck(errS)) return\n",
        "          call o2a_trace_set_fourier_index(iFourier)\n"
        "          call ordersScat(errS, controlS, geometryS, numOrdersMax, RTMnlevelCloud, &\n"
        "                          RTMnlayer, atten, dimSV_fc, nmutot, nmuextra, nGauss,    &\n"
        "                          RT_fc, UDsumLocal_fc, UDLocal_fc, UDorde_fc, UD_fc)\n"
        "          if (errorCheck(errS)) return\n",
        path,
    )
    text = replace_once(
        text,
        "        factor = 2.0d0\n"
        "        if (iFourier == 0) factor = 1.0d0\n\n\n"
        "        wfAlbedo               = wfAlbedo                + factor * wfAlbedo_fc                * cos_m_dphi\n",
        "        factor = 2.0d0\n"
        "        if (iFourier == 0) factor = 1.0d0\n\n"
        "        trace_surface_refl = 0.0d0\n"
        "        trace_surface_e_view = 0.0d0\n"
        "        trace_surface_u_view_solar = 0.0d0\n"
        "        if (iFourier == 0) then\n"
        "          trace_surface_e_view = UD_fc(RTMnlevelCloud)%E(1 + nGauss * dimSV_fc)\n"
        "          trace_surface_u_view_solar = UD_fc(RTMnlevelCloud)%U(1 + nGauss * dimSV_fc, 2)\n"
        "          trace_surface_refl = trace_surface_e_view * trace_surface_u_view_solar\n"
        "        end if\n"
        "        call o2a_trace_fourier_term(iFourier, refl_fc(1), trace_surface_refl, trace_surface_e_view, trace_surface_u_view_solar, factor * cos_m_dphi)\n\n"
        "        wfAlbedo               = wfAlbedo                + factor * wfAlbedo_fc                * cos_m_dphi\n",
        path,
    )
    text = replace_once(
        text,
        "              contribrefl_fc(iSV, ilevel) =  UD_fc(ilevel)%E(ind) * optPropRTMGridS%ksca(ilevel) &\n"
        "                                          * (PminED(iSV) + PplusstU(iSV))\n"
        "              ! integration\n"
        "              sumRefl(iSV) = sumRefl(iSV) + optPropRTMGridS%RTMweight(ilevel) * contribrefl_fc(iSV, ilevel)\n",
        "              if (iSV == 1 .and. iFourier == 0 .and. optPropRTMGridS%RTMweight(ilevel) > 0.0d0 .and. optPropRTMGridS%ksca(ilevel) > 0.0d0) then\n"
        "                do imu = 1, nGauss\n"
        "                  trace_angle_contribution = Pmin(ind, 1 + (imu - 1) * dimSV_fc) * UD_fc(ilevel)%D(1 + (imu - 1) * dimSV_fc, is)\n"
        "                  call o2a_trace_transport_source_angle_component(iFourier, ilevel, 'pmin_diffuse', imu - 1, &\n"
        "                    Pmin(ind, 1 + (imu - 1) * dimSV_fc), UD_fc(ilevel)%D(1 + (imu - 1) * dimSV_fc, is), &\n"
        "                    trace_angle_contribution, optPropRTMGridS%RTMweight(ilevel) * UD_fc(ilevel)%E(ind) &\n"
        "                    * optPropRTMGridS%ksca(ilevel) * trace_angle_contribution)\n"
        "                end do\n"
        "                trace_angle_contribution = Pmin(ind, ind0) * UD_fc(ilevel)%E(ind0)\n"
        "                call o2a_trace_transport_source_angle_component(iFourier, ilevel, 'pmin_direct', nGauss + 1, &\n"
        "                  Pmin(ind, ind0), UD_fc(ilevel)%E(ind0), trace_angle_contribution, &\n"
        "                  optPropRTMGridS%RTMweight(ilevel) * UD_fc(ilevel)%E(ind) * optPropRTMGridS%ksca(ilevel) &\n"
        "                  * trace_angle_contribution)\n"
        "                do imu = 1, nGauss\n"
        "                  trace_angle_contribution = Pplusst(ind, 1 + (imu - 1) * dimSV_fc) * UD_fc(ilevel)%U(1 + (imu - 1) * dimSV_fc, is)\n"
        "                  call o2a_trace_transport_source_angle_component(iFourier, ilevel, 'pplusst_up', imu - 1, &\n"
        "                    Pplusst(ind, 1 + (imu - 1) * dimSV_fc), UD_fc(ilevel)%U(1 + (imu - 1) * dimSV_fc, is), &\n"
        "                    trace_angle_contribution, optPropRTMGridS%RTMweight(ilevel) * UD_fc(ilevel)%E(ind) &\n"
        "                    * optPropRTMGridS%ksca(ilevel) * trace_angle_contribution)\n"
        "                end do\n"
        "              end if\n"
        "              contribrefl_fc(iSV, ilevel) =  UD_fc(ilevel)%E(ind) * optPropRTMGridS%ksca(ilevel) &\n"
        "                                          * (PminED(iSV) + PplusstU(iSV))\n"
        "              if (iSV == 1 .and. optPropRTMGridS%RTMweight(ilevel) > 0.0d0 .and. optPropRTMGridS%ksca(ilevel) > 0.0d0) &\n"
        "                call o2a_trace_transport_source_term(iFourier, ilevel, optPropRTMGridS%RTMweight(ilevel), &\n"
        "                optPropRTMGridS%ksca(ilevel), contribrefl_fc(iSV, ilevel))\n"
        "              ! integration\n"
        "              sumRefl(iSV) = sumRefl(iSV) + optPropRTMGridS%RTMweight(ilevel) * contribrefl_fc(iSV, ilevel)\n",
        path,
    )
    path.write_text(text, encoding="utf-8")


def patch_prop_atmosphere_module(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "  use mathTools,          only: splintLin, spline, splint, polyInt, gaussDivPoints, &\n"
        "                                getSmoothAndDiffXsec, slitfunction, fleg\n",
        "  use mathTools,          only: splintLin, spline, splint, polyInt, gaussDivPoints, &\n"
        "                                getSmoothAndDiffXsec, slitfunction, fleg\n"
        "    use o2aFunctionTraceModule, only: o2a_trace_sublayer_optics, o2a_trace_interval_bound, &\n"
        "      o2a_trace_dense_profile_row, o2a_trace_hydrostatic_term, o2a_trace_transport_layer_accumulation\n",
        path,
    )
    text = replace_once(
        text,
        "        ! calculate altitude at pressure grid using integration\n"
        "        do ipressure = 1, gasPTS%npressure\n"
        "          startIndex = (ipressure - 1) * numDivisionPoints\n"
        "          altitude(ipressure)   = altitude(ipressure-1)\n"
        "          altitudeAP(ipressure) = altitudeAP(ipressure-1)\n"
        "          do igauss = 1, numDivisionPoints\n"
        "            altitude(ipressure)   = altitude(ipressure) &\n"
        "                                  + weight_gp(startIndex + igauss) * scaleHeight_gp(startIndex + igauss)\n"
        "            altitudeAP(ipressure) = altitudeAP(ipressure) &\n"
        "                                  + weight_gp(startIndex + igauss) * scaleHeightAP_gp(startIndex + igauss)\n"
        "          end do ! igauss\n"
        "        end do ! ipressure\n",
        "        ! calculate altitude at pressure grid using integration\n"
        "        do ipressure = 1, gasPTS%npressure\n"
        "          startIndex = (ipressure - 1) * numDivisionPoints\n"
        "          altitude(ipressure)   = altitude(ipressure-1)\n"
        "          altitudeAP(ipressure) = altitudeAP(ipressure-1)\n"
        "          do igauss = 1, numDivisionPoints\n"
        "            altitude(ipressure)   = altitude(ipressure) &\n"
        "                                  + weight_gp(startIndex + igauss) * scaleHeight_gp(startIndex + igauss)\n"
        "            call o2a_trace_hydrostatic_term(iteration, ipressure, igauss, lnpressure_gp(startIndex + igauss), &\n"
        "              weight_gp(startIndex + igauss), altitude_gp(startIndex + igauss), temperature_gp(startIndex + igauss), &\n"
        "              gravitationalAcceleration(45.0d0, altitude_gp(startIndex + igauss)), scaleHeight_gp(startIndex + igauss), &\n"
        "              weight_gp(startIndex + igauss) * scaleHeight_gp(startIndex + igauss), altitude(ipressure))\n"
        "            altitudeAP(ipressure) = altitudeAP(ipressure) &\n"
        "                                  + weight_gp(startIndex + igauss) * scaleHeightAP_gp(startIndex + igauss)\n"
        "          end do ! igauss\n"
        "        end do ! ipressure\n",
        path,
    )
    text = replace_once(
        text,
        "      ! fill the scale height on the pressure grid\n"
        "      do ipressure = 0, gasPTS%npressure\n"
        "        gasPTS%scaleHeight(ipressure)   = 1.0d-3 * universalGasConstant * gasPTS%temperature(ipressure) &\n"
        "              / meanMolWeightAir / gravitationalAcceleration( 45.0d0, gasPTS%alt(ipressure) )\n"
        "        gasPTS%scaleHeightAP(ipressure) = 1.0d-3 * universalGasConstant * gasPTS%temperatureAP(ipressure) &\n"
        "              / meanMolWeightAir / gravitationalAcceleration( 45.0d0, gasPTS%altAP(ipressure) )\n"
        "      end do\n",
        "      ! fill the scale height on the pressure grid\n"
        "      do ipressure = 0, gasPTS%npressure\n"
        "        gasPTS%scaleHeight(ipressure)   = 1.0d-3 * universalGasConstant * gasPTS%temperature(ipressure) &\n"
        "              / meanMolWeightAir / gravitationalAcceleration( 45.0d0, gasPTS%alt(ipressure) )\n"
        "        gasPTS%scaleHeightAP(ipressure) = 1.0d-3 * universalGasConstant * gasPTS%temperatureAP(ipressure) &\n"
        "              / meanMolWeightAir / gravitationalAcceleration( 45.0d0, gasPTS%altAP(ipressure) )\n"
        "      end do\n"
        "      do ipressure = 0, gasPTS%npressure\n"
        "        call o2a_trace_dense_profile_row(ipressure, gasPTS%pressure(ipressure), gasPTS%lnpressure(ipressure), &\n"
        "          gasPTS%alt(ipressure), gasPTS%temperature(ipressure), gasPTS%pressure(ipressure) / gasPTS%temperature(ipressure) / 1.380658d-19, &\n"
        "          gasPTS%scaleHeight(ipressure))\n"
        "      end do\n",
        path,
    )
    text = replace_once(
        text,
        "       do ialt = 0, cloudAerosolRTMgridS%ninterval\n"
        "         cloudAerosolRTMgridS%intervalBoundsAP(ialt) = &\n"
        "           splint(errS, lnpressure, gasPTS%altAP, SDaltitudeAP, log(cloudAerosolRTMgridS%intervalBoundsAP_P(ialt)), status)\n"
        "         cloudAerosolRTMgridS%intervalBounds(ialt) = &\n"
        "           splint(errS, lnpressure, gasPTS%alt, SDaltitude, log(cloudAerosolRTMgridS%intervalBounds_P(ialt)), status)\n"
        "       end do\n"
        "       surfaceS(:)%altitude = cloudAerosolRTMgridS%intervalBounds(0)\n",
        "       do ialt = 0, cloudAerosolRTMgridS%ninterval\n"
        "         cloudAerosolRTMgridS%intervalBoundsAP(ialt) = &\n"
        "           splint(errS, lnpressure, gasPTS%altAP, SDaltitudeAP, log(cloudAerosolRTMgridS%intervalBoundsAP_P(ialt)), status)\n"
        "         cloudAerosolRTMgridS%intervalBounds(ialt) = &\n"
        "           splint(errS, lnpressure, gasPTS%alt, SDaltitude, log(cloudAerosolRTMgridS%intervalBounds_P(ialt)), status)\n"
        "       end do\n"
        "       do ialt = 0, cloudAerosolRTMgridS%ninterval\n"
        "         call o2a_trace_interval_bound(ialt, cloudAerosolRTMgridS%intervalBounds_P(ialt), cloudAerosolRTMgridS%intervalBounds(ialt))\n"
        "       end do\n"
        "       surfaceS(:)%altitude = cloudAerosolRTMgridS%intervalBounds(0)\n",
        path,
    )
    text = replace_once(
        text,
        "    integer  :: icoef, ilevel, ibound, igauss, igaussSub, index, indexSub, iTrace, imodel, iExpCoef\n"
        "    integer  :: status\n",
        "    integer  :: icoef, ilevel, ibound, igauss, igaussSub, index, indexSub, iTrace, imodel, iExpCoef\n"
        "    integer  :: status\n"
        "    integer  :: o2TraceIndex, ciaTraceIndex\n"
        "    real(8)  :: oxygenNumberDensity, lineCrossSection, ciaSigma, pathLengthCm, ciaOpticalDepth\n"
        "    real(8)  :: aerosolOpticalDepth, aerosolScatteringOpticalDepth, cloudOpticalDepth, cloudScatteringOpticalDepth\n"
        "    real(8)  :: totalScatteringOpticalDepth, totalOpticalDepth\n",
        path,
    )
    text = replace_once(
        text,
        "    numberDensityAir(:) = pressure(:) / temperature(:) / 1.380658d-19 ! in molecules cm-3\n\n"
        "    ! calculate values for column grid\n",
        "    numberDensityAir(:) = pressure(:) / temperature(:) / 1.380658d-19 ! in molecules cm-3\n\n"
        "    o2TraceIndex = 0\n"
        "    ciaTraceIndex = 0\n"
        "    do iTrace = 1, nTrace\n"
        "      if (trim(traceGasS(iTrace)%nameTraceGas) == 'O2') o2TraceIndex = iTrace\n"
        "      if (trim(traceGasS(iTrace)%nameTraceGas) == 'O2-O2') ciaTraceIndex = iTrace\n"
        "    end do\n\n"
        "    ! calculate values for column grid\n",
        path,
    )
    text = replace_once(
        text,
        "        if ( bsca(index) > 1.0d-8 ) then\n"
        "          expCoefLay(:,:,:, index) = expCoefLay(:,:,:, index) / bsca(index)\n"
        "        else\n"
        "          expCoefLay(:,:,:, index) = 0.0d0\n"
        "          expCoefLay(1,1,0, index) = 1.0d0\n"
        "        end if\n\n"
        "        ! determine maxExpCoef for the layers\n",
        "        if ( bsca(index) > 1.0d-8 ) then\n"
        "          expCoefLay(:,:,:, index) = expCoefLay(:,:,:, index) / bsca(index)\n"
        "        else\n"
        "          expCoefLay(:,:,:, index) = 0.0d0\n"
        "          expCoefLay(1,1,0, index) = 1.0d0\n"
        "        end if\n"
        "        call o2a_trace_transport_layer_accumulation(wavelength, index - 1, babs(index), bsca(index), &\n"
        "          babsGas(index), bscaGas(index), babsPar(index), bscaPar(index))\n\n"
        "        ! determine maxExpCoef for the layers\n",
        path,
    )
    text = replace_once(
        text,
        "          optPropRTMGridS%kabsSubGas(indexSub) = kabsGas(indexSub)\n"
        "          optPropRTMGridS%kextSubGas(indexSub) = kabsGas(indexSub) + kscaGas(indexSub)\n"
        "          optPropRTMGridS%kextSubAer(indexSub) = kscaAer(indexSub) + kabsAer(indexSub)\n"
        "          optPropRTMGridS%kextSubCld(indexSub) = kscaCld(indexSub) + kabsCld(indexSub)\n\n"
        "          indexSub = indexSub + 1\n",
        "          optPropRTMGridS%kabsSubGas(indexSub) = kabsGas(indexSub)\n"
        "          optPropRTMGridS%kextSubGas(indexSub) = kabsGas(indexSub) + kscaGas(indexSub)\n"
        "          optPropRTMGridS%kextSubAer(indexSub) = kscaAer(indexSub) + kabsAer(indexSub)\n"
        "          optPropRTMGridS%kextSubCld(indexSub) = kscaCld(indexSub) + kabsCld(indexSub)\n"
        "          oxygenNumberDensity = 0.0d0\n"
        "          lineCrossSection = 0.0d0\n"
        "          ciaSigma = 0.0d0\n"
        "          if (o2TraceIndex > 0) then\n"
        "            oxygenNumberDensity = optPropRTMGridS%ndensSubGas(indexSub,o2TraceIndex)\n"
        "            lineCrossSection = optPropRTMGridS%XsecSubGas(indexSub,o2TraceIndex)\n"
        "          end if\n"
        "          if (ciaTraceIndex > 0) ciaSigma = optPropRTMGridS%XsecSubGas(indexSub,ciaTraceIndex)\n"
        "          pathLengthCm = optPropRTMGridS%RTMweightSub(indexSub) * 1.0d5\n"
        "          ciaOpticalDepth = 0.0d0\n"
        "          if (ciaTraceIndex > 0) ciaOpticalDepth = ciaSigma * optPropRTMGridS%ndensSubGas(indexSub,ciaTraceIndex) * pathLengthCm\n"
        "          aerosolOpticalDepth = (kscaAer(indexSub) + kabsAer(indexSub)) * optPropRTMGridS%RTMweightSub(indexSub)\n"
        "          aerosolScatteringOpticalDepth = kscaAer(indexSub) * optPropRTMGridS%RTMweightSub(indexSub)\n"
        "          cloudOpticalDepth = (kscaCld(indexSub) + kabsCld(indexSub)) * optPropRTMGridS%RTMweightSub(indexSub)\n"
        "          cloudScatteringOpticalDepth = kscaCld(indexSub) * optPropRTMGridS%RTMweightSub(indexSub)\n"
        "          totalScatteringOpticalDepth = ksca(indexSub) * optPropRTMGridS%RTMweightSub(indexSub)\n"
        "          totalOpticalDepth = (ksca(indexSub) + kabs(indexSub)) * optPropRTMGridS%RTMweightSub(indexSub)\n"
        "          call o2a_trace_sublayer_optics(wavelength, indexSub, ibound, optPropRTMGridS%RTMaltitudeSub(indexSub), optPropRTMGridS%RTMweightSub(indexSub), pressure(indexSub), temperature(indexSub), numberDensityAir(indexSub), oxygenNumberDensity, lineCrossSection, ciaSigma, kabsGas(indexSub) * optPropRTMGridS%RTMweightSub(indexSub) - ciaOpticalDepth, kscaGas(indexSub) * optPropRTMGridS%RTMweightSub(indexSub), ciaOpticalDepth, pathLengthCm, aerosolOpticalDepth, aerosolScatteringOpticalDepth, cloudOpticalDepth, cloudScatteringOpticalDepth, totalScatteringOpticalDepth, totalOpticalDepth, expCoef(1,1,0,indexSub), expCoef(1,1,1,indexSub), expCoef(1,1,2,indexSub), expCoef(1,1,3,indexSub), expCoef(1,1,10,indexSub), expCoef(1,1,20,indexSub), expCoef(1,1,39,indexSub))\n\n"
        "          indexSub = indexSub + 1\n",
        path,
    )
    text = replace_once(
        text,
        "    optPropRTMGridS%kabsSubGas(indexSub) = kabsGas(indexSub)\n"
        "    optPropRTMGridS%kextSubGas(indexSub) = kabsGas(indexSub) + kscaGas(indexSub)\n"
        "    optPropRTMGridS%kextSubAer(indexSub) = kscaAer(indexSub) + kabsAer(indexSub)\n"
        "    optPropRTMGridS%kextSubCld(indexSub) = kscaCld(indexSub) + kabsCld(indexSub)\n\n"
        "    if ( verbose ) then\n",
        "    optPropRTMGridS%kabsSubGas(indexSub) = kabsGas(indexSub)\n"
        "    optPropRTMGridS%kextSubGas(indexSub) = kabsGas(indexSub) + kscaGas(indexSub)\n"
        "    optPropRTMGridS%kextSubAer(indexSub) = kscaAer(indexSub) + kabsAer(indexSub)\n"
        "    optPropRTMGridS%kextSubCld(indexSub) = kscaCld(indexSub) + kabsCld(indexSub)\n"
        "    oxygenNumberDensity = 0.0d0\n"
        "    lineCrossSection = 0.0d0\n"
        "    ciaSigma = 0.0d0\n"
        "    if (o2TraceIndex > 0) then\n"
        "      oxygenNumberDensity = optPropRTMGridS%ndensSubGas(indexSub,o2TraceIndex)\n"
        "      lineCrossSection = optPropRTMGridS%XsecSubGas(indexSub,o2TraceIndex)\n"
        "    end if\n"
        "    if (ciaTraceIndex > 0) ciaSigma = optPropRTMGridS%XsecSubGas(indexSub,ciaTraceIndex)\n"
    "    pathLengthCm = optPropRTMGridS%RTMweightSub(indexSub) * 1.0d5\n"
    "    ciaOpticalDepth = 0.0d0\n"
    "    if (ciaTraceIndex > 0) ciaOpticalDepth = ciaSigma * optPropRTMGridS%ndensSubGas(indexSub,ciaTraceIndex) * pathLengthCm\n"
    "    aerosolOpticalDepth = (kscaAer(indexSub) + kabsAer(indexSub)) * optPropRTMGridS%RTMweightSub(indexSub)\n"
    "    aerosolScatteringOpticalDepth = kscaAer(indexSub) * optPropRTMGridS%RTMweightSub(indexSub)\n"
    "    cloudOpticalDepth = (kscaCld(indexSub) + kabsCld(indexSub)) * optPropRTMGridS%RTMweightSub(indexSub)\n"
    "    cloudScatteringOpticalDepth = kscaCld(indexSub) * optPropRTMGridS%RTMweightSub(indexSub)\n"
    "    totalScatteringOpticalDepth = ksca(indexSub) * optPropRTMGridS%RTMweightSub(indexSub)\n"
    "    totalOpticalDepth = (ksca(indexSub) + kabs(indexSub)) * optPropRTMGridS%RTMweightSub(indexSub)\n"
    "    call o2a_trace_sublayer_optics(wavelength, indexSub, cloudAerosolRTMgridS%ninterval, optPropRTMGridS%RTMaltitudeSub(indexSub), optPropRTMGridS%RTMweightSub(indexSub), pressure(indexSub), temperature(indexSub), numberDensityAir(indexSub), oxygenNumberDensity, lineCrossSection, ciaSigma, kabsGas(indexSub) * optPropRTMGridS%RTMweightSub(indexSub) - ciaOpticalDepth, kscaGas(indexSub) * optPropRTMGridS%RTMweightSub(indexSub), ciaOpticalDepth, pathLengthCm, aerosolOpticalDepth, aerosolScatteringOpticalDepth, cloudOpticalDepth, cloudScatteringOpticalDepth, totalScatteringOpticalDepth, totalOpticalDepth, expCoef(1,1,0,indexSub), expCoef(1,1,1,indexSub), expCoef(1,1,2,indexSub), expCoef(1,1,3,indexSub), expCoef(1,1,10,indexSub), expCoef(1,1,20,indexSub), expCoef(1,1,39,indexSub))\n\n"
    "    if ( verbose ) then\n",
        path,
    )
    path.write_text(text, encoding="utf-8")


def update_latest_trace_root(trace_root: Path) -> None:
    if trace_root.parent != DEFAULT_TRACE_ROOT:
        return
    latest_path = DEFAULT_TRACE_ROOT / "latest"
    if latest_path.exists() or latest_path.is_symlink():
        if latest_path.is_dir() and not latest_path.is_symlink():
            shutil.rmtree(latest_path)
        else:
            latest_path.unlink()
    try:
        latest_path.symlink_to(trace_root.name, target_is_directory=True)
    except OSError:
        shutil.copytree(trace_root, latest_path)


def run_command(command: list[str], cwd: Path, env: dict[str, str] | None = None) -> None:
    subprocess.run(command, cwd=cwd, env=env, check=True)


def replace_once(text: str, old: str, new: str, path: Path) -> str:
    if old not in text:
        raise RuntimeError(f"Failed to patch {path}: expected snippet not found")
    return text.replace(old, new, 1)


def format_wavelength(value: float) -> str:
    return f"{value:.8f}".rstrip("0").rstrip(".")


if __name__ == "__main__":
    sys.exit(main())
