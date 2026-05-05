const std = @import("std");
const Scene = @import("../../../input/Scene.zig").Scene;
const OpticsPreparation = @import("../../optical_properties/root.zig");
const CarrierEval = @import("../../optical_properties/state_build/carrier_eval.zig");
const common = @import("../../radiative_transfer/root.zig");
const labos = @import("../../radiative_transfer/labos/root.zig");
const ForwardInput = @import("forward_input.zig");
const Types = @import("types.zig");
const Storage = @import("storage.zig");
const solar_compat = @import("../../../input/reference_data/solar_irradiance.zig");

const Allocator = std.mem.Allocator;
const Error = Storage.Error;
// PUB FOR TEST: re-exported via measurement/internal.zig.
pub const min_parallel_forward_miss_count: usize = 32;

pub const ForwardIntegratedSample = struct {
    radiance: f64,
    jacobian: f64 = 0.0,
};

pub const ForwardCacheMiss = struct {
    key: u64,
    wavelength_nm: f64,
};

const ForwardSampleScratch = struct {
    layer_inputs: []common.LayerInput,
    pseudo_spherical_layers: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    support_carrier_valid: []bool,
    support_carriers: []CarrierEval.SharedOpticalCarrier,
    labos_workspace: labos.Workspace,

    fn init(
        allocator: Allocator,
        scene: *const Scene,
        route: common.Route,
        prepared: *const OpticsPreparation.PreparedOpticalState,
    ) !ForwardSampleScratch {
        const layer_count = Storage.resolvedTransportLayerCount(route, prepared);
        const pseudo_spherical_sample_count = Storage.resolvedPseudoSphericalSampleCount(scene, route, prepared);
        const support_cache_count = if (prepared.sublayers) |sublayers| sublayers.len else layer_count;

        const layer_inputs = try allocator.alloc(common.LayerInput, layer_count);
        errdefer allocator.free(layer_inputs);
        const pseudo_spherical_layers = try allocator.alloc(common.LayerInput, pseudo_spherical_sample_count);
        errdefer allocator.free(pseudo_spherical_layers);
        const source_interfaces = try allocator.alloc(common.SourceInterfaceInput, layer_count + 1);
        errdefer allocator.free(source_interfaces);
        const rtm_quadrature_levels = try allocator.alloc(common.RtmQuadratureLevel, layer_count + 1);
        errdefer allocator.free(rtm_quadrature_levels);
        const pseudo_spherical_samples = try allocator.alloc(common.PseudoSphericalSample, pseudo_spherical_sample_count);
        errdefer allocator.free(pseudo_spherical_samples);
        const pseudo_spherical_level_starts = try allocator.alloc(usize, layer_count + 1);
        errdefer allocator.free(pseudo_spherical_level_starts);
        const pseudo_spherical_level_altitudes = try allocator.alloc(f64, layer_count + 1);
        errdefer allocator.free(pseudo_spherical_level_altitudes);
        const support_carrier_valid = try allocator.alloc(bool, support_cache_count);
        errdefer allocator.free(support_carrier_valid);
        const support_carriers = try allocator.alloc(CarrierEval.SharedOpticalCarrier, support_cache_count);
        errdefer allocator.free(support_carriers);

        return .{
            .layer_inputs = layer_inputs,
            .pseudo_spherical_layers = pseudo_spherical_layers,
            .source_interfaces = source_interfaces,
            .rtm_quadrature_levels = rtm_quadrature_levels,
            .pseudo_spherical_samples = pseudo_spherical_samples,
            .pseudo_spherical_level_starts = pseudo_spherical_level_starts,
            .pseudo_spherical_level_altitudes = pseudo_spherical_level_altitudes,
            .support_carrier_valid = support_carrier_valid,
            .support_carriers = support_carriers,
            .labos_workspace = labos.Workspace.init(allocator),
        };
    }

    fn deinit(self: *ForwardSampleScratch, allocator: Allocator) void {
        self.labos_workspace.deinit();
        allocator.free(self.layer_inputs);
        allocator.free(self.pseudo_spherical_layers);
        allocator.free(self.source_interfaces);
        allocator.free(self.rtm_quadrature_levels);
        allocator.free(self.pseudo_spherical_samples);
        allocator.free(self.pseudo_spherical_level_starts);
        allocator.free(self.pseudo_spherical_level_altitudes);
        allocator.free(self.support_carrier_valid);
        allocator.free(self.support_carriers);
        self.* = undefined;
    }
};

const ForwardPrefetchErrorState = struct {
    mutex: std.Thread.Mutex = .{},
    err: ?Error = null,

    fn store(self: *ForwardPrefetchErrorState, err: Error) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.err == null) self.err = err;
    }
};

const ForwardPrefetchWorker = struct {
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
    safe_span: f64,
    misses: []const ForwardCacheMiss,
    results: []ForwardIntegratedSample,
    error_state: *ForwardPrefetchErrorState,
    profile: ?*ForwardPrefetchProfile,
    input_profile: ?*ForwardInput.Profile,
    labos_profile: ?*labos.Profile,
    labos_layers_profile: ?*labos.LayersProfile,
};

const ForwardPrefetchProfile = struct {
    mutex: std.Thread.Mutex = .{},
    configured_input_ns: i128 = 0,
    transport_ns: i128 = 0,
    radiance_ns: i128 = 0,
    sample_count: usize = 0,

    fn add(self: *ForwardPrefetchProfile, configured_input_ns: i128, transport_ns: i128, radiance_ns: i128) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.configured_input_ns += configured_input_ns;
        self.transport_ns += transport_ns;
        self.radiance_ns += radiance_ns;
        self.sample_count += 1;
    }

    fn print(self: *ForwardPrefetchProfile) void {
        const denom = @max(@as(f64, @floatFromInt(self.sample_count)), 1.0);
        std.debug.print(
            "[zds-profile] forward_samples={} configured_input_total={d:.3}ms transport_total={d:.3}ms radiance_total={d:.3}ms configured_input_mean={d:.3}ms transport_mean={d:.3}ms\n",
            .{
                self.sample_count,
                @as(f64, @floatFromInt(self.configured_input_ns)) / 1.0e6,
                @as(f64, @floatFromInt(self.transport_ns)) / 1.0e6,
                @as(f64, @floatFromInt(self.radiance_ns)) / 1.0e6,
                (@as(f64, @floatFromInt(self.configured_input_ns)) / 1.0e6) / denom,
                (@as(f64, @floatFromInt(self.transport_ns)) / 1.0e6) / denom,
            },
        );
    }
};

pub fn radianceFromForward(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
    wavelength_nm: f64,
    safe_span: f64,
    phase: f64,
    forward: common.ForwardResult,
) f64 {
    const solar_irradiance = solar_compat.irradianceAtWavelength(scene, wavelength_nm);
    const solar_cosine = scene.geometry.solarCosineAtAltitude(0.0);
    const surface_gain = implementations.surface.brdfFactor(.{
        .scene = scene,
        .prepared = prepared,
        .wavelength_nm = wavelength_nm,
        .safe_span = safe_span,
        .phase = phase,
        .forward = forward,
    });
    return solar_cosine * (forward.toa_reflectance_factor * surface_gain) * solar_irradiance / std.math.pi;
}

pub fn computeForwardSampleAtWavelength(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
    implementations: Types.Implementations,
    layer_inputs: []common.LayerInput,
    pseudo_spherical_layers: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
) Error!ForwardIntegratedSample {
    const support_cache_count = if (prepared.sublayers) |sublayers| sublayers.len else layer_inputs.len;
    const support_carrier_valid = try allocator.alloc(bool, support_cache_count);
    defer allocator.free(support_carrier_valid);
    const support_carriers = try allocator.alloc(CarrierEval.SharedOpticalCarrier, support_cache_count);
    defer allocator.free(support_carriers);
    var labos_workspace = labos.Workspace.init(allocator);
    defer labos_workspace.deinit();
    return computeForwardSampleAtWavelengthProfiled(
        allocator,
        scene,
        route,
        prepared,
        wavelength_nm,
        safe_span,
        implementations,
        layer_inputs,
        pseudo_spherical_layers,
        source_interfaces,
        rtm_quadrature_levels,
        pseudo_spherical_samples,
        pseudo_spherical_level_starts,
        pseudo_spherical_level_altitudes,
        support_carrier_valid,
        support_carriers,
        &labos_workspace,
        null,
        null,
        null,
        null,
    );
}

fn computeForwardSampleAtWavelengthProfiled(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
    implementations: Types.Implementations,
    layer_inputs: []common.LayerInput,
    pseudo_spherical_layers: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    support_carrier_valid: []bool,
    support_carriers: []CarrierEval.SharedOpticalCarrier,
    labos_workspace: *labos.Workspace,
    profile: ?*ForwardPrefetchProfile,
    input_profile: ?*ForwardInput.Profile,
    labos_profile: ?*labos.Profile,
    labos_layers_profile: ?*labos.LayersProfile,
) Error!ForwardIntegratedSample {
    const should_profile = profile != null;
    const configured_start = if (should_profile) std.time.nanoTimestamp() else 0;
    const input = try ForwardInput.configuredForwardInput(
        scene,
        route,
        prepared,
        wavelength_nm,
        layer_inputs,
        pseudo_spherical_layers,
        source_interfaces,
        rtm_quadrature_levels,
        pseudo_spherical_samples,
        pseudo_spherical_level_starts,
        pseudo_spherical_level_altitudes,
        support_carrier_valid,
        support_carriers,
        input_profile,
    );
    const transport_start = if (should_profile) std.time.nanoTimestamp() else 0;
    var effective_route = route;
    effective_route.rtm_controls = input.rtm_controls;
    const forward = if (labos_profile != null or labos_layers_profile != null) blk: {
        const previous_labos_profile = labos.setProfile(labos_profile);
        defer _ = labos.setProfile(previous_labos_profile);
        const previous_labos_layers_profile = labos.setLayersProfile(labos_layers_profile);
        defer _ = labos.setLayersProfile(previous_labos_layers_profile);
        break :blk if (implementations.transport.executePreparedWithLabosWorkspace) |execute_with_workspace|
            try execute_with_workspace(allocator, effective_route, input, labos_workspace)
        else
            try implementations.transport.executePrepared(allocator, effective_route, input);
    } else if (implementations.transport.executePreparedWithLabosWorkspace) |execute_with_workspace|
        try execute_with_workspace(allocator, effective_route, input, labos_workspace)
    else
        try implementations.transport.executePrepared(allocator, effective_route, input);
    const radiance_start = if (should_profile) std.time.nanoTimestamp() else 0;
    const radiance = radianceFromForward(scene, prepared, implementations, wavelength_nm, safe_span, 0.0, forward);
    if (profile) |profiler| {
        const end = std.time.nanoTimestamp();
        profiler.add(transport_start - configured_start, radiance_start - transport_start, end - radiance_start);
    }
    return .{
        .radiance = radiance,
        .jacobian = if (forward.jacobian_column) |value| value else 0.0,
    };
}

fn prefetchForwardWorkerMain(worker: *ForwardPrefetchWorker) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var scratch = ForwardSampleScratch.init(
        allocator,
        worker.scene,
        worker.route,
        worker.prepared,
    ) catch |err| {
        worker.error_state.store(err);
        return;
    };
    defer scratch.deinit(allocator);

    for (worker.misses, worker.results) |miss, *result| {
        result.* = computeForwardSampleAtWavelengthProfiled(
            allocator,
            worker.scene,
            worker.route,
            worker.prepared,
            miss.wavelength_nm,
            worker.safe_span,
            worker.implementations,
            scratch.layer_inputs,
            scratch.pseudo_spherical_layers,
            scratch.source_interfaces,
            scratch.rtm_quadrature_levels,
            scratch.pseudo_spherical_samples,
            scratch.pseudo_spherical_level_starts,
            scratch.pseudo_spherical_level_altitudes,
            scratch.support_carrier_valid,
            scratch.support_carriers,
            &scratch.labos_workspace,
            worker.profile,
            worker.input_profile,
            worker.labos_profile,
            worker.labos_layers_profile,
        ) catch |err| {
            worker.error_state.store(err);
            return;
        };
    }
}

pub fn prefetchForwardSamples(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Types.Implementations,
    safe_span: f64,
    misses: []const ForwardCacheMiss,
    results: []ForwardIntegratedSample,
) Error!void {
    if (misses.len == 0) return;

    const worker_count = preferredForwardWorkerCount(misses.len);

    if (worker_count == 1) {
        var scratch = try ForwardSampleScratch.init(allocator, scene, route, prepared);
        defer scratch.deinit(allocator);
        for (misses, results) |miss, *result| {
            result.* = try computeForwardSampleAtWavelengthProfiled(
                allocator,
                scene,
                route,
                prepared,
                miss.wavelength_nm,
                safe_span,
                implementations,
                scratch.layer_inputs,
                scratch.pseudo_spherical_layers,
                scratch.source_interfaces,
                scratch.rtm_quadrature_levels,
                scratch.pseudo_spherical_samples,
                scratch.pseudo_spherical_level_starts,
                scratch.pseudo_spherical_level_altitudes,
                scratch.support_carrier_valid,
                scratch.support_carriers,
                &scratch.labos_workspace,
                null,
                null,
                null,
                null,
            );
        }
        return;
    }

    var error_state = ForwardPrefetchErrorState{};
    var profile = ForwardPrefetchProfile{};
    var input_profile = ForwardInput.Profile{};
    var labos_profile = labos.Profile{};
    var labos_layers_profile = labos.LayersProfile{};
    const profile_ptr: ?*ForwardPrefetchProfile = if (std.process.hasEnvVarConstant("ZDISAMAR_PROFILE_FORWARD")) &profile else null;
    const input_profile_ptr: ?*ForwardInput.Profile = if (std.process.hasEnvVarConstant("ZDISAMAR_PROFILE_FORWARD")) &input_profile else null;
    const labos_profile_ptr: ?*labos.Profile = if (std.process.hasEnvVarConstant("ZDISAMAR_PROFILE_FORWARD")) &labos_profile else null;
    const labos_layers_profile_ptr: ?*labos.LayersProfile = if (std.process.hasEnvVarConstant("ZDISAMAR_PROFILE_FORWARD")) &labos_layers_profile else null;
    const workers = try allocator.alloc(ForwardPrefetchWorker, worker_count);
    defer allocator.free(workers);
    const threads = try allocator.alloc(std.Thread, worker_count - 1);
    defer allocator.free(threads);

    const base_count = misses.len / worker_count;
    const remainder = misses.len % worker_count;
    var start_index: usize = 0;
    var started_thread_count: usize = 0;
    for (0..worker_count) |worker_index| {
        const batch_count = base_count + @as(usize, if (worker_index < remainder) 1 else 0);
        const end_index = start_index + batch_count;
        workers[worker_index] = .{
            .scene = scene,
            .route = route,
            .prepared = prepared,
            .implementations = implementations,
            .safe_span = safe_span,
            .misses = misses[start_index..end_index],
            .results = results[start_index..end_index],
            .error_state = &error_state,
            .profile = profile_ptr,
            .input_profile = input_profile_ptr,
            .labos_profile = labos_profile_ptr,
            .labos_layers_profile = labos_layers_profile_ptr,
        };
        if (worker_index + 1 < worker_count) {
            threads[started_thread_count] = std.Thread.spawn(
                .{},
                prefetchForwardWorkerMain,
                .{&workers[worker_index]},
            ) catch {
                prefetchForwardWorkerMain(&workers[worker_index]);
                start_index = end_index;
                continue;
            };
            started_thread_count += 1;
        } else {
            prefetchForwardWorkerMain(&workers[worker_index]);
        }
        start_index = end_index;
    }
    for (threads[0..started_thread_count]) |thread| thread.join();
    if (error_state.err) |err| return err;
    if (input_profile_ptr) |profiler| profiler.print();
    if (labos_profile_ptr) |profiler| profiler.print();
    if (labos_layers_profile_ptr) |profiler| profiler.print();
    if (profile_ptr) |profiler| profiler.print();
}

// PUB FOR TEST: re-exported via measurement/internal.zig.
pub fn preferredForwardWorkerCount(miss_count: usize) usize {
    if (miss_count < min_parallel_forward_miss_count) return 1;
    const cpu_count = std.Thread.getCpuCount() catch 1;
    return @min(cpu_count, @max(@as(usize, 1), miss_count / min_parallel_forward_miss_count));
}
