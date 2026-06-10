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

// storage.zig -----------------------------------------------------------------------------------------------------------|
// Reusable memory owner for instrument-grid simulations. ProductStorage is the retained workspace behind repeated        |
// measurement runs: it owns output arrays, transport scratch, wavelength plans, forward miss plans, profile caches,      |
// optional worker pools, and the borrowed views returned by instrument_grid/root.zig.                                    |
//                                                                                                                        |
// called by                                                                                                              |
//   instrument_grid/root.zig exposes ProductStorage as the public workspace handle. simulate.zig asks for trimmed        |
//   Buffers views at the start of each product run. spectral_forward.zig uses resolved sizing helpers for worker         |
//   scratch. optimal_estimation keeps ProductStorage warm across retrieval iterations.                                   |
//                                                                                                                        |
// route map                                                                                                              |
//   ProductStorage.buffers                  -> grow/reuse output, transport, pseudo-spherical, and Jacobian buffers      |
//   ProductStorage.spectralCache            -> reset the reusable irradiance cache for this product run                  |
//   ProductStorage.forwardResultBuffer      -> dense LABOS miss result staging for spectral_forward.zig                  |
//   ProductStorage.forwardPrefetchPool      -> reusable helper threads for repeated prefetch work                        |
//   ProductStorage.invalidateWavelengthPlan -> clear wavelength sampling, forward misses, and profile caches together    |
//   validateBuffers                         -> assert a coherent one-sweep borrowed Buffers view                         |
//                                                                                                                        |
// cache boundaries                                                                                                       |
//   wavelength_plan_key guards sampling and forward-miss plans. profile_spectroscopy_cache_key guards profile-node       |
//   spectroscopy state. invalidateWavelengthPlan drops both families because they are derived from the same scene,       |
//   prepared optical state, and instrument controls and must not drift independently.                                    |
//                                                                                                                        |
// ownership                                                                                                              |
//   ProductStorage owns backing slices and retained plans. Buffers is only a trimmed borrowed view for one run.          |
//   Feature-specific buffers are freed when disabled so stale source-interface, RTM-quadrature, pseudo-spherical,        |
//   or Jacobian data cannot survive into a route that should not read them.                                              |
// -----------------------------------------------------------------------------------------------------------------------|

// runtime boundary ------------------------------------------------------------------------------------------------------|
// Product storage owns buffers and retained plans. Thread-pool lifetime stays in spectral_forward.zig and simulate.zig,  |
// so storage does not become a scheduler or worker runtime wrapper.                                                      |
// -----------------------------------------------------------------------------------------------------------------------|

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

// Buffers ---------------------------------------------------------------------------------------------------------------|
// Trimmed borrowed buffer views for one simulation run. ProductStorage owns the referenced backing storage.              |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 216 B (0.211 KiB), align: 8 B                                                                                    |
//                                                                                                                        |
// memory                                                                                                                 |
// [  0.. 15] wavelengths                      : []f64                                                                    |
// [ 16.. 31] radiance                         : []f64                                                                    |
// [ 32.. 47] irradiance                       : []f64                                                                    |
// [ 48.. 63] reflectance                      : []f64                                                                    |
// [ 64.. 79] scratch                          : []f64                                                                    |
// [ 80.. 95] scratch_aux                      : []f64                                                                    |
// [ 96..111] layer_inputs                     : []common.LayerInput                                                      |
// [112..127] source_interfaces                : []common.SourceInterfaceInput                                            |
// [128..143] rtm_quadrature_levels            : []common.RtmQuadratureLevel                                              |
// [144..159] pseudo_spherical_samples         : []common.PseudoSphericalSample                                           |
// [160..175] pseudo_spherical_level_starts    : []usize                                                                  |
// [176..191] pseudo_spherical_level_altitudes : []f64                                                                    |
// [192..207] jacobian                         : ?[]f64                                                                   |
// [208..208] jacobian_state_mask              : jacobian.StateMask                                                       |
// [209..215] padding                          : 7 B                                                                      |
//                                                                                                                        |
// all slices reference ProductStorage backing storage and do not include it in the 216 B view size.                      |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                               |
// cache span: 4 cache lines at 64 B per line                                                                             |
// footprint: per instance = 216 B (0.211 KiB); total also includes referenced storage above                              |
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

// instrumentation: trace phase timing -----------------------------------------------------------------------------------|
// captures: coarse product-simulation phase timings for trace-harness JSON summaries                                     |
// why: keeps first-use and cached-run attribution available when very deep ztracy captures bury short zones.             |
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
        // EnabledTracePhaseTiming.reset ---------------------------------------------------------------------------------|
        // Clear all phase counters before a workspace-backed product run starts.                                         |
        // ---------------------------------------------------------------------------------------------------------------|

        self.* = .{};
    }
};

const DisabledTracePhaseTiming = struct {
    pub inline fn reset(self: *@This()) void {
        // DisabledTracePhaseTiming.reset --------------------------------------------------------------------------------|
        // Compile-time no-op used when trace phase timing is not built in.                                               |
        // ---------------------------------------------------------------------------------------------------------------|

        _ = self;
    }
};

pub const TracePhaseTiming = if (trace_phase_timing_enabled) EnabledTracePhaseTiming else DisabledTracePhaseTiming;
// end instrumentation: trace phase timing -------------------------------------------------------------------------------|

pub fn configMayUseSourceInterfaces(scene: *const Scene, rtm_config: common.SolveConfig) bool {
    // configMayUseSourceInterfaces --------------------------------------------------------------------------------------|
    // Source-interface buffers are only needed when integrated-source transport is requested and the scene               |
    // still uses the coarse non-interval atmosphere contract.                                                            |
    // -------------------------------------------------------------------------------------------------------------------|

    if (!rtm_config.rtm_controls.integrate_source_function) return false;
    return scene.atmosphere.interval_grid.semantics == .none;
}

pub fn configUsesRtmQuadrature(rtm_config: common.SolveConfig) bool {
    // configUsesRtmQuadrature -------------------------------------------------------------------------------------------|
    // RTM quadrature storage follows the integrated-source flag. Some runs may later fail to populate the                |
    // quadrature table, but the buffer must be available for that attempt.                                               |
    // -------------------------------------------------------------------------------------------------------------------|

    return rtm_config.rtm_controls.integrate_source_function;
}

pub fn configUsesPseudoSphericalGrid(rtm_config: common.SolveConfig) bool {
    // configUsesPseudoSphericalGrid -------------------------------------------------------------------------------------|
    // Pseudo-spherical support storage is only needed when geometric correction is enabled.                              |
    // -------------------------------------------------------------------------------------------------------------------|

    return rtm_config.rtm_controls.use_spherical_correction;
}

// ProductStorage --------------------------------------------------------------------------------------------------------|
// Reusable instrument-grid workspace that owns product buffers, retained wavelength plans, and the optional              |
// prefetch pool.                                                                                                         |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 552 B (0.539 KiB) normally; 560 B (0.547 KiB) with trace phase timing, align: 8 B                                |
//                                                                                                                        |
// memory, normal build                                                                                                   |
// [  0.. 63] evaluation_cache                  : ?Cache.SpectralEvaluationCache                                          |
// [ 64.. 71] shared_forward_prefetch_pool      : ?*std.Thread.Pool                                                       |
// [ 72.. 87] irradiance                        : []f64                                                                   |
// [ 88..103] reflectance                       : []f64                                                                   |
// [104..119] wavelengths                       : []f64                                                                   |
// [120..135] scratch_aux                       : []f64                                                                   |
// [136..151] forward_results                   : []Types.ForwardIntegratedSample                                         |
// [152..167] layer_inputs                      : []common.LayerInput                                                     |
// [168..183] source_interfaces                 : []common.SourceInterfaceInput                                           |
// [184..199] rtm_quadrature_levels             : []common.RtmQuadratureLevel                                             |
// [200..215] pseudo_spherical_samples          : []common.PseudoSphericalSample                                          |
// [216..231] pseudo_spherical_level_starts     : []usize                                                                 |
// [232..247] radiance                          : []f64                                                                   |
// [248..263] pseudo_spherical_level_altitudes  : []f64                                                                   |
// [264..279] scratch                           : []f64                                                                   |
// [280..327] wavelength_sampling               : Plan.OwnedWavelengthSampling                                            |
// [328..375] forward_miss_plan                 : Plan.OwnedForwardMissPlan                                               |
// [376..391] profile_spectroscopy_caches       : []SpectroscopyState.ProfileNodeSpectroscopyCache                        |
// [392..399] wavelength_plan_key               : u64                                                                     |
// [400..407] forward_prefetch_pool_worker_threads : usize                                                                |
// [408..519] forward_prefetch_pool             : std.Thread.Pool                                                         |
// [520..527] profile_spectroscopy_cache_key    : u64                                                                     |
// [528..543] jacobian                          : []f64                                                                   |
// [544..544] profile_spectroscopy_cache_valid  : bool                                                                    |
// [545..545] forward_miss_plan_valid           : bool                                                                    |
// [546..546] wavelength_plan_valid             : bool                                                                    |
// [547..547] forward_prefetch_pool_valid       : bool                                                                    |
// [548..551] padding                           : 4 B                                                                     |
//                                                                                                                        |
// trace phase timing build                                                                                               |
//   trace_phase_timing occupies [400..407], moving forward_prefetch_pool_worker_threads to [408..415],                   |
//   forward_prefetch_pool to [424..535], jacobian to [536..551], and the four bools to [552..555].                       |
//                                                                                                                        |
// slices, plans, caches, and the thread pool carry referenced storage not included in the struct size.                   |
// unused bits: 32 padding + 28 bool-storage slack = 60 bits                                                              |
// cache span: 9 cache lines at 64 B per line                                                                             |
// footprint: per instance = 552 B (0.539 KiB) normally; 560 B (0.547 KiB) with trace phase timing                        |
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
        // ProductStorage.deinit -----------------------------------------------------------------------------------------|
        // Release every buffer and retained plan owned by the workspace. Shared prefetch pools are borrowed              |
        // and are not deinitialized here.                                                                                |
        // ---------------------------------------------------------------------------------------------------------------|

        if (self.forward_prefetch_pool_valid) {
            self.forward_prefetch_pool.deinit();
        }
        freeTypedBuffer(f64, allocator, self.wavelengths);
        freeTypedBuffer(f64, allocator, self.radiance);
        freeTypedBuffer(f64, allocator, self.irradiance);
        freeTypedBuffer(f64, allocator, self.reflectance);
        freeTypedBuffer(f64, allocator, self.scratch);
        freeTypedBuffer(f64, allocator, self.scratch_aux);
        freeTypedBuffer(Types.ForwardIntegratedSample, allocator, self.forward_results);
        freeTypedBuffer(common.LayerInput, allocator, self.layer_inputs);
        freeTypedBuffer(common.SourceInterfaceInput, allocator, self.source_interfaces);
        freeTypedBuffer(common.RtmQuadratureLevel, allocator, self.rtm_quadrature_levels);
        freeTypedBuffer(common.PseudoSphericalSample, allocator, self.pseudo_spherical_samples);
        freeTypedBuffer(usize, allocator, self.pseudo_spherical_level_starts);
        freeTypedBuffer(f64, allocator, self.pseudo_spherical_level_altitudes);
        freeTypedBuffer(f64, allocator, self.jacobian);
        if (self.evaluation_cache) |*cache| cache.deinit();
        self.wavelength_sampling.deinit(allocator);
        self.forward_miss_plan.deinit(allocator);
        allocator.free(self.profile_spectroscopy_caches);
        self.* = .{};
    }

    pub fn setTracePhaseTiming(self: *ProductStorage, timing: *TracePhaseTiming) void {
        // ProductStorage.setTracePhaseTiming ----------------------------------------------------------------------------|
        // Attach an opt-in phase timing sink for the next workspace-backed simulation. Product builds compile            |
        // this to a no-op when trace phase timing is disabled.                                                           |
        // ---------------------------------------------------------------------------------------------------------------|

        if (comptime trace_phase_timing_enabled) {
            self.trace_phase_timing = timing;
        }
    }

    pub fn clearTracePhaseTiming(self: *ProductStorage) void {
        // ProductStorage.clearTracePhaseTiming --------------------------------------------------------------------------|
        // Detach the opt-in phase timing sink so normal product runs do not retain trace state.                          |
        // ---------------------------------------------------------------------------------------------------------------|

        if (comptime trace_phase_timing_enabled) {
            self.trace_phase_timing = null;
        }
    }

    pub fn activeTracePhaseTiming(self: *ProductStorage) ?*TracePhaseTiming {
        // ProductStorage.activeTracePhaseTiming -------------------------------------------------------------------------|
        // Return the currently attached phase timing sink, or null in normal builds and normal product runs.             |
        // ---------------------------------------------------------------------------------------------------------------|

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
        // ProductStorage.forwardPrefetchPool ----------------------------------------------------------------------------|
        // Return a reusable worker pool for LABOS prefetch when parallelism is useful. The pool stores                   |
        // worker_count - 1 helper threads because the caller uses the current thread as the final worker.                |
        //                                                                                                                |
        // fallback                                                                                                       |
        //   If pool initialization fails, return null so the caller can spawn direct threads or run chunks               |
        //   locally. The simulation result is unchanged; only scheduling changes.                                        |
        // ---------------------------------------------------------------------------------------------------------------|

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
        // ProductStorage.invalidateWavelengthPlan -----------------------------------------------------------------------|
        // Drop derived wavelength sampling, forward-miss, and profile spectroscopy caches together. These                |
        // caches are keyed from the same spectral/instrument/prepared state and must not drift independently.            |
        // ---------------------------------------------------------------------------------------------------------------|

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
        // ProductStorage.spectralCache ----------------------------------------------------------------------------------|
        // Return the reusable irradiance cache for this run. The cache keeps capacity but clears values so               |
        // a previous spectrum cannot affect the next spectrum.                                                           |
        // ---------------------------------------------------------------------------------------------------------------|

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
        // ProductStorage.forwardResultBuffer ----------------------------------------------------------------------------|
        // Return the dense staging array used for high-resolution LABOS miss results. Reusing this buffer                |
        // avoids repeated allocation across retrieval iterations with similar wavelength plans.                          |
        // ---------------------------------------------------------------------------------------------------------------|

        try ensureTypedBufferCapacity(Types.ForwardIntegratedSample, allocator, &self.forward_results, capacity);
        return self.forward_results[0..capacity];
    }

    pub fn buffers(
        self: *ProductStorage,
        allocator: Allocator,
        scene: *const Scene,
        rtm_config: common.SolveConfig,
    ) Error!Buffers {
        // ProductStorage.buffers ----------------------------------------------------------------------------------------|
        // Ensure all output and transport buffers are large enough for one simulation, then return trimmed               |
        // views for the active sample/layer counts.                                                                      |
        //                                                                                                                |
        // allocation rule                                                                                                |
        //   Buffers grow when needed and keep capacity across runs. Buffers for disabled RTM features are                |
        //   freed so stale source-interface, quadrature, or pseudo-spherical data cannot be reused.                      |
        //                                                                                                                |
        // Jacobian layout                                                                                                |
        //   Workspace Jacobians are state-major over active states only: [active_state][sample].                         |
        // ---------------------------------------------------------------------------------------------------------------|

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

        try ensureTypedBufferCapacity(f64, allocator, &self.wavelengths, sample_count);
        try ensureTypedBufferCapacity(f64, allocator, &self.radiance, sample_count);
        try ensureTypedBufferCapacity(f64, allocator, &self.irradiance, sample_count);
        try ensureTypedBufferCapacity(f64, allocator, &self.reflectance, sample_count);
        try ensureTypedBufferCapacity(f64, allocator, &self.scratch, sample_count);
        try ensureTypedBufferCapacity(f64, allocator, &self.scratch_aux, sample_count);

        try ensureTypedBufferCapacity(common.LayerInput, allocator, &self.layer_inputs, layer_count);
        if (needs_source_interfaces) {
            try ensureTypedBufferCapacity(
                common.SourceInterfaceInput,
                allocator,
                &self.source_interfaces,
                layer_count + 1,
            );
        } else {
            freeTypedBuffer(common.SourceInterfaceInput, allocator, self.source_interfaces);
            self.source_interfaces = &.{};
        }
        if (needs_rtm_quadrature) {
            try ensureTypedBufferCapacity(
                common.RtmQuadratureLevel,
                allocator,
                &self.rtm_quadrature_levels,
                layer_count + 1,
            );
        } else {
            freeTypedBuffer(common.RtmQuadratureLevel, allocator, self.rtm_quadrature_levels);
            self.rtm_quadrature_levels = &.{};
        }
        if (needs_pseudo_spherical_grid) {
            try ensureTypedBufferCapacity(
                common.PseudoSphericalSample,
                allocator,
                &self.pseudo_spherical_samples,
                pseudo_spherical_sample_count,
            );
            try ensureTypedBufferCapacity(usize, allocator, &self.pseudo_spherical_level_starts, layer_count + 1);
            try ensureTypedBufferCapacity(f64, allocator, &self.pseudo_spherical_level_altitudes, layer_count + 1);
        } else {
            freeTypedBuffer(common.PseudoSphericalSample, allocator, self.pseudo_spherical_samples);

            freeTypedBuffer(usize, allocator, self.pseudo_spherical_level_starts);
            freeTypedBuffer(f64, allocator, self.pseudo_spherical_level_altitudes);
            self.pseudo_spherical_samples = &.{};
            self.pseudo_spherical_level_starts = &.{};
            self.pseudo_spherical_level_altitudes = &.{};
        }
        if (wants_jacobian) {
            try ensureTypedBufferCapacity(f64, allocator, &self.jacobian, sample_count * active_jacobian_count);
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
    // transportLayerCountHint -------------------------------------------------------------------------------------------|
    // Estimate layer-buffer capacity before wavelength-specific preparation. Explicit interval grids use the             |
    // interval division contract; ordinary scenes use layer_count * sublayer_divisions.                                  |
    // -------------------------------------------------------------------------------------------------------------------|

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
    // pseudoSphericalSampleCountHint ------------------------------------------------------------------------------------|
    // Over-allocate enough pseudo-spherical support samples for the unresolved scene hint. The resolved path             |
    // below may use fewer samples once PreparedOpticalState has the exact RTM grid.                                      |
    // -------------------------------------------------------------------------------------------------------------------|

    const layer_count = transportLayerCountHint(scene, rtm_config);
    return layer_count * (pseudoSphericalSubgridDivisions(scene) + 2);
}

pub fn resolvedTransportLayerCount(
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
) usize {
    // resolvedTransportLayerCount ---------------------------------------------------------------------------------------|
    // Return the exact transport-layer count from PreparedOpticalState after interval/sublayer preparation.              |
    // -------------------------------------------------------------------------------------------------------------------|

    _ = rtm_config;
    return prepared.transportLayerCount();
}

pub fn resolvedPseudoSphericalSampleCount(
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
) usize {
    // resolvedPseudoSphericalSampleCount --------------------------------------------------------------------------------|
    // Return the exact pseudo-spherical support count for worker scratch buffers. Shared RTM geometry carries            |
    // explicit per-layer support counts; the fallback uses the subgrid count for every resolved layer.                   |
    // -------------------------------------------------------------------------------------------------------------------|

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
    // pseudoSphericalSubgridDivisions -----------------------------------------------------------------------------------|
    // Clamp the scene sublayer division count to at least one so support buffers are never sized to zero                 |
    // for a geometric-correction route.                                                                                  |
    // -------------------------------------------------------------------------------------------------------------------|

    return @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
}

pub fn validateBuffers(
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    sample_count: usize,
    buffers: Buffers,
) Error!void {
    // validateBuffers ---------------------------------------------------------------------------------------------------|
    // Check that a Buffers view is internally coherent for one spectral sweep and the requested RTM route.               |
    // This catches stale workspace slices before simulation writes into them.                                            |
    // -------------------------------------------------------------------------------------------------------------------|

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
    // ensureBufferCapacity ----------------------------------------------------------------------------------------------|
    // Public f64 helper retained for tests and callers that only own scalar scratch.                                     |
    // -------------------------------------------------------------------------------------------------------------------|

    try ensureTypedBufferCapacity(f64, allocator, buffer, capacity);
}

fn ensureTypedBufferCapacity(comptime T: type, allocator: Allocator, buffer: *[]T, capacity: usize) Error!void {
    // ensureTypedBufferCapacity -----------------------------------------------------------------------------------------|
    // Grow ProductStorage-owned buffers without preserving old values. Empty sentinels are not allocator-owned,          |
    // so the paired free helper skips zero-length slices.                                                                |
    // -------------------------------------------------------------------------------------------------------------------|

    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(T, capacity);
    freeTypedBuffer(T, allocator, buffer.*);
    buffer.* = replacement;
}

fn freeTypedBuffer(comptime T: type, allocator: Allocator, buffer: []T) void {
    // freeTypedBuffer ---------------------------------------------------------------------------------------------------|
    // Free one ProductStorage backing slice when it actually came from the allocator.                                    |
    // -------------------------------------------------------------------------------------------------------------------|

    if (buffer.len != 0) allocator.free(buffer);
}
