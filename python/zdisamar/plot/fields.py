"""Stable field names used by the SVG plotting helpers."""

WAVELENGTH_NM = "wavelength_nm"
REFLECTANCE = "reflectance"
RADIANCE = "radiance"
IRRADIANCE = "irradiance"
SUN_NORMALIZED_RADIANCE = "sun_normalized_radiance"
REFLECTANCE_JACOBIAN = "reflectance_jacobian"
RADIANCE_JACOBIAN = "radiance_jacobian"
SNR = "snr"

TOTAL_OPTICAL_DEPTH = "total_optical_depth"
COLLISION_INDUCED_ABSORPTION_OPTICAL_DEPTH = "cia_optical_depth"

SPECTRUM_FIELDS = (WAVELENGTH_NM, REFLECTANCE, RADIANCE, IRRADIANCE)

QUANTITY_LABELS = {
    WAVELENGTH_NM: "Wavelength (nm)",
    REFLECTANCE: "Reflectance",
    RADIANCE: "Radiance",
    IRRADIANCE: "Irradiance",
    SUN_NORMALIZED_RADIANCE: "Sun-normalized radiance (1/sr)",
    REFLECTANCE_JACOBIAN: "Reflectance jacobian",
    RADIANCE_JACOBIAN: "Radiance jacobian",
    SNR: "Signal-to-noise ratio",
    "altitude_km": "Altitude (km)",
    "pressure_hpa": "Pressure (hPa)",
    TOTAL_OPTICAL_DEPTH: "Total optical depth",
    COLLISION_INDUCED_ABSORPTION_OPTICAL_DEPTH: "O2-O2 collision-induced absorption optical depth",
    "offset_nm": "Offset (nm)",
}
