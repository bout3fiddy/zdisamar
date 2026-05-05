"""Spectrum result wrappers for native O2A forward-model output."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .c_abi import CSpectrum


@dataclass(frozen=True)
class DiagnosticReport:
    sample_count: int
    wavelength_start_nm: float
    wavelength_end_nm: float
    mean_radiance: float
    mean_irradiance: float
    mean_reflectance: float


class Spectrum:
    """Bulk spectrum arrays returned by one native run."""

    def __init__(self, owner: Any, raw: CSpectrum, close_owner: bool = False):
        self._owner = owner
        self._raw = raw
        self._close_owner = close_owner
        self._diagnostic_report: DiagnosticReport | None = None

    def _array(self, pointer: object) -> Any:
        self._require_open()
        import numpy as np

        return np.ctypeslib.as_array(pointer, shape=(self._raw.len,))

    def _require_open(self) -> Any:
        owner = self._owner
        if owner is None or owner._ctx is None:
            raise RuntimeError("spectrum is closed")
        return owner

    @property
    def wavelength_nm(self) -> Any:
        return self._array(self._raw.wavelength_nm)

    @property
    def radiance(self) -> Any:
        return self._array(self._raw.radiance)

    @property
    def irradiance(self) -> Any:
        return self._array(self._raw.irradiance)

    @property
    def reflectance(self) -> Any:
        return self._array(self._raw.reflectance)

    @property
    def diagnostic_report(self) -> DiagnosticReport:
        owner = self._require_open()
        if self._diagnostic_report is None:
            self._diagnostic_report = owner._spectrum_report(self._raw)
        report = self._diagnostic_report
        if report is None:
            raise RuntimeError("spectrum diagnostic report is unavailable")
        return report

    def close(self) -> None:
        if self._owner is not None:
            owner = self._owner
            owner._free_spectrum(self._raw)
            if self._close_owner:
                owner.close()
            self._owner = None
            self._raw = CSpectrum()
            self._close_owner = False

    def __enter__(self) -> "Spectrum":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()
