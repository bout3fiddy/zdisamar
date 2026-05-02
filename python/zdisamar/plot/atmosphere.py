"""Atmospheric budget plots."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Literal

import altair as alt

from . import fields
from ._common import component_sums, frame, label, nearest_wavelength_rows
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
    color_scale = alt.Scale(scheme="greys", type="log" if log_color else "linear")
    heatmap = (
        alt.Chart(data)
        .mark_rect()
        .encode(
            x=alt.X(f"{fields.WAVELENGTH_NM}:Q", title=label(fields.WAVELENGTH_NM)),
            y=_vertical_y(vertical_axis),
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
    data = nearest_wavelength_rows(budget, wavelengths_nm) if wavelengths_nm else frame(
        budget, [fields.WAVELENGTH_NM, vertical_axis, quantity]
    )
    return (
        alt.Chart(data)
        .mark_line(point=True)
        .encode(
            x=alt.X(f"{quantity}:Q", title=label(quantity)),
            y=_vertical_y(vertical_axis),
            color=alt.Color(f"{fields.WAVELENGTH_NM}:N", title="Wavelength (nm)"),
            tooltip=_tooltip([fields.WAVELENGTH_NM, vertical_axis, quantity]),
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title=f"{label(quantity)} profile")
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
            color=alt.Color("component:N", title="Component"),
            tooltip=_tooltip([fields.WAVELENGTH_NM, "component", fields.VALUE]),
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="Optical-depth component stack")
    )


def single_scatter_albedo_profile(
    budget,
    *,
    vertical_axis: str = "altitude_km",
    wavelengths_nm: Sequence[float] | None = None,
):
    data = nearest_wavelength_rows(budget, wavelengths_nm) if wavelengths_nm else frame(
        budget, [fields.WAVELENGTH_NM, vertical_axis, "single_scatter_albedo"]
    )
    return (
        alt.Chart(data)
        .mark_line(point=True, color=SEMANTIC_COLORS["scattering"])
        .encode(
            x=alt.X("single_scatter_albedo:Q", title="Single-scatter albedo", scale=alt.Scale(domain=[0, 1])),
            y=_vertical_y(vertical_axis),
            color=alt.Color(f"{fields.WAVELENGTH_NM}:N", title="Wavelength (nm)"),
            tooltip=_tooltip([fields.WAVELENGTH_NM, vertical_axis, "single_scatter_albedo"]),
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="Single-scatter albedo profile")
    )


def _vertical_y(vertical_axis: str):
    if vertical_axis == "pressure_hpa":
        return alt.Y(f"{vertical_axis}:Q", title=label(vertical_axis), scale=alt.Scale(reverse=True))
    return alt.Y(f"{vertical_axis}:Q", title=label(vertical_axis))


def _tooltip(columns: Sequence[str]):
    return [alt.Tooltip(f"{column}:Q" if column != "component" else f"{column}:N", title=label(column)) for column in columns]
