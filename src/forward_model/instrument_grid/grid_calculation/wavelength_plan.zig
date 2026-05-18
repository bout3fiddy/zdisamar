const IntegrationKernel = @import("../../implementations/instrument.zig").IntegrationKernel;

// layout(64-bit):
//   size: 65592 B, align: 8 B
//   field storage: 65592 B across 5 fields; largest: radiance_integration=32784 B, irradiance_integration=32784 B, nominal_wavelength_nm=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 1025 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 65592 B (64.1 KiB); total = per instance * live instance count
pub const WavelengthSampling = struct {
    nominal_wavelength_nm: f64,
    radiance_wavelength_nm: f64,
    irradiance_wavelength_nm: f64,
    radiance_integration: IntegrationKernel,
    irradiance_integration: IntegrationKernel,
};

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: key=8 B, wavelength_nm=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count
pub const ForwardCacheMiss = struct {
    key: u64,
    wavelength_nm: f64,
};
