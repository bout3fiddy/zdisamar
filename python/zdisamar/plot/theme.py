"""Altair themes for old-school scientific zdisamar plots."""

from __future__ import annotations

from typing import Literal

import altair as alt

ThemeName = Literal["validation", "journal", "monochrome", "labbook", "talk"]
_THEMES_REGISTERED = False

MATPLOTLIB_BLUE = "#1f77b4"
MATPLOTLIB_ORANGE = "#ff7f0e"
MATPLOTLIB_RED = "#d62728"
MATPLOTLIB_GRID = "#b0b0b0"
MONOTYPE_FONT = "Menlo, Monaco, Consolas, Liberation Mono, DejaVu Sans Mono, monospace"

SEMANTIC_COLORS = {
    "reflectance": "#111111",
    "radiance": "#1F4E79",
    "irradiance": "#2F6B3F",
    "absorption": "#7F1D1D",
    "scattering": "#2A5C7A",
    "total_optical_depth": "#222222",
    "aerosol": "#9C6B1F",
    "cloud": "#6B6B6B",
    "cia": "#8C3F2D",
    "o2_weak_lines": "#4E6E8E",
    "o2_strong_lines": "#111111",
    "o2_line_mixing": "#6A4C7D",
    "residual_positive": "#8B1A1A",
    "residual_negative": "#1F4E79",
}

JOURNAL_PALETTE = [
    SEMANTIC_COLORS["reflectance"],
    SEMANTIC_COLORS["radiance"],
    SEMANTIC_COLORS["irradiance"],
    SEMANTIC_COLORS["absorption"],
    SEMANTIC_COLORS["scattering"],
    SEMANTIC_COLORS["aerosol"],
    SEMANTIC_COLORS["cia"],
    SEMANTIC_COLORS["o2_line_mixing"],
]

MONOCHROME_PALETTE = ["#000000", "#404040", "#737373", "#A6A6A6", "#C7C7C7"]
LABBOOK_PALETTE = ["#111111", "#2A5C7A", "#7F1D1D", "#2F6B3F", "#9C6B1F", "#6A4C7D"]
TALK_PALETTE = ["#000000", "#1F4E79", "#2F6B3F", "#8B1A1A", "#9C6B1F", "#6A4C7D"]


def use_theme(name: ThemeName = "validation") -> None:
    """Enable one of the zdisamar Altair themes."""

    _register_themes()
    if name not in {"validation", "journal", "monochrome", "labbook", "talk"}:
        raise ValueError(f"unknown zdisamar plot theme: {name}")
    alt.themes.enable(f"zdisamar_{name}")


def _register_themes() -> None:
    global _THEMES_REGISTERED
    if _THEMES_REGISTERED:
        return
    alt.themes.register("zdisamar_validation", _validation_theme)
    alt.themes.register("zdisamar_journal", _journal_theme)
    alt.themes.register("zdisamar_monochrome", _monochrome_theme)
    alt.themes.register("zdisamar_labbook", _labbook_theme)
    alt.themes.register("zdisamar_talk", _talk_theme)
    _THEMES_REGISTERED = True


def _base_config(
    *,
    font: str,
    label_size: int,
    title_size: int,
    width: int,
    height: int,
    palette: list[str],
    grid: bool,
    line_width: float,
):
    return {
        "config": {
            "background": "white",
            "view": {
                "stroke": "black",
                "continuousWidth": width,
                "continuousHeight": height,
            },
            "axis": {
                "domain": True,
                "domainColor": "black",
                "grid": grid,
                "gridColor": MATPLOTLIB_GRID,
                "gridOpacity": 0.25 if grid else 1.0,
                "labelColor": "black",
                "labelFont": font,
                "labelFontWeight": "normal",
                "labelFontSize": label_size,
                "tickColor": "black",
                "titleColor": "black",
                "titleFont": font,
                "titleFontWeight": "normal",
                "titleFontSize": title_size,
            },
            "header": {
                "labelColor": "black",
                "labelFont": font,
                "labelFontWeight": "normal",
                "labelFontSize": title_size,
                "titleColor": "black",
                "titleFont": font,
                "titleFontWeight": "normal",
                "titleFontSize": title_size,
            },
            "legend": {
                "labelColor": "black",
                "labelFont": font,
                "labelFontWeight": "normal",
                "labelFontSize": label_size,
                "labelLimit": 320,
                "orient": "bottom-left",
                "fillColor": "white",
                "strokeColor": "#cccccc",
                "padding": 8,
                "symbolStrokeWidth": line_width,
                "titleColor": "black",
                "titleFont": font,
                "titleFontWeight": "normal",
                "titleFontSize": label_size,
            },
            "line": {"strokeWidth": line_width},
            "point": {"size": 28},
            "range": {"category": palette},
            "title": {
                "color": "black",
                "font": font,
                "fontSize": title_size,
                "fontWeight": "normal",
                "anchor": "middle",
            },
        }
    }


def _validation_theme():
    return _base_config(
        font=MONOTYPE_FONT,
        label_size=16,
        title_size=20,
        width=1311,
        height=465,
        palette=[MATPLOTLIB_BLUE, MATPLOTLIB_ORANGE, MATPLOTLIB_RED],
        grid=True,
        line_width=1.4,
    )


def _journal_theme():
    return _base_config(
        font="Liberation Serif, Times New Roman, serif",
        label_size=11,
        title_size=12,
        width=640,
        height=260,
        palette=JOURNAL_PALETTE,
        grid=False,
        line_width=1.2,
    )


def _monochrome_theme():
    return _base_config(
        font="Liberation Serif, Times New Roman, serif",
        label_size=11,
        title_size=12,
        width=620,
        height=240,
        palette=MONOCHROME_PALETTE,
        grid=False,
        line_width=1.2,
    )


def _labbook_theme():
    return _base_config(
        font="Liberation Sans, Arial, sans-serif",
        label_size=10,
        title_size=11,
        width=560,
        height=220,
        palette=LABBOOK_PALETTE,
        grid=True,
        line_width=1.0,
    )


def _talk_theme():
    return _base_config(
        font="Liberation Sans, Arial, sans-serif",
        label_size=15,
        title_size=16,
        width=900,
        height=360,
        palette=TALK_PALETTE,
        grid=False,
        line_width=2.0,
    )
