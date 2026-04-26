//! Purpose:
//!   Own the reusable measurement-space buffers and capacity planning.
//!
//! Physics:
//!   Allocates the transport, pseudo-spherical, quadrature, and optional
//!   derivative buffers required to materialize measurement-space outputs.
//!
//! Vendor:
//!   `measurement workspace`
//!
//! Design:
//!   Reuses typed buffers across sweeps instead of rebuilding them for every
//!   spectral sample.
//!
//! Invariants:
//!   Buffer shapes must match the scene sample count and the resolved transport
//!   layer count.
//!
//! Validation:
//!   Measurement-space workspace tests and transport integration suites.

const std = @import("std");
const core_errors = @import("../../../core/errors.zig");
const Scene = @import("../../../model/Scene.zig").Scene;
const InstrumentIntegration = @import("../../../o2a/providers/instrument/integration.zig");
const NoiseProviders = @import("../../../o2a/providers/noise.zig");
const OpticsPreparation = @import("../../optics/preparation.zig");
const common = @import("../common.zig");
const Cache = @import("cache.zig");
const grid = @import("../../spectra/grid.zig");
const convolution = @import("../../spectra/convolution.zig");
const Types = @import("types.zig");

const Allocator = std.mem.Allocator;

pub const Error =
    core_errors.Error ||
    common.Error ||
    grid.Error ||
    convolution.Error ||
    InstrumentIntegration.Error ||
    NoiseProviders.Error ||
    error{
        ShapeMismatch,
        OutOfMemory,
    };

pub const Buffers = struct {
    wavelengths: []f64,
    radiance: []f64,
    irradiance: []f64,
    reflectance: []f64,
    scratch: []f64,
    scratch_aux: []f64,
    layer_inputs: []common.LayerInput,
    pseudo_spherical_layers: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    jacobian: ?[]f64 = null,
    noise_sigma: ?[]f64 = null,
    radiance_noise_sigma: ?[]f64 = null,
    irradiance_noise_sigma: ?[]f64 = null,
    reflectance_noise_sigma: ?[]f64 = null,
};

/// Reusable measurement-space workspace that owns the backing storage.
pub const SummaryWorkspace = struct {
    wavelengths: []f64 = &.{},
    radiance: []f64 = &.{},
    irradiance: []f64 = &.{},
    reflectance: []f64 = &.{},
    scratch: []f64 = &.{},
    scratch_aux: []f64 = &.{},
    layer_inputs: []common.LayerInput = &.{},
    pseudo_spherical_layers: []common.LayerInput = &.{},
    source_interfaces: []common.SourceInterfaceInput = &.{},
    rtm_quadrature_levels: []common.RtmQuadratureLevel = &.{},
    pseudo_spherical_samples: []common.PseudoSphericalSample = &.{},
    pseudo_spherical_level_starts: []usize = &.{},
    pseudo_spherical_level_altitudes: []f64 = &.{},
    jacobian: []f64 = &.{},
    noise_sigma: []f64 = &.{},
    radiance_noise_sigma: []f64 = &.{},
    irradiance_noise_sigma: []f64 = &.{},
    reflectance_noise_sigma: []f64 = &.{},
    evaluation_cache: ?Cache.SpectralEvaluationCache = null,

    /// Purpose:
    ///   Release every owned buffer held by the measurement workspace.
    pub fn deinit(self: *SummaryWorkspace, allocator: Allocator) void {
        freeBuffer(allocator, self.wavelengths);
        freeBuffer(allocator, self.radiance);
        freeBuffer(allocator, self.irradiance);
        freeBuffer(allocator, self.reflectance);
        freeBuffer(allocator, self.scratch);
        freeBuffer(allocator, self.scratch_aux);
        freeLayerBuffer(allocator, self.layer_inputs);
        freeLayerBuffer(allocator, self.pseudo_spherical_layers);
        freeSourceInterfaceBuffer(allocator, self.source_interfaces);
        freeRtmQuadratureBuffer(allocator, self.rtm_quadrature_levels);
        freePseudoSphericalSampleBuffer(allocator, self.pseudo_spherical_samples);
        freeIndexBuffer(allocator, self.pseudo_spherical_level_starts);
        freeBuffer(allocator, self.pseudo_spherical_level_altitudes);
        freeBuffer(allocator, self.jacobian);
        freeBuffer(allocator, self.noise_sigma);
        freeBuffer(allocator, self.radiance_noise_sigma);
        freeBuffer(allocator, self.irradiance_noise_sigma);
        freeBuffer(allocator, self.reflectance_noise_sigma);
        if (self.evaluation_cache) |*cache| cache.deinit();
        self.* = .{};
    }

    /// Purpose:
    ///   Return a reusable exact-wavelength spectral cache for one run.
    pub fn spectralCache(self: *SummaryWorkspace, allocator: Allocator) Error!*Cache.SpectralEvaluationCache {
        if (self.evaluation_cache == null) {
            self.evaluation_cache = Cache.SpectralEvaluationCache.init(allocator);
        }
        self.evaluation_cache.?.reset();
        return &(self.evaluation_cache.?);
    }

    /// Purpose:
    ///   Materialize the live slices used by one measurement-space sweep.
    ///
    /// Physics:
    ///   Resizes the reusable buffers to the scene and route shapes without
    ///   changing the solver-side transport contract.
    pub fn buffers(
        self: *SummaryWorkspace,
        allocator: Allocator,
        scene: *const Scene,
        route: common.Route,
        providers: Types.ProviderBindings,
    ) Error!Buffers {
        const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
        const layer_count = transportLayerCountHint(scene, route);
        const pseudo_spherical_sample_count = pseudoSphericalSampleCountHint(scene, route);
        const wants_jacobian = route.derivative_mode != .none;
        const wants_radiance_noise = providers.noise.materializesSigma(scene, .radiance);
        const wants_irradiance_noise = providers.noise.materializesSigma(scene, .irradiance);
        const wants_noise = wants_radiance_noise or
            wants_irradiance_noise or
            reflectanceCalibrationEnabled(scene);

        try ensureBufferCapacity(allocator, &self.wavelengths, sample_count);
        try ensureBufferCapacity(allocator, &self.radiance, sample_count);
        try ensureBufferCapacity(allocator, &self.irradiance, sample_count);
        try ensureBufferCapacity(allocator, &self.reflectance, sample_count);
        try ensureBufferCapacity(allocator, &self.scratch, sample_count);
        try ensureBufferCapacity(allocator, &self.scratch_aux, sample_count);
        try ensureLayerBufferCapacity(allocator, &self.layer_inputs, layer_count);
        try ensureLayerBufferCapacity(allocator, &self.pseudo_spherical_layers, pseudo_spherical_sample_count);
        try ensureSourceInterfaceBufferCapacity(allocator, &self.source_interfaces, layer_count + 1);
        try ensureRtmQuadratureBufferCapacity(allocator, &self.rtm_quadrature_levels, layer_count + 1);
        try ensurePseudoSphericalSampleBufferCapacity(allocator, &self.pseudo_spherical_samples, pseudo_spherical_sample_count);
        try ensureIndexBufferCapacity(allocator, &self.pseudo_spherical_level_starts, layer_count + 1);
        try ensureBufferCapacity(allocator, &self.pseudo_spherical_level_altitudes, layer_count + 1);
        if (wants_jacobian) {
            try ensureBufferCapacity(allocator, &self.jacobian, sample_count);
        }
        if (wants_noise) {
            try ensureBufferCapacity(allocator, &self.noise_sigma, sample_count);
            try ensureBufferCapacity(allocator, &self.radiance_noise_sigma, sample_count);
            try ensureBufferCapacity(allocator, &self.irradiance_noise_sigma, sample_count);
            try ensureBufferCapacity(allocator, &self.reflectance_noise_sigma, sample_count);
        }

        return .{
            .wavelengths = self.wavelengths[0..sample_count],
            .radiance = self.radiance[0..sample_count],
            .irradiance = self.irradiance[0..sample_count],
            .reflectance = self.reflectance[0..sample_count],
            .scratch = self.scratch[0..sample_count],
            .scratch_aux = self.scratch_aux[0..sample_count],
            .layer_inputs = self.layer_inputs[0..layer_count],
            .pseudo_spherical_layers = self.pseudo_spherical_layers[0..pseudo_spherical_sample_count],
            .source_interfaces = self.source_interfaces[0 .. layer_count + 1],
            .rtm_quadrature_levels = self.rtm_quadrature_levels[0 .. layer_count + 1],
            .pseudo_spherical_samples = self.pseudo_spherical_samples[0..pseudo_spherical_sample_count],
            .pseudo_spherical_level_starts = self.pseudo_spherical_level_starts[0 .. layer_count + 1],
            .pseudo_spherical_level_altitudes = self.pseudo_spherical_level_altitudes[0 .. layer_count + 1],
            .jacobian = if (wants_jacobian) self.jacobian[0..sample_count] else null,
            .noise_sigma = if (wants_noise) self.noise_sigma[0..sample_count] else null,
            .radiance_noise_sigma = if (wants_noise) self.radiance_noise_sigma[0..sample_count] else null,
            .irradiance_noise_sigma = if (wants_noise) self.irradiance_noise_sigma[0..sample_count] else null,
            .reflectance_noise_sigma = if (wants_noise) self.reflectance_noise_sigma[0..sample_count] else null,
        };
    }
};

/// Reusable full-product workspace that shares the same backing buffers as the
/// summary path.
pub const ProductWorkspace = SummaryWorkspace;

/// Purpose:
///   Estimate the transport-layer count needed for one measurement sweep.
pub fn transportLayerCountHint(scene: *const Scene, route: common.Route) usize {
    _ = route;
    if (scene.atmosphere.interval_grid.enabled()) {
        const uses_disamar_shared_rtm_grid =
            scene.observation_model.resolvedChannelControls(.radiance).response.integration_mode == .disamar_hr_grid or
            scene.observation_model.resolvedChannelControls(.irradiance).response.integration_mode == .disamar_hr_grid;
        var total_count: usize = 0;
        for (scene.atmosphere.interval_grid.intervals) |interval| {
            total_count += if (uses_disamar_shared_rtm_grid)
                @as(usize, interval.altitude_divisions) + 1
            else
                @max(@as(usize, interval.altitude_divisions), 1);
        }
        return @max(total_count, 1);
    }
    const layer_count = @max(@as(usize, @intCast(scene.atmosphere.layer_count)), 1);
    return layer_count * @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
}

/// Purpose:
///   Estimate the pseudo-spherical sample count needed for one sweep.
pub fn pseudoSphericalSampleCountHint(scene: *const Scene, route: common.Route) usize {
    const layer_count = transportLayerCountHint(scene, route);
    return layer_count * (pseudoSphericalSubgridDivisions(scene) + 2);
}

pub fn reflectanceCalibrationEnabled(scene: *const Scene) bool {
    const controls = scene.observation_model.resolvedReflectanceCalibration();
    return controls.multiplicative_error.enabled() or controls.additive_error.enabled();
}

/// Purpose:
///   Resolve the transport layer count from the prepared optical state.
pub fn resolvedTransportLayerCount(route: common.Route, prepared: *const OpticsPreparation.PreparedOpticalState) usize {
    _ = route;
    return prepared.transportLayerCount();
}

/// Purpose:
///   Resolve the pseudo-spherical sample count from the prepared optical state.
pub fn resolvedPseudoSphericalSampleCount(
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
) usize {
    if (prepared.intervalSemanticsUseReducedSharedRtmLayers() and
        prepared.shared_rtm_geometry.isValidFor(resolvedTransportLayerCount(route, prepared)))
    {
        var sample_count: usize = 0;
        for (prepared.shared_rtm_geometry.layers) |layer| {
            const support_count: usize = @intCast(layer.support_count);
            if (support_count > 2) sample_count += support_count - 2;
        }
        return sample_count;
    }
    return resolvedTransportLayerCount(route, prepared) * pseudoSphericalSubgridDivisions(scene);
}

fn pseudoSphericalSubgridDivisions(scene: *const Scene) usize {
    return @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
}

pub fn validateBuffers(sample_count: usize, buffers: Buffers) Error!void {
    // INVARIANT:
    //   The summary buffers, transport-layer buffers, and quadrature carriers
    //   must stay shape-compatible for a single sweep.
    if (sample_count == 0 or
        buffers.wavelengths.len != sample_count or
        buffers.radiance.len != sample_count or
        buffers.irradiance.len != sample_count or
        buffers.reflectance.len != sample_count or
        buffers.scratch.len != sample_count or
        buffers.scratch_aux.len != sample_count or
        buffers.layer_inputs.len == 0 or
        buffers.pseudo_spherical_layers.len == 0 or
        buffers.source_interfaces.len != buffers.layer_inputs.len + 1 or
        buffers.rtm_quadrature_levels.len != buffers.layer_inputs.len + 1)
    {
        return error.ShapeMismatch;
    }
    if (buffers.pseudo_spherical_samples.len != buffers.pseudo_spherical_layers.len or
        buffers.pseudo_spherical_level_starts.len != buffers.layer_inputs.len + 1 or
        buffers.pseudo_spherical_level_altitudes.len != buffers.layer_inputs.len + 1)
    {
        return error.ShapeMismatch;
    }
    if (buffers.jacobian) |jacobian| {
        if (jacobian.len != sample_count) return error.ShapeMismatch;
    }
    if (buffers.noise_sigma) |noise_sigma| {
        if (noise_sigma.len != sample_count) return error.ShapeMismatch;
    }
    if (buffers.radiance_noise_sigma) |sigma| {
        if (sigma.len != sample_count) return error.ShapeMismatch;
    }
    if (buffers.irradiance_noise_sigma) |sigma| {
        if (sigma.len != sample_count) return error.ShapeMismatch;
    }
    if (buffers.reflectance_noise_sigma) |sigma| {
        if (sigma.len != sample_count) return error.ShapeMismatch;
    }
}

pub fn ensureBufferCapacity(allocator: Allocator, buffer: *[]f64, capacity: usize) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(f64, capacity);
    freeBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensureLayerBufferCapacity(allocator: Allocator, buffer: *[]common.LayerInput, capacity: usize) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(common.LayerInput, capacity);
    freeLayerBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensureSourceInterfaceBufferCapacity(
    allocator: Allocator,
    buffer: *[]common.SourceInterfaceInput,
    capacity: usize,
) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(common.SourceInterfaceInput, capacity);
    freeSourceInterfaceBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensureRtmQuadratureBufferCapacity(
    allocator: Allocator,
    buffer: *[]common.RtmQuadratureLevel,
    capacity: usize,
) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(common.RtmQuadratureLevel, capacity);
    freeRtmQuadratureBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensurePseudoSphericalSampleBufferCapacity(
    allocator: Allocator,
    buffer: *[]common.PseudoSphericalSample,
    capacity: usize,
) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(common.PseudoSphericalSample, capacity);
    freePseudoSphericalSampleBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensureIndexBufferCapacity(allocator: Allocator, buffer: *[]usize, capacity: usize) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(usize, capacity);
    freeIndexBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

/// Purpose:
///   Release the standalone buffer slice if it owns storage.
fn freeBuffer(allocator: Allocator, buffer: []f64) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn freeLayerBuffer(allocator: Allocator, buffer: []common.LayerInput) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn freeSourceInterfaceBuffer(allocator: Allocator, buffer: []common.SourceInterfaceInput) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn freeRtmQuadratureBuffer(allocator: Allocator, buffer: []common.RtmQuadratureLevel) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn freePseudoSphericalSampleBuffer(allocator: Allocator, buffer: []common.PseudoSphericalSample) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn freeIndexBuffer(allocator: Allocator, buffer: []usize) void {
    if (buffer.len != 0) allocator.free(buffer);
}

test "measurement workspace transport hint follows explicit interval totals" {
    const scene: Scene = .{
        .id = "explicit-interval-workspace-hint",
        .atmosphere = .{
            .layer_count = 3,
            .sublayer_divisions = 2,
            .interval_grid = .{
                .semantics = .explicit_pressure_bounds,
                .intervals = &.{
                    .{
                        .index_1based = 1,
                        .top_pressure_hpa = 150.0,
                        .bottom_pressure_hpa = 350.0,
                        .top_altitude_km = 12.0,
                        .bottom_altitude_km = 7.0,
                        .altitude_divisions = 1,
                    },
                    .{
                        .index_1based = 2,
                        .top_pressure_hpa = 350.0,
                        .bottom_pressure_hpa = 800.0,
                        .top_altitude_km = 7.0,
                        .bottom_altitude_km = 2.0,
                        .altitude_divisions = 3,
                    },
                    .{
                        .index_1based = 3,
                        .top_pressure_hpa = 800.0,
                        .bottom_pressure_hpa = 1000.0,
                        .top_altitude_km = 2.0,
                        .bottom_altitude_km = 0.0,
                        .altitude_divisions = 2,
                    },
                },
            },
        },
    };
    const route: common.Route = .{
        .family = .adding,
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    };

    try std.testing.expectEqual(@as(usize, 6), transportLayerCountHint(&scene, route));
    try std.testing.expectEqual(@as(usize, 12), pseudoSphericalSampleCountHint(&scene, route));
}
