"""Instrument-response input objects."""

import math
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Self

from .shared import int_dict, to_float, to_int


@dataclass
class SpectralGrid:
    """Nominal output wavelength grid for the spectrum."""

    start_nm: float
    end_nm: float
    sample_count: int

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        return cls(
            start_nm=to_float(data["start_nm"]),
            end_nm=to_float(data["end_nm"]),
            sample_count=to_int(data["sample_count"]),
        )

    def to_dict(self) -> dict[str, float | int]:

        return {
            "start_nm": self.start_nm,
            "end_nm": self.end_nm,
            "sample_count": self.sample_count,
        }


@dataclass
class InstrumentResponse:
    """Instrument line shape and high-resolution sampling settings."""

    instrument_name: str
    regime: str
    sampling: str
    instrument_line_fwhm_nm: float
    builtin_line_shape: str
    high_resolution_step_nm: float
    high_resolution_half_span_nm: float
    adaptive_reference_grid: dict[str, int]
    solar_reference_asset_id: str
    measured_wavelengths_nm: tuple[float, ...] = ()

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        legacy_keys = {"noise_model"}.intersection(data)

        if legacy_keys:
            joined = ", ".join(sorted(legacy_keys))
            raise ValueError(f"unsupported observation fields: {joined}")

        measured_wavelengths = measured_wavelength_tuple(data.get("measured_wavelengths_nm", ()))

        return cls(
            instrument_name=str(data["instrument_name"]),
            regime=str(data["regime"]),
            sampling=str(data["sampling"]),
            instrument_line_fwhm_nm=to_float(data["instrument_line_fwhm_nm"]),
            builtin_line_shape=str(data["builtin_line_shape"]),
            high_resolution_step_nm=to_float(data["high_resolution_step_nm"]),
            high_resolution_half_span_nm=to_float(data["high_resolution_half_span_nm"]),
            adaptive_reference_grid=int_dict(data["adaptive_reference_grid"]),
            solar_reference_asset_id=str(data["solar_reference_asset_id"]),
            measured_wavelengths_nm=measured_wavelengths,
        )

    def to_dict(self) -> dict[str, object]:

        payload: dict[str, object] = {
            "instrument_name": self.instrument_name,
            "regime": self.regime,
            "sampling": self.sampling,
            "instrument_line_fwhm_nm": self.instrument_line_fwhm_nm,
            "builtin_line_shape": self.builtin_line_shape,
            "high_resolution_step_nm": self.high_resolution_step_nm,
            "high_resolution_half_span_nm": self.high_resolution_half_span_nm,
            "adaptive_reference_grid": self.adaptive_reference_grid,
            "solar_reference_asset_id": self.solar_reference_asset_id,
        }

        if self.measured_wavelengths_nm:
            payload["measured_wavelengths_nm"] = list(self.measured_wavelengths_nm)

        return payload


def measured_wavelength_tuple(values: object) -> tuple[float, ...]:
    """Return a strictly increasing explicit measured-wavelength axis."""

    if values is None:
        return ()

    if not isinstance(values, Sequence) or isinstance(values, str | bytes):
        raise TypeError("measured_wavelengths_nm must be a numeric sequence")

    wavelengths = tuple(to_float(value) for value in values)

    for index, wavelength_nm in enumerate(wavelengths):
        if not math.isfinite(wavelength_nm):
            raise ValueError("measured_wavelengths_nm must be finite")

        if index != 0 and wavelength_nm <= wavelengths[index - 1]:
            raise ValueError("measured_wavelengths_nm must be strictly increasing")

    return wavelengths
