"""Viewing-geometry and surface input objects."""

from dataclasses import dataclass
from typing import Any

from .shared import to_float


@dataclass
class Geometry:
    model: str
    solar_zenith_deg: float
    viewing_zenith_deg: float
    relative_azimuth_deg: float

    @property
    def solar_mu0(self) -> float:

        from ..quantities import solar_mu0

        return solar_mu0(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Geometry:

        return cls(
            model=str(data["model"]),
            solar_zenith_deg=to_float(data["solar_zenith_deg"]),
            viewing_zenith_deg=to_float(data["viewing_zenith_deg"]),
            relative_azimuth_deg=to_float(data["relative_azimuth_deg"]),
        )

    def to_dict(self) -> dict[str, float | str]:

        return {
            "model": self.model,
            "solar_zenith_deg": self.solar_zenith_deg,
            "viewing_zenith_deg": self.viewing_zenith_deg,
            "relative_azimuth_deg": self.relative_azimuth_deg,
        }


@dataclass
class Surface:
    albedo: float
    pressure_hpa: float
