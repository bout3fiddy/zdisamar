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
TABLE_OUTPUT = OUT_DIR / "python_collision_induced_absorption_diagnostics.csv"
QUESTIONS_OUTPUT = OUT_DIR / "python_collision_induced_absorption_questions.json"
VALIDATION_GRID_STRIDE = 5


def require_library() -> str:
    if not LIBRARY_PATH.exists():
        raise FileNotFoundError(f"{LIBRARY_PATH} does not exist; build the native shared library first")
    return str(LIBRARY_PATH)


def import_zdisamar():
    sys.path.insert(0, str(PYTHON_ROOT))
    import zdisamar as zd

    return zd


def sampled_wavelengths(case) -> np.ndarray:
    grid = np.linspace(
        case.spectral_grid.start_nm,
        case.spectral_grid.end_nm,
        case.spectral_grid.sample_count,
        dtype=np.float64,
    )
    return grid[::VALIDATION_GRID_STRIDE]


def scalar(value):
    item = value.item() if hasattr(value, "item") else value
    if isinstance(item, float) and not np.isfinite(item):
        return None
    return item


def write_csv(path: Path, table) -> None:
    fields = list(table.dtype.names or ())
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for row in table:
            writer.writerow({name: scalar(row[name]) for name in fields})


def spectral_sums(table, wavelengths: np.ndarray) -> dict[str, np.ndarray]:
    rows_per_wavelength = table.size // wavelengths.size
    if rows_per_wavelength * wavelengths.size != table.size:
        raise ValueError("collision-induced absorption table is not grouped by wavelength")

    def sum_column(name: str) -> np.ndarray:
        return table[name].reshape(wavelengths.size, rows_per_wavelength).sum(axis=1)

    return {
        "cia_optical_depth": sum_column("cia_optical_depth"),
        "total_absorption_optical_depth": sum_column("total_absorption_optical_depth"),
        "total_optical_depth": sum_column("total_optical_depth"),
    }


def interval_totals(table) -> list[dict[str, object]]:
    intervals = np.unique(table["interval_index_1based"])
    rows = []
    total = float(np.sum(table["cia_optical_depth"]))
    for interval in intervals:
        mask = table["interval_index_1based"] == interval
        value = float(np.sum(table["cia_optical_depth"][mask]))
        rows.append(
            {
                "interval_index_1based": int(interval),
                "cia_optical_depth_sum": value,
                "share": 0.0 if total == 0.0 else value / total,
            }
        )
    rows.sort(key=lambda item: item["cia_optical_depth_sum"], reverse=True)
    return rows


def temperature_split(table) -> dict[str, float]:
    active = table[table["cia_optical_depth"] > 0.0]
    if active.size == 0:
        return {
            "median_temperature_k": 0.0,
            "warm_mean_cia_cross_section_cm5_per_molecule2": 0.0,
            "cold_mean_cia_cross_section_cm5_per_molecule2": 0.0,
            "cold_to_warm_cross_section_ratio": 0.0,
        }
    median = float(np.median(active["temperature_k"]))
    warm = active[active["temperature_k"] >= median]
    cold = active[active["temperature_k"] < median]
    warm_mean = float(np.mean(warm["cia_cross_section_cm5_per_molecule2"])) if warm.size else 0.0
    cold_mean = float(np.mean(cold["cia_cross_section_cm5_per_molecule2"])) if cold.size else 0.0
    return {
        "median_temperature_k": median,
        "warm_mean_cia_cross_section_cm5_per_molecule2": warm_mean,
        "cold_mean_cia_cross_section_cm5_per_molecule2": cold_mean,
        "cold_to_warm_cross_section_ratio": 0.0 if warm_mean == 0.0 else cold_mean / warm_mean,
    }


def answer_questions(table, wavelengths: np.ndarray) -> list[dict[str, object]]:
    sums = spectral_sums(table, wavelengths)
    cia_abs_share = np.divide(
        sums["cia_optical_depth"],
        sums["total_absorption_optical_depth"],
        out=np.zeros_like(sums["cia_optical_depth"]),
        where=sums["total_absorption_optical_depth"] > 0.0,
    )
    cia_total_share = np.divide(
        sums["cia_optical_depth"],
        sums["total_optical_depth"],
        out=np.zeros_like(sums["cia_optical_depth"]),
        where=sums["total_optical_depth"] > 0.0,
    )
    best_abs = int(np.argmax(cia_abs_share))
    best_total = int(np.argmax(cia_total_share))
    intervals = interval_totals(table)
    return [
        {
            "question": "Where does O2-O2 collision-induced absorption contribute most to total absorption?",
            "answer": {
                "wavelength_nm": float(wavelengths[best_abs]),
                "cia_share_of_total_absorption": float(cia_abs_share[best_abs]),
                "cia_optical_depth": float(sums["cia_optical_depth"][best_abs]),
                "total_absorption_optical_depth": float(sums["total_absorption_optical_depth"][best_abs]),
            },
            "output": "O2-O2 collision-induced absorption diagnostic table",
        },
        {
            "question": "Where does O2-O2 collision-induced absorption contribute most to total optical depth?",
            "answer": {
                "wavelength_nm": float(wavelengths[best_total]),
                "cia_share_of_total_optical_depth": float(cia_total_share[best_total]),
                "cia_optical_depth": float(sums["cia_optical_depth"][best_total]),
                "total_optical_depth": float(sums["total_optical_depth"][best_total]),
            },
            "output": "O2-O2 collision-induced absorption diagnostic table",
        },
        {
            "question": "Which atmospheric intervals dominate collision-induced absorption optical depth?",
            "answer": {
                "ranked_intervals": intervals,
                "dominant_interval": intervals[0] if intervals else None,
            },
            "output": "interval-resolved O2-O2 collision-induced absorption diagnostic table",
        },
        {
            "question": "How does the collision-induced absorption cross section change with temperature in this case?",
            "answer": temperature_split(table),
            "output": "temperature-resolved O2-O2 collision-induced absorption diagnostic table",
        },
    ]


def run_collision_induced_absorption_diagnostics() -> dict[str, object]:
    library_path = require_library()
    zd = import_zdisamar()
    case = build_o2a_case(zd)
    wavelengths = sampled_wavelengths(case)

    total_start = time.perf_counter()
    prepare_start = time.perf_counter()
    with zd.prepare(case, library_path=library_path) as prepared:
        prepare_s = time.perf_counter() - prepare_start
        diagnostics_start = time.perf_counter()
        table = prepared.collision_induced_absorption.diagnostics(wavelengths_nm=wavelengths).table
        diagnostics_s = time.perf_counter() - diagnostics_start

    questions = answer_questions(table, wavelengths)
    write_start = time.perf_counter()
    write_csv(TABLE_OUTPUT, table)
    write_s = time.perf_counter() - write_start

    summary = {
        "row_count": int(table.size),
        "wavelength_count": int(wavelengths.size),
        "questions": questions,
        "artifacts": {
            "table_csv": str(TABLE_OUTPUT),
            "json": str(QUESTIONS_OUTPUT),
        },
        "timing": {
            "prepare_o2a_s": prepare_s,
            "diagnostics_s": diagnostics_s,
            "write_s": write_s,
            "total_s": time.perf_counter() - total_start,
        },
    }
    QUESTIONS_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    QUESTIONS_OUTPUT.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return summary


def main() -> int:
    summary = run_collision_induced_absorption_diagnostics()
    timing = summary["timing"]
    answer = summary["questions"][0]["answer"]
    interval = summary["questions"][2]["answer"]["dominant_interval"]
    print(
        f"collision_induced_absorption={TABLE_OUTPUT} questions={len(summary['questions'])} rows={summary['row_count']} "
        f"max_abs_share={answer['cia_share_of_total_absorption']:.6g}@{answer['wavelength_nm']:.2f}nm "
        f"dominant_interval={interval['interval_index_1based']} "
        f"prepare={timing['prepare_o2a_s']:.2f}s diagnostics={timing['diagnostics_s']:.2f}s "
        f"total={timing['total_s']:.2f}s"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
