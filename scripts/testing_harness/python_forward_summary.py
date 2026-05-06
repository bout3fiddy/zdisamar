#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "matplotlib>=3.10",
#   "numpy>=2.2",
# ]
# ///

from __future__ import annotations

import json
import sys
import time
from dataclasses import asdict
from pathlib import Path

import numpy as np
from o2a_python_case import build_o2a_case
from o2a_spectrum_plot import (
    interpolate_to_grid,
    load_spectrum_csv,
    write_spectrum_plot,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
OUT_DIR = REPO_ROOT / "out" / "ci"
LIBRARY_NAME = "libzdisamar_c.dylib" if sys.platform == "darwin" else "libzdisamar_c.so"
LIBRARY_PATH = REPO_ROOT / "zig-out" / "lib" / LIBRARY_NAME
VENDOR_REFERENCE_PATH = REPO_ROOT / "validation" / "data" / "o2a_with_cia_disamar_reference.csv"
SUMMARY_OUTPUT = OUT_DIR / "python_forward_summary.json"
PLOT_OUTPUT = OUT_DIR / "python_forward_summary_plot.png"
TOLERANCE = 1.0e-12


def require_library() -> str:
    if not LIBRARY_PATH.exists():
        raise FileNotFoundError(
            f"{LIBRARY_PATH} does not exist; build the native shared library first"
        )
    return str(LIBRARY_PATH)


def import_zdisamar():
    sys.path.insert(0, str(PYTHON_ROOT))
    import zdisamar as zd

    return zd


def run_forward_summary() -> dict:
    library_path = require_library()
    zd = import_zdisamar()
    case = build_o2a_case(zd)

    total_start = time.perf_counter()
    prepare_start = time.perf_counter()
    with zd.prepare(case, library_path=library_path) as prepared:
        prepare_s = time.perf_counter() - prepare_start
        forward_start = time.perf_counter()
        spectrum = prepared.forward_model()
        forward_s = time.perf_counter() - forward_start
        report = spectrum.diagnostic_report
        wavelength_nm = spectrum.wavelength_nm.copy()
        radiance = spectrum.radiance.copy()
        irradiance = spectrum.irradiance.copy()
        reflectance = spectrum.reflectance.copy()
        spectrum.close()

    min_index = int(np.argmin(reflectance))
    vendor = interpolate_to_grid(wavelength_nm, load_spectrum_csv(VENDOR_REFERENCE_PATH))
    reflectance_residual = reflectance - vendor["reflectance"]
    radiance_residual = radiance - vendor["radiance"]
    irradiance_residual = irradiance - vendor["irradiance"]

    write_spectrum_plot(
        PLOT_OUTPUT,
        wavelength_nm,
        radiance,
        irradiance,
        reflectance,
        vendor,
        min_index,
    )

    summary = {
        "sample_count": int(wavelength_nm.size),
        "min_reflectance": {
            "wavelength_nm": float(wavelength_nm[min_index]),
            "reflectance": float(reflectance[min_index]),
        },
        "diagnostic_report": asdict(report),
        "vendor_comparison": {
            "same_grid": bool(np.array_equal(wavelength_nm, vendor["wavelength_nm"])),
            "reflectance_mean_abs_residual": float(np.mean(np.abs(reflectance_residual))),
            "reflectance_max_abs_residual": float(np.max(np.abs(reflectance_residual))),
            "radiance_max_abs_residual": float(np.max(np.abs(radiance_residual))),
            "irradiance_max_abs_residual": float(np.max(np.abs(irradiance_residual))),
        },
        "timing": {
            "prepare_o2a_s": prepare_s,
            "forward_model_s": forward_s,
            "total_s": time.perf_counter() - total_start,
        },
        "artifacts": {
            "json": str(SUMMARY_OUTPUT),
            "plot": str(PLOT_OUTPUT),
        },
    }
    SUMMARY_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    SUMMARY_OUTPUT.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return summary


def main() -> int:
    summary = run_forward_summary()
    timing = summary["timing"]
    residual = summary["vendor_comparison"]["reflectance_max_abs_residual"]
    min_reflectance = summary["min_reflectance"]
    print(
        f"plot={PLOT_OUTPUT} n={summary['sample_count']} "
        f"min={min_reflectance['reflectance']:.17g}@{min_reflectance['wavelength_nm']:.2f}nm "
        f"max_abs_residual={residual:.3e} "
        f"prepare={timing['prepare_o2a_s']:.2f}s forward={timing['forward_model_s']:.2f}s "
        f"total={timing['total_s']:.2f}s"
    )
    return 0 if residual <= TOLERANCE else 1


if __name__ == "__main__":
    raise SystemExit(main())
