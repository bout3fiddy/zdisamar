"""SVG plot styling and save policy."""

from pathlib import Path
from typing import Protocol, TypeVar


class SavableSvg(Protocol):
    def save(self, path: str | Path) -> None: ...


SvgChart = TypeVar("SvgChart", bound=SavableSvg)


class PlotProperties:
    """One plotting style for spectra, diagnostics, and retrieval figures."""

    width = 1311
    height = 465
    diagnostic_width = 620
    font = "Menlo, Monaco, Consolas, Liberation Mono, DejaVu Sans Mono, monospace"
    markers_nm = (755.0, 760.76, 776.0)
    line_width = 1.4
    isrf_line_width = 1.6
    marker_rule_width = 0.8
    marker_rule_dash = (4, 3)
    profile_point_size = 26
    profile_point_opacity = 0.9
    default_point_size = 28
    minimum_point_size = 35
    noise_band_opacity = 0.45
    grid_opacity = 0.10
    x_axis_tick_count = 6
    y_axis_tick_count = 5
    axis_label_font_size = 12
    axis_title_font_size = 15
    legend_font_size = 12
    panel_title_font_size = 18
    title_font_size = 22
    colors = {
        "blue": "#1f77b4",
        "orange": "#ff7f0e",
        "red": "#d62728",
        "grid": "#b0b0b0",
        "black": "#111111",
        "neutral": "#737373",
        "band": "#D9D9D9",
        "reflectance": "#111111",
        "radiance": "#1F4E79",
        "irradiance": "#2F6B3F",
        "sun_normalized_radiance": "#2A5C7A",
        "total_optical_depth": "#222222",
        "collision_induced_absorption": "#8C3F2D",
        "residual_positive": "#8B1A1A",
        "residual_negative": "#1F4E79",
    }

    def finish(self, chart: SvgChart, *, save: str | Path | None = None) -> SvgChart:
        """Return charts by default and write image files only when requested."""

        if save is not None:
            self.save(chart, save)

        return chart

    def save(self, chart: SavableSvg, path: str | Path) -> None:
        """Save runtime plots as SVG."""

        output = Path(path)

        if output.suffix == "":
            output = output.with_suffix(".svg")

        output.parent.mkdir(parents=True, exist_ok=True)

        if output.suffix.lower() != ".svg":
            raise ValueError("zdisamar runtime plots save as SVG")

        chart.save(output)


PLOT = PlotProperties()


class PlotAccessor:
    """Shared plot accessor behavior backed by the single plot policy object."""

    def __init__(self, target):

        self.target = target

    @property
    def properties(self) -> PlotProperties:

        return PLOT

    def finish_plot(self, chart: SvgChart, *, save: str | Path | None = None) -> SvgChart:

        return PLOT.finish(chart, save=save)
