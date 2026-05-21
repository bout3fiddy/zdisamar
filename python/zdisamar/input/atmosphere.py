"""Atmospheric profile input objects."""

import math
from dataclasses import dataclass
from typing import Self

from .shared import object_dict_list, to_float, to_int


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
    def from_dict(cls, data: dict[str, object]) -> Self:

        return cls(
            index_1based=to_int(data["index_1based"]),
            top_pressure_hpa=to_float(data["top_pressure_hpa"]),
            bottom_pressure_hpa=to_float(data["bottom_pressure_hpa"]),
            altitude_divisions=to_int(data["altitude_divisions"]),
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

    def set_fit_interval_pressure_bounds(
        self,
        *,
        top_pressure_hpa: float,
        bottom_pressure_hpa: float,
    ) -> None:
        """Move the fit interval and keep adjacent pressure boundaries continuous."""

        fit_index = self.fit_interval_index_1based

        if fit_index <= 0 or fit_index > len(self.intervals):
            raise ValueError("fit interval is not present in the atmosphere")

        fit_interval = self.intervals[fit_index - 1]

        if fit_interval.index_1based != fit_index:
            raise ValueError("atmosphere intervals are not ordered by index")

        fit_interval.top_pressure_hpa = top_pressure_hpa
        fit_interval.bottom_pressure_hpa = bottom_pressure_hpa

        if fit_index > 1:
            self.intervals[fit_index - 2].bottom_pressure_hpa = top_pressure_hpa

        if fit_index < len(self.intervals):
            self.intervals[fit_index].top_pressure_hpa = bottom_pressure_hpa

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        return cls(
            layer_count=to_int(data["layer_count"]),
            sublayer_divisions=to_int(data["sublayer_divisions"]),
            fit_interval_index_1based=to_int(data["fit_interval_index_1based"]),
            intervals=[
                VerticalInterval.from_dict(item) for item in object_dict_list(data["intervals"])
            ],
        )
