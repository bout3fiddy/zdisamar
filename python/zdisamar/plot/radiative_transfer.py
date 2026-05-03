"""Radiative-transfer proxy diagnostic plots."""

from __future__ import annotations

from collections.abc import Sequence

import altair as alt

from . import fields
from ._common import frame, label, melt_components
from .spectrum import DEFAULT_HEIGHT, DEFAULT_WIDTH

SOURCE_COMPONENTS = (
    "atmospheric_scattering_source_proxy",
    "absorption_loss_proxy",
)

SHARE_COMPONENTS = (
    "atmospheric_scattering_source_proxy",
    "absorption_loss_proxy",
    "direct_surface_transmission_proxy",
)


def source_profile(
    rt,
    *,
    components: Sequence[str] = SOURCE_COMPONENTS,
    vertical_axis: str = "altitude_km",
):
    data = melt_components(rt, components, id_vars=(fields.WAVELENGTH_NM, vertical_axis))
    return (
        alt.Chart(data)
        .mark_line(point=True)
        .encode(
            x=alt.X(f"{fields.VALUE}:Q", title="Proxy value"),
            y=_vertical_y(vertical_axis),
            color=alt.Color("component_label:N", title="Component", legend=alt.Legend(orient="right")),
            column=alt.Column(f"{fields.WAVELENGTH_NM}:N", title="Wavelength (nm)"),
            tooltip=[
                alt.Tooltip("component_label:N", title="Component"),
                alt.Tooltip(f"{vertical_axis}:Q", title=label(vertical_axis), format=".4g"),
                alt.Tooltip(f"{fields.VALUE}:Q", title="Value", format=".3g"),
            ],
        )
        .properties(width=300, height=300, title="RT source/loss profile")
    )


def cumulative_transmission(
    rt,
    *,
    vertical_axis: str = "altitude_km",
):
    data = melt_components(
        rt,
        ("cumulative_optical_depth_above", "direct_surface_transmission_proxy"),
        id_vars=(fields.WAVELENGTH_NM, vertical_axis),
    )
    return (
        alt.Chart(data)
        .mark_line(point=True)
        .encode(
            x=alt.X(f"{fields.VALUE}:Q", title="Value"),
            y=_vertical_y(vertical_axis),
            color=alt.Color("component_label:N", title="Quantity", legend=alt.Legend(orient="right")),
            column=alt.Column(f"{fields.WAVELENGTH_NM}:N", title="Wavelength (nm)"),
            tooltip=[
                alt.Tooltip("component_label:N", title="Quantity"),
                alt.Tooltip(f"{vertical_axis}:Q", title=label(vertical_axis), format=".4g"),
                alt.Tooltip(f"{fields.VALUE}:Q", title="Value", format=".3g"),
            ],
        )
        .properties(width=300, height=300, title="Cumulative optical depth and transmission")
        .resolve_scale(x="independent")
    )


def proxy_share_bar(
    rt,
    *,
    components: Sequence[str] = SHARE_COMPONENTS,
    normalize: bool = True,
):
    data = melt_components(rt, components, id_vars=(fields.WAVELENGTH_NM,))
    grouped = data.groupby([fields.WAVELENGTH_NM, "component", "component_label"], as_index=False)[fields.VALUE].sum()
    if normalize:
        totals = grouped.groupby(fields.WAVELENGTH_NM)[fields.VALUE].transform("sum")
        grouped[fields.VALUE] = grouped[fields.VALUE] / totals.where(totals != 0.0, 1.0)
    return (
        alt.Chart(grouped)
        .mark_bar()
        .encode(
            x=alt.X(f"{fields.WAVELENGTH_NM}:N", title="Wavelength (nm)"),
            y=alt.Y(f"{fields.VALUE}:Q", title="Share" if normalize else "Contribution"),
            color=alt.Color("component_label:N", title="Component", legend=alt.Legend(orient="right")),
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:N", title="Wavelength (nm)"),
                alt.Tooltip("component_label:N", title="Component"),
                alt.Tooltip(f"{fields.VALUE}:Q", title="Value", format=".3g"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="RT proxy share")
    )


def pseudo_spherical_airmass_profile(
    rt,
    *,
    vertical_axis: str = "altitude_km",
):
    data = frame(rt, [fields.WAVELENGTH_NM, vertical_axis, "pseudo_spherical_airmass_factor"])
    return (
        alt.Chart(data)
        .mark_line(point=True)
        .encode(
            x=alt.X("pseudo_spherical_airmass_factor:Q", title="Pseudo-spherical airmass factor"),
            y=_vertical_y(vertical_axis),
            color=alt.Color(f"{fields.WAVELENGTH_NM}:N", title="Wavelength (nm)"),
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip("pseudo_spherical_airmass_factor:Q", title="Airmass factor", format=".4g"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="Pseudo-spherical airmass profile")
    )


def _vertical_y(vertical_axis: str):
    if vertical_axis == "pressure_hpa":
        return alt.Y(f"{vertical_axis}:Q", title=label(vertical_axis), scale=alt.Scale(reverse=True))
    return alt.Y(f"{vertical_axis}:Q", title=label(vertical_axis))
