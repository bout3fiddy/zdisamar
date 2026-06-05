const std = @import("std");
const build_options = @import("build_options");
const core_errors = @import("../../../common/errors.zig");
const Scene = @import("../../../input/Scene.zig").Scene;
const InstrumentIntegration = @import("../../implementations/instrument/integration.zig");
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

// migration note: Zig 0.15.2 runtime boundary ---------------------------------------------------------------|
// Product storage keeps the existing std.Thread.Pool route while the project is pinned to Zig 0.15.2.        |
// The failed 0.16 migration briefly moved this path to std.Io.Threaded; do not reintroduce that API here.    |
// end migration note: Zig 0.15.2 runtime boundary -----------------------------------------------------------|

pub const trace_phase_timing_enabled: bool = enabled_by_build: {
    if (!@hasDecl(build_options, "enable_trace_phase_timing")) break :enabled_by_build false;
    break :enabled_by_build build_options.enable_trace_phase_timing;
};

const TracePhaseTimingRoute = if (trace_phase_timing_enabled) struct {
    const Slot = ?*TracePhaseTiming;
    const empty: Slot = null;
} else struct {
    const Slot = void;
    const empty: Slot = {};
};

const TracePhaseTimingSlot = TracePhaseTimingRoute.Slot;
const trace_phase_timing_slot_default = TracePhaseTimingRoute.empty;

pub const Error =
    core_errors.Error ||
    common.Error ||
    grid.Error ||
    convolution.Error ||
    InstrumentIntegration.Error ||
    error{
        ShapeMismatch,
        OutOfMemory,
    };

// layout(64-bit):
//   size: 280 B, align: 8 B
//   field storage:
//     273 B across 18 fields; largest: wavelengths=16 B, radiance=16 B, irradiance=16 B
//     padding: 7 B (56 bits)
//   unused bits: 56 padding + 0 bool-storage slack = 56 bits
//   out-of-line:
//     wavelength/product slices are always active
//     source_interfaces, rtm_quadrature_levels, and pseudo_spherical_* slices are rtm_config-gated
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
};

// instrumentation: trace phase timing -----------------------------------------------------------------------|
// captures: coarse product-simulation phase timings for trace-harness JSON summaries                         |
// why: keeps first-use and cached-run attribution available when very deep ztracy captures bury short zones. |
const EnabledTracePhaseTiming = struct {
    wavelength_sampling_ns: u64 = 0,
    forward_miss_collection_ns: u64 = 0,
    profile_spectroscopy_cache_ns: u64 = 0,
    forward_prefetch_ns: u64 = 0,
    radiance_cache_integration_ns: u64 = 0,
    radiance_convolution_ns: u64 = 0,
    radiance_postprocess_ns: u64 = 0,
    irradiance_sampling_ns: u64 = 0,
    irradiance_convolution_ns: u64 = 0,
    irradiance_postprocess_ns: u64 = 0,
    reflectance_assembly_ns: u64 = 0,
    jacobian_processing_ns: u64 = 0,
    labos: common.labos.PhaseTiming = .{},

    pub fn reset(self: *@This()) void {
        self.* = .{};
    }
};

const DisabledTracePhaseTiming = struct {
    pub inline fn reset(self: *@This()) void {
        _ = self;
    }
};

pub const TracePhaseTiming = if (trace_phase_timing_enabled) EnabledTracePhaseTiming else DisabledTracePhaseTiming;
// end instrumentation: trace phase timing -------------------------------------------------------------------|

pub fn configMayUseSourceInterfaces(scene: *const Scene, rtm_config: common.SolveConfig) bool {
    if (!rtm_config.rtm_controls.integrate_source_function) return false;
    return scene.atmosphere.interval_grid.semantics == .none;
}

pub fn configUsesRtmQuadrature(rtm_config: common.SolveConfig) bool {
    return rtm_config.rtm_controls.integrate_source_function;
}

pub fn configUsesPseudoSphericalGrid(rtm_config: common.SolveConfig) bool {
    return rtm_config.rtm_controls.use_spherical_correction;
}

// Reusable instrument grid storage that owns the backing storage.
// layout(64-bit):
//   size: 560 B normally; 568 B when trace phase timing is enabled, align: 8 B
//   field storage:
//     540 B across 26 normal fields; trace builds add trace_phase_timing=8 B
//     largest: forward_prefetch_pool=112 B, evaluation_cache=64 B
//     wavelength_sampling=48 B, forward_miss_plan=48 B; padding: 20 B (160 bits)
//   unused bits: 160 padding + 28 bool-storage slack = 188 bits in trace builds
//   out-of-line:
//     product/cache/result slices carry backing storage
//     source_interfaces, rtm_quadrature_levels, and pseudo_spherical_* storage are rtm_config-gated
//   cache span: 9 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 560 B (0.547 KiB) normally; 568 B (0.555 KiB) in trace builds
pub const ProductStorage = struct {
    wavelengths: []f64 = &.{},
    radiance: []f64 = &.{},
    irradiance: []f64 = &.{},
    reflectance: []f64 = &.{},
    scratch: []f64 = &.{},
    scratch_aux: []f64 = &.{},
    forward_results: []Types.ForwardIntegratedSample = &.{},
    layer_inputs: []common.LayerInput = &.{},
    source_interfaces: []common.SourceInterfaceInput = &.{},
    rtm_quadrature_levels: []common.RtmQuadratureLevel = &.{},
    pseudo_spherical_samples: []common.PseudoSphericalSample = &.{},
    pseudo_spherical_level_starts: []usize = &.{},
    pseudo_spherical_level_altitudes: []f64 = &.{},
    jacobian: []f64 = &.{},
    evaluation_cache: ?Cache.SpectralEvaluationCache = null,
    wavelength_sampling: Plan.OwnedWavelengthSampling = .{},
    forward_miss_plan: Plan.OwnedForwardMissPlan = .{},
    profile_spectroscopy_caches: []SpectroscopyState.ProfileNodeSpectroscopyCache = &.{},
    wavelength_plan_key: u64 = 0,
    wavelength_plan_valid: bool = false,
    forward_miss_plan_valid: bool = false,
    profile_spectroscopy_cache_key: u64 = 0,
    profile_spectroscopy_cache_valid: bool = false,
    shared_forward_prefetch_pool: ?*std.Thread.Pool = null,
    forward_prefetch_pool: std.Thread.Pool = undefined,
    forward_prefetch_pool_worker_threads: usize = 0,
    forward_prefetch_pool_valid: bool = false,
    trace_phase_timing: TracePhaseTimingSlot = trace_phase_timing_slot_default,

    pub fn deinit(self: *ProductStorage, allocator: Allocator) void {
        if (self.forward_prefetch_pool_valid) {
            self.forward_prefetch_pool.deinit();
        }
        freeBuffer(allocator, self.wavelengths);
        freeBuffer(allocator, self.radiance);
        freeBuffer(allocator, self.irradiance);
        freeBuffer(allocator, self.reflectance);
        freeBuffer(allocator, self.scratch);
        freeBuffer(allocator, self.scratch_aux);
        freeForwardResultBuffer(allocator, self.forward_results);
        freeLayerBuffer(allocator, self.layer_inputs);
        freeSourceInterfaceBuffer(allocator, self.source_interfaces);
        freeRtmQuadratureBuffer(allocator, self.rtm_quadrature_levels);
        freePseudoSphericalSampleBuffer(allocator, self.pseudo_spherical_samples);
        freeIndexBuffer(allocator, self.pseudo_spherical_level_starts);
        freeBuffer(allocator, self.pseudo_spherical_level_altitudes);
        freeBuffer(allocator, self.jacobian);
        if (self.evaluation_cache) |*cache| cache.deinit();
        self.wavelength_sampling.deinit(allocator);
        self.forward_miss_plan.deinit(allocator);
        allocator.free(self.profile_spectroscopy_caches);
        self.* = .{};
    }

    pub fn setTracePhaseTiming(self: *ProductStorage, timing: *TracePhaseTiming) void {
        if (comptime trace_phase_timing_enabled) {
            self.trace_phase_timing = timing;
        }
    }

    pub fn clearTracePhaseTiming(self: *ProductStorage) void {
        if (comptime trace_phase_timing_enabled) {
            self.trace_phase_timing = null;
        }
    }

    pub fn activeTracePhaseTiming(self: *ProductStorage) ?*TracePhaseTiming {
        if (comptime trace_phase_timing_enabled) {
            return self.trace_phase_timing;
        } else {
            return null;
        }
    }

    pub fn forwardPrefetchPool(
        self: *ProductStorage,
        allocator: Allocator,
        worker_count: usize,
    ) ?*std.Thread.Pool {
        if (worker_count <= 1) return null;
        if (self.shared_forward_prefetch_pool) |pool| return pool;

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

    pub fn invalidateWavelengthPlan(self: *ProductStorage, allocator: Allocator) void {
        self.wavelength_sampling.deinit(allocator);
        self.forward_miss_plan.deinit(allocator);
        allocator.free(self.profile_spectroscopy_caches);
        self.wavelength_sampling = .{};
        self.forward_miss_plan = .{};
        self.profile_spectroscopy_caches = &.{};
        self.wavelength_plan_key = 0;
        self.wavelength_plan_valid = false;
        self.forward_miss_plan_valid = false;
        self.profile_spectroscopy_cache_key = 0;
        self.profile_spectroscopy_cache_valid = false;
    }

    pub fn spectralCache(self: *ProductStorage, allocator: Allocator) Error!*Cache.SpectralEvaluationCache {
        if (self.evaluation_cache == null) {
            self.evaluation_cache = Cache.SpectralEvaluationCache.init(allocator);
        }
        self.evaluation_cache.?.reset();
        return &(self.evaluation_cache.?);
    }

    pub fn forwardResultBuffer(
        self: *ProductStorage,
        allocator: Allocator,
        capacity: usize,
    ) Error![]Types.ForwardIntegratedSample {

        // hot path:
        //   when: OE iterations reuse the same high-resolution miss plan
        //   work: retains the dense prefetch result staging array between batches
        //   reads: one ForwardIntegratedSample per unique forward-cache miss
        //   follow: spectral_eval.prefetchForwardSamples cache insertion
        try ensureForwardResultCapacity(allocator, &self.forward_results, capacity);
        return self.forward_results[0..capacity];
    }

    pub fn buffers(
        self: *ProductStorage,
        allocator: Allocator,
        scene: *const Scene,
        rtm_config: common.SolveConfig,
    ) Error!Buffers {
        const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
        const layer_count = transportLayerCountHint(scene, rtm_config);

        const needs_source_interfaces = configMayUseSourceInterfaces(scene, rtm_config);
        const needs_rtm_quadrature = configUsesRtmQuadrature(rtm_config);
        const needs_pseudo_spherical_grid = configUsesPseudoSphericalGrid(rtm_config);

        const pseudo_spherical_sample_count = if (needs_pseudo_spherical_grid)
            pseudoSphericalSampleCountHint(scene, rtm_config)
        else
            0;

        const active_jacobian_mask = if (rtm_config.derivative_mode != .none)
            jacobian.sanitizedMask(rtm_config.derivative_state_mask)
        else
            0;

        const active_jacobian_count = jacobian.activeStateCount(active_jacobian_mask);
        const wants_jacobian = active_jacobian_count != 0;

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
            try ensurePseudoSphericalSampleBufferCapacity(
                allocator,
                &self.pseudo_spherical_samples,
                pseudo_spherical_sample_count,
            );
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

        const source_interface_view: []common.SourceInterfaceInput = if (needs_source_interfaces)
            self.source_interfaces[0 .. layer_count + 1]
        else
            @constCast(&[_]common.SourceInterfaceInput{});
        const rtm_quadrature_view: []common.RtmQuadratureLevel = if (needs_rtm_quadrature)
            self.rtm_quadrature_levels[0 .. layer_count + 1]
        else
            @constCast(&[_]common.RtmQuadratureLevel{});

        var pseudo_spherical_samples_view: []common.PseudoSphericalSample =
            @constCast(&[_]common.PseudoSphericalSample{});
        var pseudo_spherical_starts_view: []usize = @constCast(&[_]usize{});
        var pseudo_spherical_altitudes_view: []f64 = @constCast(&[_]f64{});
        if (needs_pseudo_spherical_grid) {
            pseudo_spherical_samples_view = self.pseudo_spherical_samples[0..pseudo_spherical_sample_count];
            pseudo_spherical_starts_view = self.pseudo_spherical_level_starts[0 .. layer_count + 1];
            pseudo_spherical_altitudes_view = self.pseudo_spherical_level_altitudes[0 .. layer_count + 1];
        }

        const jacobian_view = if (wants_jacobian)
            self.jacobian[0 .. sample_count * active_jacobian_count]
        else
            null;

        return .{
            .wavelengths = self.wavelengths[0..sample_count],
            .radiance = self.radiance[0..sample_count],
            .irradiance = self.irradiance[0..sample_count],
            .reflectance = self.reflectance[0..sample_count],
            .scratch = self.scratch[0..sample_count],
            .scratch_aux = self.scratch_aux[0..sample_count],
            .layer_inputs = self.layer_inputs[0..layer_count],
            .source_interfaces = source_interface_view,
            .rtm_quadrature_levels = rtm_quadrature_view,
            .pseudo_spherical_samples = pseudo_spherical_samples_view,
            .pseudo_spherical_level_starts = pseudo_spherical_starts_view,
            .pseudo_spherical_level_altitudes = pseudo_spherical_altitudes_view,
            .jacobian = jacobian_view,
            .jacobian_state_mask = if (wants_jacobian) active_jacobian_mask else 0,
        };
    }
};

pub fn transportLayerCountHint(scene: *const Scene, rtm_config: common.SolveConfig) usize {
    _ = rtm_config;

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

pub fn pseudoSphericalSampleCountHint(scene: *const Scene, rtm_config: common.SolveConfig) usize {
    const layer_count = transportLayerCountHint(scene, rtm_config);
    return layer_count * (pseudoSphericalSubgridDivisions(scene) + 2);
}

pub fn resolvedTransportLayerCount(
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
) usize {
    _ = rtm_config;
    return prepared.transportLayerCount();
}

pub fn resolvedPseudoSphericalSampleCount(
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
) usize {
    if (prepared.intervalSemanticsUseReducedSharedRtmLayers() and
        prepared.shared_rtm_geometry.isValidFor(resolvedTransportLayerCount(rtm_config, prepared)))
    {
        var sample_count: usize = 0;
        for (prepared.shared_rtm_geometry.layers) |layer| {
            const support_count: usize = @intCast(layer.support_count);
            if (support_count > 2) sample_count += support_count - 2;
        }
        return sample_count;
    }
    return resolvedTransportLayerCount(rtm_config, prepared) * pseudoSphericalSubgridDivisions(scene);
}

fn pseudoSphericalSubgridDivisions(scene: *const Scene) usize {
    return @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
}

pub fn validateBuffers(
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    sample_count: usize,
    buffers: Buffers,
) Error!void {

    // The always-active summary buffers and the rtm_config-selected transport
    // carriers must stay shape-compatible for a single sweep.
    const summary_buffers_match =
        sample_count != 0 and
        buffers.wavelengths.len == sample_count and
        buffers.radiance.len == sample_count and
        buffers.irradiance.len == sample_count and
        buffers.reflectance.len == sample_count and
        buffers.scratch.len == sample_count and
        buffers.scratch_aux.len == sample_count and
        buffers.layer_inputs.len != 0;
    if (!summary_buffers_match) {
        return error.ShapeMismatch;
    }

    const source_interfaces_match =
        !configMayUseSourceInterfaces(scene, rtm_config) or
        buffers.source_interfaces.len == buffers.layer_inputs.len + 1;
    if (!source_interfaces_match) {
        return error.ShapeMismatch;
    }

    const rtm_quadrature_matches =
        !configUsesRtmQuadrature(rtm_config) or
        buffers.rtm_quadrature_levels.len == buffers.layer_inputs.len + 1;
    if (!rtm_quadrature_matches) {
        return error.ShapeMismatch;
    }

    const pseudo_spherical_grid_matches =
        !configUsesPseudoSphericalGrid(rtm_config) or
        (buffers.pseudo_spherical_samples.len != 0 and
            buffers.pseudo_spherical_level_starts.len == buffers.layer_inputs.len + 1 and
            buffers.pseudo_spherical_level_altitudes.len == buffers.layer_inputs.len + 1);
    if (!pseudo_spherical_grid_matches) {
        return error.ShapeMismatch;
    }

    if (buffers.jacobian) |values| {
        const active_jacobian_count = jacobian.activeStateCount(buffers.jacobian_state_mask);
        if (active_jacobian_count == 0 or
            values.len != sample_count * active_jacobian_count)
        {
            return error.ShapeMismatch;
        }
    } else if (buffers.jacobian_state_mask != 0) {
        return error.ShapeMismatch;
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

fn ensureForwardResultCapacity(
    allocator: Allocator,
    buffer: *[]Types.ForwardIntegratedSample,
    capacity: usize,
) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(Types.ForwardIntegratedSample, capacity);
    freeForwardResultBuffer(allocator, buffer.*);
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

fn freeForwardResultBuffer(allocator: Allocator, buffer: []Types.ForwardIntegratedSample) void {
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
