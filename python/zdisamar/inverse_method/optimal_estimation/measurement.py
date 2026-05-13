"""Measurement-grid validation for optimal estimation."""

from dataclasses import dataclass

import numpy as np

from .retrieval import Measurement


class WavelengthGridMismatchError(ValueError):
    """Raised when retrieval quantities are sampled on different wavelength grids."""


@dataclass(frozen=True)
class MeasurementArrays:
    """Validated retrieval-vector arrays in solver-ready dtype."""

    wavelength_nm: np.ndarray
    reflectance: np.ndarray
    variance: np.ndarray


def measurement_arrays(measurement: Measurement) -> MeasurementArrays:
    """Return validated float64 arrays for a measurement."""

    wavelength_nm = np.asarray(measurement.wavelength_nm, dtype=np.float64)
    reflectance = np.asarray(measurement.reflectance, dtype=np.float64)
    variance = np.asarray(measurement.variance, dtype=np.float64)

    if wavelength_nm.ndim != 1 or reflectance.ndim != 1 or variance.ndim != 1:
        raise ValueError(
            "measurement wavelength, reflectance, and variance must be one-dimensional"
        )

    if wavelength_nm.size == 0:
        raise ValueError("measurement must contain at least one sample")

    if wavelength_nm.shape != reflectance.shape or wavelength_nm.shape != variance.shape:
        raise ValueError("measurement wavelength, reflectance, and variance shapes must match")

    if np.any(~np.isfinite(wavelength_nm)) or np.any(~np.isfinite(reflectance)):
        raise ValueError("measurement wavelength and reflectance values must be finite")

    if np.any(~np.isfinite(variance)) or np.any(variance <= 0.0):
        raise ValueError("measurement variance values must be finite and positive")

    if np.any(np.diff(wavelength_nm) <= 0.0):
        raise ValueError("measurement wavelength grid must be strictly increasing")

    return MeasurementArrays(
        wavelength_nm=wavelength_nm,
        reflectance=reflectance,
        variance=variance,
    )


def require_matching_wavelength_grid(
    expected: np.ndarray,
    actual: np.ndarray,
    *,
    expected_name: str,
    actual_name: str,
) -> None:
    """Reject hidden wavelength-grid adaptation at OE boundaries."""

    expected_values = np.asarray(expected, dtype=np.float64)
    actual_values = np.asarray(actual, dtype=np.float64)

    if expected_values.shape != actual_values.shape or not np.array_equal(
        expected_values, actual_values
    ):
        raise WavelengthGridMismatchError(
            f"{actual_name} wavelength grid must match {expected_name} wavelength grid"
        )
