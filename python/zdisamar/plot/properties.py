"""Plot styling and save policy."""

from pathlib import Path
from typing import Any, cast

import altair as alt


class PlotProperties:
    width = 1311
    height = 465
    theme_name = "zdisamar_validation"
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
    png_scale_factor = 4.0
    axis_label_font_size = 16
    axis_title_font_size = 20
    legend_font_size = 16
    title_font_size = 20
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

    def __init__(self) -> None:
        self._registered = False
        self._enabled = False

    def prepare(self) -> None:
        if self._enabled:
            return
        if not self._registered:
            alt.themes.register(self.theme_name, cast(Any, self._theme))
            self._registered = True
        alt.themes.enable(cast(Any, self.theme_name))
        self._enabled = True

    def chart(self, title: str) -> dict[str, object]:
        return {"width": self.width, "height": self.height, "title": title}

    def theme(self):
        return self._theme()

    def finish(self, chart, *, save: str | Path | None = None):
        if save is not None:
            self.save(chart, save)
        return chart

    def save(self, chart, path: str | Path) -> None:
        output = Path(path)
        if output.suffix == "":
            output = output.with_suffix(".png")
        output.parent.mkdir(parents=True, exist_ok=True)
        kwargs = {"scale_factor": self.png_scale_factor} if output.suffix.lower() == ".png" else {}
        chart.save(output, **kwargs)

    def _theme(self):
        return {
            "config": {
                "background": "white",
                "view": {
                    "stroke": "black",
                    "continuousWidth": self.width,
                    "continuousHeight": self.height,
                },
                "axis": {
                    "domain": True,
                    "domainColor": "black",
                    "grid": True,
                    "gridColor": self.colors["grid"],
                    "gridOpacity": 0.25,
                    "labelColor": "black",
                    "labelFont": self.font,
                    "labelFontSize": self.axis_label_font_size,
                    "tickColor": "black",
                    "titleColor": "black",
                    "titleFont": self.font,
                    "titleFontSize": self.axis_title_font_size,
                },
                "legend": {
                    "labelColor": "black",
                    "labelFont": self.font,
                    "labelFontSize": self.legend_font_size,
                    "labelLimit": 320,
                    "orient": "bottom-left",
                    "fillColor": "white",
                    "strokeColor": "#cccccc",
                    "padding": 8,
                    "titleColor": "black",
                    "titleFont": self.font,
                    "titleFontSize": self.legend_font_size,
                },
                "line": {"strokeWidth": self.line_width},
                "point": {"size": self.default_point_size},
                "range": {
                    "category": [
                        self.colors["blue"],
                        self.colors["orange"],
                        self.colors["red"],
                    ]
                },
                "title": {
                    "color": "black",
                    "font": self.font,
                    "fontSize": self.title_font_size,
                    "fontWeight": "normal",
                    "anchor": "middle",
                },
            }
        }


PLOT = PlotProperties()


class PlotAccessor:
    """Shared plot accessor behavior backed by the single plot policy object."""

    def __init__(self, target: Any):
        PLOT.prepare()
        self._target = target

    @property
    def properties(self) -> PlotProperties:
        return PLOT

    def _chart_properties(self, title: str) -> dict[str, object]:
        return PLOT.chart(title)

    def _finish(self, chart, *, save: str | Path | None = None):
        return PLOT.finish(chart, save=save)
