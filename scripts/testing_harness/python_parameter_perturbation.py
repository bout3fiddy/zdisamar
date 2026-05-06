#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "numpy>=2.2",
# ]
# ///

from __future__ import annotations

import csv
import json
import sys
import time
from dataclasses import asdict
from pathlib import Path

import numpy as np
from o2a_python_case import build_o2a_case

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
OUT_DIR = REPO_ROOT / "out" / "ci"
LIBRARY_NAME = "libzdisamar_c.dylib" if sys.platform == "darwin" else "libzdisamar_c.so"
LIBRARY_PATH = REPO_ROOT / "zig-out" / "lib" / LIBRARY_NAME
TABLE_OUTPUT = OUT_DIR / "python_parameter_perturbation.csv"
QUESTIONS_OUTPUT = OUT_DIR / "python_parameter_perturbation_questions.json"
PERTURBATION_SAMPLE_COUNT = 141


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


def scalar(value):
    item = value.item() if hasattr(value, "item") else value
    if isinstance(item, float) and not np.isfinite(item):
        return None
    return item


def write_csv(path: Path, results) -> None:
    fields = [
        "label",
        "parameter_path",
        "wavelength_nm",
        "baseline_reflectance",
        "perturbed_reflectance",
        "delta_reflectance",
        "abs_delta_reflectance",
        "baseline_radiance",
        "perturbed_radiance",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for result in results:
            for row in result.table:
                writer.writerow(
                    {
                        "label": result.summary.label,
                        "parameter_path": result.summary.parameter_path,
                        **{name: scalar(row[name]) for name in result.columns},
                    }
                )


def top_wavelengths(result, count: int = 10) -> list[dict[str, float]]:
    order = np.argsort(result.table["abs_delta_reflectance"])[::-1][:count]
    return [
        {
            "wavelength_nm": float(result.table["wavelength_nm"][index]),
            "delta_reflectance": float(result.table["delta_reflectance"][index]),
            "abs_delta_reflectance": float(result.table["abs_delta_reflectance"][index]),
        }
        for index in order
    ]


def answer_questions(results) -> list[dict[str, object]]:
    by_label = {result.summary.label: result for result in results}
    return [
        {
            "question": "Which wavelengths are most sensitive to aerosol optical depth?",
            "answer": {
                "summary": asdict(by_label["aerosol optical depth +10%"].summary),
                "top_wavelengths": top_wavelengths(by_label["aerosol optical depth +10%"]),
            },
            "output": "parameter perturbation reflectance-delta table",
        },
        {
            "question": "Which wavelengths are most sensitive to the line-mixing factor?",
            "answer": {
                "summary": asdict(by_label["line mixing factor 0.5"].summary),
                "top_wavelengths": top_wavelengths(by_label["line mixing factor 0.5"]),
            },
            "output": "parameter perturbation reflectance-delta table",
        },
        {
            "question": (
                "Does collision-induced absorption change the apparent "
                "continuum or specific O2 A-band structures?"
            ),
            "answer": {
                "summary": asdict(by_label["collision-induced absorption disabled"].summary),
                "top_wavelengths": top_wavelengths(
                    by_label["collision-induced absorption disabled"]
                ),
            },
            "output": "parameter perturbation reflectance-delta table",
        },
        {
            "question": "How does changing FWHM change the apparent O2 A-band depth?",
            "answer": {
                "summary": asdict(by_label["instrument FWHM +10%"].summary),
                "top_wavelengths": top_wavelengths(by_label["instrument FWHM +10%"]),
            },
            "output": "parameter perturbation reflectance-delta table",
        },
        {
            "question": (
                "Does multiple scattering materially change reflectance in a selected band?"
            ),
            "answer": {
                "summary": asdict(by_label["single scattering"].summary),
                "top_wavelengths": top_wavelengths(by_label["single scattering"]),
            },
            "output": "parameter perturbation reflectance-delta table",
        },
    ]


def run_parameter_perturbations() -> dict[str, object]:
    library_path = require_library()
    zd = import_zdisamar()
    case = build_o2a_case(zd)
    case.spectral_grid.sample_count = PERTURBATION_SAMPLE_COUNT

    perturbations = [
        {
            "label": "aerosol optical depth +10%",
            "parameter_path": "aerosol.optical_depth_550_nm",
            "value": case.aerosol.optical_depth_550_nm * 1.1,
        },
        {
            "label": "line mixing factor 0.5",
            "parameter_path": "o2_lines.line_mixing_factor",
            "value": 0.5,
        },
        {
            "label": "collision-induced absorption disabled",
            "parameter_path": "collision_induced_absorption.enabled",
            "value": False,
        },
        {
            "label": "instrument FWHM +10%",
            "parameter_path": "instrument_response.instrument_line_fwhm_nm",
            "value": case.instrument_response.instrument_line_fwhm_nm * 1.1,
        },
        {
            "label": "single scattering",
            "parameter_path": "radiative_transfer.scattering",
            "value": "single",
        },
    ]

    total_start = time.perf_counter()
    prepare_start = time.perf_counter()
    with zd.prepare(case, library_path=library_path) as prepared:
        prepare_s = time.perf_counter() - prepare_start
        perturb_start = time.perf_counter()
        results = prepared.perturbations.spectrum_deltas(perturbations)
        perturb_s = time.perf_counter() - perturb_start

    questions = answer_questions(results)
    write_start = time.perf_counter()
    write_csv(TABLE_OUTPUT, results)
    write_s = time.perf_counter() - write_start

    summary = {
        "row_count": int(sum(result.row_count for result in results)),
        "spectrum_sample_count": PERTURBATION_SAMPLE_COUNT,
        "perturbations": [asdict(result.summary) for result in results],
        "questions": questions,
        "artifacts": {
            "table_csv": str(TABLE_OUTPUT),
            "json": str(QUESTIONS_OUTPUT),
        },
        "timing": {
            "prepare_o2a_s": prepare_s,
            "perturbations_s": perturb_s,
            "write_s": write_s,
            "total_s": time.perf_counter() - total_start,
        },
    }
    QUESTIONS_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    QUESTIONS_OUTPUT.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return summary


def main() -> int:
    summary = run_parameter_perturbations()
    timing = summary["timing"]
    strongest = max(summary["perturbations"], key=lambda item: item["max_abs_delta_reflectance"])
    print(
        f"perturbations={TABLE_OUTPUT} "
        f"questions={len(summary['questions'])} rows={summary['row_count']} "
        f"strongest={strongest['label']}:{strongest['max_abs_delta_reflectance']:.3e}"
        f"@{strongest['max_abs_delta_wavelength_nm']:.2f}nm "
        f"prepare={timing['prepare_o2a_s']:.2f}s perturb={timing['perturbations_s']:.2f}s "
        f"total={timing['total_s']:.2f}s"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
