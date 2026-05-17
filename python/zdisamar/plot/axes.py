"""Shared Altair axis and O2 A wavelength helpers."""

import altair as alt

from . import fields
from .properties import PLOT


def label(name: str) -> str:

    return fields.QUANTITY_LABELS.get(name, name.replace("_", " "))


def wavelength_x():

    return alt.X(
        f"{fields.WAVELENGTH_NM}:Q",
        title=fields.QUANTITY_LABELS[fields.WAVELENGTH_NM],
        axis=alt.Axis(grid=False, tickCount=6, tickMinStep=5),
        scale=alt.Scale(zero=False),
    )


def marker_rules(data):
    """Draw fixed O2 A reference wavelengths only inside the plotted band."""

    import pandas as pd

    start = float(data[fields.WAVELENGTH_NM].min())
    end = float(data[fields.WAVELENGTH_NM].max())
    markers = [value for value in PLOT.markers_nm if start <= value <= end]

    return (
        alt.Chart(pd.DataFrame({fields.WAVELENGTH_NM: markers}))
        .mark_rule(
            color=PLOT.colors["neutral"],
            strokeDash=list(PLOT.marker_rule_dash),
            strokeWidth=PLOT.marker_rule_width,
        )
        .encode(x=f"{fields.WAVELENGTH_NM}:Q")
    )


def scaled_y(data, field: str, title: str | None, *, axis: alt.Axis | None = None):
    """Return a y encoding without altering the plotted values."""

    return (
        data,
        field,
        alt.Y(
            f"{field}:Q",
            title=title,
            axis=axis or alt.Axis(tickCount=PLOT.y_axis_tick_count),
            scale=finite_padded_scale(data[field]),
        ),
    )


def scaled_x(data, field: str, title: str | None, *, axis: alt.Axis | None = None):
    """Return an x encoding without altering the plotted values."""

    return (
        data,
        field,
        alt.X(
            f"{field}:Q",
            title=title,
            axis=axis or alt.Axis(tickCount=PLOT.x_axis_tick_count),
            scale=finite_padded_scale(data[field]),
        ),
    )


def finite_padded_scale(values):
    """Pad finite y-ranges so flat or single-point plots remain readable."""

    finite = _finite_values(values)

    if not finite:
        return alt.Scale(zero=False)

    low = min(finite)
    high = max(finite)
    pad = max(abs(low) * 0.05, 1.0) if low == high else (high - low) * 0.04

    return alt.Scale(domain=[low - pad, high + pad], zero=False)


def _finite_values(values) -> list[float]:

    import math

    return [float(value) for value in values if math.isfinite(float(value))]
