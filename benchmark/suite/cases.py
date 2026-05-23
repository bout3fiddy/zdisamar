"""Benchmark case construction."""

import copy
import json
from dataclasses import dataclass
from typing import Any

from zdisamar.wavelength_bands import o2a as band

from validation.o2a import baseline as band_baseline
from validation.o2a.case import build_o2a_case, build_o2a_jacobian_case
from validation.optimal_estimation import reference_cases, setup

from . import config


@dataclass(frozen=True)
class SceneSpec:
    label: str
    values: dict[str, float]


@dataclass(frozen=True)
class SweepCase:
    index: int
    truth: dict[str, float]
    initial: dict[str, float]
    case: Any


def forward_case() -> Any:

    case = build_o2a_jacobian_case(band)
    band_baseline.configure_case(case)

    return case


def scene_cases() -> list[tuple[SceneSpec, Any]]:

    base = build_o2a_case(band)
    band_baseline.configure_case(base)
    selected_labels = config.FAST_SCENE_LABELS
    specs = scene_specs()

    if selected_labels is not None:
        selected = set(selected_labels)
        specs = [spec for spec in specs if spec.label in selected]
        missing = selected - {spec.label for spec in specs}

        if missing:
            raise ValueError(f"unknown benchmark scene label(s): {sorted(missing)}")

    return [
        (
            spec,
            setup.build_scene(
                base,
                index=index,
                id_prefix="benchmark_fast_spectra",
                scene=spec.values,
            ),
        )
        for index, spec in enumerate(specs, start=1)
    ]


def retrieval_case() -> tuple[Any, dict[str, Any]]:

    reference = json.loads(config.REFERENCE_OE_PATH.read_text())
    case = build_o2a_case(band, jacobian_reference_layer=True)
    band_baseline.configure_case(case)

    return case, reference


def sweep_cases() -> list[SweepCase]:

    base = build_o2a_case(band, jacobian_reference_layer=True)
    band_baseline.configure_case(base)
    selected_indices = config.SWEEP_CASE_INDICES
    requested_count = max(selected_indices) if selected_indices is not None else config.SWEEP_COUNT
    selected = set(selected_indices) if selected_indices is not None else None
    rows = []

    for row in reference_cases.case_rows(count=requested_count):
        index = int(row["case"])

        if selected is not None and index not in selected:
            continue

        truth = reference_cases.scene_from_row(row)
        rows.append(
            SweepCase(
                index=index,
                truth=truth,
                initial=reference_cases.initial_from_row(row),
                case=setup.build_scene(
                    base,
                    index=index,
                    id_prefix="benchmark_retrieval",
                    scene=truth,
                ),
            )
        )

    if selected is not None:
        missing = selected - {row.index for row in rows}

        if missing:
            raise ValueError(f"unknown benchmark OE sweep case(s): {sorted(missing)}")

    return rows


def fast_case(case: Any) -> Any:

    return copy.deepcopy(case).with_fast_mode()


def scene_specs() -> list[SceneSpec]:

    return [
        SceneSpec(
            label="baseline",
            values={
                "solar_zenith_deg": 60.0,
                "viewing_zenith_deg": 30.0,
                "relative_azimuth_deg": 120.0,
                "surface_pressure_hpa": 1013.25,
                "surface_albedo": 0.20,
                "aerosol_optical_depth": 0.30,
                "aerosol_mid_pressure_hpa": 510.0,
            },
        ),
        SceneSpec(
            label="bright surface",
            values={
                "solar_zenith_deg": 35.0,
                "viewing_zenith_deg": 12.0,
                "relative_azimuth_deg": 150.0,
                "surface_pressure_hpa": 1013.25,
                "surface_albedo": 0.55,
                "aerosol_optical_depth": 0.12,
                "aerosol_mid_pressure_hpa": 720.0,
            },
        ),
        SceneSpec(
            label="oblique aerosol",
            values={
                "solar_zenith_deg": 53.76029607719826,
                "viewing_zenith_deg": 45.71214389158657,
                "relative_azimuth_deg": 7.0232796692031245,
                "surface_pressure_hpa": 896.819424951348,
                "surface_albedo": 0.19528921533381227,
                "aerosol_optical_depth": 1.9681905891962788,
                "aerosol_mid_pressure_hpa": 329.192074869615,
            },
        ),
        SceneSpec(
            label="low sun dark surface",
            values={
                "solar_zenith_deg": 65.0,
                "viewing_zenith_deg": 42.0,
                "relative_azimuth_deg": 25.0,
                "surface_pressure_hpa": 950.0,
                "surface_albedo": 0.08,
                "aerosol_optical_depth": 1.45,
                "aerosol_mid_pressure_hpa": 410.0,
            },
        ),
    ]
