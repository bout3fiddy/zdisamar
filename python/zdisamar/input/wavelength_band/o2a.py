"""Typed O2 A wavelength-band input object and JSON conversion."""

import json
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from ..aerosol import Aerosol
from ..assets import ReferenceAssets
from ..atmosphere import Atmosphere
from ..geometry import Geometry, Surface
from ..instrument import InstrumentResponse, SpectralGrid
from ..radiative_transfer import RadiativeTransferControls
from ..shared import json_value, to_float
from ..spectroscopy import O2LineByLine, OxygenCollisionInducedAbsorption


def _object_dict(data: dict[str, Any], key: str) -> dict[str, Any]:

    return dict(data[key])


def _object_list(data: dict[str, Any], key: str) -> list[dict[str, Any]]:

    return [dict(item) for item in data.get(key, [])]


@dataclass
class O2AInput:
    metadata: dict[str, Any]
    plan: dict[str, Any]
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
    outputs: list[dict[str, Any]]
    validation: dict[str, Any]

    FAST_ADAPTIVE_REFERENCE_GRID = {
        "points_per_fwhm": 28,
        "strong_line_min_divisions": 6,
        "strong_line_max_divisions": 22,
    }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> O2AInput:

        return cls(
            metadata=_object_dict(data, "metadata"),
            plan=_object_dict(data, "plan"),
            reference_assets=ReferenceAssets.from_dict(data["inputs"]),
            scene_id=str(data["scene_id"]),
            spectral_grid=SpectralGrid.from_dict(data["spectral_grid"]),
            atmosphere=Atmosphere.from_dict(data),
            surface=Surface(
                albedo=to_float(data["surface_albedo"]),
                pressure_hpa=to_float(data["surface_pressure_hpa"]),
            ),
            geometry=Geometry.from_dict(data["geometry"]),
            aerosol=Aerosol.from_dict(data["aerosol"]),
            instrument_response=InstrumentResponse.from_dict(data["observation"]),
            o2_lines=O2LineByLine.from_dict(data["o2"]),
            collision_induced_absorption=OxygenCollisionInducedAbsorption.from_dict(data["o2o2"]),
            radiative_transfer=RadiativeTransferControls.from_dict(data["rtm_controls"]),
            outputs=_object_list(data, "outputs"),
            validation=_object_dict(data, "validation"),
        )

    @classmethod
    def from_json(cls, raw: str | bytes) -> O2AInput:

        return cls.from_dict(json.loads(raw))

    def to_dict(self) -> dict[str, Any]:

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

        return json.dumps(json_value(self.to_dict()), sort_keys=True, separators=(",", ":")).encode(
            "utf-8"
        )

    def with_fast_mode(self) -> O2AInput:
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

    def with_resolved_asset_paths(self, base: str | Path) -> O2AInput:

        root = Path(base)

        return self.with_resolved_asset_resolver(lambda path: (root / path).resolve())

    def with_resolved_asset_resolver(self, resolver) -> O2AInput:

        resolved = deepcopy(self)
        resolved.reference_assets.atmosphere_profile = (
            resolved.reference_assets.atmosphere_profile.with_resolved_path(resolver)
        )
        resolved.reference_assets.vendor_reference_csv = (
            resolved.reference_assets.vendor_reference_csv.with_resolved_path(resolver)
        )
        resolved.reference_assets.raw_solar_reference = (
            resolved.reference_assets.raw_solar_reference.with_resolved_path(resolver)
        )
        resolved.reference_assets.airmass_factor_lut = (
            resolved.reference_assets.airmass_factor_lut.with_resolved_path(resolver)
        )
        resolved.o2_lines.line_list_asset = resolved.o2_lines.line_list_asset.with_resolved_path(
            resolver
        )
        resolved.o2_lines.line_mixing_asset = (
            resolved.o2_lines.line_mixing_asset.with_resolved_path(resolver)
        )
        resolved.o2_lines.strong_lines_asset = (
            resolved.o2_lines.strong_lines_asset.with_resolved_path(resolver)
        )

        if resolved.collision_induced_absorption.cross_section_asset is not None:
            resolved.collision_induced_absorption.cross_section_asset = (
                resolved.collision_induced_absorption.cross_section_asset.with_resolved_path(
                    resolver
                )
            )

        return resolved
