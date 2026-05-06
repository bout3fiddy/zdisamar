"""Pressure-altitude conversion for pressure-coordinate scene settings."""

from __future__ import annotations

import csv
import math
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np


def _endpoint_slope_spline_second_derivatives(x: np.ndarray, y: np.ndarray) -> np.ndarray:
    """Return cubic-spline second derivatives for a monotonic tabulation."""

    count = len(x)
    matrix = np.zeros((count, count), dtype=np.float64)
    rhs = np.zeros(count, dtype=np.float64)
    widths = np.diff(x)
    slopes = np.diff(y) / widths

    # The endpoint slopes come from the adjacent atmospheric layer. That keeps
    # pressure-altitude conversion local to the profile instead of introducing
    # an external lapse-rate assumption at retrieval boundaries.
    matrix[0, 0] = 2.0 * widths[0]
    matrix[0, 1] = widths[0]
    rhs[0] = 0.0

    for index in range(1, count - 1):
        matrix[index, index - 1] = widths[index - 1]
        matrix[index, index] = 2.0 * (widths[index - 1] + widths[index])
        matrix[index, index + 1] = widths[index]
        rhs[index] = 6.0 * (slopes[index] - slopes[index - 1])

    matrix[-1, -2] = widths[-1]
    matrix[-1, -1] = 2.0 * widths[-1]
    rhs[-1] = 0.0
    return np.linalg.solve(matrix, rhs)


def _cubic_spline_interpolate(
    x: np.ndarray, y: np.ndarray, second: np.ndarray, value: float
) -> float:
    lower_index = int(np.searchsorted(x, value, side="right") - 1)
    lower_index = max(0, min(lower_index, len(x) - 2))
    upper_index = lower_index + 1
    width = x[upper_index] - x[lower_index]
    if width <= 0.0:
        raise ValueError("spline coordinates must be strictly increasing")

    upper_weight = (x[upper_index] - value) / width
    lower_weight = (value - x[lower_index]) / width
    interpolated = upper_weight * y[lower_index] + lower_weight * y[upper_index]
    curvature = (upper_weight**3 - upper_weight) * second[lower_index]
    curvature += (lower_weight**3 - lower_weight) * second[upper_index]
    return float(interpolated + curvature * width * width / 6.0)


@dataclass(frozen=True)
class PressureAltitudeProfile:
    """Monotonic pressure-altitude relation used by layer-placement parameters."""

    altitude_km: np.ndarray
    pressure_hpa: np.ndarray
    _log_pressure_hpa: np.ndarray = field(init=False, repr=False)
    _pressure_by_altitude_second: np.ndarray = field(init=False, repr=False)

    def __post_init__(self) -> None:
        altitude = np.asarray(self.altitude_km, dtype=np.float64)
        pressure = np.asarray(self.pressure_hpa, dtype=np.float64)
        if altitude.ndim != 1 or pressure.ndim != 1 or len(altitude) != len(pressure):
            raise ValueError("pressure-altitude profile arrays must be one-dimensional peers")
        if len(altitude) < 2:
            raise ValueError("pressure-altitude profile must contain at least two rows")
        if np.any(~np.isfinite(altitude)) or np.any(~np.isfinite(pressure)):
            raise ValueError("pressure-altitude profile values must be finite")
        if np.any(np.diff(altitude) <= 0.0):
            raise ValueError("altitude grid must be strictly increasing")
        if np.any(pressure <= 0.0) or np.any(np.diff(pressure) >= 0.0):
            raise ValueError("pressure grid must be positive and strictly decreasing")

        log_pressure = np.log(pressure)
        object.__setattr__(self, "altitude_km", altitude)
        object.__setattr__(self, "pressure_hpa", pressure)
        object.__setattr__(self, "_log_pressure_hpa", log_pressure)
        object.__setattr__(
            self,
            "_pressure_by_altitude_second",
            _endpoint_slope_spline_second_derivatives(altitude, log_pressure),
        )

    @classmethod
    def from_csv(cls, path: Path) -> PressureAltitudeProfile:
        altitudes: list[float] = []
        pressures: list[float] = []
        with path.open(newline="") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                altitudes.append(float(row["altitude_km"]))
                pressures.append(float(row["pressure_hpa"]))
        if len(altitudes) < 2:
            raise ValueError("pressure-altitude profile must contain at least two rows")
        return cls(
            altitude_km=np.asarray(altitudes, dtype=np.float64),
            pressure_hpa=np.asarray(pressures, dtype=np.float64),
        )

    def pressure_at_altitude(self, altitude_km: float) -> float:
        """Evaluate pressure from altitude using the atmospheric tabulation."""

        if not math.isfinite(altitude_km):
            raise ValueError("altitude must be finite")
        lower = float(self.altitude_km[0])
        upper = float(self.altitude_km[-1])
        if altitude_km < lower or altitude_km > upper:
            raise ValueError("altitude is outside the pressure-altitude profile")
        log_pressure = _cubic_spline_interpolate(
            self.altitude_km,
            self._log_pressure_hpa,
            self._pressure_by_altitude_second,
            altitude_km,
        )
        return float(math.exp(log_pressure))
