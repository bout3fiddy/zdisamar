const std = @import("std");
const SpectralChannel = @import("../../../input/Instrument.zig").SpectralChannel;
const Scene = @import("../../../input/Scene.zig").Scene;
const OpticsPreparation = @import("../../optical_properties/root.zig");
const calibration = @import("../spectral_math/calibration.zig");
const convolution = @import("../spectral_math/convolution.zig");
const grid = @import("../spectral_math/grid.zig");
const common = @import("../../radiative_transfer/root.zig");
const jacobian = @import("../../jacobian/root.zig");
const instrument_calibration = @import("../../implementations/instrument/calibration.zig");
const instrument_integration = @import("../../implementations/instrument/integration.zig");
const WavelengthSampling = @import("wavelength_sampling.zig");
const SpectralEval = @import("spectral_eval.zig");
const SpectroscopyState = @import("../../optical_properties/state_build/state_spectroscopy.zig");
const Plan = @import("wavelength_plan.zig");
const Types = @import("types.zig");
const Storage = @import("storage.zig");
const Telemetry = @import("../../instrumentation/telemetry.zig");
const Trace = @import("../../instrumentation/trace.zig");
const work_partition = @import("../../work_partition.zig");

const Allocator = std.mem.Allocator;
const max_summary_samples: u32 = 128;
const profile_cache_build_chunk_size: usize = 8;

// simulate.zig ----------------------------------------------------------------------------------------------------------|
// Product-level instrument-grid coordinator. This file turns one Scene + PreparedOpticalState into output                |
// wavelength, radiance, irradiance, reflectance, and optional Jacobian arrays.                                           |
//                                                                                                                        |
// main path                                                                                                              |
//   buildSimulationSetup                                                                                                 |
//     -> resolveSimulationPlan                                                                                           |
//     -> prefetchSimulationPlan                                                                                          |
//     -> fillRadianceSamples                                                                                             |
//     -> fillIrradianceSamples                                                                                           |
//     -> assembleReflectance                                                                                             |
//     -> processJacobianSamples                                                                                          |
//                                                                                                                        |
// ownership                                                                                                              |
//   ProductStorage owns reusable output buffers and retained plans. One-shot calls allocate owned plan/result            |
//   storage inside ResolvedSimulationPlan and release it before returning.                                               |
// -----------------------------------------------------------------------------------------------------------------------|

// SimulationSetup -------------------------------------------------------------------------------------------------------|
// Resolved channel calibration, axis, and plan key for one product simulation.                                           |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 216 B (0.211 KiB), align: 8 B                                                                                    |
//                                                                                                                        |
// memory                                                                                                                 |
// [  0..  7] sample_count                       : usize                                                                  |
// [  8.. 47] resolved_axis                      : grid.ResolvedAxis                                                      |
// [ 48.. 79] radiance_calibration               : calibration.Calibration                                                |
// [ 80..111] irradiance_calibration             : calibration.Calibration                                                |
// [112..151] radiance_slit_kernel               : [5]f64                                                                 |
// [152..191] irradiance_slit_kernel             : [5]f64                                                                 |
// [192..199] safe_span                          : f64                                                                    |
// [200..207] plan_key                           : u64                                                                    |
// [208..208] uses_integrated_radiance_sampling  : bool                                                                   |
// [209..209] uses_integrated_irradiance_sampling : bool                                                                  |
// [210..215] padding                            : 6 B                                                                    |
//                                                                                                                        |
// unused bits: 48 padding + 14 bool-storage slack = 62 bits                                                              |
// cache span: 4 cache lines at 64 B per line                                                                             |
// footprint: per instance = 216 B (0.211 KiB); total = per instance * live instance count                                |
const SimulationSetup = struct {
    sample_count: usize,
    resolved_axis: grid.ResolvedAxis,
    radiance_calibration: calibration.Calibration,
    irradiance_calibration: calibration.Calibration,
    radiance_slit_kernel: [5]f64,
    irradiance_slit_kernel: [5]f64,
    uses_integrated_radiance_sampling: bool,
    uses_integrated_irradiance_sampling: bool,
    safe_span: f64,
    plan_key: u64,
};

// ResolvedSimulationPlan ----------------------------------------------------------------------------------------------- |
// Borrowed or owned wavelength sampling, forward miss, and profile-cache state for one simulation.                       |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 240 B (0.234 KiB), align: 8 B                                                                                    |
//                                                                                                                        |
// memory                                                                                                                 |
// [  0.. 47] wavelength_sampling          : WavelengthSampling.WavelengthSamplingTable                                   |
// [ 48.. 95] forward_miss_plan            : Plan.ForwardMissPlan                                                         |
// [ 96..111] forward_results              : []const SpectralEval.ForwardIntegratedSample                                 |
// [112..127] profile_spectroscopy_caches  : []const SpectroscopyState.ProfileNodeSpectroscopyCache                       |
// [128..175] owned_wavelength_sampling    : WavelengthSampling.OwnedWavelengthSampling                                   |
// [176..223] owned_forward_miss_plan      : Plan.OwnedForwardMissPlan                                                    |
// [224..239] owned_forward_results        : []SpectralEval.ForwardIntegratedSample                                       |
//                                                                                                                        |
// slices and owned plans carry referenced storage not included in the 240 B struct size.                                 |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 4 cache lines at 64 B per line                                                                             |
// footprint: per instance = 240 B (0.234 KiB); total also includes referenced storage above                              |
const ResolvedSimulationPlan = struct {
    wavelength_sampling: WavelengthSampling.WavelengthSamplingTable = .{},
    forward_miss_plan: Plan.ForwardMissPlan = .{},
    forward_results: []const SpectralEval.ForwardIntegratedSample = &.{},
    profile_spectroscopy_caches: []const SpectroscopyState.ProfileNodeSpectroscopyCache = &.{},
    owned_wavelength_sampling: WavelengthSampling.OwnedWavelengthSampling = .{},
    owned_forward_miss_plan: Plan.OwnedForwardMissPlan = .{},
    owned_forward_results: []SpectralEval.ForwardIntegratedSample = &.{},

    fn deinit(self: *ResolvedSimulationPlan, allocator: Allocator) void {
        // ResolvedSimulationPlan.deinit ---------------------------------------------------------------------------------|
        // Release one-shot owned plan/result storage. Workspace-backed runs borrow these fields and have                 |
        // nothing to free here.                                                                                          |
        // ---------------------------------------------------------------------------------------------------------------|

        self.owned_wavelength_sampling.deinit(allocator);
        self.owned_forward_miss_plan.deinit(allocator);
        allocator.free(self.owned_forward_results);
        self.* = undefined;
    }
};

inline fn tracePhaseStart(phase_timing: ?*Storage.TracePhaseTiming) ?i128 {

    // instrumentation: trace phase clock --------------------------------------------------------------------------------|
    // captures: coarse per-product phase durations for opt-in trace harness summaries                                    |
    // why: preserves JSON attribution for first-use and cached runs when ztracy timeline exports are too large.          |
    if (comptime Storage.trace_phase_timing_enabled) {
        _ = phase_timing orelse return null;

        return std.time.nanoTimestamp();
    } else {
        return null;
    }
    // end instrumentation: trace phase clock ----------------------------------------------------------------------------|

}

inline fn tracePhaseFinish(
    phase_timing: ?*Storage.TracePhaseTiming,
    start_timestamp: ?i128,
    comptime field_name: []const u8,
) void {

    // instrumentation: trace phase clock --------------------------------------------------------------------------------|
    // captures: elapsed phase duration accumulated into the requested timing field                                       |
    // why: keeps opt-in JSON attribution next to the ztracy phase boundary it summarizes.                                |
    if (comptime Storage.trace_phase_timing_enabled) {
        const timing = phase_timing orelse return;
        const started = start_timestamp orelse return;

        const finished = std.time.nanoTimestamp();
        if (finished <= started) return;
        const elapsed_ns = finished - started;
        if (elapsed_ns <= 0) return;

        @field(timing.*, field_name) += std.math.cast(u64, elapsed_ns) orelse std.math.maxInt(u64);
    } else {
        return;
    }
    // end instrumentation: trace phase clock ----------------------------------------------------------------------------|

}

// ActiveJacobianStates --------------------------------------------------------------------------------------------------|
// Active derivative states resolved once per simulation from the RTM config and storage mask.                            |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 16 B (0.016 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] count   : usize                                                                                               |
// [ 8..10] states  : [3]jacobian.State                                                                                   |
// [11..15] padding : 5 B                                                                                                 |
//                                                                                                                        |
// unused bits: 40 padding + 0 bool-storage slack = 40 bits                                                               |
// footprint: per instance = 16 B (0.016 KiB); one stack value in Jacobian-producing simulations                          |
const ActiveJacobianStates = struct {
    count: usize = 0,
    states: [jacobian.state_count]jacobian.State = undefined,

    fn init(mask: jacobian.StateMask) ActiveJacobianStates {
        // ActiveJacobianStates.init -------------------------------------------------------------------------------------|
        // Convert the active-state bit mask into a compact ordered array used by state-major Jacobian buffers.           |
        // ---------------------------------------------------------------------------------------------------------------|

        const active_mask = jacobian.sanitizedMask(mask);
        var result = ActiveJacobianStates{};
        for (0..jacobian.state_count) |state_index| {
            const state: jacobian.State = @enumFromInt(state_index);
            if (!jacobian.includes(active_mask, state)) continue;
            result.states[result.count] = state;
            result.count += 1;
        }
        return result;
    }

    fn at(self: ActiveJacobianStates, active_index: usize) ?jacobian.State {
        // ActiveJacobianStates.at ---------------------------------------------------------------------------------------|
        // Return the active state at a compact column index, or null when the index is outside the active set.           |
        // ---------------------------------------------------------------------------------------------------------------|

        if (active_index >= self.count) return null;
        return self.states[active_index];
    }
};

// RunningSummary --------------------------------------------------------------------------------------------------------|
// Accumulators used to compute product-level means while reflectance samples are assembled.                              |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 48 B (0.047 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] radiance_sum    : f64                                                                                         |
// [ 8..15] irradiance_sum  : f64                                                                                         |
// [16..23] reflectance_sum : f64                                                                                         |
// [24..47] jacobian_sum    : [3]f64                                                                                      |
//                                                                                                                        |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// footprint: per instance = 48 B (0.047 KiB); total = per instance * live instance count                                 |
const RunningSummary = struct {
    radiance_sum: f64,
    irradiance_sum: f64,
    reflectance_sum: f64,
    jacobian_sum: jacobian.Vector,

    fn init() RunningSummary {
        // RunningSummary.init -------------------------------------------------------------------------------------------|
        // Start zeroed accumulators for product mean statistics.                                                         |
        // ---------------------------------------------------------------------------------------------------------------|

        return .{
            .radiance_sum = 0.0,
            .irradiance_sum = 0.0,
            .reflectance_sum = 0.0,
            .jacobian_sum = jacobian.zero(),
        };
    }

    fn addReflectanceSample(self: *RunningSummary, radiance: f64, irradiance: f64, reflectance: f64) void {
        // RunningSummary.addReflectanceSample ---------------------------------------------------------------------------|
        // Add one output row to the running radiance, irradiance, and reflectance sums.                                  |
        // ---------------------------------------------------------------------------------------------------------------|

        self.radiance_sum += radiance;
        self.irradiance_sum += irradiance;
        self.reflectance_sum += reflectance;
    }

    fn toInstrumentGridSummary(
        self: RunningSummary,
        sample_count: usize,
        wavelengths: []const f64,
        mean_jacobian: ?jacobian.Vector,
    ) Types.InstrumentGridSummary {
        // RunningSummary.toInstrumentGridSummary ------------------------------------------------------------------------|
        // Convert accumulated sums into mean values and attach the output wavelength range.                              |
        // ---------------------------------------------------------------------------------------------------------------|

        const denominator = @as(f64, @floatFromInt(sample_count));
        return .{
            .sample_count = @intCast(sample_count),
            .wavelength_start_nm = wavelengths[0],
            .wavelength_end_nm = wavelengths[sample_count - 1],
            .mean_radiance = self.radiance_sum / denominator,
            .mean_irradiance = self.irradiance_sum / denominator,
            .mean_reflectance = self.reflectance_sum / denominator,
            .mean_jacobian = mean_jacobian,
        };
    }
};

// RadianceSamplingRequest -----------------------------------------------------------------------------------------------|
// Read-only data needed to gather prefetched LABOS misses into nominal radiance rows.                                    |
// This value owns no arrays; wavelength and miss tables are borrowed from ResolvedSimulationPlan or ProductStorage.      |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 416 B (0.406 KiB), align: 8 B                                                                                    |
//                                                                                                                        |
// memory                                                                                                                 |
// [  0.. 79] rtm_config          : common.SolveConfig                                                                    |
// [ 80..295] setup               : SimulationSetup                                                                       |
// [296..343] wavelength_sampling : WavelengthSampling.WavelengthSamplingTable                                            |
// [344..391] forward_miss_plan   : Plan.ForwardMissPlan                                                                  |
// [392..407] forward_results     : []const SpectralEval.ForwardIntegratedSample                                          |
// [408..415] trace_phase_timing  : ?*Storage.TracePhaseTiming                                                            |
//                                                                                                                        |
// out-of-line storage: all slices point at the resolved simulation plan or retained product workspace.                   |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// footprint: per instance = 416 B (0.406 KiB); total excludes borrowed plan/result storage                               |
const RadianceSamplingRequest = struct {
    rtm_config: common.SolveConfig,
    setup: SimulationSetup,
    wavelength_sampling: WavelengthSampling.WavelengthSamplingTable,
    forward_miss_plan: Plan.ForwardMissPlan,
    forward_results: []const SpectralEval.ForwardIntegratedSample,
    trace_phase_timing: ?*Storage.TracePhaseTiming,
};
// -----------------------------------------------------------------------------------------------------------------------|

// RadianceSampleBuffers -------------------------------------------------------------------------------------------------|
// Borrowed output and scratch slices touched while producing calibrated radiance. Transport scratch stays                |
// out of this view, so the radiance stage exposes only the product rows it reads or writes.                              |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 72 B (0.070 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0..15] wavelengths         : []f64                                                                                   |
// [16..31] radiance            : []f64                                                                                   |
// [32..47] scratch             : []f64                                                                                   |
// [48..63] jacobian            : ?[]f64                                                                                  |
// [64..64] jacobian_state_mask : jacobian.StateMask                                                                      |
// [65..71] padding             : 7 B                                                                                     |
//                                                                                                                        |
// out-of-line storage: slices borrow ProductStorage backing arrays.                                                      |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                               |
// footprint: per instance = 72 B (0.070 KiB); total excludes borrowed product buffers                                    |
const RadianceSampleBuffers = struct {
    wavelengths: []f64,
    radiance: []f64,
    scratch: []f64,
    jacobian: ?[]f64,
    jacobian_state_mask: jacobian.StateMask,
};
// -----------------------------------------------------------------------------------------------------------------------|

// IrradianceSamplingRequest ---------------------------------------------------------------------------------------------|
// Read-only data needed to sample solar irradiance on the nominal product grid. The evaluation cache is                  |
// borrowed and retains exact-wavelength solar samples across rows.                                                       |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 296 B (0.289 KiB), align: 8 B                                                                                    |
//                                                                                                                        |
// memory                                                                                                                 |
// [  0..  7] scene               : *const Scene                                                                          |
// [  8.. 15] prepared            : *const OpticsPreparation.PreparedOpticalState                                         |
// [ 16..231] setup               : SimulationSetup                                                                       |
// [232..279] wavelength_sampling : WavelengthSampling.WavelengthSamplingTable                                            |
// [280..287] evaluation_cache    : *SpectralEval.SpectralEvaluationCache                                                 |
// [288..295] trace_phase_timing  : ?*Storage.TracePhaseTiming                                                            |
//                                                                                                                        |
// out-of-line storage: scene, prepared, sampling rows, and cache are borrowed from the caller.                           |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// footprint: per instance = 296 B (0.289 KiB); total excludes borrowed scene/prepared/cache storage                      |
const IrradianceSamplingRequest = struct {
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    setup: SimulationSetup,
    wavelength_sampling: WavelengthSampling.WavelengthSamplingTable,
    evaluation_cache: *SpectralEval.SpectralEvaluationCache,
    trace_phase_timing: ?*Storage.TracePhaseTiming,
};
// -----------------------------------------------------------------------------------------------------------------------|

// IrradianceSampleBuffers -----------------------------------------------------------------------------------------------|
// Borrowed slices touched while producing calibrated irradiance.                                                         |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 32 B (0.031 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0..15] scratch    : []f64                                                                                            |
// [16..31] irradiance : []f64                                                                                            |
//                                                                                                                        |
// out-of-line storage: slices borrow ProductStorage backing arrays.                                                      |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// footprint: per instance = 32 B (0.031 KiB); total excludes borrowed product buffers                                    |
const IrradianceSampleBuffers = struct {
    scratch: []f64,
    irradiance: []f64,
};
// -----------------------------------------------------------------------------------------------------------------------|

// ProfileCacheBuildWorker -----------------------------------------------------------------------------------------------|
// Static range assigned to a profile-spectroscopy cache worker.                                                          |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 64 B (0.062 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] prepared        : *const OpticsPreparation.PreparedOpticalState                                               |
// [ 8..23] forward_misses  : []const SpectralEval.ForwardCacheMiss                                                       |
// [24..39] caches          : []SpectroscopyState.ProfileNodeSpectroscopyCache                                            |
// [40..47] start_index     : usize                                                                                       |
// [48..55] end_index       : usize                                                                                       |
// [56..63] worker_index    : usize                                                                                       |
//                                                                                                                        |
// prepared, forward_misses, and caches reference storage not included in the 64 B struct size.                           |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 1 cache line at 64 B per line                                                                              |
// footprint: per instance = 64 B (0.062 KiB); total also includes referenced storage above                               |
const ProfileCacheBuildWorker = struct {
    prepared: *const OpticsPreparation.PreparedOpticalState,
    forward_misses: []const SpectralEval.ForwardCacheMiss,
    caches: []SpectroscopyState.ProfileNodeSpectroscopyCache,
    start_index: usize,
    end_index: usize,
    worker_index: usize = 0,
};

fn profileCacheBuildWorkerMain(worker: *ProfileCacheBuildWorker) void {
    // profileCacheBuildWorkerMain ---------------------------------------------------------------------------------------|
    // Build ProfileNodeSpectroscopyCache entries for a static worker range. Each cache belongs to the same               |
    // index as the forward miss it accelerates.                                                                          |
    // -------------------------------------------------------------------------------------------------------------------|

    var thread_name_buffer: [64]u8 = undefined;
    const thread_name = std.fmt.bufPrintZ(
        &thread_name_buffer,
        "zdisamar-profile-cache-{d}",
        .{worker.worker_index},
    ) catch "zdisamar-profile-cache";

    // instrumentation: trace thread label: profile cache worker -------------------------------------------------------- |
    // captures: profile spectroscopy cache worker identity                                                               |
    // why: makes parallel cache-build lanes separable in timeline traces.                                                |
    Trace.setThreadName(thread_name);
    // end instrumentation: trace thread label: profile cache worker ---------------------------------------------------- |

    // instrumentation: trace zone: profile cache worker ---------------------------------------------------------------- |
    // captures: profile spectroscopy cache worker wall time                                                              |
    // why: separates worker fanout cost from the main simulation path.                                                   |
    const zone = Trace.staticZone(@src(), "profile_spectroscopy_cache.worker");
    zone.value(@intCast(worker.worker_index));
    defer zone.end();
    // end instrumentation: trace zone: profile cache worker ------------------------------------------------------------ |

    var chunk_start = worker.start_index;
    while (chunk_start < worker.end_index) {
        const chunk = .{
            .start = chunk_start,
            .end = @min(chunk_start + profile_cache_build_chunk_size, worker.end_index),
        };
        chunk_start = chunk.end;
        for (chunk.start..chunk.end) |index| {
            worker.caches[index] = SpectroscopyState.ProfileNodeSpectroscopyCache.init(
                worker.prepared,
                worker.forward_misses[index].wavelength_nm,
            );
        }
    }
}

pub fn warmWavelengthPlan(
    allocator: Allocator,
    storage: *Storage.ProductStorage,
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
) Storage.Error!void {
    // warmWavelengthPlan ------------------------------------------------------------------------------------------------|
    // Prebuild the reusable wavelength sampling, forward-miss, and profile spectroscopy caches for a stored              |
    // product workspace. This lets the next simulation skip first-use planning work when the key still                   |
    // matches.                                                                                                           |
    // -------------------------------------------------------------------------------------------------------------------|

    try scene.validate();
    const spectral_grid: grid.SpectralGrid = .{
        .start_nm = scene.spectral_grid.start_nm,
        .end_nm = scene.spectral_grid.end_nm,
        .sample_count = scene.spectral_grid.sample_count,
    };
    const resolved_axis: grid.ResolvedAxis = .{
        .base = spectral_grid,
        .explicit_wavelengths_nm = scene.observation_model.measured_wavelengths_nm,
    };
    try resolved_axis.validate();

    const plan_key = wavelengthPlanKey(scene, prepared);
    if (storage.wavelength_plan_valid and storage.wavelength_plan_key == plan_key) {
        _ = try ensureProfileSpectroscopyCaches(allocator, storage, prepared, storage.forward_miss_plan.misses);
        return;
    }

    storage.invalidateWavelengthPlan(allocator);
    errdefer storage.invalidateWavelengthPlan(allocator);

    storage.wavelength_sampling = try WavelengthSampling.buildWavelengthSampling(
        allocator,
        scene,
        prepared,
        &resolved_axis,
        instrument_calibration.calibrationForScene(scene, .radiance),
        instrument_calibration.calibrationForScene(scene, .irradiance),
    );
    storage.forward_miss_plan = try WavelengthSampling.buildForwardMissPlan(
        allocator,
        storage.wavelength_sampling.view(),
    );
    storage.forward_miss_plan_valid = true;
    _ = try ensureProfileSpectroscopyCaches(allocator, storage, prepared, storage.forward_miss_plan.misses);
    storage.wavelength_plan_key = plan_key;
    storage.wavelength_plan_valid = true;
}

fn ensureProfileSpectroscopyCaches(
    allocator: Allocator,
    storage: *Storage.ProductStorage,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    forward_misses: []const SpectralEval.ForwardCacheMiss,
) ![]const SpectroscopyState.ProfileNodeSpectroscopyCache {
    // ensureProfileSpectroscopyCaches -----------------------------------------------------------------------------------|
    // Return profile-node spectroscopy caches matching the current prepared state and forward-miss list.                 |
    // Cache entries are invalidated together because a miss wavelength and spectroscopy profile inputs both              |
    // decide the carrier rows used by forward_input.zig.                                                                 |
    // -------------------------------------------------------------------------------------------------------------------|

    const cache_key = profileSpectroscopyCacheKey(prepared, forward_misses);
    if (storage.profile_spectroscopy_cache_valid and
        storage.profile_spectroscopy_cache_key == cache_key and
        storage.profile_spectroscopy_caches.len == forward_misses.len)
    {
        return storage.profile_spectroscopy_caches;
    }

    allocator.free(storage.profile_spectroscopy_caches);
    storage.profile_spectroscopy_caches = &.{};
    storage.profile_spectroscopy_cache_key = 0;
    storage.profile_spectroscopy_cache_valid = false;

    const worker_count = SpectralEval.preferredForwardWorkerCount(forward_misses.len);
    const thread_pool = storage.forwardPrefetchPool(allocator, worker_count);
    storage.profile_spectroscopy_caches = try buildProfileSpectroscopyCaches(
        allocator,
        prepared,
        forward_misses,
        thread_pool,
    );
    storage.profile_spectroscopy_cache_key = cache_key;
    storage.profile_spectroscopy_cache_valid = true;
    return storage.profile_spectroscopy_caches;
}

fn buildProfileSpectroscopyCaches(
    allocator: Allocator,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    forward_misses: []const SpectralEval.ForwardCacheMiss,
    thread_pool: ?*std.Thread.Pool,
) ![]SpectroscopyState.ProfileNodeSpectroscopyCache {
    // buildProfileSpectroscopyCaches ------------------------------------------------------------------------------------|
    // Build one ProfileNodeSpectroscopyCache per forward miss. Large miss batches can use the same worker                |
    // pool as LABOS prefetch because both phases partition the miss list by index.                                       |
    // -------------------------------------------------------------------------------------------------------------------|

    // instrumentation: trace zone: profile cache build ----------------------------------------------------------------- |
    // captures: profile spectroscopy cache build wall time and miss count                                                |
    // why: shows when cache construction, rather than LABOS transport, dominates prefetch setup.                         |
    const zone = Trace.staticZone(@src(), "profile_spectroscopy_cache.build");
    zone.value(@intCast(forward_misses.len));
    defer zone.end();
    // end instrumentation: trace zone: profile cache build ------------------------------------------------------------- |

    const caches = try allocator.alloc(SpectroscopyState.ProfileNodeSpectroscopyCache, forward_misses.len);
    errdefer allocator.free(caches);

    const worker_count = SpectralEval.preferredForwardWorkerCount(forward_misses.len);
    if (worker_count == 1) {
        for (forward_misses, caches) |miss, *cache| {
            cache.* = SpectroscopyState.ProfileNodeSpectroscopyCache.init(prepared, miss.wavelength_nm);
        }
        return caches;
    }

    std.debug.assert(worker_count <= work_partition.max_workers);
    var worker_storage: [work_partition.max_workers]ProfileCacheBuildWorker = undefined;
    const workers = worker_storage[0..worker_count];
    for (0..worker_count) |worker_index| {
        const range = work_partition.staticRange(forward_misses.len, worker_count, worker_index);
        workers[worker_index] = .{
            .prepared = prepared,
            .forward_misses = forward_misses,
            .caches = caches,
            .start_index = range.start,
            .end_index = range.end,
            .worker_index = worker_index,
        };
    }

    if (thread_pool) |pool| {
        var wait_group = std.Thread.WaitGroup{};
        for (0..worker_count - 1) |worker_index| {
            pool.spawnWg(&wait_group, profileCacheBuildWorkerMain, .{&workers[worker_index]});
        }
        profileCacheBuildWorkerMain(&workers[worker_count - 1]);
        wait_group.wait();
        return caches;
    }

    var thread_storage: [work_partition.max_workers - 1]std.Thread = undefined;
    const threads = thread_storage[0 .. worker_count - 1];
    var started_thread_count: usize = 0;
    for (0..worker_count - 1) |worker_index| {
        threads[started_thread_count] = std.Thread.spawn(
            .{},
            profileCacheBuildWorkerMain,
            .{&workers[worker_index]},
        ) catch {
            profileCacheBuildWorkerMain(&workers[worker_index]);
            continue;
        };
        started_thread_count += 1;
    }
    profileCacheBuildWorkerMain(&workers[worker_count - 1]);
    for (threads[0..started_thread_count]) |thread| thread.join();
    return caches;
}

pub fn simulateInternal(
    allocator: Allocator,
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    buffers: Storage.Buffers,
    evaluation_cache: *SpectralEval.SpectralEvaluationCache,
    wavelength_plan_storage: ?*Storage.ProductStorage,
) Storage.Error!Types.InstrumentGridSummary {
    // simulateInternal --------------------------------------------------------------------------------------------------|
    // Main product simulation. This function sequences plan resolution, high-resolution forward prefetch,                |
    // instrument-channel assembly, reflectance conversion, and optional Jacobian postprocessing.                         |
    //                                                                                                                    |
    // data flow                                                                                                          |
    //   wavelength plan -> forward miss plan -> forward results -> radiance                                              |
    //   wavelength plan -> irradiance cache -> irradiance                                                                |
    //   radiance + irradiance + geometry -> reflectance                                                                  |
    //                                                                                                                    |
    // workspace                                                                                                          |
    //   When wavelength_plan_storage is present, plans and buffers are reused. Otherwise this call owns and              |
    //   frees temporary plan/result storage through ResolvedSimulationPlan.                                              |
    // -------------------------------------------------------------------------------------------------------------------|

    // instrumentation: trace zone: product simulation ------------------------------------------------------------------ |
    // captures: whole instrument-grid product simulation wall time                                                       |
    // why: anchors nested sampling, prefetch, convolution, and assembly phases to one forward solve.                     |
    const simulate_zone = Trace.staticZone(@src(), "simulate.product");
    defer simulate_zone.end();
    // end instrumentation: trace zone: product simulation -------------------------------------------------------------- |

    const trace_phase_timing = if (wavelength_plan_storage) |storage| storage.activeTracePhaseTiming() else null;
    if (trace_phase_timing) |timing| timing.reset();

    const setup = try buildSimulationSetup(scene, rtm_config, prepared, buffers);
    var simulation_plan = try resolveSimulationPlan(
        allocator,
        scene,
        prepared,
        setup,
        wavelength_plan_storage,
        trace_phase_timing,
    );
    defer simulation_plan.deinit(allocator);
    try prefetchSimulationPlan(
        allocator,
        scene,
        rtm_config,
        prepared,
        &simulation_plan,
        wavelength_plan_storage,
        trace_phase_timing,
    );

    var summary = RunningSummary.init();
    _ = try validateTransportBuffers(scene, rtm_config, prepared, buffers);
    const radiance_request = RadianceSamplingRequest{
        .rtm_config = rtm_config,
        .setup = setup,
        .wavelength_sampling = simulation_plan.wavelength_sampling,
        .forward_miss_plan = simulation_plan.forward_miss_plan,
        .forward_results = simulation_plan.forward_results,
        .trace_phase_timing = trace_phase_timing,
    };
    const radiance_output = RadianceSampleBuffers{
        .wavelengths = buffers.wavelengths,
        .radiance = buffers.radiance,
        .scratch = buffers.scratch,
        .jacobian = buffers.jacobian,
        .jacobian_state_mask = buffers.jacobian_state_mask,
    };
    try fillRadianceSamples(radiance_request, radiance_output);

    const irradiance_request = IrradianceSamplingRequest{
        .scene = scene,
        .prepared = prepared,
        .setup = setup,
        .wavelength_sampling = simulation_plan.wavelength_sampling,
        .evaluation_cache = evaluation_cache,
        .trace_phase_timing = trace_phase_timing,
    };
    const irradiance_output = IrradianceSampleBuffers{
        .scratch = buffers.scratch,
        .irradiance = buffers.irradiance,
    };
    try fillIrradianceSamples(irradiance_request, irradiance_output);
    assembleReflectance(scene, setup.sample_count, buffers, &summary, trace_phase_timing);
    const mean_jacobian = try processJacobianSamples(
        rtm_config.derivative_state_mask,
        setup,
        buffers,
        &summary,
        trace_phase_timing,
    );
    return summary.toInstrumentGridSummary(
        setup.sample_count,
        buffers.wavelengths,
        mean_jacobian,
    );
}

fn buildSimulationSetup(
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    buffers: Storage.Buffers,
) Storage.Error!SimulationSetup {
    // buildSimulationSetup ----------------------------------------------------------------------------------------------|
    // Validate caller input and collect the channel-level constants needed by the rest of the simulation.                |
    // This keeps sampling/convolution code from repeatedly resolving scene controls.                                     |
    // -------------------------------------------------------------------------------------------------------------------|

    try scene.validate();
    const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
    try Storage.validateBuffers(scene, rtm_config, sample_count, buffers);

    const spectral_grid: grid.SpectralGrid = .{
        .start_nm = scene.spectral_grid.start_nm,
        .end_nm = scene.spectral_grid.end_nm,
        .sample_count = scene.spectral_grid.sample_count,
    };
    const resolved_axis: grid.ResolvedAxis = .{
        .base = spectral_grid,
        .explicit_wavelengths_nm = scene.observation_model.measured_wavelengths_nm,
    };
    try resolved_axis.validate();

    const radiance_calibration = instrument_calibration.calibrationForScene(scene, .radiance);
    const irradiance_calibration = instrument_calibration.calibrationForScene(scene, .irradiance);
    const radiance_slit_kernel = instrument_integration.slitKernelForScene(scene, .radiance);
    const irradiance_slit_kernel = instrument_integration.slitKernelForScene(scene, .irradiance);
    const uses_integrated_radiance_sampling =
        instrument_integration.usesIntegratedInstrumentSampling(scene, .radiance);
    const uses_integrated_irradiance_sampling =
        instrument_integration.usesIntegratedInstrumentSampling(scene, .irradiance);
    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;

    // Use at least 1 nm as the support span floor for normalized carrier and support interpolation.
    const safe_span = if (span_nm <= 0.0) 1.0 else span_nm;

    // instrumentation: trace counter: output wavelengths --------------------------------------------------------------- |
    // captures: number of output wavelength samples                                                                      |
    // why: normalizes product-level timeline cost by the emitted spectrum size.                                          |
    Trace.plotU("output_wavelengths", @intCast(sample_count));
    // end instrumentation: trace counter: output wavelengths ----------------------------------------------------------- |

    const plan_key = wavelengthPlanKey(scene, prepared);

    return .{
        .sample_count = sample_count,
        .resolved_axis = resolved_axis,
        .radiance_calibration = radiance_calibration,
        .irradiance_calibration = irradiance_calibration,
        .radiance_slit_kernel = radiance_slit_kernel,
        .irradiance_slit_kernel = irradiance_slit_kernel,
        .uses_integrated_radiance_sampling = uses_integrated_radiance_sampling,
        .uses_integrated_irradiance_sampling = uses_integrated_irradiance_sampling,
        .safe_span = safe_span,
        .plan_key = plan_key,
    };
}

fn resolveSimulationPlan(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    setup: SimulationSetup,
    wavelength_plan_storage: ?*Storage.ProductStorage,
    trace_phase_timing: ?*Storage.TracePhaseTiming,
) Storage.Error!ResolvedSimulationPlan {
    // resolveSimulationPlan ---------------------------------------------------------------------------------------------|
    // Resolve the wavelength sampling table, forward-miss plan, and profile spectroscopy caches. Workspace               |
    // runs reuse retained plans when their keys match; one-shot runs build owned temporary plans.                        |
    // -------------------------------------------------------------------------------------------------------------------|

    var plan: ResolvedSimulationPlan = .{};
    errdefer plan.deinit(allocator);

    plan.wavelength_sampling = resolve_wavelength_sampling: {

        // instrumentation: trace zone: wavelength sampling resolution -------------------------------------------------- |
        // captures: wavelength sampling plan resolution wall time                                                        |
        // why: distinguishes cache hits, plan rebuilds, and owned one-shot sampling setup.                               |
        const trace_start_ns = tracePhaseStart(trace_phase_timing);
        defer tracePhaseFinish(trace_phase_timing, trace_start_ns, "wavelength_sampling_ns");
        const zone = Trace.staticZone(@src(), "simulate.wavelength_sampling");
        defer zone.end();
        // end instrumentation: trace zone: wavelength sampling resolution ---------------------------------------------- |

        if (wavelength_plan_storage) |storage| {
            if (storage.wavelength_plan_valid and storage.wavelength_plan_key == setup.plan_key) {
                break :resolve_wavelength_sampling storage.wavelength_sampling.view();
            }
            storage.invalidateWavelengthPlan(allocator);
            storage.wavelength_sampling = try WavelengthSampling.buildWavelengthSampling(
                allocator,
                scene,
                prepared,
                &setup.resolved_axis,
                setup.radiance_calibration,
                setup.irradiance_calibration,
            );
            storage.wavelength_plan_key = setup.plan_key;
            storage.wavelength_plan_valid = true;
            break :resolve_wavelength_sampling storage.wavelength_sampling.view();
        }
        plan.owned_wavelength_sampling = try WavelengthSampling.buildWavelengthSampling(
            allocator,
            scene,
            prepared,
            &setup.resolved_axis,
            setup.radiance_calibration,
            setup.irradiance_calibration,
        );
        break :resolve_wavelength_sampling plan.owned_wavelength_sampling.view();
    };
    plan.forward_miss_plan = resolve_forward_miss_plan: {

        // instrumentation: trace zone: forward miss collection --------------------------------------------------------- |
        // captures: forward-cache miss collection wall time                                                              |
        // why: measures the unique high-resolution wavelength expansion before LABOS prefetch.                           |
        const trace_start_ns = tracePhaseStart(trace_phase_timing);
        defer tracePhaseFinish(trace_phase_timing, trace_start_ns, "forward_miss_collection_ns");
        const zone = Trace.staticZone(@src(), "simulate.forward_miss_collection");
        defer zone.end();
        // end instrumentation: trace zone: forward miss collection ----------------------------------------------------- |

        if (wavelength_plan_storage) |storage| {
            if (!storage.forward_miss_plan_valid) {
                storage.forward_miss_plan = try WavelengthSampling.buildForwardMissPlan(
                    allocator,
                    plan.wavelength_sampling,
                );
                storage.forward_miss_plan_valid = true;
            }
            break :resolve_forward_miss_plan storage.forward_miss_plan.view();
        }
        plan.owned_forward_miss_plan = try WavelengthSampling.buildForwardMissPlan(
            allocator,
            plan.wavelength_sampling,
        );
        break :resolve_forward_miss_plan plan.owned_forward_miss_plan.view();
    };
    plan.profile_spectroscopy_caches = resolve_profile_spectroscopy_caches: {

        // instrumentation: trace zone: profile spectroscopy cache ------------------------------------------------------ |
        // captures: profile spectroscopy cache lookup/build wall time                                                    |
        // why: isolates profile-node spectroscopy setup from transport execution.                                        |
        const trace_start_ns = tracePhaseStart(trace_phase_timing);
        defer tracePhaseFinish(trace_phase_timing, trace_start_ns, "profile_spectroscopy_cache_ns");
        const zone = Trace.staticZone(@src(), "simulate.profile_spectroscopy_cache");
        defer zone.end();
        // end instrumentation: trace zone: profile spectroscopy cache -------------------------------------------------- |

        if (wavelength_plan_storage) |storage| {
            break :resolve_profile_spectroscopy_caches try ensureProfileSpectroscopyCaches(
                allocator,
                storage,
                prepared,
                plan.forward_miss_plan.misses,
            );
        }
        break :resolve_profile_spectroscopy_caches &.{};
    };
    return plan;
}

fn prefetchSimulationPlan(
    allocator: Allocator,
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    simulation_plan: *ResolvedSimulationPlan,
    wavelength_plan_storage: ?*Storage.ProductStorage,
    trace_phase_timing: ?*Storage.TracePhaseTiming,
) Storage.Error!void {
    // prefetchSimulationPlan --------------------------------------------------------------------------------------------|
    // Allocate or reuse the dense forward-result buffer, then compute every unique forward miss before                   |
    // nominal radiance integration starts.                                                                               |
    // -------------------------------------------------------------------------------------------------------------------|

    {

        // instrumentation: trace zone: forward prefetch wall ----------------------------------------------------------- |
        // captures: forward prefetch wall time and miss count                                                            |
        // why: tracks the batched high-resolution LABOS work hidden behind nominal samples.                              |
        const trace_start_ns = tracePhaseStart(trace_phase_timing);
        defer tracePhaseFinish(trace_phase_timing, trace_start_ns, "forward_prefetch_ns");
        const zone = Trace.staticZone(@src(), "simulate.forward_prefetch_wall");
        zone.value(@intCast(simulation_plan.forward_miss_plan.misses.len));
        defer zone.end();
        // end instrumentation: trace zone: forward prefetch wall ------------------------------------------------------- |

        const worker_count = SpectralEval.preferredForwardWorkerCount(simulation_plan.forward_miss_plan.misses.len);

        var thread_pool: ?*std.Thread.Pool = null;
        var results: []SpectralEval.ForwardIntegratedSample = undefined;
        if (wavelength_plan_storage) |storage| {
            thread_pool = storage.forwardPrefetchPool(allocator, worker_count);
            results = try storage.forwardResultBuffer(
                allocator,
                simulation_plan.forward_miss_plan.misses.len,
            );
        } else {
            results = try allocator.alloc(
                SpectralEval.ForwardIntegratedSample,
                simulation_plan.forward_miss_plan.misses.len,
            );
            simulation_plan.owned_forward_results = results;
        }

        try SpectralEval.prefetchForwardSamples(
            allocator,
            scene,
            rtm_config,
            prepared,
            simulation_plan.forward_miss_plan.misses,
            simulation_plan.profile_spectroscopy_caches,
            results,
            thread_pool,
            trace_phase_timing,
        );

        simulation_plan.forward_results = results;
    }
}

fn validateTransportBuffers(
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    buffers: Storage.Buffers,
) Storage.Error!usize {
    // validateTransportBuffers ------------------------------------------------------------------------------------------|
    // Check transport-side buffer capacity against the exact prepared state before wavelength writes begin.              |
    // ProductStorage.buffers sizes from scene hints; this catches any mismatch after preparation resolves                |
    // explicit interval or shared RTM geometry details.                                                                  |
    // -------------------------------------------------------------------------------------------------------------------|

    const transport_layer_count = Storage.resolvedTransportLayerCount(rtm_config, prepared);

    if (buffers.layer_inputs.len < transport_layer_count) {
        return error.ShapeMismatch;
    }

    if (Storage.configMayUseSourceInterfaces(scene, rtm_config) and
        buffers.source_interfaces.len < transport_layer_count + 1)
    {
        return error.ShapeMismatch;
    }

    if (Storage.configUsesRtmQuadrature(rtm_config) and
        buffers.rtm_quadrature_levels.len < transport_layer_count + 1)
    {
        return error.ShapeMismatch;
    }

    if (Storage.configUsesPseudoSphericalGrid(rtm_config) and
        buffers.pseudo_spherical_level_starts.len < transport_layer_count + 1)
    {
        return error.ShapeMismatch;
    }

    return transport_layer_count;
}

fn fillRadianceSamples(
    request: RadianceSamplingRequest,
    output: RadianceSampleBuffers,
) Storage.Error!void {
    // fillRadianceSamples -----------------------------------------------------------------------------------------------|
    // Fill output wavelengths and radiance. Radiance first gathers prefetched forward results through the                |
    // miss plan, then either copies integrated samples directly or applies slit convolution, then channel                |
    // calibration. Active Jacobian rows are written in state-major workspace layout during the gather.                   |
    //                                                                                                                    |
    // math                                                                                                               |
    //   L_raw_i = sum_j weight_ij * F(lambda_i + offset_ij)                                                              |
    //   L_out_i = channel_calibration(convolution(L_raw)_i)                                                              |
    //                                                                                                                    |
    // integrated sampling                                                                                                |
    //   When the instrument integration kernel has already built L_raw_i from high-resolution samples, the               |
    //   later slit convolution is skipped so the line shape is not applied twice.                                        |
    // -------------------------------------------------------------------------------------------------------------------|

    const active_jacobians = if (output.jacobian != null)
        ActiveJacobianStates.init(output.jacobian_state_mask)
    else
        ActiveJacobianStates{};

    {

        // instrumentation: trace zone: radiance cache integration ------------------------------------------------------ |
        // captures: radiance cache integration wall time                                                                 |
        // why: isolates nominal-wavelength gather work from later convolution and calibration.                           |
        const trace_start_ns = tracePhaseStart(request.trace_phase_timing);
        defer tracePhaseFinish(request.trace_phase_timing, trace_start_ns, "radiance_cache_integration_ns");
        const zone = Trace.staticZone(@src(), "simulate.radiance_cache_integration");
        defer zone.end();
        // end instrumentation: trace zone: radiance cache integration -------------------------------------------------- |

        for (request.wavelength_sampling.rows, 0..) |plan, index| {
            const nominal_wavelength_nm = plan.nominal_wavelength_nm;
            output.wavelengths[index] = nominal_wavelength_nm;

            if (index >= request.forward_miss_plan.rows.len) return error.ShapeMismatch;
            const integrated = try SpectralEval.integratePrefetchedForwardAtNominal(
                request.rtm_config,
                request.forward_results,
                request.forward_miss_plan.rows[index],
                request.forward_miss_plan.sample_indices,
                &plan.radiance_integration,
                request.wavelength_sampling.kernel_storage,
            );
            output.scratch[index] = integrated.radiance;
            if (output.jacobian) |jacobian_buffer| {
                writeJacobianSample(
                    jacobian_buffer,
                    active_jacobians,
                    request.setup.sample_count,
                    index,
                    integrated.jacobian,
                );
            }
        }
    }
    if (request.setup.uses_integrated_radiance_sampling) {

        // Integrated sampling bypasses slit convolution because the instrument integration kernel has already
        // performed that spectral averaging.
        @memcpy(output.radiance, output.scratch);
    } else {

        // instrumentation: trace zone: radiance convolution ------------------------------------------------------------ |
        // captures: radiance slit convolution wall time                                                                  |
        // why: separates instrument-kernel cost from RTM cache integration.                                              |
        const trace_start_ns = tracePhaseStart(request.trace_phase_timing);
        defer tracePhaseFinish(request.trace_phase_timing, trace_start_ns, "radiance_convolution_ns");
        const zone = Trace.staticZone(@src(), "simulate.radiance_convolution");
        defer zone.end();
        // end instrumentation: trace zone: radiance convolution -------------------------------------------------------- |

        try convolution.apply(output.scratch, request.setup.radiance_slit_kernel[0..], output.radiance);
    }
    {

        // instrumentation: trace zone: radiance postprocess ------------------------------------------------------------ |
        // captures: radiance channel postprocess wall time                                                               |
        // why: keeps calibration/postprocess cost visible after convolution.                                             |
        const trace_start_ns = tracePhaseStart(request.trace_phase_timing);
        defer tracePhaseFinish(request.trace_phase_timing, trace_start_ns, "radiance_postprocess_ns");
        const zone = Trace.staticZone(@src(), "simulate.radiance_postprocess");
        defer zone.end();
        // end instrumentation: trace zone: radiance postprocess -------------------------------------------------------- |

        try calibration.applySignal(
            request.setup.radiance_calibration,
            output.radiance,
            output.radiance,
        );
    }
}

fn fillIrradianceSamples(
    request: IrradianceSamplingRequest,
    output: IrradianceSampleBuffers,
) Storage.Error!void {
    // fillIrradianceSamples ---------------------------------------------------------------------------------------------|
    // Fill irradiance through the same nominal sampling contract used for radiance. Solar samples come from              |
    // the irradiance cache instead of LABOS forward results.                                                             |
    //                                                                                                                    |
    // math                                                                                                               |
    //   E0_raw_i = sum_j weight_ij * E0(lambda_i + offset_ij)                                                            |
    //   E0_out_i = channel_calibration(convolution(E0_raw)_i)                                                            |
    //                                                                                                                    |
    // source of samples                                                                                                  |
    //   Radiance samples come from LABOS forward misses. Irradiance samples come from solar support data,                |
    //   but both channels apply the same instrument-response pattern: integrate, optionally convolve, calibrate.         |
    // -------------------------------------------------------------------------------------------------------------------|

    {

        // instrumentation: trace zone: irradiance sampling ------------------------------------------------------------- |
        // captures: irradiance sampling wall time                                                                        |
        // why: distinguishes solar irradiance interpolation/integration from radiance transport.                         |
        const trace_start_ns = tracePhaseStart(request.trace_phase_timing);
        defer tracePhaseFinish(request.trace_phase_timing, trace_start_ns, "irradiance_sampling_ns");
        const zone = Trace.staticZone(@src(), "simulate.irradiance_sampling");
        defer zone.end();
        // end instrumentation: trace zone: irradiance sampling --------------------------------------------------------- |

        try request.evaluation_cache.reserveIrradiance(irradianceCacheCapacity(request.wavelength_sampling));
        for (request.wavelength_sampling.rows, 0..) |plan, index| {
            output.scratch[index] = try SpectralEval.integrateIrradianceAtNominal(
                request.scene,
                request.prepared,
                plan.irradiance_wavelength_nm,
                request.setup.safe_span,
                request.evaluation_cache,
                &plan.irradiance_integration,
                request.wavelength_sampling.kernel_storage,
            );
        }
    }
    if (request.setup.uses_integrated_irradiance_sampling) {
        @memcpy(output.irradiance, output.scratch);
    } else {

        // instrumentation: trace zone: irradiance convolution ---------------------------------------------------------- |
        // captures: irradiance slit convolution wall time                                                                |
        // why: separates solar-channel instrument-kernel cost from sampling.                                             |
        const trace_start_ns = tracePhaseStart(request.trace_phase_timing);
        defer tracePhaseFinish(request.trace_phase_timing, trace_start_ns, "irradiance_convolution_ns");
        const zone = Trace.staticZone(@src(), "simulate.irradiance_convolution");
        defer zone.end();
        // end instrumentation: trace zone: irradiance convolution ------------------------------------------------------ |

        try convolution.apply(output.scratch, request.setup.irradiance_slit_kernel[0..], output.irradiance);
    }
    {

        // instrumentation: trace zone: irradiance postprocess ---------------------------------------------------------- |
        // captures: irradiance channel postprocess wall time                                                             |
        // why: keeps solar calibration cost visible before reflectance assembly.                                         |
        const trace_start_ns = tracePhaseStart(request.trace_phase_timing);
        defer tracePhaseFinish(request.trace_phase_timing, trace_start_ns, "irradiance_postprocess_ns");
        const zone = Trace.staticZone(@src(), "simulate.irradiance_postprocess");
        defer zone.end();
        // end instrumentation: trace zone: irradiance postprocess ------------------------------------------------------ |

        try calibration.applySignal(
            request.setup.irradiance_calibration,
            output.irradiance,
            output.irradiance,
        );
    }
}

fn irradianceCacheCapacity(wavelength_sampling: WavelengthSampling.WavelengthSamplingTable) usize {
    // irradianceCacheCapacity -------------------------------------------------------------------------------------------|
    // Count high-resolution irradiance samples so the exact-wavelength cache can reserve before hot inserts.             |
    // -------------------------------------------------------------------------------------------------------------------|

    var count: usize = 0;
    for (wavelength_sampling.rows) |plan| {
        count += plan.irradiance_integration.activeSampleCount();
    }
    return count;
}

fn assembleReflectance(
    scene: *const Scene,
    sample_count: usize,
    buffers: Storage.Buffers,
    summary: *RunningSummary,
    trace_phase_timing: ?*Storage.TracePhaseTiming,
) void {
    // assembleReflectance -----------------------------------------------------------------------------------------------|
    // Convert calibrated radiance and irradiance into top-of-atmosphere reflectance for each output sample,              |
    // while accumulating summary means.                                                                                  |
    //                                                                                                                    |
    // math                                                                                                               |
    //   rho_i = pi * L_i / max(E0_i * mu0, 1e-9)                                                                         |
    //                                                                                                                    |
    // relation to forward scaling                                                                                        |
    //   spectral_forward.zig uses L = rho * mu0 * E0 / pi. This step inverts that convention after the                   |
    //   instrument has produced calibrated radiance and irradiance on the product grid.                                  |
    //                                                                                                                    |
    // clamp                                                                                                              |
    //   1e-9 prevents a near-zero irradiance denominator from producing Inf/NaN reflectance. Telemetry records           |
    //   how often the clamp changes the raw denominator.                                                                 |
    // -------------------------------------------------------------------------------------------------------------------|

    {

        // instrumentation: trace zone: reflectance assembly ------------------------------------------------------------ |
        // captures: reflectance assembly wall time                                                                       |
        // why: isolates final radiance/irradiance-to-reflectance conversion.                                             |
        const trace_start_ns = tracePhaseStart(trace_phase_timing);
        defer tracePhaseFinish(trace_phase_timing, trace_start_ns, "reflectance_assembly_ns");
        const zone = Trace.staticZone(@src(), "simulate.reflectance_assembly");
        defer zone.end();
        // end instrumentation: trace zone: reflectance assembly -------------------------------------------------------- |

        const solar_cosine = scene.geometry.solarCosineAtAltitude(0.0);
        var denominator_clamp_count: usize = 0;
        var min_denominator = std.math.inf(f64);
        var max_reflectance = -std.math.inf(f64);
        for (0..sample_count) |index| {
            const denominator_raw = buffers.irradiance[index] * solar_cosine;
            const denominator = @max(denominator_raw, 1e-9);
            buffers.reflectance[index] = (buffers.radiance[index] * std.math.pi) / denominator;

            // instrumentation: calculation telemetry: reflectance extrema ---------------------------------------------- |
            // captures: denominator clamps and final reflectance extrema                                                 |
            // why: identifies numerically fragile spectra where simple pruning would change outputs.                     |
            if (Telemetry.enabled) {
                if (denominator_raw <= 1e-9) denominator_clamp_count += 1;
                min_denominator = @min(min_denominator, denominator_raw);
                max_reflectance = @max(max_reflectance, buffers.reflectance[index]);
            }
            // end instrumentation: calculation telemetry: reflectance extrema ------------------------------------------ |

            summary.addReflectanceSample(
                buffers.radiance[index],
                buffers.irradiance[index],
                buffers.reflectance[index],
            );
        }

        // instrumentation: calculation telemetry: reflectance assembly summary ----------------------------------------- |
        // captures: per-spectrum reflectance assembly summary                                                            |
        // why: stores one compact row for studying clamp incidence against scene geometry.                               |
        if (Telemetry.enabled) {
            Telemetry.reflectanceAssembly(
                sample_count,
                denominator_clamp_count,
                if (sample_count == 0) 0.0 else min_denominator,
                if (sample_count == 0) 0.0 else max_reflectance,
            );
        }
        // end instrumentation: calculation telemetry: reflectance assembly summary ------------------------------------- |

    }
}

fn processJacobianSamples(
    derivative_state_mask: jacobian.StateMask,
    setup: SimulationSetup,
    buffers: Storage.Buffers,
    summary: *RunningSummary,
    trace_phase_timing: ?*Storage.TracePhaseTiming,
) Storage.Error!?jacobian.Vector {
    // processJacobianSamples --------------------------------------------------------------------------------------------|
    // Postprocess active radiance Jacobian columns after radiance sampling has filled the state-major buffer.            |
    //                                                                                                                    |
    // math per active state x                                                                                            |
    //   J_raw_i(x) = dL_raw_i/dx                                                                                         |
    //   J_out_i(x) = d channel_calibration(convolution(L_raw)_i) / dx                                                    |
    //              = calibration_derivative(convolution(J_raw)_i) for non-integrated radiance sampling                   |
    //              = calibration_derivative(J_raw_i)              for already-integrated radiance sampling               |
    //                                                                                                                    |
    // summary                                                                                                            |
    //   mean_jacobian[x] = sum_i J_out_i(x) / sample_count                                                               |
    // -------------------------------------------------------------------------------------------------------------------|

    if (buffers.jacobian) |jacobian_buffer| {
        {

            // instrumentation: trace zone: Jacobian processing --------------------------------------------------------- |
            // captures: Jacobian convolution, calibration, and reduction wall time                                       |
            // why: separates derivative-column postprocessing from RTM evaluation.                                       |
            const trace_start_ns = tracePhaseStart(trace_phase_timing);
            defer tracePhaseFinish(trace_phase_timing, trace_start_ns, "jacobian_processing_ns");
            const zone = Trace.staticZone(@src(), "simulate.jacobian_processing");
            defer zone.end();
            // end instrumentation: trace zone: Jacobian processing ----------------------------------------------------- |

            const active_jacobians = ActiveJacobianStates.init(buffers.jacobian_state_mask);
            if (active_jacobians.count == 0 or
                jacobian_buffer.len != setup.sample_count * active_jacobians.count)
            {
                return error.ShapeMismatch;
            }
            if (!setup.uses_integrated_radiance_sampling) {
                for (0..active_jacobians.count) |active_index| {
                    const state = active_jacobians.at(active_index) orelse return error.ShapeMismatch;

                    if (!jacobian.includes(derivative_state_mask, state)) return error.ShapeMismatch;
                    const column = jacobianColumn(jacobian_buffer, setup.sample_count, active_index);
                    try convolution.apply(column, setup.radiance_slit_kernel[0..], buffers.scratch_aux);
                    @memcpy(column, buffers.scratch_aux);
                }
            }
            for (0..active_jacobians.count) |active_index| {
                const state = active_jacobians.at(active_index) orelse return error.ShapeMismatch;

                if (!jacobian.includes(derivative_state_mask, state)) return error.ShapeMismatch;
                const column = jacobianColumn(jacobian_buffer, setup.sample_count, active_index);
                try calibration.applySignalDerivative(
                    setup.radiance_calibration,
                    column,
                    column,
                );
            }
            for (0..active_jacobians.count) |active_index| {
                const state = active_jacobians.at(active_index) orelse return error.ShapeMismatch;
                const column = jacobianColumn(jacobian_buffer, setup.sample_count, active_index);
                const state_index = jacobian.stateIndex(state);
                var column_sum: f64 = 0.0;

                var column_max_abs: f64 = 0.0;
                for (column) |value| {
                    column_sum += value;

                    // instrumentation: calculation telemetry: Jacobian max magnitude ----------------------------------- |
                    // captures: maximum absolute derivative value per active state                                       |
                    // why: flags near-zero sensitivity columns that may be safe to skip.                                 |
                    if (Telemetry.enabled) column_max_abs = @max(column_max_abs, @abs(value));
                    // end instrumentation: calculation telemetry: Jacobian max magnitude ------------------------------- |

                }
                summary.jacobian_sum[state_index] += column_sum;

                // instrumentation: calculation telemetry: Jacobian column summary -------------------------------------- |
                // captures: derivative column sum, mean, and max magnitude                                               |
                // why: relates retrieval-state sensitivity to final spectrum impact.                                     |
                if (Telemetry.enabled) {
                    Telemetry.jacobianColumn(
                        state_index,
                        column_sum,
                        if (setup.sample_count == 0) 0.0 else column_sum / @as(f64, @floatFromInt(setup.sample_count)),
                        column_max_abs,
                    );
                }
                // end instrumentation: calculation telemetry: Jacobian column summary ---------------------------------- |

            }
            return jacobian.scale(summary.jacobian_sum, 1.0 / @as(f64, @floatFromInt(setup.sample_count)));
        }
    }
    return null;
}

fn wavelengthPlanKey(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
) u64 {
    // wavelengthPlanKey -------------------------------------------------------------------------------------------------|
    // Hash every input that changes wavelength sampling or forward-miss structure. A matching key means the              |
    // retained wavelength plan can be reused without rebuilding instrument kernels or miss indexes.                      |
    // -------------------------------------------------------------------------------------------------------------------|

    var hash = std.hash.Wyhash.init(0x4f32_4132_7761_7665);
    updateFloat(&hash, scene.spectral_grid.start_nm);
    updateFloat(&hash, scene.spectral_grid.end_nm);
    updateInt(&hash, scene.spectral_grid.sample_count);
    updateInt(&hash, @intFromEnum(scene.observation_model.sampling));
    updateFloat(&hash, scene.observation_model.wavelength_shift_nm);
    updateFloatSlice(&hash, scene.observation_model.measured_wavelengths_nm);
    updateAdaptiveReferenceGrid(&hash, scene.observation_model.adaptive_reference_grid);
    const spectroscopy_plan_key = if (prepared.spectroscopy_plan_key != 0)
        prepared.spectroscopy_plan_key
    else
        prepared.computeSpectroscopyPlanKey();
    updateInt(&hash, spectroscopy_plan_key);
    updateChannelControls(&hash, scene, .radiance);
    updateChannelControls(&hash, scene, .irradiance);
    return hash.final();
}

fn profileSpectroscopyCacheKey(
    prepared: *const OpticsPreparation.PreparedOpticalState,
    forward_misses: []const SpectralEval.ForwardCacheMiss,
) u64 {
    // profileSpectroscopyCacheKey ---------------------------------------------------------------------------------------|
    // Hash the exact forward-miss wavelengths plus spectroscopy profile inputs. A matching key means cached              |
    // profile-node spectroscopy rows still correspond to the miss list.                                                  |
    // -------------------------------------------------------------------------------------------------------------------|

    var hash = std.hash.Wyhash.init(0x4f32_4132_7072_6f66);
    updateInt(&hash, forward_misses.len);
    for (forward_misses) |miss| {
        updateFloat(&hash, miss.wavelength_nm);
    }
    const spectroscopy_profile_key = if (prepared.spectroscopy_profile_cache_inputs_key != 0)
        prepared.spectroscopy_profile_cache_inputs_key
    else
        prepared.computeSpectroscopyProfileCacheInputsKey();
    updateInt(&hash, spectroscopy_profile_key);
    return hash.final();
}

fn updateChannelControls(hash: *std.hash.Wyhash, scene: *const Scene, channel: SpectralChannel) void {
    // updateChannelControls ---------------------------------------------------------------------------------------------|
    // Add all channel controls that influence wavelength shifts, line-shape kernels, or integration mode to              |
    // the wavelength-plan hash.                                                                                          |
    // -------------------------------------------------------------------------------------------------------------------|

    const controls = scene.observation_model.resolvedChannelControls(channel);
    updateInt(hash, @intFromEnum(channel));
    updateFloat(hash, controls.wavelength_shift_nm);
    const response = controls.response;
    updateInt(hash, response.explicit);
    updateInt(hash, @intFromEnum(response.slit_index));
    updateFloat(hash, response.fwhm_nm);
    updateFloat(hash, response.amplitude);
    updateFloat(hash, response.scale);
    updateFloat(hash, response.phase_deg);
    updateInt(hash, @intFromEnum(response.builtin_line_shape));
    updateInt(hash, @intFromEnum(response.integration_mode));
    updateFloat(hash, response.high_resolution_step_nm);
    updateFloat(hash, response.high_resolution_half_span_nm);
    updateInt(hash, response.instrument_line_shape.sample_count);
    const line_shape_sample_count = response.instrument_line_shape.sample_count;
    const line_shape_offset_count = @min(
        response.instrument_line_shape.offsets_nm.len,
        line_shape_sample_count,
    );
    const line_shape_weight_count = @min(
        response.instrument_line_shape.weights.len,
        line_shape_sample_count,
    );
    updateFloatSlice(hash, response.instrument_line_shape.offsets_nm[0..line_shape_offset_count]);
    updateFloatSlice(hash, response.instrument_line_shape.weights[0..line_shape_weight_count]);
    updateInt(hash, response.instrument_line_shape_table.nominal_count);
    updateInt(hash, response.instrument_line_shape_table.sample_count);
    const table_nominal_count = @min(
        response.instrument_line_shape_table.nominal_wavelengths_nm.len,
        response.instrument_line_shape_table.nominal_count,
    );
    const table_offset_count = @min(
        response.instrument_line_shape_table.offsets_nm.len,
        response.instrument_line_shape_table.sample_count,
    );
    updateFloatSlice(
        hash,
        response.instrument_line_shape_table.nominal_wavelengths_nm[0..table_nominal_count],
    );
    updateFloatSlice(
        hash,
        response.instrument_line_shape_table.offsets_nm[0..table_offset_count],
    );
    const table_weight_count = @min(
        response.instrument_line_shape_table.weights.len,
        @as(usize, response.instrument_line_shape_table.nominal_count) *
            @as(usize, response.instrument_line_shape_table.sample_count),
    );
    updateFloatSlice(hash, response.instrument_line_shape_table.weights[0..table_weight_count]);
}

fn updateAdaptiveReferenceGrid(
    hash: *std.hash.Wyhash,
    adaptive: @import("../../../input/Instrument.zig").AdaptiveReferenceGrid,
) void {
    // updateAdaptiveReferenceGrid ---------------------------------------------------------------------------------------|
    // Add adaptive-grid controls that can change integration sample offsets around strong spectral lines.                |
    // -------------------------------------------------------------------------------------------------------------------|

    updateInt(hash, adaptive.points_per_fwhm);
    updateInt(hash, adaptive.strong_line_min_divisions);
    updateInt(hash, adaptive.strong_line_max_divisions);
}

fn updateFloatSlice(hash: *std.hash.Wyhash, values: []const f64) void {
    // updateFloatSlice --------------------------------------------------------------------------------------------------|
    // Add a float slice length and raw f64 bytes to a plan hash. The length keeps prefix-equal slices distinct.          |
    // -------------------------------------------------------------------------------------------------------------------|

    updateInt(hash, values.len);
    hash.update(std.mem.sliceAsBytes(values));
}

fn updateFloat(hash: *std.hash.Wyhash, value: f64) void {
    // updateFloat -------------------------------------------------------------------------------------------------------|
    // Add one f64 value to a plan hash using its exact bit pattern.                                                      |
    // -------------------------------------------------------------------------------------------------------------------|

    var bits = @as(u64, @bitCast(value));
    hash.update(std.mem.asBytes(&bits));
}

fn updateInt(hash: *std.hash.Wyhash, value: anytype) void {
    // updateInt ---------------------------------------------------------------------------------------------------------|
    // Add one integer or enum backing value to a plan hash.                                                              |
    // -------------------------------------------------------------------------------------------------------------------|

    var bits = value;
    hash.update(std.mem.asBytes(&bits));
}

fn jacobianColumn(buffer: []f64, sample_count: usize, active_index: usize) []f64 {
    // jacobianColumn ----------------------------------------------------------------------------------------------------|
    // Return one state-major Jacobian column from the workspace buffer.                                                  |
    // -------------------------------------------------------------------------------------------------------------------|

    return buffer[active_index * sample_count ..][0..sample_count];
}

fn writeJacobianSample(
    buffer: []f64,
    active_jacobians: ActiveJacobianStates,
    sample_count: usize,
    sample_index: usize,
    values: jacobian.Vector,
) void {
    // writeJacobianSample -----------------------------------------------------------------------------------------------|
    // Copy one full LABOS Jacobian vector into the compact active-state workspace columns for one sample row.            |
    // -------------------------------------------------------------------------------------------------------------------|

    for (0..active_jacobians.count) |active_index| {
        const state = active_jacobians.at(active_index) orelse unreachable;
        buffer[active_index * sample_count + sample_index] = values[jacobian.stateIndex(state)];
    }
}

pub fn simulate(
    allocator: Allocator,
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    buffers: Storage.Buffers,
) Storage.Error!Types.InstrumentGridSummary {
    // simulate ----------------------------------------------------------------------------------------------------------|
    // One-shot internal route for callers that already provide output buffers but not a reusable spectral                |
    // evaluation cache.                                                                                                  |
    // -------------------------------------------------------------------------------------------------------------------|

    var evaluation_cache = SpectralEval.SpectralEvaluationCache.init(allocator);
    defer evaluation_cache.deinit();
    evaluation_cache.reset();
    return simulateInternal(allocator, scene, rtm_config, prepared, buffers, &evaluation_cache, null);
}

pub fn simulateSummary(
    allocator: Allocator,
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
) Storage.Error!Types.InstrumentGridSummary {
    // simulateSummary ---------------------------------------------------------------------------------------------------|
    // Convenience summary route with temporary ProductStorage.                                                           |
    // -------------------------------------------------------------------------------------------------------------------|

    var storage: Storage.ProductStorage = .{};
    defer storage.deinit(allocator);
    return simulateSummaryWithWorkspace(allocator, &storage, scene, rtm_config, prepared);
}

pub fn simulateSummaryWithWorkspace(
    allocator: Allocator,
    storage: *Storage.ProductStorage,
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
) Storage.Error!Types.InstrumentGridSummary {
    // simulateSummaryWithWorkspace --------------------------------------------------------------------------------------|
    // Summary route that reuses ProductStorage. Very long output grids are capped because summary mode only              |
    // reports means and should stay lightweight.                                                                         |
    // -------------------------------------------------------------------------------------------------------------------|

    var summary_scene = scene.*;

    // Summary mode truncates very long spectral grids while the full product route preserves every sample.
    if (summary_scene.spectral_grid.sample_count > max_summary_samples) {
        summary_scene.spectral_grid.sample_count = max_summary_samples;
    }
    return simulateInternal(
        allocator,
        &summary_scene,
        rtm_config,
        prepared,
        try storage.buffers(allocator, &summary_scene, rtm_config),
        try storage.spectralCache(allocator),
        storage,
    );
}
