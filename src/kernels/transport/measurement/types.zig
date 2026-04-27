const std = @import("std");
const InstrumentProviders = @import("../../../o2a/providers/instrument.zig");
const NoiseProviders = @import("../../../o2a/providers/noise.zig");
const SurfaceProviders = @import("../../../o2a/providers/surface.zig");
const TransportProviders = @import("../../../o2a/providers/transport.zig");

const Allocator = std.mem.Allocator;

pub const reflectance_export_name = "reflectance";
pub const fitted_reflectance_export_name = "fitted_reflectance";

// Bound implementation implementations used by instrument grid evaluation.
pub const ProviderBindings = struct {
    transport: TransportProviders.Provider,
    surface: SurfaceProviders.Provider,
    instrument: InstrumentProviders.Provider,
    noise: NoiseProviders.Provider,
};

// Measurement-space summary statistics for one spectral sweep.
pub const MeasurementSpaceSummary = struct {
    sample_count: u32,
    wavelength_start_nm: f64,
    wavelength_end_nm: f64,
    mean_radiance: f64,
    mean_irradiance: f64,
    mean_reflectance: f64,
    mean_noise_sigma: f64,
    mean_jacobian: ?f64 = null,
};

// Measurement-space product arrays and associated bulk optical properties.
pub const MeasurementSpaceProduct = struct {
    summary: MeasurementSpaceSummary,
    wavelengths: []f64,
    radiance: []f64,
    irradiance: []f64,
    reflectance: []f64,
    noise_sigma: []f64,
    radiance_noise_sigma: []f64 = &.{},
    irradiance_noise_sigma: []f64 = &.{},
    reflectance_noise_sigma: []f64 = &.{},
    jacobian: ?[]f64 = null,
    effective_air_mass_factor: f64,
    effective_single_scatter_albedo: f64,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
    gas_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    cloud_optical_depth: f64,
    total_optical_depth: f64,
    depolarization_factor: f64,
    d_optical_depth_d_temperature: f64,

    pub fn deinit(self: *MeasurementSpaceProduct, allocator: Allocator) void {
        allocator.free(self.wavelengths);
        allocator.free(self.radiance);
        allocator.free(self.irradiance);
        allocator.free(self.reflectance);
        allocator.free(self.noise_sigma);
        if (self.radiance_noise_sigma.len != 0 and self.radiance_noise_sigma.ptr != self.noise_sigma.ptr) allocator.free(self.radiance_noise_sigma);
        if (self.irradiance_noise_sigma.len != 0) allocator.free(self.irradiance_noise_sigma);
        if (self.reflectance_noise_sigma.len != 0) allocator.free(self.reflectance_noise_sigma);
        if (self.jacobian) |values| allocator.free(values);
        self.* = undefined;
    }
};

// Borrowed instrument grid outputs backed by a reusable product storage.
pub const MeasurementSpaceProductView = struct {
    summary: MeasurementSpaceSummary,
    wavelengths: []const f64,
    radiance: []const f64,
    irradiance: []const f64,
    reflectance: []const f64,
    noise_sigma: []const f64,
    radiance_noise_sigma: []const f64 = &.{},
    irradiance_noise_sigma: []const f64 = &.{},
    reflectance_noise_sigma: []const f64 = &.{},
    jacobian: ?[]const f64 = null,
    effective_air_mass_factor: f64,
    effective_single_scatter_albedo: f64,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
    gas_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    cloud_optical_depth: f64,
    total_optical_depth: f64,
    depolarization_factor: f64,
    d_optical_depth_d_temperature: f64,

    pub fn toOwned(self: MeasurementSpaceProductView, allocator: Allocator) !MeasurementSpaceProduct {
        const wavelengths = try cloneF64Slice(allocator, self.wavelengths);
        errdefer allocator.free(wavelengths);
        const radiance = try cloneF64Slice(allocator, self.radiance);
        errdefer allocator.free(radiance);
        const irradiance = try cloneF64Slice(allocator, self.irradiance);
        errdefer allocator.free(irradiance);
        const reflectance = try cloneF64Slice(allocator, self.reflectance);
        errdefer allocator.free(reflectance);
        const noise_sigma = try cloneF64Slice(allocator, self.noise_sigma);
        errdefer allocator.free(noise_sigma);
        const radiance_noise_sigma = if (self.radiance_noise_sigma.ptr == self.noise_sigma.ptr)
            noise_sigma
        else
            try cloneF64Slice(allocator, self.radiance_noise_sigma);
        errdefer if (radiance_noise_sigma.ptr != noise_sigma.ptr) allocator.free(radiance_noise_sigma);
        const irradiance_noise_sigma = try cloneF64Slice(allocator, self.irradiance_noise_sigma);
        errdefer allocator.free(irradiance_noise_sigma);
        const reflectance_noise_sigma = try cloneF64Slice(allocator, self.reflectance_noise_sigma);
        errdefer allocator.free(reflectance_noise_sigma);
        const jacobian = if (self.jacobian) |values| try cloneF64Slice(allocator, values) else null;
        errdefer if (jacobian) |values| allocator.free(values);

        return .{
            .summary = self.summary,
            .wavelengths = wavelengths,
            .radiance = radiance,
            .irradiance = irradiance,
            .reflectance = reflectance,
            .noise_sigma = noise_sigma,
            .radiance_noise_sigma = radiance_noise_sigma,
            .irradiance_noise_sigma = irradiance_noise_sigma,
            .reflectance_noise_sigma = reflectance_noise_sigma,
            .jacobian = jacobian,
            .effective_air_mass_factor = self.effective_air_mass_factor,
            .effective_single_scatter_albedo = self.effective_single_scatter_albedo,
            .effective_temperature_k = self.effective_temperature_k,
            .effective_pressure_hpa = self.effective_pressure_hpa,
            .gas_optical_depth = self.gas_optical_depth,
            .cia_optical_depth = self.cia_optical_depth,
            .aerosol_optical_depth = self.aerosol_optical_depth,
            .cloud_optical_depth = self.cloud_optical_depth,
            .total_optical_depth = self.total_optical_depth,
            .depolarization_factor = self.depolarization_factor,
            .d_optical_depth_d_temperature = self.d_optical_depth_d_temperature,
        };
    }
};

fn cloneF64Slice(allocator: Allocator, values: []const f64) ![]f64 {
    if (values.len == 0) return try allocator.alloc(f64, 0);
    return try allocator.dupe(f64, values);
}
