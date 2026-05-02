"""Stable field names used by the Altair plotting helpers."""

WAVELENGTH_NM = "wavelength_nm"
REFLECTANCE = "reflectance"
RADIANCE = "radiance"
IRRADIANCE = "irradiance"

TOTAL_OPTICAL_DEPTH = "total_optical_depth"
TOTAL_ABSORPTION_OPTICAL_DEPTH = "total_absorption_optical_depth"
TOTAL_SCATTERING_OPTICAL_DEPTH = "total_scattering_optical_depth"
CIA_OPTICAL_DEPTH = "cia_optical_depth"
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
    TOTAL_OPTICAL_DEPTH: "Total optical depth",
    TOTAL_ABSORPTION_OPTICAL_DEPTH: "Total absorption optical depth",
    TOTAL_SCATTERING_OPTICAL_DEPTH: "Total scattering optical depth",
    CIA_OPTICAL_DEPTH: "O2-O2 CIA optical depth",
    AEROSOL_OPTICAL_DEPTH: "Aerosol optical depth",
    CLOUD_OPTICAL_DEPTH: "Cloud optical depth",
    DELTA_REFLECTANCE: "Delta reflectance",
    ABS_DELTA_REFLECTANCE: "Absolute delta reflectance",
    RESIDUAL: "Residual",
    RELATIVE_RESIDUAL: "Relative residual",
}
