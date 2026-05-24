"""Profile-retrieval SVG plots."""

import math
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import cast

from .properties import PLOT, PlotAccessor
from .svg import SvgFigure, SvgPanel, SvgSeries

PROFILE_PANEL_WIDTH = 520
PROFILE_SINGLE_PANEL_WIDTH = 400
PROFILE_PANEL_MIN_HEIGHT = 520
PROFILE_BIN_PIXEL_HEIGHT = 34
PROFILE_PANEL_SPACING = 100
PROFILE_Y_TICK_LABEL_FONT_SIZE = 8
TRUTH_COLOR = "#4C4C4C"


@dataclass(frozen=True)
class TruthProfile:
    """Truth aerosol loading rebinned onto the retrieval pressure grid."""

    aod_by_bin: tuple[float, ...]
    fraction_by_bin: tuple[float, ...]
    total_aod_550_nm: float
    center_pressure_hpa: float | None


class ProfileRetrievalPlot(PlotAccessor):
    """Plots for the discrete aerosol-location profile supplement."""

    def __init__(self, result):

        super().__init__(result)

    def probability(
        self,
        save: str | Path | None = None,
        *,
        truth_layers: Sequence[object] | None = None,
    ):

        figure = probability_figure(self.target, truth_layers=truth_layers)

        return self.finish_plot(figure, save=save)

    def expected_aod(
        self,
        save: str | Path | None = None,
        *,
        truth_layers: Sequence[object] | None = None,
    ):

        figure = expected_aod_figure(self.target, truth_layers=truth_layers)

        return self.finish_plot(figure, save=save)

    def summary(
        self,
        save: str | Path | None = None,
        *,
        truth_layers: Sequence[object] | None = None,
        subtitle: str | None = None,
    ):

        return self.finish_plot(
            summary_figure(self.target, truth_layers=truth_layers, subtitle=subtitle),
            save=save,
        )


def probability_figure(
    result,
    *,
    truth_layers: Sequence[object] | None = None,
) -> SvgFigure:

    return SvgFigure(
        title="Aerosol layer-location probability",
        panels=(
            probability_panel(
                result,
                truth_layers=truth_layers,
                width=PROFILE_SINGLE_PANEL_WIDTH,
            ),
        ),
        margin_right=20,
    )


def expected_aod_figure(
    result,
    *,
    truth_layers: Sequence[object] | None = None,
) -> SvgFigure:

    return SvgFigure(
        title="Expected aerosol optical depth profile",
        panels=(
            expected_aod_panel(
                result,
                truth_layers=truth_layers,
                width=PROFILE_SINGLE_PANEL_WIDTH,
            ),
        ),
        margin_right=20,
    )


def summary_figure(
    result,
    *,
    truth_layers: Sequence[object] | None = None,
    subtitle: str | None = None,
) -> SvgFigure:

    truth = truth_profile(result, truth_layers)

    return SvgFigure(
        title="Discrete aerosol-layer profile",
        subtitle=subtitle,
        panels=(
            probability_panel(result, truth=truth),
            expected_aod_panel(result, truth=truth, show_y_title=False),
        ),
        columns=2,
        panel_spacing=PROFILE_PANEL_SPACING,
        y_independent=False,
        title_anchor="start",
        show_title=subtitle is not None,
    )


def probability_panel(
    result,
    *,
    truth_layers: Sequence[object] | None = None,
    truth: TruthProfile | None = None,
    width: int = PROFILE_PANEL_WIDTH,
) -> SvgPanel:

    candidates = ordered_candidates(result)
    probability = [candidate.probability for candidate in candidates]
    truth_value = truth if truth is not None else truth_profile(result, truth_layers)
    series = []

    if truth_value is not None:
        series.append(
            SvgSeries.horizontal_bars(
                "Truth AOD fraction",
                truth_value.fraction_by_bin,
                [candidate.bin.top_pressure_hpa for candidate in candidates],
                [candidate.bin.bottom_pressure_hpa for candidate in candidates],
                color=TRUTH_COLOR,
                opacity=0.22,
                stroke_color=TRUTH_COLOR,
                stroke_width=0.9,
            )
        )

    series.append(
        SvgSeries.horizontal_bars(
            "Retrieved probability",
            probability,
            [candidate.bin.top_pressure_hpa for candidate in candidates],
            [candidate.bin.bottom_pressure_hpa for candidate in candidates],
            color=PLOT.colors["blue"],
            opacity=0.82,
            value_labels=True,
            value_label_format=".3f",
            show_legend=truth_value is not None,
        )
    )

    return SvgPanel(
        title="Layer-location probability",
        x_title="Probability",
        y_title="Pressure bin (hPa)",
        series=tuple(series),
        width=width,
        height=profile_panel_height(result),
        x_domain=(0.0, padded_x_max([*probability, *truth_fraction_values(truth_value)])),
        y_domain=pressure_domain(result),
        y_ticks=bin_centers(candidates),
        y_tick_labels=bin_mid_pressure_labels(candidates),
        y_tick_label_font_size=PROFILE_Y_TICK_LABEL_FONT_SIZE,
        rule_y=truth_rule_y(truth_value),
        show_x_grid=True,
        show_y_grid=False,
        show_legend=truth_value is not None,
    )


def expected_aod_panel(
    result,
    *,
    truth_layers: Sequence[object] | None = None,
    truth: TruthProfile | None = None,
    show_y_title: bool = True,
    width: int = PROFILE_PANEL_WIDTH,
) -> SvgPanel:

    rows = ordered_expected_aod(result)
    expected_aod = [row.expected_aod_550_nm for row in rows]
    truth_value = truth if truth is not None else truth_profile(result, truth_layers)
    series = []

    if truth_value is not None:
        series.append(
            SvgSeries.horizontal_bars(
                "Truth AOD",
                truth_value.aod_by_bin,
                [row.bin.top_pressure_hpa for row in rows],
                [row.bin.bottom_pressure_hpa for row in rows],
                color=TRUTH_COLOR,
                opacity=0.22,
                stroke_color=TRUTH_COLOR,
                stroke_width=0.9,
            )
        )

    series.append(
        SvgSeries.horizontal_bars(
            "Model-averaged AOD",
            expected_aod,
            [row.bin.top_pressure_hpa for row in rows],
            [row.bin.bottom_pressure_hpa for row in rows],
            color="#B75C43",
            opacity=0.82,
            value_labels=True,
            value_label_format=".4f",
            show_legend=truth_value is not None,
        )
    )

    return SvgPanel(
        title="Model-averaged AOD distribution",
        x_title="Expected AOD at 550 nm",
        y_title="Pressure bin (hPa)" if show_y_title else None,
        series=tuple(series),
        width=width,
        height=profile_panel_height(result),
        x_domain=(0.0, padded_x_max([*expected_aod, *truth_aod_values(truth_value)])),
        y_domain=pressure_domain(result),
        y_ticks=bin_centers(rows),
        y_tick_labels=bin_mid_pressure_labels(rows),
        y_tick_label_font_size=PROFILE_Y_TICK_LABEL_FONT_SIZE,
        rule_y=truth_rule_y(truth_value),
        show_x_grid=True,
        show_y_grid=False,
        show_legend=truth_value is not None,
    )


def ordered_candidates(result):

    return sorted(result.candidates, key=lambda candidate: candidate.bin.center_pressure_hpa)


def ordered_expected_aod(result):

    return sorted(result.expected_aod_profile, key=lambda row: row.bin.center_pressure_hpa)


def bin_centers(rows) -> tuple[float, ...]:

    return tuple(row.bin.center_pressure_hpa for row in rows)


def bin_mid_pressure_labels(rows) -> tuple[str, ...]:

    return tuple(format_pressure(row.bin.center_pressure_hpa) for row in rows)


def format_pressure(value: float) -> str:

    rounded = round(value)

    if math.isclose(value, rounded, abs_tol=1.0e-9):
        return str(rounded)

    return f"{value:.1f}"


def padded_x_max(values: Sequence[float]) -> float:

    finite_values = [float(value) for value in values if math.isfinite(float(value))]

    if not finite_values:
        return 1.0

    maximum = max(finite_values)

    if maximum <= 0.0:
        return 1.0

    return maximum * 1.10


def truth_fraction_values(truth: TruthProfile | None) -> tuple[float, ...]:

    return () if truth is None else truth.fraction_by_bin


def truth_aod_values(truth: TruthProfile | None) -> tuple[float, ...]:

    return () if truth is None else truth.aod_by_bin


def truth_rule_y(truth: TruthProfile | None) -> tuple[float, ...]:

    if truth is None or truth.center_pressure_hpa is None:
        return ()

    return (truth.center_pressure_hpa,)


def truth_profile(result, truth_layers: Sequence[object] | None) -> TruthProfile | None:

    if truth_layers is None:
        return None

    layers = tuple(truth_layers)

    if not layers:
        return None

    candidates = ordered_candidates(result)
    aod_by_bin = [0.0 for _candidate in candidates]
    total_aod = 0.0
    weighted_pressure = 0.0

    for layer in layers:
        top = layer_float(layer, "top_pressure_hpa")
        bottom = layer_float(layer, "bottom_pressure_hpa")
        optical_depth = layer_aod_550_nm(layer)

        if bottom <= top:
            raise ValueError(
                "truth aerosol layers must have bottom_pressure_hpa > top_pressure_hpa"
            )

        total_aod += optical_depth
        weighted_pressure += optical_depth * 0.5 * (top + bottom)

        for index, candidate in enumerate(candidates):
            overlap_top = max(top, candidate.bin.top_pressure_hpa)
            overlap_bottom = min(bottom, candidate.bin.bottom_pressure_hpa)
            overlap = max(0.0, overlap_bottom - overlap_top)

            if overlap > 0.0:
                aod_by_bin[index] += optical_depth * overlap / (bottom - top)

    binned_total = sum(aod_by_bin)
    fraction_by_bin = (
        tuple(0.0 for _value in aod_by_bin)
        if binned_total <= 0.0
        else tuple(value / binned_total for value in aod_by_bin)
    )
    center = None if total_aod <= 0.0 else weighted_pressure / total_aod

    return TruthProfile(
        aod_by_bin=tuple(aod_by_bin),
        fraction_by_bin=fraction_by_bin,
        total_aod_550_nm=total_aod,
        center_pressure_hpa=center,
    )


def layer_float(layer: object, name: str) -> float:

    if isinstance(layer, Mapping):
        value = cast(Mapping[str, object], layer)[name]
    else:
        value = getattr(layer, name)

    return finite_layer_float(value, name)


def layer_aod_550_nm(layer: object) -> float:

    optical_depth = first_layer_float(
        layer,
        ("optical_depth", "aerosol_optical_depth_550_nm", "aod_550_nm"),
    )
    reference_wavelength = first_layer_float(layer, ("reference_wavelength_nm",), default=550.0)
    angstrom = first_layer_float(layer, ("angstrom_exponent",), default=0.0)

    if optical_depth < 0.0:
        raise ValueError("truth aerosol layer optical depth must be non-negative")

    if reference_wavelength <= 0.0:
        raise ValueError("truth aerosol layer reference_wavelength_nm must be positive")

    return optical_depth * (550.0 / reference_wavelength) ** (-angstrom)


def first_layer_float(
    layer: object,
    names: Sequence[str],
    *,
    default: float | None = None,
) -> float:

    for name in names:
        if isinstance(layer, Mapping):
            mapping = cast(Mapping[str, object], layer)

            if name in mapping:
                return finite_layer_float(mapping[name], name)
        elif hasattr(layer, name):
            return finite_layer_float(getattr(layer, name), name)

    if default is not None:
        return default

    raise ValueError(f"truth aerosol layer must define one of {', '.join(names)}")


def finite_layer_float(value: object, name: str) -> float:

    if not isinstance(value, str | int | float):
        raise ValueError(f"truth aerosol layer {name} must be numeric")

    number = float(value)

    if not math.isfinite(number):
        raise ValueError(f"truth aerosol layer {name} must be finite")

    return number


def default_subtitle(result, truth: TruthProfile | None) -> str:

    parts = [
        "AOD-only fixed-location retrieval",
        f"beta={result.probability_calibration_beta:g}",
    ]

    if truth is not None:
        if truth.center_pressure_hpa is not None:
            parts.append(f"truth center={truth.center_pressure_hpa:.1f} hPa")

        parts.append(f"truth AOD={truth.total_aod_550_nm:.3g}")

    return "; ".join(parts)


def pressure_domain(result) -> tuple[float, float]:

    top = min(candidate.bin.top_pressure_hpa for candidate in result.candidates)
    bottom = max(candidate.bin.bottom_pressure_hpa for candidate in result.candidates)

    return (bottom, top)


def profile_panel_height(result) -> int:

    return max(PROFILE_PANEL_MIN_HEIGHT, len(result.candidates) * PROFILE_BIN_PIXEL_HEIGHT)


__all__ = [
    "ProfileRetrievalPlot",
    "TruthProfile",
    "expected_aod_figure",
    "probability_figure",
    "summary_figure",
]
