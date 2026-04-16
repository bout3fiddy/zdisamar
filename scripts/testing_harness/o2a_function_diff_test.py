#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///

from __future__ import annotations

import tempfile
from pathlib import Path

from o2a_function_diff import CSV_SPECS, EXPECTED_CSVS, compare_csv_files, summarize_pairwise_diff, write_csv_rows


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
        assert "final_radiance: max_abs_diff=2.500000000000e-01" in summary
        assert "final_irradiance: max_abs_diff=0.0 first_diff=none" in summary
        assert "final_reflectance: max_abs_diff=6.250000000000e-02" in summary
        assert "first_nonzero_delta: column=final_radiance row=2 vendor=2.0 yaml=2.25" in summary

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

        pair_lines = summarize_pairwise_diff(vendor_root, yaml_root, "vendor", "yaml")
        pair_summary = "\n".join(pair_lines)
        assert "vendor_vs_yaml" in pair_summary
        assert "transport_summary.csv" in pair_summary
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
