"""Aerosol input objects."""

import math
from dataclasses import dataclass
from typing import Self

from .shared import object_dict, to_float, to_int


@dataclass
class AerosolPlacement:
    """Pressure-layer placement used when aerosol moves with the fit interval."""

    semantics: str
    interval_index_1based: int
    top_pressure_hpa: float
    bottom_pressure_hpa: float
    top_altitude_km: float = math.nan
    bottom_altitude_km: float = math.nan

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        return cls(
            semantics=str(data["semantics"]),
            interval_index_1based=to_int(data["interval_index_1based"]),
            top_pressure_hpa=to_float(data["top_pressure_hpa"]),
            bottom_pressure_hpa=to_float(data["bottom_pressure_hpa"]),
            top_altitude_km=to_float(data.get("top_altitude_km", math.nan)),
            bottom_altitude_km=to_float(data.get("bottom_altitude_km", math.nan)),
        )

    def to_dict(self) -> dict[str, float | int | str]:

        return {
            "semantics": self.semantics,
            "interval_index_1based": self.interval_index_1based,
            "top_pressure_hpa": self.top_pressure_hpa,
            "bottom_pressure_hpa": self.bottom_pressure_hpa,
            "top_altitude_km": self.top_altitude_km,
            "bottom_altitude_km": self.bottom_altitude_km,
        }


@dataclass
class Aerosol:
    """Single aerosol layer and its optical properties for the O2 A scene."""

    optical_depth_550_nm: float
    single_scatter_albedo: float
    asymmetry_factor: float
    angstrom_exponent: float
    reference_wavelength_nm: float
    layer_center_km: float
    layer_width_km: float
    placement: AerosolPlacement

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        return cls(
            optical_depth_550_nm=to_float(data["optical_depth"]),
            single_scatter_albedo=to_float(data["single_scatter_albedo"]),
            asymmetry_factor=to_float(data["asymmetry_factor"]),
            angstrom_exponent=to_float(data["angstrom_exponent"]),
            reference_wavelength_nm=to_float(data["reference_wavelength_nm"]),
            layer_center_km=to_float(data["layer_center_km"]),
            layer_width_km=to_float(data["layer_width_km"]),
            placement=AerosolPlacement.from_dict(object_dict(data["placement"])),
        )

    def to_dict(self) -> dict[str, float | dict[str, float | int | str]]:

        return {
            "optical_depth": self.optical_depth_550_nm,
            "single_scatter_albedo": self.single_scatter_albedo,
            "asymmetry_factor": self.asymmetry_factor,
            "angstrom_exponent": self.angstrom_exponent,
            "reference_wavelength_nm": self.reference_wavelength_nm,
            "layer_center_km": self.layer_center_km,
            "layer_width_km": self.layer_width_km,
            "placement": self.placement.to_dict(),
        }
