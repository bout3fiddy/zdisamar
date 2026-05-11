const std = @import("std");
const ReferenceData = @import("../../../input/ReferenceData.zig");
const Rayleigh = @import("../../../input/reference/rayleigh.zig");
const Context = @import("context.zig").PreparationContext;
const Absorbers = @import("absorbers.zig");
const LayerSpectroscopy = @import("layer_spectroscopy.zig");
const Spectroscopy = @import("spectroscopy.zig");
const State = @import("state.zig");
const ParticleProfiles = @import("../shared/particle_profiles.zig");
const PhaseFunctions = @import("../shared/phase_functions.zig");
const Trace = @import("../../performance_trace.zig");
const ClimatologyProfile = @import("../../../input/reference/climatology.zig").ClimatologyProfile;
const spline = @import("../../../common/math/interpolation/spline.zig");
const internal = @import("internal.zig");

const Allocator = std.mem.Allocator;
const min_parallel_parity_support_row_count: usize = 64;
const parity_support_row_chunk_size: usize = 8;
const oxygen_volume_mixing_ratio = Spectroscopy.default_o2_volume_mixing_ratio;
const centimeters_per_kilometer = 1.0e5;
const boltzmann_hpa_cm3_per_k = internal.boltzmann_hpa_cm3_per_k;
const max_collision_complex_profile_nodes: usize = 256;

const pressureFromParitySupportBounds = internal.pressureFromParitySupportBounds;
const paritySupportThermodynamicsFromProfile = internal.paritySupportThermodynamicsFromProfile;

const ParitySupportRowErrorState = struct {
    mutex: std.Thread.Mutex = .{},
    err: ?anyerror = null,

    fn store(self: *ParitySupportRowErrorState, err: anyerror) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.err == null) self.err = err;
    }
};

const ParitySupportRowQueue = struct {
    mutex: std.Thread.Mutex = .{},
    next_index: usize = 0,
    len: usize,

    fn next(self: *ParitySupportRowQueue) ?struct { start: usize, end: usize } {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.next_index >= self.len) return null;
        const start = self.next_index;
        const end = @min(start + parity_support_row_chunk_size, self.len);
        self.next_index = end;
        return .{ .start = start, .end = end };
    }
};

const ParitySupportRowWorker = struct {
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
    profile_spectroscopy_cache: ?*const LayerSpectroscopy.ProfileSpectroscopyCache,
    aerosol_sublayer_distribution: []const f64,
    cloud_sublayer_distribution: []const f64,
    aerosol_phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64,
    cloud_phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64,
    aerosol_single_scatter_albedo: f64,
    cloud_single_scatter_albedo: f64,
    aerosol_extinction_scale: f64,
    cloud_extinction_scale: f64,
    aerosol_fraction: f64,
    cloud_fraction: f64,
    queue: *ParitySupportRowQueue,
    error_state: *ParitySupportRowErrorState,
    worker_index: usize,
    totals: LayerAccumulation = .{},
};

fn collisionComplexPairDensityCm6(
    context: *const Context,
    altitude_km: f64,
    air_number_density_cm3: f64,
    fallback_oxygen_number_density_cm3: f64,
) f64 {
    const node_count = context.spectroscopy_profile_altitudes_km.len;
    if (context.collision_induced_absorption == null and !context.operational_o2o2_lut.enabled()) {
        return fallback_oxygen_number_density_cm3 * fallback_oxygen_number_density_cm3;
    }
    if (node_count < 3 or
        node_count > max_collision_complex_profile_nodes or
        context.spectroscopy_profile_pressures_hpa.len != node_count or
        context.spectroscopy_profile_temperatures_k.len != node_count or
        air_number_density_cm3 <= 0.0)
    {
        return fallback_oxygen_number_density_cm3 * fallback_oxygen_number_density_cm3;
    }

    var altitudes_km: [max_collision_complex_profile_nodes]f64 = undefined;
    var log_complex_vmr_fraction: [max_collision_complex_profile_nodes]f64 = undefined;
    for (0..node_count) |index| {
        const pressure_hpa = context.spectroscopy_profile_pressures_hpa[index];
        const temperature_k = context.spectroscopy_profile_temperatures_k[index];
        const node_air_density_cm3 = pressure_hpa / @max(temperature_k, 1.0e-9) / boltzmann_hpa_cm3_per_k;
        const parent_fraction = Spectroscopy.speciesMixingRatioAtPressure(
            context.scene,
            .o2,
            &.{},
            pressure_hpa,
            oxygen_volume_mixing_ratio,
        ) orelse oxygen_volume_mixing_ratio;
        const parent_density_cm3 = node_air_density_cm3 * parent_fraction;
        const complex_vmr_fraction = if (node_air_density_cm3 > 0.0)
            parent_density_cm3 * parent_density_cm3 / node_air_density_cm3
        else
            0.0;
        if (complex_vmr_fraction <= 0.0) {
            return fallback_oxygen_number_density_cm3 * fallback_oxygen_number_density_cm3;
        }
        altitudes_km[index] = context.spectroscopy_profile_altitudes_km[index];
        log_complex_vmr_fraction[index] = @log(complex_vmr_fraction);
    }

    if (altitude_km <= altitudes_km[0]) {
        return @exp(log_complex_vmr_fraction[0]) * air_number_density_cm3;
    }
    if (altitude_km >= altitudes_km[node_count - 1]) {
        return @exp(log_complex_vmr_fraction[node_count - 1]) * air_number_density_cm3;
    }
    const sampled_log_vmr = spline.sampleEndpointSecant(
        altitudes_km[0..node_count],
        log_complex_vmr_fraction[0..node_count],
        altitude_km,
    ) catch return fallback_oxygen_number_density_cm3 * fallback_oxygen_number_density_cm3;
    return @exp(sampled_log_vmr) * air_number_density_cm3;
}

pub const LayerAccumulation = struct {
    base_single_scatter_albedo: f64 = 0.0,
    aerosol_single_scatter_albedo: f64 = 0.0,
    cloud_single_scatter_albedo: f64 = 0.0,
    total_optical_depth: f64 = 0.0,
    total_temperature_weighted: f64 = 0.0,
    total_pressure_weighted: f64 = 0.0,
    total_weight: f64 = 0.0,
    air_column_density_factor: f64 = 0.0,
    oxygen_column_density_factor: f64 = 0.0,
    column_density_factor: f64 = 0.0,
    cia_pair_path_factor_cm5: f64 = 0.0,
    total_gas_optical_depth: f64 = 0.0,
    total_cia_optical_depth: f64 = 0.0,
    total_aerosol_optical_depth: f64 = 0.0,
    total_aerosol_base_optical_depth: f64 = 0.0,
    total_cloud_optical_depth: f64 = 0.0,
    total_cloud_base_optical_depth: f64 = 0.0,
    total_scattering_optical_depth: f64 = 0.0,
    total_d_optical_depth_d_temperature: f64 = 0.0,
    depolarization_weighted: f64 = 0.0,
};

pub fn populate(
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
) !LayerAccumulation {
    var totals: LayerAccumulation = .{
        .base_single_scatter_albedo = PhaseFunctions.computeSingleScatterAlbedo(
            context.scene,
            context.midpoint_nm,
        ),
    };

    const aerosol_sublayer_distribution = try ParticleProfiles.buildAerosolSublayerDistribution(
        allocator,
        context.scene,
        context.vertical_grid.borrow(),
    );
    defer allocator.free(aerosol_sublayer_distribution);
    const cloud_sublayer_distribution = try ParticleProfiles.buildCloudSublayerDistribution(
        allocator,
        context.scene,
        context.vertical_grid.borrow(),
    );
    defer allocator.free(cloud_sublayer_distribution);

    const aerosol_mie_point = if (context.aerosol_mie) |table| table.interpolate(context.midpoint_nm) else null;
    const cloud_mie_point = if (context.cloud_mie) |table| table.interpolate(context.midpoint_nm) else null;
    const aerosol_phase_coefficients = if (aerosol_mie_point) |point|
        PhaseFunctions.phaseCoefficientsFromCompact(point.phase_coefficients)
    else
        PhaseFunctions.hgPhaseCoefficientsWithThreshold(
            context.scene.aerosol.asymmetry_factor,
            context.scene.phase_function_truncation_threshold,
        );
    const cloud_phase_coefficients = if (cloud_mie_point) |point|
        PhaseFunctions.phaseCoefficientsFromCompact(point.phase_coefficients)
    else
        PhaseFunctions.hgPhaseCoefficientsWithThreshold(
            context.scene.cloud.asymmetry_factor,
            context.scene.phase_function_truncation_threshold,
        );
    totals.aerosol_single_scatter_albedo = if (aerosol_mie_point) |point|
        point.single_scatter_albedo
    else
        context.scene.aerosol.single_scatter_albedo;
    totals.cloud_single_scatter_albedo = if (cloud_mie_point) |point|
        point.single_scatter_albedo
    else
        context.scene.cloud.single_scatter_albedo;
    const aerosol_extinction_scale = if (aerosol_mie_point) |point| point.extinction_scale else 1.0;
    const cloud_extinction_scale = if (cloud_mie_point) |point| point.extinction_scale else 1.0;
    const aerosol_fraction = if (context.scene.aerosol.fraction.enabled)
        context.scene.aerosol.fraction.valueAtWavelength(context.midpoint_nm)
    else if (context.scene.aerosol.enabled)
        @as(f64, 1.0)
    else
        @as(f64, 0.0);
    const cloud_fraction = if (context.scene.cloud.fraction.enabled)
        context.scene.cloud.fraction.valueAtWavelength(context.midpoint_nm)
    else if (context.scene.cloud.enabled)
        @as(f64, 1.0)
    else
        @as(f64, 0.0);
    var profile_spectroscopy_cache = LayerSpectroscopy.ProfileSpectroscopyCache.init(
        context,
        absorbers,
        context.midpoint_nm,
    );
    const profile_spectroscopy_cache_ptr = if (profile_spectroscopy_cache.node_count != 0)
        &profile_spectroscopy_cache
    else
        null;

    if (usesDisamarParitySupportGrid(context)) {
        if (canParallelPopulateParitySupportRows(context, absorbers, profile_spectroscopy_cache_ptr)) {
            try populateParitySupportRowsParallel(
                allocator,
                context,
                absorbers,
                profile_spectroscopy_cache_ptr,
                &totals,
                aerosol_sublayer_distribution,
                cloud_sublayer_distribution,
                aerosol_phase_coefficients,
                cloud_phase_coefficients,
                totals.aerosol_single_scatter_albedo,
                totals.cloud_single_scatter_albedo,
                aerosol_extinction_scale,
                cloud_extinction_scale,
                aerosol_fraction,
                cloud_fraction,
            );
        } else {
            try populateParitySupportRows(
                allocator,
                context,
                absorbers,
                profile_spectroscopy_cache_ptr,
                &totals,
                aerosol_sublayer_distribution,
                cloud_sublayer_distribution,
                aerosol_phase_coefficients,
                cloud_phase_coefficients,
                totals.aerosol_single_scatter_albedo,
                totals.cloud_single_scatter_albedo,
                aerosol_extinction_scale,
                cloud_extinction_scale,
                aerosol_fraction,
                cloud_fraction,
            );
        }
        for (context.layers, 0..) |*layer, index| {
            reduceParityLayer(
                context,
                totals.aerosol_single_scatter_albedo,
                totals.cloud_single_scatter_albedo,
                layer,
                index,
            );
        }
        return totals;
    }

    for (context.layers, 0..) |*layer, index| {
        try populateLayer(
            allocator,
            context,
            absorbers,
            profile_spectroscopy_cache_ptr,
            &totals,
            aerosol_sublayer_distribution,
            cloud_sublayer_distribution,
            aerosol_phase_coefficients,
            cloud_phase_coefficients,
            totals.aerosol_single_scatter_albedo,
            totals.cloud_single_scatter_albedo,
            aerosol_extinction_scale,
            cloud_extinction_scale,
            aerosol_fraction,
            cloud_fraction,
            layer,
            index,
        );
    }

    return totals;
}

fn populateParitySupportRows(
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
    profile_spectroscopy_cache: ?*const LayerSpectroscopy.ProfileSpectroscopyCache,
    totals: *LayerAccumulation,
    aerosol_sublayer_distribution: []const f64,
    cloud_sublayer_distribution: []const f64,
    aerosol_phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64,
    cloud_phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64,
    aerosol_single_scatter_albedo: f64,
    cloud_single_scatter_albedo: f64,
    aerosol_extinction_scale: f64,
    cloud_extinction_scale: f64,
    aerosol_fraction: f64,
    cloud_fraction: f64,
) !void {
    for (0..context.sublayers.len) |write_index| {
        try populateParitySupportRow(
            allocator,
            context,
            absorbers,
            profile_spectroscopy_cache,
            totals,
            aerosol_sublayer_distribution,
            cloud_sublayer_distribution,
            aerosol_phase_coefficients,
            cloud_phase_coefficients,
            aerosol_single_scatter_albedo,
            cloud_single_scatter_albedo,
            aerosol_extinction_scale,
            cloud_extinction_scale,
            aerosol_fraction,
            cloud_fraction,
            write_index,
        );
    }
}

fn populateParitySupportRowsParallel(
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
    profile_spectroscopy_cache: ?*const LayerSpectroscopy.ProfileSpectroscopyCache,
    totals: *LayerAccumulation,
    aerosol_sublayer_distribution: []const f64,
    cloud_sublayer_distribution: []const f64,
    aerosol_phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64,
    cloud_phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64,
    aerosol_single_scatter_albedo: f64,
    cloud_single_scatter_albedo: f64,
    aerosol_extinction_scale: f64,
    cloud_extinction_scale: f64,
    aerosol_fraction: f64,
    cloud_fraction: f64,
) !void {
    const worker_count = preferredParitySupportRowWorkerCount(context.sublayers.len);
    if (worker_count == 1) {
        return populateParitySupportRows(
            allocator,
            context,
            absorbers,
            profile_spectroscopy_cache,
            totals,
            aerosol_sublayer_distribution,
            cloud_sublayer_distribution,
            aerosol_phase_coefficients,
            cloud_phase_coefficients,
            aerosol_single_scatter_albedo,
            cloud_single_scatter_albedo,
            aerosol_extinction_scale,
            cloud_extinction_scale,
            aerosol_fraction,
            cloud_fraction,
        );
    }

    var error_state = ParitySupportRowErrorState{};
    var queue: ParitySupportRowQueue = .{ .len = context.sublayers.len };
    var worker_buffer: [Trace.max_workers]ParitySupportRowWorker = undefined;
    var thread_buffer: [Trace.max_workers - 1]std.Thread = undefined;
    const workers = worker_buffer[0..worker_count];
    const threads = thread_buffer[0 .. worker_count - 1];
    var started_thread_count: usize = 0;

    for (0..worker_count) |worker_index| {
        workers[worker_index] = .{
            .allocator = allocator,
            .context = context,
            .absorbers = absorbers,
            .profile_spectroscopy_cache = profile_spectroscopy_cache,
            .aerosol_sublayer_distribution = aerosol_sublayer_distribution,
            .cloud_sublayer_distribution = cloud_sublayer_distribution,
            .aerosol_phase_coefficients = aerosol_phase_coefficients,
            .cloud_phase_coefficients = cloud_phase_coefficients,
            .aerosol_single_scatter_albedo = aerosol_single_scatter_albedo,
            .cloud_single_scatter_albedo = cloud_single_scatter_albedo,
            .aerosol_extinction_scale = aerosol_extinction_scale,
            .cloud_extinction_scale = cloud_extinction_scale,
            .aerosol_fraction = aerosol_fraction,
            .cloud_fraction = cloud_fraction,
            .queue = &queue,
            .error_state = &error_state,
            .worker_index = worker_index,
        };
        if (worker_index + 1 < worker_count) {
            threads[started_thread_count] = std.Thread.spawn(
                .{},
                paritySupportRowWorkerMain,
                .{&workers[worker_index]},
            ) catch {
                paritySupportRowWorkerMain(&workers[worker_index]);
                continue;
            };
            started_thread_count += 1;
        } else {
            paritySupportRowWorkerMain(&workers[worker_index]);
        }
    }
    for (threads[0..started_thread_count]) |thread| thread.join();
    if (error_state.err) |err| return err;

    for (workers) |worker| {
        mergeParitySupportTotals(totals, worker.totals);
    }
}

fn paritySupportRowWorkerMain(worker: *ParitySupportRowWorker) void {
    var thread_name_buffer: [64]u8 = undefined;
    const thread_name = std.fmt.bufPrintZ(
        &thread_name_buffer,
        "zdisamar-accum-{d}",
        .{worker.worker_index},
    ) catch "zdisamar-accum-worker";
    Trace.setThreadName(thread_name);

    const worker_zone = Trace.staticZone(@src(), "optical_prepare.parity_rows_worker");
    worker_zone.value(@intCast(worker.worker_index));
    defer worker_zone.end();

    while (worker.queue.next()) |chunk| {
        const chunk_zone = Trace.deepStaticZone(@src(), "optical_prepare.parity_rows_chunk");
        chunk_zone.value(@intCast(chunk.end - chunk.start));
        defer chunk_zone.end();

        for (chunk.start..chunk.end) |write_index| {
            populateParitySupportRow(
                worker.allocator,
                worker.context,
                worker.absorbers,
                worker.profile_spectroscopy_cache,
                &worker.totals,
                worker.aerosol_sublayer_distribution,
                worker.cloud_sublayer_distribution,
                worker.aerosol_phase_coefficients,
                worker.cloud_phase_coefficients,
                worker.aerosol_single_scatter_albedo,
                worker.cloud_single_scatter_albedo,
                worker.aerosol_extinction_scale,
                worker.cloud_extinction_scale,
                worker.aerosol_fraction,
                worker.cloud_fraction,
                write_index,
            ) catch |err| {
                worker.error_state.store(err);
                return;
            };
        }
    }
}

fn populateParitySupportRow(
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
    profile_spectroscopy_cache: ?*const LayerSpectroscopy.ProfileSpectroscopyCache,
    totals: *LayerAccumulation,
    aerosol_sublayer_distribution: []const f64,
    cloud_sublayer_distribution: []const f64,
    aerosol_phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64,
    cloud_phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64,
    aerosol_single_scatter_albedo: f64,
    cloud_single_scatter_albedo: f64,
    aerosol_extinction_scale: f64,
    cloud_extinction_scale: f64,
    aerosol_fraction: f64,
    cloud_fraction: f64,
    write_index: usize,
) !void {
    const current_layer_index = layerIndexForSublayer(context, write_index);
    const layer_thickness_km = @max(
        context.vertical_grid.layer_top_altitudes_km[current_layer_index] -
            context.vertical_grid.layer_bottom_altitudes_km[current_layer_index],
        1.0e-9,
    );
    var ignored_density_weight: f64 = 0.0;
    var ignored_density_sum: f64 = 0.0;
    var ignored_temperature_sum: f64 = 0.0;
    var ignored_pressure_sum: f64 = 0.0;
    var ignored_line_sigma_sum: f64 = 0.0;
    var ignored_line_mixing_sum: f64 = 0.0;
    var ignored_d_cross_section_sum: f64 = 0.0;
    var ignored_gas_optical_depth: f64 = 0.0;
    var ignored_gas_scattering_optical_depth: f64 = 0.0;
    var ignored_cia_optical_depth: f64 = 0.0;
    var ignored_aerosol_optical_depth: f64 = 0.0;
    var ignored_aerosol_base_optical_depth: f64 = 0.0;
    var ignored_cloud_optical_depth: f64 = 0.0;
    var ignored_cloud_base_optical_depth: f64 = 0.0;
    const layer_start_index = @as(usize, @intCast(context.layers[current_layer_index].sublayer_start_index));
    try populateSublayer(
        allocator,
        context,
        absorbers,
        profile_spectroscopy_cache,
        totals,
        aerosol_sublayer_distribution,
        cloud_sublayer_distribution,
        aerosol_phase_coefficients,
        cloud_phase_coefficients,
        aerosol_single_scatter_albedo,
        cloud_single_scatter_albedo,
        aerosol_extinction_scale,
        cloud_extinction_scale,
        aerosol_fraction,
        cloud_fraction,
        layer_thickness_km,
        current_layer_index,
        if (write_index >= layer_start_index) write_index - layer_start_index else 0,
        write_index,
        &ignored_density_weight,
        &ignored_density_sum,
        &ignored_temperature_sum,
        &ignored_pressure_sum,
        &ignored_line_sigma_sum,
        &ignored_line_mixing_sum,
        &ignored_d_cross_section_sum,
        &ignored_gas_optical_depth,
        &ignored_gas_scattering_optical_depth,
        &ignored_cia_optical_depth,
        &ignored_aerosol_optical_depth,
        &ignored_aerosol_base_optical_depth,
        &ignored_cloud_optical_depth,
        &ignored_cloud_base_optical_depth,
    );
}

fn canParallelPopulateParitySupportRows(
    context: *const Context,
    absorbers: *const Absorbers.AbsorberBuildState,
    profile_spectroscopy_cache: ?*const LayerSpectroscopy.ProfileSpectroscopyCache,
) bool {
    return context.sublayers.len >= min_parallel_parity_support_row_count and
        profile_spectroscopy_cache != null and
        absorbers.owned_cross_section_absorbers.len == 0 and
        absorbers.owned_line_absorbers.len == 0 and
        absorbers.strong_line_states == null;
}

fn preferredParitySupportRowWorkerCount(row_count: usize) usize {
    if (row_count < min_parallel_parity_support_row_count) return 1;
    const cpu_count = std.Thread.getCpuCount() catch 1;
    return @min(Trace.max_workers, @min(cpu_count, @max(@as(usize, 1), row_count / min_parallel_parity_support_row_count)));
}

fn layerIndexForSublayer(context: *const Context, write_index: usize) usize {
    var layer_index: usize = 0;
    while (layer_index + 1 < context.layers.len and
        write_index >= @as(usize, @intCast(context.layers[layer_index + 1].sublayer_start_index)))
    {
        layer_index += 1;
    }
    return layer_index;
}

fn mergeParitySupportTotals(total: *LayerAccumulation, local: LayerAccumulation) void {
    total.air_column_density_factor += local.air_column_density_factor;
    total.oxygen_column_density_factor += local.oxygen_column_density_factor;
    total.column_density_factor += local.column_density_factor;
    total.cia_pair_path_factor_cm5 += local.cia_pair_path_factor_cm5;
    total.total_d_optical_depth_d_temperature += local.total_d_optical_depth_d_temperature;
}

fn reduceParityLayer(
    context: *Context,
    aerosol_single_scatter_albedo: f64,
    cloud_single_scatter_albedo: f64,
    layer: *State.PreparedLayer,
    index: usize,
) void {
    const layer_top_altitude_km = context.vertical_grid.layer_top_altitudes_km[index];
    const layer_bottom_altitude_km = context.vertical_grid.layer_bottom_altitudes_km[index];
    const layer_top_pressure_hpa = context.vertical_grid.layer_top_pressures_hpa[index];
    const layer_bottom_pressure_hpa = context.vertical_grid.layer_bottom_pressures_hpa[index];
    const layer_sublayer_start_index = context.vertical_grid.layer_sublayer_starts[index];
    const layer_sublayer_count = context.vertical_grid.layer_sublayer_counts[index];
    const layer_interval_index_1based = context.vertical_grid.layer_interval_indices_1based[index];
    const layer_subcolumn_label = context.vertical_grid.layer_subcolumn_labels[index];
    const start_index: usize = @intCast(layer_sublayer_start_index);
    const count: usize = @intCast(layer_sublayer_count);
    const support_rows = context.sublayers[start_index .. start_index + count];
    const lower_boundary = support_rows[0];

    var layer_line_sigma_sum: f64 = 0.0;
    var layer_line_mixing_sum: f64 = 0.0;
    var layer_d_cross_section_sum: f64 = 0.0;
    var layer_gas_optical_depth: f64 = 0.0;
    var layer_gas_scattering_optical_depth: f64 = 0.0;
    var layer_cia_optical_depth: f64 = 0.0;
    var layer_aerosol_optical_depth: f64 = 0.0;
    var layer_aerosol_base_optical_depth: f64 = 0.0;
    var layer_cloud_optical_depth: f64 = 0.0;
    var layer_cloud_base_optical_depth: f64 = 0.0;
    var support_point_count: usize = 0;

    if (support_rows.len > 2) {
        for (support_rows[1 .. support_rows.len - 1]) |support_row| {
            layer_line_sigma_sum += support_row.line_cross_section_cm2_per_molecule;
            layer_line_mixing_sum += support_row.line_mixing_cross_section_cm2_per_molecule;
            layer_d_cross_section_sum += support_row.d_cross_section_d_temperature_cm2_per_molecule_per_k;
            layer_gas_optical_depth += support_row.gas_absorption_optical_depth + support_row.gas_scattering_optical_depth;
            layer_gas_scattering_optical_depth += support_row.gas_scattering_optical_depth;
            layer_cia_optical_depth += support_row.cia_optical_depth;
            layer_aerosol_optical_depth += support_row.aerosol_optical_depth;
            layer_aerosol_base_optical_depth += support_row.aerosol_base_optical_depth;
            layer_cloud_optical_depth += support_row.cloud_optical_depth;
            layer_cloud_base_optical_depth += support_row.cloud_base_optical_depth;
            support_point_count += 1;
        }
    }

    const aerosol_scattering = layer_aerosol_optical_depth * aerosol_single_scatter_albedo;
    const cloud_scattering = layer_cloud_optical_depth * cloud_single_scatter_albedo;
    const gas_scattering = layer_gas_scattering_optical_depth;
    const optical_depth =
        layer_gas_optical_depth +
        layer_cia_optical_depth +
        layer_aerosol_optical_depth +
        layer_cloud_optical_depth;
    const scattering = aerosol_scattering + cloud_scattering + gas_scattering;
    const absorption = @max(optical_depth - scattering, 1.0e-9);
    const layer_single_scatter_albedo = scattering / @max(scattering + absorption, 1.0e-9);
    const depolarization = PhaseFunctions.computeLayerDepolarization(
        context.scene,
        gas_scattering,
        aerosol_scattering,
        cloud_scattering,
    );

    layer.* = .{
        .layer_index = @intCast(index),
        .sublayer_start_index = layer_sublayer_start_index,
        .sublayer_count = layer_sublayer_count,
        .altitude_km = 0.5 * (layer_top_altitude_km + layer_bottom_altitude_km),
        .pressure_hpa = lower_boundary.pressure_hpa,
        .temperature_k = lower_boundary.temperature_k,
        .number_density_cm3 = lower_boundary.number_density_cm3,
        .continuum_cross_section_cm2_per_molecule = lower_boundary.continuum_cross_section_cm2_per_molecule,
        .line_cross_section_cm2_per_molecule = if (support_point_count == 0) 0.0 else layer_line_sigma_sum / @as(f64, @floatFromInt(support_point_count)),
        .line_mixing_cross_section_cm2_per_molecule = if (support_point_count == 0) 0.0 else layer_line_mixing_sum / @as(f64, @floatFromInt(support_point_count)),
        .cia_optical_depth = layer_cia_optical_depth,
        .d_cross_section_d_temperature_cm2_per_molecule_per_k = if (support_point_count == 0) 0.0 else layer_d_cross_section_sum / @as(f64, @floatFromInt(support_point_count)),
        .gas_optical_depth = layer_gas_optical_depth,
        .gas_scattering_optical_depth = gas_scattering,
        .aerosol_optical_depth = layer_aerosol_optical_depth,
        .aerosol_base_optical_depth = layer_aerosol_base_optical_depth,
        .cloud_optical_depth = layer_cloud_optical_depth,
        .cloud_base_optical_depth = layer_cloud_base_optical_depth,
        .layer_single_scatter_albedo = layer_single_scatter_albedo,
        .depolarization_factor = depolarization,
        .optical_depth = optical_depth,
        .top_altitude_km = layer_top_altitude_km,
        .bottom_altitude_km = layer_bottom_altitude_km,
        .top_pressure_hpa = layer_top_pressure_hpa,
        .bottom_pressure_hpa = layer_bottom_pressure_hpa,
        .interval_index_1based = layer_interval_index_1based,
        .subcolumn_label = layer_subcolumn_label,
        .aerosol_fraction = lower_boundary.aerosol_fraction,
        .cloud_fraction = lower_boundary.cloud_fraction,
    };
}

fn populateLayer(
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
    profile_spectroscopy_cache: ?*const LayerSpectroscopy.ProfileSpectroscopyCache,
    totals: *LayerAccumulation,
    aerosol_sublayer_distribution: []const f64,
    cloud_sublayer_distribution: []const f64,
    aerosol_phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64,
    cloud_phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64,
    aerosol_single_scatter_albedo: f64,
    cloud_single_scatter_albedo: f64,
    aerosol_extinction_scale: f64,
    cloud_extinction_scale: f64,
    aerosol_fraction: f64,
    cloud_fraction: f64,
    layer: *State.PreparedLayer,
    index: usize,
) !void {
    const layer_top_altitude_km = context.vertical_grid.layer_top_altitudes_km[index];
    const layer_bottom_altitude_km = context.vertical_grid.layer_bottom_altitudes_km[index];
    const layer_center_altitude_km = 0.5 * (layer_top_altitude_km + layer_bottom_altitude_km);
    const layer_top_pressure_hpa = context.vertical_grid.layer_top_pressures_hpa[index];
    const layer_bottom_pressure_hpa = context.vertical_grid.layer_bottom_pressures_hpa[index];
    const layer_sublayer_start_index = context.vertical_grid.layer_sublayer_starts[index];
    const layer_sublayer_count = context.vertical_grid.layer_sublayer_counts[index];
    const layer_interval_index_1based = context.vertical_grid.layer_interval_indices_1based[index];
    const layer_subcolumn_label = context.vertical_grid.layer_subcolumn_labels[index];
    const layer_thickness_km = @max(layer_top_altitude_km - layer_bottom_altitude_km, 1.0e-9);

    var layer_density_weight: f64 = 0.0;
    var layer_density_sum: f64 = 0.0;
    var layer_temperature_sum: f64 = 0.0;
    var layer_pressure_sum: f64 = 0.0;
    var layer_line_sigma_sum: f64 = 0.0;
    var layer_line_mixing_sum: f64 = 0.0;
    var layer_d_cross_section_sum: f64 = 0.0;
    var layer_gas_optical_depth: f64 = 0.0;
    var layer_gas_scattering_optical_depth: f64 = 0.0;
    var layer_cia_optical_depth: f64 = 0.0;
    var layer_aerosol_optical_depth: f64 = 0.0;
    var layer_aerosol_base_optical_depth: f64 = 0.0;
    var layer_cloud_optical_depth: f64 = 0.0;
    var layer_cloud_base_optical_depth: f64 = 0.0;

    for (0..layer_sublayer_count) |sublayer_index| {
        const write_index = @as(usize, layer_sublayer_start_index) + sublayer_index;
        try populateSublayer(
            allocator,
            context,
            absorbers,
            profile_spectroscopy_cache,
            totals,
            aerosol_sublayer_distribution,
            cloud_sublayer_distribution,
            aerosol_phase_coefficients,
            cloud_phase_coefficients,
            aerosol_single_scatter_albedo,
            cloud_single_scatter_albedo,
            aerosol_extinction_scale,
            cloud_extinction_scale,
            aerosol_fraction,
            cloud_fraction,
            layer_thickness_km,
            index,
            sublayer_index,
            write_index,
            &layer_density_weight,
            &layer_density_sum,
            &layer_temperature_sum,
            &layer_pressure_sum,
            &layer_line_sigma_sum,
            &layer_line_mixing_sum,
            &layer_d_cross_section_sum,
            &layer_gas_optical_depth,
            &layer_gas_scattering_optical_depth,
            &layer_cia_optical_depth,
            &layer_aerosol_optical_depth,
            &layer_aerosol_base_optical_depth,
            &layer_cloud_optical_depth,
            &layer_cloud_base_optical_depth,
        );
    }

    const density = layer_density_sum;
    const temperature = if (layer_density_weight == 0.0) 0.0 else layer_temperature_sum / layer_density_weight;
    const pressure = if (layer_density_weight == 0.0) 0.0 else layer_pressure_sum / layer_density_weight;
    const gas_optical_depth = layer_gas_optical_depth;
    const aerosol_optical_depth = layer_aerosol_optical_depth;
    const aerosol_base_optical_depth = layer_aerosol_base_optical_depth;
    const cloud_optical_depth = layer_cloud_optical_depth;
    const cloud_base_optical_depth = layer_cloud_base_optical_depth;
    const optical_depth = gas_optical_depth + layer_cia_optical_depth + aerosol_optical_depth + cloud_optical_depth;
    const aerosol_scattering = aerosol_optical_depth * aerosol_single_scatter_albedo;
    const cloud_scattering = cloud_optical_depth * cloud_single_scatter_albedo;
    const gas_scattering = layer_gas_scattering_optical_depth;
    const scattering = aerosol_scattering + cloud_scattering + gas_scattering;
    const absorption = @max(optical_depth - scattering, 1e-9);
    const layer_single_scatter_albedo = scattering / @max(scattering + absorption, 1e-9);
    const depolarization = PhaseFunctions.computeLayerDepolarization(
        context.scene,
        gas_scattering,
        aerosol_scattering,
        cloud_scattering,
    );

    totals.total_optical_depth += optical_depth;
    totals.total_temperature_weighted += temperature * density;
    totals.total_pressure_weighted += pressure * density;
    totals.total_weight += density;
    totals.total_gas_optical_depth += gas_optical_depth;
    totals.total_cia_optical_depth += layer_cia_optical_depth;
    totals.total_aerosol_optical_depth += aerosol_optical_depth;
    totals.total_aerosol_base_optical_depth += aerosol_base_optical_depth;
    totals.total_cloud_optical_depth += cloud_optical_depth;
    totals.total_cloud_base_optical_depth += cloud_base_optical_depth;
    totals.total_scattering_optical_depth += scattering;
    totals.depolarization_weighted += depolarization * optical_depth;

    layer.* = .{
        .layer_index = @intCast(index),
        .sublayer_start_index = layer_sublayer_start_index,
        .sublayer_count = layer_sublayer_count,
        .altitude_km = layer_center_altitude_km,
        .pressure_hpa = pressure,
        .temperature_k = temperature,
        .number_density_cm3 = density,
        .continuum_cross_section_cm2_per_molecule = absorbers.mean_sigma,
        .line_cross_section_cm2_per_molecule = layer_line_sigma_sum / @as(f64, @floatFromInt(@max(layer_sublayer_count, 1))),
        .line_mixing_cross_section_cm2_per_molecule = layer_line_mixing_sum / @as(f64, @floatFromInt(@max(layer_sublayer_count, 1))),
        .cia_optical_depth = layer_cia_optical_depth,
        .d_cross_section_d_temperature_cm2_per_molecule_per_k = layer_d_cross_section_sum / @as(f64, @floatFromInt(@max(layer_sublayer_count, 1))),
        .gas_optical_depth = gas_optical_depth,
        .gas_scattering_optical_depth = gas_scattering,
        .aerosol_optical_depth = aerosol_optical_depth,
        .aerosol_base_optical_depth = aerosol_base_optical_depth,
        .cloud_optical_depth = cloud_optical_depth,
        .cloud_base_optical_depth = cloud_base_optical_depth,
        .layer_single_scatter_albedo = layer_single_scatter_albedo,
        .depolarization_factor = depolarization,
        .optical_depth = optical_depth,
        .top_altitude_km = layer_top_altitude_km,
        .bottom_altitude_km = layer_bottom_altitude_km,
        .top_pressure_hpa = layer_top_pressure_hpa,
        .bottom_pressure_hpa = layer_bottom_pressure_hpa,
        .interval_index_1based = layer_interval_index_1based,
        .subcolumn_label = layer_subcolumn_label,
        .aerosol_fraction = aerosol_fraction,
        .cloud_fraction = cloud_fraction,
    };
}

fn populateSublayer(
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
    profile_spectroscopy_cache: ?*const LayerSpectroscopy.ProfileSpectroscopyCache,
    totals: *LayerAccumulation,
    aerosol_sublayer_distribution: []const f64,
    cloud_sublayer_distribution: []const f64,
    aerosol_phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64,
    cloud_phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64,
    aerosol_single_scatter_albedo: f64,
    cloud_single_scatter_albedo: f64,
    aerosol_extinction_scale: f64,
    cloud_extinction_scale: f64,
    aerosol_fraction: f64,
    cloud_fraction: f64,
    layer_thickness_km: f64,
    parent_layer_index: usize,
    sublayer_index: usize,
    write_index: usize,
    layer_density_weight: *f64,
    layer_density_sum: *f64,
    layer_temperature_sum: *f64,
    layer_pressure_sum: *f64,
    layer_line_sigma_sum: *f64,
    layer_line_mixing_sum: *f64,
    layer_d_cross_section_sum: *f64,
    layer_gas_optical_depth: *f64,
    layer_gas_scattering_optical_depth: *f64,
    layer_cia_optical_depth: *f64,
    layer_aerosol_optical_depth: *f64,
    layer_aerosol_base_optical_depth: *f64,
    layer_cloud_optical_depth: *f64,
    layer_cloud_base_optical_depth: *f64,
) !void {
    const top_altitude_km = context.vertical_grid.sublayer_top_altitudes_km[write_index];
    const bottom_altitude_km = context.vertical_grid.sublayer_bottom_altitudes_km[write_index];
    const top_pressure_hpa = context.vertical_grid.sublayer_top_pressures_hpa[write_index];
    const bottom_pressure_hpa = context.vertical_grid.sublayer_bottom_pressures_hpa[write_index];
    const altitude_km = context.vertical_grid.sublayer_mid_altitudes_km[write_index];
    const disamar_support_grid = usesDisamarParitySupportGrid(context);
    const parity_support_state = if (disamar_support_grid)
        paritySupportThermodynamicsFromProfile(context.profile, altitude_km)
    else
        null;
    const pressure = if (parity_support_state) |state|
        state.pressure_hpa
    else if (context.scene.atmosphere.interval_grid.enabled() and
        top_pressure_hpa > 0.0 and
        bottom_pressure_hpa > 0.0)
        @sqrt(top_pressure_hpa * bottom_pressure_hpa)
    else
        context.profile.interpolatePressure(altitude_km);
    const temperature = if (parity_support_state) |state|
        state.temperature_k
    else
        context.profile.interpolateTemperature(altitude_km);
    const density = if (parity_support_state) |state|
        state.density_cm3
    else
        context.profile.interpolateDensity(altitude_km);
    const support_weight_km = if (disamar_support_grid)
        context.vertical_grid.sublayer_support_weights_km[write_index]
    else
        @max(top_altitude_km - bottom_altitude_km, 0.0);
    const sublayer_path_length_cm = if (usesDisamarParitySupportGrid(context))
        @max(support_weight_km, 0.0) * centimeters_per_kilometer
    else
        @max(support_weight_km, 1.0e-9) * centimeters_per_kilometer;
    const sublayer_weight = support_weight_km / layer_thickness_km;
    const oxygen_mixing_ratio = Spectroscopy.speciesMixingRatioAtPressure(
        context.scene,
        .o2,
        &.{},
        pressure,
        oxygen_volume_mixing_ratio,
    ) orelse oxygen_volume_mixing_ratio;

    var absorber_density_cm3: f64 = 0.0;
    var cross_section_absorber_density_cm3: f64 = 0.0;
    var cross_section_optical_depth: f64 = 0.0;
    var cross_section_d_optical_depth_d_temperature: f64 = 0.0;
    for (absorbers.owned_cross_section_absorbers, absorbers.active_cross_section_absorbers) |*cross_section_absorber, active_absorber| {
        const absorber_mixing_ratio = Spectroscopy.speciesMixingRatioAtPressure(
            context.scene,
            cross_section_absorber.species,
            active_absorber.volume_mixing_ratio_profile_ppmv,
            pressure,
            if (cross_section_absorber.species == .o2) oxygen_volume_mixing_ratio else null,
        ) orelse return error.InvalidRequest;
        const absorber_density = density * absorber_mixing_ratio;
        cross_section_absorber.number_densities_cm3[write_index] = absorber_density;
        cross_section_absorber_density_cm3 += absorber_density;
        if (absorber_density <= 0.0) continue;

        const sigma = cross_section_absorber.sigmaAt(context.midpoint_nm, temperature, pressure);
        const d_sigma_d_temperature = cross_section_absorber.dSigmaDTemperatureAt(
            context.midpoint_nm,
            temperature,
            pressure,
        );
        cross_section_optical_depth += sigma * absorber_density * sublayer_path_length_cm;
        cross_section_d_optical_depth_d_temperature +=
            d_sigma_d_temperature * absorber_density * sublayer_path_length_cm;
        cross_section_absorber.column_density_factor += absorber_density * sublayer_path_length_cm;
    }

    const spectroscopy_eval = try LayerSpectroscopy.resolveSpectroscopyEvaluation(
        allocator,
        context,
        absorbers,
        write_index,
        density,
        pressure,
        temperature,
        oxygen_mixing_ratio,
        sublayer_path_length_cm,
        &absorber_density_cm3,
        profile_spectroscopy_cache,
    );

    const o2_density_cm3 = density * oxygen_mixing_ratio;
    const continuum_density_cm3 = LayerSpectroscopy.continuumCarrierDensity(
        absorbers,
        context,
        write_index,
        absorber_density_cm3,
        o2_density_cm3,
    );
    const total_gas_density_cm3 = if (absorbers.owned_cross_section_absorbers.len != 0 and !absorbers.has_line_absorbers)
        cross_section_absorber_density_cm3
    else
        absorber_density_cm3 + cross_section_absorber_density_cm3;
    const line_gas_column_density_cm2 = absorber_density_cm3 * sublayer_path_length_cm;
    const continuum_column_density_cm2 = continuum_density_cm3 * sublayer_path_length_cm;
    const total_gas_column_density_cm2 = total_gas_density_cm3 * sublayer_path_length_cm;
    const molecular_gas_optical_depth =
        absorbers.midpoint_continuum_sigma * continuum_column_density_cm2 +
        spectroscopy_eval.total_sigma_cm2_per_molecule * line_gas_column_density_cm2 +
        cross_section_optical_depth;
    const cia_sigma_cm5_per_molecule2 = if (context.operational_o2o2_lut.enabled())
        context.operational_o2o2_lut.sigmaAt(context.midpoint_nm, temperature, pressure)
    else if (context.collision_induced_absorption) |cia_table|
        cia_table.sigmaAt(context.midpoint_nm, temperature)
    else
        0.0;
    const d_cia_sigma_d_temperature = if (context.operational_o2o2_lut.enabled())
        context.operational_o2o2_lut.dSigmaDTemperatureAt(context.midpoint_nm, temperature, pressure)
    else if (context.collision_induced_absorption) |cia_table|
        cia_table.dSigmaDTemperatureAt(context.midpoint_nm, temperature)
    else
        0.0;
    const cia_pair_density_cm6 = collisionComplexPairDensityCm6(
        context,
        altitude_km,
        density,
        o2_density_cm3,
    );
    const cia_pair_column_factor_cm5 = cia_pair_density_cm6 * sublayer_path_length_cm;
    const cia_optical_depth = cia_sigma_cm5_per_molecule2 * cia_pair_column_factor_cm5;
    const gas_scattering_optical_depth = Rayleigh.scatteringOpticalDepthForColumn(
        context.midpoint_nm,
        density * sublayer_path_length_cm,
    );
    const gas_absorption_optical_depth = molecular_gas_optical_depth;
    const gas_extinction_optical_depth = gas_absorption_optical_depth + cia_optical_depth + gas_scattering_optical_depth;
    const d_cia_optical_depth_d_temperature = d_cia_sigma_d_temperature * cia_pair_column_factor_cm5;
    const d_gas_optical_depth_d_temperature =
        spectroscopy_eval.d_sigma_d_temperature_cm2_per_molecule_per_k * line_gas_column_density_cm2 +
        cross_section_d_optical_depth_d_temperature;
    const aerosol_base_optical_depth = aerosol_sublayer_distribution[write_index] * aerosol_extinction_scale;
    const cloud_base_optical_depth = cloud_sublayer_distribution[write_index] * cloud_extinction_scale;
    const aerosol_optical_depth = aerosol_base_optical_depth * aerosol_fraction;
    const cloud_optical_depth = cloud_base_optical_depth * cloud_fraction;
    const aerosol_scattering_optical_depth = aerosol_optical_depth * aerosol_single_scatter_albedo;
    const cloud_scattering_optical_depth = cloud_optical_depth * cloud_single_scatter_albedo;
    const combined_phase_coefficients = PhaseFunctions.combinePhaseCoefficients(
        context.midpoint_nm,
        gas_scattering_optical_depth,
        aerosol_scattering_optical_depth,
        cloud_scattering_optical_depth,
        aerosol_phase_coefficients,
        cloud_phase_coefficients,
    );

    context.sublayers[write_index] = .{
        .parent_layer_index = @intCast(parent_layer_index),
        .sublayer_index = @intCast(sublayer_index),
        .global_sublayer_index = @intCast(write_index),
        .altitude_km = altitude_km,
        .pressure_hpa = pressure,
        .temperature_k = temperature,
        .number_density_cm3 = density,
        .oxygen_number_density_cm3 = density * oxygen_mixing_ratio,
        .cia_pair_density_cm6 = cia_pair_density_cm6,
        .absorber_number_density_cm3 = total_gas_density_cm3,
        .path_length_cm = sublayer_path_length_cm,
        .continuum_cross_section_cm2_per_molecule = if (absorbers.owned_cross_section_absorbers.len == 0)
            absorbers.midpoint_continuum_sigma
        else
            0.0,
        .line_cross_section_cm2_per_molecule = spectroscopy_eval.line_sigma_cm2_per_molecule,
        .line_mixing_cross_section_cm2_per_molecule = spectroscopy_eval.line_mixing_sigma_cm2_per_molecule,
        .cia_sigma_cm5_per_molecule2 = cia_sigma_cm5_per_molecule2,
        .cia_optical_depth = cia_optical_depth,
        .d_cross_section_d_temperature_cm2_per_molecule_per_k = spectroscopy_eval.d_sigma_d_temperature_cm2_per_molecule_per_k,
        .gas_absorption_optical_depth = gas_absorption_optical_depth,
        .gas_scattering_optical_depth = gas_scattering_optical_depth,
        .gas_extinction_optical_depth = gas_extinction_optical_depth,
        .d_gas_optical_depth_d_temperature = d_gas_optical_depth_d_temperature,
        .d_cia_optical_depth_d_temperature = d_cia_optical_depth_d_temperature,
        .aerosol_optical_depth = aerosol_optical_depth,
        .aerosol_base_optical_depth = aerosol_base_optical_depth,
        .cloud_optical_depth = cloud_optical_depth,
        .cloud_base_optical_depth = cloud_base_optical_depth,
        .aerosol_single_scatter_albedo = aerosol_single_scatter_albedo,
        .cloud_single_scatter_albedo = cloud_single_scatter_albedo,
        .aerosol_phase_coefficients = aerosol_phase_coefficients,
        .cloud_phase_coefficients = cloud_phase_coefficients,
        .combined_phase_coefficients = combined_phase_coefficients,
        .top_altitude_km = top_altitude_km,
        .bottom_altitude_km = bottom_altitude_km,
        .top_pressure_hpa = top_pressure_hpa,
        .bottom_pressure_hpa = bottom_pressure_hpa,
        .interval_index_1based = context.vertical_grid.sublayer_interval_indices_1based[write_index],
        .subcolumn_label = context.vertical_grid.sublayer_subcolumn_labels[write_index],
        .aerosol_fraction = aerosol_fraction,
        .cloud_fraction = cloud_fraction,
        .support_row_kind = if (!disamar_support_grid)
            .physical
        else if (support_weight_km > 0.0)
            .parity_active
        else
            .parity_boundary,
    };

    layer_density_weight.* += density * sublayer_weight;
    layer_density_sum.* += density * sublayer_weight;
    layer_temperature_sum.* += temperature * density * sublayer_weight;
    layer_pressure_sum.* += pressure * density * sublayer_weight;
    layer_line_sigma_sum.* += spectroscopy_eval.line_sigma_cm2_per_molecule;
    layer_line_mixing_sum.* += spectroscopy_eval.line_mixing_sigma_cm2_per_molecule;
    layer_d_cross_section_sum.* += spectroscopy_eval.d_sigma_d_temperature_cm2_per_molecule_per_k;
    layer_gas_optical_depth.* += gas_absorption_optical_depth + gas_scattering_optical_depth;
    layer_gas_scattering_optical_depth.* += gas_scattering_optical_depth;
    layer_cia_optical_depth.* += cia_optical_depth;
    layer_aerosol_optical_depth.* += aerosol_optical_depth;
    layer_aerosol_base_optical_depth.* += aerosol_base_optical_depth;
    layer_cloud_optical_depth.* += cloud_optical_depth;
    layer_cloud_base_optical_depth.* += cloud_base_optical_depth;
    totals.air_column_density_factor += density * sublayer_path_length_cm;
    totals.oxygen_column_density_factor += o2_density_cm3 * sublayer_path_length_cm;
    totals.column_density_factor += total_gas_column_density_cm2;
    totals.cia_pair_path_factor_cm5 += cia_pair_column_factor_cm5;
    totals.total_d_optical_depth_d_temperature +=
        d_gas_optical_depth_d_temperature + d_cia_optical_depth_d_temperature;
}

fn usesDisamarParitySupportGrid(context: *const Context) bool {
    return context.scene.observation_model.resolvedChannelControls(.radiance).response.integration_mode == .disamar_hr_grid or
        context.scene.observation_model.resolvedChannelControls(.irradiance).response.integration_mode == .disamar_hr_grid;
}
