#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "numpy>=2.0",
# ]
# ///

"""Score public zdisamar plot accessors without visual inspection."""

import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol, cast

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(REPO_ROOT), str(REPO_ROOT / "python")]

from zdisamar.inverse_method.optimal_estimation.retrieval import (  # noqa: E402
    Iteration,
    Measurement,
    Result,
)
from zdisamar.inverse_method.optimal_estimation.rtm_evaluation import RtmEvaluation  # noqa: E402
from zdisamar.plot.atmosphere import BudgetPlot  # noqa: E402
from zdisamar.plot.collision_induced_absorption import (  # noqa: E402
    CollisionInducedAbsorptionPlot,
)
from zdisamar.plot.instrument_response import InstrumentResponsePlot  # noqa: E402
from zdisamar.plot.properties import PLOT  # noqa: E402
from zdisamar.plot.svg import SvgFigure  # noqa: E402

OUTPUT_PATH = Path("validation/outputs/plot_quality/scores.json")


class FigureFactory(Protocol):
    def __call__(self) -> SvgFigure: ...


@dataclass(frozen=True)
class SpectrumFixture:
    wavelength_nm: np.ndarray
    radiance: np.ndarray
    irradiance: np.ndarray
    reflectance: np.ndarray
    reflectance_jacobian_values: np.ndarray
    jacobian_state_names: tuple[str, ...]

    @property
    def sun_normalized_radiance(self) -> np.ndarray:

        return self.radiance / self.irradiance

    @property
    def plot(self):

        from zdisamar.plot.spectrum import SpectrumPlot

        return SpectrumPlot(self)

    def reflectance_jacobian(self, state: str) -> np.ndarray:

        return self.reflectance_jacobian_values[:, self.jacobian_state_names.index(state)]


@dataclass(frozen=True)
class NoiseFixture:
    snr_wavelengths_nm: np.ndarray
    snr_values: np.ndarray


@dataclass(frozen=True)
class TableFixture:
    rows: tuple[dict[str, object], ...]

    def to_rows(self) -> list[dict[str, object]]:

        return [dict(row) for row in self.rows]

    def column(self, name: str) -> np.ndarray:

        return np.asarray([row[name] for row in self.rows])


@dataclass(frozen=True)
class InstrumentResponseFixture(TableFixture):
    @property
    def plot(self):

        return InstrumentResponsePlot(self)


def main() -> int:

    cases = plot_cases()
    scores = {name: score_figure(name, factory()) for name, factory in cases.items()}
    failures = [name for name, score in scores.items() if not score["passed"]]
    payload = {
        "schema_version": 1,
        "thresholds": {
            "data_max_px_error": 1.0e-9,
            "duplicate_visible_title_count": 0,
            "min_axis_title_tick_gap_px": 20.0,
            "out_of_bounds_count": 0,
            "style_mismatch_count": 0,
            "min_svg_bytes": 1_000,
        },
        "summary": {
            "case_count": len(scores),
            "passed": len(failures) == 0,
            "failures": failures,
        },
        "cases": scores,
    }
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    if failures:
        raise SystemExit(f"plot quality failures: {', '.join(failures)}")

    print(f"plot_quality=ok cases={len(scores)} output={OUTPUT_PATH}")

    return 0


def plot_cases() -> dict[str, FigureFactory]:

    spectrum = spectrum_fixture()
    noise = NoiseFixture(
        snr_wavelengths_nm=np.array([755.0, 760.76, 776.0], dtype=np.float64),
        snr_values=np.array([450.0, 600.0, 410.0], dtype=np.float64),
    )
    budget = TableFixture(tuple(profile_rows("total_optical_depth")))
    cia = TableFixture(tuple(profile_rows("cia_optical_depth")))
    instrument_response = InstrumentResponseFixture(tuple(instrument_response_rows()))
    oe_result = optimal_estimation_result()

    return {
        "spectrum_reflectance": lambda: spectrum.plot.reflectance(),
        "spectrum_radiance": lambda: spectrum.plot.radiance(),
        "spectrum_jacobian": lambda: spectrum.plot.jacobian("aerosol_optical_depth"),
        "spectrum_snr": lambda: spectrum.plot.snr(noise),
        "spectrum_noise_envelope": lambda: spectrum.plot.noise_envelope(noise),
        "atmospheric_budget": lambda: BudgetPlot(budget).optical_depth(),
        "collision_induced_absorption": lambda: CollisionInducedAbsorptionPlot(cia).optical_depth(),
        "instrument_response": lambda: instrument_response.plot.curve(),
        "oe_convergence": lambda: oe_result.plot.convergence(),
        "oe_measurement_fit": lambda: oe_result.plot.measurement_fit(),
        "oe_residual": lambda: oe_result.plot.residual(),
        "oe_jacobian": lambda: oe_result.plot.jacobian(),
    }


def score_figure(name: str, figure: SvgFigure) -> dict[str, object]:

    metrics = figure.quality_metrics()
    description = figure.to_dict()
    panels = list_value(description, "panels")
    svg = figure._repr_svg_()
    style_mismatch_count = int_value(metrics["style_mismatch_count"])
    style_mismatch_count += expected_style_mismatches(panels)
    passed = (
        float_value(metrics["data_max_px_error"]) <= 1.0e-9
        and int_value(metrics["out_of_bounds_count"]) == 0
        and style_mismatch_count == 0
        and int_value(metrics["duplicate_visible_title_count"]) == 0
        and float_value(metrics["min_axis_title_tick_gap_px"]) >= 20.0
        and len(svg) >= 1_000
        and len(panels) >= 1
        and int_value(metrics["series_count"]) >= 1
    )

    return {
        "passed": passed,
        "svg_bytes": len(svg),
        "panel_count": len(panels),
        "series_count": metrics["series_count"],
        "data_max_px_error": metrics["data_max_px_error"],
        "out_of_bounds_count": metrics["out_of_bounds_count"],
        "style_mismatch_count": style_mismatch_count,
        "duplicate_visible_title_count": metrics["duplicate_visible_title_count"],
        "min_axis_title_tick_gap_px": metrics["min_axis_title_tick_gap_px"],
        "width": description["width"],
        "height": description["height"],
        "title": description["title"],
        "case": name,
    }


def expected_style_mismatches(panels: list[object]) -> int:

    expected_colors = set(PLOT.colors.values())
    mismatches = 0

    for panel in panels:
        if not isinstance(panel, dict):
            mismatches += 1

            continue

        for series in list_value(panel, "series"):
            if not isinstance(series, dict):
                mismatches += 1

                continue

            if field_value(series, "color") not in expected_colors:
                mismatches += 1

    return mismatches


def int_value(value: object) -> int:

    if isinstance(value, int):
        return value

    if isinstance(value, float | str):
        return int(value)

    raise TypeError(f"expected integer metric, got {type(value).__name__}")


def float_value(value: object) -> float:

    if isinstance(value, int | float | str):
        return float(value)

    raise TypeError(f"expected numeric metric, got {type(value).__name__}")


def field_value(values: object, key: str) -> object:

    if isinstance(values, dict):
        return cast(dict[str, object], values)[key]

    raise TypeError(f"expected object field {key!r}, got {type(values).__name__}")


def list_value(values: object, key: str) -> list[object]:

    value = field_value(values, key)

    if isinstance(value, list):
        return cast(list[object], value)

    raise TypeError(f"expected list field {key!r}, got {type(value).__name__}")


def spectrum_fixture() -> SpectrumFixture:

    wavelength = np.linspace(755.0, 776.0, 701, dtype=np.float64)
    center = 760.76
    absorption = np.exp(-0.5 * ((wavelength - center) / 1.15) ** 2)
    reflectance = 0.22 - 0.15 * absorption + 0.006 * np.sin((wavelength - 755.0) * 1.6)
    irradiance = 1.8 + 0.015 * np.cos((wavelength - 755.0) * 0.4)
    radiance = reflectance * irradiance
    jacobian = np.column_stack(
        (
            0.11 * absorption,
            -1.0e-5 * (1.0 + 0.25 * np.sin((wavelength - 760.0) * 1.2)),
        )
    )

    return SpectrumFixture(
        wavelength_nm=wavelength,
        radiance=radiance,
        irradiance=irradiance,
        reflectance=reflectance,
        reflectance_jacobian_values=jacobian,
        jacobian_state_names=("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa"),
    )


def profile_rows(value_name: str) -> list[dict[str, object]]:

    rows: list[dict[str, object]] = []

    for wavelength in (759.0, 760.76, 762.0):
        for layer in range(8):
            bottom = float(layer)
            top = float(layer + 1)
            value = (8 - layer) * (1.0 + abs(wavelength - 760.76) * 0.05) * 1.0e-3
            rows.append(
                {
                    "wavelength_nm": wavelength,
                    "top_altitude_km": top,
                    "bottom_altitude_km": bottom,
                    "altitude_km": 0.5 * (top + bottom),
                    value_name: value,
                    "support_row_kind_label": "parity_active",
                }
            )

    return rows


def instrument_response_rows() -> list[dict[str, object]]:

    rows: list[dict[str, object]] = []

    for nominal in (759.0, 760.76):
        for offset in np.linspace(-0.25, 0.25, 81, dtype=np.float64):
            weight = float(np.exp(-0.5 * (offset / 0.07) ** 2))
            rows.append(
                {
                    "nominal_wavelength_nm": nominal,
                    "channel": 0,
                    "offset_nm": float(offset),
                    "support_wavelength_nm": float(nominal + offset),
                    "weight": weight,
                    "instrument_fwhm_nm": 0.12,
                }
            )

    return rows


def optimal_estimation_result() -> Result:

    wavelength = np.linspace(755.0, 776.0, 101, dtype=np.float64)
    measurement = 0.2 - 0.11 * np.exp(-0.5 * ((wavelength - 760.76) / 1.2) ** 2)
    retrieved = measurement + 1.2e-4 * np.sin((wavelength - 755.0) * 2.0)
    jacobian = np.column_stack(
        (
            0.09 * np.exp(-0.5 * ((wavelength - 760.76) / 1.4) ** 2),
            -1.0e-5 * (1.0 + 0.2 * np.cos((wavelength - 760.0) * 1.1)),
        )
    )

    return Result(
        state_names=("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa"),
        state=np.array([0.28, 900.0], dtype=np.float64),
        initial_state=np.array([0.12, 875.0], dtype=np.float64),
        iterations=2,
        converged=True,
        history=(
            Iteration(1, np.array([0.18, 890.0]), 10.0, 9.4, 0.6, 80.0, True),
            Iteration(2, np.array([0.28, 900.0]), 1.0, 0.9, 0.1, 0.4, True),
        ),
        posterior_covariance=np.eye(2, dtype=np.float64),
        averaging_kernel=np.eye(2, dtype=np.float64),
        measurement=Measurement(
            wavelength_nm=wavelength,
            reflectance=measurement,
            variance=np.full_like(wavelength, 1.0e-6),
        ),
        final_evaluation=RtmEvaluation(
            wavelength_nm=wavelength,
            reflectance=retrieved,
            reflectance_jacobian=jacobian,
        ),
    )


if __name__ == "__main__":
    raise SystemExit(main())
