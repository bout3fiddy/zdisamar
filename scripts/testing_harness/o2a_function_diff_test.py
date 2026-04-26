#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "matplotlib>=3.10",
#   "numpy>=2.2",
# ]
# ///

from __future__ import annotations

import tempfile
import json
from pathlib import Path
import csv

from o2a_function_diff import (
    CSV_SPECS,
    EXPECTED_CSVS,
    WEAK_LINE_CONTRIBUTOR_FILE,
    WEAK_LINE_CONTRIBUTOR_SPEC,
    align_sublayer_optics_to_yaml,
    aggregate_weak_line_contributors,
    canonicalize_optional_csv,
    compare_csv_files,
    derive_granular_transport_traces,
    load_parity_irradiance_support,
    merge_fortran_sublayer_optics,
    representative_vendor_indices_for_yaml,
    summarize_pairwise_diff,
    write_function_diff_plot_bundle,
    write_granular_contributor_summaries,
    write_irradiance_support_diagnostic,
    write_weak_line_contributor_summary,
    write_csv_rows,
)

REPO_ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    with tempfile.TemporaryDirectory() as tmpdir:
        root = Path(tmpdir)
        build_zig = (REPO_ROOT / "build.zig").read_text(encoding="utf-8")
        assert '"o2a-parity-diagnostics"' in build_zig
        assert 'o2a_parity_diagnostics_step.dependOn(&o2a_plot_bundle_cmd.step);' in build_zig
        assert 'o2a_parity_diagnostics_step.dependOn(&o2a_parity_diagnostics_function_diff_cmd.step);' in build_zig
        assert '"764.48,762.29,773.9"' in build_zig

        left = root / "left.csv"
        right = root / "right.csv"
        write_csv_rows(
            left,
            ["nominal_wavelength_nm", "final_radiance", "final_irradiance", "final_reflectance"],
            [
                {
                    "nominal_wavelength_nm": "755.0",
                    "final_radiance": "1.0",
                    "final_irradiance": "2.0",
                    "final_reflectance": "0.5",
                },
                {
                    "nominal_wavelength_nm": "762.29",
                    "final_radiance": "2.0",
                    "final_irradiance": "4.0",
                    "final_reflectance": "0.5",
                },
            ],
        )
        write_csv_rows(
            right,
            ["nominal_wavelength_nm", "final_radiance", "final_irradiance", "final_reflectance"],
            [
                {
                    "nominal_wavelength_nm": "755.0",
                    "final_radiance": "1.0",
                    "final_irradiance": "2.0",
                    "final_reflectance": "0.5",
                },
                {
                    "nominal_wavelength_nm": "762.29",
                    "final_radiance": "2.25",
                    "final_irradiance": "4.0",
                    "final_reflectance": "0.5625",
                },
            ],
        )

        lines = compare_csv_files(
            left,
            right,
            CSV_SPECS["transport_summary.csv"],
            left_label="vendor",
            right_label="yaml",
        )
        summary = "\n".join(lines)
        assert "rows: vendor=2 yaml=2" in summary
        assert "keys/order: match" in summary
        assert "alignment: aligned" in summary
        assert "final_radiance: max_abs_diff=2.500000000000e-01" in summary
        assert "final_irradiance: max_abs_diff=0.0 first_diff=none" in summary
        assert "final_reflectance: max_abs_diff=6.250000000000e-02" in summary
        assert "first_nonzero_delta: column=final_radiance row=2 vendor=2.0 yaml=2.25" in summary

        sublayer_headers = [
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
        ]
        sublayer_extra_defaults = {
            "altitude_km": "0.0",
            "support_weight_km": "1.0",
            "aerosol_optical_depth": "0.0",
            "aerosol_scattering_optical_depth": "0.0",
            "cloud_optical_depth": "0.0",
            "cloud_scattering_optical_depth": "0.0",
            "total_scattering_optical_depth": "0.0",
            "total_optical_depth": "0.0",
            "combined_phase_coef_0": "1.0",
            "combined_phase_coef_1": "0.0",
            "combined_phase_coef_2": "0.0",
            "combined_phase_coef_3": "0.0",
            "combined_phase_coef_10": "0.0",
            "combined_phase_coef_20": "0.0",
            "combined_phase_coef_39": "0.0",
        }
        left_sublayer = root / "left_sublayer.csv"
        right_sublayer = root / "right_sublayer.csv"
        write_csv_rows(
            left_sublayer,
            sublayer_headers,
            [
                {
                    "wavelength_nm": "761.75",
                    "global_sublayer_index": "0",
                    "interval_index_1based": "1",
                    "pressure_hpa": "1000.0",
                    "temperature_k": "290.0",
                    "number_density_cm3": "2.4e19",
                    "oxygen_number_density_cm3": "5.0e18",
                    "line_cross_section_cm2_per_molecule": "1.0e-24",
                    "line_mixing_cross_section_cm2_per_molecule": "5.0e-27",
                    "cia_sigma_cm5_per_molecule2": "1.0e-46",
                    "gas_absorption_optical_depth": "0.5",
                    "gas_scattering_optical_depth": "0.1",
                    "cia_optical_depth": "0.02",
                    "path_length_cm": "100.0",
                    **sublayer_extra_defaults,
                },
            ],
        )
        write_csv_rows(
            right_sublayer,
            sublayer_headers,
            [
                {
                    "wavelength_nm": "761.75",
                    "global_sublayer_index": "0",
                    "interval_index_1based": "1",
                    "pressure_hpa": "1000.0",
                    "temperature_k": "290.0",
                    "number_density_cm3": "2.4e19",
                    "oxygen_number_density_cm3": "5.0e18",
                    "line_cross_section_cm2_per_molecule": "1.0e-24",
                    "line_mixing_cross_section_cm2_per_molecule": "5.0e-27",
                    "cia_sigma_cm5_per_molecule2": "1.0e-46",
                    "gas_absorption_optical_depth": "0.5",
                    "gas_scattering_optical_depth": "0.125",
                    "cia_optical_depth": "0.02",
                    "path_length_cm": "100.0",
                    **sublayer_extra_defaults,
                },
            ],
        )
        sublayer_lines = compare_csv_files(
            left_sublayer,
            right_sublayer,
            CSV_SPECS["sublayer_optics.csv"],
            left_label="vendor",
            right_label="yaml",
        )
        sublayer_summary = "\n".join(sublayer_lines)
        assert "alignment: aligned" in sublayer_summary
        assert "gas_scattering_optical_depth: max_abs_diff=2.500000000000e-02" in sublayer_summary

        fortran_root = root / "fortran"
        fortran_root.mkdir()
        write_csv_rows(
            fortran_root / "spectroscopy_summary.csv",
            [
                "pressure_hpa",
                "temperature_k",
                "wavelength_nm",
                "weak_sigma_cm2_per_molecule",
                "strong_sigma_cm2_per_molecule",
                "line_mixing_sigma_cm2_per_molecule",
                "total_sigma_cm2_per_molecule",
            ],
            [
                {
                    "pressure_hpa": "1000.0",
                    "temperature_k": "290.0",
                    "wavelength_nm": "761.75",
                    "weak_sigma_cm2_per_molecule": "1.0e-24",
                    "strong_sigma_cm2_per_molecule": "2.0e-24",
                    "line_mixing_sigma_cm2_per_molecule": "3.0e-27",
                    "total_sigma_cm2_per_molecule": "3.003e-24",
                },
            ],
        )
        write_csv_rows(
            fortran_root / "sublayer_optics_raw.csv",
            [
                "actual_wavelength_nm",
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
            ],
            [
                {
                    "actual_wavelength_nm": "761.741",
                    "wavelength_nm": "761.75",
                    "global_sublayer_index": "5",
                    "interval_index_1based": "2",
                    "pressure_hpa": "1000.0",
                    "temperature_k": "290.0",
                    "number_density_cm3": "2.4e19",
                    "oxygen_number_density_cm3": "5.0e18",
                    "line_cross_section_cm2_per_molecule": "nan",
                    "line_mixing_cross_section_cm2_per_molecule": "nan",
                    "cia_sigma_cm5_per_molecule2": "1.0e-46",
                    "gas_absorption_optical_depth": "0.40",
                    "gas_scattering_optical_depth": "0.10",
                    "cia_optical_depth": "0.02",
                    "path_length_cm": "100.0",
                    **sublayer_extra_defaults,
                },
                {
                    "actual_wavelength_nm": "761.749",
                    "wavelength_nm": "761.75",
                    "global_sublayer_index": "5",
                    "interval_index_1based": "2",
                    "pressure_hpa": "1000.0",
                    "temperature_k": "290.0",
                    "number_density_cm3": "2.4e19",
                    "oxygen_number_density_cm3": "5.0e18",
                    "line_cross_section_cm2_per_molecule": "nan",
                    "line_mixing_cross_section_cm2_per_molecule": "nan",
                    "cia_sigma_cm5_per_molecule2": "2.0e-46",
                    "gas_absorption_optical_depth": "0.50",
                    "gas_scattering_optical_depth": "0.20",
                    "cia_optical_depth": "0.03",
                    "path_length_cm": "100.0",
                    **sublayer_extra_defaults,
                },
            ],
        )
        merge_fortran_sublayer_optics(fortran_root)
        merged_rows = list(csv.DictReader((fortran_root / "sublayer_optics.csv").open()))
        assert len(merged_rows) == 1
        assert not (fortran_root / "sublayer_optics_raw.csv").exists()
        merged_row = merged_rows[0]
        assert merged_row["global_sublayer_index"] == "5"
        assert merged_row["interval_index_1based"] == "2"
        assert merged_row["gas_scattering_optical_depth"] == "0.20"
        assert abs(float(merged_row["line_cross_section_cm2_per_molecule"]) - 3.0e-24) < 1.0e-30
        assert merged_row["line_mixing_cross_section_cm2_per_molecule"] == "3.0e-27"
        assert representative_vendor_indices_for_yaml(
            [{"pressure_hpa": value} for value in ["1000.0", "990.0", "980.0", "970.0", "960.0", "950.0", "940.0"]],
            [{"pressure_hpa": value} for value in ["995.0", "965.0", "945.0"]],
        ) == [0, 3, 5]

        aligned_vendor_root = root / "aligned_vendor"
        aligned_yaml_root = root / "aligned_yaml"
        aligned_vendor_root.mkdir()
        aligned_yaml_root.mkdir()
        write_csv_rows(
            aligned_vendor_root / "sublayer_optics.csv",
            sublayer_headers,
            [
                {
                    "wavelength_nm": "761.75",
                    "global_sublayer_index": str(index),
                    "interval_index_1based": "1",
                    "pressure_hpa": str(1000.0 - index),
                    "temperature_k": "290.0",
                    "number_density_cm3": "2.4e19",
                    "oxygen_number_density_cm3": "5.0e18",
                    "line_cross_section_cm2_per_molecule": "1.0e-24",
                    "line_mixing_cross_section_cm2_per_molecule": "5.0e-27",
                    "cia_sigma_cm5_per_molecule2": "1.0e-46",
                    "gas_absorption_optical_depth": str(0.1 * (index + 1)),
                    "gas_scattering_optical_depth": "0.1",
                    "cia_optical_depth": "0.02",
                    "path_length_cm": "100.0",
                    **sublayer_extra_defaults,
                }
                for index in range(7)
            ],
        )
        write_csv_rows(
            aligned_yaml_root / "sublayer_optics.csv",
            sublayer_headers,
            [
                {
                    "wavelength_nm": "761.75",
                    "global_sublayer_index": "10",
                    "interval_index_1based": "1",
                    "pressure_hpa": "1000.0",
                    "temperature_k": "290.0",
                    "number_density_cm3": "2.4e19",
                    "oxygen_number_density_cm3": "5.0e18",
                    "line_cross_section_cm2_per_molecule": "1.0e-24",
                    "line_mixing_cross_section_cm2_per_molecule": "5.0e-27",
                    "cia_sigma_cm5_per_molecule2": "1.0e-46",
                    "gas_absorption_optical_depth": "0.1",
                    "gas_scattering_optical_depth": "0.1",
                    "cia_optical_depth": "0.02",
                    "path_length_cm": "100.0",
                    **sublayer_extra_defaults,
                },
                {
                    "wavelength_nm": "761.75",
                    "global_sublayer_index": "11",
                    "interval_index_1based": "1",
                    "pressure_hpa": "995.0",
                    "temperature_k": "290.0",
                    "number_density_cm3": "2.4e19",
                    "oxygen_number_density_cm3": "5.0e18",
                    "line_cross_section_cm2_per_molecule": "1.0e-24",
                    "line_mixing_cross_section_cm2_per_molecule": "5.0e-27",
                    "cia_sigma_cm5_per_molecule2": "1.0e-46",
                    "gas_absorption_optical_depth": "0.2",
                    "gas_scattering_optical_depth": "0.1",
                    "cia_optical_depth": "0.02",
                    "path_length_cm": "100.0",
                    **sublayer_extra_defaults,
                },
                {
                    "wavelength_nm": "761.75",
                    "global_sublayer_index": "12",
                    "interval_index_1based": "1",
                    "pressure_hpa": "990.0",
                    "temperature_k": "290.0",
                    "number_density_cm3": "2.4e19",
                    "oxygen_number_density_cm3": "5.0e18",
                    "line_cross_section_cm2_per_molecule": "1.0e-24",
                    "line_mixing_cross_section_cm2_per_molecule": "5.0e-27",
                    "cia_sigma_cm5_per_molecule2": "1.0e-46",
                    "gas_absorption_optical_depth": "0.3",
                    "gas_scattering_optical_depth": "0.1",
                    "cia_optical_depth": "0.02",
                    "path_length_cm": "100.0",
                    **sublayer_extra_defaults,
                },
            ],
        )
        align_sublayer_optics_to_yaml(aligned_vendor_root, aligned_yaml_root)
        aligned_rows = list(csv.DictReader((aligned_vendor_root / "sublayer_optics.csv").open()))
        assert [row["global_sublayer_index"] for row in aligned_rows] == ["10", "11", "12"]
        assert [row["interval_index_1based"] for row in aligned_rows] == ["1", "1", "1"]
        assert [float(row["gas_absorption_optical_depth"]) for row in aligned_rows] == [0.1, 0.6000000000000001, 0.7000000000000001]
        assert (aligned_vendor_root / "sublayer_optics_physical.csv").exists()

        vendor_root = root / "vendor"
        yaml_root = root / "yaml"
        vendor_root.mkdir()
        yaml_root.mkdir()
        for file_name in EXPECTED_CSVS:
            spec = CSV_SPECS[file_name]
            fieldnames = list(dict.fromkeys((*spec.key_columns, *spec.numeric_columns)))
            row = {field: "0.0" for field in fieldnames}
            write_csv_rows(vendor_root / file_name, fieldnames, [row])
            write_csv_rows(yaml_root / file_name, fieldnames, [row])

        write_csv_rows(
            vendor_root / "line_catalog.csv",
            [
                "source_row_index",
                *list(dict.fromkeys((*CSV_SPECS["line_catalog.csv"].key_columns, *CSV_SPECS["line_catalog.csv"].numeric_columns))),
            ],
            [
                {
                    "source_row_index": "1",
                    "gas_index": "7",
                    "isotope_number": "1",
                    "center_wavelength_nm": "761.75",
                    "center_wavenumber_cm1": "13127.0",
                    "line_strength_cm2_per_molecule": "1.0e-20",
                    "air_half_width_nm": "0.001",
                    "temperature_exponent": "0.7",
                    "lower_state_energy_cm1": "10.0",
                    "pressure_shift_nm": "0.0",
                    "line_mixing_coefficient": "0.0",
                    "branch_ic1": "5",
                    "branch_ic2": "1",
                    "rotational_nf": "1",
                },
            ],
        )
        write_csv_rows(
            yaml_root / "line_catalog.csv",
            [
                "source_row_index",
                *list(dict.fromkeys((*CSV_SPECS["line_catalog.csv"].key_columns, *CSV_SPECS["line_catalog.csv"].numeric_columns))),
            ],
            [
                {
                    "source_row_index": "1",
                    "gas_index": "7",
                    "isotope_number": "1",
                    "center_wavelength_nm": "761.75",
                    "center_wavenumber_cm1": "13127.0",
                    "line_strength_cm2_per_molecule": "1.1e-20",
                    "air_half_width_nm": "0.001",
                    "temperature_exponent": "0.7",
                    "lower_state_energy_cm1": "10.0",
                    "pressure_shift_nm": "0.0",
                    "line_mixing_coefficient": "0.0",
                    "branch_ic1": "5",
                    "branch_ic2": "1",
                    "rotational_nf": "1",
                },
            ],
        )

        pair = summarize_pairwise_diff(vendor_root, yaml_root, "vendor", "yaml", [761.75])
        pair_lines = pair["lines"]
        pair_summary = "\n".join(pair_lines)
        assert "vendor_vs_yaml" in pair_summary
        assert "first_divergence" in pair_summary
        assert "first_aligned_physics_divergence" in pair_summary
        assert "file=line_catalog.csv" in pair_summary
        assert "transport_summary.csv" in pair_summary
        pair_json = pair["json"]
        assert pair_json["wavelengths_nm"] == [761.75]
        assert pair_json["first_mismatching_file"] == "line_catalog.csv"
        assert pair_json["first_mismatching_numeric_column"] == "line_strength_cm2_per_molecule"
        assert pair_json["first_aligned_mismatching_file"] == "line_catalog.csv"
        assert pair_json["first_aligned_mismatching_numeric_column"] == "line_strength_cm2_per_molecule"

        weak_trace_root = root / "weak_trace"
        weak_vendor_root = weak_trace_root / "vendor"
        weak_yaml_root = weak_trace_root / "yaml"
        weak_diff_root = weak_trace_root / "diff"
        weak_vendor_root.mkdir(parents=True)
        weak_yaml_root.mkdir(parents=True)
        weak_diff_root.mkdir(parents=True)
        weak_headers = [
            "pressure_hpa",
            "temperature_k",
            "wavelength_nm",
            "sample_wavelength_nm",
            "source_row_index",
            "contribution_kind",
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
        ]
        write_csv_rows(
            weak_vendor_root / WEAK_LINE_CONTRIBUTOR_FILE,
            weak_headers,
            [
                {
                    "pressure_hpa": "1.0",
                    "temperature_k": "200.0",
                    "wavelength_nm": "764.48",
                    "sample_wavelength_nm": "764.4801",
                    "source_row_index": "10",
                    "contribution_kind": "weak_included",
                    "gas_index": "7",
                    "isotope_number": "1",
                    "center_wavelength_nm": "764.0",
                    "center_wavenumber_cm1": "13080.0",
                    "shifted_center_wavenumber_cm1": "13080.1",
                    "line_strength_cm2_per_molecule": "1.0e-25",
                    "air_half_width_nm": "1.0e-3",
                    "temperature_exponent": "0.7",
                    "lower_state_energy_cm1": "20.0",
                    "pressure_shift_nm": "1.0e-4",
                    "line_mixing_coefficient": "0.1",
                    "branch_ic1": "nan",
                    "branch_ic2": "nan",
                    "rotational_nf": "nan",
                    "matched_strong_index": "nan",
                    "weak_line_sigma_cm2_per_molecule": "2.5e-33",
                },
            ],
        )
        write_csv_rows(
            weak_yaml_root / WEAK_LINE_CONTRIBUTOR_FILE,
            weak_headers,
            [
                {
                    "pressure_hpa": "1.0",
                    "temperature_k": "200.0",
                    "wavelength_nm": "764.48",
                    "sample_wavelength_nm": "764.48",
                    "source_row_index": "10",
                    "contribution_kind": "weak_included",
                    "gas_index": "7",
                    "isotope_number": "1",
                    "center_wavelength_nm": "764.0",
                    "center_wavenumber_cm1": "13080.0",
                    "shifted_center_wavenumber_cm1": "13080.1",
                    "line_strength_cm2_per_molecule": "1.0e-25",
                    "air_half_width_nm": "1.0e-3",
                    "temperature_exponent": "0.7",
                    "lower_state_energy_cm1": "20.0",
                    "pressure_shift_nm": "1.0e-4",
                    "line_mixing_coefficient": "0.1",
                    "branch_ic1": "nan",
                    "branch_ic2": "nan",
                    "rotational_nf": "nan",
                    "matched_strong_index": "nan",
                    "weak_line_sigma_cm2_per_molecule": "1.0e-33",
                },
            ],
        )
        canonicalize_optional_csv(weak_vendor_root, WEAK_LINE_CONTRIBUTOR_FILE, WEAK_LINE_CONTRIBUTOR_SPEC)
        canonicalize_optional_csv(weak_yaml_root, WEAK_LINE_CONTRIBUTOR_FILE, WEAK_LINE_CONTRIBUTOR_SPEC)
        write_weak_line_contributor_summary(weak_trace_root, weak_diff_root, [764.48])
        weak_summary = (weak_diff_root / "weak_line_contributors_summary.txt").read_text()
        assert "wavelength_nm=764.48" in weak_summary
        assert "vendor_total=2.5000000000000001e-33" in weak_summary
        weak_json = (weak_diff_root / "weak_line_contributors_summary.json").read_text()
        assert '"wavelength_nm": 764.48' in weak_json
        aggregates = aggregate_weak_line_contributors(
            list(csv.DictReader((weak_vendor_root / WEAK_LINE_CONTRIBUTOR_FILE).open())),
            764.48,
        )
        assert len(aggregates) == 1
        only_record = next(iter(aggregates.values()))
        assert abs(only_record["total"] - 2.5e-33) < 1.0e-40

        granular_names = {
            "transport_radiance_contributions.csv",
            "transport_order_surface.csv",
            "transport_source_components.csv",
            "transport_source_angle_components.csv",
            "transport_pseudo_spherical_terms.csv",
            "transport_optical_depth_components.csv",
        }
        assert granular_names <= set(EXPECTED_CSVS)
        for name in granular_names:
            assert name in CSV_SPECS
            assert CSV_SPECS[name].key_columns
            assert CSV_SPECS[name].numeric_columns

        granular_trace_root = root / "granular_trace"
        granular_vendor = granular_trace_root / "vendor"
        granular_yaml = granular_trace_root / "yaml"
        granular_diff = granular_trace_root / "diff"
        granular_vendor.mkdir(parents=True)
        granular_yaml.mkdir(parents=True)
        granular_diff.mkdir(parents=True)
        transport_headers = ["nominal_wavelength_nm", "sample_index", "sample_wavelength_nm", "radiance", "irradiance", "weight"]
        write_csv_rows(
            granular_vendor / "transport_samples.csv",
            transport_headers,
            [
                {
                    "nominal_wavelength_nm": "764.48",
                    "sample_index": "0",
                    "sample_wavelength_nm": "764.48",
                    "radiance": "100.0",
                    "irradiance": "2.0",
                    "weight": "0.0",
                },
                {
                    "nominal_wavelength_nm": "764.48",
                    "sample_index": "1",
                    "sample_wavelength_nm": "764.49",
                    "radiance": "120.0",
                    "irradiance": "2.0",
                    "weight": "0.5",
                },
            ],
        )
        write_csv_rows(
            granular_yaml / "transport_samples.csv",
            transport_headers,
            [
                {
                    "nominal_wavelength_nm": "764.48",
                    "sample_index": "0",
                    "sample_wavelength_nm": "764.48",
                    "radiance": "999.0",
                    "irradiance": "2.0",
                    "weight": "0.0",
                },
                {
                    "nominal_wavelength_nm": "764.48",
                    "sample_index": "1",
                    "sample_wavelength_nm": "764.49",
                    "radiance": "100.0",
                    "irradiance": "2.0",
                    "weight": "0.5",
                },
            ],
        )
        source_headers = [
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
        ]
        write_csv_rows(
            granular_vendor / "transport_source_terms.csv",
            source_headers,
            [
                {
                    "nominal_wavelength_nm": "764.48",
                    "sample_index": "1",
                    "sample_wavelength_nm": "764.49",
                    "kernel_weight": "0.5",
                    "fourier_index": "0",
                    "level_index": "2",
                    "rtm_weight": "0.25",
                    "ksca": "2.0",
                    "source_contribution": "4.0",
                    "weighted_source_contribution": "1.0",
                },
            ],
        )
        write_csv_rows(
            granular_yaml / "transport_source_terms.csv",
            source_headers,
            [
                {
                    "nominal_wavelength_nm": "764.48",
                    "sample_index": "1",
                    "sample_wavelength_nm": "764.49",
                    "kernel_weight": "0.5",
                    "fourier_index": "0",
                    "level_index": "2",
                    "rtm_weight": "0.25",
                    "ksca": "2.0",
                    "source_contribution": "2.0",
                    "weighted_source_contribution": "0.5",
                },
            ],
        )
        attenuation_headers = [
            "nominal_wavelength_nm",
            "sample_index",
            "sample_wavelength_nm",
            "kernel_weight",
            "direction_kind",
            "direction_index",
            "level_index",
            "sumkext",
            "attenuation_top_to_level",
            "grid_valid",
        ]
        pseudo_headers = [
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
        ]
        for side in (granular_vendor, granular_yaml):
            write_csv_rows(
                side / "transport_attenuation_terms.csv",
                attenuation_headers,
                [
                    {
                        "nominal_wavelength_nm": "764.48",
                        "sample_index": "1",
                        "sample_wavelength_nm": "764.49",
                        "kernel_weight": "0.5",
                        "direction_kind": "view",
                        "direction_index": "4",
                        "level_index": "0",
                        "sumkext": "1.0",
                        "attenuation_top_to_level": "0.5",
                        "grid_valid": "1",
                    },
                ],
            )
        write_csv_rows(
            granular_vendor / "transport_pseudo_spherical_samples.csv",
            pseudo_headers,
            [
                {
                    "nominal_wavelength_nm": "764.48",
                    "sample_index": "1",
                    "sample_wavelength_nm": "764.49",
                    "kernel_weight": "0.5",
                    "global_sample_index": "3",
                    "altitude_km": "10.0",
                    "support_weight_km": "1.0",
                    "optical_depth": "0.2",
                    "radius_weighted_optical_depth": "1276.2",
                    "grid_valid": "1",
                },
            ],
        )
        write_csv_rows(
            granular_yaml / "transport_pseudo_spherical_samples.csv",
            pseudo_headers,
            [
                {
                    "nominal_wavelength_nm": "764.48",
                    "sample_index": "1",
                    "sample_wavelength_nm": "764.49",
                    "kernel_weight": "0.5",
                    "global_sample_index": "3",
                    "altitude_km": "10.0",
                    "support_weight_km": "1.0",
                    "optical_depth": "0.1",
                    "radius_weighted_optical_depth": "638.1",
                    "grid_valid": "1",
                },
            ],
        )
        for side, total in ((granular_vendor, "0.3"), (granular_yaml, "0.2")):
            write_csv_rows(
                side / "sublayer_optics.csv",
                [
                    "wavelength_nm",
                    "global_sublayer_index",
                    "interval_index_1based",
                    "gas_absorption_optical_depth",
                    "gas_scattering_optical_depth",
                    "cia_optical_depth",
                    "aerosol_optical_depth",
                    "cloud_optical_depth",
                    "total_scattering_optical_depth",
                    "total_optical_depth",
                ],
                [
                    {
                        "wavelength_nm": "764.48",
                        "global_sublayer_index": "0",
                        "interval_index_1based": "1",
                        "gas_absorption_optical_depth": "0.1",
                        "gas_scattering_optical_depth": "0.05",
                        "cia_optical_depth": "0.01",
                        "aerosol_optical_depth": "0.0",
                        "cloud_optical_depth": "0.0",
                        "total_scattering_optical_depth": "0.05",
                        "total_optical_depth": total,
                    },
                ],
            )
        order_headers = [
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
        ]
        angle_headers = [
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
        ]
        for side, order_value, angle_value in (
            (granular_vendor, "0.4", "0.2"),
            (granular_yaml, "0.3", "0.1"),
        ):
            write_csv_rows(
                side / "transport_order_surface.csv",
                order_headers,
                [
                    {
                        "nominal_wavelength_nm": "764.48",
                        "sample_index": "1",
                        "sample_wavelength_nm": "764.49",
                        "kernel_weight": "0.5",
                        "fourier_index": "0",
                        "order_index": "1",
                        "stop_reason": "accumulated",
                        "max_value": "1.0e-4",
                        "surface_u_order": order_value,
                        "surface_u_accumulated": order_value,
                        "surface_d_order": "0.0",
                        "surface_e_view": "0.9",
                    },
                ],
            )
            write_csv_rows(
                side / "transport_source_angle_components.csv",
                angle_headers,
                [
                    {
                        "nominal_wavelength_nm": "764.48",
                        "sample_index": "1",
                        "sample_wavelength_nm": "764.49",
                        "kernel_weight": "0.5",
                        "fourier_index": "0",
                        "level_index": "2",
                        "component_kind": "pmin_diffuse",
                        "angle_index": "0",
                        "phase_value": "0.25",
                        "field_value": "0.8",
                        "angle_contribution": angle_value,
                        "weighted_angle_contribution": angle_value,
                    },
                ],
            )
        derive_granular_transport_traces(granular_vendor)
        derive_granular_transport_traces(granular_yaml)
        write_granular_contributor_summaries(granular_trace_root, granular_diff, [764.48])
        radiance_summary = (granular_diff / "radiance_contributor_summary.txt").read_text()
        first_ranked_line = next(line for line in radiance_summary.splitlines() if "column=" in line)
        assert "column=weighted_radiance_contribution" in first_ranked_line
        assert "signed_delta=1.000000000000e+01" in radiance_summary
        assert "signed_delta=2.000000000000e+01" in radiance_summary
        assert "signed_delta=-8.990000000000e+02" not in radiance_summary
        assert len(list(csv.DictReader((granular_vendor / "transport_order_surface.csv").open()))) == 1
        assert len(list(csv.DictReader((granular_vendor / "transport_source_angle_components.csv").open()))) == 1
        assert (granular_diff / "labos_m0_summary.json").exists()
        assert (granular_diff / "attenuation_contributor_summary.json").exists()
        assert (granular_diff / "optical_depth_component_summary.json").exists()

        plot_trace_root = root / "plot_trace"
        plot_vendor = plot_trace_root / "vendor"
        plot_yaml = plot_trace_root / "yaml"
        plot_diff = plot_trace_root / "diff"
        plot_vendor.mkdir(parents=True)
        plot_yaml.mkdir(parents=True)
        plot_diff.mkdir(parents=True)
        summary_headers = ["nominal_wavelength_nm", "final_radiance", "final_irradiance", "final_reflectance"]
        write_csv_rows(
            plot_vendor / "transport_summary.csv",
            summary_headers,
            [
                {
                    "nominal_wavelength_nm": "761.75",
                    "final_radiance": "10.0",
                    "final_irradiance": "100.0",
                    "final_reflectance": "0.1",
                },
                {
                    "nominal_wavelength_nm": "762.29",
                    "final_radiance": "20.0",
                    "final_irradiance": "100.0",
                    "final_reflectance": "0.2",
                },
            ],
        )
        write_csv_rows(
            plot_yaml / "transport_summary.csv",
            summary_headers,
            [
                {
                    "nominal_wavelength_nm": "761.75",
                    "final_radiance": "11.0",
                    "final_irradiance": "100.0",
                    "final_reflectance": "0.11",
                },
                {
                    "nominal_wavelength_nm": "762.29",
                    "final_radiance": "21.0",
                    "final_irradiance": "100.0",
                    "final_reflectance": "0.21",
                },
            ],
        )
        write_function_diff_plot_bundle(plot_trace_root, plot_diff, [761.75, 762.29])
        plot_dir = plot_diff / "function_diff_plots"
        assert (plot_dir / "comparison_metrics.json").exists()
        assert (plot_dir / "current_vs_vendor_residuals.png").exists()
        plot_metrics = json.loads((plot_dir / "comparison_metrics.json").read_text())
        assert plot_metrics["irradiance"]["max_abs"] == 0.0

        solar_path, half_span_nm = load_parity_irradiance_support()
        assert solar_path.exists()
        assert half_span_nm > 0.0
        write_irradiance_support_diagnostic(root, [755.0, 761.75, 776.0])
        support_json = json.loads((root / "irradiance_support_summary.json").read_text(encoding="utf-8"))
        assert support_json["solar_start_nm"] <= 753.0
        assert support_json["solar_end_nm"] >= 778.0
        assert all(entry["covered"] for entry in support_json["per_wavelength"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
