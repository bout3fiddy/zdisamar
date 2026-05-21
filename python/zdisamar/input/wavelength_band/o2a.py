"""Typed O2 A wavelength-band input object and JSON conversion."""

import json
from copy import copy, deepcopy
from dataclasses import dataclass
from pathlib import Path
from typing import Self

from ...display import NotebookDisplay
from ..aerosol import Aerosol
from ..assets import ReferenceAssets
from ..atmosphere import Atmosphere
from ..geometry import Geometry, Surface
from ..instrument import InstrumentResponse, SpectralGrid
from ..radiative_transfer import RadiativeTransferControls
from ..shared import json_value, object_dict, object_dict_list, to_float
from ..spectroscopy import O2LineByLine, OxygenCollisionInducedAbsorption


def _object_dict(data: dict[str, object], key: str) -> dict[str, object]:

    return object_dict(data[key])


def _object_list(data: dict[str, object], key: str) -> list[dict[str, object]]:

    return object_dict_list(data.get(key, []))


@dataclass
class O2AInput(NotebookDisplay):
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
    o2_lines: O2LineByLine
    collision_induced_absorption: OxygenCollisionInducedAbsorption
    radiative_transfer: RadiativeTransferControls
    outputs: list[dict[str, object]]
    validation: dict[str, object]

    FAST_ADAPTIVE_REFERENCE_GRID = {
        "points_per_fwhm": 28,
        "strong_line_min_divisions": 6,
        "strong_line_max_divisions": 22,
    }

    @property
    def aerosol_optical_depth_550_nm(self) -> float:
        """Return the aerosol optical depth at 550 nm."""

        return self.aerosol.optical_depth_550_nm

    @aerosol_optical_depth_550_nm.setter
    def aerosol_optical_depth_550_nm(self, value: float) -> None:

        self.aerosol.optical_depth_550_nm = float(value)

    @property
    def aerosol_layer_pressure_thickness_hpa(self) -> float:
        """Return the aerosol layer pressure thickness."""

        placement = self.aerosol.placement

        return placement.bottom_pressure_hpa - placement.top_pressure_hpa

    @aerosol_layer_pressure_thickness_hpa.setter
    def aerosol_layer_pressure_thickness_hpa(self, value: float) -> None:

        thickness_hpa = float(value)

        if thickness_hpa <= 0.0:
            raise ValueError("aerosol layer pressure thickness must be positive")

        mid_pressure_hpa = self.aerosol_layer_mid_pressure_hpa
        self.set_aerosol_layer_pressure_bounds(
            top_pressure_hpa=mid_pressure_hpa - 0.5 * thickness_hpa,
            bottom_pressure_hpa=mid_pressure_hpa + 0.5 * thickness_hpa,
        )

    @property
    def aerosol_layer_mid_pressure_hpa(self) -> float:
        """Return the aerosol layer midpoint pressure for fixed-thickness placement."""

        placement = self.aerosol.placement

        return 0.5 * (placement.top_pressure_hpa + placement.bottom_pressure_hpa)

    @aerosol_layer_mid_pressure_hpa.setter
    def aerosol_layer_mid_pressure_hpa(self, value: float) -> None:

        thickness_hpa = self.aerosol_layer_pressure_thickness_hpa

        if thickness_hpa <= 0.0:
            raise ValueError("aerosol layer pressure thickness must be positive")

        mid_pressure_hpa = float(value)
        self.set_aerosol_layer_pressure_bounds(
            top_pressure_hpa=mid_pressure_hpa - 0.5 * thickness_hpa,
            bottom_pressure_hpa=mid_pressure_hpa + 0.5 * thickness_hpa,
        )

    def set_aerosol_layer_pressure_bounds(
        self,
        *,
        top_pressure_hpa: float,
        bottom_pressure_hpa: float,
    ) -> None:
        """Set aerosol layer pressure bounds and keep the fit interval aligned."""

        if bottom_pressure_hpa <= top_pressure_hpa:
            raise ValueError("aerosol layer bottom pressure must exceed top pressure")

        placement = self.aerosol.placement

        if placement.interval_index_1based != self.atmosphere.fit_interval_index_1based:
            raise ValueError("aerosol placement interval does not match atmosphere fit interval")

        placement.top_pressure_hpa = top_pressure_hpa
        placement.bottom_pressure_hpa = bottom_pressure_hpa
        self.atmosphere.set_fit_interval_pressure_bounds(
            top_pressure_hpa=top_pressure_hpa,
            bottom_pressure_hpa=bottom_pressure_hpa,
        )

    def __repr__(self) -> str:

        return (
            "O2AInput(\n"
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
            "  aerosol="
            f"optical depth {self.aerosol.optical_depth_550_nm:g} at 550 nm, "
            f"center {self.aerosol.layer_center_km:g} km, "
            f"width {self.aerosol.layer_width_km:g} km,\n"
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
            o2_lines=O2LineByLine.from_dict(object_dict(data["o2"])),
            collision_induced_absorption=OxygenCollisionInducedAbsorption.from_dict(
                object_dict(data["o2o2"])
            ),
            radiative_transfer=RadiativeTransferControls.from_dict(
                object_dict(data["rtm_controls"])
            ),
            outputs=_object_list(data, "outputs"),
            validation=_object_dict(data, "validation"),
        )

    @classmethod
    def from_json(cls, raw: str | bytes) -> Self:
        """Read an O2 A scene emitted by the zdisamar model."""

        return cls.from_dict(json.loads(raw))

    def to_dict(self) -> dict[str, object]:
        """Return the O2 A scene shape expected by the zdisamar model."""

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
            "outputs": self.outputs,
            "validation": self.validation,
        }

    def to_json_bytes(self) -> bytes:
        """Encode the scene deterministically before the zdisamar model reads it."""

        return json.dumps(json_value(self.to_dict()), sort_keys=True, separators=(",", ":")).encode(
            "utf-8"
        )

    def with_fast_mode(self) -> Self:
        """Return a copy with the validated O2 A fast-mode preset applied.

        The preset combines radiative-transfer performance thresholds with a
        modestly thinner adaptive reference grid.  The grid part is O2 A
        specific: it reduces high-resolution line sampling work while preserving
        the output wavelength grid seen by callers.
        """
        fast = deepcopy(self)
        fast.radiative_transfer.performance_thresholds = (
            fast.radiative_transfer.performance_thresholds.with_fast_mode()
        )
        fast.instrument_response.adaptive_reference_grid = {
            **fast.instrument_response.adaptive_reference_grid,
            **self.FAST_ADAPTIVE_REFERENCE_GRID,
        }

        return fast

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
