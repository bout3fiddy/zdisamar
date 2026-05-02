"""O2-O2 CIA diagnostic plots."""

from __future__ import annotations

from typing import Literal

import altair as alt

from . import fields
from ._common import frame, label
from .spectrum import DEFAULT_HEIGHT, DEFAULT_WIDTH
from .theme import SEMANTIC_COLORS


def share_profile(
    cia,
    *,
    share: Literal["cia_share_of_total_absorption", "cia_share_of_total_optical_depth"] = "cia_share_of_total_absorption",
    vertical_axis: str = "altitude_km",
):
    data = frame(cia, [fields.WAVELENGTH_NM, vertical_axis, share])
    return (
        alt.Chart(data)
        .mark_line(point=True, color=SEMANTIC_COLORS["cia"])
        .encode(
            x=alt.X(f"{share}:Q", title=label(share)),
            y=_vertical_y(vertical_axis),
            color=alt.Color(f"{fields.WAVELENGTH_NM}:N", title="Wavelength (nm)"),
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip(f"{vertical_axis}:Q", title=label(vertical_axis), format=".4g"),
                alt.Tooltip(f"{share}:Q", title=label(share), format=".3g"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="CIA share profile")
    )


def share_spectrum(
    cia,
    *,
    denominator: Literal["absorption", "total"] = "absorption",
):
    import numpy as np

    denominator_field = {
        "absorption": fields.TOTAL_ABSORPTION_OPTICAL_DEPTH,
        "total": fields.TOTAL_OPTICAL_DEPTH,
    }[denominator]
    data = frame(cia, [fields.WAVELENGTH_NM, fields.CIA_OPTICAL_DEPTH, denominator_field])
    grouped = data.groupby(fields.WAVELENGTH_NM, as_index=False)[[fields.CIA_OPTICAL_DEPTH, denominator_field]].sum()
    grouped["cia_share"] = np.divide(
        grouped[fields.CIA_OPTICAL_DEPTH],
        grouped[denominator_field],
        out=np.zeros(grouped.shape[0], dtype=float),
        where=grouped[denominator_field] > 0.0,
    )
    return (
        alt.Chart(grouped)
        .mark_line(color=SEMANTIC_COLORS["cia"])
        .encode(
            x=alt.X(f"{fields.WAVELENGTH_NM}:Q", title=label(fields.WAVELENGTH_NM)),
            y=alt.Y("cia_share:Q", title=f"CIA share of {denominator}"),
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip("cia_share:Q", title="Share", format=".3g"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="CIA share spectrum")
    )


def cross_section_temperature(
    cia,
    *,
    y: str = "cia_cross_section_cm5_per_molecule2",
    color: str = "pressure_hpa",
    log_y: bool = True,
):
    data = frame(cia, ["temperature_k", y, color, fields.WAVELENGTH_NM])
    y_encoding = alt.Y(f"{y}:Q", title=label(y), scale=alt.Scale(type="log")) if log_y else alt.Y(f"{y}:Q", title=label(y))
    return (
        alt.Chart(data)
        .mark_point(filled=True, color=SEMANTIC_COLORS["cia"], opacity=0.75)
        .encode(
            x=alt.X("temperature_k:Q", title="Temperature (K)"),
            y=y_encoding,
            color=alt.Color(f"{color}:Q", title=label(color)),
            column=alt.Column(f"{fields.WAVELENGTH_NM}:N", title="Wavelength (nm)"),
            tooltip=[
                alt.Tooltip("temperature_k:Q", title="Temperature (K)", format=".3g"),
                alt.Tooltip(f"{color}:Q", title=label(color), format=".3g"),
                alt.Tooltip(f"{y}:Q", title=label(y), format=".3e"),
            ],
        )
        .properties(width=300, height=260, title="CIA cross section by temperature")
    )


def _vertical_y(vertical_axis: str):
    if vertical_axis == "pressure_hpa":
        return alt.Y(f"{vertical_axis}:Q", title=label(vertical_axis), scale=alt.Scale(reverse=True))
    return alt.Y(f"{vertical_axis}:Q", title=label(vertical_axis))
