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
from pathlib import Path

import numpy as np
from o2a_python_case import build_o2a_case

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
OUT_DIR = REPO_ROOT / "out" / "ci"
LIBRARY_NAME = "libzdisamar_c.dylib" if sys.platform == "darwin" else "libzdisamar_c.so"
LIBRARY_PATH = REPO_ROOT / "zig-out" / "lib" / LIBRARY_NAME
TABLE_OUTPUT = OUT_DIR / "python_instrument_response.csv"
QUESTIONS_OUTPUT = OUT_DIR / "python_instrument_response_questions.json"
NOMINAL_GRID_STRIDE = 35
CHANNEL_LABELS = {0: "radiance", 1: "irradiance"}


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


def sampled_nominal_wavelengths(case) -> np.ndarray:
    grid = np.linspace(
        case.spectral_grid.start_nm,
        case.spectral_grid.end_nm,
        case.spectral_grid.sample_count,
        dtype=np.float64,
    )
    return grid[::NOMINAL_GRID_STRIDE]


def scalar(value):
    item = value.item() if hasattr(value, "item") else value
    if isinstance(item, float) and not np.isfinite(item):
        return None
    return item


def write_csv(path: Path, table) -> None:
    fields = list(table.dtype.names or ())
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields + ["channel_label"])
        writer.writeheader()
        for row in table:
            item = {name: scalar(row[name]) for name in fields}
            item["channel_label"] = CHANNEL_LABELS.get(int(row["channel"]), "unknown")
            writer.writerow(item)


def answer_questions(table) -> list[dict[str, object]]:
    nominal_wavelengths = np.unique(table["nominal_wavelength_nm"])
    support_widths = []
    support_counts = []
    for wavelength in nominal_wavelengths:
        mask = (table["nominal_wavelength_nm"] == wavelength) & (table["channel"] == 0)
        support_widths.append(float(np.max(table["support_width_nm"][mask])))
        support_counts.append(int(np.max(table["support_count"][mask])))
    support_widths = np.array(support_widths, dtype=np.float64)
    support_counts = np.array(support_counts, dtype=np.int64)
    widest_index = int(np.argmax(support_widths))

    target = 760.76
    target_wavelength = float(
        nominal_wavelengths[int(np.argmin(np.abs(nominal_wavelengths - target)))]
    )
    target_mask = (table["nominal_wavelength_nm"] == target_wavelength) & (table["channel"] == 0)
    target_rows = table[target_mask]
    top_indexes = np.argsort(target_rows["weight"])[::-1][:10]
    top_support = [
        {
            "support_wavelength_nm": float(target_rows["support_wavelength_nm"][index]),
            "offset_nm": float(target_rows["offset_nm"][index]),
            "weight": float(target_rows["weight"][index]),
        }
        for index in top_indexes
    ]

    positive = target_rows[target_rows["weight"] > 0.0]
    weighted_mean_offset = float(np.sum(positive["offset_nm"] * positive["weight"]))
    weighted_std_offset = float(
        np.sqrt(
            np.sum(np.square(positive["offset_nm"] - weighted_mean_offset) * positive["weight"])
        )
    )
    return [
        {
            "question": "Which nominal wavelengths use the broadest high-resolution support?",
            "answer": {
                "wavelength_nm": float(nominal_wavelengths[widest_index]),
                "support_width_nm": float(support_widths[widest_index]),
                "support_count": int(support_counts[widest_index]),
            },
            "output": "instrument response high-resolution sampling table",
        },
        {
            "question": "Which high-resolution wavelengths dominate a nominal wavelength?",
            "answer": {
                "nominal_wavelength_nm": target_wavelength,
                "top_support_samples": top_support,
            },
            "output": "instrument response support weights",
        },
        {
            "question": "How wide is the effective response around a selected nominal wavelength?",
            "answer": {
                "nominal_wavelength_nm": target_wavelength,
                "weighted_mean_offset_nm": weighted_mean_offset,
                "weighted_std_offset_nm": weighted_std_offset,
            },
            "output": "instrument response support weights",
        },
    ]


def run_instrument_response() -> dict[str, object]:
    library_path = require_library()
    zd = import_zdisamar()
    case = build_o2a_case(zd)
    nominal = sampled_nominal_wavelengths(case)

    total_start = time.perf_counter()
    prepare_start = time.perf_counter()
    with zd.prepare(case, library_path=library_path) as prepared:
        prepare_s = time.perf_counter() - prepare_start
        diagnostics_start = time.perf_counter()
        table = prepared.instrument_response.sampling_table(wavelengths_nm=nominal).table
        diagnostics_s = time.perf_counter() - diagnostics_start

    questions = answer_questions(table)
    write_start = time.perf_counter()
    write_csv(TABLE_OUTPUT, table)
    write_s = time.perf_counter() - write_start

    summary = {
        "row_count": int(table.size),
        "nominal_wavelength_count": int(nominal.size),
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
    summary = run_instrument_response()
    timing = summary["timing"]
    widest = summary["questions"][0]["answer"]
    print(
        f"instrument_response={TABLE_OUTPUT} "
        f"questions={len(summary['questions'])} rows={summary['row_count']} "
        f"widest_support={widest['support_width_nm']:.3f}nm"
        f"@{widest['wavelength_nm']:.2f}nm "
        f"prepare={timing['prepare_o2a_s']:.2f}s diagnostics={timing['diagnostics_s']:.2f}s "
        f"total={timing['total_s']:.2f}s"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
