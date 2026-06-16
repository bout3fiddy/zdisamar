"""Shared axis and wavelength helpers."""

import math

from . import fields
from .properties import PLOT


def label(name: str) -> str:

    return fields.QUANTITY_LABELS.get(name, name.replace("_", " "))


def marker_values(values) -> list[float]:
    """Draw fixed reference wavelengths only inside the plotted band."""

    finite = finite_values(values)

    if not finite:
        return []

    start = min(finite)
    end = max(finite)

    return [value for value in PLOT.markers_nm if start <= value <= end]


def finite_padded_domain(values) -> tuple[float, float] | None:
    """Return the finite padded domain used by all SVG plots."""

    finite = finite_values(values)

    if not finite:
        return None

    low = min(finite)
    high = max(finite)

    pad = max(abs(low) * 0.05, 1.0e-12) if low == high else (high - low) * 0.04

    return (low - pad, high + pad)


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
