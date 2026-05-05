"""Private ctypes declarations for the native zdisamar C ABI."""

from __future__ import annotations

import ctypes
import os
import sys
from pathlib import Path


class CSpectrum(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_size_t),
        ("wavelength_nm", ctypes.POINTER(ctypes.c_double)),
        ("radiance", ctypes.POINTER(ctypes.c_double)),
        ("irradiance", ctypes.POINTER(ctypes.c_double)),
        ("reflectance", ctypes.POINTER(ctypes.c_double)),
        ("jacobian", ctypes.POINTER(ctypes.c_double)),
        ("jacobian_state_count", ctypes.c_size_t),
        ("result_handle", ctypes.c_void_p),
    ]


class CDiagnosticReport(ctypes.Structure):
    _fields_ = [
        ("sample_count", ctypes.c_uint32),
        ("wavelength_start_nm", ctypes.c_double),
        ("wavelength_end_nm", ctypes.c_double),
        ("mean_radiance", ctypes.c_double),
        ("mean_irradiance", ctypes.c_double),
        ("mean_reflectance", ctypes.c_double),
    ]


class CAtmosphericBudgetRow(ctypes.Structure):
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


class CAtmosphericBudget(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_size_t),
        ("rows", ctypes.POINTER(CAtmosphericBudgetRow)),
    ]


class O2LineContributionRow(ctypes.Structure):
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


class O2LineContributionsRaw(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_size_t),
        ("total_row_count", ctypes.c_size_t),
        ("truncated", ctypes.c_uint8),
        ("rows", ctypes.POINTER(O2LineContributionRow)),
    ]


class CInstrumentResponseRow(ctypes.Structure):
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


class CInstrumentResponse(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_size_t),
        ("rows", ctypes.POINTER(CInstrumentResponseRow)),
    ]


class O2O2CIARow(ctypes.Structure):
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


class O2O2CIADiagnosticsRaw(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_size_t),
        ("rows", ctypes.POINTER(O2O2CIARow)),
    ]


class CRadiativeTransferDiagnosticRow(ctypes.Structure):
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


class CRadiativeTransferDiagnostics(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_size_t),
        ("rows", ctypes.POINTER(CRadiativeTransferDiagnosticRow)),
    ]


def load_library(path: str | os.PathLike[str] | None = None) -> ctypes.CDLL:
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


def configure(lib: ctypes.CDLL) -> ctypes.CDLL:
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
    lib.zds_run_spectrum.argtypes = [ctypes.c_void_p, ctypes.POINTER(CSpectrum)]
    lib.zds_run_spectrum.restype = ctypes.c_int
    lib.zds_run_spectrum_jacobian.argtypes = [ctypes.c_void_p, ctypes.POINTER(CSpectrum)]
    lib.zds_run_spectrum_jacobian.restype = ctypes.c_int
    lib.zds_spectrum_report.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(CSpectrum),
        ctypes.POINTER(CDiagnosticReport),
    ]
    lib.zds_spectrum_report.restype = ctypes.c_int
    lib.zds_atmospheric_budget.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_size_t,
        ctypes.POINTER(CAtmosphericBudget),
    ]
    lib.zds_atmospheric_budget.restype = ctypes.c_int
    lib.zds_o2_line_contributions.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_size_t,
        ctypes.c_size_t,
        ctypes.POINTER(O2LineContributionsRaw),
    ]
    lib.zds_o2_line_contributions.restype = ctypes.c_int
    lib.zds_instrument_response_sampling.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_size_t,
        ctypes.c_uint32,
        ctypes.POINTER(CInstrumentResponse),
    ]
    lib.zds_instrument_response_sampling.restype = ctypes.c_int
    lib.zds_o2_o2_cia_diagnostics.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_size_t,
        ctypes.POINTER(O2O2CIADiagnosticsRaw),
    ]
    lib.zds_o2_o2_cia_diagnostics.restype = ctypes.c_int
    lib.zds_radiative_transfer_diagnostics.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_size_t,
        ctypes.POINTER(CSpectrum),
        ctypes.POINTER(CRadiativeTransferDiagnostics),
    ]
    lib.zds_radiative_transfer_diagnostics.restype = ctypes.c_int
    lib.zds_spectrum_free.argtypes = [ctypes.c_void_p, ctypes.POINTER(CSpectrum)]
    lib.zds_spectrum_free.restype = None
    lib.zds_atmospheric_budget_free.argtypes = [ctypes.c_void_p, ctypes.POINTER(CAtmosphericBudget)]
    lib.zds_atmospheric_budget_free.restype = None
    lib.zds_o2_line_contributions_free.argtypes = [ctypes.c_void_p, ctypes.POINTER(O2LineContributionsRaw)]
    lib.zds_o2_line_contributions_free.restype = None
    lib.zds_instrument_response_free.argtypes = [ctypes.c_void_p, ctypes.POINTER(CInstrumentResponse)]
    lib.zds_instrument_response_free.restype = None
    lib.zds_o2_o2_cia_diagnostics_free.argtypes = [ctypes.c_void_p, ctypes.POINTER(O2O2CIADiagnosticsRaw)]
    lib.zds_o2_o2_cia_diagnostics_free.restype = None
    lib.zds_radiative_transfer_diagnostics_free.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(CRadiativeTransferDiagnostics),
    ]
    lib.zds_radiative_transfer_diagnostics_free.restype = None
    lib.zds_last_error.argtypes = [ctypes.c_void_p]
    lib.zds_last_error.restype = ctypes.c_char_p
    return lib


def _library_name() -> str:
    if sys.platform == "darwin":
        return "libzdisamar_c.dylib"
    if os.name == "nt":
        return "zdisamar_c.dll"
    return "libzdisamar_c.so"
