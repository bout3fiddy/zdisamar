"""Instrument-response input objects."""

from dataclasses import dataclass
from typing import Any

from .shared import to_float


@dataclass
class SpectralGrid:
    start_nm: float
    end_nm: float
    sample_count: int

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> SpectralGrid:

        return cls(
            start_nm=to_float(data["start_nm"]),
            end_nm=to_float(data["end_nm"]),
            sample_count=int(data["sample_count"]),
        )

    def to_dict(self) -> dict[str, float | int]:

        return {
            "start_nm": self.start_nm,
            "end_nm": self.end_nm,
            "sample_count": self.sample_count,
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
            instrument_line_fwhm_nm=to_float(data["instrument_line_fwhm_nm"]),
            builtin_line_shape=str(data["builtin_line_shape"]),
            high_resolution_step_nm=to_float(data["high_resolution_step_nm"]),
            high_resolution_half_span_nm=to_float(data["high_resolution_half_span_nm"]),
            adaptive_reference_grid={
                key: int(value) for key, value in data["adaptive_reference_grid"].items()
            },
            solar_reference_asset_id=str(data["solar_reference_asset_id"]),
        )

    def to_dict(self) -> dict[str, float | str | dict[str, int]]:

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
