"""Atmospheric profile input objects."""

import math
from dataclasses import dataclass
from typing import Any

from .shared import to_float


@dataclass
class VerticalInterval:
    """One pressure interval from the DISAMAR-style atmospheric grid."""

    index_1based: int
    top_pressure_hpa: float
    bottom_pressure_hpa: float
    altitude_divisions: int
    top_altitude_km: float = math.nan
    bottom_altitude_km: float = math.nan
    top_pressure_variance_hpa2: float = 0.0
    bottom_pressure_variance_hpa2: float = 0.0

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> VerticalInterval:

        return cls(
            index_1based=int(data["index_1based"]),
            top_pressure_hpa=to_float(data["top_pressure_hpa"]),
            bottom_pressure_hpa=to_float(data["bottom_pressure_hpa"]),
            altitude_divisions=int(data["altitude_divisions"]),
            top_altitude_km=to_float(data.get("top_altitude_km", math.nan)),
            bottom_altitude_km=to_float(data.get("bottom_altitude_km", math.nan)),
            top_pressure_variance_hpa2=to_float(data.get("top_pressure_variance_hpa2", 0.0)),
            bottom_pressure_variance_hpa2=to_float(data.get("bottom_pressure_variance_hpa2", 0.0)),
        )

    def to_dict(self) -> dict[str, float | int]:

        return {
            "index_1based": self.index_1based,
            "top_pressure_hpa": self.top_pressure_hpa,
            "bottom_pressure_hpa": self.bottom_pressure_hpa,
            "top_altitude_km": self.top_altitude_km,
            "bottom_altitude_km": self.bottom_altitude_km,
            "top_pressure_variance_hpa2": self.top_pressure_variance_hpa2,
            "bottom_pressure_variance_hpa2": self.bottom_pressure_variance_hpa2,
            "altitude_divisions": self.altitude_divisions,
        }


@dataclass
class Atmosphere:
    """Layer grid and fit interval used to build the O2 A atmosphere."""

    layer_count: int
    sublayer_divisions: int
    fit_interval_index_1based: int
    intervals: list[VerticalInterval]

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Atmosphere:

        return cls(
            layer_count=int(data["layer_count"]),
            sublayer_divisions=int(data["sublayer_divisions"]),
            fit_interval_index_1based=int(data["fit_interval_index_1based"]),
            intervals=[VerticalInterval.from_dict(item) for item in data["intervals"]],
        )
