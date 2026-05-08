"""Altair styling helpers for validation plots."""

from __future__ import annotations

from typing import cast

import altair as alt

type JsonScalar = str | int | float | bool | None
type JsonValue = JsonScalar | list[JsonValue] | dict[str, JsonValue]

VALIDATION_BLUE = "#1f77b4"
VALIDATION_ORANGE = "#ff7f0e"
VALIDATION_RED = "#d62728"
VALIDATION_GREEN = "#2ca02c"
VALIDATION_GRID = "#b0b0b0"


def validation_theme() -> dict[str, JsonValue]:
    mono_font = "Menlo, Monaco, 'Courier New', monospace"
    return {
        "config": {
            "background": "white",
            "font": mono_font,
            "axis": {
                "domain": True,
                "domainColor": "black",
                "domainWidth": 0.8,
                "grid": True,
                "gridColor": VALIDATION_GRID,
                "gridOpacity": 0.32,
                "gridWidth": 0.65,
                "labelColor": "black",
                "labelFont": mono_font,
                "tickColor": "black",
                "tickSize": 4,
                "titleColor": "black",
                "titleFont": mono_font,
            },
            "header": {
                "labelColor": "black",
                "labelFont": mono_font,
                "labelFontSize": 13,
                "titleColor": "black",
                "titleFont": mono_font,
            },
            "legend": {
                "labelFont": mono_font,
                "titleFont": mono_font,
            },
            "text": {"font": mono_font},
            "title": {
                "anchor": "start",
                "color": "black",
                "font": mono_font,
                "fontSize": 15,
                "fontWeight": "normal",
            },
            "view": {
                "continuousHeight": 300,
                "continuousWidth": 420,
                "stroke": "black",
                "strokeWidth": 0.8,
            },
        }
    }


def enable_validation_theme() -> None:
    @alt.theme.register("zdisamar_validation", enable=True)
    def _zdisamar_validation_theme() -> alt.theme.ThemeConfig:
        return cast(alt.theme.ThemeConfig, validation_theme())
