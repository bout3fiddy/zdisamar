"""Function declarations for the zdisamar library."""

import ctypes

from .structures import (
    CAtmosphericBudget,
    CDiagnosticReport,
    COptimalEstimationBatchRequest,
    COptimalEstimationBatchResult,
    COptimalEstimationFastmodeBatchResult,
    COptimalEstimationRequest,
    COptimalEstimationResult,
    CSpectrum,
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
    bind(
        lib,
        "zds_prepare_o2a_json",
        [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t],
        ctypes.c_int,
    )
    bind(lib, "zds_warm_o2a_session", [ctypes.c_void_p], ctypes.c_int)
    bind(
        lib,
        "zds_warm_o2a_optimal_estimation",
        [ctypes.c_void_p],
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
        "zds_run_o2a_optimal_estimation",
        [
            ctypes.c_void_p,
            ctypes.POINTER(COptimalEstimationRequest),
            ctypes.POINTER(COptimalEstimationResult),
        ],
        ctypes.c_int,
    )
    bind(
        lib,
        "zds_run_o2a_optimal_estimation_correction",
        [
            ctypes.c_void_p,
            ctypes.POINTER(COptimalEstimationRequest),
            ctypes.POINTER(COptimalEstimationResult),
        ],
        ctypes.c_int,
    )
    bind(
        lib,
        "zds_run_o2a_optimal_estimation_batch",
        [
            ctypes.c_void_p,
            ctypes.POINTER(COptimalEstimationBatchRequest),
            ctypes.POINTER(COptimalEstimationBatchResult),
        ],
        ctypes.c_int,
    )
    bind(
        lib,
        "zds_run_o2a_fastmode_optimal_estimation_batch",
        [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.POINTER(COptimalEstimationBatchRequest),
            ctypes.POINTER(COptimalEstimationBatchRequest),
            ctypes.POINTER(COptimalEstimationFastmodeBatchResult),
        ],
        ctypes.c_int,
    )
    bind(lib, "zds_spectrum_free", [ctypes.c_void_p, ctypes.POINTER(CSpectrum)], None)
    bind(
        lib,
        "zds_optimal_estimation_result_free",
        [ctypes.c_void_p, ctypes.POINTER(COptimalEstimationResult)],
        None,
    )
    bind(
        lib,
        "zds_optimal_estimation_batch_result_free",
        [ctypes.c_void_p, ctypes.POINTER(COptimalEstimationBatchResult)],
        None,
    )
    bind(
        lib,
        "zds_optimal_estimation_fastmode_batch_result_free",
        [ctypes.c_void_p, ctypes.POINTER(COptimalEstimationFastmodeBatchResult)],
        None,
    )
    bind(
        lib,
        "zds_atmospheric_budget_free",
        [ctypes.c_void_p, ctypes.POINTER(CAtmosphericBudget)],
        None,
    )
    bind(lib, "zds_last_error", [ctypes.c_void_p], ctypes.c_char_p)

    return lib
