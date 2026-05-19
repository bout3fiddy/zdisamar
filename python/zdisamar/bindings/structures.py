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


class OxygenCollisionInducedAbsorptionRow(ctypes.Structure):
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


class OxygenCollisionInducedAbsorptionDiagnosticsRaw(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_size_t),
        ("rows", ctypes.POINTER(OxygenCollisionInducedAbsorptionRow)),
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


class COptimalEstimationStateSpec(ctypes.Structure):
    _fields_ = [
        ("state_id", ctypes.c_uint8),
        ("has_lower", ctypes.c_uint8),
        ("has_upper", ctypes.c_uint8),
        ("interval_index_1based", ctypes.c_uint32),
        ("initial", ctypes.c_double),
        ("prior", ctypes.c_double),
        ("variance", ctypes.c_double),
        ("lower", ctypes.c_double),
        ("upper", ctypes.c_double),
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
        ("collect_timing", ctypes.c_uint8),
    ]


class COptimalEstimationRequest(ctypes.Structure):
    _fields_ = [
        ("sample_count", ctypes.c_size_t),
        ("wavelength_nm", ctypes.POINTER(ctypes.c_double)),
        ("reflectance", ctypes.POINTER(ctypes.c_double)),
        ("variance", ctypes.POINTER(ctypes.c_double)),
        ("state_count", ctypes.c_size_t),
        ("states", ctypes.POINTER(COptimalEstimationStateSpec)),
        ("controls", COptimalEstimationControls),
    ]


class COptimalEstimationResult(ctypes.Structure):
    _fields_ = [
        ("state_count", ctypes.c_size_t),
        ("iteration_count", ctypes.c_size_t),
        ("timing_count", ctypes.c_size_t),
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
        ("timing_rtm_and_jacobian_s", ctypes.POINTER(ctypes.c_double)),
        ("timing_solver_update_s", ctypes.POINTER(ctypes.c_double)),
        ("timing_total_iteration_s", ctypes.POINTER(ctypes.c_double)),
        ("result_handle", ctypes.c_void_p),
    ]
