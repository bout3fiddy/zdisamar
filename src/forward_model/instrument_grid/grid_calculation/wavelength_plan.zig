const IntegrationKernel = @import("../../implementations/instrument.zig").IntegrationKernel;

pub const WavelengthSampling = struct {
    nominal_wavelength_nm: f64,
    radiance_wavelength_nm: f64,
    irradiance_wavelength_nm: f64,
    radiance_integration: IntegrationKernel,
    irradiance_integration: IntegrationKernel,
};

pub const ForwardCacheMiss = struct {
    key: u64,
    wavelength_nm: f64,
};
