"""ctypes function signatures for the native zdisamar C ABI."""

import ctypes

from .structures import (
    CAtmosphericBudget,
    CDiagnosticReport,
    CInstrumentResponse,
    CRadiativeTransferDiagnostics,
    CSpectrum,
    O2LineContributionsRaw,
    OxygenCollisionInducedAbsorptionDiagnosticsRaw,
)


def configure(lib: ctypes.CDLL) -> ctypes.CDLL:
    lib.zds_context_create.argtypes = []
    lib.zds_context_create.restype = ctypes.c_void_p
    lib.zds_context_destroy.argtypes = [ctypes.c_void_p]
    lib.zds_context_destroy.restype = None
    lib.zds_prepare_default_o2a.argtypes = [ctypes.c_void_p]
    lib.zds_prepare_default_o2a.restype = ctypes.c_int
    lib.zds_prepare_o2a_json.argtypes = [
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_size_t,
    ]
    lib.zds_prepare_o2a_json.restype = ctypes.c_int
    lib.zds_warm_o2a_session.argtypes = [ctypes.c_void_p]
    lib.zds_warm_o2a_session.restype = ctypes.c_int
    lib.zds_default_o2a_input_json.argtypes = [
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_size_t),
    ]
    lib.zds_default_o2a_input_json.restype = ctypes.c_int
    lib.zds_run_spectrum.argtypes = [ctypes.c_void_p, ctypes.POINTER(CSpectrum)]
    lib.zds_run_spectrum.restype = ctypes.c_int
    lib.zds_run_spectrum_jacobian.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(CSpectrum),
    ]
    lib.zds_run_spectrum_jacobian.restype = ctypes.c_int
    lib.zds_run_spectrum_jacobian_for_states.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(CSpectrum),
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_size_t,
    ]
    lib.zds_run_spectrum_jacobian_for_states.restype = ctypes.c_int
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
        ctypes.POINTER(OxygenCollisionInducedAbsorptionDiagnosticsRaw),
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
    lib.zds_atmospheric_budget_free.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(CAtmosphericBudget),
    ]
    lib.zds_atmospheric_budget_free.restype = None
    lib.zds_o2_line_contributions_free.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(O2LineContributionsRaw),
    ]
    lib.zds_o2_line_contributions_free.restype = None
    lib.zds_instrument_response_free.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(CInstrumentResponse),
    ]
    lib.zds_instrument_response_free.restype = None
    lib.zds_o2_o2_cia_diagnostics_free.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(OxygenCollisionInducedAbsorptionDiagnosticsRaw),
    ]
    lib.zds_o2_o2_cia_diagnostics_free.restype = None
    lib.zds_radiative_transfer_diagnostics_free.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(CRadiativeTransferDiagnostics),
    ]
    lib.zds_radiative_transfer_diagnostics_free.restype = None
    lib.zds_last_error.argtypes = [ctypes.c_void_p]
    lib.zds_last_error.restype = ctypes.c_char_p
    return lib
