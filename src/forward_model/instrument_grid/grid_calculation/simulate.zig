const std = @import("std");
const SpectralChannel = @import("../../../input/Instrument.zig").SpectralChannel;
const Scene = @import("../../../input/Scene.zig").Scene;
const OpticsPreparation = @import("../../optical_properties/root.zig");
const calibration = @import("../spectral_math/calibration.zig");
const convolution = @import("../spectral_math/convolution.zig");
const grid = @import("../spectral_math/grid.zig");
const common = @import("../../radiative_transfer/root.zig");
const jacobian = @import("../../jacobian/root.zig");
const Postprocess = @import("postprocess.zig");
const WavelengthSampling = @import("wavelength_sampling.zig");
const SpectralEval = @import("spectral_eval.zig");
const SpectroscopyState = @import("../../optical_properties/state_build/state_spectroscopy.zig");
const Plan = @import("wavelength_plan.zig");
const Types = @import("types.zig");
const Storage = @import("storage.zig");
const Telemetry = @import("../../calculation_telemetry.zig");
const Trace = @import("../../performance_trace.zig");
const work_partition = @import("../../work_partition.zig");

const Allocator = std.mem.Allocator;
const max_summary_samples: u32 = 128;
const profile_cache_build_chunk_size: usize = 8;

// layout(64-bit):
//   size: 216 B, align: 8 B
//   field storage: 210 B across 10 fields; largest: resolved_axis=40 B, radiance_slit_kernel=40 B, irradiance_slit_kernel=40 B; padding: 6 B (48 bits)
//   unused bits: 48 padding + 14 bool-storage slack = 62 bits
//   inline arrays: radiance_slit_kernel:[5]f64=40 B, irradiance_slit_kernel:[5]f64=40 B
//   cache span: 4 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 216 B (0.211 KiB); total = per instance * live instance count
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

// layout(64-bit):
//   size: 240 B, align: 8 B
//   field storage: 240 B across 7 fields; largest: forward_miss_plan=48 B, owned_forward_miss_plan=48 B, wavelength_sampling=48 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: wavelength_sampling, forward_miss_plan, forward_results, profile_spectroscopy_caches, and owned fields carry references/descriptors
//   cache span: 4 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 240 B (0.234 KiB); total also includes referenced storage above
const ResolvedSimulationPlan = struct {
    wavelength_sampling: WavelengthSampling.WavelengthSamplingTable = .{},
    forward_miss_plan: Plan.ForwardMissPlan = .{},
    forward_results: []const SpectralEval.ForwardIntegratedSample = &.{},
    profile_spectroscopy_caches: []const SpectroscopyState.ProfileNodeSpectroscopyCache = &.{},
    owned_wavelength_sampling: WavelengthSampling.OwnedWavelengthSampling = .{},
    owned_forward_miss_plan: Plan.OwnedForwardMissPlan = .{},
    owned_forward_results: []SpectralEval.ForwardIntegratedSample = &.{},

    fn deinit(self: *ResolvedSimulationPlan, allocator: Allocator) void {
        self.owned_wavelength_sampling.deinit(allocator);
        self.owned_forward_miss_plan.deinit(allocator);
        allocator.free(self.owned_forward_results);
        self.* = undefined;
    }
};

// Active Jacobian states resolved once per simulation from the route/storage mask.
// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: count=8 B, states=3 B; padding: 5 B (40 bits)
//   unused bits: 40 padding + 0 bool-storage slack = 40 bits
//   inline arrays: states:[3]jacobian.State=3 B
//   count: one stack value in Jacobian-producing simulations
//   footprint: per instance = 16 B (0.016 KiB)
const ActiveJacobianStates = struct {
    count: usize = 0,
    states: [jacobian.state_count]jacobian.State = undefined,

    fn init(mask: jacobian.StateMask) ActiveJacobianStates {
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
        if (active_index >= self.count) return null;
        return self.states[active_index];
    }
};

// layout(64-bit):
//   size: 56 B, align: 8 B
//   field storage: 56 B across 5 fields; largest: jacobian_sum=24 B, radiance_sum=8 B, irradiance_sum=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   inline arrays: jacobian_sum:[3]f64=24 B
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 56 B (0.055 KiB); total = per instance * live instance count
const RunningSummary = struct {
    radiance_sum: f64,
    irradiance_sum: f64,
    reflectance_sum: f64,
    jacobian_sum: jacobian.Vector,

    fn init() RunningSummary {
        return .{
            .radiance_sum = 0.0,
            .irradiance_sum = 0.0,
            .reflectance_sum = 0.0,
            .jacobian_sum = jacobian.zero(),
        };
    }

    fn addReflectanceSample(self: *RunningSummary, radiance: f64, irradiance: f64, reflectance: f64) void {
        // math: running sums store sum L_i, sum E0_i, and sum rho_i for later arithmetic means.
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
        const denominator = @as(f64, @floatFromInt(sample_count));
        return .{
            .sample_count = @intCast(sample_count),
            .wavelength_start_nm = wavelengths[0],
            .wavelength_end_nm = wavelengths[sample_count - 1],
            // math: mean(y) = (sum_i y_i) / N for radiance, irradiance, reflectance, and any active Jacobian vector.
            .mean_radiance = self.radiance_sum / denominator,
            .mean_irradiance = self.irradiance_sum / denominator,
            .mean_reflectance = self.reflectance_sum / denominator,
            .mean_jacobian = mean_jacobian,
        };
    }
};

// layout(64-bit):
//   size: 64 B, align: 8 B
//   field storage: 64 B across 6 fields; largest: forward_misses=16 B, caches=16 B, prepared=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: prepared, forward_misses, caches carry references/descriptors; referenced storage is not included in size
//   cache span: 1 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 64 B (0.062 KiB); total also includes referenced storage above
const ProfileCacheBuildWorker = struct {
    prepared: *const OpticsPreparation.PreparedOpticalState,
    forward_misses: []const SpectralEval.ForwardCacheMiss,
    caches: []SpectroscopyState.ProfileNodeSpectroscopyCache,
    start_index: usize,
    end_index: usize,
    worker_index: usize = 0,
};

fn profileCacheBuildWorkerMain(worker: *ProfileCacheBuildWorker) void {
    var thread_name_buffer: [64]u8 = undefined;
    const thread_name = std.fmt.bufPrintZ(
        &thread_name_buffer,
        "zdisamar-profile-cache-{d}",
        .{worker.worker_index},
    ) catch "zdisamar-profile-cache";
    Trace.setThreadName(thread_name);

    const zone = Trace.staticZone(@src(), "profile_spectroscopy_cache.worker");
    zone.value(@intCast(worker.worker_index));
    defer zone.end();

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
    storage: *Storage.SummaryStorage,
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
) Storage.Error!void {
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

    const plan_key = wavelengthPlanKey(scene, prepared, implementations);
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
        implementations.instrument.calibrationForScene(scene, .radiance),
        implementations.instrument.calibrationForScene(scene, .irradiance),
        implementations,
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
    storage: *Storage.SummaryStorage,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    forward_misses: []const SpectralEval.ForwardCacheMiss,
) ![]const SpectroscopyState.ProfileNodeSpectroscopyCache {
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
    const zone = Trace.staticZone(@src(), "profile_spectroscopy_cache.build");
    zone.value(@intCast(forward_misses.len));
    defer zone.end();

    const caches = try allocator.alloc(SpectroscopyState.ProfileNodeSpectroscopyCache, forward_misses.len);
    errdefer allocator.free(caches);

    const worker_count = SpectralEval.preferredForwardWorkerCount(forward_misses.len);
    if (worker_count == 1) {
        for (forward_misses, caches) |miss, *cache| {
            cache.* = SpectroscopyState.ProfileNodeSpectroscopyCache.init(prepared, miss.wavelength_nm);
        }
        return caches;
    }

    const workers = try allocator.alloc(ProfileCacheBuildWorker, worker_count);
    defer allocator.free(workers);
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

    const threads = try allocator.alloc(std.Thread, worker_count - 1);
    defer allocator.free(threads);
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

// hot path:
//   when: once per product simulation in forward and retrieval runs
//   work: sequences wavelength planning, forward-cache fill, convolution, noise, and Jacobian processing
//   data: instrument buffers, spectral evaluation cache, wavelength plan storage, active derivative mask
//   follow: downstream calls into fillRadianceSamples, fillIrradianceSamples, and processJacobianSamples
pub fn simulateInternal(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
    buffers: Storage.Buffers,
    evaluation_cache: *SpectralEval.SpectralEvaluationCache,
    wavelength_plan_storage: ?*Storage.SummaryStorage,
) Storage.Error!Types.InstrumentGridSummary {
    const simulate_zone = Trace.staticZone(@src(), "simulate.product");
    defer simulate_zone.end();

    const setup = try buildSimulationSetup(scene, route, prepared, implementations, buffers);
    var simulation_plan = try resolveSimulationPlan(
        allocator,
        scene,
        prepared,
        implementations,
        setup,
        wavelength_plan_storage,
    );
    defer simulation_plan.deinit(allocator);
    try prefetchSimulationPlan(
        allocator,
        scene,
        route,
        prepared,
        implementations,
        setup,
        &simulation_plan,
        wavelength_plan_storage,
    );

    var summary = RunningSummary.init();
    _ = try validateTransportBuffers(scene, route, prepared, buffers);
    try fillRadianceSamples(
        route,
        setup,
        simulation_plan.wavelength_sampling,
        simulation_plan.forward_miss_plan,
        simulation_plan.forward_results,
        buffers,
    );
    try fillIrradianceSamples(
        scene,
        prepared,
        setup,
        simulation_plan.wavelength_sampling,
        buffers,
        evaluation_cache,
    );
    assembleReflectance(scene, setup.sample_count, buffers, &summary);
    const mean_jacobian = try processJacobianSamples(
        route.derivative_state_mask,
        setup,
        buffers,
        &summary,
    );
    return summary.toInstrumentGridSummary(
        setup.sample_count,
        buffers.wavelengths,
        mean_jacobian,
    );
}

fn buildSimulationSetup(
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
    buffers: Storage.Buffers,
) Storage.Error!SimulationSetup {
    try scene.validate();
    const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
    try Storage.validateBuffers(scene, route, sample_count, buffers);

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

    const radiance_calibration = implementations.instrument.calibrationForScene(scene, .radiance);
    const irradiance_calibration = implementations.instrument.calibrationForScene(scene, .irradiance);
    const radiance_slit_kernel = implementations.instrument.slitKernelForScene(scene, .radiance);
    const irradiance_slit_kernel = implementations.instrument.slitKernelForScene(scene, .irradiance);
    const uses_integrated_radiance_sampling = implementations.instrument.usesIntegratedSampling(scene, .radiance);
    const uses_integrated_irradiance_sampling = implementations.instrument.usesIntegratedSampling(scene, .irradiance);
    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    // math: safe_span = max(lambda_end - lambda_start, 1 nm) for normalized carrier and support interpolation.
    const safe_span = if (span_nm <= 0.0) 1.0 else span_nm;
    Trace.plotU("output_wavelengths", @intCast(sample_count));
    const plan_key = wavelengthPlanKey(scene, prepared, implementations);

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

// hot path:
//   when: once per simulation, with cached storage reused across OE iterations
//   work: resolves wavelength sampling, unique forward misses, and profile spectroscopy caches
//   data: wavelength sampling rows, forward miss keys, profile-node spectroscopy cache array
//   follow: plan storage reuse and cache invalidation before prefetchSimulationPlan
fn resolveSimulationPlan(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
    setup: SimulationSetup,
    wavelength_plan_storage: ?*Storage.SummaryStorage,
) Storage.Error!ResolvedSimulationPlan {
    var plan: ResolvedSimulationPlan = .{};
    errdefer plan.deinit(allocator);

    plan.wavelength_sampling = blk: {
        const zone = Trace.staticZone(@src(), "simulate.wavelength_sampling");
        defer zone.end();

        if (wavelength_plan_storage) |storage| {
            if (storage.wavelength_plan_valid and storage.wavelength_plan_key == setup.plan_key) {
                break :blk storage.wavelength_sampling.view();
            }
            storage.invalidateWavelengthPlan(allocator);
            storage.wavelength_sampling = try WavelengthSampling.buildWavelengthSampling(
                allocator,
                scene,
                prepared,
                &setup.resolved_axis,
                setup.radiance_calibration,
                setup.irradiance_calibration,
                implementations,
            );
            storage.wavelength_plan_key = setup.plan_key;
            storage.wavelength_plan_valid = true;
            break :blk storage.wavelength_sampling.view();
        }
        plan.owned_wavelength_sampling = try WavelengthSampling.buildWavelengthSampling(
            allocator,
            scene,
            prepared,
            &setup.resolved_axis,
            setup.radiance_calibration,
            setup.irradiance_calibration,
            implementations,
        );
        break :blk plan.owned_wavelength_sampling.view();
    };
    plan.forward_miss_plan = blk: {
        const zone = Trace.staticZone(@src(), "simulate.forward_miss_collection");
        defer zone.end();

        if (wavelength_plan_storage) |storage| {
            if (!storage.forward_miss_plan_valid) {
                storage.forward_miss_plan = try WavelengthSampling.buildForwardMissPlan(
                    allocator,
                    plan.wavelength_sampling,
                );
                storage.forward_miss_plan_valid = true;
            }
            break :blk storage.forward_miss_plan.view();
        }
        plan.owned_forward_miss_plan = try WavelengthSampling.buildForwardMissPlan(
            allocator,
            plan.wavelength_sampling,
        );
        break :blk plan.owned_forward_miss_plan.view();
    };
    plan.profile_spectroscopy_caches = blk: {
        const zone = Trace.staticZone(@src(), "simulate.profile_spectroscopy_cache");
        defer zone.end();

        if (wavelength_plan_storage) |storage| {
            break :blk try ensureProfileSpectroscopyCaches(allocator, storage, prepared, plan.forward_miss_plan.misses);
        }
        break :blk &.{};
    };
    return plan;
}

fn prefetchSimulationPlan(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
    setup: SimulationSetup,
    simulation_plan: *ResolvedSimulationPlan,
    wavelength_plan_storage: ?*Storage.SummaryStorage,
) Storage.Error!void {
    {
        const zone = Trace.staticZone(@src(), "simulate.forward_prefetch_wall");
        zone.value(@intCast(simulation_plan.forward_miss_plan.misses.len));
        defer zone.end();
        const worker_count = SpectralEval.preferredForwardWorkerCount(simulation_plan.forward_miss_plan.misses.len);
        const thread_pool = if (wavelength_plan_storage) |storage|
            storage.forwardPrefetchPool(allocator, worker_count)
        else
            null;
        const results = if (wavelength_plan_storage) |storage|
            try storage.forwardResultBuffer(allocator, simulation_plan.forward_miss_plan.misses.len)
        else blk: {
            simulation_plan.owned_forward_results = try allocator.alloc(
                SpectralEval.ForwardIntegratedSample,
                simulation_plan.forward_miss_plan.misses.len,
            );
            break :blk simulation_plan.owned_forward_results;
        };
        try SpectralEval.prefetchForwardSamples(
            allocator,
            scene,
            route,
            prepared,
            implementations,
            setup.safe_span,
            simulation_plan.forward_miss_plan.misses,
            simulation_plan.profile_spectroscopy_caches,
            results,
            thread_pool,
        );
        simulation_plan.forward_results = results;
    }
}

fn validateTransportBuffers(
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    buffers: Storage.Buffers,
) Storage.Error!usize {
    const transport_layer_count = Storage.resolvedTransportLayerCount(route, prepared);
    if (buffers.layer_inputs.len < transport_layer_count) {
        return error.ShapeMismatch;
    }
    if (Storage.routeMayUseSourceInterfaces(scene, route) and
        buffers.source_interfaces.len < transport_layer_count + 1)
    {
        return error.ShapeMismatch;
    }
    if (Storage.routeUsesRtmQuadrature(route) and
        buffers.rtm_quadrature_levels.len < transport_layer_count + 1)
    {
        return error.ShapeMismatch;
    }
    if (Storage.routeUsesPseudoSphericalGrid(route) and
        buffers.pseudo_spherical_level_starts.len < transport_layer_count + 1)
    {
        return error.ShapeMismatch;
    }
    return transport_layer_count;
}

// hot path:
//   when: once per output wavelength after forward misses have been prefetched
//   work: integrates radiance samples, writes wavelength/radiance buffers, and records Jacobian rows
//   data: wavelength sampling rows, dense forward results, direct miss-index rows, jacobian buffer
//   follow: SpectralEval.integratePrefetchedForwardAtNominal and convolution/postprocess passes
//   math: L_out = C_slit(sum_j w_ij F(lambda_i + delta_ij)) followed by channel calibration
fn fillRadianceSamples(
    route: common.Route,
    setup: SimulationSetup,
    wavelength_sampling: WavelengthSampling.WavelengthSamplingTable,
    forward_miss_plan: Plan.ForwardMissPlan,
    forward_results: []const SpectralEval.ForwardIntegratedSample,
    buffers: Storage.Buffers,
) Storage.Error!void {
    const active_jacobians = if (buffers.jacobian != null)
        ActiveJacobianStates.init(buffers.jacobian_state_mask)
    else
        ActiveJacobianStates{};

    {
        const zone = Trace.staticZone(@src(), "simulate.radiance_cache_integration");
        defer zone.end();
        for (wavelength_sampling.rows, 0..) |plan, index| {
            const nominal_wavelength_nm = plan.nominal_wavelength_nm;
            buffers.wavelengths[index] = nominal_wavelength_nm;

            if (index >= forward_miss_plan.rows.len) return error.ShapeMismatch;
            const integrated = try SpectralEval.integratePrefetchedForwardAtNominal(
                route,
                forward_results,
                forward_miss_plan.rows[index],
                forward_miss_plan.sample_indices,
                &plan.radiance_integration,
                wavelength_sampling.kernel_storage,
            );
            buffers.scratch[index] = integrated.radiance;
            if (buffers.jacobian) |jacobian_buffer| {
                writeJacobianSample(
                    jacobian_buffer,
                    active_jacobians,
                    setup.sample_count,
                    index,
                    integrated.jacobian,
                );
            }
        }
    }
    if (setup.uses_integrated_radiance_sampling) {
        // DECISION:
        //   Integrated sampling bypasses slit convolution because the
        //   instrument already performed the spectral integration.
        @memcpy(buffers.radiance, buffers.scratch);
    } else {
        const zone = Trace.staticZone(@src(), "simulate.radiance_convolution");
        defer zone.end();
        try convolution.apply(buffers.scratch, setup.radiance_slit_kernel[0..], buffers.radiance);
    }
    {
        const zone = Trace.staticZone(@src(), "simulate.radiance_postprocess");
        defer zone.end();
        try Postprocess.applyChannelCorrections(
            setup.radiance_calibration,
            buffers.radiance,
        );
    }
}

// hot path:
//   when: once per output wavelength for irradiance sampling
//   work: integrates irradiance samples and applies convolution plus channel postprocess
//   data: irradiance integration plans, irradiance cache, scratch buffer, output irradiance buffer
//   follow: SpectralEval.integrateIrradianceAtNominal and calibration-only channel corrections
//   math: E0_out = C_slit(sum_j w_ij E0(lambda_i + delta_ij)) followed by channel calibration
fn fillIrradianceSamples(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    setup: SimulationSetup,
    wavelength_sampling: WavelengthSampling.WavelengthSamplingTable,
    buffers: Storage.Buffers,
    evaluation_cache: *SpectralEval.SpectralEvaluationCache,
) Storage.Error!void {
    {
        const zone = Trace.staticZone(@src(), "simulate.irradiance_sampling");
        defer zone.end();
        try evaluation_cache.reserveIrradiance(irradianceCacheCapacity(wavelength_sampling));
        for (wavelength_sampling.rows, 0..) |plan, index| {
            buffers.scratch[index] = try SpectralEval.integrateIrradianceAtNominal(
                scene,
                prepared,
                plan.irradiance_wavelength_nm,
                setup.safe_span,
                evaluation_cache,
                &plan.irradiance_integration,
                wavelength_sampling.kernel_storage,
            );
        }
    }
    if (setup.uses_integrated_irradiance_sampling) {
        @memcpy(buffers.irradiance, buffers.scratch);
    } else {
        const zone = Trace.staticZone(@src(), "simulate.irradiance_convolution");
        defer zone.end();
        try convolution.apply(buffers.scratch, setup.irradiance_slit_kernel[0..], buffers.irradiance);
    }
    {
        const zone = Trace.staticZone(@src(), "simulate.irradiance_postprocess");
        defer zone.end();
        try Postprocess.applyChannelCorrections(
            setup.irradiance_calibration,
            buffers.irradiance,
        );
    }
}

fn irradianceCacheCapacity(wavelength_sampling: WavelengthSampling.WavelengthSamplingTable) usize {
    var count: usize = 0;
    for (wavelength_sampling.rows) |plan| {
        count += plan.irradiance_integration.activeSampleCount();
    }
    return count;
}

// hot path:
//   when: once per output wavelength after radiance and irradiance channels are materialized
//   work: computes reflectance and accumulates summary statistics
//   data: radiance, irradiance, reflectance, and running summary fields
//   follow: contiguous output buffers and the summary accumulator write pattern
//   math: rho_i = pi * L_i / max(E0_i * mu0, 1e-9)
fn assembleReflectance(
    scene: *const Scene,
    sample_count: usize,
    buffers: Storage.Buffers,
    summary: *RunningSummary,
) void {
    {
        const zone = Trace.staticZone(@src(), "simulate.reflectance_assembly");
        defer zone.end();
        const solar_cosine = scene.geometry.solarCosineAtAltitude(0.0);
        var denominator_clamp_count: usize = 0;
        var min_denominator = std.math.inf(f64);
        var max_reflectance = -std.math.inf(f64);
        for (0..sample_count) |index| {
            const denominator_raw = buffers.irradiance[index] * solar_cosine;
            const denominator = @max(denominator_raw, 1e-9);
            buffers.reflectance[index] = (buffers.radiance[index] * std.math.pi) / denominator;
            if (Telemetry.enabled) {
                if (denominator_raw <= 1e-9) denominator_clamp_count += 1;
                min_denominator = @min(min_denominator, denominator_raw);
                max_reflectance = @max(max_reflectance, buffers.reflectance[index]);
            }
            summary.addReflectanceSample(
                buffers.radiance[index],
                buffers.irradiance[index],
                buffers.reflectance[index],
            );
        }
        if (Telemetry.enabled) {
            Telemetry.reflectanceAssembly(
                sample_count,
                denominator_clamp_count,
                if (sample_count == 0) 0.0 else min_denominator,
                if (sample_count == 0) 0.0 else max_reflectance,
            );
        }
    }
}

// hot path:
//   when: once per simulation when a Jacobian buffer is requested
//   work: convolves and calibrates active derivative columns, then accumulates mean Jacobian rows
//   data: derivative state mask, state-major active-column buffer, wavelength array
//   follow: jacobianColumn and Postprocess.applyChannelJacobianCorrections
fn processJacobianSamples(
    derivative_state_mask: jacobian.StateMask,
    setup: SimulationSetup,
    buffers: Storage.Buffers,
    summary: *RunningSummary,
) Storage.Error!?jacobian.Vector {
    if (buffers.jacobian) |jacobian_buffer| {
        {
            const zone = Trace.staticZone(@src(), "simulate.jacobian_processing");
            defer zone.end();
            const active_jacobians = ActiveJacobianStates.init(buffers.jacobian_state_mask);
            if (active_jacobians.count == 0 or jacobian_buffer.len != setup.sample_count * active_jacobians.count) return error.ShapeMismatch;
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
                try Postprocess.applyChannelJacobianCorrections(
                    setup.radiance_calibration,
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
                    if (Telemetry.enabled) column_max_abs = @max(column_max_abs, @abs(value));
                }
                summary.jacobian_sum[state_index] += column_sum;
                if (Telemetry.enabled) {
                    Telemetry.jacobianColumn(
                        state_index,
                        column_sum,
                        if (setup.sample_count == 0) 0.0 else column_sum / @as(f64, @floatFromInt(setup.sample_count)),
                        column_max_abs,
                    );
                }
            }
            return jacobian.scale(summary.jacobian_sum, 1.0 / @as(f64, @floatFromInt(setup.sample_count)));
        }
    }
    return null;
}

fn wavelengthPlanKey(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
) u64 {
    var hash = std.hash.Wyhash.init(0x4f32_4132_7761_7665);
    hash.update(implementations.instrument.id);
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
    updateFloatSlice(hash, response.instrument_line_shape.offsets_nm[0..@min(response.instrument_line_shape.offsets_nm.len, response.instrument_line_shape.sample_count)]);
    updateFloatSlice(hash, response.instrument_line_shape.weights[0..@min(response.instrument_line_shape.weights.len, response.instrument_line_shape.sample_count)]);
    updateInt(hash, response.instrument_line_shape_table.nominal_count);
    updateInt(hash, response.instrument_line_shape_table.sample_count);
    updateFloatSlice(hash, response.instrument_line_shape_table.nominal_wavelengths_nm[0..@min(response.instrument_line_shape_table.nominal_wavelengths_nm.len, response.instrument_line_shape_table.nominal_count)]);
    updateFloatSlice(hash, response.instrument_line_shape_table.offsets_nm[0..@min(response.instrument_line_shape_table.offsets_nm.len, response.instrument_line_shape_table.sample_count)]);
    const table_weight_count = @min(
        response.instrument_line_shape_table.weights.len,
        @as(usize, response.instrument_line_shape_table.nominal_count) * @as(usize, response.instrument_line_shape_table.sample_count),
    );
    updateFloatSlice(hash, response.instrument_line_shape_table.weights[0..table_weight_count]);
}

fn updateAdaptiveReferenceGrid(
    hash: *std.hash.Wyhash,
    adaptive: @import("../../../input/Instrument.zig").AdaptiveReferenceGrid,
) void {
    updateInt(hash, adaptive.points_per_fwhm);
    updateInt(hash, adaptive.strong_line_min_divisions);
    updateInt(hash, adaptive.strong_line_max_divisions);
}

fn updateFloatSlice(hash: *std.hash.Wyhash, values: []const f64) void {
    updateInt(hash, values.len);
    hash.update(std.mem.sliceAsBytes(values));
}

fn updateFloat(hash: *std.hash.Wyhash, value: f64) void {
    var bits = @as(u64, @bitCast(value));
    hash.update(std.mem.asBytes(&bits));
}

fn updateInt(hash: *std.hash.Wyhash, value: anytype) void {
    var bits = value;
    hash.update(std.mem.asBytes(&bits));
}

fn jacobianColumn(buffer: []f64, sample_count: usize, active_index: usize) []f64 {
    return buffer[active_index * sample_count ..][0..sample_count];
}

fn writeJacobianSample(
    buffer: []f64,
    active_jacobians: ActiveJacobianStates,
    sample_count: usize,
    sample_index: usize,
    values: jacobian.Vector,
) void {
    for (0..active_jacobians.count) |active_index| {
        const state = active_jacobians.at(active_index) orelse unreachable;
        buffer[active_index * sample_count + sample_index] = values[jacobian.stateIndex(state)];
    }
}

pub fn simulate(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
    buffers: Storage.Buffers,
) Storage.Error!Types.InstrumentGridSummary {
    var evaluation_cache = SpectralEval.SpectralEvaluationCache.init(allocator);
    defer evaluation_cache.deinit();
    evaluation_cache.reset();
    return simulateInternal(allocator, scene, route, prepared, implementations, buffers, &evaluation_cache, null);
}

pub fn simulateSummary(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
) Storage.Error!Types.InstrumentGridSummary {
    var storage: Storage.SummaryStorage = .{};
    defer storage.deinit(allocator);
    return simulateSummaryWithWorkspace(allocator, &storage, scene, route, prepared, implementations);
}

pub fn simulateSummaryWithWorkspace(
    allocator: Allocator,
    storage: *Storage.SummaryStorage,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
) Storage.Error!Types.InstrumentGridSummary {
    var summary_scene = scene.*;
    // GOTCHA:
    //   Summary mode truncates very long spectral grids so it can stay
    //   lightweight while preserving the full-product path for complete runs.
    if (summary_scene.spectral_grid.sample_count > max_summary_samples) {
        summary_scene.spectral_grid.sample_count = max_summary_samples;
    }
    return simulateInternal(
        allocator,
        &summary_scene,
        route,
        prepared,
        implementations,
        try storage.buffers(allocator, &summary_scene, route),
        try storage.spectralCache(allocator),
        storage,
    );
}
