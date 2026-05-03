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
from pathlib import Path
import sys
import time

import numpy as np

from o2a_python_case import build_o2a_case


REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
OUT_DIR = REPO_ROOT / "out" / "ci"
LIBRARY_NAME = "libzdisamar_c.dylib" if sys.platform == "darwin" else "libzdisamar_c.so"
LIBRARY_PATH = REPO_ROOT / "zig-out" / "lib" / LIBRARY_NAME
BUDGET_OUTPUT = OUT_DIR / "python_atmosphere_budget.csv"
SUMMARY_OUTPUT = OUT_DIR / "python_atmosphere_budget_questions.json"


def require_library() -> str:
    if not LIBRARY_PATH.exists():
        raise FileNotFoundError(f"{LIBRARY_PATH} does not exist; build the native shared library first")
    return str(LIBRARY_PATH)


def import_zdisamar():
    sys.path.insert(0, str(PYTHON_ROOT))
    import zdisamar as zd

    return zd


def sampled_wavelengths(case) -> np.ndarray:
    return np.linspace(
        case.spectral_grid.start_nm,
        case.spectral_grid.end_nm,
        case.spectral_grid.sample_count,
        dtype=np.float64,
    )


def spectral_sums(table, wavelengths: np.ndarray) -> dict[str, np.ndarray]:
    rows_per_wavelength = table.size // wavelengths.size
    if rows_per_wavelength * wavelengths.size != table.size:
        raise ValueError("budget table is not grouped by wavelength")

    def sum_column(name: str) -> np.ndarray:
        return table[name].reshape(wavelengths.size, rows_per_wavelength).sum(axis=1)

    return {
        "gas_absorption_optical_depth": sum_column("gas_absorption_optical_depth"),
        "gas_scattering_optical_depth": sum_column("gas_scattering_optical_depth"),
        "cia_optical_depth": sum_column("cia_optical_depth"),
        "aerosol_optical_depth": sum_column("aerosol_optical_depth"),
        "aerosol_scattering_optical_depth": sum_column("aerosol_scattering_optical_depth"),
        "total_scattering_optical_depth": sum_column("total_scattering_optical_depth"),
        "total_optical_depth": sum_column("total_optical_depth"),
    }


def safe_share(numerator: np.ndarray, denominator: np.ndarray) -> np.ndarray:
    return np.divide(
        numerator,
        denominator,
        out=np.zeros_like(numerator, dtype=np.float64),
        where=denominator > 0.0,
    )


def strongest_interval(table) -> dict[str, float | int]:
    intervals = np.unique(table["interval_index_1based"])
    interval_totals = []
    for interval in intervals:
        mask = table["interval_index_1based"] == interval
        interval_totals.append(float(np.sum(table["aerosol_optical_depth"][mask])))
    totals = np.array(interval_totals, dtype=np.float64)
    best_index = int(np.argmax(totals))
    total_aerosol = float(np.sum(totals))
    return {
        "interval_index_1based": int(intervals[best_index]),
        "aerosol_optical_depth_sum": float(totals[best_index]),
        "share_of_aerosol_optical_depth": float(totals[best_index] / total_aerosol),
    }


def answer_questions(table, wavelengths: np.ndarray) -> list[dict[str, object]]:
    sums = spectral_sums(table, wavelengths)
    aerosol_total_share = safe_share(
        sums["aerosol_optical_depth"],
        sums["total_optical_depth"],
    )
    aerosol_scattering_share = safe_share(
        sums["aerosol_scattering_optical_depth"],
        sums["total_scattering_optical_depth"],
    )

    total_index = int(np.argmax(aerosol_total_share))
    scattering_index = int(np.argmax(aerosol_scattering_share))
    return [
        {
            "question": "Which sampled wavelength has the largest aerosol share of total optical depth?",
            "answer": {
                "wavelength_nm": float(wavelengths[total_index]),
                "aerosol_share_of_total_optical_depth": float(aerosol_total_share[total_index]),
                "aerosol_optical_depth": float(sums["aerosol_optical_depth"][total_index]),
                "total_optical_depth": float(sums["total_optical_depth"][total_index]),
            },
            "output": "atmospheric layer and optical-property budget table",
        },
        {
            "question": "Which sampled wavelength has the largest aerosol share of scattering optical depth?",
            "answer": {
                "wavelength_nm": float(wavelengths[scattering_index]),
                "aerosol_share_of_scattering_optical_depth": float(aerosol_scattering_share[scattering_index]),
                "aerosol_scattering_optical_depth": float(
                    sums["aerosol_scattering_optical_depth"][scattering_index]
                ),
                "total_scattering_optical_depth": float(
                    sums["total_scattering_optical_depth"][scattering_index]
                ),
            },
            "output": "atmospheric layer and optical-property budget table",
        },
        {
            "question": "Which atmospheric interval contributes most to the aerosol signal?",
            "answer": strongest_interval(table),
            "output": "interval-resolved atmospheric layer and optical-property budget table",
        },
    ]


def write_budget_csv(path: Path, table) -> None:
    support_row_kind_labels = {
        0: "physical",
        1: "parity_boundary",
        2: "parity_active",
    }
    subcolumn_label_labels = {
        0: "unspecified",
        1: "boundary_layer",
        2: "free_troposphere",
        3: "fit_interval",
        4: "stratosphere",
    }
    fields = list(table.dtype.names or ())
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=fields + ["support_row_kind_label", "subcolumn_label_label"],
        )
        writer.writeheader()
        for row in table:
            item = {name: row[name].item() for name in fields}
            item["support_row_kind_label"] = support_row_kind_labels.get(
                int(item["support_row_kind"]),
                "unknown",
            )
            item["subcolumn_label_label"] = subcolumn_label_labels.get(
                int(item["subcolumn_label"]),
                "unknown",
            )
            writer.writerow(item)


def run_atmosphere_budget() -> dict[str, object]:
    library_path = require_library()
    zd = import_zdisamar()
    case = build_o2a_case(zd)
    wavelengths = sampled_wavelengths(case)

    total_start = time.perf_counter()
    prepare_start = time.perf_counter()
    with zd.prepare(case, library_path=library_path) as prepared:
        prepare_s = time.perf_counter() - prepare_start
        budget_start = time.perf_counter()
        with prepared.atmosphere.budget(wavelengths_nm=wavelengths) as budget:
            table = budget.table.copy()
        budget_s = time.perf_counter() - budget_start

    questions = answer_questions(table, wavelengths)
    write_start = time.perf_counter()
    write_budget_csv(BUDGET_OUTPUT, table)
    write_s = time.perf_counter() - write_start

    summary = {
        "row_count": int(table.size),
        "wavelength_count": int(wavelengths.size),
        "questions": questions,
        "artifacts": {
            "budget_csv": str(BUDGET_OUTPUT),
            "json": str(SUMMARY_OUTPUT),
        },
        "timing": {
            "prepare_o2a_s": prepare_s,
            "budget_s": budget_s,
            "write_s": write_s,
            "total_s": time.perf_counter() - total_start,
        },
    }
    SUMMARY_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    SUMMARY_OUTPUT.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return summary


def main() -> int:
    summary = run_atmosphere_budget()
    timing = summary["timing"]
    questions = summary["questions"]
    total_share = questions[0]["answer"]
    scattering_share = questions[1]["answer"]
    interval = questions[2]["answer"]
    print(
        f"budget={BUDGET_OUTPUT} questions={len(questions)} rows={summary['row_count']} "
        f"max_aerosol_total_share={total_share['aerosol_share_of_total_optical_depth']:.6g}"
        f"@{total_share['wavelength_nm']:.2f}nm "
        f"max_aerosol_scattering_share={scattering_share['aerosol_share_of_scattering_optical_depth']:.6g}"
        f"@{scattering_share['wavelength_nm']:.2f}nm "
        f"aerosol_interval={interval['interval_index_1based']} "
        f"prepare={timing['prepare_o2a_s']:.2f}s budget={timing['budget_s']:.2f}s "
        f"total={timing['total_s']:.2f}s"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
