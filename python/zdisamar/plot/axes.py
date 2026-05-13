"""Shared Altair axis and O2 A wavelength helpers."""

import math

import altair as alt

from . import fields
from .properties import PLOT


def label(name: str) -> str:

    return fields.QUANTITY_LABELS.get(name, name.replace("_", " "))


def wavelength_x():

    return alt.X(
        f"{fields.WAVELENGTH_NM}:Q",
        title=fields.QUANTITY_LABELS[fields.WAVELENGTH_NM],
        axis=alt.Axis(tickMinStep=5),
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


def scaled_y(data, field: str, title: str, *, axis: alt.Axis | None = None):
    """Return data and a y encoding with one shared exponent in the axis title."""

    plot_data = data
    plot_field = field
    scale_factor = _axis_scale_factor(data[field])

    if scale_factor != 1.0:
        plot_field = f"{field}_scaled"
        plot_data = data.copy()
        plot_data[plot_field] = data[field].astype(float) / scale_factor
        title = f"{title} ({_scale_label(scale_factor)})"

    return (
        plot_data,
        plot_field,
        alt.Y(
            f"{plot_field}:Q",
            title=title,
            axis=axis or alt.Axis(format=".4g"),
            scale=finite_padded_scale(plot_data[plot_field]),
        ),
    )


def scaled_x(data, field: str, title: str, *, axis: alt.Axis | None = None):
    """Return data and an x encoding with one shared exponent in the axis title."""

    plot_data = data
    plot_field = field
    scale_factor = _axis_scale_factor(data[field])

    if scale_factor != 1.0:
        plot_field = f"{field}_scaled"
        plot_data = data.copy()
        plot_data[plot_field] = data[field].astype(float) / scale_factor
        title = f"{title} ({_scale_label(scale_factor)})"

    return (
        plot_data,
        plot_field,
        alt.X(
            f"{plot_field}:Q",
            title=title,
            axis=axis or alt.Axis(format=".4g"),
            scale=finite_padded_scale(plot_data[plot_field]),
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


def _axis_scale_factor(values) -> float:

    finite = _finite_values(values)

    if not finite:
        return 1.0

    max_abs = max(abs(value) for value in finite)

    if max_abs == 0.0 or 1.0e-2 <= max_abs < 1.0e4:
        return 1.0

    exponent = int(math.floor(math.log10(max_abs) / 3.0) * 3)

    return 10.0**exponent


def _scale_label(scale_factor: float) -> str:

    exponent = int(round(math.log10(scale_factor)))

    return f"1e{exponent:+d}"


def _finite_values(values) -> list[float]:

    return [float(value) for value in values if math.isfinite(float(value))]
