#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "numpy>=2.2",
# ]
# ///

from __future__ import annotations

import argparse
from dataclasses import asdict
import json
from pathlib import Path
import sys
import time
from typing import Any

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify that the typed Python O2 A setup matches the default DISAMAR parity entrypoint."
    )
    parser.add_argument("--library", help="Path to the zdisamar C-facing shared library.")
    parser.add_argument(
        "--output",
        default="out/ci/python_o2a_setup_roundtrip.json",
        help="JSON report path. Defaults to out/ci/python_o2a_setup_roundtrip.json.",
    )
    return parser.parse_args()


def spectrum_arrays(spectrum: Any) -> dict[str, np.ndarray]:
    return {
        "wavelength_nm": spectrum.wavelength_nm.copy(),
        "radiance": spectrum.radiance.copy(),
        "irradiance": spectrum.irradiance.copy(),
        "reflectance": spectrum.reflectance.copy(),
    }


def run_roundtrip(library_path: str | None) -> dict[str, Any]:
    sys.path.insert(0, str(PYTHON_ROOT))
    import zdisamar as zd

    tolerance = 1.0e-12
    start_s = time.perf_counter()

    input_start_s = time.perf_counter()
    case = zd.o2a_disamar_reference_input(library_path)
    input_s = time.perf_counter() - input_start_s

    typed_prepare_start_s = time.perf_counter()
    with zd.prepare(case, library_path=library_path) as prepared:
        typed_prepare_s = time.perf_counter() - typed_prepare_start_s
        typed_forward_start_s = time.perf_counter()
        typed_spectrum = prepared.forward_model()
        typed_forward_s = time.perf_counter() - typed_forward_start_s
        typed_report = typed_spectrum.diagnostic_report
        typed_arrays = spectrum_arrays(typed_spectrum)
        typed_spectrum.close()

    default_prepare_start_s = time.perf_counter()
    with zd.prepare_default_o2a(library_path) as prepared:
        default_prepare_s = time.perf_counter() - default_prepare_start_s
        default_forward_start_s = time.perf_counter()
        default_spectrum = prepared.forward_model()
        default_forward_s = time.perf_counter() - default_forward_start_s
        default_report = default_spectrum.diagnostic_report
        default_arrays = spectrum_arrays(default_spectrum)
        default_spectrum.close()

    checks = {
        "typed_sample_count": int(typed_arrays["wavelength_nm"].size),
        "default_sample_count": int(default_arrays["wavelength_nm"].size),
        "sample_counts_match": bool(typed_arrays["wavelength_nm"].size == default_arrays["wavelength_nm"].size),
        "typed_report_matches_arrays": bool(
            typed_report.sample_count == typed_arrays["wavelength_nm"].size
            and np.isclose(typed_report.mean_reflectance, np.mean(typed_arrays["reflectance"]), atol=tolerance, rtol=tolerance)
        ),
        "default_report_matches_arrays": bool(
            default_report.sample_count == default_arrays["wavelength_nm"].size
            and np.isclose(default_report.mean_reflectance, np.mean(default_arrays["reflectance"]), atol=tolerance, rtol=tolerance)
        ),
        "default_matches_typed_arrays": bool(
            np.allclose(default_arrays["wavelength_nm"], typed_arrays["wavelength_nm"], atol=tolerance, rtol=tolerance)
            and np.allclose(default_arrays["radiance"], typed_arrays["radiance"], atol=tolerance, rtol=tolerance)
            and np.allclose(default_arrays["irradiance"], typed_arrays["irradiance"], atol=tolerance, rtol=tolerance)
            and np.allclose(default_arrays["reflectance"], typed_arrays["reflectance"], atol=tolerance, rtol=tolerance)
        ),
        "parity_route_used": True,
        "tolerance": tolerance,
    }

    return {
        "question": "Does the typed Python O2 A setup match the default DISAMAR parity entrypoint?",
        "answer": {
            "matches": checks["default_matches_typed_arrays"],
            "sample_count": checks["typed_sample_count"],
        },
        "typed_diagnostic_report": asdict(typed_report),
        "default_diagnostic_report": asdict(default_report),
        "checks": checks,
        "timing": {
            "o2a_input_s": input_s,
            "typed_prepare_s": typed_prepare_s,
            "typed_forward_s": typed_forward_s,
            "default_prepare_s": default_prepare_s,
            "default_forward_s": default_forward_s,
            "total_s": time.perf_counter() - start_s,
        },
    }


def main() -> int:
    args = parse_args()
    output_path = Path(args.output)
    summary = run_roundtrip(args.library)
    summary["artifacts"] = {"json": str(output_path)}
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    checks = summary["checks"]
    print(summary["question"])
    print(f"answer: matches={summary['answer']['matches']}, sample_count={summary['answer']['sample_count']}")
    print(
        "checks: "
        f"sample_counts_match={checks['sample_counts_match']}, "
        f"typed_report_matches_arrays={checks['typed_report_matches_arrays']}, "
        f"default_report_matches_arrays={checks['default_report_matches_arrays']}, "
        f"default_matches_typed_arrays={checks['default_matches_typed_arrays']}"
    )
    print(f"json: {output_path}")
    passed = all(value for key, value in checks.items() if key not in {"tolerance", "typed_sample_count", "default_sample_count"})
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
