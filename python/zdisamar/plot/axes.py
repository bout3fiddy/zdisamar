"""Shared axis and O2 A wavelength helpers."""

import math
from dataclasses import dataclass

from . import fields
from .properties import PLOT


@dataclass(frozen=True)
class ScaleSpec:
    """Small scale object kept for tests and SVG plot construction."""

    domain: tuple[float, float] | None = None
    zero: bool = False

    def to_dict(self) -> dict[str, object]:

        result: dict[str, object] = {"zero": self.zero}

        if self.domain is not None:
            result["domain"] = [self.domain[0], self.domain[1]]

        return result


@dataclass(frozen=True)
class AxisSpec:
    """Small axis object kept independent of any plotting package."""

    format: str = ".4g"
    tickCount: int = 5  # noqa: N815
    labelExpr: str | None = None  # noqa: N815

    def to_dict(self) -> dict[str, object]:

        result: dict[str, object] = {"format": self.format, "tickCount": self.tickCount}

        if self.labelExpr is not None:
            result["labelExpr"] = self.labelExpr

        return result


@dataclass(frozen=True)
class EncodingSpec:
    """Axis encoding object with the old `to_dict()` inspection surface."""

    field: str
    title: str | None
    axis: AxisSpec
    scale: ScaleSpec

    def to_dict(self) -> dict[str, object]:

        return {
            "field": self.field,
            "type": "quantitative",
            "title": self.title,
            "axis": self.axis.to_dict(),
            "scale": self.scale.to_dict(),
        }


def label(name: str) -> str:

    return fields.QUANTITY_LABELS.get(name, name.replace("_", " "))


def wavelength_x():

    return EncodingSpec(
        field=fields.WAVELENGTH_NM,
        title=fields.QUANTITY_LABELS[fields.WAVELENGTH_NM],
        axis=AxisSpec(tickCount=6),
        scale=ScaleSpec(zero=False),
    )


def marker_values(values) -> list[float]:
    """Draw fixed O2 A reference wavelengths only inside the plotted band."""

    finite = finite_values(values)

    if not finite:
        return []

    start = min(finite)
    end = max(finite)

    return [value for value in PLOT.markers_nm if start <= value <= end]


def marker_rules(data):
    """Return marker values for callers that still inspect this helper."""

    if isinstance(data, dict):
        return marker_values(data[fields.WAVELENGTH_NM])

    return marker_values(row[fields.WAVELENGTH_NM] for row in data)


def scaled_y(
    data,
    field: str,
    title: str | None,
    *,
    axis: AxisSpec | None = None,
    compact_axis: bool = False,
):
    """Return a y encoding without altering the plotted values."""

    values = data[field]

    return (
        data,
        field,
        EncodingSpec(
            field=field,
            title=title,
            axis=axis or default_numeric_axis(values, PLOT.y_axis_tick_count, compact_axis),
            scale=finite_padded_scale(values),
        ),
    )


def scaled_x(
    data,
    field: str,
    title: str | None,
    *,
    axis: AxisSpec | None = None,
    compact_axis: bool = False,
):
    """Return an x encoding without altering the plotted values."""

    values = data[field]

    return (
        data,
        field,
        EncodingSpec(
            field=field,
            title=title,
            axis=axis or default_numeric_axis(values, PLOT.x_axis_tick_count, compact_axis),
            scale=finite_padded_scale(values),
        ),
    )


def finite_padded_scale(values):
    """Pad finite y-ranges so flat or single-point plots remain readable."""

    domain = finite_padded_domain(values)

    if domain is None:
        return ScaleSpec(zero=False)

    return ScaleSpec(domain=domain, zero=False)


def finite_padded_domain(values) -> tuple[float, float] | None:
    """Return the finite padded domain used by all SVG plots."""

    finite = finite_values(values)

    if not finite:
        return None

    low = min(finite)
    high = max(finite)

    pad = max(abs(low) * 0.05, 1.0e-12) if low == high else (high - low) * 0.04

    return (low - pad, high + pad)


def default_numeric_axis(values, tick_count: int, compact_axis: bool) -> AxisSpec:

    if compact_axis:
        return numeric_axis(values, tickCount=tick_count)

    return AxisSpec(format=".4g", tickCount=tick_count)


def numeric_axis(values, *, tickCount: int):  # noqa: N803
    """Return a compact numeric axis without changing plotted data values."""

    exponent = axis_exponent(values)

    if exponent is None:
        return AxisSpec(format="~f", tickCount=tickCount)

    scale = 10.0**exponent

    return AxisSpec(
        format="~g",
        labelExpr=f"format(datum.value / {scale:.16e}, '~g')",
        tickCount=tickCount,
    )


def axis_multiplier_text(values):
    """Place one scientific multiplier near the axis for compact tick labels."""

    exponent = axis_exponent(values)

    if exponent is None:
        return None

    return f"x1e{exponent}"


def axis_exponent(values) -> int | None:
    """Use one power-of-ten multiplier for very small or large tick labels."""

    finite = finite_values(values)

    if not finite:
        return None

    max_abs = max(abs(value) for value in finite)

    if max_abs == 0.0 or 1.0e-3 <= max_abs < 1.0e3:
        return None

    return int(math.floor(math.log10(max_abs)))


def finite_values(values) -> list[float]:

    return [float(value) for value in values if math.isfinite(float(value))]
