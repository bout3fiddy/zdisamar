"""Viewing-geometry and surface input objects."""

from dataclasses import dataclass
from typing import Self

from .shared import to_float


@dataclass
class Geometry:
    """Solar and viewing geometry for the O2 A radiance calculation."""

    model: str
    solar_zenith_deg: float
    viewing_zenith_deg: float
    relative_azimuth_deg: float

    @property
    def solar_mu0(self) -> float:
        """Return cos(solar zenith), used in reflectance conversion."""

        from ..rtm.geometry import solar_zenith_cosine

        return solar_zenith_cosine(self)

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

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
    """Lambertian surface parameters used by the current O2 A model."""

    albedo: float
    pressure_hpa: float
