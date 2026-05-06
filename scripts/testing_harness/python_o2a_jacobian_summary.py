#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "numpy>=2.2",
# ]
# ///

from __future__ import annotations

import argparse
import json
import math
import sys
import time
from pathlib import Path

import numpy as np
from o2a_python_case import build_o2a_case

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
OUT_DIR = REPO_ROOT / "out" / "ci"
LIBRARY_NAME = "libzdisamar_c.dylib" if sys.platform == "darwin" else "libzdisamar_c.so"
LIBRARY_PATH = REPO_ROOT / "zig-out" / "lib" / LIBRARY_NAME
REFLECTANCE_REFERENCE_PATH = (
    REPO_ROOT
    / "validation"
    / "spectra"
    / "data"
    / "reference"
    / "o2a_jacobian_simulation_instrument_reflectance.csv"
)
FORWARD_REFERENCE_PATH = (
    REPO_ROOT
    / "validation"
    / "spectra"
    / "data"
    / "reference"
    / "o2a_jacobian_retrieval_instrument_forward.csv"
)
SUMMARY_OUTPUT = OUT_DIR / "python_o2a_jacobian_summary.json"
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


def import_zdisamar():
    sys.path.insert(0, str(PYTHON_ROOT))
    import zdisamar as zd

    return zd


def require_library(path: Path) -> str:
    if not path.exists():
        raise FileNotFoundError(f"{path} does not exist; build the native shared library first")
    return str(path)


def load_reference(path: Path) -> np.ndarray:
    return np.genfromtxt(path, delimiter=",", names=True, dtype=np.float64)


def max_abs_residual(current: np.ndarray, reference: np.ndarray) -> dict[str, float]:
    residuals: dict[str, float] = {}
    for state_name in STATE_NAMES:
        interpolated = np.interp(
            current["wavelength_nm"],
            reference["wavelength_nm"],
            reference[REFERENCE_COLUMNS[state_name]],
        )
        residual = current[state_name] - interpolated
        residuals[state_name] = float(np.max(np.abs(residual)))
    return residuals


def reflectance_jacobian_from_radiance(
    case,
    radiance_jacobian: np.ndarray,
    irradiance: np.ndarray,
) -> np.ndarray:
    mu0 = math.cos(math.radians(case.geometry.solar_zenith_deg))
    return radiance_jacobian / ((mu0 * irradiance / np.pi)[:, None])


def forward_max_abs_residual(
    wavelengths: np.ndarray,
    radiance: np.ndarray,
    irradiance: np.ndarray,
    reference: np.ndarray,
) -> dict[str, float]:
    radiance_reference = np.interp(
        wavelengths,
        reference["wavelength_nm"],
        reference["radiance"],
    )
    irradiance_reference = np.interp(
        wavelengths,
        reference["wavelength_nm"],
        reference["solar_irradiance"],
    )
    return {
        "radiance": float(np.max(np.abs(radiance - radiance_reference))),
        "irradiance": float(np.max(np.abs(irradiance - irradiance_reference))),
    }


def run_summary(
    library_path: Path,
    reflectance_reference_path: Path,
    forward_reference_path: Path,
    threshold: float,
    reflectance_threshold: float,
) -> dict[str, object]:
    zd = import_zdisamar()
    case = build_o2a_case(zd, jacobian_reference_layer=True)
    library = require_library(library_path)
    reflectance_reference = load_reference(reflectance_reference_path)
    forward_reference = load_reference(forward_reference_path)

    with zd.prepare(case, library_path=library) as prepared:
        spectrum_start = time.perf_counter()
        spectrum = prepared.forward_model()
        spectrum_forward_s = time.perf_counter() - spectrum_start
        forward_wavelengths = spectrum.wavelength_nm.copy()
        forward_radiance = spectrum.radiance.copy()
        forward_irradiance = spectrum.irradiance.copy()
        spectrum.close()

        jacobian_start = time.perf_counter()
        jacobian_spectrum = prepared.forward_model(jacobian=True)
        jacobian_forward_s = time.perf_counter() - jacobian_start
        wavelengths = jacobian_spectrum.wavelength_nm.copy()
        jacobian_irradiance = jacobian_spectrum.irradiance.copy()
        jacobian = jacobian_spectrum.radiance_jacobian.copy()
        jacobian_spectrum.close()

    mask = (wavelengths >= float(reflectance_reference["wavelength_nm"][0])) & (
        wavelengths <= float(reflectance_reference["wavelength_nm"][-1])
    )
    reflectance_jacobian = reflectance_jacobian_from_radiance(
        case,
        jacobian,
        jacobian_irradiance,
    )
    current_dtype = [("wavelength_nm", np.float64)] + [(state, np.float64) for state in STATE_NAMES]
    reflectance_current = np.empty(int(np.count_nonzero(mask)), dtype=current_dtype)
    reflectance_current["wavelength_nm"] = wavelengths[mask]
    for index, state_name in enumerate(STATE_NAMES):
        reflectance_current[state_name] = reflectance_jacobian[mask, index]

    reflectance_residuals = max_abs_residual(reflectance_current, reflectance_reference)
    forward_residuals = forward_max_abs_residual(
        forward_wavelengths,
        forward_radiance,
        forward_irradiance,
        forward_reference,
    )
    max_reflectance_residual = max(reflectance_residuals.values())
    max_forward_residual = max(forward_residuals.values())
    ratio = jacobian_forward_s / spectrum_forward_s if spectrum_forward_s > 0.0 else float("inf")
    summary = {
        "sample_count": int(wavelengths.size),
        "reference_sample_count": int(reflectance_reference.size),
        "comparison_sample_count": int(reflectance_current.size),
        "state_names": list(STATE_NAMES),
        "reflectance_max_abs_residual": reflectance_residuals,
        "forward_max_abs_residual": forward_residuals,
        "passes_forward_threshold": bool(max_forward_residual <= threshold),
        "passes_reflectance_jacobian_threshold": bool(
            max_reflectance_residual <= reflectance_threshold
        ),
        "passes_threshold": bool(
            max_forward_residual <= threshold and max_reflectance_residual <= reflectance_threshold
        ),
        "threshold": threshold,
        "reflectance_threshold": reflectance_threshold,
        "timing": {
            "spectrum_forward_s": spectrum_forward_s,
            "spectrum_jacobian_forward_s": jacobian_forward_s,
            "jacobian_to_spectrum_ratio": ratio,
        },
        "artifacts": {
            "json": str(SUMMARY_OUTPUT),
            "reflectance_reference": str(reflectance_reference_path),
            "forward_reference": str(forward_reference_path),
        },
    }
    SUMMARY_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    SUMMARY_OUTPUT.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--library", type=Path, default=LIBRARY_PATH)
    parser.add_argument("--reflectance-reference", type=Path, default=REFLECTANCE_REFERENCE_PATH)
    parser.add_argument("--forward-reference", type=Path, default=FORWARD_REFERENCE_PATH)
    parser.add_argument("--threshold", type=float, default=1.0e1)
    parser.add_argument("--reflectance-threshold", type=float, default=1.0e-13)
    parser.add_argument("--enforce", action="store_true")
    args = parser.parse_args()

    summary = run_summary(
        args.library,
        args.reflectance_reference,
        args.forward_reference,
        args.threshold,
        args.reflectance_threshold,
    )
    timing = summary["timing"]
    reflectance_residuals = summary["reflectance_max_abs_residual"]
    forward_residuals = summary["forward_max_abs_residual"]
    print(
        "jacobian_summary="
        f"{SUMMARY_OUTPUT} n={summary['sample_count']} "
        f"ratio={timing['jacobian_to_spectrum_ratio']:.3f} "
        f"reflectance_max_abs={max(reflectance_residuals.values()):.3e} "
        f"forward_radiance_max_abs={forward_residuals['radiance']:.3e}"
    )
    if args.enforce and not summary["passes_threshold"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
