const std = @import("std");
const Scene = @import("../../../input/Scene.zig").Scene;
const OpticsPreparation = @import("../../optical_properties/root.zig");
const CarrierEval = @import("../../optical_properties/state_build/carrier_eval.zig");
const SpectroscopyState = @import("../../optical_properties/state_build/state_spectroscopy.zig");
const common = @import("../../radiative_transfer/root.zig");
const jacobian = @import("../../jacobian/root.zig");
const labos = common.labos;
const Trace = @import("../../instrumentation/trace.zig");
const ForwardInput = @import("forward_input.zig");
const Types = @import("types.zig");
const Storage = @import("storage.zig");
const Plan = @import("wavelength_plan.zig");
const solar_compat = @import("../../../input/reference_data/solar_irradiance.zig");
const work_partition = @import("../../work_partition.zig");
const Telemetry = @import("../../instrumentation/telemetry.zig");

const Allocator = std.mem.Allocator;
const Error = Storage.Error;

// spectral_forward.zig --------------------------------------------------------------------------------------------------|
// Computes the dense high-resolution forward-result array used by nominal radiance rows.                                 |
//                                                                                                                        |
// called by                                                                                                              |
//   spectral_eval.zig after wavelength_sampling.zig has deduplicated radiance integration wavelengths                    |
//                                                                                                                        |
// main paths                                                                                                             |
//   prefetchForwardSamples -> choose single-worker, spawned workers, or reusable thread-pool workers                     |
//   prefetchForwardWorkerMain -> worker-local ForwardSampleScratch loop over miss chunks                                 |
//   computeForwardSampleAtWavelengthWithScratch -> ForwardInput -> LABOS -> radiance-scaled result row                   |
//                                                                                                                        |
// hot path                                                                                                               |
//   Each miss is one high-resolution wavelength. Workers reuse layer, source-interface, RTM-quadrature,                  |
//   pseudo-spherical, carrier-cache, and LABOS workspace storage across many misses, then write results[index]           |
//   for misses[index]. Later gather loops read this dense array by integer index instead of hashing.                     |
//                                                                                                                        |
// math                                                                                                                   |
//   LABOS returns a top-of-atmosphere reflectance factor. radianceScaleFromForward multiplies by                         |
//   mu0 * solar_irradiance(lambda) / pi, and active Jacobians get the same fixed scale.                                  |
//                                                                                                                        |
// memory                                                                                                                 |
//   ForwardSampleScratch is worker-local mutable state. The caller owns the result slice; this file fills it and         |
//   records the first worker error without sharing transport buffers between workers.                                    |
// -----------------------------------------------------------------------------------------------------------------------|

// Re-exported through src/internal.zig so the worker-count threshold stays covered by unit tests.
pub const min_parallel_forward_miss_count: usize = 32;

pub const ForwardIntegratedSample = Types.ForwardIntegratedSample;

pub const ForwardCacheMiss = Plan.ForwardCacheMiss;
const forward_prefetch_chunk_size: usize = 8;

// Pooled workers handle reused OE/session runs. Smaller chunks trade a little
// more queue traffic for less tail imbalance across thousands of LABOS misses.
const forward_prefetch_pooled_chunk_size: usize = 8;

// migration note: Zig 0.15.2 prefetch runtime ---------------------------------------------------------------------------|
// Forward prefetch uses std.Thread.Pool while product builds remain pinned to Zig 0.15.2.                                |
// The abandoned 0.16 migration used std.Io.Threaded/Group here; keep retained timing independent of that.                |
// end migration note: Zig 0.15.2 prefetch runtime -----------------------------------------------------------------------|

const TracePrefetchRoute = if (Storage.trace_phase_timing_enabled) struct {
    const WorkerLabosTiming = ?*labos.PhaseTiming;
    const SingleLabosTiming = labos.PhaseTiming;
    const LabosTimingStorage = [work_partition.max_workers]labos.PhaseTiming;

    const worker_labos_timing_empty: WorkerLabosTiming = null;
    const single_labos_timing_empty: SingleLabosTiming = .{};
} else struct {
    const WorkerLabosTiming = void;
    const SingleLabosTiming = void;
    const LabosTimingStorage = void;

    const worker_labos_timing_empty: WorkerLabosTiming = {};
    const single_labos_timing_empty: SingleLabosTiming = {};
};

const TraceWorkerLabosTiming = TracePrefetchRoute.WorkerLabosTiming;
const TraceSingleLabosTiming = TracePrefetchRoute.SingleLabosTiming;
const TraceLabosTimingStorage = TracePrefetchRoute.LabosTimingStorage;

const trace_worker_labos_timing_default = TracePrefetchRoute.worker_labos_timing_empty;
const trace_single_labos_timing_default = TracePrefetchRoute.single_labos_timing_empty;
const trace_labos_timing_storage_default: TraceLabosTimingStorage = undefined;

// ForwardPrefetchRequest ------------------------------------------------------------------------------------------------|
// Borrowed batch inputs and output rows for high-resolution forward prefetch.                                            |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 160 B (0.156 KiB), align: 8 B                                                                                    |
//                                                                                                                        |
// memory                                                                                                                 |
// [  0..  7] scene                       : *const Scene                                                                  |
// [  8.. 87] rtm_config                  : common.SolveConfig                                                            |
// [ 88.. 95] prepared                    : *const OpticsPreparation.PreparedOpticalState                                 |
// [ 96..111] misses                      : []const ForwardCacheMiss                                                      |
// [112..127] profile_spectroscopy_caches : []const SpectroscopyState.ProfileNodeSpectroscopyCache                        |
// [128..143] results                     : []ForwardIntegratedSample                                                     |
// [144..151] thread_pool                 : ?*std.Thread.Pool                                                             |
// [152..159] trace_phase_timing          : ?*Storage.TracePhaseTiming                                                    |
//                                                                                                                        |
// out-of-line storage: scene, prepared, misses, profile caches, results, pool, and timing sink are borrowed.             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 3 cache lines at 64 B per line                                                                             |
// footprint: per instance = 160 B (0.156 KiB); total excludes borrowed batch rows and runtime handles                    |
pub const ForwardPrefetchRequest = struct {
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    misses: []const ForwardCacheMiss,
    profile_spectroscopy_caches: []const SpectroscopyState.ProfileNodeSpectroscopyCache,
    results: []ForwardIntegratedSample,
    thread_pool: ?*std.Thread.Pool,
    trace_phase_timing: ?*Storage.TracePhaseTiming,
};
// -----------------------------------------------------------------------------------------------------------------------|

// ForwardScratchRequirementsRequest -------------------------------------------------------------------------------------|
// Borrowed inputs used once per prefetch batch to size worker-local scratch buffers.                                     |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 24 B (0.023 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] scene      : *const Scene                                                                                     |
// [ 8..15] rtm_config : *const common.SolveConfig                                                                        |
// [16..23] prepared   : *const OpticsPreparation.PreparedOpticalState                                                    |
//                                                                                                                        |
// referenced storage: borrowed scene, solve config, and prepared optical state; no referenced storage is owned here.     |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 1 cache line at 64 B per line                                                                              |
// footprint: per instance = 24 B (0.023 KiB); no out-of-line storage                                                     |
const ForwardScratchRequirementsRequest = struct {
    scene: *const Scene,
    rtm_config: *const common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
};

// ForwardScratchRequirements --------------------------------------------------------------------------------------------|
// Plain counts used by ForwardSampleScratch.initInto. This row keeps scratch allocation separate from broad              |
// scene/prepared-state queries while preserving the same buffer sizes.                                                   |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 48 B (0.047 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] layer_count                    : usize                                                                        |
// [ 8..15] source_interface_count         : usize                                                                        |
// [16..23] rtm_quadrature_level_count     : usize                                                                        |
// [24..31] pseudo_spherical_sample_count  : usize                                                                        |
// [32..39] pseudo_spherical_level_count   : usize                                                                        |
// [40..47] support_cache_count            : usize                                                                        |
//                                                                                                                        |
// referenced storage: none; this is a stack value copied by value.                                                       |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 1 cache line at 64 B per line                                                                              |
// footprint: per instance = 48 B (0.047 KiB); no out-of-line storage                                                     |
const ForwardScratchRequirements = struct {
    layer_count: usize,
    source_interface_count: usize,
    rtm_quadrature_level_count: usize,
    pseudo_spherical_sample_count: usize,
    pseudo_spherical_level_count: usize,
    support_cache_count: usize,

    fn fromRequest(request: *const ForwardScratchRequirementsRequest) ForwardScratchRequirements {
        // ForwardScratchRequirements.fromRequest ------------------------------------------------------------------------|
        // Gather scratch sizes once for the batch before worker-local allocation starts.                                 |
        // ---------------------------------------------------------------------------------------------------------------|

        const scene = request.scene;
        const rtm_config = request.rtm_config.*;
        const prepared = request.prepared;
        const layer_count = Storage.resolvedTransportLayerCount(rtm_config, prepared);
        const uses_source_interfaces = Storage.configMayUseSourceInterfaces(scene, rtm_config);
        const uses_rtm_quadrature = Storage.configUsesRtmQuadrature(rtm_config);
        const uses_pseudo_spherical_grid = Storage.configUsesPseudoSphericalGrid(rtm_config);
        const support_cache_count = if (prepared.sublayers) |sublayers| sublayers.len else layer_count;

        var source_interface_count: usize = 0;
        if (uses_source_interfaces) {
            source_interface_count = layer_count + 1;
        }

        var rtm_quadrature_level_count: usize = 0;
        if (uses_rtm_quadrature) {
            rtm_quadrature_level_count = layer_count + 1;
        }

        var pseudo_spherical_sample_count: usize = 0;
        var pseudo_spherical_level_count: usize = 0;
        if (uses_pseudo_spherical_grid) {
            pseudo_spherical_sample_count = Storage.resolvedPseudoSphericalSampleCount(scene, rtm_config, prepared);
            pseudo_spherical_level_count = layer_count + 1;
        }

        return .{
            .layer_count = layer_count,
            .source_interface_count = source_interface_count,
            .rtm_quadrature_level_count = rtm_quadrature_level_count,
            .pseudo_spherical_sample_count = pseudo_spherical_sample_count,
            .pseudo_spherical_level_count = pseudo_spherical_level_count,
            .support_cache_count = support_cache_count,
        };
    }
};

fn emptyMutableSlice(comptime T: type) []T {
    // emptyMutableSlice -------------------------------------------------------------------------------------------------|
    // Return the shared zero-length slice used for optional scratch buffers that are not needed for this route.          |
    // -------------------------------------------------------------------------------------------------------------------|

    return @constCast(&[_]T{});
}

fn allocScratchSlice(comptime T: type, allocator: Allocator, count: usize) ![]T {
    // allocScratchSlice -------------------------------------------------------------------------------------------------|
    // Allocate a scratch slice only when the batch route needs rows of this type.                                        |
    // -------------------------------------------------------------------------------------------------------------------|

    if (count == 0) return emptyMutableSlice(T);
    return allocator.alloc(T, count);
}

fn freeScratchSlice(comptime T: type, allocator: Allocator, rows: []T) void {
    // freeScratchSlice --------------------------------------------------------------------------------------------------|
    // Release an optional scratch slice allocated by allocScratchSlice.                                                  |
    // -------------------------------------------------------------------------------------------------------------------|

    if (rows.len == 0) return;
    allocator.free(rows);
}

// ForwardScratchBuffers -------------------------------------------------------------------------------------------------|
// Worker-local transport buffers reused for every high-resolution forward miss assigned to one worker.                   |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 136 B (0.133 KiB), align: 8 B                                                                                    |
//                                                                                                                        |
// memory                                                                                                                 |
// [  0.. 15] layer_inputs                     : []common.LayerInput                                                      |
// [ 16.. 31] source_interfaces                : []common.SourceInterfaceInput                                            |
// [ 32.. 47] rtm_quadrature_levels            : []common.RtmQuadratureLevel                                              |
// [ 48.. 63] pseudo_spherical_samples         : []common.PseudoSphericalSample                                           |
// [ 64.. 79] pseudo_spherical_level_starts    : []usize                                                                  |
// [ 80.. 95] pseudo_spherical_level_altitudes : []f64                                                                    |
// [ 96..135] support_carrier_cache            : CarrierEval.SupportRowScalarCache                                        |
//                                                                                                                        |
// referenced storage: all slices and the support carrier cache are owned by this row and released together.              |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 3 cache lines at 64 B per line                                                                             |
// footprint: per worker = 136 B (0.133 KiB); total also includes referenced scratch arrays                               |
const ForwardScratchBuffers = struct {
    layer_inputs: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    support_carrier_cache: CarrierEval.SupportRowScalarCache,

    fn init(
        allocator: Allocator,
        requirements: ForwardScratchRequirements,
    ) !ForwardScratchBuffers {
        // ForwardScratchBuffers.init ------------------------------------------------------------------------------------|
        // Allocate the transport rows needed by a worker-local scratch bundle. Empty optional routes keep                |
        // zero-length shared slices, so deinit has one clear ownership table to release.                                 |
        // ---------------------------------------------------------------------------------------------------------------|

        const layer_inputs = try allocator.alloc(common.LayerInput, requirements.layer_count);
        errdefer allocator.free(layer_inputs);

        const source_interfaces = try allocScratchSlice(
            common.SourceInterfaceInput,
            allocator,
            requirements.source_interface_count,
        );
        errdefer freeScratchSlice(common.SourceInterfaceInput, allocator, source_interfaces);

        const rtm_quadrature_levels = try allocScratchSlice(
            common.RtmQuadratureLevel,
            allocator,
            requirements.rtm_quadrature_level_count,
        );
        errdefer freeScratchSlice(common.RtmQuadratureLevel, allocator, rtm_quadrature_levels);

        const pseudo_spherical_samples = try allocScratchSlice(
            common.PseudoSphericalSample,
            allocator,
            requirements.pseudo_spherical_sample_count,
        );
        errdefer freeScratchSlice(common.PseudoSphericalSample, allocator, pseudo_spherical_samples);

        const pseudo_spherical_level_starts = try allocScratchSlice(
            usize,
            allocator,
            requirements.pseudo_spherical_level_count,
        );
        errdefer freeScratchSlice(usize, allocator, pseudo_spherical_level_starts);

        const pseudo_spherical_level_altitudes = try allocScratchSlice(
            f64,
            allocator,
            requirements.pseudo_spherical_level_count,
        );
        errdefer freeScratchSlice(f64, allocator, pseudo_spherical_level_altitudes);

        var support_carrier_cache = try CarrierEval.SupportRowScalarCache.init(
            allocator,
            requirements.support_cache_count,
        );
        errdefer support_carrier_cache.deinit(allocator);

        return .{
            .layer_inputs = layer_inputs,
            .source_interfaces = source_interfaces,
            .rtm_quadrature_levels = rtm_quadrature_levels,
            .pseudo_spherical_samples = pseudo_spherical_samples,
            .pseudo_spherical_level_starts = pseudo_spherical_level_starts,
            .pseudo_spherical_level_altitudes = pseudo_spherical_level_altitudes,
            .support_carrier_cache = support_carrier_cache,
        };
    }

    fn deinit(self: *ForwardScratchBuffers, allocator: Allocator) void {
        // ForwardScratchBuffers.deinit ----------------------------------------------------------------------------------|
        // Release every transport scratch allocation owned by this worker.                                               |
        // ---------------------------------------------------------------------------------------------------------------|

        allocator.free(self.layer_inputs);
        freeScratchSlice(common.SourceInterfaceInput, allocator, self.source_interfaces);
        freeScratchSlice(common.RtmQuadratureLevel, allocator, self.rtm_quadrature_levels);
        freeScratchSlice(common.PseudoSphericalSample, allocator, self.pseudo_spherical_samples);
        freeScratchSlice(usize, allocator, self.pseudo_spherical_level_starts);
        freeScratchSlice(f64, allocator, self.pseudo_spherical_level_altitudes);
        self.support_carrier_cache.deinit(allocator);
        self.* = undefined;
    }

    fn forwardInputScratch(
        self: *ForwardScratchBuffers,
        profile_spectroscopy_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
    ) ForwardInput.ForwardInputScratch {
        // ForwardScratchBuffers.forwardInputScratch ---------------------------------------------------------------------|
        // Return the borrowed buffer view needed by forward_input.zig. The worker keeps owning all backing               |
        // arrays; this view only names the subset refreshed for one wavelength.                                          |
        // ---------------------------------------------------------------------------------------------------------------|

        return .{
            .layer_inputs = self.layer_inputs,
            .source_interfaces = self.source_interfaces,
            .rtm_quadrature_levels = self.rtm_quadrature_levels,
            .pseudo_spherical_samples = self.pseudo_spherical_samples,
            .pseudo_spherical_level_starts = self.pseudo_spherical_level_starts,
            .pseudo_spherical_level_altitudes = self.pseudo_spherical_level_altitudes,
            .support_carrier_cache = &self.support_carrier_cache,
            .profile_spectroscopy_cache = profile_spectroscopy_cache,
        };
    }
};
// -----------------------------------------------------------------------------------------------------------------------|

// ForwardSampleScratch --------------------------------------------------------------------------------------------------|
// Worker-local scratch storage for repeated high-resolution forward misses.                                              |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 3304 B (3.227 KiB) normally; 3320 B (3.242 KiB) with trace phase timing, align: 8 B                              |
//                                                                                                                        |
// memory                                                                                                                 |
// [   0.. 135] buffers                          : ForwardScratchBuffers                                                  |
// [ 136..3303] labos_workspace                  : labos.Workspace                                                        |
//                                                                                                                        |
// trace phase timing build                                                                                               |
//   labos_workspace grows to [136..3319] because LABOS retains a trace-phase timing pointer.                             |
//                                                                                                                        |
// slice fields carry out-of-line transport buffers not included in the struct size.                                      |
//                                                                                                                        |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 52 cache lines at 64 B per line                                                                            |
// footprint: per instance = 3304 B (3.227 KiB) normally; 3320 B (3.242 KiB) with trace phase timing                      |
const ForwardSampleScratch = struct {
    buffers: ForwardScratchBuffers,
    labos_workspace: labos.Workspace,

    fn initInto(
        self: *ForwardSampleScratch,
        allocator: Allocator,
        requirements: ForwardScratchRequirements,
    ) !void {
        // ForwardSampleScratch.initInto ---------------------------------------------------------------------------------|
        // Allocate worker-local scratch buffers from precomputed batch requirements.                                     |
        //                                                                                                                |
        // why                                                                                                            |
        //   A worker computes many misses. Reusing these buffers avoids per-miss allocation and keeps LABOS              |
        //   workspace state private to the worker.                                                                       |
        // ---------------------------------------------------------------------------------------------------------------|

        const buffers = try ForwardScratchBuffers.init(allocator, requirements);

        self.* = .{
            .buffers = buffers,
            .labos_workspace = labos.Workspace.init(allocator),
        };
    }

    fn deinit(self: *ForwardSampleScratch, allocator: Allocator) void {
        // ForwardSampleScratch.deinit -----------------------------------------------------------------------------------|
        // Release every worker-local scratch buffer and the nested LABOS workspace.                                      |
        // ---------------------------------------------------------------------------------------------------------------|

        self.labos_workspace.deinit();
        self.buffers.deinit(allocator);
        self.* = undefined;
    }

    fn forwardInputScratch(
        self: *ForwardSampleScratch,
        profile_spectroscopy_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
    ) ForwardInput.ForwardInputScratch {
        // ForwardSampleScratch.forwardInputScratch ----------------------------------------------------------------------|
        // Return the borrowed buffer view owned by ForwardScratchBuffers.                                                |
        // ---------------------------------------------------------------------------------------------------------------|

        return self.buffers.forwardInputScratch(profile_spectroscopy_cache);
    }
};

// ForwardPrefetchErrorState ---------------------------------------------------------------------------------------------|
// Shared first-error slot for parallel forward-prefetch workers.                                                         |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 24 B (0.023 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0..15] mutex   : std.Thread.Mutex                                                                                    |
// [16..17] err     : ?Error                                                                                              |
// [18..23] padding : 6 B                                                                                                 |
//                                                                                                                        |
// unused bits: 48 padding + 0 bool-storage slack = 48 bits                                                               |
// footprint: per instance = 24 B (0.023 KiB); total = per instance * live instance count                                 |
const ForwardPrefetchErrorState = struct {
    mutex: std.Thread.Mutex = .{},
    err: ?Error = null,

    fn store(self: *ForwardPrefetchErrorState, err: Error) void {
        // ForwardPrefetchErrorState.store -------------------------------------------------------------------------------|
        // Record the first worker error. A mutex is enough here because workers only write on failure.                   |
        // ---------------------------------------------------------------------------------------------------------------|

        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.err == null) self.err = err;
    }
};

// ForwardPrefetchWorker -------------------------------------------------------------------------------------------------|
// Worker context for high-resolution LABOS prefetch.                                                                     |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 192 B (0.188 KiB) normally; 288 B (0.281 KiB) in telemetry CLI builds, align: 8 B                                |
//                                                                                                                        |
// memory, normal build                                                                                                   |
// [  0..  7] scene                        : *const Scene                                                                 |
// [  8.. 87] rtm_config                   : common.SolveConfig                                                           |
// [ 88.. 95] prepared                     : *const OpticsPreparation.PreparedOpticalState                                |
// [ 96..103] scratch_requirements         : *const ForwardScratchRequirements                                            |
// [104..119] misses                       : []const ForwardCacheMiss                                                     |
// [120..135] profile_spectroscopy_caches  : []const SpectroscopyState.ProfileNodeSpectroscopyCache                       |
// [136..151] results                      : []ForwardIntegratedSample                                                    |
// [152..159] error_state                  : *ForwardPrefetchErrorState                                                   |
// [160..167] start_index                  : usize                                                                        |
// [168..175] end_index                    : usize                                                                        |
// [176..183] queue                        : ?*work_partition.ChunkQueue                                                  |
// [184..191] worker_index                 : usize                                                                        |
//                                                                                                                        |
// telemetry CLI build                                                                                                    |
//   telemetry_context occupies [192..287], moving zero-size labos_phase_timing to offset 288.                            |
//                                                                                                                        |
// trace phase timing build                                                                                               |
//   labos_phase_timing follows the normal fields when trace phase timing is enabled.                                     |
//                                                                                                                        |
// pointers and slices reference external storage not included in the struct size.                                        |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 3 cache lines at 64 B per line                                                                             |
// footprint: per instance = 192 B (0.188 KiB) normally; 288 B (0.281 KiB) in telemetry CLI builds                        |
// telemetry                                                                                                              |
//   validation telemetry builds use telemetry_context for row attribution.                                               |
const ForwardPrefetchWorker = struct {
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    scratch_requirements: *const ForwardScratchRequirements,
    misses: []const ForwardCacheMiss,
    profile_spectroscopy_caches: []const SpectroscopyState.ProfileNodeSpectroscopyCache,
    results: []ForwardIntegratedSample,
    error_state: *ForwardPrefetchErrorState,
    start_index: usize,
    end_index: usize,
    queue: ?*work_partition.ChunkQueue = null,
    worker_index: usize = 0,
    telemetry_context: Telemetry.Context,
    labos_phase_timing: TraceWorkerLabosTiming = trace_worker_labos_timing_default,
};

inline fn initializeTraceLabosTimingStorage(
    trace_phase_timing: ?*Storage.TracePhaseTiming,
    worker_count: usize,
    storage: *TraceLabosTimingStorage,
) void {
    // initializeTraceLabosTimingStorage ---------------------------------------------------------------------------------|
    // Clear per-worker LABOS timing slots when the opt-in phase timing route is active.                                  |
    // -------------------------------------------------------------------------------------------------------------------|

    if (comptime Storage.trace_phase_timing_enabled) {
        if (trace_phase_timing != null) {
            for (storage[0..worker_count]) |*timing| timing.* = .{};
        }
    }
}

inline fn attachSingleTraceLabosTiming(
    trace_phase_timing: ?*Storage.TracePhaseTiming,
    scratch: *ForwardSampleScratch,
    timing: *TraceSingleLabosTiming,
) void {
    // attachSingleTraceLabosTiming --------------------------------------------------------------------------------------|
    // Attach LABOS phase timing for the single-worker route so it reports through the same aggregate fields              |
    // as the parallel route.                                                                                             |
    // -------------------------------------------------------------------------------------------------------------------|

    if (comptime Storage.trace_phase_timing_enabled) {
        _ = trace_phase_timing orelse return;
        scratch.labos_workspace.setTracePhaseTiming(timing);
    }
}

inline fn clearTraceLabosTiming(scratch: *ForwardSampleScratch) void {
    // clearTraceLabosTiming ---------------------------------------------------------------------------------------------|
    // Detach any opt-in LABOS timing sink before worker scratch is reused or destroyed.                                  |
    // -------------------------------------------------------------------------------------------------------------------|

    if (comptime Storage.trace_phase_timing_enabled) {
        scratch.labos_workspace.clearTracePhaseTiming();
    }
}

inline fn traceWorkerLabosTiming(
    trace_phase_timing: ?*Storage.TracePhaseTiming,
    storage: *TraceLabosTimingStorage,
    worker_index: usize,
) TraceWorkerLabosTiming {
    // traceWorkerLabosTiming --------------------------------------------------------------------------------------------|
    // Return the per-worker LABOS timing slot when phase timing is active; otherwise return the zero-cost                |
    // disabled representation.                                                                                           |
    // -------------------------------------------------------------------------------------------------------------------|

    if (comptime Storage.trace_phase_timing_enabled) {
        if (trace_phase_timing != null) return &storage[worker_index];

        return null;
    } else {
        return {};
    }
}

fn radianceScaleFromForward(
    scene: *const Scene,
    wavelength_nm: f64,
) f64 {
    // radianceScaleFromForward ------------------------------------------------------------------------------------------|
    // Convert top-of-atmosphere reflectance factor into radiance scaling for the built-in O2 A surface path.             |
    //                                                                                                                    |
    // math                                                                                                               |
    //   reflectance_factor = pi * L / (mu0 * E0)                                                                         |
    //   therefore L        = reflectance_factor * mu0 * E0 / pi                                                          |
    //   scale(lambda)     = mu0 * E0(lambda) / pi                                                                        |
    //                                                                                                                    |
    // symbols                                                                                                            |
    //   L  : radiance                                                                                                    |
    //   E0 : solar irradiance                                                                                            |
    //   mu0: solar zenith cosine at the surface                                                                          |
    // -------------------------------------------------------------------------------------------------------------------|

    const solar_irradiance = solar_compat.irradianceAtWavelength(scene, wavelength_nm);
    const solar_cosine = scene.geometry.solarCosineAtAltitude(0.0);

    return solar_cosine * solar_irradiance / std.math.pi;
}

fn integratedSampleFromForward(
    request: ForwardInput.ForwardSampleRequest,
    forward: common.ForwardResult,
) ForwardIntegratedSample {
    // integratedSampleFromForward ---------------------------------------------------------------------------------------|
    // Pack one LABOS reflectance result into the dense forward-result row consumed by radiance integration.              |
    //                                                                                                                    |
    // math                                                                                                               |
    //   L(lambda)   = reflectance_factor(lambda) * scale(lambda)                                                         |
    //   dL/dx       = scale(lambda) * d(reflectance_factor)/dx for active retrieval states                               |
    //                                                                                                                    |
    // why no d(scale)/dx term                                                                                            |
    //   The Jacobian states handled here change the RTM reflectance. The solar irradiance and geometry scale             |
    //   are fixed for that state vector, so the product rule reduces to scale * d(reflectance_factor)/dx.                |
    // -------------------------------------------------------------------------------------------------------------------|

    const scale = radianceScaleFromForward(request.scene, request.wavelength_nm);
    var radiance_jacobian = jacobian.zero();
    if (forward.jacobian) |reflectance_jacobian| {
        radiance_jacobian = jacobian.scaleMasked(
            reflectance_jacobian,
            scale,
            request.rtm_config.derivative_state_mask,
        );
    }

    return .{
        .radiance = forward.toa_reflectance_factor * scale,
        .jacobian = radiance_jacobian,
    };
}

fn computeForwardSampleAtWavelengthWithScratch(
    allocator: Allocator,
    request: ForwardInput.ForwardSampleRequest,
    scratch: ForwardInput.ForwardInputScratch,
    labos_workspace: *labos.Workspace,
) Error!ForwardIntegratedSample {
    // computeForwardSampleAtWavelengthWithScratch -----------------------------------------------------------------------|
    // Compute one high-resolution forward miss. Request names the fixed sample inputs; scratch names the                 |
    // caller-owned buffers reused inside worker loops without allocating transport arrays.                               |
    //                                                                                                                    |
    // steps                                                                                                              |
    //   1. build wavelength-specific ForwardInput from carrier caches                                                    |
    //   2. execute LABOS with the worker-local workspace                                                                 |
    //   3. scale reflectance and active Jacobians into radiance units                                                    |
    //                                                                                                                    |
    // math                                                                                                               |
    //   lambda -> optical layers(lambda) -> LABOS reflectance_factor(lambda) -> L(lambda)                                |
    // -------------------------------------------------------------------------------------------------------------------|

    // instrumentation: trace zone: forward sample ---------------------------------------------------------------------- |
    // captures: one high-resolution forward-sample solve                                                                 |
    // why: separates per-miss optical input setup and LABOS execution from nominal-grid assembly.                        |
    const sample_zone = Trace.deepStaticZone(@src(), "forward_sample");
    defer sample_zone.end();
    // end instrumentation: trace zone: forward sample ------------------------------------------------------------------ |

    // instrumentation: trace counter: forward sample count ------------------------------------------------------------- |
    // captures: number of high-resolution forward samples evaluated                                                      |
    // why: normalizes prefetch wall time by actual LABOS solve count.                                                    |
    Trace.plotU("forward_samples", 1);
    // end instrumentation: trace counter: forward sample count --------------------------------------------------------- |

    const input = input: {

        // instrumentation: trace zone: configured forward input -------------------------------------------------------- |
        // captures: wavelength-specific forward-input construction                                                       |
        // why: shows carrier/layer preparation cost before transport.                                                    |
        const zone = Trace.deepStaticZone(@src(), "forward_sample.configured_forward_input");
        defer zone.end();
        // end instrumentation: trace zone: configured forward input ---------------------------------------------------- |

        break :input try ForwardInput.configuredForwardInput(
            request,
            scratch,
        );
    };
    var effective_config = request.rtm_config;
    effective_config.rtm_controls = input.rtm_controls;
    const forward = forward: {

        // instrumentation: trace zone: LABOS execute ------------------------------------------------------------------- |
        // captures: LABOS transport execution for one forward sample                                                     |
        // why: keeps the radiative-transfer solve separate from surrounding input and scaling work.                      |
        const zone = Trace.deepStaticZone(@src(), "forward_sample.labos_execute");
        defer zone.end();
        // end instrumentation: trace zone: LABOS execute --------------------------------------------------------------- |

        break :forward try common.executePreparedWithLabosWorkspace(
            allocator,
            effective_config,
            input,
            labos_workspace,
        );
    };
    return integratedSampleFromForward(request, forward);
}

fn prefetchForwardWorkerMain(worker: *ForwardPrefetchWorker) void {
    // prefetchForwardWorkerMain -----------------------------------------------------------------------------------------|
    // Worker loop for forward misses. Each worker owns one scratch bundle and repeatedly fills result slots              |
    // for either a static range or chunks from a shared queue.                                                           |
    // -------------------------------------------------------------------------------------------------------------------|

    var thread_name_buffer: [64]u8 = undefined;
    const thread_name = std.fmt.bufPrintZ(
        &thread_name_buffer,
        "zdisamar-forward-{d}",
        .{worker.worker_index},
    ) catch "zdisamar-forward-worker";

    // instrumentation: trace thread label: forward prefetch worker ----------------------------------------------------- |
    // captures: forward-prefetch worker identity                                                                         |
    // why: makes parallel miss batches separable in timeline traces.                                                     |
    Trace.setThreadName(thread_name);
    // end instrumentation: trace thread label: forward prefetch worker ------------------------------------------------- |

    // instrumentation: trace zone: forward prefetch worker ------------------------------------------------------------- |
    // captures: forward-prefetch worker wall time                                                                        |
    // why: exposes load balance across high-resolution miss chunks.                                                      |
    const worker_zone = Trace.staticZone(@src(), "forward_prefetch.worker");
    worker_zone.value(@intCast(worker.worker_index));
    defer worker_zone.end();
    // end instrumentation: trace zone: forward prefetch worker --------------------------------------------------------- |

    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var scratch: ForwardSampleScratch = undefined;
    scratch.initInto(allocator, worker.scratch_requirements.*) catch |err| {
        worker.error_state.store(err);
        return;
    };
    if (comptime Storage.trace_phase_timing_enabled) {
        if (worker.labos_phase_timing) |timing| {
            scratch.labos_workspace.setTracePhaseTiming(timing);
        }
    }
    defer clearTraceLabosTiming(&scratch);
    defer scratch.deinit(allocator);

    while (nextForwardPrefetchChunk(worker)) |chunk| {
        {

            // instrumentation: trace zone: forward prefetch chunk ------------------------------------------------------ |
            // captures: one prefetch chunk size and wall time                                                            |
            // why: reveals tail imbalance and chunking overhead in parallel forward solves.                              |
            const chunk_zone = Trace.deepStaticZone(@src(), "forward_prefetch.chunk");
            chunk_zone.value(@intCast(chunk.end - chunk.start));
            defer chunk_zone.end();
            // end instrumentation: trace zone: forward prefetch chunk -------------------------------------------------- |

            for (chunk.start..chunk.end) |index| {
                const miss = worker.misses[index];
                const profile_spectroscopy_cache = if (worker.profile_spectroscopy_caches.len == worker.misses.len)
                    &worker.profile_spectroscopy_caches[index]
                else
                    null;

                worker.results[index] = compute_sample: {
                    const previous_context = Telemetry.currentContext();
                    Telemetry.setContext(telemetrySampleContext(
                        worker.telemetry_context,
                        index + 1,
                        miss.wavelength_nm,
                    ));
                    defer Telemetry.setContext(previous_context);
                    const request = ForwardInput.ForwardSampleRequest{
                        .scene = worker.scene,
                        .rtm_config = worker.rtm_config,
                        .prepared = worker.prepared,
                        .wavelength_nm = miss.wavelength_nm,
                    };
                    break :compute_sample computeForwardSampleAtWavelengthWithScratch(
                        allocator,
                        request,
                        scratch.forwardInputScratch(profile_spectroscopy_cache),
                        &scratch.labos_workspace,
                    ) catch |err| {
                        worker.error_state.store(err);
                        return;
                    };
                };
            }
        }
    }
}

fn nextForwardPrefetchChunk(worker: *ForwardPrefetchWorker) ?work_partition.Range {
    // nextForwardPrefetchChunk ------------------------------------------------------------------------------------------|
    // Return the next miss range for a worker. Pooled workers share a queue for better load balance; direct              |
    // spawned workers use their static range.                                                                            |
    // -------------------------------------------------------------------------------------------------------------------|

    if (worker.queue) |queue| return queue.next();
    if (worker.start_index >= worker.end_index) return null;
    const chunk = work_partition.Range{
        .start = worker.start_index,
        .end = @min(worker.start_index + forward_prefetch_chunk_size, worker.end_index),
    };

    worker.start_index = chunk.end;
    return chunk;
}

pub fn prefetchForwardSamples(
    allocator: Allocator,
    request: *const ForwardPrefetchRequest,
) Error!void {
    // prefetchForwardSamples --------------------------------------------------------------------------------------------|
    // Schedule all high-resolution forward misses across the selected worker route. Single-worker runs avoid             |
    // thread setup; larger batches use static ranges or a reusable queue-backed pool.                                    |
    //                                                                                                                    |
    // output                                                                                                             |
    //   results[index] is filled from misses[index]. Any worker failure records the first error and stops the            |
    //   batch after joined workers return.                                                                               |
    // -------------------------------------------------------------------------------------------------------------------|

    if (request.misses.len == 0) return;
    if (request.results.len != request.misses.len) return error.ShapeMismatch;
    const preferred_worker_count = preferredForwardWorkerCount(request.misses.len);
    const worker_count = preferred_worker_count;

    // instrumentation: trace counter: forward worker count ------------------------------------------------------------- |
    // captures: selected forward worker count                                                                            |
    // why: ties prefetch timing to the concurrency shape chosen for this miss batch.                                     |
    Trace.plotU("forward_worker_count", @intCast(worker_count));
    // end instrumentation: trace counter: forward worker count --------------------------------------------------------- |

    // instrumentation: trace counter: high-resolution misses ----------------------------------------------------------- |
    // captures: unique high-resolution cache misses                                                                      |
    // why: distinguishes fewer computations from cheaper computation per miss.                                           |
    Trace.plotU("high_resolution_misses", @intCast(request.misses.len));
    // end instrumentation: trace counter: high-resolution misses ------------------------------------------------------- |

    const telemetry_context = Telemetry.currentContext();
    const scratch_requirements_request = ForwardScratchRequirementsRequest{
        .scene = request.scene,
        .rtm_config = &request.rtm_config,
        .prepared = request.prepared,
    };
    const scratch_requirements = ForwardScratchRequirements.fromRequest(&scratch_requirements_request);

    if (worker_count == 1) {
        var labos_phase_timing: TraceSingleLabosTiming = trace_single_labos_timing_default;
        var scratch: ForwardSampleScratch = undefined;
        try scratch.initInto(allocator, scratch_requirements);

        attachSingleTraceLabosTiming(request.trace_phase_timing, &scratch, &labos_phase_timing);
        defer clearTraceLabosTiming(&scratch);
        defer scratch.deinit(allocator);

        for (request.misses, request.results, 0..) |miss, *result, miss_index| {
            const profile_spectroscopy_cache = if (request.profile_spectroscopy_caches.len == request.misses.len)
                &request.profile_spectroscopy_caches[miss_index]
            else
                null;

            result.* = result_value: {
                const previous_context = Telemetry.currentContext();
                Telemetry.setContext(telemetrySampleContext(
                    telemetry_context,
                    miss_index + 1,
                    miss.wavelength_nm,
                ));
                defer Telemetry.setContext(previous_context);
                const sample_request = ForwardInput.ForwardSampleRequest{
                    .scene = request.scene,
                    .rtm_config = request.rtm_config,
                    .prepared = request.prepared,
                    .wavelength_nm = miss.wavelength_nm,
                };
                break :result_value try computeForwardSampleAtWavelengthWithScratch(
                    allocator,
                    sample_request,
                    scratch.forwardInputScratch(profile_spectroscopy_cache),
                    &scratch.labos_workspace,
                );
            };
        }
        if (comptime Storage.trace_phase_timing_enabled) {
            mergeLabosPhaseTiming(request.trace_phase_timing, &.{labos_phase_timing});
        }
        return;
    }

    std.debug.assert(worker_count <= work_partition.max_workers);
    var error_state = ForwardPrefetchErrorState{};
    var labos_phase_timing_storage: TraceLabosTimingStorage = trace_labos_timing_storage_default;
    initializeTraceLabosTimingStorage(request.trace_phase_timing, worker_count, &labos_phase_timing_storage);

    var worker_storage: [work_partition.max_workers]ForwardPrefetchWorker = undefined;
    const workers = worker_storage[0..worker_count];

    for (0..worker_count) |worker_index| {
        const range = work_partition.staticRange(request.misses.len, worker_count, worker_index);
        workers[worker_index] = .{
            .scene = request.scene,
            .rtm_config = request.rtm_config,
            .prepared = request.prepared,
            .scratch_requirements = &scratch_requirements,
            .misses = request.misses,
            .profile_spectroscopy_caches = request.profile_spectroscopy_caches,
            .results = request.results,
            .error_state = &error_state,
            .start_index = range.start,
            .end_index = range.end,
            .worker_index = worker_index,
            .telemetry_context = telemetry_context,
            .labos_phase_timing = traceWorkerLabosTiming(
                request.trace_phase_timing,
                &labos_phase_timing_storage,
                worker_index,
            ),
        };
    }

    if (request.thread_pool) |pool| {
        var queue = work_partition.ChunkQueue.init(request.misses.len, forward_prefetch_pooled_chunk_size);
        for (workers) |*worker| worker.queue = &queue;
        var wait_group = std.Thread.WaitGroup{};

        for (0..worker_count - 1) |worker_index| {
            pool.spawnWg(&wait_group, prefetchForwardWorkerMain, .{&workers[worker_index]});
        }
        prefetchForwardWorkerMain(&workers[worker_count - 1]);

        wait_group.wait();
        if (comptime Storage.trace_phase_timing_enabled) {
            mergeLabosPhaseTiming(request.trace_phase_timing, labos_phase_timing_storage[0..worker_count]);
        }
        if (error_state.err) |err| return err;
        return;
    }

    var thread_storage: [work_partition.max_workers - 1]std.Thread = undefined;
    const threads = thread_storage[0 .. worker_count - 1];
    var started_thread_count: usize = 0;
    for (0..worker_count - 1) |worker_index| {
        threads[started_thread_count] = std.Thread.spawn(
            .{},

            prefetchForwardWorkerMain,
            .{&workers[worker_index]},
        ) catch {
            prefetchForwardWorkerMain(&workers[worker_index]);
            continue;
        };

        started_thread_count += 1;
    }
    prefetchForwardWorkerMain(&workers[worker_count - 1]);
    for (threads[0..started_thread_count]) |thread| thread.join();
    if (comptime Storage.trace_phase_timing_enabled) {
        mergeLabosPhaseTiming(request.trace_phase_timing, labos_phase_timing_storage[0..worker_count]);
    }
    if (error_state.err) |err| return err;
}

fn mergeLabosPhaseTiming(
    trace_phase_timing: ?*Storage.TracePhaseTiming,
    worker_timings: []const labos.PhaseTiming,
) void {
    // mergeLabosPhaseTiming ---------------------------------------------------------------------------------------------|
    // Merge worker-local LABOS phase counters into the product-level phase timing sink.                                  |
    // -------------------------------------------------------------------------------------------------------------------|

    if (comptime Storage.trace_phase_timing_enabled) {
        const timing = trace_phase_timing orelse return;
        for (worker_timings) |worker_timing| timing.labos.merge(worker_timing);
    } else {
        return;
    }
}

pub fn preferredForwardWorkerCount(miss_count: usize) usize {
    // preferredForwardWorkerCount ---------------------------------------------------------------------------------------|
    // Keep small miss batches single-threaded and scale larger batches through the shared work-partition                 |
    // policy.                                                                                                            |
    // -------------------------------------------------------------------------------------------------------------------|

    return work_partition.preferredWorkerCount(miss_count, min_parallel_forward_miss_count);
}

fn telemetrySampleContext(base: Telemetry.Context, sample_index: usize, wavelength_nm: f64) Telemetry.Context {
    // telemetrySampleContext --------------------------------------------------------------------------------------------|
    // Add per-miss row and wavelength information to telemetry events when telemetry is compiled in.                     |
    // -------------------------------------------------------------------------------------------------------------------|

    if (comptime !Telemetry.enabled) return base;
    var context = base;
    context.sample_index = std.math.cast(i64, sample_index) orelse std.math.maxInt(i64);
    context.wavelength_nm = wavelength_nm;
    return context;
}
