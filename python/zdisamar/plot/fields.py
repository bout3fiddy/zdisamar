"""Stable field names used by the Altair plotting helpers."""

WAVELENGTH_NM = "wavelength_nm"
REFLECTANCE = "reflectance"
RADIANCE = "radiance"
IRRADIANCE = "irradiance"

TOTAL_OPTICAL_DEPTH = "total_optical_depth"
TOTAL_ABSORPTION_OPTICAL_DEPTH = "total_absorption_optical_depth"
TOTAL_SCATTERING_OPTICAL_DEPTH = "total_scattering_optical_depth"
COLLISION_INDUCED_ABSORPTION_OPTICAL_DEPTH = "cia_optical_depth"
AEROSOL_OPTICAL_DEPTH = "aerosol_optical_depth"
CLOUD_OPTICAL_DEPTH = "cloud_optical_depth"

DELTA_REFLECTANCE = "delta_reflectance"
ABS_DELTA_REFLECTANCE = "abs_delta_reflectance"

SOURCE = "source"
VALUE = "value"
QUANTITY = "quantity"
METRIC = "metric"
RESIDUAL = "residual"
RELATIVE_RESIDUAL = "relative_residual"

SPECTRUM_FIELDS = (WAVELENGTH_NM, REFLECTANCE, RADIANCE, IRRADIANCE)

QUANTITY_LABELS = {
    WAVELENGTH_NM: "Wavelength (nm)",
    REFLECTANCE: "Reflectance",
    RADIANCE: "Radiance",
    IRRADIANCE: "Irradiance",
    "altitude_km": "Altitude (km)",
    "pressure_hpa": "Pressure (hPa)",
    "temperature_k": "Temperature (K)",
    TOTAL_OPTICAL_DEPTH: "Total optical depth",
    TOTAL_ABSORPTION_OPTICAL_DEPTH: "Total absorption optical depth",
    TOTAL_SCATTERING_OPTICAL_DEPTH: "Total scattering optical depth",
    COLLISION_INDUCED_ABSORPTION_OPTICAL_DEPTH: "O2-O2 collision-induced absorption optical depth",
    AEROSOL_OPTICAL_DEPTH: "Aerosol optical depth",
    CLOUD_OPTICAL_DEPTH: "Cloud optical depth",
    "gas_absorption_optical_depth": "Gas absorption",
    "gas_scattering_optical_depth": "Gas scattering",
    "aerosol_scattering_optical_depth": "Aerosol scattering",
    "aerosol_absorption_optical_depth": "Aerosol absorption",
    "cloud_scattering_optical_depth": "Cloud scattering",
    "cloud_absorption_optical_depth": "Cloud absorption",
    "single_scatter_albedo": "Single-scatter albedo",
    "cia_share_of_total_absorption": "Collision-induced absorption share of absorption",
    "cia_share_of_total_optical_depth": "Collision-induced absorption share of total optical depth",
    "cia_cross_section_cm5_per_molecule2": (
        "Collision-induced absorption cross section cm5 per molecule2"
    ),
    "weak_line_sigma_cm2_per_molecule": "Weak-line sigma",
    "strong_line_sigma_cm2_per_molecule": "Strong-line sigma",
    "line_mixing_sigma_cm2_per_molecule": "Line-mixing sigma",
    "total_sigma_cm2_per_molecule": "Total sigma",
    "abs_total_sigma_cm2_per_molecule": "Abs total sigma",
    "atmospheric_scattering_source_proxy": "Scattering source",
    "absorption_loss_proxy": "Absorption loss",
    "direct_surface_transmission_proxy": "Direct transmission",
    "cumulative_optical_depth_above": "Cumulative optical depth above",
    "support_width_nm": "Support width (nm)",
    "support_count": "Support count",
    "offset_nm": "Offset (nm)",
    DELTA_REFLECTANCE: "Delta reflectance",
    ABS_DELTA_REFLECTANCE: "Absolute delta reflectance",
    "max_abs_delta_reflectance": "Max absolute delta reflectance",
    "mean_abs_delta_reflectance": "Mean absolute delta reflectance",
    RESIDUAL: "Residual",
    RELATIVE_RESIDUAL: "Relative residual",
}
