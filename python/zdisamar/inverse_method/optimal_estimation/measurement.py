"""Measurement-grid validation for optimal estimation."""

import math
from array import array
from dataclasses import dataclass

from .retrieval import Measurement


class WavelengthGridMismatchError(ValueError):
    """Raised when retrieval quantities are sampled on different wavelength grids."""


@dataclass(frozen=True)
class MeasurementArrays:
    """Validated retrieval-vector arrays in solver-ready dtype."""

    wavelength_nm: array
    reflectance: array
    variance: array


def measurement_arrays(measurement: Measurement) -> MeasurementArrays:
    """Return validated float64 arrays for a measurement."""

    wavelength_nm = array("d", (float(value) for value in measurement.wavelength_nm))
    reflectance = array("d", (float(value) for value in measurement.reflectance))
    variance = array("d", (float(value) for value in measurement.variance))

    if not wavelength_nm:
        raise ValueError("measurement must contain at least one sample")

    if len(wavelength_nm) != len(reflectance) or len(wavelength_nm) != len(variance):
        raise ValueError("measurement wavelength, reflectance, and variance shapes must match")

    if any(not math.isfinite(value) for value in wavelength_nm):
        raise ValueError("measurement wavelength and reflectance values must be finite")

    if any(not math.isfinite(value) for value in reflectance):
        raise ValueError("measurement wavelength and reflectance values must be finite")

    if any(not math.isfinite(value) or value <= 0.0 for value in variance):
        raise ValueError("measurement variance values must be finite and positive")

    if any(upper <= lower for lower, upper in zip(wavelength_nm, wavelength_nm[1:], strict=False)):
        raise ValueError("measurement wavelength grid must be strictly increasing")

    return MeasurementArrays(
        wavelength_nm=wavelength_nm,
        reflectance=reflectance,
        variance=variance,
    )


def require_matching_wavelength_grid(
    expected,
    actual,
    *,
    expected_name: str,
    actual_name: str,
) -> None:
    """Reject hidden wavelength-grid adaptation at OE boundaries."""

    expected_values = tuple(float(value) for value in expected)
    actual_values = tuple(float(value) for value in actual)

    if expected_values != actual_values:
        raise WavelengthGridMismatchError(
            f"{actual_name} wavelength grid must match {expected_name} wavelength grid"
        )
