"""Pressure-altitude conversion for pressure-coordinate scene settings."""

from __future__ import annotations

import csv
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np


@dataclass(frozen=True)
class PressureAltitudeProfile:
    """Monotonic pressure-altitude relation used by layer-placement parameters."""

    altitude_km: np.ndarray
    pressure_hpa: np.ndarray

    @classmethod
    def from_csv(cls, path: Path) -> "PressureAltitudeProfile":
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
        """Interpolate pressure in log-pressure space at a physical altitude."""

        if not math.isfinite(altitude_km):
            raise ValueError("altitude must be finite")
        lower = float(self.altitude_km[0])
        upper = float(self.altitude_km[-1])
        if altitude_km < lower or altitude_km > upper:
            raise ValueError("altitude is outside the pressure-altitude profile")
        log_pressure = np.interp(
            altitude_km,
            self.altitude_km,
            np.log(self.pressure_hpa),
        )
        return float(math.exp(float(log_pressure)))

