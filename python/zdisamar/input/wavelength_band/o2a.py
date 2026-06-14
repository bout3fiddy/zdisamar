"""Typed O2 A wavelength-band input object and JSON conversion."""

import json
import math
from copy import copy, deepcopy
from dataclasses import dataclass, field
from pathlib import Path
from typing import Self

from ...display import NotebookDisplay
from ..aerosol import Aerosol, AerosolProfileLayer, coerce_profile_layers
from ..assets import ReferenceAssets
from ..atmosphere import Atmosphere
from ..geometry import Geometry, Surface
from ..instrument import InstrumentResponse, SpectralGrid
from ..radiative_transfer import RadiativeTransferControls
from ..shared import json_value, native_json_value, object_dict, to_float
from ..spectroscopy import LineByLine, OxygenCollisionInducedAbsorption
from .optimisation import Optimisation


def _object_dict(data: dict[str, object], key: str) -> dict[str, object]:

    return object_dict(data[key])


@dataclass
class Scene(NotebookDisplay):
    """Complete O2 A wavelength-band case passed to the zdisamar RTM."""

    metadata: dict[str, object]
    plan: dict[str, object]
    reference_assets: ReferenceAssets
    scene_id: str
    spectral_grid: SpectralGrid
    atmosphere: Atmosphere
    surface: Surface
    geometry: Geometry
    aerosol: Aerosol
    instrument_response: InstrumentResponse
    o2_lines: LineByLine
    collision_induced_absorption: OxygenCollisionInducedAbsorption
    radiative_transfer: RadiativeTransferControls
    optimisation: Optimisation = field(default_factory=Optimisation.defaults)

    @property
    def aerosol_optical_depth_550_nm(self) -> float:
        """Return the aerosol optical depth at 550 nm."""

        return self.aerosol.optical_depth_550_nm

    @aerosol_optical_depth_550_nm.setter
    def aerosol_optical_depth_550_nm(self, value: float) -> None:

        self.aerosol.set_single_layer_optical_depth_550_nm(float(value))

    @property
    def aerosol_profile(self) -> tuple[AerosolProfileLayer, ...]:
        """Return aerosol layers used by forward simulation."""

        return self.aerosol.profile

    @aerosol_profile.setter
    def aerosol_profile(self, layers: object) -> None:

        self.set_aerosol_profile(layers)

    @property
    def aerosol_layer(self) -> "AerosolLayer":  # noqa: UP037
        """Return the coupled aerosol-layer placement view."""

        return AerosolLayer(self)

    @property
    def measurement_wavelengths_nm(self) -> tuple[float, ...]:
        """Return the nominal measurement axis for the case."""

        measured_wavelengths = self.instrument_response.measured_wavelengths_nm

        if measured_wavelengths:
            return measured_wavelengths

        sample_count = int(self.spectral_grid.sample_count)

        if sample_count < 2:
            raise ValueError("spectral grid must contain at least two samples")

        start_nm = float(self.spectral_grid.start_nm)
        step_nm = (float(self.spectral_grid.end_nm) - start_nm) / float(sample_count - 1)

        return tuple(start_nm + (step_nm * index) for index in range(sample_count))

    def __repr__(self) -> str:

        aerosol_profile = self.aerosol.profile

        if len(aerosol_profile) > 1:
            aerosol_description = (
                f"profile with {len(aerosol_profile)} layers, "
                f"total optical depth {sum(layer.optical_depth for layer in aerosol_profile):g}"
            )
        else:
            aerosol_description = (
                f"optical depth {self.aerosol.optical_depth_550_nm:g} at 550 nm, "
                f"layer mid-pressure {self.aerosol_layer.mid_pressure_hpa:g} hPa, "
                f"thickness {self.aerosol_layer.thickness_hpa:g} hPa"
            )

        return (
            "Scene(\n"
            f"  scene_id={self.scene_id!r},\n"
            "  spectral_grid="
            f"{self.spectral_grid.start_nm:g}-{self.spectral_grid.end_nm:g} nm "
            f"({self.spectral_grid.sample_count} samples),\n"
            "  atmosphere="
            f"{self.atmosphere.layer_count} layers, "
            f"{self.atmosphere.sublayer_divisions} sublayers, "
            f"fit interval {self.atmosphere.fit_interval_index_1based},\n"
            "  surface="
            f"albedo {self.surface.albedo:g}, pressure {self.surface.pressure_hpa:g} hPa,\n"
            "  geometry="
            f"solar {self.geometry.solar_zenith_deg:g} deg, "
            f"viewing {self.geometry.viewing_zenith_deg:g} deg, "
            f"relative azimuth {self.geometry.relative_azimuth_deg:g} deg,\n"
            f"  aerosol={aerosol_description},\n"
            "  instrument="
            f"{self.instrument_response.instrument_name!r}, "
            f"FWHM {self.instrument_response.instrument_line_fwhm_nm:g} nm, "
            f"step {self.instrument_response.high_resolution_step_nm:g} nm,\n"
            "  radiative_transfer="
            f"{self.radiative_transfer.scattering!r}, "
            f"{self.radiative_transfer.n_streams} streams, "
            f"integrated_source={self.radiative_transfer.integrate_source_function},\n"
            ")"
        )

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:
        """Turn the validation-file shape into typed scene parts."""

        removed_metadata = {"outputs", "validation"}.intersection(data)
        if removed_metadata:
            joined = ", ".join(sorted(removed_metadata))
            raise ValueError(f"unsupported O2 A input fields: {joined}")

        return cls(
            metadata=_object_dict(data, "metadata"),
            plan=_object_dict(data, "plan"),
            reference_assets=ReferenceAssets.from_dict(object_dict(data["inputs"])),
            scene_id=str(data["scene_id"]),
            spectral_grid=SpectralGrid.from_dict(object_dict(data["spectral_grid"])),
            atmosphere=Atmosphere.from_dict(data),
            surface=Surface(
                albedo=to_float(data["surface_albedo"]),
                pressure_hpa=to_float(data["surface_pressure_hpa"]),
            ),
            geometry=Geometry.from_dict(object_dict(data["geometry"])),
            aerosol=Aerosol.from_dict(object_dict(data["aerosol"])),
            instrument_response=InstrumentResponse.from_dict(object_dict(data["observation"])),
            o2_lines=LineByLine.from_dict(object_dict(data["o2"])),
            collision_induced_absorption=OxygenCollisionInducedAbsorption.from_dict(
                object_dict(data["o2o2"])
            ),
            radiative_transfer=RadiativeTransferControls.from_dict(
                object_dict(data["rtm_controls"])
            ),
            optimisation=Optimisation.from_dict(object_dict(data.get("optimisation", {}))),
        )

    @classmethod
    def from_json(cls, raw: str | bytes) -> Self:
        """Read an O2 A scene emitted by the zdisamar model."""

        return cls.from_dict(json.loads(raw))

    def to_dict(self) -> dict[str, object]:
        """Return the Python O2 A case shape, including optimisation controls."""

        payload = self.to_native_dict()
        payload["optimisation"] = self.optimisation.to_dict()

        return payload

    def to_native_dict(self) -> dict[str, object]:
        """Return the O2 A scene shape expected by the native zdisamar model."""

        return {
            "metadata": self.metadata,
            "plan": self.plan,
            "inputs": self.reference_assets.to_dict(),
            "scene_id": self.scene_id,
            "spectral_grid": self.spectral_grid.to_dict(),
            "layer_count": self.atmosphere.layer_count,
            "sublayer_divisions": self.atmosphere.sublayer_divisions,
            "surface_pressure_hpa": self.surface.pressure_hpa,
            "fit_interval_index_1based": self.atmosphere.fit_interval_index_1based,
            "intervals": [item.to_dict() for item in self.atmosphere.intervals],
            "surface_albedo": self.surface.albedo,
            "geometry": self.geometry.to_dict(),
            "aerosol": self.aerosol.to_dict(),
            "observation": self.instrument_response.to_dict(),
            "o2": self.o2_lines.to_dict(),
            "o2o2": self.collision_induced_absorption.to_dict(),
            "rtm_controls": self.radiative_transfer.to_dict(),
        }

    def to_json_bytes(self) -> bytes:
        """Encode the Python case deterministically, including optimisation controls."""

        return json.dumps(json_value(self.to_dict()), sort_keys=True, separators=(",", ":")).encode(
            "utf-8"
        )

    def to_native_json_bytes(self) -> bytes:
        """Encode the native scene without Python-only optimisation controls."""

        return json.dumps(
            native_json_value(self.to_native_dict()), sort_keys=True, separators=(",", ":")
        ).encode("utf-8")

    def set_aerosol_profile(self, layers: object) -> None:
        """Install a case-owned aerosol profile for forward simulations."""

        profile = coerce_profile_layers(layers)

        if not profile:
            raise ValueError("aerosol profile must contain at least one layer")

        if len(profile) == 1:
            self.set_single_aerosol_profile_layer(profile[0])

            return

        for layer in profile:
            layer.validate()

        self.aerosol.set_profile_layers(profile)

    def set_single_aerosol_profile_layer(self, layer: AerosolProfileLayer) -> None:
        """Move the scalar aerosol layer and keep the atmosphere grid coherent."""

        layer.validate()
        placement = self.aerosol.placement

        if placement.semantics != "explicit_interval_bounds":
            raise ValueError("aerosol profile setters require explicit interval bounds placement")

        if placement.interval_index_1based != self.atmosphere.fit_interval_index_1based:
            raise ValueError("aerosol placement interval does not match atmosphere fit interval")

        self.atmosphere.set_fit_interval_pressure_bounds(
            top_pressure_hpa=layer.top_pressure_hpa,
            bottom_pressure_hpa=layer.bottom_pressure_hpa,
        )
        self.aerosol.set_profile_layers((layer,))

    def with_rtm_optimisation_applied(self) -> Self:
        """Return the native RTM case after applying enabled optimisation modes."""

        resolved = deepcopy(self)

        if resolved.optimisation.fastmode.enabled:
            resolved.optimisation.fastmode.apply_to_scene(resolved)
            resolved.optimisation.fastmode.enabled = False

        return resolved

    def with_resolved_asset_paths(self, base: str | Path) -> Self:
        """Resolve relative reference-data files from one directory."""

        root = Path(base)

        return self.with_resolved_asset_resolver(lambda path: (root / path).resolve())

    def with_resolved_asset_resolver(self, resolver) -> Self:
        """Return a copy with every reference-data file path resolved."""

        resolved = copy(self)
        resolved.reference_assets = ReferenceAssets(
            atmosphere_profile=self.reference_assets.atmosphere_profile.with_resolved_path(
                resolver
            ),
            vendor_reference_csv=self.reference_assets.vendor_reference_csv.with_resolved_path(
                resolver
            ),
            raw_solar_reference=self.reference_assets.raw_solar_reference.with_resolved_path(
                resolver
            ),
            airmass_factor_lut=self.reference_assets.airmass_factor_lut.with_resolved_path(
                resolver
            ),
        )
        resolved.o2_lines = copy(self.o2_lines)
        resolved.o2_lines.isotopes_sim = list(self.o2_lines.isotopes_sim)
        resolved.o2_lines.line_list_asset = self.o2_lines.line_list_asset.with_resolved_path(
            resolver
        )
        resolved.o2_lines.line_mixing_asset = self.o2_lines.line_mixing_asset.with_resolved_path(
            resolver
        )
        resolved.o2_lines.strong_lines_asset = self.o2_lines.strong_lines_asset.with_resolved_path(
            resolver
        )

        resolved.collision_induced_absorption = copy(self.collision_induced_absorption)

        cia_asset = self.collision_induced_absorption.cross_section_asset

        if cia_asset is not None:
            resolved.collision_induced_absorption.cross_section_asset = (
                cia_asset.with_resolved_path(resolver)
            )

        return resolved


def apply_aerosol_layer_midpoint_and_thickness(
    scene: Scene,
    *,
    mid_pressure_hpa: float,
    thickness_hpa: float,
) -> None:
    """Apply aerosol-layer placement and keep the fit interval aligned."""

    mid_pressure_hpa = float(mid_pressure_hpa)
    thickness_hpa = float(thickness_hpa)

    if not math.isfinite(mid_pressure_hpa) or not math.isfinite(thickness_hpa):
        raise ValueError("aerosol layer pressure values must be finite")

    if thickness_hpa <= 0.0:
        raise ValueError("aerosol layer pressure thickness must be positive")

    scene.aerosol.require_retrieval_compatible()

    top_pressure_hpa = mid_pressure_hpa - 0.5 * thickness_hpa
    bottom_pressure_hpa = mid_pressure_hpa + 0.5 * thickness_hpa

    placement = scene.aerosol.placement

    if placement.semantics != "explicit_interval_bounds":
        raise ValueError("aerosol pressure setters require explicit interval bounds placement")

    if placement.interval_index_1based != scene.atmosphere.fit_interval_index_1based:
        raise ValueError("aerosol placement interval does not match atmosphere fit interval")

    scene.atmosphere.set_fit_interval_pressure_bounds(
        top_pressure_hpa=top_pressure_hpa,
        bottom_pressure_hpa=bottom_pressure_hpa,
    )
    placement.top_pressure_hpa = top_pressure_hpa
    placement.bottom_pressure_hpa = bottom_pressure_hpa
    scene.aerosol.replace_single_profile_layer(
        top_pressure_hpa=top_pressure_hpa,
        bottom_pressure_hpa=bottom_pressure_hpa,
    )


class AerosolLayer:
    """Pressure-layer placement coupled to the atmosphere fit interval."""

    __slots__ = ("scene",)

    def __init__(self, scene: Scene) -> None:

        self.scene = scene

    @property
    def mid_pressure_hpa(self) -> float:
        """Return the aerosol-layer midpoint pressure."""

        self.scene.aerosol.require_retrieval_compatible()
        placement = self.scene.aerosol.placement

        return 0.5 * (placement.top_pressure_hpa + placement.bottom_pressure_hpa)

    @mid_pressure_hpa.setter
    def mid_pressure_hpa(self, value: float) -> None:

        apply_aerosol_layer_midpoint_and_thickness(
            self.scene,
            mid_pressure_hpa=value,
            thickness_hpa=self.thickness_hpa,
        )

    @property
    def thickness_hpa(self) -> float:
        """Return the aerosol-layer pressure thickness."""

        self.scene.aerosol.require_retrieval_compatible()
        placement = self.scene.aerosol.placement

        return placement.bottom_pressure_hpa - placement.top_pressure_hpa

    @thickness_hpa.setter
    def thickness_hpa(self, value: float) -> None:

        apply_aerosol_layer_midpoint_and_thickness(
            self.scene,
            mid_pressure_hpa=self.mid_pressure_hpa,
            thickness_hpa=value,
        )
