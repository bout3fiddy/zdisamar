"""Result layouts returned by the zdisamar library."""

import ctypes


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
        ("gas_absorption_optical_depth", ctypes.c_double),
        ("gas_scattering_optical_depth", ctypes.c_double),
        ("cia_optical_depth", ctypes.c_double),
        ("aerosol_optical_depth", ctypes.c_double),
        ("aerosol_scattering_optical_depth", ctypes.c_double),
        ("aerosol_absorption_optical_depth", ctypes.c_double),
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


class COptimalEstimationScalarSpec(ctypes.Structure):
    _fields_ = [
        ("has_lower", ctypes.c_uint8),
        ("has_upper", ctypes.c_uint8),
        ("initial", ctypes.c_double),
        ("prior", ctypes.c_double),
        ("variance", ctypes.c_double),
        ("lower", ctypes.c_double),
        ("upper", ctypes.c_double),
    ]


class COptimalEstimationPressureSpec(ctypes.Structure):
    _fields_ = [
        ("scalar", COptimalEstimationScalarSpec),
        ("interval_index_1based", ctypes.c_uint32),
        ("thickness_hpa", ctypes.c_double),
        ("pressure_profile_count", ctypes.c_size_t),
        ("pressure_profile_altitude_km", ctypes.POINTER(ctypes.c_double)),
        ("pressure_profile_pressure_hpa", ctypes.POINTER(ctypes.c_double)),
    ]


class COptimalEstimationControls(ctypes.Structure):
    _fields_ = [
        ("max_iterations", ctypes.c_size_t),
        ("state_vector_convergence_threshold", ctypes.c_double),
        ("max_change_transformed_state", ctypes.c_double),
    ]


class COptimalEstimationRequest(ctypes.Structure):
    _fields_ = [
        ("sample_count", ctypes.c_size_t),
        ("wavelength_nm", ctypes.POINTER(ctypes.c_double)),
        ("reflectance", ctypes.POINTER(ctypes.c_double)),
        ("variance", ctypes.POINTER(ctypes.c_double)),
        ("aerosol_optical_depth", COptimalEstimationScalarSpec),
        ("aerosol_layer_pressure", COptimalEstimationPressureSpec),
        ("controls", COptimalEstimationControls),
    ]


class COptimalEstimationResult(ctypes.Structure):
    _fields_ = [
        ("state_count", ctypes.c_size_t),
        ("iteration_count", ctypes.c_size_t),
        ("converged", ctypes.c_uint8),
        ("state_ids", ctypes.POINTER(ctypes.c_uint8)),
        ("state", ctypes.POINTER(ctypes.c_double)),
        ("initial_state", ctypes.POINTER(ctypes.c_double)),
        ("posterior_covariance", ctypes.POINTER(ctypes.c_double)),
        ("averaging_kernel", ctypes.POINTER(ctypes.c_double)),
        ("history_state", ctypes.POINTER(ctypes.c_double)),
        ("history_chi2", ctypes.POINTER(ctypes.c_double)),
        ("history_chi2_reflectance", ctypes.POINTER(ctypes.c_double)),
        ("history_chi2_state_vector", ctypes.POINTER(ctypes.c_double)),
        ("history_state_vector_convergence", ctypes.POINTER(ctypes.c_double)),
        ("history_snr_normal", ctypes.POINTER(ctypes.c_uint8)),
        ("result_handle", ctypes.c_void_p),
    ]


class COptimalEstimationBatchRequest(ctypes.Structure):
    _fields_ = [
        ("sample_count", ctypes.c_size_t),
        ("wavelength_nm", ctypes.POINTER(ctypes.c_double)),
        ("reflectance", ctypes.POINTER(ctypes.c_double)),
        ("variance", ctypes.POINTER(ctypes.c_double)),
        ("aerosol_optical_depth", COptimalEstimationScalarSpec),
        ("aerosol_layer_pressure", COptimalEstimationPressureSpec),
        ("run_count", ctypes.c_size_t),
        ("initial", ctypes.POINTER(ctypes.c_double)),
        ("prior", ctypes.POINTER(ctypes.c_double)),
        ("controls", COptimalEstimationControls),
        ("batch_worker_count", ctypes.c_size_t),
    ]


class COptimalEstimationBatchResult(ctypes.Structure):
    _fields_ = [
        ("run_count", ctypes.c_size_t),
        ("state_count", ctypes.c_size_t),
        ("history_capacity", ctypes.c_size_t),
        ("iteration_count", ctypes.POINTER(ctypes.c_size_t)),
        ("converged", ctypes.POINTER(ctypes.c_uint8)),
        ("status", ctypes.POINTER(ctypes.c_uint8)),
        ("state", ctypes.POINTER(ctypes.c_double)),
        ("history_state", ctypes.POINTER(ctypes.c_double)),
        ("result_handle", ctypes.c_void_p),
    ]


class COptimalEstimationFastmodeBatchResult(ctypes.Structure):
    _fields_ = [
        ("run_count", ctypes.c_size_t),
        ("state_count", ctypes.c_size_t),
        ("history_capacity", ctypes.c_size_t),
        ("iteration_count", ctypes.POINTER(ctypes.c_size_t)),
        ("converged", ctypes.POINTER(ctypes.c_uint8)),
        ("status", ctypes.POINTER(ctypes.c_uint8)),
        ("state", ctypes.POINTER(ctypes.c_double)),
        ("history_state", ctypes.POINTER(ctypes.c_double)),
        ("fast_stage_iteration_count", ctypes.POINTER(ctypes.c_size_t)),
        ("fast_stage_converged", ctypes.POINTER(ctypes.c_uint8)),
        ("full_correction_iteration_count", ctypes.POINTER(ctypes.c_size_t)),
        ("full_correction_converged", ctypes.POINTER(ctypes.c_uint8)),
        ("result_handle", ctypes.c_void_p),
    ]
