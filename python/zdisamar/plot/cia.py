"""O2-O2 CIA diagnostic plots."""

from __future__ import annotations

from typing import Literal

import altair as alt

from . import fields
from ._common import frame, interval_profile_rows, label, nearest_wavelength_value
from .spectrum import DEFAULT_HEIGHT, DEFAULT_WIDTH
from .theme import SEMANTIC_COLORS


def share_profile(
    cia,
    *,
    share: Literal["cia_share_of_total_absorption", "cia_share_of_total_optical_depth"] = "cia_share_of_total_absorption",
    vertical_axis: str = "altitude_km",
    wavelength_nm: float | None = None,
):
    denominator = (
        fields.TOTAL_ABSORPTION_OPTICAL_DEPTH
        if share == "cia_share_of_total_absorption"
        else fields.TOTAL_OPTICAL_DEPTH
    )
    data = interval_profile_rows(
        cia,
        value=share,
        vertical_axis=vertical_axis,
        wavelength_nm=wavelength_nm,
        numerator=fields.CIA_OPTICAL_DEPTH,
        denominator=denominator,
    )
    title = "CIA share profile"
    if wavelength_nm is not None and not data.empty:
        title = f"CIA share profile, {nearest_wavelength_value(data, wavelength_nm):.2f} nm"
    return (
        alt.Chart(data)
        .mark_point(filled=True, color=SEMANTIC_COLORS["cia"], size=26, opacity=0.9)
        .encode(
            x=alt.X(f"{share}:Q", title=label(share), scale=alt.Scale(zero=False), axis=alt.Axis(format=".2e")),
            y=_vertical_y(vertical_axis),
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip(f"{vertical_axis}:Q", title=label(vertical_axis), format=".4g"),
                alt.Tooltip(f"{share}:Q", title=label(share), format=".3g"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title=title)
    )


def optical_depth_profile(
    cia,
    *,
    vertical_axis: str = "altitude_km",
    wavelength_nm: float | None = None,
):
    data = interval_profile_rows(
        cia,
        value=fields.CIA_OPTICAL_DEPTH,
        vertical_axis=vertical_axis,
        wavelength_nm=wavelength_nm,
    )
    title = "O2-O2 CIA optical depth profile"
    if wavelength_nm is not None and not data.empty:
        title = f"O2-O2 CIA optical depth profile, {nearest_wavelength_value(data, wavelength_nm):.2f} nm"
    return (
        alt.Chart(data)
        .mark_point(filled=True, color=SEMANTIC_COLORS["cia"], size=26, opacity=0.9)
        .encode(
            x=alt.X(
                f"{fields.CIA_OPTICAL_DEPTH}:Q",
                title=label(fields.CIA_OPTICAL_DEPTH),
                scale=alt.Scale(zero=False),
                axis=alt.Axis(format=".2e"),
            ),
            y=_vertical_y(vertical_axis),
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip(f"{vertical_axis}:Q", title=label(vertical_axis), format=".4g"),
                alt.Tooltip(f"{fields.CIA_OPTICAL_DEPTH}:Q", title=label(fields.CIA_OPTICAL_DEPTH), format=".4e"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title=title)
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
    wavelength_nm: float | None = None,
):
    data = _active_rows(cia, ["temperature_k", y, color, fields.WAVELENGTH_NM], wavelength_nm=wavelength_nm)
    if log_y:
        data = data[data[y] > 0.0].copy()
    y_encoding = alt.Y(f"{y}:Q", title=label(y), scale=alt.Scale(type="log")) if log_y else alt.Y(f"{y}:Q", title=label(y))
    title = "CIA cross section by temperature"
    if wavelength_nm is not None and not data.empty:
        title = f"CIA cross section by temperature, {nearest_wavelength_value(data, wavelength_nm):.2f} nm"
    return (
        alt.Chart(data)
        .mark_point(filled=True, color=SEMANTIC_COLORS["cia"], opacity=0.75)
        .encode(
            x=alt.X("temperature_k:Q", title="Temperature (K)", scale=alt.Scale(zero=False)),
            y=y_encoding,
            color=alt.Color(f"{color}:Q", title=label(color)),
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip("temperature_k:Q", title="Temperature (K)", format=".3g"),
                alt.Tooltip(f"{color}:Q", title=label(color), format=".3g"),
                alt.Tooltip(f"{y}:Q", title=label(y), format=".3e"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title=title)
    )


def _active_rows(cia, required: list[str], *, wavelength_nm: float | None):
    import numpy as np

    data = frame(cia, required).copy()
    if wavelength_nm is not None:
        selected = nearest_wavelength_value(data, wavelength_nm)
        data = data[data[fields.WAVELENGTH_NM] == selected].copy()
    if "path_length_cm" in data.columns:
        active = data[data["path_length_cm"] > 0.0].copy()
        if not active.empty:
            data = active
    finite = np.ones(len(data), dtype=bool)
    for column in required:
        if data[column].dtype.kind in "fiu":
            finite &= np.isfinite(data[column].to_numpy(dtype=float))
    return data.loc[finite].copy()


def _vertical_y(vertical_axis: str):
    if vertical_axis == "pressure_hpa":
        return alt.Y(f"{vertical_axis}:Q", title=label(vertical_axis), scale=alt.Scale(reverse=True))
    return alt.Y(f"{vertical_axis}:Q", title=label(vertical_axis))
