//! Purpose:
//!   Define the measurement-space transport products and provider bindings.
//!
//! Physics:
//!   Carries the transport, surface, instrument, and noise hooks required to
//!   map radiance into measurement-space summary and product outputs.
//!
//! Vendor:
//!   `measurement-space products`
//!
//! Design:
//!   Keeps measurement-space outputs separate from the transport kernels so
//!   the solver can remain focused on optical state preparation.
//!
//! Invariants:
//!   Measurement summaries and products share the same sample count and shape
//!   contract established by the workspace helpers.
//!
//! Validation:
//!   Measurement-space summary and product tests.

const std = @import("std");
const InstrumentProviders = @import("../../../plugins/providers/instrument.zig");
const NoiseProviders = @import("../../../plugins/providers/noise.zig");
const SurfaceProviders = @import("../../../plugins/providers/surface.zig");
const TransportProviders = @import("../../../plugins/providers/transport.zig");

const Allocator = std.mem.Allocator;

pub const reflectance_export_name = "reflectance";
pub const fitted_reflectance_export_name = "fitted_reflectance";

/// Bound provider implementations used by measurement-space evaluation.
pub const ProviderBindings = struct {
    transport: TransportProviders.Provider,
    surface: SurfaceProviders.Provider,
    instrument: InstrumentProviders.Provider,
    noise: NoiseProviders.Provider,
};

/// Measurement-space summary statistics for one spectral sweep.
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

/// Measurement-space product arrays and associated bulk optical properties.
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

    /// Purpose:
    ///   Release the owned measurement-space product buffers.
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
