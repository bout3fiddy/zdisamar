"""Typed O2 A input object and JSON conversion."""

import json
import math
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
from typing import Any


def _float(value: Any) -> float:
    if isinstance(value, str) and value.lower() == "nan":
        return math.nan
    return float(value)


def _optional_float(data: dict[str, Any], key: str) -> float | None:
    value = data.get(key)
    return None if value is None else _float(value)


def _object_dict(data: dict[str, Any], key: str) -> dict[str, Any]:
    return dict(data[key])


def _object_list(data: dict[str, Any], key: str) -> list[dict[str, Any]]:
    return [dict(item) for item in data.get(key, [])]


def _asset_or_none(asset: ReferenceAsset | None) -> dict[str, Any] | None:
    return None if asset is None else asset.to_dict()


def _json_value(value: Any) -> Any:
    if isinstance(value, float) and math.isnan(value):
        return "nan"
    if isinstance(value, list):
        return [_json_value(item) for item in value]
    if isinstance(value, dict):
        return {key: _json_value(item) for key, item in value.items()}
    return value


@dataclass
class ReferenceAsset:
    id: str
    path: str
    format: str

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> ReferenceAsset:
        return cls(
            id=str(data["id"]),
            path=str(data["path"]),
            format=str(data["format"]),
        )

    def to_dict(self) -> dict[str, Any]:
        return {"id": self.id, "path": self.path, "format": self.format}

    def with_resolved_path(self, resolver) -> ReferenceAsset:
        path = Path(self.path)
        if path.is_absolute():
            return deepcopy(self)
        return ReferenceAsset(id=self.id, path=str(resolver(path)), format=self.format)


@dataclass
class ReferenceAssets:
    atmosphere_profile: ReferenceAsset
    vendor_reference_csv: ReferenceAsset
    raw_solar_reference: ReferenceAsset
    airmass_factor_lut: ReferenceAsset

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> ReferenceAssets:
        return cls(
            atmosphere_profile=ReferenceAsset.from_dict(data["atmosphere_profile"]),
            vendor_reference_csv=ReferenceAsset.from_dict(data["vendor_reference_csv"]),
            raw_solar_reference=ReferenceAsset.from_dict(data["raw_solar_reference"]),
            airmass_factor_lut=ReferenceAsset.from_dict(data["airmass_factor_lut"]),
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "atmosphere_profile": self.atmosphere_profile.to_dict(),
            "vendor_reference_csv": self.vendor_reference_csv.to_dict(),
            "raw_solar_reference": self.raw_solar_reference.to_dict(),
            "airmass_factor_lut": self.airmass_factor_lut.to_dict(),
        }


@dataclass
class SpectralGrid:
    start_nm: float
    end_nm: float
    sample_count: int

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> SpectralGrid:
        return cls(
            start_nm=_float(data["start_nm"]),
            end_nm=_float(data["end_nm"]),
            sample_count=int(data["sample_count"]),
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "start_nm": self.start_nm,
            "end_nm": self.end_nm,
            "sample_count": self.sample_count,
        }


@dataclass
class VerticalInterval:
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
            top_pressure_hpa=_float(data["top_pressure_hpa"]),
            bottom_pressure_hpa=_float(data["bottom_pressure_hpa"]),
            altitude_divisions=int(data["altitude_divisions"]),
            top_altitude_km=_float(data.get("top_altitude_km", math.nan)),
            bottom_altitude_km=_float(data.get("bottom_altitude_km", math.nan)),
            top_pressure_variance_hpa2=_float(data.get("top_pressure_variance_hpa2", 0.0)),
            bottom_pressure_variance_hpa2=_float(data.get("bottom_pressure_variance_hpa2", 0.0)),
        )

    def to_dict(self) -> dict[str, Any]:
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
            solar_zenith_deg=_float(data["solar_zenith_deg"]),
            viewing_zenith_deg=_float(data["viewing_zenith_deg"]),
            relative_azimuth_deg=_float(data["relative_azimuth_deg"]),
        )

    def to_dict(self) -> dict[str, Any]:
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


@dataclass
class AerosolPlacement:
    semantics: str
    interval_index_1based: int
    top_pressure_hpa: float
    bottom_pressure_hpa: float
    top_altitude_km: float = math.nan
    bottom_altitude_km: float = math.nan

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> AerosolPlacement:
        return cls(
            semantics=str(data["semantics"]),
            interval_index_1based=int(data["interval_index_1based"]),
            top_pressure_hpa=_float(data["top_pressure_hpa"]),
            bottom_pressure_hpa=_float(data["bottom_pressure_hpa"]),
            top_altitude_km=_float(data.get("top_altitude_km", math.nan)),
            bottom_altitude_km=_float(data.get("bottom_altitude_km", math.nan)),
        )

    def to_dict(self) -> dict[str, Any]:
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
    optical_depth_550_nm: float
    single_scatter_albedo: float
    asymmetry_factor: float
    angstrom_exponent: float
    reference_wavelength_nm: float
    layer_center_km: float
    layer_width_km: float
    placement: AerosolPlacement

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Aerosol:
        return cls(
            optical_depth_550_nm=_float(data["optical_depth"]),
            single_scatter_albedo=_float(data["single_scatter_albedo"]),
            asymmetry_factor=_float(data["asymmetry_factor"]),
            angstrom_exponent=_float(data["angstrom_exponent"]),
            reference_wavelength_nm=_float(data["reference_wavelength_nm"]),
            layer_center_km=_float(data["layer_center_km"]),
            layer_width_km=_float(data["layer_width_km"]),
            placement=AerosolPlacement.from_dict(data["placement"]),
        )

    def to_dict(self) -> dict[str, Any]:
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


@dataclass
class O2LineByLine:
    line_list_asset: ReferenceAsset
    line_mixing_asset: ReferenceAsset
    strong_lines_asset: ReferenceAsset
    line_mixing_factor: float | None
    isotopes_sim: list[int]
    threshold_line_sim: float | None
    cutoff_sim_cm1: float | None

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> O2LineByLine:
        return cls(
            line_list_asset=ReferenceAsset.from_dict(data["line_list_asset"]),
            line_mixing_asset=ReferenceAsset.from_dict(data["line_mixing_asset"]),
            strong_lines_asset=ReferenceAsset.from_dict(data["strong_lines_asset"]),
            line_mixing_factor=_optional_float(data, "line_mixing_factor"),
            isotopes_sim=[int(value) for value in data["isotopes_sim"]],
            threshold_line_sim=_optional_float(data, "threshold_line_sim"),
            cutoff_sim_cm1=_optional_float(data, "cutoff_sim_cm1"),
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "line_list_asset": self.line_list_asset.to_dict(),
            "line_mixing_asset": self.line_mixing_asset.to_dict(),
            "strong_lines_asset": self.strong_lines_asset.to_dict(),
            "line_mixing_factor": self.line_mixing_factor,
            "isotopes_sim": self.isotopes_sim,
            "threshold_line_sim": self.threshold_line_sim,
            "cutoff_sim_cm1": self.cutoff_sim_cm1,
        }


@dataclass
class OxygenCollisionInducedAbsorption:
    enabled: bool
    cross_section_asset: ReferenceAsset | None

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> OxygenCollisionInducedAbsorption:
        cross_section_asset = data.get("cia_asset")
        return cls(
            enabled=bool(data["enabled"]),
            cross_section_asset=(
                None
                if cross_section_asset is None
                else ReferenceAsset.from_dict(cross_section_asset)
            ),
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "enabled": self.enabled,
            "cia_asset": _asset_or_none(self.cross_section_asset),
        }


@dataclass
class InstrumentResponse:
    instrument_name: str
    regime: str
    sampling: str
    noise_model: str
    instrument_line_fwhm_nm: float
    builtin_line_shape: str
    high_resolution_step_nm: float
    high_resolution_half_span_nm: float
    adaptive_reference_grid: dict[str, int]
    solar_reference_asset_id: str

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> InstrumentResponse:
        return cls(
            instrument_name=str(data["instrument_name"]),
            regime=str(data["regime"]),
            sampling=str(data["sampling"]),
            noise_model=str(data["noise_model"]),
            instrument_line_fwhm_nm=_float(data["instrument_line_fwhm_nm"]),
            builtin_line_shape=str(data["builtin_line_shape"]),
            high_resolution_step_nm=_float(data["high_resolution_step_nm"]),
            high_resolution_half_span_nm=_float(data["high_resolution_half_span_nm"]),
            adaptive_reference_grid={
                key: int(value) for key, value in data["adaptive_reference_grid"].items()
            },
            solar_reference_asset_id=str(data["solar_reference_asset_id"]),
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "instrument_name": self.instrument_name,
            "regime": self.regime,
            "sampling": self.sampling,
            "noise_model": self.noise_model,
            "instrument_line_fwhm_nm": self.instrument_line_fwhm_nm,
            "builtin_line_shape": self.builtin_line_shape,
            "high_resolution_step_nm": self.high_resolution_step_nm,
            "high_resolution_half_span_nm": self.high_resolution_half_span_nm,
            "adaptive_reference_grid": self.adaptive_reference_grid,
            "solar_reference_asset_id": self.solar_reference_asset_id,
        }


@dataclass
class RadiativeTransferControls:
    scattering: str
    n_streams: int
    use_adding: bool
    num_orders_max: int
    fourier_floor_scalar: int
    threshold_conv_first: float
    threshold_conv_mult: float
    threshold_doubl: float
    threshold_mul: float
    use_spherical_correction: bool
    integrate_source_function: bool
    renorm_phase_function: bool
    stokes_dimension: int
    phase_function_truncation_threshold: float = 1.0e-8

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> RadiativeTransferControls:
        return cls(
            scattering=str(data["scattering"]),
            n_streams=int(data["n_streams"]),
            use_adding=bool(data["use_adding"]),
            num_orders_max=int(data["num_orders_max"]),
            fourier_floor_scalar=int(data["fourier_floor_scalar"]),
            threshold_conv_first=_float(data["threshold_conv_first"]),
            threshold_conv_mult=_float(data["threshold_conv_mult"]),
            threshold_doubl=_float(data["threshold_doubl"]),
            threshold_mul=_float(data["threshold_mul"]),
            use_spherical_correction=bool(data["use_spherical_correction"]),
            integrate_source_function=bool(data["integrate_source_function"]),
            renorm_phase_function=bool(data["renorm_phase_function"]),
            phase_function_truncation_threshold=_float(
                data.get("phase_function_truncation_threshold", 1.0e-8)
            ),
            stokes_dimension=int(data["stokes_dimension"]),
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "scattering": self.scattering,
            "n_streams": self.n_streams,
            "use_adding": self.use_adding,
            "num_orders_max": self.num_orders_max,
            "fourier_floor_scalar": self.fourier_floor_scalar,
            "threshold_conv_first": self.threshold_conv_first,
            "threshold_conv_mult": self.threshold_conv_mult,
            "threshold_doubl": self.threshold_doubl,
            "threshold_mul": self.threshold_mul,
            "use_spherical_correction": self.use_spherical_correction,
            "integrate_source_function": self.integrate_source_function,
            "renorm_phase_function": self.renorm_phase_function,
            "phase_function_truncation_threshold": self.phase_function_truncation_threshold,
            "stokes_dimension": self.stokes_dimension,
        }


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
                albedo=_float(data["surface_albedo"]),
                pressure_hpa=_float(data["surface_pressure_hpa"]),
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
        return json.dumps(
            _json_value(self.to_dict()), sort_keys=True, separators=(",", ":")
        ).encode("utf-8")

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
