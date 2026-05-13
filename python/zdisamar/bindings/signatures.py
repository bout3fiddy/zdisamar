"""Function declarations for the zdisamar library."""

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


def bind(lib: ctypes.CDLL, name: str, argtypes: list[object], restype: object) -> None:
    """Declare argument and result types before calling zdisamar."""

    function = getattr(lib, name)
    function.argtypes = argtypes
    function.restype = restype


def configure(lib: ctypes.CDLL) -> ctypes.CDLL:
    """Collect the zdisamar library declarations in one place."""

    bind(lib, "zds_context_create", [], ctypes.c_void_p)
    bind(lib, "zds_context_destroy", [ctypes.c_void_p], None)
    bind(lib, "zds_prepare_default_o2a", [ctypes.c_void_p], ctypes.c_int)
    bind(
        lib,
        "zds_prepare_o2a_json",
        [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t],
        ctypes.c_int,
    )
    bind(lib, "zds_warm_o2a_session", [ctypes.c_void_p], ctypes.c_int)
    bind(
        lib,
        "zds_default_o2a_input_json",
        [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_size_t,
            ctypes.POINTER(ctypes.c_size_t),
        ],
        ctypes.c_int,
    )
    bind(lib, "zds_run_spectrum", [ctypes.c_void_p, ctypes.POINTER(CSpectrum)], ctypes.c_int)
    bind(
        lib,
        "zds_run_spectrum_jacobian",
        [ctypes.c_void_p, ctypes.POINTER(CSpectrum)],
        ctypes.c_int,
    )
    bind(
        lib,
        "zds_run_spectrum_jacobian_for_states",
        [
            ctypes.c_void_p,
            ctypes.POINTER(CSpectrum),
            ctypes.POINTER(ctypes.c_uint8),
            ctypes.c_size_t,
        ],
        ctypes.c_int,
    )
    bind(
        lib,
        "zds_spectrum_report",
        [ctypes.c_void_p, ctypes.POINTER(CSpectrum), ctypes.POINTER(CDiagnosticReport)],
        ctypes.c_int,
    )
    bind(
        lib,
        "zds_atmospheric_budget",
        [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_double),
            ctypes.c_size_t,
            ctypes.POINTER(CAtmosphericBudget),
        ],
        ctypes.c_int,
    )
    bind(
        lib,
        "zds_o2_line_contributions",
        [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_double),
            ctypes.c_size_t,
            ctypes.c_size_t,
            ctypes.POINTER(O2LineContributionsRaw),
        ],
        ctypes.c_int,
    )
    bind(
        lib,
        "zds_instrument_response_sampling",
        [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_double),
            ctypes.c_size_t,
            ctypes.c_uint32,
            ctypes.POINTER(CInstrumentResponse),
        ],
        ctypes.c_int,
    )
    bind(
        lib,
        "zds_o2_o2_cia_diagnostics",
        [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_double),
            ctypes.c_size_t,
            ctypes.POINTER(OxygenCollisionInducedAbsorptionDiagnosticsRaw),
        ],
        ctypes.c_int,
    )
    bind(
        lib,
        "zds_radiative_transfer_diagnostics",
        [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_double),
            ctypes.c_size_t,
            ctypes.POINTER(CSpectrum),
            ctypes.POINTER(CRadiativeTransferDiagnostics),
        ],
        ctypes.c_int,
    )
    bind(lib, "zds_spectrum_free", [ctypes.c_void_p, ctypes.POINTER(CSpectrum)], None)
    bind(
        lib,
        "zds_atmospheric_budget_free",
        [ctypes.c_void_p, ctypes.POINTER(CAtmosphericBudget)],
        None,
    )
    bind(
        lib,
        "zds_o2_line_contributions_free",
        [ctypes.c_void_p, ctypes.POINTER(O2LineContributionsRaw)],
        None,
    )
    bind(
        lib,
        "zds_instrument_response_free",
        [ctypes.c_void_p, ctypes.POINTER(CInstrumentResponse)],
        None,
    )
    bind(
        lib,
        "zds_o2_o2_cia_diagnostics_free",
        [ctypes.c_void_p, ctypes.POINTER(OxygenCollisionInducedAbsorptionDiagnosticsRaw)],
        None,
    )
    bind(
        lib,
        "zds_radiative_transfer_diagnostics_free",
        [ctypes.c_void_p, ctypes.POINTER(CRadiativeTransferDiagnostics)],
        None,
    )
    bind(lib, "zds_last_error", [ctypes.c_void_p], ctypes.c_char_p)

    return lib
