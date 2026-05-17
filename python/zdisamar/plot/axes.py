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

    values = data[field]

    return (
        data,
        field,
        alt.Y(
            f"{field}:Q",
            title=title,
            axis=axis or numeric_axis(values, tickCount=PLOT.y_axis_tick_count),
            scale=finite_padded_scale(values),
        ),
    )


def scaled_x(data, field: str, title: str | None, *, axis: alt.Axis | None = None):
    """Return an x encoding without altering the plotted values."""

    values = data[field]

    return (
        data,
        field,
        alt.X(
            f"{field}:Q",
            title=title,
            axis=axis or numeric_axis(values, tickCount=PLOT.x_axis_tick_count),
            scale=finite_padded_scale(values),
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


def numeric_axis(values, *, tickCount: int):  # noqa: N803
    """Return a compact numeric axis without changing plotted data values."""

    exponent = axis_exponent(values)

    if exponent is None:
        return alt.Axis(format="~f", tickCount=tickCount)

    scale = 10.0**exponent

    return alt.Axis(
        labelExpr=f"format(datum.value / {scale:.16e}, '~g')",
        tickCount=tickCount,
    )


def axis_multiplier_text(values):
    """Place one scientific multiplier near the axis for compact tick labels."""

    exponent = axis_exponent(values)

    if exponent is None:
        return None

    import pandas as pd

    return (
        alt.Chart(pd.DataFrame({"axis_multiplier": [f"x1e{exponent}"]}))
        .mark_text(
            align="left",
            baseline="bottom",
            color="black",
            dx=0,
            dy=-10,
            font=PLOT.font,
            fontSize=PLOT.axis_label_font_size,
        )
        .encode(
            x=alt.value(0),
            y=alt.value(0),
            text="axis_multiplier:N",
        )
    )


def axis_exponent(values) -> int | None:
    """Use one power-of-ten multiplier for very small or large tick labels."""

    finite = _finite_values(values)

    if not finite:
        return None

    max_abs = max(abs(value) for value in finite)

    if max_abs == 0.0 or 1.0e-3 <= max_abs < 1.0e3:
        return None

    return int(math.floor(math.log10(max_abs)))


def _finite_values(values) -> list[float]:

    return [float(value) for value in values if math.isfinite(float(value))]
