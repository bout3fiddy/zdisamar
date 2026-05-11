const ReferenceData = @import("../../../input/ReferenceData.zig");
const LineListEval = @import("../../../input/reference/spectroscopy/line_list_eval.zig");
const Context = @import("context.zig").PreparationContext;
const Absorbers = @import("absorbers.zig");
const Spectroscopy = @import("spectroscopy.zig");
const State = @import("state.zig");
const Trace = @import("../../performance_trace.zig");
const spline = @import("../../../common/math/interpolation/spline.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const oxygen_volume_mixing_ratio = Spectroscopy.default_o2_volume_mixing_ratio;
const max_spectroscopy_profile_nodes: usize = 256;
const min_parallel_profile_cache_node_count: usize = 8;
const profile_cache_node_chunk_size: usize = 2;

const ProfileCacheValueQueue = struct {
    mutex: std.Thread.Mutex = .{},
    next_index: usize = 0,
    len: usize,

    fn next(self: *ProfileCacheValueQueue) ?struct { start: usize, end: usize } {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.next_index >= self.len) return null;
        const start = self.next_index;
        const end = @min(start + profile_cache_node_chunk_size, self.len);
        self.next_index = end;
        return .{ .start = start, .end = end };
    }
};

const ProfileCacheValueWorker = struct {
    cache: *ProfileSpectroscopyCache,
    line_list: ReferenceData.SpectroscopyLineList,
    context: *const Context,
    wavelength_nm: f64,
    prepared_states: ?[]const ReferenceData.StrongLinePreparedState,
    prepared_weak_states: ?[]const ReferenceData.WeakLinePreparedState,
    wavelength_window: ?LineListEval.StrongLineWavelengthWindow,
    queue: *ProfileCacheValueQueue,
    worker_index: usize,
};

pub const ProfileSpectroscopyCache = struct {
    node_count: usize = 0,
    altitudes_km: []const f64 = &.{},
    weak_values: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,
    strong_values: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,
    line_values: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,
    line_mixing_values: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,
    total_values: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,
    weak_second: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,
    strong_second: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,
    line_second: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,
    line_mixing_second: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,
    total_second: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,

    pub fn init(
        context: *const Context,
        absorbers: *const Absorbers.AbsorberBuildState,
        wavelength_nm: f64,
    ) ProfileSpectroscopyCache {
        const line_list = absorbers.owned_lines orelse return .{};
        if (absorbers.owned_line_absorbers.len != 0 or context.operational_o2_lut.enabled()) return .{};
        const node_count = context.spectroscopy_profile_altitudes_km.len;
        if (node_count < 3 or node_count > max_spectroscopy_profile_nodes) return .{};
        if (context.spectroscopy_profile_pressures_hpa.len != node_count or
            context.spectroscopy_profile_temperatures_k.len != node_count) return .{};
        const prepared_states = if (absorbers.profile_strong_line_states) |states|
            if (states.len == node_count) states else null
        else
            null;
        const prepared_weak_states = if (absorbers.profile_weak_line_states) |states|
            if (states.len == node_count) states else null
        else
            null;

        var cache = ProfileSpectroscopyCache{
            .node_count = node_count,
            .altitudes_km = context.spectroscopy_profile_altitudes_km[0..node_count],
            .weak_values = undefined,
            .strong_values = undefined,
            .line_values = undefined,
            .line_mixing_values = undefined,
            .total_values = undefined,
            .weak_second = undefined,
            .strong_second = undefined,
            .line_second = undefined,
            .line_mixing_second = undefined,
            .total_second = undefined,
        };
        const wavelength_window = if (prepared_states != null)
            LineListEval.prepareStrongLineWavelengthWindow(line_list, wavelength_nm)
        else
            null;
        fillProfileSpectroscopyCacheValues(
            &cache,
            line_list,
            context,
            wavelength_nm,
            prepared_states,
            prepared_weak_states,
            wavelength_window,
        );
        const altitudes = cache.altitudes_km[0..node_count];
        spline.endpointSecantSecondDerivatives5(
            altitudes,
            cache.weak_values[0..node_count],
            cache.strong_values[0..node_count],
            cache.line_values[0..node_count],
            cache.line_mixing_values[0..node_count],
            cache.total_values[0..node_count],
            cache.weak_second[0..node_count],
            cache.strong_second[0..node_count],
            cache.line_second[0..node_count],
            cache.line_mixing_second[0..node_count],
            cache.total_second[0..node_count],
        ) catch return .{};
        return cache;
    }

    pub fn evaluationAtAltitude(
        self: *const ProfileSpectroscopyCache,
        altitude_km: f64,
    ) ?ReferenceData.SpectroscopyEvaluation {
        if (self.node_count < 3) return null;
        if (altitude_km < self.altitudes_km[0] or
            altitude_km > self.altitudes_km[self.node_count - 1]) return null;

        const altitudes = self.altitudes_km[0..self.node_count];
        var klo: usize = 0;
        var khi: usize = self.node_count - 1;
        while (khi - klo > 1) {
            const mid = (khi + klo) / 2;
            if (altitudes[mid] > altitude_km) {
                khi = mid;
            } else {
                klo = mid;
            }
        }
        return .{
            .weak_line_sigma_cm2_per_molecule = sampleCachedEndpointSecant(
                altitudes,
                self.weak_values[0..self.node_count],
                self.weak_second[0..self.node_count],
                altitude_km,
                klo,
                khi,
            ),
            .strong_line_sigma_cm2_per_molecule = sampleCachedEndpointSecant(
                altitudes,
                self.strong_values[0..self.node_count],
                self.strong_second[0..self.node_count],
                altitude_km,
                klo,
                khi,
            ),
            .line_sigma_cm2_per_molecule = sampleCachedEndpointSecant(
                altitudes,
                self.line_values[0..self.node_count],
                self.line_second[0..self.node_count],
                altitude_km,
                klo,
                khi,
            ),
            .line_mixing_sigma_cm2_per_molecule = sampleCachedEndpointSecant(
                altitudes,
                self.line_mixing_values[0..self.node_count],
                self.line_mixing_second[0..self.node_count],
                altitude_km,
                klo,
                khi,
            ),
            .total_sigma_cm2_per_molecule = @max(
                sampleCachedEndpointSecant(
                    altitudes,
                    self.total_values[0..self.node_count],
                    self.total_second[0..self.node_count],
                    altitude_km,
                    klo,
                    khi,
                ),
                0.0,
            ),
            .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
        };
    }
};

fn fillProfileSpectroscopyCacheValues(
    cache: *ProfileSpectroscopyCache,
    line_list: ReferenceData.SpectroscopyLineList,
    context: *const Context,
    wavelength_nm: f64,
    prepared_states: ?[]const ReferenceData.StrongLinePreparedState,
    prepared_weak_states: ?[]const ReferenceData.WeakLinePreparedState,
    wavelength_window: ?LineListEval.StrongLineWavelengthWindow,
) void {
    const worker_count = preferredProfileCacheWorkerCount(cache.node_count);
    if (worker_count == 1) {
        fillProfileSpectroscopyCacheValueRange(
            cache,
            line_list,
            context,
            wavelength_nm,
            prepared_states,
            prepared_weak_states,
            wavelength_window,
            0,
            cache.node_count,
        );
        return;
    }

    var queue: ProfileCacheValueQueue = .{ .len = cache.node_count };
    var worker_buffer: [Trace.max_workers]ProfileCacheValueWorker = undefined;
    var thread_buffer: [Trace.max_workers - 1]std.Thread = undefined;
    const workers = worker_buffer[0..worker_count];
    const threads = thread_buffer[0 .. worker_count - 1];
    var started_thread_count: usize = 0;

    for (0..worker_count) |worker_index| {
        workers[worker_index] = .{
            .cache = cache,
            .line_list = line_list,
            .context = context,
            .wavelength_nm = wavelength_nm,
            .prepared_states = prepared_states,
            .prepared_weak_states = prepared_weak_states,
            .wavelength_window = wavelength_window,
            .queue = &queue,
            .worker_index = worker_index,
        };
        if (worker_index + 1 < worker_count) {
            threads[started_thread_count] = std.Thread.spawn(
                .{},
                profileCacheValueWorkerMain,
                .{&workers[worker_index]},
            ) catch {
                profileCacheValueWorkerMain(&workers[worker_index]);
                continue;
            };
            started_thread_count += 1;
        } else {
            profileCacheValueWorkerMain(&workers[worker_index]);
        }
    }
    for (threads[0..started_thread_count]) |thread| thread.join();
}

fn profileCacheValueWorkerMain(worker: *ProfileCacheValueWorker) void {
    var thread_name_buffer: [64]u8 = undefined;
    const thread_name = std.fmt.bufPrintZ(
        &thread_name_buffer,
        "zdisamar-profile-init-{d}",
        .{worker.worker_index},
    ) catch "zdisamar-profile-init";
    Trace.setThreadName(thread_name);

    const worker_zone = Trace.staticZone(@src(), "optical_prepare.profile_cache_init_worker");
    worker_zone.value(@intCast(worker.worker_index));
    defer worker_zone.end();

    while (worker.queue.next()) |chunk| {
        const chunk_zone = Trace.deepStaticZone(@src(), "optical_prepare.profile_cache_init_chunk");
        chunk_zone.value(@intCast(chunk.end - chunk.start));
        defer chunk_zone.end();

        fillProfileSpectroscopyCacheValueRange(
            worker.cache,
            worker.line_list,
            worker.context,
            worker.wavelength_nm,
            worker.prepared_states,
            worker.prepared_weak_states,
            worker.wavelength_window,
            chunk.start,
            chunk.end,
        );
    }
}

fn fillProfileSpectroscopyCacheValueRange(
    cache: *ProfileSpectroscopyCache,
    line_list: ReferenceData.SpectroscopyLineList,
    context: *const Context,
    wavelength_nm: f64,
    prepared_states: ?[]const ReferenceData.StrongLinePreparedState,
    prepared_weak_states: ?[]const ReferenceData.WeakLinePreparedState,
    wavelength_window: ?LineListEval.StrongLineWavelengthWindow,
    start: usize,
    end: usize,
) void {
    for (start..end) |index| {
        const evaluation = if (prepared_states) |states|
            LineListEval.totalSigmaWithPreparedStrongLineStateAndWindow(
                line_list,
                wavelength_nm,
                context.spectroscopy_profile_temperatures_k[index],
                context.spectroscopy_profile_pressures_hpa[index],
                &states[index],
                if (prepared_weak_states) |weak_states| &weak_states[index] else null,
                &wavelength_window.?,
            )
        else
            LineListEval.totalSigmaAt(
                line_list,
                wavelength_nm,
                context.spectroscopy_profile_temperatures_k[index],
                context.spectroscopy_profile_pressures_hpa[index],
            );
        cache.weak_values[index] = evaluation.weak_line_sigma_cm2_per_molecule;
        cache.strong_values[index] = evaluation.strong_line_sigma_cm2_per_molecule;
        cache.line_values[index] = evaluation.line_sigma_cm2_per_molecule;
        cache.line_mixing_values[index] = evaluation.line_mixing_sigma_cm2_per_molecule;
        cache.total_values[index] = evaluation.total_sigma_cm2_per_molecule;
    }
}

fn preferredProfileCacheWorkerCount(node_count: usize) usize {
    if (node_count < min_parallel_profile_cache_node_count) return 1;
    const cpu_count = std.Thread.getCpuCount() catch 1;
    return @min(Trace.max_workers, @min(cpu_count, @max(@as(usize, 1), node_count / min_parallel_profile_cache_node_count)));
}

fn sampleCachedEndpointSecant(
    x: []const f64,
    y: []const f64,
    second: []const f64,
    target_x: f64,
    klo: usize,
    khi: usize,
) f64 {
    const h = x[khi] - x[klo];
    if (h == 0.0) return y[klo];
    const a = (x[khi] - target_x) / h;
    const b = (target_x - x[klo]) / h;
    return a * y[klo] + b * y[khi] +
        ((a * a * a - a) * second[klo] + (b * b * b - b) * second[khi]) * (h * h) / 6.0;
}

pub fn continuumCarrierDensity(
    absorbers: *Absorbers.AbsorberBuildState,
    context: *Context,
    write_index: usize,
    absorber_density_cm3: f64,
    o2_density_cm3: f64,
) f64 {
    if (absorbers.owned_cross_section_absorbers.len != 0) return 0.0;
    if (absorbers.owned_line_absorbers.len == 0) return absorber_density_cm3;

    const owner_species = absorbers.continuum_owner_species orelse return absorber_density_cm3;
    if (context.operational_o2_lut.enabled() and owner_species == .o2) return o2_density_cm3;
    for (absorbers.owned_line_absorbers) |line_absorber| {
        if (line_absorber.species != owner_species) continue;
        return line_absorber.number_densities_cm3[write_index];
    }
    return absorber_density_cm3;
}

pub fn resolveSpectroscopyEvaluation(
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
    write_index: usize,
    density: f64,
    pressure: f64,
    temperature: f64,
    oxygen_mixing_ratio: f64,
    sublayer_path_length_cm: f64,
    absorber_density_cm3: *f64,
    profile_cache: ?*const ProfileSpectroscopyCache,
) !ReferenceData.SpectroscopyEvaluation {
    if (absorbers.owned_line_absorbers.len != 0) {
        return resolvePreparedLineEvaluation(
            allocator,
            context,
            absorbers,
            write_index,
            density,
            pressure,
            temperature,
            oxygen_mixing_ratio,
            sublayer_path_length_cm,
            absorber_density_cm3,
        );
    }
    return resolveSingleLineEvaluation(
        allocator,
        context,
        absorbers,
        write_index,
        density,
        pressure,
        temperature,
        absorber_density_cm3,
        profile_cache,
    );
}

fn resolvePreparedLineEvaluation(
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
    write_index: usize,
    density: f64,
    pressure: f64,
    temperature: f64,
    oxygen_mixing_ratio: f64,
    sublayer_path_length_cm: f64,
    absorber_density_cm3: *f64,
) !ReferenceData.SpectroscopyEvaluation {
    var spectroscopy_weight: f64 = 0.0;
    var weighted: ReferenceData.SpectroscopyEvaluation = .{
        .line_sigma_cm2_per_molecule = 0.0,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = 0.0,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };

    if (context.operational_o2_lut.enabled()) {
        const o2_density_cm3 = density * oxygen_mixing_ratio;
        absorber_density_cm3.* += o2_density_cm3;
        if (o2_density_cm3 > 0.0) {
            const o2_eval = Spectroscopy.operationalO2EvaluationAtWavelength(
                context.operational_o2_lut,
                context.midpoint_nm,
                temperature,
                pressure,
            );
            spectroscopy_weight += o2_density_cm3;
            weighted.weak_line_sigma_cm2_per_molecule += o2_eval.weak_line_sigma_cm2_per_molecule * o2_density_cm3;
            weighted.strong_line_sigma_cm2_per_molecule += o2_eval.strong_line_sigma_cm2_per_molecule * o2_density_cm3;
            weighted.line_sigma_cm2_per_molecule += o2_eval.line_sigma_cm2_per_molecule * o2_density_cm3;
            weighted.line_mixing_sigma_cm2_per_molecule += o2_eval.line_mixing_sigma_cm2_per_molecule * o2_density_cm3;
            weighted.total_sigma_cm2_per_molecule += o2_eval.total_sigma_cm2_per_molecule * o2_density_cm3;
            weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
                o2_eval.d_sigma_d_temperature_cm2_per_molecule_per_k * o2_density_cm3;
        }
    }

    for (absorbers.owned_line_absorbers, absorbers.active_line_absorbers) |*line_absorber, active_absorber| {
        if (context.operational_o2_lut.enabled() and line_absorber.species == .o2) {
            line_absorber.number_densities_cm3[write_index] = 0.0;
            continue;
        }
        const absorber_mixing_ratio = Spectroscopy.speciesMixingRatioAtPressure(
            context.scene,
            line_absorber.species,
            active_absorber.volume_mixing_ratio_profile_ppmv,
            pressure,
            if (line_absorber.species == .o2) oxygen_volume_mixing_ratio else null,
        ) orelse return error.InvalidRequest;
        const density_cm3 = density * absorber_mixing_ratio;
        line_absorber.number_densities_cm3[write_index] = density_cm3;
        absorber_density_cm3.* += density_cm3;
        if (density_cm3 <= 0.0) continue;

        const evaluation = try evaluatePreparedLineAbsorber(
            allocator,
            line_absorber,
            write_index,
            context.midpoint_nm,
            temperature,
            pressure,
        );
        spectroscopy_weight += density_cm3;
        weighted.weak_line_sigma_cm2_per_molecule += evaluation.weak_line_sigma_cm2_per_molecule * density_cm3;
        weighted.strong_line_sigma_cm2_per_molecule += evaluation.strong_line_sigma_cm2_per_molecule * density_cm3;
        weighted.line_sigma_cm2_per_molecule += evaluation.line_sigma_cm2_per_molecule * density_cm3;
        weighted.line_mixing_sigma_cm2_per_molecule += evaluation.line_mixing_sigma_cm2_per_molecule * density_cm3;
        weighted.total_sigma_cm2_per_molecule += evaluation.total_sigma_cm2_per_molecule * density_cm3;
        weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
            evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * density_cm3;
        line_absorber.column_density_factor += density_cm3 * sublayer_path_length_cm;
    }

    if (spectroscopy_weight <= 0.0) {
        return .{
            .line_sigma_cm2_per_molecule = 0.0,
            .line_mixing_sigma_cm2_per_molecule = 0.0,
            .total_sigma_cm2_per_molecule = 0.0,
            .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
        };
    }

    weighted.weak_line_sigma_cm2_per_molecule /= spectroscopy_weight;
    weighted.strong_line_sigma_cm2_per_molecule /= spectroscopy_weight;
    weighted.line_sigma_cm2_per_molecule /= spectroscopy_weight;
    weighted.line_mixing_sigma_cm2_per_molecule /= spectroscopy_weight;
    weighted.total_sigma_cm2_per_molecule /= spectroscopy_weight;
    weighted.d_sigma_d_temperature_cm2_per_molecule_per_k /= spectroscopy_weight;
    return weighted;
}

fn evaluatePreparedLineAbsorber(
    allocator: Allocator,
    line_absorber: *State.PreparedLineAbsorber,
    write_index: usize,
    midpoint_nm: f64,
    temperature: f64,
    pressure: f64,
) !ReferenceData.SpectroscopyEvaluation {
    var evaluation = if (line_absorber.strong_line_states) |states| blk: {
        states[write_index] = (try line_absorber.line_list.prepareStrongLineState(
            allocator,
            temperature,
            pressure,
        )).?;
        line_absorber.strong_line_state_initialized.?[write_index] = true;
        line_absorber.strong_line_state_count += 1;
        break :blk line_absorber.line_list.evaluateAtPrepared(
            midpoint_nm,
            temperature,
            pressure,
            &states[write_index],
        );
    } else line_absorber.line_list.evaluateAt(midpoint_nm, temperature, pressure);

    const upper = line_absorber.line_list.evaluateAt(midpoint_nm, temperature + 0.5, pressure);
    const lower = line_absorber.line_list.evaluateAt(midpoint_nm, @max(temperature - 0.5, 150.0), pressure);
    evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k =
        (upper.total_sigma_cm2_per_molecule - lower.total_sigma_cm2_per_molecule) / 1.0;
    return evaluation;
}

fn resolveSingleLineEvaluation(
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
    write_index: usize,
    density: f64,
    pressure: f64,
    temperature: f64,
    absorber_density_cm3: *f64,
    profile_cache: ?*const ProfileSpectroscopyCache,
) !ReferenceData.SpectroscopyEvaluation {
    const species = absorbers.active_line_species;
    const absorber_mixing_ratio = if (species) |active_species|
        Spectroscopy.speciesMixingRatioAtPressure(
            context.scene,
            active_species,
            if (absorbers.single_active_line_absorber) |line_absorber|
                line_absorber.volume_mixing_ratio_profile_ppmv
            else
                &.{},
            pressure,
            if (active_species == .o2) oxygen_volume_mixing_ratio else null,
        ) orelse oxygen_volume_mixing_ratio
    else
        oxygen_volume_mixing_ratio;
    absorber_density_cm3.* = density * absorber_mixing_ratio;

    if (context.operational_o2_lut.enabled()) {
        const sigma = context.operational_o2_lut.sigmaAt(context.midpoint_nm, temperature, pressure);
        return .{
            .weak_line_sigma_cm2_per_molecule = sigma,
            .strong_line_sigma_cm2_per_molecule = 0.0,
            .line_sigma_cm2_per_molecule = sigma,
            .line_mixing_sigma_cm2_per_molecule = 0.0,
            .total_sigma_cm2_per_molecule = sigma,
            .d_sigma_d_temperature_cm2_per_molecule_per_k = context.operational_o2_lut.dSigmaDTemperatureAt(
                context.midpoint_nm,
                temperature,
                pressure,
            ),
        };
    }
    if (absorbers.owned_lines) |*line_list| {
        if (profile_cache) |cache| if (cache.evaluationAtAltitude(context.vertical_grid.sublayer_mid_altitudes_km[write_index])) |evaluation| {
            return evaluation;
        };
        if (absorbers.strong_line_states) |states| {
            states[write_index] = (try line_list.prepareStrongLineState(allocator, temperature, pressure)).?;
            absorbers.strong_line_state_count += 1;
            var evaluation = line_list.evaluateAtPrepared(
                context.midpoint_nm,
                temperature,
                pressure,
                &states[write_index],
            );
            const upper = line_list.evaluateAt(context.midpoint_nm, temperature + 0.5, pressure);
            const lower = line_list.evaluateAt(context.midpoint_nm, @max(temperature - 0.5, 150.0), pressure);
            evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k =
                (upper.total_sigma_cm2_per_molecule - lower.total_sigma_cm2_per_molecule) / 1.0;
            return evaluation;
        }
        return line_list.evaluateAt(context.midpoint_nm, temperature, pressure);
    }
    return .{
        .weak_line_sigma_cm2_per_molecule = 0.0,
        .strong_line_sigma_cm2_per_molecule = 0.0,
        .line_sigma_cm2_per_molecule = 0.0,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = 0.0,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}
