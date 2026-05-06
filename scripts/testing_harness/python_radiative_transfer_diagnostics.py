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
TABLE_OUTPUT = OUT_DIR / "python_radiative_transfer_diagnostics.csv"
QUESTIONS_OUTPUT = OUT_DIR / "python_radiative_transfer_questions.json"
TARGET_WAVELENGTHS_NM = np.array([755.0, 760.76, 776.0], dtype=np.float64)


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


def write_csv(path: Path, table) -> None:
    fields = list(table.dtype.names or ())
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for row in table:
            writer.writerow({name: scalar(row[name]) for name in fields})


def ranked_layers(table, column: str) -> list[dict[str, object]]:
    keys = np.unique(table["global_sublayer_index"])
    rows = []
    total = float(np.sum(table[column]))
    for key in keys:
        mask = table["global_sublayer_index"] == key
        value = float(np.sum(table[column][mask]))
        first = table[mask][0]
        rows.append(
            {
                "global_sublayer_index": int(key),
                "layer_index": int(first["layer_index"]),
                "interval_index_1based": int(first["interval_index_1based"]),
                "altitude_km": float(first["altitude_km"]),
                f"{column}_sum": value,
                "share": 0.0 if total == 0.0 else value / total,
            }
        )
    rows.sort(key=lambda item: item[f"{column}_sum"], reverse=True)
    return rows


def source_proxy_totals(table) -> dict[str, float]:
    direct = float(np.mean(table["direct_surface_transmission_proxy"]))
    scattering = float(np.sum(table["atmospheric_scattering_source_proxy"]))
    absorption = float(np.sum(table["absorption_loss_proxy"]))
    denom = direct + scattering + absorption
    return {
        "direct_surface_transmission_proxy": direct,
        "atmospheric_scattering_source_proxy": scattering,
        "absorption_loss_proxy": absorption,
        "direct_surface_proxy_share": 0.0 if denom == 0.0 else direct / denom,
        "atmospheric_scattering_proxy_share": 0.0 if denom == 0.0 else scattering / denom,
        "absorption_loss_proxy_share": 0.0 if denom == 0.0 else absorption / denom,
    }


def answer_questions(table) -> list[dict[str, object]]:
    scattering_layers = ranked_layers(table, "atmospheric_scattering_source_proxy")
    absorption_layers = ranked_layers(table, "absorption_loss_proxy")
    airmass = float(table["pseudo_spherical_airmass_factor"][0]) if table.size else 0.0
    return [
        {
            "question": (
                "Which layers dominate the final-radiance scattering "
                "proxy for selected wavelengths?"
            ),
            "answer": {
                "ranked_layers": scattering_layers[:10],
                "dominant_layer": scattering_layers[0] if scattering_layers else None,
            },
            "output": "bounded radiative-transfer layer diagnostic table",
        },
        {
            "question": (
                "How much of the proxy signal is direct surface "
                "transmission versus atmospheric scattering?"
            ),
            "answer": source_proxy_totals(table),
            "output": "bounded radiative-transfer source proxy columns",
        },
        {
            "question": "Which source-function proxy terms matter most?",
            "answer": {
                "ranked_absorption_layers": absorption_layers[:10],
                "ranked_scattering_layers": scattering_layers[:10],
            },
            "output": "bounded radiative-transfer source proxy columns",
        },
        {
            "question": "How much does pseudo-spherical geometry stretch the layer path?",
            "answer": {
                "pseudo_spherical_airmass_factor": airmass,
                "solar_zenith_viewing_zenith_airmass_definition": (
                    "sec(solar_zenith)+sec(viewing_zenith)"
                ),
            },
            "output": "pseudo-spherical path proxy column",
        },
    ]


def run_radiative_transfer_diagnostics() -> dict[str, object]:
    library_path = require_library()
    zd = import_zdisamar()
    case = build_o2a_case(zd)
    wavelengths = validation_grid_wavelengths(case)

    total_start = time.perf_counter()
    prepare_start = time.perf_counter()
    with zd.prepare(case, library_path=library_path) as prepared:
        prepare_s = time.perf_counter() - prepare_start
        forward_start = time.perf_counter()
        with prepared.forward_model() as spectrum:
            forward_s = time.perf_counter() - forward_start
            diagnostics_start = time.perf_counter()
            table = prepared.radiative_transfer.diagnostics(
                wavelengths_nm=wavelengths, spectrum=spectrum
            ).table
            diagnostics_s = time.perf_counter() - diagnostics_start

    questions = answer_questions(table)
    write_start = time.perf_counter()
    write_csv(TABLE_OUTPUT, table)
    write_s = time.perf_counter() - write_start

    summary = {
        "row_count": int(table.size),
        "selected_wavelengths_nm": wavelengths.tolist(),
        "questions": questions,
        "artifacts": {
            "table_csv": str(TABLE_OUTPUT),
            "json": str(QUESTIONS_OUTPUT),
        },
        "timing": {
            "prepare_o2a_s": prepare_s,
            "forward_model_s": forward_s,
            "diagnostics_s": diagnostics_s,
            "write_s": write_s,
            "total_s": time.perf_counter() - total_start,
        },
    }
    QUESTIONS_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    QUESTIONS_OUTPUT.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return summary


def main() -> int:
    summary = run_radiative_transfer_diagnostics()
    timing = summary["timing"]
    dominant = summary["questions"][0]["answer"]["dominant_layer"]
    print(
        f"radiative_transfer={TABLE_OUTPUT} "
        f"questions={len(summary['questions'])} rows={summary['row_count']} "
        f"dominant_layer={dominant['global_sublayer_index']} "
        f"prepare={timing['prepare_o2a_s']:.2f}s forward={timing['forward_model_s']:.2f}s "
        f"diagnostics={timing['diagnostics_s']:.2f}s total={timing['total_s']:.2f}s"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
