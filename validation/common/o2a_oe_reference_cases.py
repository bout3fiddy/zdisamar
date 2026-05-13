"""Shared O2 A optimal-estimation reference sweep cases."""

import json
from typing import Any

from validation.common import o2a_optimal_estimation_setup as oe_setup
from validation.common.paths import VALIDATION_REFERENCE_DATA_ROOT, stable_repo_path

MANIFEST_PATH = (
    VALIDATION_REFERENCE_DATA_ROOT / "optimal_estimation" / "disamar_oe_sweep_cases.json"
)


def manifest() -> dict[str, Any]:
    return json.loads(MANIFEST_PATH.read_text())


def run_count() -> int:
    return int(manifest()["run_count"])


def scene_sample_count() -> int:
    return int(manifest()["scene_sample_count"])


def seed() -> int:
    return int(manifest()["seed"])


def manifest_path() -> str:
    return stable_repo_path(MANIFEST_PATH)


def truth_scenes(*, count: int | None = None) -> list[dict[str, float]]:
    payload = manifest()
    requested = int(payload["run_count"] if count is None else count)
    available = int(payload["scene_sample_count"])
    if requested > available:
        raise ValueError(
            f"requested {requested} OE reference cases but manifest only samples {available}"
        )
    return oe_setup.sampled_scenes(available, int(payload["seed"]))[:requested]


def initial_state(index: int, truth: dict[str, float]) -> dict[str, float]:
    return oe_setup.initial_state(index, truth)


def case_rows(*, count: int | None = None) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for index, truth in enumerate(truth_scenes(count=count), start=1):
        initial = initial_state(index, truth)
        rows.append(
            {
                "case": index,
                **truth,
                "initial_aerosol_optical_depth": initial["aerosol_optical_depth"],
                "initial_aerosol_mid_pressure_hpa": initial["aerosol_mid_pressure_hpa"],
            }
        )
    return rows


def scene_from_row(row: dict[str, Any]) -> dict[str, float]:
    return {
        key: float(row[key])
        for key in (
            "solar_zenith_deg",
            "viewing_zenith_deg",
            "relative_azimuth_deg",
            "surface_pressure_hpa",
            "surface_albedo",
            "aerosol_optical_depth",
            "aerosol_mid_pressure_hpa",
        )
    }


def initial_from_row(row: dict[str, Any]) -> dict[str, float]:
    return {
        "aerosol_optical_depth": float(row["initial_aerosol_optical_depth"]),
        "aerosol_mid_pressure_hpa": float(row["initial_aerosol_mid_pressure_hpa"]),
    }
