"""Instrument-response diagnostic plots."""

from __future__ import annotations

from typing import Literal

import altair as alt

from .common import frame, label, numeric_cell_bounds, with_channel_labels
from .spectrum import DEFAULT_HEIGHT, DEFAULT_WIDTH


def isrf(
    response,
    *,
    nominal_wavelength_nm: float = 760.76,
    channel: Literal["radiance", "irradiance"] = "radiance",
):
    data = with_channel_labels(response)
    required = [
        "nominal_wavelength_nm",
        "channel_label",
        "offset_nm",
        "support_wavelength_nm",
        "weight",
        "instrument_fwhm_nm",
    ]
    for column in required:
        if column not in data.columns:
            raise ValueError(f"missing required plotting column: {column}")
    data = data[data["channel_label"] == channel].copy()
    if data.empty:
        raise ValueError(f"no instrument response rows for channel: {channel}")
    nearest = (data["nominal_wavelength_nm"] - float(nominal_wavelength_nm)).abs().idxmin()
    selected = float(data.loc[nearest, "nominal_wavelength_nm"])
    data = data[data["nominal_wavelength_nm"] == selected].sort_values("offset_nm").copy()
    max_weight = float(data["weight"].max())
    if max_weight <= 0.0:
        raise ValueError("instrument response weights are not positive")
    data["normalized_response"] = data["weight"] / max_weight
    plot_data = data[data["weight"] >= max_weight * 1.0e-4].copy()
    if plot_data.empty:
        plot_data = data
    x_min = float(plot_data["offset_nm"].min())
    x_max = float(plot_data["offset_nm"].max())
    x_pad = max((x_max - x_min) * 0.04, 0.01)

    return (
        alt.Chart(plot_data)
        .mark_line(color="#111111", strokeWidth=1.6)
        .encode(
            x=alt.X(
                "offset_nm:Q",
                title="Offset from nominal wavelength (nm)",
                scale=alt.Scale(domain=[x_min - x_pad, x_max + x_pad], zero=False),
            ),
            y=alt.Y(
                "normalized_response:Q",
                title="Normalized ISRF",
                scale=alt.Scale(domain=[0.0, 1.05]),
                axis=alt.Axis(format=".2f"),
            ),
            tooltip=[
                alt.Tooltip("nominal_wavelength_nm:Q", title="Nominal wavelength (nm)", format=".5f"),
                alt.Tooltip("support_wavelength_nm:Q", title="Support wavelength (nm)", format=".5f"),
                alt.Tooltip("offset_nm:Q", title="Offset (nm)", format=".6f"),
                alt.Tooltip("normalized_response:Q", title="Normalized ISRF", format=".5f"),
                alt.Tooltip("weight:Q", title="Native weight", format=".5g"),
                alt.Tooltip("instrument_fwhm_nm:Q", title="FWHM (nm)", format=".5f"),
            ],
        )
        .properties(
            width=DEFAULT_WIDTH,
            height=560,
            title=f"Instrument spectral response function (ISRF), {selected:.5f} nm",
        )
    )


def matrix(
    response,
    *,
    channel: Literal["radiance", "irradiance"] = "radiance",
):
    data = with_channel_labels(response)
    data = data[data["channel_label"] == channel]
    data = numeric_cell_bounds(data, "support_wavelength_nm", y="nominal_wavelength_nm")
    return (
        alt.Chart(data)
        .mark_rect()
        .encode(
            x=alt.X(
                "_x_start:Q",
                title="Support wavelength (nm)",
                scale=alt.Scale(zero=False),
                axis=alt.Axis(tickMinStep=5),
            ),
            x2="_x_end:Q",
            y=alt.Y(
                "_y_start:Q",
                title="Nominal wavelength (nm)",
                scale=alt.Scale(zero=False),
                axis=alt.Axis(tickMinStep=5),
            ),
            y2="_y_end:Q",
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
