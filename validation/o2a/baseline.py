"""Shared O2 A optimal-estimation retrieval baseline settings."""

WAVELENGTH_START_NM = 758.0
WAVELENGTH_END_NM = 770.0
WAVELENGTH_STEP_NM = 0.04
SAMPLE_COUNT = int(round((WAVELENGTH_END_NM - WAVELENGTH_START_NM) / WAVELENGTH_STEP_NM)) + 1
LAYER_THICKNESS_HPA = 50.0
SURFACE_ALBEDO_WAVELENGTHS_NM = (758.0, 770.0)
AEROSOL_SINGLE_SCATTER_ALBEDO = 1.0
AEROSOL_ASYMMETRY_FACTOR = 0.7
AEROSOL_ANGSTROM_EXPONENT = 0.0
INSTRUMENT_LINE_FWHM_NM = 0.12
SOLAR_REFERENCE_PATH = (
    "data/reference_data/solar/o2a_solar_reference_chance_kurucz_2010_753_778.csv"
)
POINTS_PER_FWHM = 30
STRONG_LINE_MIN_DIVISIONS = 6
STRONG_LINE_MAX_DIVISIONS = 30
ZDISAMAR_N_STREAMS = 20
UPPER_ALTITUDE_DIVISIONS = 16
AEROSOL_INTERVAL_DIVISIONS = 4
LOWER_ALTITUDE_DIVISIONS = 6
RADIANCE_SNR_WAVELENGTH_NM = 758.0
RADIANCE_REFERENCE_SNR = 500.0
RADIANCE_REFERENCE_BIN_WIDTH_NM = 0.15
RADIANCE_SNR_MAX = 5000.0
IRRADIANCE_SNR_WAVELENGTH_NM = 758.0
IRRADIANCE_REFERENCE_SNR = 5000.0
IRRADIANCE_SNR_MAX = 5000.0


def configure_case(case) -> None:
    """Apply the retrieval baseline to a mutable zdisamar O2 A case."""

    case.spectral_grid.start_nm = WAVELENGTH_START_NM
    case.spectral_grid.end_nm = WAVELENGTH_END_NM
    case.spectral_grid.sample_count = SAMPLE_COUNT
    case.aerosol.single_scatter_albedo = AEROSOL_SINGLE_SCATTER_ALBEDO
    case.aerosol.asymmetry_factor = AEROSOL_ASYMMETRY_FACTOR
    case.aerosol.angstrom_exponent = AEROSOL_ANGSTROM_EXPONENT
    case.instrument_response.instrument_line_fwhm_nm = INSTRUMENT_LINE_FWHM_NM
    case.reference_assets.raw_solar_reference.path = SOLAR_REFERENCE_PATH
    case.instrument_response.high_resolution_half_span_nm = 3.0 * INSTRUMENT_LINE_FWHM_NM
    case.instrument_response.adaptive_reference_grid["points_per_fwhm"] = POINTS_PER_FWHM
    case.instrument_response.adaptive_reference_grid["strong_line_min_divisions"] = (
        STRONG_LINE_MIN_DIVISIONS
    )
    case.instrument_response.adaptive_reference_grid["strong_line_max_divisions"] = (
        STRONG_LINE_MAX_DIVISIONS
    )
    case.radiative_transfer.n_streams = ZDISAMAR_N_STREAMS
    case.aerosol_layer.thickness_hpa = LAYER_THICKNESS_HPA

    for interval in case.atmosphere.intervals:
        if interval.index_1based == 1:
            interval.altitude_divisions = UPPER_ALTITUDE_DIVISIONS
        elif interval.index_1based == 2:
            interval.altitude_divisions = AEROSOL_INTERVAL_DIVISIONS
        elif interval.index_1based == 3:
            interval.altitude_divisions = LOWER_ALTITUDE_DIVISIONS
