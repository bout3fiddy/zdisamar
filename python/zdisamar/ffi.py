"""ctypes bindings for coarse native O2A spectrum calls."""

from __future__ import annotations

import ctypes
import copy
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from .types import O2AInput


class _CSpectrum(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_size_t),
        ("wavelength_nm", ctypes.POINTER(ctypes.c_double)),
        ("radiance", ctypes.POINTER(ctypes.c_double)),
        ("irradiance", ctypes.POINTER(ctypes.c_double)),
        ("reflectance", ctypes.POINTER(ctypes.c_double)),
        ("result_handle", ctypes.c_void_p),
    ]


class _CDiagnosticReport(ctypes.Structure):
    _fields_ = [
        ("sample_count", ctypes.c_uint32),
        ("wavelength_start_nm", ctypes.c_double),
        ("wavelength_end_nm", ctypes.c_double),
        ("mean_radiance", ctypes.c_double),
        ("mean_irradiance", ctypes.c_double),
        ("mean_reflectance", ctypes.c_double),
    ]


class _CAtmosphericBudgetRow(ctypes.Structure):
    _fields_ = [
        ("wavelength_nm", ctypes.c_double),
        ("layer_index", ctypes.c_uint32),
        ("sublayer_index", ctypes.c_uint32),
        ("global_sublayer_index", ctypes.c_uint32),
        ("interval_index_1based", ctypes.c_uint32),
        ("support_row_kind", ctypes.c_uint32),
        ("subcolumn_label", ctypes.c_uint32),
        ("altitude_km", ctypes.c_double),
        ("top_altitude_km", ctypes.c_double),
        ("bottom_altitude_km", ctypes.c_double),
        ("pressure_hpa", ctypes.c_double),
        ("top_pressure_hpa", ctypes.c_double),
        ("bottom_pressure_hpa", ctypes.c_double),
        ("temperature_k", ctypes.c_double),
        ("number_density_cm3", ctypes.c_double),
        ("oxygen_number_density_cm3", ctypes.c_double),
        ("absorber_number_density_cm3", ctypes.c_double),
        ("path_length_cm", ctypes.c_double),
        ("aerosol_fraction", ctypes.c_double),
        ("cloud_fraction", ctypes.c_double),
        ("gas_absorption_optical_depth", ctypes.c_double),
        ("gas_scattering_optical_depth", ctypes.c_double),
        ("cia_optical_depth", ctypes.c_double),
        ("aerosol_optical_depth", ctypes.c_double),
        ("aerosol_scattering_optical_depth", ctypes.c_double),
        ("aerosol_absorption_optical_depth", ctypes.c_double),
        ("cloud_optical_depth", ctypes.c_double),
        ("cloud_scattering_optical_depth", ctypes.c_double),
        ("cloud_absorption_optical_depth", ctypes.c_double),
        ("total_absorption_optical_depth", ctypes.c_double),
        ("total_scattering_optical_depth", ctypes.c_double),
        ("total_optical_depth", ctypes.c_double),
        ("single_scatter_albedo", ctypes.c_double),
    ]


class _CAtmosphericBudget(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_size_t),
        ("rows", ctypes.POINTER(_CAtmosphericBudgetRow)),
    ]


class _O2LineContributionRow(ctypes.Structure):
    _fields_ = [
        ("wavelength_nm", ctypes.c_double),
        ("profile_node_index", ctypes.c_uint32),
        ("altitude_km", ctypes.c_double),
        ("row_kind", ctypes.c_uint32),
        ("status", ctypes.c_uint32),
        ("line_index", ctypes.c_uint32),
        ("strong_line_index", ctypes.c_uint32),
        ("matched_strong_line_index", ctypes.c_uint32),
        ("gas_index", ctypes.c_uint16),
        ("isotope_number", ctypes.c_uint8),
        ("isotopologue_code", ctypes.c_int32),
        ("center_wavelength_nm", ctypes.c_double),
        ("center_wavenumber_cm1", ctypes.c_double),
        ("shifted_center_wavenumber_cm1", ctypes.c_double),
        ("line_strength_cm2_per_molecule", ctypes.c_double),
        ("air_half_width_cm1", ctypes.c_double),
        ("pressure_shift_cm1", ctypes.c_double),
        ("lower_state_energy_cm1", ctypes.c_double),
        ("temperature_k", ctypes.c_double),
        ("pressure_hpa", ctypes.c_double),
        ("weak_line_sigma_cm2_per_molecule", ctypes.c_double),
        ("strong_line_sigma_cm2_per_molecule", ctypes.c_double),
        ("line_mixing_sigma_cm2_per_molecule", ctypes.c_double),
        ("total_sigma_cm2_per_molecule", ctypes.c_double),
        ("abs_total_sigma_cm2_per_molecule", ctypes.c_double),
    ]


class _O2LineContributions(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_size_t),
        ("total_row_count", ctypes.c_size_t),
        ("truncated", ctypes.c_uint8),
        ("rows", ctypes.POINTER(_O2LineContributionRow)),
    ]


class _CInstrumentResponseRow(ctypes.Structure):
    _fields_ = [
        ("nominal_index", ctypes.c_int32),
        ("nominal_wavelength_nm", ctypes.c_double),
        ("channel", ctypes.c_uint32),
        ("sample_index", ctypes.c_uint32),
        ("support_count", ctypes.c_uint32),
        ("offset_nm", ctypes.c_double),
        ("support_wavelength_nm", ctypes.c_double),
        ("weight", ctypes.c_double),
        ("support_width_nm", ctypes.c_double),
        ("instrument_fwhm_nm", ctypes.c_double),
        ("high_resolution_step_nm", ctypes.c_double),
        ("high_resolution_half_span_nm", ctypes.c_double),
        ("integration_mode", ctypes.c_uint32),
        ("response_enabled", ctypes.c_uint8),
    ]


class _CInstrumentResponse(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_size_t),
        ("rows", ctypes.POINTER(_CInstrumentResponseRow)),
    ]


class _O2O2CIARow(ctypes.Structure):
    _fields_ = [
        ("wavelength_nm", ctypes.c_double),
        ("layer_index", ctypes.c_uint32),
        ("sublayer_index", ctypes.c_uint32),
        ("global_sublayer_index", ctypes.c_uint32),
        ("interval_index_1based", ctypes.c_uint32),
        ("altitude_km", ctypes.c_double),
        ("pressure_hpa", ctypes.c_double),
        ("temperature_k", ctypes.c_double),
        ("oxygen_number_density_cm3", ctypes.c_double),
        ("path_length_cm", ctypes.c_double),
        ("cia_cross_section_cm5_per_molecule2", ctypes.c_double),
        ("cia_optical_depth", ctypes.c_double),
        ("total_absorption_optical_depth", ctypes.c_double),
        ("total_optical_depth", ctypes.c_double),
        ("cia_share_of_total_absorption", ctypes.c_double),
        ("cia_share_of_total_optical_depth", ctypes.c_double),
    ]


class _O2O2CIADiagnostics(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_size_t),
        ("rows", ctypes.POINTER(_O2O2CIARow)),
    ]


class _CRadiativeTransferDiagnosticRow(ctypes.Structure):
    _fields_ = [
        ("wavelength_nm", ctypes.c_double),
        ("layer_index", ctypes.c_uint32),
        ("sublayer_index", ctypes.c_uint32),
        ("global_sublayer_index", ctypes.c_uint32),
        ("interval_index_1based", ctypes.c_uint32),
        ("altitude_km", ctypes.c_double),
        ("total_optical_depth", ctypes.c_double),
        ("total_absorption_optical_depth", ctypes.c_double),
        ("total_scattering_optical_depth", ctypes.c_double),
        ("single_scatter_albedo", ctypes.c_double),
        ("cumulative_optical_depth_above", ctypes.c_double),
        ("mid_layer_transmission_proxy", ctypes.c_double),
        ("direct_surface_transmission_proxy", ctypes.c_double),
        ("atmospheric_scattering_source_proxy", ctypes.c_double),
        ("absorption_loss_proxy", ctypes.c_double),
        ("pseudo_spherical_airmass_factor", ctypes.c_double),
        ("n_streams", ctypes.c_uint32),
        ("integrate_source_function", ctypes.c_uint8),
        ("final_reflectance", ctypes.c_double),
        ("final_radiance", ctypes.c_double),
    ]


class _CRadiativeTransferDiagnostics(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_size_t),
        ("rows", ctypes.POINTER(_CRadiativeTransferDiagnosticRow)),
    ]


@dataclass(frozen=True)
class DiagnosticReport:
    sample_count: int
    wavelength_start_nm: float
    wavelength_end_nm: float
    mean_radiance: float
    mean_irradiance: float
    mean_reflectance: float


def _library_name() -> str:
    if sys.platform == "darwin":
        return "libzdisamar_c.dylib"
    if os.name == "nt":
        return "zdisamar_c.dll"
    return "libzdisamar_c.so"


def _load_library(path: Optional[str | os.PathLike[str]] = None) -> ctypes.CDLL:
    if path is not None:
        return ctypes.CDLL(os.fspath(path))

    env_path = os.environ.get("ZDISAMAR_LIBRARY")
    if env_path:
        return ctypes.CDLL(env_path)

    repo_root = Path(__file__).resolve().parents[2]
    candidates = [
        repo_root / "zig-out" / "lib" / _library_name(),
        repo_root / _library_name(),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ctypes.CDLL(str(candidate))

    return ctypes.CDLL(_library_name())


def _configure(lib: ctypes.CDLL) -> ctypes.CDLL:
    lib.zds_context_create.argtypes = []
    lib.zds_context_create.restype = ctypes.c_void_p
    lib.zds_context_destroy.argtypes = [ctypes.c_void_p]
    lib.zds_context_destroy.restype = None
    lib.zds_prepare_default_o2a.argtypes = [ctypes.c_void_p]
    lib.zds_prepare_default_o2a.restype = ctypes.c_int
    lib.zds_prepare_o2a_json.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t]
    lib.zds_prepare_o2a_json.restype = ctypes.c_int
    lib.zds_default_o2a_input_json.argtypes = [
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_size_t),
    ]
    lib.zds_default_o2a_input_json.restype = ctypes.c_int
    lib.zds_run_spectrum.argtypes = [ctypes.c_void_p, ctypes.POINTER(_CSpectrum)]
    lib.zds_run_spectrum.restype = ctypes.c_int
    lib.zds_spectrum_report.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(_CSpectrum),
        ctypes.POINTER(_CDiagnosticReport),
    ]
    lib.zds_spectrum_report.restype = ctypes.c_int
    lib.zds_atmospheric_budget.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_size_t,
        ctypes.POINTER(_CAtmosphericBudget),
    ]
    lib.zds_atmospheric_budget.restype = ctypes.c_int
    lib.zds_o2_line_contributions.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_size_t,
        ctypes.c_size_t,
        ctypes.POINTER(_O2LineContributions),
    ]
    lib.zds_o2_line_contributions.restype = ctypes.c_int
    lib.zds_instrument_response_sampling.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_size_t,
        ctypes.c_uint32,
        ctypes.POINTER(_CInstrumentResponse),
    ]
    lib.zds_instrument_response_sampling.restype = ctypes.c_int
    lib.zds_o2_o2_cia_diagnostics.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_size_t,
        ctypes.POINTER(_O2O2CIADiagnostics),
    ]
    lib.zds_o2_o2_cia_diagnostics.restype = ctypes.c_int
    lib.zds_radiative_transfer_diagnostics.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_size_t,
        ctypes.POINTER(_CSpectrum),
        ctypes.POINTER(_CRadiativeTransferDiagnostics),
    ]
    lib.zds_radiative_transfer_diagnostics.restype = ctypes.c_int
    lib.zds_spectrum_free.argtypes = [ctypes.c_void_p, ctypes.POINTER(_CSpectrum)]
    lib.zds_spectrum_free.restype = None
    lib.zds_atmospheric_budget_free.argtypes = [ctypes.c_void_p, ctypes.POINTER(_CAtmosphericBudget)]
    lib.zds_atmospheric_budget_free.restype = None
    lib.zds_o2_line_contributions_free.argtypes = [ctypes.c_void_p, ctypes.POINTER(_O2LineContributions)]
    lib.zds_o2_line_contributions_free.restype = None
    lib.zds_instrument_response_free.argtypes = [ctypes.c_void_p, ctypes.POINTER(_CInstrumentResponse)]
    lib.zds_instrument_response_free.restype = None
    lib.zds_o2_o2_cia_diagnostics_free.argtypes = [ctypes.c_void_p, ctypes.POINTER(_O2O2CIADiagnostics)]
    lib.zds_o2_o2_cia_diagnostics_free.restype = None
    lib.zds_radiative_transfer_diagnostics_free.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(_CRadiativeTransferDiagnostics),
    ]
    lib.zds_radiative_transfer_diagnostics_free.restype = None
    lib.zds_last_error.argtypes = [ctypes.c_void_p]
    lib.zds_last_error.restype = ctypes.c_char_p
    return lib


class Spectrum:
    """Bulk spectrum arrays returned by one native run."""

    def __init__(self, owner: "Context", raw: _CSpectrum, close_owner: bool = False):
        self._owner = owner
        self._raw = raw
        self._close_owner = close_owner
        self._diagnostic_report: Optional[DiagnosticReport] = None

    def _array(self, pointer: object):
        self._require_open()
        import numpy as np

        return np.ctypeslib.as_array(pointer, shape=(self._raw.len,))

    def _require_open(self) -> None:
        if self._owner is None or self._owner._ctx is None:
            raise RuntimeError("spectrum is closed")

    @property
    def wavelength_nm(self):
        return self._array(self._raw.wavelength_nm)

    @property
    def radiance(self):
        return self._array(self._raw.radiance)

    @property
    def irradiance(self):
        return self._array(self._raw.irradiance)

    @property
    def reflectance(self):
        return self._array(self._raw.reflectance)

    @property
    def diagnostic_report(self) -> DiagnosticReport:
        self._require_open()
        owner = self._owner
        if owner is None:
            raise RuntimeError("spectrum is closed")
        if self._diagnostic_report is None:
            self._diagnostic_report = owner._spectrum_report(self._raw)
        return self._diagnostic_report

    def close(self) -> None:
        if self._owner is not None:
            owner = self._owner
            owner._free_spectrum(self._raw)
            if self._close_owner:
                owner.close()
            self._owner = None
            self._raw = _CSpectrum()
            self._close_owner = False

    def __enter__(self) -> "Spectrum":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


class AtmosphericBudget:
    """Atmospheric support-row absorption and scattering table."""

    support_row_kind_labels = {
        0: "physical",
        1: "parity_boundary",
        2: "parity_active",
    }
    subcolumn_label_labels = {
        0: "unspecified",
        1: "boundary_layer",
        2: "free_troposphere",
        3: "fit_interval",
        4: "stratosphere",
    }
    columns = tuple(name for name, _ctype in _CAtmosphericBudgetRow._fields_)

    def __init__(self, owner: "Context", raw: _CAtmosphericBudget):
        self._owner = owner
        self._raw = raw

    def _require_open(self) -> None:
        if self._owner is None or self._owner._ctx is None:
            raise RuntimeError("atmospheric budget is closed")

    @property
    def row_count(self) -> int:
        return int(self._raw.len)

    @property
    def table(self):
        self._require_open()
        import numpy as np

        return np.ctypeslib.as_array(self._raw.rows, shape=(self._raw.len,))

    def column(self, name: str):
        if name not in self.columns:
            raise KeyError(name)
        return self.table[name]

    def to_rows(self) -> list[dict[str, float | int | str]]:
        table = self.table
        rows: list[dict[str, float | int | str]] = []
        for row in table:
            item = {name: row[name].item() for name in self.columns}
            item["support_row_kind_label"] = self.support_row_kind_labels.get(
                int(item["support_row_kind"]),
                "unknown",
            )
            item["subcolumn_label_label"] = self.subcolumn_label_labels.get(
                int(item["subcolumn_label"]),
                "unknown",
            )
            rows.append(item)
        return rows

    def to_pandas(self):
        import pandas as pd

        rows = self.to_rows()
        return pd.DataFrame.from_records(rows)

    def close(self) -> None:
        if self._owner is not None:
            self._owner._free_atmospheric_budget(self._raw)
            self._owner = None
            self._raw = _CAtmosphericBudget()

    def __enter__(self) -> "AtmosphericBudget":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


class O2LineContributions:
    """O2 line-by-line contribution table for selected wavelengths."""

    row_kind_labels = {
        0: "weak_line",
        1: "strong_line",
    }
    status_labels = {
        0: "weak_included",
        1: "weak_excluded_by_strong_line",
        2: "strong_sidecar",
        3: "weak_zero_after_cutoff",
    }
    columns = tuple(name for name, _ctype in _O2LineContributionRow._fields_)

    def __init__(self, owner: "Context", raw: _O2LineContributions):
        self._owner = owner
        self._raw = raw

    def _require_open(self) -> None:
        if self._owner is None or self._owner._ctx is None:
            raise RuntimeError("O2 line contribution table is closed")

    @property
    def row_count(self) -> int:
        return int(self._raw.len)

    @property
    def total_row_count(self) -> int:
        return int(self._raw.total_row_count)

    @property
    def truncated(self) -> bool:
        return bool(self._raw.truncated)

    @property
    def table(self):
        self._require_open()
        import numpy as np

        return np.ctypeslib.as_array(self._raw.rows, shape=(self._raw.len,))

    def column(self, name: str):
        if name not in self.columns:
            raise KeyError(name)
        return self.table[name]

    def to_rows(self) -> list[dict[str, float | int | str]]:
        table = self.table
        rows: list[dict[str, float | int | str]] = []
        for row in table:
            item = {name: row[name].item() for name in self.columns}
            item["row_kind_label"] = self.row_kind_labels.get(
                int(item["row_kind"]),
                "unknown",
            )
            item["status_label"] = self.status_labels.get(
                int(item["status"]),
                "unknown",
            )
            rows.append(item)
        return rows

    def to_pandas(self):
        import pandas as pd

        rows = self.to_rows()
        return pd.DataFrame.from_records(rows)

    def close(self) -> None:
        if self._owner is not None:
            self._owner._free_o2_line_contributions(self._raw)
            self._owner = None
            self._raw = _O2LineContributions()

    def __enter__(self) -> "O2LineContributions":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


class InstrumentResponseTable:
    """Native instrument response support-weight table."""

    channel_labels = {
        0: "radiance",
        1: "irradiance",
    }
    integration_mode_labels = {
        0: "auto",
        1: "explicit_hr_grid",
        2: "disamar_hr_grid",
        3: "adaptive",
    }
    columns = tuple(name for name, _ctype in _CInstrumentResponseRow._fields_)

    def __init__(self, owner: "Context", raw: _CInstrumentResponse):
        self._owner = owner
        self._raw = raw

    def _require_open(self) -> None:
        if self._owner is None or self._owner._ctx is None:
            raise RuntimeError("instrument response table is closed")

    @property
    def row_count(self) -> int:
        return int(self._raw.len)

    @property
    def table(self):
        self._require_open()
        import numpy as np

        return np.ctypeslib.as_array(self._raw.rows, shape=(self._raw.len,))

    def to_rows(self) -> list[dict[str, float | int | str]]:
        rows: list[dict[str, float | int | str]] = []
        for row in self.table:
            item = {name: row[name].item() for name in self.columns}
            item["channel_label"] = self.channel_labels.get(int(item["channel"]), "unknown")
            item["integration_mode_label"] = self.integration_mode_labels.get(
                int(item["integration_mode"]),
                "unknown",
            )
            rows.append(item)
        return rows

    def to_pandas(self):
        import pandas as pd

        return pd.DataFrame.from_records(self.to_rows())

    def close(self) -> None:
        if self._owner is not None:
            self._owner._free_instrument_response(self._raw)
            self._owner = None
            self._raw = _CInstrumentResponse()

    def __enter__(self) -> "InstrumentResponseTable":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


class O2O2CIADiagnosticTable:
    """Native O2-O2 CIA diagnostic table."""

    columns = tuple(name for name, _ctype in _O2O2CIARow._fields_)

    def __init__(self, owner: "Context", raw: _O2O2CIADiagnostics):
        self._owner = owner
        self._raw = raw

    def _require_open(self) -> None:
        if self._owner is None or self._owner._ctx is None:
            raise RuntimeError("O2-O2 CIA diagnostic table is closed")

    @property
    def row_count(self) -> int:
        return int(self._raw.len)

    @property
    def table(self):
        self._require_open()
        import numpy as np

        return np.ctypeslib.as_array(self._raw.rows, shape=(self._raw.len,))

    def to_rows(self) -> list[dict[str, float | int]]:
        return [{name: row[name].item() for name in self.columns} for row in self.table]

    def to_pandas(self):
        import pandas as pd

        return pd.DataFrame.from_records(self.to_rows())

    def close(self) -> None:
        if self._owner is not None:
            self._owner._free_o2_o2_cia_diagnostics(self._raw)
            self._owner = None
            self._raw = _O2O2CIADiagnostics()

    def __enter__(self) -> "O2O2CIADiagnosticTable":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


class RadiativeTransferDiagnosticTable:
    """Native bounded radiative-transfer diagnostic table."""

    columns = tuple(name for name, _ctype in _CRadiativeTransferDiagnosticRow._fields_)

    def __init__(self, owner: "Context", raw: _CRadiativeTransferDiagnostics):
        self._owner = owner
        self._raw = raw

    def _require_open(self) -> None:
        if self._owner is None or self._owner._ctx is None:
            raise RuntimeError("radiative-transfer diagnostic table is closed")

    @property
    def row_count(self) -> int:
        return int(self._raw.len)

    @property
    def table(self):
        self._require_open()
        import numpy as np

        return np.ctypeslib.as_array(self._raw.rows, shape=(self._raw.len,))

    def to_rows(self) -> list[dict[str, float | int]]:
        return [{name: row[name].item() for name in self.columns} for row in self.table]

    def to_pandas(self):
        import pandas as pd

        return pd.DataFrame.from_records(self.to_rows())

    def close(self) -> None:
        if self._owner is not None:
            self._owner._free_radiative_transfer_diagnostics(self._raw)
            self._owner = None
            self._raw = _CRadiativeTransferDiagnostics()

    def __enter__(self) -> "RadiativeTransferDiagnosticTable":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


class AtmosphereDiagnostics:
    """Prepared atmospheric diagnostic entrypoints."""

    def __init__(self, prepared: "PreparedO2A | PreparedDefaultO2A"):
        self._prepared = prepared

    def budget(self, wavelengths_nm) -> AtmosphericBudget:
        return self._prepared.atmospheric_budget(wavelengths_nm)


class O2LineDiagnostics:
    """Prepared O2 line diagnostic entrypoints."""

    def __init__(self, prepared: "PreparedO2A | PreparedDefaultO2A"):
        self._prepared = prepared

    def contributions(self, wavelengths_nm, max_rows: int = 50_000) -> O2LineContributions:
        return self._prepared.o2_line_contributions(wavelengths_nm, max_rows=max_rows)


def _contiguous_wavelengths(wavelengths_nm):
    import numpy as np

    wavelengths = np.ascontiguousarray(wavelengths_nm, dtype=np.float64)
    if wavelengths.ndim != 1:
        raise ValueError("wavelengths_nm must be one-dimensional")
    if wavelengths.size == 0:
        raise ValueError("wavelengths_nm must not be empty")
    return wavelengths


def _channel_mask(channels: tuple[str, ...]) -> int:
    masks = {"radiance": 1, "irradiance": 2}
    mask = 0
    for channel in channels:
        try:
            mask |= masks[channel]
        except KeyError as exc:
            raise ValueError(f"unsupported spectral channel: {channel}") from exc
    if mask == 0:
        raise ValueError("channels must not be empty")
    return mask


class Context:
    """Native zdisamar context."""

    def __init__(self, library_path: Optional[str | os.PathLike[str]] = None):
        self._lib = _configure(_load_library(library_path))
        self._ctx = self._lib.zds_context_create()
        if not self._ctx:
            raise RuntimeError("failed to create zdisamar context")

    def close(self) -> None:
        if self._ctx:
            self._lib.zds_context_destroy(self._ctx)
            self._ctx = None

    def prepare_default_o2a(self) -> "Context":
        self._check(self._lib.zds_prepare_default_o2a(self._ctx))
        return self

    def default_o2a_input(self) -> O2AInput:
        size = ctypes.c_size_t()
        self._check(self._lib.zds_default_o2a_input_json(self._ctx, None, 0, ctypes.byref(size)))
        buffer = ctypes.create_string_buffer(size.value + 1)
        self._check(
            self._lib.zds_default_o2a_input_json(
                self._ctx,
                ctypes.cast(buffer, ctypes.c_void_p),
                ctypes.sizeof(buffer),
                ctypes.byref(size),
            )
        )
        return O2AInput.from_json(buffer.value[: size.value])

    def prepare_o2a(self, input: O2AInput) -> "Context":
        payload = input.to_json_bytes()
        self._check(
            self._lib.zds_prepare_o2a_json(
                self._ctx,
                ctypes.c_char_p(payload),
                len(payload),
            )
        )
        return self

    def run(self) -> Spectrum:
        raw = _CSpectrum()
        self._check(self._lib.zds_run_spectrum(self._ctx, ctypes.byref(raw)))
        return Spectrum(self, raw)

    def forward_model(self) -> Spectrum:
        return self.run()

    def _spectrum_report(self, raw: _CSpectrum) -> DiagnosticReport:
        report = _CDiagnosticReport()
        self._check(self._lib.zds_spectrum_report(self._ctx, ctypes.byref(raw), ctypes.byref(report)))
        return DiagnosticReport(
            sample_count=report.sample_count,
            wavelength_start_nm=report.wavelength_start_nm,
            wavelength_end_nm=report.wavelength_end_nm,
            mean_radiance=report.mean_radiance,
            mean_irradiance=report.mean_irradiance,
            mean_reflectance=report.mean_reflectance,
        )

    def atmospheric_budget(self, wavelengths_nm) -> AtmosphericBudget:
        wavelengths = _contiguous_wavelengths(wavelengths_nm)
        raw = _CAtmosphericBudget()
        self._check(
            self._lib.zds_atmospheric_budget(
                self._ctx,
                wavelengths.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                wavelengths.size,
                ctypes.byref(raw),
            )
        )
        return AtmosphericBudget(self, raw)

    def o2_line_contributions(self, wavelengths_nm, max_rows: int = 50_000) -> O2LineContributions:
        wavelengths = _contiguous_wavelengths(wavelengths_nm)
        if max_rows <= 0:
            raise ValueError("max_rows must be positive")
        raw = _O2LineContributions()
        self._check(
            self._lib.zds_o2_line_contributions(
                self._ctx,
                wavelengths.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                wavelengths.size,
                max_rows,
                ctypes.byref(raw),
            )
        )
        return O2LineContributions(self, raw)

    def instrument_response_sampling(
        self,
        wavelengths_nm,
        channels: tuple[str, ...] = ("radiance", "irradiance"),
    ) -> InstrumentResponseTable:
        wavelengths = _contiguous_wavelengths(wavelengths_nm)
        raw = _CInstrumentResponse()
        self._check(
            self._lib.zds_instrument_response_sampling(
                self._ctx,
                wavelengths.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                wavelengths.size,
                _channel_mask(channels),
                ctypes.byref(raw),
            )
        )
        return InstrumentResponseTable(self, raw)

    def o2_o2_cia_diagnostics(self, wavelengths_nm) -> O2O2CIADiagnosticTable:
        wavelengths = _contiguous_wavelengths(wavelengths_nm)
        raw = _O2O2CIADiagnostics()
        self._check(
            self._lib.zds_o2_o2_cia_diagnostics(
                self._ctx,
                wavelengths.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                wavelengths.size,
                ctypes.byref(raw),
            )
        )
        return O2O2CIADiagnosticTable(self, raw)

    def radiative_transfer_diagnostics(self, wavelengths_nm, spectrum: Spectrum | None = None) -> RadiativeTransferDiagnosticTable:
        wavelengths = _contiguous_wavelengths(wavelengths_nm)
        raw = _CRadiativeTransferDiagnostics()
        spectrum_ptr = None
        if spectrum is not None:
            spectrum._require_open()
            spectrum_ptr = ctypes.byref(spectrum._raw)
        self._check(
            self._lib.zds_radiative_transfer_diagnostics(
                self._ctx,
                wavelengths.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                wavelengths.size,
                spectrum_ptr,
                ctypes.byref(raw),
            )
        )
        return RadiativeTransferDiagnosticTable(self, raw)

    def _free_spectrum(self, raw: _CSpectrum) -> None:
        self._lib.zds_spectrum_free(self._ctx, ctypes.byref(raw))

    def _free_atmospheric_budget(self, raw: _CAtmosphericBudget) -> None:
        self._lib.zds_atmospheric_budget_free(self._ctx, ctypes.byref(raw))

    def _free_o2_line_contributions(self, raw: _O2LineContributions) -> None:
        self._lib.zds_o2_line_contributions_free(self._ctx, ctypes.byref(raw))

    def _free_instrument_response(self, raw: _CInstrumentResponse) -> None:
        self._lib.zds_instrument_response_free(self._ctx, ctypes.byref(raw))

    def _free_o2_o2_cia_diagnostics(self, raw: _O2O2CIADiagnostics) -> None:
        self._lib.zds_o2_o2_cia_diagnostics_free(self._ctx, ctypes.byref(raw))

    def _free_radiative_transfer_diagnostics(self, raw: _CRadiativeTransferDiagnostics) -> None:
        self._lib.zds_radiative_transfer_diagnostics_free(self._ctx, ctypes.byref(raw))

    def _check(self, status: int) -> None:
        if status == 0:
            return
        message = self._lib.zds_last_error(self._ctx)
        raise RuntimeError((message or b"zdisamar error").decode("utf-8", errors="replace"))

    def __enter__(self) -> "Context":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


class _PreparedO2ABase:
    """Shared prepared O2A wrapper behavior."""

    _ctx: Optional[Context]
    _input: O2AInput
    _library_path: Optional[str | os.PathLike[str]]

    @property
    def input(self) -> O2AInput:
        return copy.deepcopy(self._input)

    @property
    def library_path(self) -> Optional[str | os.PathLike[str]]:
        return self._library_path

    def _require_context(self) -> Context:
        if self._ctx is None:
            raise RuntimeError("prepared input is closed")
        return self._ctx

    def forward_model(self) -> Spectrum:
        return self._require_context().forward_model()

    @property
    def atmosphere(self: "PreparedO2A | PreparedDefaultO2A") -> AtmosphereDiagnostics:
        self._require_context()
        return AtmosphereDiagnostics(self)

    @property
    def o2_lines(self: "PreparedO2A | PreparedDefaultO2A") -> O2LineDiagnostics:
        self._require_context()
        return O2LineDiagnostics(self)

    @property
    def o2_o2_cia(self: "PreparedO2A | PreparedDefaultO2A"):
        self._require_context()
        from .diagnostics import O2O2CIADiagnostics

        return O2O2CIADiagnostics(self)

    @property
    def instrument_response(self: "PreparedO2A | PreparedDefaultO2A"):
        self._require_context()
        from .diagnostics import InstrumentResponseDiagnostics

        return InstrumentResponseDiagnostics(self)

    @property
    def radiative_transfer(self: "PreparedO2A | PreparedDefaultO2A"):
        self._require_context()
        from .diagnostics import RadiativeTransferDiagnostics

        return RadiativeTransferDiagnostics(self)

    @property
    def perturbations(self: "PreparedO2A | PreparedDefaultO2A"):
        self._require_context()
        from .diagnostics import PerturbationDiagnostics

        return PerturbationDiagnostics(self)

    def atmospheric_budget(self, wavelengths_nm) -> AtmosphericBudget:
        return self._require_context().atmospheric_budget(wavelengths_nm)

    def o2_line_contributions(self, wavelengths_nm, max_rows: int = 50_000) -> O2LineContributions:
        return self._require_context().o2_line_contributions(wavelengths_nm, max_rows=max_rows)

    def instrument_response_sampling(
        self,
        wavelengths_nm,
        channels: tuple[str, ...] = ("radiance", "irradiance"),
    ) -> InstrumentResponseTable:
        return self._require_context().instrument_response_sampling(wavelengths_nm, channels=channels)

    def o2_o2_cia_diagnostics(self, wavelengths_nm) -> O2O2CIADiagnosticTable:
        return self._require_context().o2_o2_cia_diagnostics(wavelengths_nm)

    def radiative_transfer_diagnostics(
        self,
        wavelengths_nm,
        spectrum: Spectrum | None = None,
    ) -> RadiativeTransferDiagnosticTable:
        return self._require_context().radiative_transfer_diagnostics(wavelengths_nm, spectrum=spectrum)

    def close(self) -> None:
        if self._ctx is not None:
            self._ctx.close()
            self._ctx = None

    def __enter__(self):
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


class PreparedDefaultO2A(_PreparedO2ABase):
    """Prepared default O2A input for research-facing forward-model calls."""

    def __init__(self, library_path: Optional[str | os.PathLike[str]] = None):
        ctx = Context(library_path)
        try:
            self._input = ctx.default_o2a_input()
            ctx.prepare_default_o2a()
        except Exception:
            ctx.close()
            raise
        self._ctx: Optional[Context] = ctx
        self._library_path = library_path


class PreparedO2A(_PreparedO2ABase):
    """Prepared O2A input for research-facing forward-model calls."""

    def __init__(self, input: O2AInput, library_path: Optional[str | os.PathLike[str]] = None):
        ctx = Context(library_path)
        try:
            ctx.prepare_o2a(input)
        except Exception:
            ctx.close()
            raise
        self._ctx: Optional[Context] = ctx
        self._input = copy.deepcopy(input)
        self._library_path = library_path


def o2a_disamar_reference_input(
    library_path: Optional[str | os.PathLike[str]] = None,
) -> O2AInput:
    with Context(library_path) as ctx:
        return ctx.default_o2a_input()


def prepare(
    input: O2AInput,
    library_path: Optional[str | os.PathLike[str]] = None,
) -> PreparedO2A:
    return PreparedO2A(input, library_path)


def prepare_default_o2a(
    library_path: Optional[str | os.PathLike[str]] = None,
) -> PreparedDefaultO2A:
    return PreparedDefaultO2A(library_path)


def forward(library_path: Optional[str | os.PathLike[str]] = None) -> Spectrum:
    ctx = Context(library_path)
    try:
        ctx.prepare_default_o2a()
        raw = _CSpectrum()
        ctx._check(ctx._lib.zds_run_spectrum(ctx._ctx, ctypes.byref(raw)))
        return Spectrum(ctx, raw, close_owner=True)
    except Exception:
        ctx.close()
        raise
