"""Pressure-altitude conversion for pressure-coordinate scene settings."""

import bisect
import csv
import math
from dataclasses import dataclass, field
from pathlib import Path
from typing import Self


def _endpoint_slope_spline_second_derivatives(
    x: tuple[float, ...],
    y: tuple[float, ...],
) -> tuple[float, ...]:
    """Return cubic-spline second derivatives for a monotonic tabulation."""

    count = len(x)
    widths = [x[index + 1] - x[index] for index in range(count - 1)]
    slopes = [(y[index + 1] - y[index]) / widths[index] for index in range(count - 1)]
    lower = [0.0] * count
    diagonal = [0.0] * count
    upper = [0.0] * count
    rhs = [0.0] * count

    # The endpoint slopes come from the adjacent atmospheric layer. That keeps
    # pressure-altitude conversion local to the profile instead of introducing
    # an external lapse-rate assumption at retrieval boundaries.
    diagonal[0] = 2.0 * widths[0]
    upper[0] = widths[0]
    rhs[0] = 0.0

    for index in range(1, count - 1):
        lower[index] = widths[index - 1]
        diagonal[index] = 2.0 * (widths[index - 1] + widths[index])
        upper[index] = widths[index]
        rhs[index] = 6.0 * (slopes[index] - slopes[index - 1])

    lower[-1] = widths[-1]
    diagonal[-1] = 2.0 * widths[-1]
    rhs[-1] = 0.0

    return _solve_tridiagonal(lower, diagonal, upper, rhs)


def _solve_tridiagonal(
    lower: list[float],
    diagonal: list[float],
    upper: list[float],
    rhs: list[float],
) -> tuple[float, ...]:
    """Solve the spline's tridiagonal system without shipping LAPACK."""

    count = len(diagonal)
    c_prime = [0.0] * count
    d_prime = [0.0] * count
    c_prime[0] = upper[0] / diagonal[0]
    d_prime[0] = rhs[0] / diagonal[0]

    for index in range(1, count):
        denominator = diagonal[index] - lower[index] * c_prime[index - 1]

        if denominator == 0.0:
            raise ValueError("pressure-altitude spline system is singular")

        c_prime[index] = upper[index] / denominator if index < count - 1 else 0.0
        d_prime[index] = (rhs[index] - lower[index] * d_prime[index - 1]) / denominator

    solution = [0.0] * count
    solution[-1] = d_prime[-1]

    for index in range(count - 2, -1, -1):
        solution[index] = d_prime[index] - c_prime[index] * solution[index + 1]

    return tuple(solution)


def _cubic_spline_interpolate(
    x: tuple[float, ...],
    y: tuple[float, ...],
    second: tuple[float, ...],
    value: float,
) -> float:
    """Evaluate the pressure-altitude spline without adding a SciPy dependency."""

    lower_index = bisect.bisect_right(x, value) - 1
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

    altitude_km: tuple[float, ...]
    pressure_hpa: tuple[float, ...]
    _log_pressure_hpa: tuple[float, ...] = field(init=False, repr=False)
    _pressure_by_altitude_second: tuple[float, ...] = field(init=False, repr=False)

    def __post_init__(self) -> None:

        altitude = tuple(float(value) for value in self.altitude_km)
        pressure = tuple(float(value) for value in self.pressure_hpa)

        if len(altitude) != len(pressure):
            raise ValueError("pressure-altitude profile arrays must be one-dimensional peers")

        if len(altitude) < 2:
            raise ValueError("pressure-altitude profile must contain at least two rows")

        if any(not math.isfinite(value) for value in altitude + pressure):
            raise ValueError("pressure-altitude profile values must be finite")

        if any(upper <= lower for lower, upper in zip(altitude, altitude[1:], strict=False)):
            raise ValueError("altitude grid must be strictly increasing")

        if any(value <= 0.0 for value in pressure) or any(
            upper >= lower for lower, upper in zip(pressure, pressure[1:], strict=False)
        ):
            raise ValueError("pressure grid must be positive and strictly decreasing")

        log_pressure = tuple(math.log(value) for value in pressure)
        object.__setattr__(self, "altitude_km", altitude)
        object.__setattr__(self, "pressure_hpa", pressure)
        object.__setattr__(self, "_log_pressure_hpa", log_pressure)
        object.__setattr__(
            self,
            "_pressure_by_altitude_second",
            _endpoint_slope_spline_second_derivatives(altitude, log_pressure),
        )

    @classmethod
    def from_csv(cls, path: Path) -> Self:
        """Read a pressure-altitude table into the validated profile object."""

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
            altitude_km=tuple(altitudes),
            pressure_hpa=tuple(pressures),
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

    def altitude_at_pressure(self, pressure_hpa: float) -> float:
        """Evaluate altitude from pressure using the atmospheric tabulation."""

        if not math.isfinite(pressure_hpa):
            raise ValueError("pressure must be finite")

        lower_pressure = float(self.pressure_hpa[-1])
        upper_pressure = float(self.pressure_hpa[0])

        if pressure_hpa < lower_pressure or pressure_hpa > upper_pressure:
            raise ValueError("pressure is outside the pressure-altitude profile")

        lower_altitude = float(self.altitude_km[0])
        upper_altitude = float(self.altitude_km[-1])

        for _ in range(80):
            # Bisection keeps the inverse tied to pressure_at_altitude instead
            # of introducing a second pressure-altitude approximation.
            mid_altitude = 0.5 * (lower_altitude + upper_altitude)
            mid_pressure = self.pressure_at_altitude(mid_altitude)

            if mid_pressure > pressure_hpa:
                lower_altitude = mid_altitude
            else:
                upper_altitude = mid_altitude

        return 0.5 * (lower_altitude + upper_altitude)

    def altitude_derivative_at_pressure(self, pressure_hpa: float) -> float:
        """Evaluate dz/dp in km/hPa at a pressure coordinate."""

        step_hpa = max(abs(pressure_hpa) * 1.0e-4, 1.0e-3)
        lower_pressure = max(float(self.pressure_hpa[-1]), pressure_hpa - step_hpa)
        upper_pressure = min(float(self.pressure_hpa[0]), pressure_hpa + step_hpa)

        if upper_pressure <= lower_pressure:
            raise ValueError("pressure derivative stencil is outside the profile")

        altitude_span = self.altitude_at_pressure(upper_pressure) - self.altitude_at_pressure(
            lower_pressure
        )

        return altitude_span / (upper_pressure - lower_pressure)
