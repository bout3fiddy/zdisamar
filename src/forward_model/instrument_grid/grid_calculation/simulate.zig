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
const Types = @import("types.zig");
const Storage = @import("storage.zig");
const Trace = @import("../../performance_trace.zig");

const Allocator = std.mem.Allocator;
const max_summary_samples: u32 = 128;
const profile_cache_build_chunk_size: usize = 8;

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

const ResolvedSimulationPlan = struct {
    wavelength_sampling: []const WavelengthSampling.WavelengthSampling = &.{},
    forward_misses: []const SpectralEval.ForwardCacheMiss = &.{},
    profile_spectroscopy_caches: []const SpectroscopyState.ProfileNodeSpectroscopyCache = &.{},
    owned_wavelength_sampling: []WavelengthSampling.WavelengthSampling = &.{},
    owned_forward_misses: []SpectralEval.ForwardCacheMiss = &.{},

    fn deinit(self: *ResolvedSimulationPlan, allocator: Allocator) void {
        allocator.free(self.owned_wavelength_sampling);
        allocator.free(self.owned_forward_misses);
        self.* = undefined;
    }
};

const RunningSummary = struct {
    radiance_sum: f64,
    irradiance_sum: f64,
    reflectance_sum: f64,
    noise_sum: f64,
    jacobian_sum: jacobian.Vector,

    fn init() RunningSummary {
        return .{
            .radiance_sum = 0.0,
            .irradiance_sum = 0.0,
            .reflectance_sum = 0.0,
            .noise_sum = 0.0,
            .jacobian_sum = jacobian.zero(),
        };
    }

    fn addReflectanceSample(self: *RunningSummary, radiance: f64, irradiance: f64, reflectance: f64) void {
        self.radiance_sum += radiance;
        self.irradiance_sum += irradiance;
        self.reflectance_sum += reflectance;
    }

    fn addNoiseSigma(self: *RunningSummary, values: []const f64) void {
        for (values) |value| self.noise_sum += value;
    }

    fn addJacobianRow(self: *RunningSummary, values: jacobian.Vector) void {
        jacobian.addScaled(&self.jacobian_sum, values, 1.0);
    }

    fn toInstrumentGridSummary(
        self: RunningSummary,
        sample_count: usize,
        wavelengths: []const f64,
        has_noise_sigma: bool,
        mean_jacobian: ?jacobian.Vector,
    ) Types.InstrumentGridSummary {
        const denominator = @as(f64, @floatFromInt(sample_count));
        return .{
            .sample_count = @intCast(sample_count),
            .wavelength_start_nm = wavelengths[0],
            .wavelength_end_nm = wavelengths[sample_count - 1],
            .mean_radiance = self.radiance_sum / denominator,
            .mean_irradiance = self.irradiance_sum / denominator,
            .mean_reflectance = self.reflectance_sum / denominator,
            .mean_noise_sigma = if (has_noise_sigma) self.noise_sum / denominator else 0.0,
            .mean_jacobian = mean_jacobian,
        };
    }
};

const ProfileCacheBuildQueue = struct {
    mutex: std.Thread.Mutex = .{},
    next_index: usize = 0,
    len: usize,

    fn next(self: *ProfileCacheBuildQueue) ?struct { start: usize, end: usize } {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.next_index >= self.len) return null;
        const start = self.next_index;
        const end = @min(start + profile_cache_build_chunk_size, self.len);
        self.next_index = end;
        return .{ .start = start, .end = end };
    }
};

const ProfileCacheBuildWorker = struct {
    prepared: *const OpticsPreparation.PreparedOpticalState,
    forward_misses: []const SpectralEval.ForwardCacheMiss,
    caches: []SpectroscopyState.ProfileNodeSpectroscopyCache,
    queue: *ProfileCacheBuildQueue,
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

    while (worker.queue.next()) |chunk| {
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
        _ = try ensureProfileSpectroscopyCaches(allocator, storage, prepared, storage.forward_misses);
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
    storage.forward_misses = try WavelengthSampling.collectUniqueForwardMisses(
        allocator,
        storage.wavelength_sampling,
    );
    storage.forward_misses_valid = true;
    _ = try ensureProfileSpectroscopyCaches(allocator, storage, prepared, storage.forward_misses);
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

    storage.profile_spectroscopy_caches = try buildProfileSpectroscopyCaches(
        allocator,
        prepared,
        forward_misses,
    );
    storage.profile_spectroscopy_cache_key = cache_key;
    storage.profile_spectroscopy_cache_valid = true;
    return storage.profile_spectroscopy_caches;
}

fn buildProfileSpectroscopyCaches(
    allocator: Allocator,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    forward_misses: []const SpectralEval.ForwardCacheMiss,
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

    var queue: ProfileCacheBuildQueue = .{ .len = forward_misses.len };
    const workers = try allocator.alloc(ProfileCacheBuildWorker, worker_count);
    defer allocator.free(workers);
    const threads = try allocator.alloc(std.Thread, worker_count - 1);
    defer allocator.free(threads);

    var started_thread_count: usize = 0;
    for (0..worker_count) |worker_index| {
        workers[worker_index] = .{
            .prepared = prepared,
            .forward_misses = forward_misses,
            .caches = caches,
            .queue = &queue,
            .worker_index = worker_index,
        };
        if (worker_index + 1 < worker_count) {
            threads[started_thread_count] = std.Thread.spawn(
                .{},
                profileCacheBuildWorkerMain,
                .{&workers[worker_index]},
            ) catch {
                profileCacheBuildWorkerMain(&workers[worker_index]);
                continue;
            };
            started_thread_count += 1;
        } else {
            profileCacheBuildWorkerMain(&workers[worker_index]);
        }
    }
    for (threads[0..started_thread_count]) |thread| thread.join();
    return caches;
}

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

    const setup = try buildSimulationSetup(scene, prepared, implementations, buffers);
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
        simulation_plan,
        evaluation_cache,
    );

    var summary = RunningSummary.init();
    const transport_layer_count = try validateTransportBuffers(route, prepared, buffers);
    try fillRadianceSamples(
        allocator,
        scene,
        route,
        prepared,
        implementations,
        setup,
        simulation_plan.wavelength_sampling,
        transport_layer_count,
        buffers,
        evaluation_cache,
    );
    try fillIrradianceSamples(
        scene,
        prepared,
        setup,
        simulation_plan.wavelength_sampling,
        buffers,
        evaluation_cache,
    );
    try applyRingCorrection(scene, buffers);
    assembleReflectance(scene, setup.sample_count, buffers, &summary);
    const radiance_noise_sigma = try materializeNoiseSamples(
        scene,
        implementations,
        setup.sample_count,
        buffers,
        &summary,
    );
    const mean_jacobian = try processJacobianSamples(
        scene,
        prepared,
        setup,
        buffers,
        &summary,
    );
    return summary.toInstrumentGridSummary(
        setup.sample_count,
        buffers.wavelengths,
        radiance_noise_sigma != null,
        mean_jacobian,
    );
}

fn buildSimulationSetup(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
    buffers: Storage.Buffers,
) Storage.Error!SimulationSetup {
    try scene.validate();
    const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
    try Storage.validateBuffers(sample_count, buffers);

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
                break :blk storage.wavelength_sampling;
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
            break :blk storage.wavelength_sampling;
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
        break :blk plan.owned_wavelength_sampling;
    };
    plan.forward_misses = blk: {
        const zone = Trace.staticZone(@src(), "simulate.forward_miss_collection");
        defer zone.end();

        if (wavelength_plan_storage) |storage| {
            if (!storage.forward_misses_valid) {
                storage.forward_misses = try WavelengthSampling.collectUniqueForwardMisses(
                    allocator,
                    plan.wavelength_sampling,
                );
                storage.forward_misses_valid = true;
            }
            break :blk storage.forward_misses;
        }
        plan.owned_forward_misses = try WavelengthSampling.collectUniqueForwardMisses(
            allocator,
            plan.wavelength_sampling,
        );
        break :blk plan.owned_forward_misses;
    };
    plan.profile_spectroscopy_caches = blk: {
        const zone = Trace.staticZone(@src(), "simulate.profile_spectroscopy_cache");
        defer zone.end();

        if (wavelength_plan_storage) |storage| {
            break :blk try ensureProfileSpectroscopyCaches(allocator, storage, prepared, plan.forward_misses);
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
    simulation_plan: ResolvedSimulationPlan,
    evaluation_cache: *SpectralEval.SpectralEvaluationCache,
) Storage.Error!void {
    {
        const zone = Trace.staticZone(@src(), "simulate.forward_prefetch_wall");
        zone.value(@intCast(simulation_plan.forward_misses.len));
        defer zone.end();
        try SpectralEval.prefetchForwardSamples(
            allocator,
            scene,
            route,
            prepared,
            implementations,
            setup.safe_span,
            simulation_plan.forward_misses,
            simulation_plan.profile_spectroscopy_caches,
            evaluation_cache,
        );
    }
}

fn validateTransportBuffers(
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    buffers: Storage.Buffers,
) Storage.Error!usize {
    const transport_layer_count = Storage.resolvedTransportLayerCount(route, prepared);
    if (buffers.layer_inputs.len < transport_layer_count or
        buffers.source_interfaces.len < transport_layer_count + 1 or
        buffers.rtm_quadrature_levels.len < transport_layer_count + 1 or
        buffers.pseudo_spherical_level_starts.len < transport_layer_count + 1)
    {
        return error.ShapeMismatch;
    }
    return transport_layer_count;
}

fn fillRadianceSamples(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
    setup: SimulationSetup,
    wavelength_sampling: []const WavelengthSampling.WavelengthSampling,
    transport_layer_count: usize,
    buffers: Storage.Buffers,
    evaluation_cache: *SpectralEval.SpectralEvaluationCache,
) Storage.Error!void {
    {
        const zone = Trace.staticZone(@src(), "simulate.radiance_cache_integration");
        defer zone.end();
        for (wavelength_sampling, 0..) |plan, index| {
            const nominal_wavelength_nm = plan.nominal_wavelength_nm;
            buffers.wavelengths[index] = nominal_wavelength_nm;

            const integrated = try SpectralEval.integrateForwardAtNominal(
                allocator,
                scene,
                route,
                prepared,
                plan.radiance_wavelength_nm,
                setup.safe_span,
                implementations,
                buffers.layer_inputs[0..transport_layer_count],
                buffers.pseudo_spherical_layers,
                buffers.source_interfaces[0 .. transport_layer_count + 1],
                buffers.rtm_quadrature_levels[0 .. transport_layer_count + 1],
                buffers.pseudo_spherical_samples,
                buffers.pseudo_spherical_level_starts[0 .. transport_layer_count + 1],
                buffers.pseudo_spherical_level_altitudes[0 .. transport_layer_count + 1],
                evaluation_cache,
                &plan.radiance_integration,
            );
            buffers.scratch[index] = integrated.radiance;
            if (buffers.jacobian) |jacobian_buffer| writeJacobianRow(jacobian_buffer, index, integrated.jacobian);
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
            scene,
            .radiance,
            setup.radiance_calibration,
            prepared.depolarization_factor,
            buffers.wavelengths,
            buffers.radiance,
            buffers.scratch_aux,
        );
    }
}

fn fillIrradianceSamples(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    setup: SimulationSetup,
    wavelength_sampling: []const WavelengthSampling.WavelengthSampling,
    buffers: Storage.Buffers,
    evaluation_cache: *SpectralEval.SpectralEvaluationCache,
) Storage.Error!void {
    {
        const zone = Trace.staticZone(@src(), "simulate.irradiance_sampling");
        defer zone.end();
        for (wavelength_sampling, 0..) |plan, index| {
            buffers.scratch[index] = try SpectralEval.integrateIrradianceAtNominal(
                scene,
                prepared,
                plan.irradiance_wavelength_nm,
                setup.safe_span,
                evaluation_cache,
                &plan.irradiance_integration,
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
            scene,
            .irradiance,
            setup.irradiance_calibration,
            prepared.depolarization_factor,
            buffers.wavelengths,
            buffers.irradiance,
            buffers.scratch_aux,
        );
    }
}

fn applyRingCorrection(scene: *const Scene, buffers: Storage.Buffers) Storage.Error!void {
    {
        const zone = Trace.staticZone(@src(), "simulate.ring_correction");
        defer zone.end();
        try calibration.applyRingSpectrum(
            scene.observation_model.resolvedRingControls(),
            buffers.wavelengths,
            buffers.irradiance,
            buffers.radiance,
            buffers.scratch_aux,
        );
    }
}

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
        for (0..sample_count) |index| {
            buffers.reflectance[index] = (buffers.radiance[index] * std.math.pi) /
                @max(buffers.irradiance[index] * solar_cosine, 1e-9);
            summary.addReflectanceSample(
                buffers.radiance[index],
                buffers.irradiance[index],
                buffers.reflectance[index],
            );
        }
    }
}

fn materializeNoiseSamples(
    scene: *const Scene,
    implementations: Types.Implementations,
    sample_count: usize,
    buffers: Storage.Buffers,
    summary: *RunningSummary,
) Storage.Error!?[]f64 {
    return noise: {
        const zone = Trace.staticZone(@src(), "simulate.noise_sigma");
        defer zone.end();
        const sigma = if (buffers.radiance_noise_sigma) |value|
            value
        else if (buffers.noise_sigma) |value|
            value
        else if (buffers.reflectance_noise_sigma != null)
            buffers.scratch
        else
            null;
        if (sigma) |values| {
            try Postprocess.materializeChannelSigma(implementations, scene, .radiance, buffers.wavelengths, buffers.radiance, values);
        }
        if (buffers.noise_sigma) |noise_sigma| {
            const values = sigma orelse return error.ShapeMismatch;
            if (noise_sigma.ptr != values.ptr) {
                @memcpy(noise_sigma, values);
            }
        }

        const irradiance_noise_sigma = if (buffers.irradiance_noise_sigma) |value|
            value
        else if (buffers.reflectance_noise_sigma != null)
            buffers.scratch_aux
        else
            null;
        if (irradiance_noise_sigma) |values| {
            try Postprocess.materializeChannelSigma(implementations, scene, .irradiance, buffers.wavelengths, buffers.irradiance, values);
        }

        if (buffers.reflectance_noise_sigma) |reflectance_noise_sigma| {
            const radiance_sigma = sigma orelse return error.ShapeMismatch;
            const irradiance_sigma = irradiance_noise_sigma orelse return error.ShapeMismatch;
            for (0..sample_count) |index| {
                const radiance_term = if (radiance_sigma.len == sample_count and buffers.radiance[index] > 0.0)
                    buffers.reflectance[index] * (radiance_sigma[index] / @max(buffers.radiance[index], 1.0e-12))
                else
                    0.0;
                const irradiance_term = if (irradiance_sigma.len == sample_count and buffers.irradiance[index] > 0.0)
                    buffers.reflectance[index] * (irradiance_sigma[index] / @max(buffers.irradiance[index], 1.0e-12))
                else
                    0.0;
                reflectance_noise_sigma[index] = std.math.sqrt(radiance_term * radiance_term + irradiance_term * irradiance_term);
            }
            try calibration.applyReflectanceCalibrationErrorSigma(
                scene.observation_model.resolvedReflectanceCalibration(),
                buffers.wavelengths,
                buffers.reflectance,
                reflectance_noise_sigma,
                buffers.scratch_aux,
            );
        }

        if (sigma) |values| {
            summary.addNoiseSigma(values);
        }
        break :noise sigma;
    };
}

fn processJacobianSamples(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    setup: SimulationSetup,
    buffers: Storage.Buffers,
    summary: *RunningSummary,
) Storage.Error!?jacobian.Vector {
    if (buffers.jacobian) |jacobian_buffer| {
        {
            const zone = Trace.staticZone(@src(), "simulate.jacobian_processing");
            defer zone.end();
            if (!setup.uses_integrated_radiance_sampling) {
                for (0..jacobian.state_count) |state_index| {
                    copyJacobianColumnToScratch(jacobian_buffer, state_index, buffers.scratch);
                    try convolution.apply(buffers.scratch, setup.radiance_slit_kernel[0..], buffers.scratch_aux);
                    copyScratchToJacobianColumn(buffers.scratch_aux, jacobian_buffer, state_index);
                }
            }
            for (0..jacobian.state_count) |state_index| {
                copyJacobianColumnToScratch(jacobian_buffer, state_index, buffers.scratch);
                try Postprocess.applyChannelJacobianCorrections(
                    scene,
                    .radiance,
                    setup.radiance_calibration,
                    prepared.depolarization_factor,
                    buffers.wavelengths,
                    buffers.scratch,
                    buffers.scratch_aux,
                );
                copyScratchToJacobianColumn(buffers.scratch, jacobian_buffer, state_index);
            }
            // DECISION:
            //   Ring synthesis uses the irradiance-only basis from the current
            //   forward model, so it does not change the routed radiance Jacobian.
            for (0..setup.sample_count) |index| {
                summary.addJacobianRow(readJacobianRow(jacobian_buffer, index));
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
    updateSpectroscopyPlanInputs(&hash, prepared);
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
    updateFloatSlice(&hash, prepared.spectroscopy_profile_altitudes_km);
    updateFloatSlice(&hash, prepared.spectroscopy_profile_pressures_hpa);
    updateFloatSlice(&hash, prepared.spectroscopy_profile_temperatures_k);
    updateSpectroscopyCacheInputs(&hash, prepared);
    return hash.final();
}

fn updateSpectroscopyCacheInputs(
    hash: *std.hash.Wyhash,
    prepared: *const OpticsPreparation.PreparedOpticalState,
) void {
    updateInt(hash, prepared.spectroscopy_lines != null);
    if (prepared.spectroscopy_lines) |line_list| updateFullLineListInputs(hash, line_list);
    updateInt(hash, prepared.operational_o2_lut.enabled());
    updateStrongLinePreparedStates(hash, prepared.spectroscopy_profile_strong_line_states);
    updateWeakLinePreparedStates(hash, prepared.spectroscopy_profile_weak_line_states);
}

fn updateStrongLinePreparedStates(hash: *std.hash.Wyhash, states: anytype) void {
    updateInt(hash, states != null);
    if (states) |resolved| {
        updateInt(hash, resolved.len);
        for (resolved) |state| {
            updateInt(hash, state.line_count);
            updateFloat(hash, state.sig_moy_cm1);
            updateFloatSlice(hash, state.population_t);
            updateFloatSlice(hash, state.dipole_t);
            updateFloatSlice(hash, state.mod_sig_cm1);
            updateFloatSlice(hash, state.half_width_cm1_at_t);
            updateFloatSlice(hash, state.line_mixing_coefficients);
            updateFloatSlice(hash, state.relaxation_weights);
        }
    }
}

fn updateWeakLinePreparedStates(hash: *std.hash.Wyhash, states: anytype) void {
    updateInt(hash, states != null);
    if (states) |resolved| {
        updateInt(hash, resolved.len);
        for (resolved) |state| {
            updateInt(hash, state.line_count);
            updateInt(hash, state.lines.len);
            for (state.lines) |line| {
                updateFloat(hash, line.shifted_center_wavenumber_cm1);
                updateFloat(hash, line.cte);
                updateFloat(hash, line.line_shape_y);
                updateFloat(hash, line.prefactor_base);
                updateFloat(hash, line.safe_temperature);
                updateFloat(hash, line.safe_pressure);
            }
        }
    }
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

fn updateSpectroscopyPlanInputs(
    hash: *std.hash.Wyhash,
    prepared: *const OpticsPreparation.PreparedOpticalState,
) void {
    updateInt(hash, prepared.spectroscopy_lines != null);
    if (prepared.spectroscopy_lines) |line_list| {
        updateLineListPlanInputs(hash, line_list);
    }
    updateInt(hash, prepared.line_absorbers.len);
    for (prepared.line_absorbers) |line_absorber| {
        updateLineListPlanInputs(hash, line_absorber.line_list);
    }
}

fn updateLineListPlanInputs(hash: *std.hash.Wyhash, line_list: anytype) void {
    updateOptionalFloat(hash, line_list.runtime_controls.threshold_line_scale);
    updateInt(hash, line_list.lines.len);
    for (line_list.lines) |line| {
        updateFloat(hash, line.center_wavelength_nm);
        updateFloat(hash, line.line_strength_cm2_per_molecule);
    }
}

fn updateFullLineListInputs(hash: *std.hash.Wyhash, line_list: anytype) void {
    updateFloat(hash, line_list.strong_line_tolerance_nm);
    updateInt(hash, line_list.lines_sorted_ascending);
    updateInt(hash, line_list.preserve_anchor_weak_lines);
    updateInt(hash, line_list.vendor_strong_line_partition);
    updateOptionalIntSlice(hash, line_list.strong_line_match_by_line);
    updateFullRuntimeControls(hash, line_list.runtime_controls);

    updateInt(hash, line_list.lines.len);
    for (line_list.lines) |line| {
        updateInt(hash, line.gas_index);
        updateInt(hash, line.isotope_number);
        updateFloat(hash, line.abundance_fraction);
        updateInt(hash, line.vendor_filter_metadata_from_source);
        updateFloat(hash, line.center_wavelength_nm);
        updateFloat(hash, line.center_wavenumber_cm1);
        updateFloat(hash, line.line_strength_cm2_per_molecule);
        updateFloat(hash, line.air_half_width_nm);
        updateFloat(hash, line.air_half_width_cm1);
        updateFloat(hash, line.temperature_exponent);
        updateFloat(hash, line.lower_state_energy_cm1);
        updateFloat(hash, line.pressure_shift_nm);
        updateFloat(hash, line.pressure_shift_cm1);
        updateFloat(hash, line.line_mixing_coefficient);
        updateOptionalInt(hash, line.branch_ic1);
        updateOptionalInt(hash, line.branch_ic2);
        updateOptionalInt(hash, line.rotational_nf);
    }

    updateInt(hash, line_list.strong_lines != null);
    if (line_list.strong_lines) |strong_lines| {
        updateInt(hash, strong_lines.len);
        for (strong_lines) |line| {
            updateFloat(hash, line.center_wavenumber_cm1);
            updateFloat(hash, line.center_wavelength_nm);
            updateFloat(hash, line.population_t0);
            updateFloat(hash, line.dipole_ratio);
            updateFloat(hash, line.dipole_t0);
            updateFloat(hash, line.lower_state_energy_cm1);
            updateFloat(hash, line.air_half_width_cm1);
            updateFloat(hash, line.air_half_width_nm);
            updateFloat(hash, line.temperature_exponent);
            updateFloat(hash, line.pressure_shift_cm1);
            updateFloat(hash, line.pressure_shift_nm);
            updateInt(hash, line.rotational_index_m1);
        }
    }

    updateInt(hash, line_list.relaxation_matrix != null);
    if (line_list.relaxation_matrix) |matrix| {
        updateInt(hash, matrix.line_count);
        updateFloatSlice(hash, matrix.wt0);
        updateFloatSlice(hash, matrix.bw);
    }
}

fn updateFullRuntimeControls(hash: *std.hash.Wyhash, controls: anytype) void {
    updateOptionalInt(hash, controls.gas_index);
    updateInt(hash, controls.active_isotopes.len);
    hash.update(controls.active_isotopes);
    updateOptionalFloat(hash, controls.threshold_line_scale);
    updateOptionalFloat(hash, controls.cutoff_cm1);
    updateFloatSlice(hash, controls.cutoff_grid_wavelengths_nm);
    updateFloatSlice(hash, controls.cutoff_grid_wavenumbers_cm1);
    updateFloat(hash, controls.line_mixing_factor);
}

fn updateOptionalInt(hash: *std.hash.Wyhash, value: anytype) void {
    updateInt(hash, value != null);
    if (value) |resolved| updateInt(hash, resolved);
}

fn updateOptionalIntSlice(hash: *std.hash.Wyhash, value: anytype) void {
    updateInt(hash, value != null);
    if (value) |resolved| {
        updateInt(hash, resolved.len);
        for (resolved) |item| updateOptionalInt(hash, item);
    }
}

fn updateOptionalFloat(hash: *std.hash.Wyhash, value: ?f64) void {
    updateInt(hash, value != null);
    if (value) |resolved| updateFloat(hash, resolved);
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

fn jacobianOffset(sample_index: usize, state_index: usize) usize {
    return sample_index * jacobian.state_count + state_index;
}

fn writeJacobianRow(buffer: []f64, sample_index: usize, values: jacobian.Vector) void {
    for (0..jacobian.state_count) |state_index| {
        buffer[jacobianOffset(sample_index, state_index)] = values[state_index];
    }
}

fn readJacobianRow(buffer: []const f64, sample_index: usize) jacobian.Vector {
    var values = jacobian.zero();
    for (0..jacobian.state_count) |state_index| {
        values[state_index] = buffer[jacobianOffset(sample_index, state_index)];
    }
    return values;
}

fn copyJacobianColumnToScratch(buffer: []const f64, state_index: usize, scratch: []f64) void {
    for (scratch, 0..) |*value, sample_index| {
        value.* = buffer[jacobianOffset(sample_index, state_index)];
    }
}

fn copyScratchToJacobianColumn(scratch: []const f64, buffer: []f64, state_index: usize) void {
    for (scratch, 0..) |value, sample_index| {
        buffer[jacobianOffset(sample_index, state_index)] = value;
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
        try storage.buffers(allocator, &summary_scene, route, implementations),
        try storage.spectralCache(allocator),
        storage,
    );
}
