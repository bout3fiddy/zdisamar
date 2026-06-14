"""Aerosol input objects."""

import math
from collections.abc import Iterable
from dataclasses import dataclass, replace
from typing import Self

from .shared import object_dict, object_dict_list, placeholder_float, to_float, to_int


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
            top_altitude_km=placeholder_float(data, "top_altitude_km", math.nan),
            bottom_altitude_km=placeholder_float(data, "bottom_altitude_km", math.nan),
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


@dataclass(frozen=True)
class AerosolProfileLayer:
    """One pressure-bounded aerosol component used for forward truth spectra."""

    top_pressure_hpa: float
    bottom_pressure_hpa: float
    optical_depth: float
    single_scatter_albedo: float = 0.93
    asymmetry_factor: float = 0.65
    angstrom_exponent: float = 1.3
    reference_wavelength_nm: float = 550.0

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        return cls(
            top_pressure_hpa=to_float(data["top_pressure_hpa"]),
            bottom_pressure_hpa=to_float(data["bottom_pressure_hpa"]),
            optical_depth=to_float(data["optical_depth"]),
            single_scatter_albedo=to_float(data.get("single_scatter_albedo", 0.93)),
            asymmetry_factor=to_float(data.get("asymmetry_factor", 0.65)),
            angstrom_exponent=to_float(data.get("angstrom_exponent", 1.3)),
            reference_wavelength_nm=to_float(data.get("reference_wavelength_nm", 550.0)),
        )

    def to_dict(self) -> dict[str, float]:

        return {
            "top_pressure_hpa": self.top_pressure_hpa,
            "bottom_pressure_hpa": self.bottom_pressure_hpa,
            "optical_depth": self.optical_depth,
            "single_scatter_albedo": self.single_scatter_albedo,
            "asymmetry_factor": self.asymmetry_factor,
            "angstrom_exponent": self.angstrom_exponent,
            "reference_wavelength_nm": self.reference_wavelength_nm,
        }

    def validate(self) -> None:

        if (
            not math.isfinite(self.top_pressure_hpa)
            or not math.isfinite(self.bottom_pressure_hpa)
            or self.bottom_pressure_hpa <= self.top_pressure_hpa
            or self.top_pressure_hpa < 0.0
        ):
            raise ValueError("aerosol profile layer pressure bounds are invalid")

        if not math.isfinite(self.optical_depth) or self.optical_depth < 0.0:
            raise ValueError("aerosol profile layer optical depth is invalid")

        if (
            not math.isfinite(self.single_scatter_albedo)
            or self.single_scatter_albedo < 0.0
            or self.single_scatter_albedo > 1.0
        ):
            raise ValueError("aerosol profile layer single scatter albedo is invalid")

        if (
            not math.isfinite(self.asymmetry_factor)
            or self.asymmetry_factor < -1.0
            or self.asymmetry_factor > 1.0
        ):
            raise ValueError("aerosol profile layer asymmetry factor is invalid")

        if (
            not math.isfinite(self.angstrom_exponent)
            or not math.isfinite(self.reference_wavelength_nm)
            or self.reference_wavelength_nm <= 0.0
        ):
            raise ValueError("aerosol profile layer wavelength scaling is invalid")


@dataclass
class Aerosol:
    """Aerosol optical properties for the O2 A scene."""

    optical_depth_550_nm: float
    single_scatter_albedo: float
    asymmetry_factor: float
    angstrom_exponent: float
    reference_wavelength_nm: float
    placement: AerosolPlacement
    profile: tuple[AerosolProfileLayer, ...] = ()

    def __post_init__(self) -> None:

        if self.profile:
            self.set_profile_layers(self.profile)

            return

        self.profile = (self.scalar_profile_layer(),)

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        legacy_keys = {"layer_center_km", "layer_width_km"}.intersection(data)

        if legacy_keys:
            joined = ", ".join(sorted(legacy_keys))
            raise ValueError(f"unsupported aerosol placement fields: {joined}; use placement")

        profile_data = object_dict_list(data.get("profile", []))
        explicit_profile = tuple(AerosolProfileLayer.from_dict(item) for item in profile_data)
        placement = AerosolPlacement.from_dict(object_dict(data["placement"]))
        optical_depth = to_float(data["optical_depth"])
        single_scatter_albedo = to_float(data["single_scatter_albedo"])
        asymmetry_factor = to_float(data["asymmetry_factor"])
        angstrom_exponent = to_float(data["angstrom_exponent"])
        reference_wavelength_nm = to_float(data["reference_wavelength_nm"])
        scalar_profile = (
            AerosolProfileLayer(
                top_pressure_hpa=placement.top_pressure_hpa,
                bottom_pressure_hpa=placement.bottom_pressure_hpa,
                optical_depth=optical_depth,
                single_scatter_albedo=single_scatter_albedo,
                asymmetry_factor=asymmetry_factor,
                angstrom_exponent=angstrom_exponent,
                reference_wavelength_nm=reference_wavelength_nm,
            ),
        )

        return cls(
            optical_depth_550_nm=optical_depth,
            single_scatter_albedo=single_scatter_albedo,
            asymmetry_factor=asymmetry_factor,
            angstrom_exponent=angstrom_exponent,
            reference_wavelength_nm=reference_wavelength_nm,
            placement=placement,
            profile=explicit_profile or scalar_profile,
        )

    def to_dict(self) -> dict[str, object]:

        if len(self.profile) > 1:
            primary = self.profile[0]
            data: dict[str, object] = {
                "optical_depth": primary.optical_depth,
                "single_scatter_albedo": primary.single_scatter_albedo,
                "asymmetry_factor": primary.asymmetry_factor,
                "angstrom_exponent": primary.angstrom_exponent,
                "reference_wavelength_nm": primary.reference_wavelength_nm,
                "placement": self.placement.to_dict(),
            }
            data["profile"] = [layer.to_dict() for layer in self.profile]

            return data

        return {
            "optical_depth": self.optical_depth_550_nm,
            "single_scatter_albedo": self.single_scatter_albedo,
            "asymmetry_factor": self.asymmetry_factor,
            "angstrom_exponent": self.angstrom_exponent,
            "reference_wavelength_nm": self.reference_wavelength_nm,
            "placement": self.placement.to_dict(),
        }

    def set_single_layer_optical_depth_550_nm(self, value: float) -> None:

        self.require_retrieval_compatible()
        self.optical_depth_550_nm = float(value)
        self.replace_single_profile_layer(optical_depth=self.optical_depth_550_nm)

    def set_profile_layers(self, value: object) -> None:

        profile = coerce_profile_layers(value)

        if not profile:
            raise ValueError("aerosol profile must contain at least one layer")

        for layer in profile:
            layer.validate()

        self.profile = profile

        if len(profile) == 1:
            self.sync_scalar_fields_from_profile_layer(profile[0])

    def require_retrieval_compatible(self) -> None:
        """Reject profile shapes that the single-layer OE state model cannot mutate."""

        if len(self.profile) > 1:
            raise ValueError("multi-layer aerosol profiles are forward-simulation only")

    def replace_single_profile_layer(self, **updates: float) -> None:
        """Update the explicit one-layer profile when scalar layer helpers move it."""

        if not self.profile:
            return

        if len(self.profile) != 1:
            raise ValueError("scalar aerosol setters require a single-layer aerosol profile")

        layer = replace(self.scalar_profile_layer(), **updates)
        layer.validate()
        self.profile = (layer,)
        self.sync_scalar_fields_from_profile_layer(layer)

    def sync_scalar_fields_from_profile_layer(self, layer: AerosolProfileLayer) -> None:

        self.optical_depth_550_nm = layer.optical_depth
        self.single_scatter_albedo = layer.single_scatter_albedo
        self.asymmetry_factor = layer.asymmetry_factor
        self.angstrom_exponent = layer.angstrom_exponent
        self.reference_wavelength_nm = layer.reference_wavelength_nm
        self.placement.top_pressure_hpa = layer.top_pressure_hpa
        self.placement.bottom_pressure_hpa = layer.bottom_pressure_hpa

    def scalar_profile_layer(self) -> AerosolProfileLayer:

        return AerosolProfileLayer(
            top_pressure_hpa=self.placement.top_pressure_hpa,
            bottom_pressure_hpa=self.placement.bottom_pressure_hpa,
            optical_depth=self.optical_depth_550_nm,
            single_scatter_albedo=self.single_scatter_albedo,
            asymmetry_factor=self.asymmetry_factor,
            angstrom_exponent=self.angstrom_exponent,
            reference_wavelength_nm=self.reference_wavelength_nm,
        )


def coerce_profile_layers(value: object) -> tuple[AerosolProfileLayer, ...]:

    if value is None:
        return ()

    if not isinstance(value, Iterable) or isinstance(value, str | bytes):
        raise TypeError("aerosol profile must be an iterable of AerosolProfileLayer")

    layers: list[AerosolProfileLayer] = []

    for layer in value:
        if not isinstance(layer, AerosolProfileLayer):
            raise TypeError("aerosol profile entries must be AerosolProfileLayer")

        layers.append(layer)

    return tuple(layers)
