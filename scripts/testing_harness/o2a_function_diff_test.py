#!/usr/bin/env python3

from __future__ import annotations

import tempfile
from pathlib import Path

from o2a_function_diff import CSV_SPECS, compare_csv_files, write_csv_rows


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

        lines = compare_csv_files(left, right, CSV_SPECS["transport_summary.csv"])
        summary = "\n".join(lines)
        assert "rows: fortran=2 zig=2" in summary
        assert "keys/order: match" in summary
        assert "final_radiance: max_abs_diff=2.500000000000e-01" in summary
        assert "final_irradiance: max_abs_diff=0.0 first_diff=none" in summary
        assert "final_reflectance: max_abs_diff=6.250000000000e-02" in summary
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
