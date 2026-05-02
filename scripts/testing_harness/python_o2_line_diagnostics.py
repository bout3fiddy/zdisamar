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
TABLE_OUTPUT = OUT_DIR / "python_o2_line_contributions.csv"
QUESTIONS_OUTPUT = OUT_DIR / "python_o2_line_questions.json"
TARGET_WAVELENGTHS_NM = np.array([760.0, 760.76, 761.0], dtype=np.float64)
MAX_ROWS = 100_000
TOP_ROW_COUNT = 10
MISSING_INDEX = np.iinfo(np.uint32).max

ROW_KIND_LABELS = {
    0: "weak_line",
    1: "strong_line",
}
STATUS_LABELS = {
    0: "weak_included",
    1: "weak_excluded_by_strong_line",
    2: "strong_sidecar",
    3: "weak_zero_after_cutoff",
}


def require_library() -> str:
    if not LIBRARY_PATH.exists():
        raise FileNotFoundError(f"{LIBRARY_PATH} does not exist; build the native shared library first")
    return str(LIBRARY_PATH)


def import_zdisamar():
    sys.path.insert(0, str(PYTHON_ROOT))
    import zdisamar as zd

    return zd


def validation_grid_wavelengths(case) -> np.ndarray:
    grid = np.linspace(
        case.spectral_grid.start_nm,
        case.spectral_grid.end_nm,
        case.spectral_grid.sample_count,
        dtype=np.float64,
    )
    indexes = np.unique([int(np.argmin(np.abs(grid - target))) for target in TARGET_WAVELENGTHS_NM])
    return grid[indexes]


def scalar(value):
    item = value.item() if hasattr(value, "item") else value
    if isinstance(item, float) and not np.isfinite(item):
        return None
    return item


def label_row(row) -> dict[str, object]:
    return {
        "wavelength_nm": scalar(row["wavelength_nm"]),
        "profile_node_index": None
        if int(row["profile_node_index"]) == MISSING_INDEX
        else int(row["profile_node_index"]),
        "altitude_km": scalar(row["altitude_km"]),
        "row_kind": ROW_KIND_LABELS.get(int(row["row_kind"]), "unknown"),
        "status": STATUS_LABELS.get(int(row["status"]), "unknown"),
        "line_index": None if int(row["line_index"]) == MISSING_INDEX else int(row["line_index"]),
        "strong_line_index": None
        if int(row["strong_line_index"]) == MISSING_INDEX
        else int(row["strong_line_index"]),
        "matched_strong_line_index": None
        if int(row["matched_strong_line_index"]) == MISSING_INDEX
        else int(row["matched_strong_line_index"]),
        "gas_index": int(row["gas_index"]),
        "isotope_number": int(row["isotope_number"]),
        "isotopologue_code": int(row["isotopologue_code"]),
        "center_wavelength_nm": scalar(row["center_wavelength_nm"]),
        "center_wavenumber_cm1": scalar(row["center_wavenumber_cm1"]),
        "shifted_center_wavenumber_cm1": scalar(row["shifted_center_wavenumber_cm1"]),
        "line_strength_cm2_per_molecule": scalar(row["line_strength_cm2_per_molecule"]),
        "air_half_width_cm1": scalar(row["air_half_width_cm1"]),
        "pressure_shift_cm1": scalar(row["pressure_shift_cm1"]),
        "lower_state_energy_cm1": scalar(row["lower_state_energy_cm1"]),
        "weak_line_sigma_cm2_per_molecule": scalar(row["weak_line_sigma_cm2_per_molecule"]),
        "strong_line_sigma_cm2_per_molecule": scalar(row["strong_line_sigma_cm2_per_molecule"]),
        "line_mixing_sigma_cm2_per_molecule": scalar(row["line_mixing_sigma_cm2_per_molecule"]),
        "total_sigma_cm2_per_molecule": scalar(row["total_sigma_cm2_per_molecule"]),
        "abs_total_sigma_cm2_per_molecule": scalar(row["abs_total_sigma_cm2_per_molecule"]),
    }


def top_contribution_rows(table) -> list[dict[str, object]]:
    order = np.argsort(table["abs_total_sigma_cm2_per_molecule"])[::-1]
    return [label_row(table[index]) for index in order[:TOP_ROW_COUNT]]


def status_counts(table) -> list[dict[str, object]]:
    pairs = np.stack([table["row_kind"], table["status"]], axis=1)
    unique_pairs, counts = np.unique(pairs, axis=0, return_counts=True)
    rows = []
    for pair, count in zip(unique_pairs, counts, strict=True):
        row_kind = int(pair[0])
        status = int(pair[1])
        rows.append(
            {
                "row_kind": ROW_KIND_LABELS.get(row_kind, "unknown"),
                "status": STATUS_LABELS.get(status, "unknown"),
                "row_count": int(count),
            }
        )
    return rows


def isotope_totals(table) -> list[dict[str, object]]:
    isotopes = np.unique(table["isotope_number"])
    rows = []
    for isotope in isotopes:
        mask = table["isotope_number"] == isotope
        rows.append(
            {
                "isotope_number": int(isotope),
                "abs_total_sigma_sum_cm2_per_molecule": float(
                    np.sum(table["abs_total_sigma_cm2_per_molecule"][mask])
                ),
                "row_count": int(np.count_nonzero(mask)),
            }
        )
    rows.sort(key=lambda item: item["abs_total_sigma_sum_cm2_per_molecule"], reverse=True)
    return rows


def cross_section_partition(table) -> dict[str, float]:
    weak_abs = float(np.sum(np.abs(table["weak_line_sigma_cm2_per_molecule"])))
    strong_abs = float(np.sum(np.abs(table["strong_line_sigma_cm2_per_molecule"])))
    line_mixing_abs = float(np.sum(np.abs(table["line_mixing_sigma_cm2_per_molecule"])))
    total_abs = float(np.sum(table["abs_total_sigma_cm2_per_molecule"]))
    denominator = weak_abs + strong_abs + line_mixing_abs
    return {
        "weak_line_abs_sum_cm2_per_molecule": weak_abs,
        "strong_line_abs_sum_cm2_per_molecule": strong_abs,
        "line_mixing_abs_sum_cm2_per_molecule": line_mixing_abs,
        "total_abs_sum_cm2_per_molecule": total_abs,
        "weak_line_abs_share": 0.0 if denominator == 0.0 else weak_abs / denominator,
        "strong_line_abs_share": 0.0 if denominator == 0.0 else strong_abs / denominator,
        "line_mixing_abs_share": 0.0 if denominator == 0.0 else line_mixing_abs / denominator,
    }


def answer_questions(table, wavelengths: np.ndarray) -> list[dict[str, object]]:
    isotope_rows = isotope_totals(table)
    return [
        {
            "question": "Which O2 lines dominate a selected O2 A trough?",
            "answer": {
                "selected_wavelengths_nm": wavelengths.tolist(),
                "top_rows": top_contribution_rows(table),
            },
            "output": "O2 line contribution table",
        },
        {
            "question": "Which weak lines are included, excluded, or handled through strong-line data?",
            "answer": {
                "status_counts": status_counts(table),
            },
            "output": "O2 line inclusion and strong-line status columns",
        },
        {
            "question": "Which isotope contributes most in the selected wavelength region?",
            "answer": {
                "ranked_isotopes": isotope_rows,
                "dominant_isotope": isotope_rows[0] if isotope_rows else None,
            },
            "output": "isotope-resolved O2 line contribution table",
        },
        {
            "question": "How much of the cross section comes from weak lines, strong lines, and line mixing?",
            "answer": cross_section_partition(table),
            "output": "weak, strong, and line-mixing contribution columns",
        },
    ]


def write_table_csv(path: Path, table) -> None:
    fields = list(table.dtype.names or ())
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields + ["row_kind_label", "status_label"])
        writer.writeheader()
        for row in table:
            item = {name: scalar(row[name]) for name in fields}
            item["row_kind_label"] = ROW_KIND_LABELS.get(int(row["row_kind"]), "unknown")
            item["status_label"] = STATUS_LABELS.get(int(row["status"]), "unknown")
            writer.writerow(item)


def run_o2_line_diagnostics() -> dict[str, object]:
    library_path = require_library()
    zd = import_zdisamar()
    case = build_o2a_case(zd)
    wavelengths = validation_grid_wavelengths(case)

    total_start = time.perf_counter()
    prepare_start = time.perf_counter()
    with zd.prepare(case, library_path=library_path) as prepared:
        prepare_s = time.perf_counter() - prepare_start
        diagnostics_start = time.perf_counter()
        with prepared.o2_lines.contributions(wavelengths_nm=wavelengths, max_rows=MAX_ROWS) as contributions:
            table = contributions.table.copy()
            total_row_count = contributions.total_row_count
            truncated = contributions.truncated
        diagnostics_s = time.perf_counter() - diagnostics_start

    questions = answer_questions(table, wavelengths)
    write_start = time.perf_counter()
    write_table_csv(TABLE_OUTPUT, table)
    write_s = time.perf_counter() - write_start

    summary = {
        "row_count": int(table.size),
        "total_row_count": int(total_row_count),
        "truncated": bool(truncated),
        "selected_wavelengths_nm": wavelengths.tolist(),
        "questions": questions,
        "artifacts": {
            "table_csv": str(TABLE_OUTPUT),
            "json": str(QUESTIONS_OUTPUT),
        },
        "timing": {
            "prepare_o2a_s": prepare_s,
            "o2_line_diagnostics_s": diagnostics_s,
            "write_s": write_s,
            "total_s": time.perf_counter() - total_start,
        },
    }
    QUESTIONS_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    QUESTIONS_OUTPUT.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return summary


def main() -> int:
    summary = run_o2_line_diagnostics()
    timing = summary["timing"]
    top_row = summary["questions"][0]["answer"]["top_rows"][0]
    dominant_isotope = summary["questions"][2]["answer"]["dominant_isotope"]
    print(
        f"o2_lines={TABLE_OUTPUT} questions={len(summary['questions'])} "
        f"rows={summary['row_count']}/{summary['total_row_count']} "
        f"top_center={top_row['center_wavelength_nm']:.5f}nm "
        f"top_kind={top_row['row_kind']} dominant_isotope={dominant_isotope['isotope_number']} "
        f"prepare={timing['prepare_o2a_s']:.2f}s diagnostics={timing['o2_line_diagnostics_s']:.2f}s "
        f"total={timing['total_s']:.2f}s"
    )
    return 1 if summary["truncated"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
