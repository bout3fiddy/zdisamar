const std = @import("std");
const jacobian = @import("../../jacobian/root.zig");
const InstrumentProviders = @import("../../implementations/instrument.zig");
const NoiseProviders = @import("../../implementations/noise.zig");
const SurfaceProviders = @import("../../implementations/surface.zig");
const TransportProviders = @import("../../implementations/transport.zig");

const Allocator = std.mem.Allocator;

pub const reflectance_export_name = "reflectance";
pub const fitted_reflectance_export_name = "fitted_reflectance";

// Bound implementation implementations used by instrument grid evaluation.
// layout(64-bit):
//   size: 168 B, align: 8 B
//   field storage: transport=64 B, surface=24 B, instrument=48 B, noise=32 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 3 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 168 B (0.164 KiB); total = per instance * live instance count
pub const Implementations = struct {
    transport: TransportProviders.Implementation,
    surface: SurfaceProviders.Implementation,
    instrument: InstrumentProviders.Implementation,
    noise: NoiseProviders.Implementation,
};

// Measurement-space summary statistics for one spectral sweep.
// layout(64-bit):
//   size: 88 B, align: 8 B
//   field storage: 84 B across 8 fields; largest: mean_jacobian=32 B, wavelength_start_nm=8 B, wavelength_end_nm=8 B; padding: 4 B (32 bits)
//   unused bits: 32 padding + 0 bool-storage slack = 32 bits
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 88 B (0.086 KiB); total = per instance * live instance count
pub const InstrumentGridSummary = struct {
    sample_count: u32,
    wavelength_start_nm: f64,
    wavelength_end_nm: f64,
    mean_radiance: f64,
    mean_irradiance: f64,
    mean_reflectance: f64,
    mean_noise_sigma: f64,
    mean_jacobian: ?jacobian.Vector = null,
};

// High-resolution forward result retained between prefetch and cache insertion.
// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage: radiance=8 B, jacobian=24 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   inline arrays: jacobian:[3]f64=24 B
//   count: one cell per unique forward-cache miss in the prefetch batch
//   footprint: per instance = 32 B (0.031 KiB); storage reuses one dense array across batches
pub const ForwardIntegratedSample = struct {
    radiance: f64,
    jacobian: jacobian.Vector = jacobian.zero(),
};

// Measurement-space product arrays and associated bulk optical properties.
// layout(64-bit):
//   size: 320 B, align: 8 B
//   field storage: 320 B across 21 fields; largest: summary=88 B, wavelengths=16 B, radiance=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: wavelengths, radiance, irradiance, reflectance, noise_sigma, +3 more carry references/descriptors; referenced storage is not included in size
//   cache span: 5 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 320 B (0.312 KiB); total also includes referenced storage above
pub const InstrumentGridProduct = struct {
    summary: InstrumentGridSummary,
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

    pub fn deinit(self: *InstrumentGridProduct, allocator: Allocator) void {
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
// layout(64-bit):
//   size: 328 B, align: 8 B
//   field storage: 321 B across 22 fields; largest: summary=88 B, wavelengths=16 B, radiance=16 B; padding: 7 B (56 bits)
//   unused bits: 56 padding + 0 bool-storage slack = 56 bits
//   out-of-line: wavelengths, radiance, irradiance, reflectance, noise_sigma, +3 more carry references/descriptors; referenced storage is not included in size
//   cache span: 6 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 328 B (0.320 KiB); total also includes referenced storage above
pub const InstrumentGridProductView = struct {
    summary: InstrumentGridSummary,
    wavelengths: []const f64,
    radiance: []const f64,
    irradiance: []const f64,
    reflectance: []const f64,
    noise_sigma: []const f64,
    radiance_noise_sigma: []const f64 = &.{},
    irradiance_noise_sigma: []const f64 = &.{},
    reflectance_noise_sigma: []const f64 = &.{},
    // Borrowed workspace Jacobians are state-major and contain only the active
    // derivative states. The default owned product keeps the public full-state
    // row-major shape; requested-state API paths clone compact row-major output
    // directly from the same workspace columns.
    jacobian: ?[]const f64 = null,
    jacobian_state_mask: jacobian.StateMask = 0,
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

    pub fn toOwned(self: InstrumentGridProductView, allocator: Allocator) !InstrumentGridProduct {
        return self.toOwnedWithJacobianStates(allocator, @as([]const jacobian.State, &.{}));
    }

    pub fn toOwnedWithJacobianStates(
        self: InstrumentGridProductView,
        allocator: Allocator,
        output_states: []const jacobian.State,
    ) !InstrumentGridProduct {
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
        const jacobian_values = if (self.jacobian) |values| blk: {
            if (output_states.len == 0) {
                break :blk try cloneExpandedJacobian(allocator, values, self.jacobian_state_mask, self.wavelengths.len);
            }
            break :blk try cloneSelectedRowMajorJacobian(
                allocator,
                values,
                self.jacobian_state_mask,
                self.wavelengths.len,
                output_states,
            );
        } else null;
        errdefer if (jacobian_values) |values| allocator.free(values);

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
            .jacobian = jacobian_values,
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

fn cloneExpandedJacobian(
    allocator: Allocator,
    values: []const f64,
    active_mask: jacobian.StateMask,
    sample_count: usize,
) ![]f64 {
    const active_count = jacobian.activeStateCount(active_mask);
    if (active_count == 0 or values.len != active_count * sample_count) return error.ShapeMismatch;

    const expanded = try allocator.alloc(f64, sample_count * jacobian.state_count);
    @memset(expanded, 0.0);
    for (0..active_count) |active_index| {
        const state = jacobian.activeStateAt(active_mask, active_index) orelse return error.ShapeMismatch;
        const state_index = jacobian.stateIndex(state);
        const column = values[active_index * sample_count ..][0..sample_count];
        for (column, 0..) |value, sample_index| {
            expanded[sample_index * jacobian.state_count + state_index] = value;
        }
    }
    return expanded;
}

fn cloneSelectedRowMajorJacobian(
    allocator: Allocator,
    values: []const f64,
    active_mask: jacobian.StateMask,
    sample_count: usize,
    output_states: []const jacobian.State,
) ![]f64 {
    const active_count = jacobian.activeStateCount(active_mask);
    if (output_states.len == 0 or active_count == 0 or values.len != active_count * sample_count) {
        return error.ShapeMismatch;
    }

    const selected = try allocator.alloc(f64, sample_count * output_states.len);
    errdefer allocator.free(selected);
    for (output_states, 0..) |state, output_index| {
        const active_index = jacobian.activeStateIndex(active_mask, state) orelse return error.ShapeMismatch;
        const column = values[active_index * sample_count ..][0..sample_count];
        for (column, 0..) |value, sample_index| {
            selected[sample_index * output_states.len + output_index] = value;
        }
    }
    return selected;
}

fn cloneF64Slice(allocator: Allocator, values: []const f64) ![]f64 {
    if (values.len == 0) return try allocator.alloc(f64, 0);
    return try allocator.dupe(f64, values);
}
