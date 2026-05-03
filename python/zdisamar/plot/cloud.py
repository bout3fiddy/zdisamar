"""Cloud diagnostic plots."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Literal

import altair as alt

from . import fields
from ._common import frame, label, nearest_wavelength_rows
from .spectrum import DEFAULT_HEIGHT, DEFAULT_WIDTH
from .theme import SEMANTIC_COLORS


def share_spectrum(
    budget,
    *,
    share: Literal["total", "scattering", "absorption"] = "total",
):
    import numpy as np

    numerator = {
        "total": fields.CLOUD_OPTICAL_DEPTH,
        "scattering": "cloud_scattering_optical_depth",
        "absorption": "cloud_absorption_optical_depth",
    }[share]
    data = frame(budget, [fields.WAVELENGTH_NM, numerator, fields.TOTAL_OPTICAL_DEPTH])
    grouped = data.groupby(fields.WAVELENGTH_NM, as_index=False)[[numerator, fields.TOTAL_OPTICAL_DEPTH]].sum()
    grouped["cloud_share"] = np.divide(
        grouped[numerator],
        grouped[fields.TOTAL_OPTICAL_DEPTH],
        out=np.zeros(grouped.shape[0], dtype=float),
        where=grouped[fields.TOTAL_OPTICAL_DEPTH] > 0.0,
    )
    return (
        alt.Chart(grouped)
        .mark_line(color=SEMANTIC_COLORS["cloud"])
        .encode(
            x=alt.X(f"{fields.WAVELENGTH_NM}:Q", title=label(fields.WAVELENGTH_NM)),
            y=alt.Y("cloud_share:Q", title=f"Cloud {share} share"),
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip("cloud_share:Q", title="Share", format=".3g"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title=f"Cloud {share} share spectrum")
    )


def optical_depth_profile(
    budget,
    *,
    vertical_axis: str = "altitude_km",
    wavelengths_nm: Sequence[float] | None = None,
):
    data = nearest_wavelength_rows(budget, wavelengths_nm) if wavelengths_nm else frame(
        budget, [fields.WAVELENGTH_NM, vertical_axis, fields.CLOUD_OPTICAL_DEPTH]
    )
    return (
        alt.Chart(data)
        .mark_line(point=True, color=SEMANTIC_COLORS["cloud"])
        .encode(
            x=alt.X(f"{fields.CLOUD_OPTICAL_DEPTH}:Q", title=label(fields.CLOUD_OPTICAL_DEPTH)),
            y=_vertical_y(vertical_axis),
            color=alt.Color(f"{fields.WAVELENGTH_NM}:N", title="Wavelength (nm)"),
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip(f"{vertical_axis}:Q", title=label(vertical_axis), format=".4g"),
                alt.Tooltip(f"{fields.CLOUD_OPTICAL_DEPTH}:Q", title=label(fields.CLOUD_OPTICAL_DEPTH), format=".3g"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="Cloud optical-depth profile")
    )


def _vertical_y(vertical_axis: str):
    if vertical_axis == "pressure_hpa":
        return alt.Y(f"{vertical_axis}:Q", title=label(vertical_axis), scale=alt.Scale(reverse=True))
    return alt.Y(f"{vertical_axis}:Q", title=label(vertical_axis))
