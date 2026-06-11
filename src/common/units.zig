// units.zig --------------------------------------------------------------------------------------------------|
// Small unit conversions needed by setup tables.                                                              |
// ------------------------------------------------------------------------------------------------------------|

pub fn wavenumberToWavelengthNm(wavenumber_cm1: f64) f64 {
    // wavenumberToWavelengthNm -------------------------------------------------------------------------------|
    // Convert cm^-1 to nm with the same tiny positive floor used by setup readers.                            |
    // --------------------------------------------------------------------------------------------------------|
    return 1.0e7 / @max(wavenumber_cm1, 1.0e-9);
}

pub fn wavelengthToWavenumberCm1(wavelength_nm: f64) f64 {
    // wavelengthToWavenumberCm1 ------------------------------------------------------------------------------|
    // Convert nm to cm^-1 with the weak-cutoff support-grid floor.                                            |
    // --------------------------------------------------------------------------------------------------------|
    return 1.0e7 / @max(wavelength_nm, 1.0e-9);
}

pub fn spectralWidthCm1ToNm(width_cm1: f64, center_wavenumber_cm1: f64) f64 {
    // spectralWidthCm1ToNm -----------------------------------------------------------------------------------|
    // Convert a local spectral width around a line center from cm^-1 to nm.                                   |
    // --------------------------------------------------------------------------------------------------------|
    const safe_center = @max(center_wavenumber_cm1, 1.0);
    return width_cm1 * 1.0e7 / (safe_center * safe_center);
}
