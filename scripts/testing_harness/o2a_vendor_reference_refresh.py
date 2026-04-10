#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import time


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Regenerate the tracked O2A vendor reference CSV from the vendored DISAMAR executable."
    )
    parser.add_argument(
        "--vendor-root",
        default="vendor/disamar-fortran",
        help="Vendored DISAMAR root directory.",
    )
    parser.add_argument(
        "--config",
        default="InputFiles/Config_O2_with_CIA.in",
        help="Vendor config to link to Config.in for the refresh run.",
    )
    parser.add_argument(
        "--reference-csv",
        default="validation/reference/o2a_with_cia_disamar_reference.csv",
        help="Tracked vendor reference CSV to overwrite.",
    )
    parser.add_argument(
        "--output-dir",
        default="out/analysis/o2a/vendor_reference_refresh",
        help="Disposable output directory for raw vendor run artifacts.",
    )
    return parser.parse_args()


def parse_ascii_hdf_arrays(path: Path) -> dict[str, list[float]]:
    wanted = {
        "solar_zenith_angle",
        "wavelength_irradiance_band_1",
        "wavelength_radiance_band_1",
        "solar_irradiance_band_1",
        "earth_radiance_band_1",
    }
    arrays: dict[str, list[float]] = {}
    current: str | None = None
    capture = False
    with path.open(errors="ignore") as handle:
        for raw in handle:
            line = raw.strip()
            match = re.match(r"BeginArray\(([^,]+),", line)
            if match:
                current = match.group(1)
                capture = current in wanted
                if capture:
                    arrays[current] = []
                continue
            if current is None:
                continue
            if line == "EndArray":
                current = None
                capture = False
                continue
            if not capture or not line:
                continue
            if line.startswith(
                (
                    "BeginAttributes",
                    "EndAttributes",
                    "Order =",
                    "NumDimensions =",
                    "Size =",
                    "unit =",
                    "wavelength =",
                    "remark =",
                )
            ):
                continue
            for token in line.split():
                try:
                    arrays[current].append(float(token.replace("D", "E")))
                except ValueError:
                    continue
    return arrays


def write_reference_csv(path: Path, arrays: dict[str, list[float]]) -> None:
    solar_zenith_deg = arrays["solar_zenith_angle"][0]
    mu0 = math.cos(math.radians(solar_zenith_deg))
    wavelength_irradiance = arrays["wavelength_irradiance_band_1"]
    wavelength_radiance = arrays["wavelength_radiance_band_1"]
    if wavelength_irradiance != wavelength_radiance:
        raise ValueError("Vendor irradiance and radiance wavelength grids differ")

    irradiance = arrays["solar_irradiance_band_1"]
    radiance = arrays["earth_radiance_band_1"]
    reflectance = [
        (math.pi * value) / max(irr * mu0, 1.0e-30)
        for value, irr in zip(radiance, irradiance, strict=True)
    ]

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["wavelength_nm", "irradiance", "radiance", "reflectance"])
        for row in zip(wavelength_radiance, irradiance, radiance, reflectance, strict=True):
            writer.writerow(
                [
                    f"{row[0]:.8f}",
                    f"{row[1]:.12e}",
                    f"{row[2]:.12e}",
                    f"{row[3]:.12e}",
                ]
            )


def refresh_vendor_reference(
    vendor_root: Path,
    config_path: Path,
    reference_csv_path: Path,
    output_dir: Path,
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    config_link = vendor_root / "Config.in"
    previous_target = None
    if config_link.exists() or config_link.is_symlink():
        previous_target = config_link.readlink() if config_link.is_symlink() else None

    try:
        if config_link.exists() or config_link.is_symlink():
            config_link.unlink()
        config_link.symlink_to(config_path)

        for name in (
            "disamar.asciiHDF",
            "disamar.out",
            "disamar.sim",
            "disamar.imed",
            "additionalOutput.out",
            "profile_errorCovariance.out",
        ):
            path = vendor_root / name
            if path.exists():
                path.unlink()

        started = time.perf_counter()
        proc = subprocess.run(
            [str(vendor_root / "src" / "Disamar.exe")],
            cwd=vendor_root,
            text=True,
            capture_output=True,
            check=False,
        )
        wall_seconds = time.perf_counter() - started

        (output_dir / "vendor_run.stdout").write_text(proc.stdout)
        (output_dir / "vendor_run.stderr").write_text(proc.stderr)
        timing_doc = {
            "wall_seconds": wall_seconds,
            "return_code": proc.returncode,
            "vendor_root": vendor_root.as_posix(),
            "config": config_path.as_posix(),
        }
        (output_dir / "vendor_timing.json").write_text(json.dumps(timing_doc, indent=2) + "\n")
        if proc.returncode != 0:
            raise RuntimeError(f"Vendored DISAMAR run failed with exit code {proc.returncode}")

        for name in (
            "disamar.asciiHDF",
            "disamar.out",
            "disamar.sim",
            "disamar.imed",
            "additionalOutput.out",
            "profile_errorCovariance.out",
        ):
            path = vendor_root / name
            if path.exists():
                shutil.copyfile(path, output_dir / name)

        arrays = parse_ascii_hdf_arrays(output_dir / "disamar.asciiHDF")
        write_reference_csv(reference_csv_path, arrays)
    finally:
        if config_link.exists() or config_link.is_symlink():
            config_link.unlink()
        if previous_target is not None:
            config_link.symlink_to(previous_target)


def main() -> None:
    args = parse_args()
    vendor_root = Path(args.vendor_root)
    refresh_vendor_reference(
        vendor_root=vendor_root,
        config_path=Path(args.config),
        reference_csv_path=Path(args.reference_csv),
        output_dir=Path(args.output_dir),
    )


if __name__ == "__main__":
    main()
