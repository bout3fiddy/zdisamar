#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///

from __future__ import annotations

import tempfile
from pathlib import Path
import csv

from o2a_function_diff import (
    CSV_SPECS,
    EXPECTED_CSVS,
    align_sublayer_optics_to_yaml,
    compare_csv_files,
    merge_fortran_sublayer_optics,
    representative_vendor_indices_for_yaml,
    summarize_pairwise_diff,
    write_csv_rows,
)


def main() -> int:
    with tempfile.TemporaryDirectory() as tmpdir:
        root = Path(tmpdir)
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
        ]
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
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
