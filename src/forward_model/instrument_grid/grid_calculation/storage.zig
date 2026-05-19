const std = @import("std");
const core_errors = @import("../../../common/errors.zig");
const Scene = @import("../../../input/Scene.zig").Scene;
const InstrumentIntegration = @import("../../implementations/instrument/integration.zig");
const NoiseProviders = @import("../../implementations/noise.zig");
const OpticsPreparation = @import("../../optical_properties/root.zig");
const common = @import("../../radiative_transfer/root.zig");
const jacobian = @import("../../jacobian/root.zig");
const Cache = @import("cache.zig");
const Plan = @import("wavelength_plan.zig");
const SpectroscopyState = @import("../../optical_properties/state_build/state_spectroscopy.zig");
const grid = @import("../spectral_math/grid.zig");
const convolution = @import("../spectral_math/convolution.zig");
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

// layout(64-bit):
//   size: 280 B, align: 8 B
//   field storage: 273 B across 18 fields; largest: wavelengths=16 B, radiance=16 B, irradiance=16 B; padding: 7 B (56 bits)
//   unused bits: 56 padding + 0 bool-storage slack = 56 bits
//   out-of-line: wavelength/product slices are always active; source_interfaces, rtm_quadrature_levels, and pseudo_spherical_* slices are route-gated and may be empty
//   cache span: 5 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 280 B (0.273 KiB); total also includes referenced storage above
pub const Buffers = struct {
    wavelengths: []f64,
    radiance: []f64,
    irradiance: []f64,
    reflectance: []f64,
    scratch: []f64,
    scratch_aux: []f64,
    layer_inputs: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    jacobian: ?[]f64 = null,
    jacobian_state_mask: jacobian.StateMask = 0,
    noise_sigma: ?[]f64 = null,
    radiance_noise_sigma: ?[]f64 = null,
    irradiance_noise_sigma: ?[]f64 = null,
    reflectance_noise_sigma: ?[]f64 = null,
};

pub fn routeMayUseSourceInterfaces(scene: *const Scene, route: common.Route) bool {
    if (!route.rtm_controls.integrate_source_function) return false;
    return scene.atmosphere.interval_grid.semantics == .none;
}

pub fn routeUsesRtmQuadrature(route: common.Route) bool {
    return route.rtm_controls.integrate_source_function;
}

pub fn routeUsesPseudoSphericalGrid(route: common.Route) bool {
    return route.rtm_controls.use_spherical_correction;
}

// Reusable instrument grid storage that owns the backing storage.
// layout(64-bit):
//   size: 600 B, align: 8 B
//   field storage: 596 B across 29 fields; largest: forward_prefetch_pool=112 B, evaluation_cache=104 B, wavelength_sampling=48 B; padding: 4 B (32 bits)
//   unused bits: 32 padding + 28 bool-storage slack = 60 bits
//   out-of-line: product/noise/cache slices carry backing storage; source_interfaces, rtm_quadrature_levels, and pseudo_spherical_* storage are route-gated
//   cache span: 10 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 600 B (0.586 KiB); total also includes referenced storage above
pub const SummaryStorage = struct {
    wavelengths: []f64 = &.{},
    radiance: []f64 = &.{},
    irradiance: []f64 = &.{},
    reflectance: []f64 = &.{},
    scratch: []f64 = &.{},
    scratch_aux: []f64 = &.{},
    layer_inputs: []common.LayerInput = &.{},
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
    wavelength_sampling: Plan.OwnedWavelengthSampling = .{},
    forward_misses: []Plan.ForwardCacheMiss = &.{},
    profile_spectroscopy_caches: []SpectroscopyState.ProfileNodeSpectroscopyCache = &.{},
    wavelength_plan_key: u64 = 0,
    wavelength_plan_valid: bool = false,
    forward_misses_valid: bool = false,
    profile_spectroscopy_cache_key: u64 = 0,
    profile_spectroscopy_cache_valid: bool = false,
    forward_prefetch_pool: std.Thread.Pool = undefined,
    forward_prefetch_pool_worker_threads: usize = 0,
    forward_prefetch_pool_valid: bool = false,

    pub fn deinit(self: *SummaryStorage, allocator: Allocator) void {
        if (self.forward_prefetch_pool_valid) {
            self.forward_prefetch_pool.deinit();
        }
        freeBuffer(allocator, self.wavelengths);
        freeBuffer(allocator, self.radiance);
        freeBuffer(allocator, self.irradiance);
        freeBuffer(allocator, self.reflectance);
        freeBuffer(allocator, self.scratch);
        freeBuffer(allocator, self.scratch_aux);
        freeLayerBuffer(allocator, self.layer_inputs);
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
        self.wavelength_sampling.deinit(allocator);
        allocator.free(self.forward_misses);
        allocator.free(self.profile_spectroscopy_caches);
        self.* = .{};
    }

    pub fn forwardPrefetchPool(
        self: *SummaryStorage,
        allocator: Allocator,
        worker_count: usize,
    ) ?*std.Thread.Pool {
        if (worker_count <= 1) return null;

        const worker_thread_count = worker_count - 1;
        if (self.forward_prefetch_pool_valid and
            self.forward_prefetch_pool_worker_threads == worker_thread_count)
        {
            return &self.forward_prefetch_pool;
        }

        if (self.forward_prefetch_pool_valid) {
            self.forward_prefetch_pool.deinit();
            self.forward_prefetch_pool_valid = false;
            self.forward_prefetch_pool_worker_threads = 0;
        }

        self.forward_prefetch_pool.init(.{
            .allocator = allocator,
            .n_jobs = worker_thread_count,
        }) catch return null;
        self.forward_prefetch_pool_worker_threads = worker_thread_count;
        self.forward_prefetch_pool_valid = true;
        return &self.forward_prefetch_pool;
    }

    pub fn invalidateWavelengthPlan(self: *SummaryStorage, allocator: Allocator) void {
        self.wavelength_sampling.deinit(allocator);
        allocator.free(self.forward_misses);
        allocator.free(self.profile_spectroscopy_caches);
        self.wavelength_sampling = .{};
        self.forward_misses = &.{};
        self.profile_spectroscopy_caches = &.{};
        self.wavelength_plan_key = 0;
        self.wavelength_plan_valid = false;
        self.forward_misses_valid = false;
        self.profile_spectroscopy_cache_key = 0;
        self.profile_spectroscopy_cache_valid = false;
    }

    pub fn spectralCache(self: *SummaryStorage, allocator: Allocator) Error!*Cache.SpectralEvaluationCache {
        if (self.evaluation_cache == null) {
            self.evaluation_cache = Cache.SpectralEvaluationCache.init(allocator);
        }
        self.evaluation_cache.?.reset();
        return &(self.evaluation_cache.?);
    }

    pub fn buffers(
        self: *SummaryStorage,
        allocator: Allocator,
        scene: *const Scene,
        route: common.Route,
        implementations: Types.Implementations,
    ) Error!Buffers {
        const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
        const layer_count = transportLayerCountHint(scene, route);
        const needs_source_interfaces = routeMayUseSourceInterfaces(scene, route);
        const needs_rtm_quadrature = routeUsesRtmQuadrature(route);
        const needs_pseudo_spherical_grid = routeUsesPseudoSphericalGrid(route);
        const pseudo_spherical_sample_count = if (needs_pseudo_spherical_grid)
            pseudoSphericalSampleCountHint(scene, route)
        else
            0;
        const active_jacobian_mask = if (route.derivative_mode != .none)
            jacobian.sanitizedMask(route.derivative_state_mask)
        else
            0;
        const active_jacobian_count = jacobian.activeStateCount(active_jacobian_mask);
        const wants_jacobian = active_jacobian_count != 0;
        const wants_radiance_noise = implementations.noise.materializesSigma(scene, .radiance);
        const wants_irradiance_noise = implementations.noise.materializesSigma(scene, .irradiance);
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
        if (needs_source_interfaces) {
            try ensureSourceInterfaceBufferCapacity(allocator, &self.source_interfaces, layer_count + 1);
        } else {
            freeSourceInterfaceBuffer(allocator, self.source_interfaces);
            self.source_interfaces = &.{};
        }
        if (needs_rtm_quadrature) {
            try ensureRtmQuadratureBufferCapacity(allocator, &self.rtm_quadrature_levels, layer_count + 1);
        } else {
            freeRtmQuadratureBuffer(allocator, self.rtm_quadrature_levels);
            self.rtm_quadrature_levels = &.{};
        }
        if (needs_pseudo_spherical_grid) {
            try ensurePseudoSphericalSampleBufferCapacity(allocator, &self.pseudo_spherical_samples, pseudo_spherical_sample_count);
            try ensureIndexBufferCapacity(allocator, &self.pseudo_spherical_level_starts, layer_count + 1);
            try ensureBufferCapacity(allocator, &self.pseudo_spherical_level_altitudes, layer_count + 1);
        } else {
            freePseudoSphericalSampleBuffer(allocator, self.pseudo_spherical_samples);
            freeIndexBuffer(allocator, self.pseudo_spherical_level_starts);
            freeBuffer(allocator, self.pseudo_spherical_level_altitudes);
            self.pseudo_spherical_samples = &.{};
            self.pseudo_spherical_level_starts = &.{};
            self.pseudo_spherical_level_altitudes = &.{};
        }
        if (wants_jacobian) {
            try ensureBufferCapacity(allocator, &self.jacobian, sample_count * active_jacobian_count);
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
            .source_interfaces = if (needs_source_interfaces) self.source_interfaces[0 .. layer_count + 1] else &.{},
            .rtm_quadrature_levels = if (needs_rtm_quadrature) self.rtm_quadrature_levels[0 .. layer_count + 1] else &.{},
            .pseudo_spherical_samples = if (needs_pseudo_spherical_grid) self.pseudo_spherical_samples[0..pseudo_spherical_sample_count] else &.{},
            .pseudo_spherical_level_starts = if (needs_pseudo_spherical_grid) self.pseudo_spherical_level_starts[0 .. layer_count + 1] else &.{},
            .pseudo_spherical_level_altitudes = if (needs_pseudo_spherical_grid) self.pseudo_spherical_level_altitudes[0 .. layer_count + 1] else &.{},
            .jacobian = if (wants_jacobian) self.jacobian[0 .. sample_count * active_jacobian_count] else null,
            .jacobian_state_mask = if (wants_jacobian) active_jacobian_mask else 0,
            .noise_sigma = if (wants_noise) self.noise_sigma[0..sample_count] else null,
            .radiance_noise_sigma = if (wants_noise) self.radiance_noise_sigma[0..sample_count] else null,
            .irradiance_noise_sigma = if (wants_noise) self.irradiance_noise_sigma[0..sample_count] else null,
            .reflectance_noise_sigma = if (wants_noise) self.reflectance_noise_sigma[0..sample_count] else null,
        };
    }
};

// Reusable full-product storage that shares the same backing buffers as the
// summary path.
pub const ProductStorage = SummaryStorage;

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

pub fn pseudoSphericalSampleCountHint(scene: *const Scene, route: common.Route) usize {
    const layer_count = transportLayerCountHint(scene, route);
    return layer_count * (pseudoSphericalSubgridDivisions(scene) + 2);
}

pub fn reflectanceCalibrationEnabled(scene: *const Scene) bool {
    const controls = scene.observation_model.resolvedReflectanceCalibration();
    return controls.multiplicative_error.enabled() or controls.additive_error.enabled();
}

pub fn resolvedTransportLayerCount(route: common.Route, prepared: *const OpticsPreparation.PreparedOpticalState) usize {
    _ = route;
    return prepared.transportLayerCount();
}

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

pub fn validateBuffers(scene: *const Scene, route: common.Route, sample_count: usize, buffers: Buffers) Error!void {
    // INVARIANT:
    //   The always-active summary buffers and the route-selected transport
    //   carriers must stay shape-compatible for a single sweep.
    if (sample_count == 0 or
        buffers.wavelengths.len != sample_count or
        buffers.radiance.len != sample_count or
        buffers.irradiance.len != sample_count or
        buffers.reflectance.len != sample_count or
        buffers.scratch.len != sample_count or
        buffers.scratch_aux.len != sample_count or
        buffers.layer_inputs.len == 0)
    {
        return error.ShapeMismatch;
    }
    if (routeMayUseSourceInterfaces(scene, route) and
        buffers.source_interfaces.len != buffers.layer_inputs.len + 1)
    {
        return error.ShapeMismatch;
    }
    if (routeUsesRtmQuadrature(route) and
        buffers.rtm_quadrature_levels.len != buffers.layer_inputs.len + 1)
    {
        return error.ShapeMismatch;
    }
    if (routeUsesPseudoSphericalGrid(route) and
        (buffers.pseudo_spherical_samples.len == 0 or
            buffers.pseudo_spherical_level_starts.len != buffers.layer_inputs.len + 1 or
            buffers.pseudo_spherical_level_altitudes.len != buffers.layer_inputs.len + 1))
    {
        return error.ShapeMismatch;
    }
    if (buffers.jacobian) |values| {
        const active_jacobian_count = jacobian.activeStateCount(buffers.jacobian_state_mask);
        if (active_jacobian_count == 0 or values.len != sample_count * active_jacobian_count) return error.ShapeMismatch;
    } else if (buffers.jacobian_state_mask != 0) {
        return error.ShapeMismatch;
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
