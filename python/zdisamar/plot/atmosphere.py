"""Atmospheric budget plots."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Literal

import altair as alt

from . import fields
from ._common import component_sums, frame, interval_profile_rows, label, nearest_wavelength_value, numeric_cell_bounds
from .spectrum import DEFAULT_HEIGHT, DEFAULT_WIDTH
from .theme import SEMANTIC_COLORS

DEFAULT_COMPONENTS = (
    "gas_absorption_optical_depth",
    "gas_scattering_optical_depth",
    fields.CIA_OPTICAL_DEPTH,
    fields.AEROSOL_OPTICAL_DEPTH,
    fields.CLOUD_OPTICAL_DEPTH,
)


def optical_depth_heatmap(
    budget,
    *,
    quantity: str = fields.TOTAL_OPTICAL_DEPTH,
    vertical_axis: Literal["altitude_km", "pressure_hpa"] = "altitude_km",
    log_color: bool = False,
    markers_nm: Sequence[float] = (),
):
    data = frame(budget, [fields.WAVELENGTH_NM, vertical_axis, quantity])
    if "support_row_kind_label" in data.columns:
        active = data[data["support_row_kind_label"] == "parity_active"].copy()
        if not active.empty:
            data = active
    data = numeric_cell_bounds(data, fields.WAVELENGTH_NM, y=vertical_axis)
    color_scale = alt.Scale(scheme="greys", type="log" if log_color else "linear")
    y_scale = alt.Scale(reverse=True) if vertical_axis == "pressure_hpa" else alt.Scale()
    heatmap = (
        alt.Chart(data)
        .mark_rect()
        .encode(
            x=alt.X(
                "_x_start:Q",
                title=label(fields.WAVELENGTH_NM),
                scale=alt.Scale(zero=False),
                axis=alt.Axis(tickMinStep=5),
            ),
            x2="_x_end:Q",
            y=alt.Y("_y_start:Q", title=label(vertical_axis), scale=y_scale),
            y2="_y_end:Q",
            color=alt.Color(f"{quantity}:Q", title=label(quantity), scale=color_scale),
            tooltip=_tooltip([fields.WAVELENGTH_NM, vertical_axis, quantity]),
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title=label(quantity))
    )
    if not markers_nm:
        return heatmap
    import pandas as pd

    rules = (
        alt.Chart(pd.DataFrame({fields.WAVELENGTH_NM: list(markers_nm)}))
        .mark_rule(color="#737373", strokeDash=[4, 3], strokeWidth=0.8)
        .encode(x=f"{fields.WAVELENGTH_NM}:Q")
    )
    return alt.layer(heatmap, rules)


def optical_depth_profile(
    budget,
    *,
    quantity: str = fields.TOTAL_OPTICAL_DEPTH,
    vertical_axis: Literal["altitude_km", "pressure_hpa"] = "altitude_km",
    wavelengths_nm: Sequence[float] | None = None,
):
    wavelength_nm = wavelengths_nm[0] if wavelengths_nm else None
    data = interval_profile_rows(
        budget,
        value=quantity,
        vertical_axis=vertical_axis,
        wavelength_nm=wavelength_nm,
    )
    title = f"{label(quantity)} profile"
    color = alt.value(SEMANTIC_COLORS.get(quantity, "#111111"))
    if wavelength_nm is not None and not data.empty:
        selected = nearest_wavelength_value(data, wavelength_nm)
        title = f"{label(quantity)} profile, {selected:.2f} nm"
        color = alt.value("#111111")
    return (
        alt.Chart(data)
        .mark_point(filled=True, size=26, opacity=0.9)
        .encode(
            x=alt.X(f"{quantity}:Q", title=label(quantity), scale=alt.Scale(zero=False)),
            y=_vertical_y(vertical_axis),
            color=color,
            tooltip=_tooltip([fields.WAVELENGTH_NM, vertical_axis, quantity]),
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title=title)
    )


def component_stack(
    budget,
    *,
    components: Sequence[str] = DEFAULT_COMPONENTS,
    aggregate_layers: bool = True,
):
    data = component_sums(budget, components) if aggregate_layers else component_sums(
        budget, components, group_by=(fields.WAVELENGTH_NM, "global_sublayer_index")
    )
    return (
        alt.Chart(data)
        .mark_area()
        .encode(
            x=alt.X(f"{fields.WAVELENGTH_NM}:Q", title=label(fields.WAVELENGTH_NM)),
            y=alt.Y(f"{fields.VALUE}:Q", title="Optical depth"),
            color=alt.Color("component_label:N", title="Component", legend=alt.Legend(orient="right")),
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip("component_label:N", title="Component"),
                alt.Tooltip(f"{fields.VALUE}:Q", title="Optical depth", format=".4g"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="Optical-depth component stack")
    )


def single_scatter_albedo_profile(
    budget,
    *,
    vertical_axis: str = "altitude_km",
    wavelengths_nm: Sequence[float] | None = None,
):
    wavelength_nm = wavelengths_nm[0] if wavelengths_nm else None
    data = interval_profile_rows(
        budget,
        value="single_scatter_albedo",
        vertical_axis=vertical_axis,
        wavelength_nm=wavelength_nm,
        numerator=fields.TOTAL_SCATTERING_OPTICAL_DEPTH,
        denominator=fields.TOTAL_OPTICAL_DEPTH,
    )
    title = "Single-scatter albedo profile"
    if wavelength_nm is not None and not data.empty:
        title = f"Single-scatter albedo profile, {nearest_wavelength_value(data, wavelength_nm):.2f} nm"
    return (
        alt.Chart(data)
        .mark_point(filled=True, color=SEMANTIC_COLORS["scattering"], size=26, opacity=0.9)
        .encode(
            x=alt.X("single_scatter_albedo:Q", title="Single-scatter albedo", scale=alt.Scale(zero=False)),
            y=_vertical_y(vertical_axis),
            tooltip=_tooltip([fields.WAVELENGTH_NM, vertical_axis, "single_scatter_albedo"]),
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title=title)
    )


def _vertical_y(vertical_axis: str):
    if vertical_axis == "pressure_hpa":
        return alt.Y(f"{vertical_axis}:Q", title=label(vertical_axis), scale=alt.Scale(reverse=True))
    return alt.Y(f"{vertical_axis}:Q", title=label(vertical_axis))


def _tooltip(columns: Sequence[str]):
    return [alt.Tooltip(f"{column}:Q" if column != "component" else f"{column}:N", title=label(column)) for column in columns]
