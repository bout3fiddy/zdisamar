"""Profile-retrieval SVG plots."""

from pathlib import Path

from .properties import PLOT, PlotAccessor
from .svg import SvgFigure, SvgPanel, SvgSeries

PROFILE_PANEL_WIDTH = 520
PROFILE_PANEL_HEIGHT = 520
PROFILE_PANEL_SPACING = 100


class ProfileRetrievalPlot(PlotAccessor):
    """Plots for the discrete aerosol-location profile supplement."""

    def __init__(self, result):

        super().__init__(result)

    def probability(self, save: str | Path | None = None):

        return self.finish_plot(probability_figure(self.target), save=save)

    def expected_aod(self, save: str | Path | None = None):

        return self.finish_plot(expected_aod_figure(self.target), save=save)

    def summary(self, save: str | Path | None = None):

        return self.finish_plot(summary_figure(self.target), save=save)


def probability_figure(result) -> SvgFigure:

    return SvgFigure(
        title="Aerosol layer-location probability",
        panels=(probability_panel(result),),
    )


def expected_aod_figure(result) -> SvgFigure:

    return SvgFigure(
        title="Expected aerosol optical depth profile",
        panels=(expected_aod_panel(result),),
    )


def summary_figure(result) -> SvgFigure:

    return SvgFigure(
        title="Discrete aerosol profile retrieval",
        panels=(probability_panel(result), expected_aod_panel(result)),
        columns=2,
        panel_spacing=PROFILE_PANEL_SPACING,
        y_independent=False,
    )


def probability_panel(result) -> SvgPanel:

    candidates = ordered_candidates(result)
    pressure = [candidate.bin.center_pressure_hpa for candidate in candidates]
    probability = [candidate.probability for candidate in candidates]
    best = max(candidates, key=lambda candidate: candidate.probability)

    return SvgPanel(
        title="Layer-location probability",
        x_title="Probability",
        y_title="Pressure (hPa)",
        series=(
            SvgSeries.line(
                "Probability",
                probability,
                pressure,
                color=PLOT.colors["blue"],
                show_legend=False,
            ),
            SvgSeries.points(
                "Probability",
                probability,
                pressure,
                color=PLOT.colors["blue"],
                point_size=PLOT.profile_point_size,
                opacity=PLOT.profile_point_opacity,
                show_legend=False,
            ),
            SvgSeries.points(
                "Best bin",
                [best.probability],
                [best.bin.center_pressure_hpa],
                color=PLOT.colors["orange"],
                point_size=PLOT.minimum_point_size,
                show_legend=False,
            ),
        ),
        width=PROFILE_PANEL_WIDTH,
        height=PROFILE_PANEL_HEIGHT,
        x_domain=(0.0, max(probability) * 1.08 if probability else 1.0),
        y_domain=pressure_domain(result),
        show_legend=False,
    )


def expected_aod_panel(result) -> SvgPanel:

    rows = ordered_expected_aod(result)
    pressure = [row.bin.center_pressure_hpa for row in rows]
    expected_aod = [row.expected_aod_550_nm for row in rows]

    return SvgPanel(
        title="Probability-weighted AOD",
        x_title="Expected AOD at 550 nm",
        y_title="Pressure (hPa)",
        series=(
            SvgSeries.line(
                "Expected AOD",
                expected_aod,
                pressure,
                color=PLOT.colors["orange"],
                show_legend=False,
            ),
            SvgSeries.points(
                "Expected AOD",
                expected_aod,
                pressure,
                color=PLOT.colors["orange"],
                point_size=PLOT.profile_point_size,
                opacity=PLOT.profile_point_opacity,
                show_legend=False,
            ),
        ),
        width=PROFILE_PANEL_WIDTH,
        height=PROFILE_PANEL_HEIGHT,
        x_domain=(0.0, max(expected_aod) * 1.08 if expected_aod else 1.0),
        y_domain=pressure_domain(result),
        show_legend=False,
    )


def ordered_candidates(result):

    return sorted(result.candidates, key=lambda candidate: candidate.bin.center_pressure_hpa)


def ordered_expected_aod(result):

    return sorted(result.expected_aod_profile, key=lambda row: row.bin.center_pressure_hpa)


def pressure_domain(result) -> tuple[float, float]:

    top = min(candidate.bin.top_pressure_hpa for candidate in result.candidates)
    bottom = max(candidate.bin.bottom_pressure_hpa for candidate in result.candidates)

    return (bottom, top)


__all__ = [
    "ProfileRetrievalPlot",
    "expected_aod_figure",
    "probability_figure",
    "summary_figure",
]
