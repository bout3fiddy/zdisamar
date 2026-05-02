"""Instrument-response diagnostic plots."""

from __future__ import annotations

from typing import Literal

import altair as alt

from ._common import frame, label, with_channel_labels
from .spectrum import DEFAULT_HEIGHT, DEFAULT_WIDTH


def kernel(
    response,
    *,
    nominal_wavelength_nm: float | None = None,
    channel: Literal["radiance", "irradiance"] | None = "radiance",
    x: Literal["offset_nm", "support_wavelength_nm"] = "offset_nm",
    as_area: bool = False,
):
    data = with_channel_labels(response)
    required = ["nominal_wavelength_nm", "channel_label", x, "weight"]
    for column in required:
        if column not in data.columns:
            raise ValueError(f"missing required plotting column: {column}")
    if channel is not None:
        data = data[data["channel_label"] == channel]
    if nominal_wavelength_nm is not None:
        nearest = (data["nominal_wavelength_nm"] - float(nominal_wavelength_nm)).abs().idxmin()
        selected = float(data.loc[nearest, "nominal_wavelength_nm"])
        data = data[data["nominal_wavelength_nm"] == selected]
    mark = alt.Chart(data).mark_area(opacity=0.45) if as_area else alt.Chart(data).mark_line()
    return (
        mark.encode(
            x=alt.X(f"{x}:Q", title=label(x)),
            y=alt.Y("weight:Q", title="Weight"),
            color=alt.Color("channel_label:N", title="Channel"),
            tooltip=[
                alt.Tooltip("nominal_wavelength_nm:Q", title="Nominal wavelength (nm)", format=".4f"),
                alt.Tooltip(f"{x}:Q", title=label(x), format=".5f"),
                alt.Tooltip("weight:Q", title="Weight", format=".5g"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="Instrument response kernel")
    )


def matrix(
    response,
    *,
    channel: Literal["radiance", "irradiance"] = "radiance",
):
    data = with_channel_labels(response)
    data = data[data["channel_label"] == channel]
    return (
        alt.Chart(data)
        .mark_rect()
        .encode(
            x=alt.X("support_wavelength_nm:Q", title="Support wavelength (nm)"),
            y=alt.Y("nominal_wavelength_nm:Q", title="Nominal wavelength (nm)"),
            color=alt.Color("weight:Q", title="Weight", scale=alt.Scale(scheme="greys")),
            tooltip=[
                alt.Tooltip("support_wavelength_nm:Q", title="Support wavelength (nm)", format=".5f"),
                alt.Tooltip("nominal_wavelength_nm:Q", title="Nominal wavelength (nm)", format=".5f"),
                alt.Tooltip("weight:Q", title="Weight", format=".5g"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="Instrument response matrix")
    )


def support_width(
    response,
    *,
    y: Literal["support_width_nm", "support_count"] = "support_width_nm",
):
    data = with_channel_labels(response)
    data = frame(data, ["nominal_wavelength_nm", "channel_label", y]).drop_duplicates(
        subset=["nominal_wavelength_nm", "channel_label"]
    )
    return (
        alt.Chart(data)
        .mark_line(point=True)
        .encode(
            x=alt.X("nominal_wavelength_nm:Q", title="Nominal wavelength (nm)"),
            y=alt.Y(f"{y}:Q", title=label(y)),
            color=alt.Color("channel_label:N", title="Channel"),
            tooltip=[
                alt.Tooltip("nominal_wavelength_nm:Q", title="Nominal wavelength (nm)", format=".4f"),
                alt.Tooltip(f"{y}:Q", title=label(y), format=".4g"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="Instrument support width")
    )


def weight_rank(
    response,
    *,
    nominal_wavelength_nm: float,
    channel: Literal["radiance", "irradiance"] = "radiance",
    top_n: int | None = None,
):
    data = with_channel_labels(response)
    data = data[data["channel_label"] == channel].copy()
    nearest = (data["nominal_wavelength_nm"] - float(nominal_wavelength_nm)).abs().idxmin()
    selected = float(data.loc[nearest, "nominal_wavelength_nm"])
    data = data[data["nominal_wavelength_nm"] == selected].sort_values("weight", ascending=False)
    if top_n is not None:
        data = data.head(top_n)
    return (
        alt.Chart(data)
        .mark_bar(color="#737373")
        .encode(
            x=alt.X("sample_index:O", title="Support sample"),
            y=alt.Y("weight:Q", title="Weight"),
            tooltip=[
                alt.Tooltip("sample_index:O", title="Sample"),
                alt.Tooltip("offset_nm:Q", title="Offset (nm)", format=".5f"),
                alt.Tooltip("weight:Q", title="Weight", format=".5g"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="Dominant support weights")
    )
