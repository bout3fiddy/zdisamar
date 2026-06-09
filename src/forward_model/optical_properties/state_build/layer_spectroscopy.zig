const ReferenceData = @import("../../../input/ReferenceData.zig");
const LineListEval = @import("../../../input/reference/spectroscopy/line_list.zig");
const Context = @import("context.zig").PreparationContext;
const Absorbers = @import("absorbers.zig");
const Spectroscopy = @import("spectroscopy.zig");
const State = @import("state.zig");
const Trace = @import("../../instrumentation/trace.zig");
const work_partition = @import("../../work_partition.zig");
const spline = @import("../../../common/math/interpolation/spline.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const oxygen_volume_mixing_ratio = Spectroscopy.default_o2_volume_mixing_ratio;
const max_spectroscopy_profile_nodes: usize = 64;
const min_parallel_profile_cache_node_count: usize = 8;
const profile_cache_node_chunk_size: usize = 2;
const StrongLineAnchorBuffer = [ReferenceData.max_strong_line_sidecars]ReferenceData.StrongLineAnchorIndex;

// layer_spectroscopy.zig -------------------------------------------------------------------------------------|
// Builds layer-preparation spectroscopy values from line lists, operational O2 LUTs, and profile caches.      |
//                                                                                                             |
// called by                                                                                                   |
//   layer_accumulation while filling prepared layer and sublayer rows.                                        |
//                                                                                                             |
// main paths                                                                                                  |
//   profile cache  : evaluate spectroscopy at profile nodes and spline it over altitude.                      |
//   prepared lines : evaluate active line absorbers and density-weight their sigma values.                    |
//   single line    : use one line list, operational O2, or zero spectroscopy when no line data is active.     |
//                                                                                                             |
// hot path                                                                                                    |
//   Runs during optical-state preparation. The cache path is parallelized for larger profile grids so each    |
//   worker fills a chunk of profile-node spectroscopy values before spline setup.                             |
// ------------------------------------------------------------------------------------------------------------|

// ProfileCacheValueRequest -----------------------------------------------------------------------------------|
// Borrowed inputs shared by profile-spectroscopy cache fill workers.                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 264 B (0.258 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..207] line_list            : SpectroscopyLineList                                                      |
// [208..223] prepared_states      : ?[]const StrongLinePreparedState                                          |
// [224..239] prepared_weak_states : ?[]const WeakLinePreparedState                                            |
// [240..247] context              : *const PreparationContext                                                 |
// [248..255] wavelength_nm        : f64                                                                       |
// [256..263] wavelength_window    : ?*const StrongLineWavelengthWindow                                        |
//                                                                                                             |
// out-of-line                                                                                                 |
//   context, prepared state rows, and wavelength-window storage are borrowed from the cache init call.        |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 5 cache lines at 64 B per line                                                                  |
// footprint: per cache fill = 264 B plus borrowed context/profile storage                                     |
const ProfileCacheValueRequest = struct {
    line_list: ReferenceData.SpectroscopyLineList,
    context: *const Context,
    wavelength_nm: f64,
    prepared_states: ?[]const ReferenceData.StrongLinePreparedState,
    prepared_weak_states: ?[]const ReferenceData.WeakLinePreparedState,
    wavelength_window: ?*const LineListEval.StrongLineWavelengthWindow,
};
// ------------------------------------------------------------------------------------------------------------|

// ProfileCacheValueWorker ------------------------------------------------------------------------------------|
// Work item passed to each profile-spectroscopy cache initialization worker.                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] cache        : *ProfileSpectroscopyCache                                                           |
// [ 8..15] request      : *const ProfileCacheValueRequest                                                     |
// [16..23] queue        : *ChunkQueue                                                                         |
// [24..31] worker_index : usize                                                                               |
//                                                                                                             |
// out-of-line                                                                                                 |
//   cache, request, and queue storage are borrowed. Each worker writes only the chunks it claims from queue.  |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 1 cache line at 64 B per line                                                                   |
// footprint: per worker = 32 B plus borrowed request/cache/queue storage                                      |
const ProfileCacheValueWorker = struct {
    cache: *ProfileSpectroscopyCache,
    request: *const ProfileCacheValueRequest,
    queue: *work_partition.ChunkQueue,
    worker_index: usize,
};

// ProfileSpectroscopyCache -----------------------------------------------------------------------------------|
// Spline-ready spectroscopy values for one wavelength on the spectroscopy profile grid.                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 3096 B (3.023 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// node_count: usize                                                                                           |
// altitudes_km: []const f64                                                                                   |
// line, line-mixing, total values and second-derivative arrays: 6 x [64]f64 = 3072 B                          |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 49 cache lines at 64 B per line                                                                 |
// footprint: per instance = 3096 B; altitude storage is borrowed                                              |
// capacity: enabled profile-spectroscopy requests with more than 64 profile nodes are rejected                |
//                                                                                                             |
// hot path                                                                                                    |
//   cache stores sigma_line(z), sigma_mixing(z), sigma_total(z), and endpoint-secant spline second            |
//   derivatives for altitude interpolation during support-row evaluation.                                     |
pub const ProfileSpectroscopyCache = struct {
    node_count: usize = 0,
    altitudes_km: []const f64 = &.{},
    line_values: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,
    line_mixing_values: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,
    total_values: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,
    line_second: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,
    line_mixing_second: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,
    total_second: [max_spectroscopy_profile_nodes]f64 = [_]f64{0.0} ** max_spectroscopy_profile_nodes,

    pub fn init(
        context: *const Context,
        absorbers: *const Absorbers.AbsorberBuildState,
        wavelength_nm: f64,
    ) !ProfileSpectroscopyCache {
        // ProfileSpectroscopyCache.init --------------------------------------------------------------------- |
        // Build profile-node spectroscopy values and spline second derivatives for one wavelength.            |
        //                                                                                                     |
        // hot path                                                                                            |
        // called once per high-resolution forward miss when profile spectroscopy is active.                   |
        //                                                                                                     |
        // route                                                                                               |
        // skip cache when active line absorbers or operational O2 already own the spectroscopy route.         |
        // --------------------------------------------------------------------------------------------------- |

        const line_list = absorbers.owned_lines orelse return .{};
        if (absorbers.owned_line_absorbers.len != 0 or context.operational_o2_lut.enabled()) return .{};
        const node_count = context.spectroscopy_profile_altitudes_km.len;
        if (node_count > max_spectroscopy_profile_nodes) return error.InvalidRequest;
        if (node_count < 3) return .{};
        if (context.spectroscopy_profile_pressures_hpa.len != node_count or
            context.spectroscopy_profile_temperatures_k.len != node_count) return .{};

        const prepared_states = choose_prepared_states: {
            if (absorbers.profile_strong_line_states) |states| {
                if (states.len == node_count) break :choose_prepared_states states;
            }
            break :choose_prepared_states null;
        };

        const prepared_weak_states = choose_prepared_weak_states: {
            if (absorbers.profile_weak_line_states) |states| {
                if (states.len == node_count) break :choose_prepared_weak_states states;
            }
            break :choose_prepared_weak_states null;
        };

        var cache = ProfileSpectroscopyCache{
            .node_count = node_count,
            .altitudes_km = context.spectroscopy_profile_altitudes_km[0..node_count],
            .line_values = undefined,
            .line_mixing_values = undefined,
            .total_values = undefined,
            .line_second = undefined,
            .line_mixing_second = undefined,
            .total_second = undefined,
        };

        var wavelength_window_storage: LineListEval.StrongLineWavelengthWindow = undefined;
        var wavelength_anchor_storage: StrongLineAnchorBuffer = undefined;
        const wavelength_window: ?*const LineListEval.StrongLineWavelengthWindow = choose_window: {
            if (prepared_states == null) break :choose_window null;
            wavelength_window_storage = LineListEval.prepareStrongLineWavelengthWindow(
                line_list,
                wavelength_nm,
                &wavelength_anchor_storage,
            );
            break :choose_window &wavelength_window_storage;
        };

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
        spline.endpointSecantSecondDerivatives3(
            altitudes,
            cache.line_values[0..node_count],
            cache.line_mixing_values[0..node_count],
            cache.total_values[0..node_count],
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
        // ProfileSpectroscopyCache.evaluationAtAltitude ----------------------------------------------------- |
        // Sample cached line, line-mixing, and total spectroscopy at altitude.                                |
        //                                                                                                     |
        // hot path                                                                                            |
        // used by support-row evaluation after the cache has spline-ready profile values.                     |
        //                                                                                                     |
        // math                                                                                                |
        // sigma(z) = cubic endpoint-secant spline over cached profile-node values.                            |
        // --------------------------------------------------------------------------------------------------- |

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
    wavelength_window: ?*const LineListEval.StrongLineWavelengthWindow,
) void {
    // fillProfileSpectroscopyCacheValues -------------------------------------------------------------------- |
    // Fill all profile-node spectroscopy values, using worker chunks when the profile is large enough.        |
    //                                                                                                         |
    // hot path                                                                                                |
    // preparation calls this once per cache miss; workers write disjoint node ranges into inline arrays.      |
    //                                                                                                         |
    // instrumentation                                                                                         |
    // worker and chunk zones expose parallel cache-fill cost in timeline traces.                              |
    // ------------------------------------------------------------------------------------------------------- |

    const request = ProfileCacheValueRequest{
        .line_list = line_list,
        .context = context,
        .wavelength_nm = wavelength_nm,
        .prepared_states = prepared_states,
        .prepared_weak_states = prepared_weak_states,
        .wavelength_window = wavelength_window,
    };
    const worker_count = preferredProfileCacheWorkerCount(cache.node_count);
    if (worker_count == 1) {
        fillProfileSpectroscopyCacheValueRange(
            cache,
            &request,
            0,
            cache.node_count,
        );
        return;
    }

    var queue = work_partition.ChunkQueue.init(cache.node_count, profile_cache_node_chunk_size);
    var worker_buffer: [work_partition.max_workers]ProfileCacheValueWorker = undefined;
    var thread_buffer: [work_partition.max_workers - 1]std.Thread = undefined;
    const workers = worker_buffer[0..worker_count];
    const threads = thread_buffer[0 .. worker_count - 1];
    var started_thread_count: usize = 0;

    for (0..worker_count) |worker_index| {
        workers[worker_index] = .{
            .cache = cache,
            .request = &request,
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

    // instrumentation: trace thread label
    // captures: profile spectroscopy cache worker identity
    // why: make parallel cache-initialization lanes separable in timeline traces.
    Trace.setThreadName(thread_name);

    // instrumentation: trace zone
    // captures: profile spectroscopy cache worker wall time
    // why: expose per-worker cost of filling spline-ready spectroscopy values.
    const worker_zone = Trace.staticZone(@src(), "optical_prepare.profile_cache_init_worker");
    worker_zone.value(@intCast(worker.worker_index));
    defer worker_zone.end();

    while (worker.queue.next()) |chunk| {
        {

            // instrumentation: trace zone
            // captures: profile spectroscopy cache chunk wall time and node count
            // why: reveal chunk imbalance while building per-altitude spectroscopy values.
            const chunk_zone = Trace.deepStaticZone(@src(), "optical_prepare.profile_cache_init_chunk");
            chunk_zone.value(@intCast(chunk.end - chunk.start));
            defer chunk_zone.end();

            fillProfileSpectroscopyCacheValueRange(
                worker.cache,
                worker.request,
                chunk.start,
                chunk.end,
            );
        }
    }
}

fn fillProfileSpectroscopyCacheValueRange(
    cache: *ProfileSpectroscopyCache,
    request: *const ProfileCacheValueRequest,
    start: usize,
    end: usize,
) void {
    // fillProfileSpectroscopyCacheValueRange ---------------------------------------------------------------- |
    // Fill one contiguous range of cached profile-node spectroscopy values.                                   |
    //                                                                                                         |
    // hot path                                                                                                |
    // each worker repeatedly calls this on queue chunks until the profile cache is complete.                  |
    // ------------------------------------------------------------------------------------------------------- |

    for (start..end) |index| {
        const evaluation = evaluate_profile_node: {
            if (request.prepared_states) |states| {
                break :evaluate_profile_node LineListEval.totalSigmaWithPreparedStrongLineStateAndWindow(
                    request.line_list,
                    request.wavelength_nm,
                    request.context.spectroscopy_profile_temperatures_k[index],
                    request.context.spectroscopy_profile_pressures_hpa[index],
                    &states[index],
                    if (request.prepared_weak_states) |weak_states| &weak_states[index] else null,
                    request.wavelength_window.?,
                );
            }

            break :evaluate_profile_node LineListEval.totalSigmaAt(
                request.line_list,
                request.wavelength_nm,
                request.context.spectroscopy_profile_temperatures_k[index],
                request.context.spectroscopy_profile_pressures_hpa[index],
            );
        };
        cache.line_values[index] = evaluation.line_sigma_cm2_per_molecule;
        cache.line_mixing_values[index] = evaluation.line_mixing_sigma_cm2_per_molecule;
        cache.total_values[index] = evaluation.total_sigma_cm2_per_molecule;
    }
}

fn preferredProfileCacheWorkerCount(node_count: usize) usize {
    return work_partition.preferredWorkerCount(node_count, min_parallel_profile_cache_node_count);
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

    // math: cubic spline segment with endpoint-secant second derivatives.
    return a * y[klo] + b * y[khi] +
        ((a * a * a - a) * second[klo] + (b * b * b - b) * second[khi]) * (h * h) / 6.0;
}

pub fn continuumCarrierDensity(
    absorbers: *const Absorbers.AbsorberBuildState,
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

pub fn resolveCachedSingleLineEvaluation(
    context: *const Context,
    absorbers: *const Absorbers.AbsorberBuildState,
    write_index: usize,
    density: f64,
    pressure: f64,
    temperature: f64,
    absorber_density_cm3: *f64,
    profile_cache: *const ProfileSpectroscopyCache,
) ReferenceData.SpectroscopyEvaluation {
    // resolveCachedSingleLineEvaluation --------------------------------------------------------------------- |
    // Resolve single-line spectroscopy while layer preparation already owns a profile spectroscopy cache.     |
    //                                                                                                         |
    // hot path                                                                                                |
    // support-row preparation calls this when one retained line list is active.                               |
    // ------------------------------------------------------------------------------------------------------- |

    const absorber_mixing_ratio = activeLineMixingRatio(context, absorbers, pressure);
    absorber_density_cm3.* = density * absorber_mixing_ratio;

    if (context.operational_o2_lut.enabled()) {
        return operationalO2EvaluationAtContext(context, temperature, pressure);
    }

    if (absorbers.owned_lines) |line_list| {
        const altitude_km = context.vertical_grid.sublayer_mid_altitudes_km[write_index];
        if (profile_cache.evaluationAtAltitude(altitude_km)) |evaluation| {
            return evaluation;
        }
        return line_list.evaluateAt(context.midpoint_nm, temperature, pressure);
    }

    return zeroSpectroscopyEvaluation();
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
    // resolveSpectroscopyEvaluation ------------------------------------------------------------------------- |
    // Resolve spectroscopy for one support row through prepared active absorbers or the single-line route.    |
    //                                                                                                         |
    // hot path                                                                                                |
    // called inside support-row carrier evaluation for active line absorbers.                                 |
    //                                                                                                         |
    // math                                                                                                    |
    // active line absorbers are density-weighted: sigma_bar = sum(sigma_species * n_species) / sum(n).        |
    // ------------------------------------------------------------------------------------------------------- |

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
            weighted.weak_line_sigma_cm2_per_molecule +=
                o2_eval.weak_line_sigma_cm2_per_molecule * o2_density_cm3;
            weighted.strong_line_sigma_cm2_per_molecule +=
                o2_eval.strong_line_sigma_cm2_per_molecule * o2_density_cm3;
            weighted.line_sigma_cm2_per_molecule +=
                o2_eval.line_sigma_cm2_per_molecule * o2_density_cm3;
            weighted.line_mixing_sigma_cm2_per_molecule +=
                o2_eval.line_mixing_sigma_cm2_per_molecule * o2_density_cm3;
            weighted.total_sigma_cm2_per_molecule +=
                o2_eval.total_sigma_cm2_per_molecule * o2_density_cm3;
            weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
                o2_eval.d_sigma_d_temperature_cm2_per_molecule_per_k * o2_density_cm3;
        }
    }

    for (absorbers.owned_line_absorbers, absorbers.active_line_absorbers) |*line_absorber, active_absorber| {
        const operational_o2_owns_species = context.operational_o2_lut.enabled() and line_absorber.species == .o2;
        if (operational_o2_owns_species) {
            line_absorber.number_densities_cm3[write_index] = 0.0;
            continue;
        }

        // route: use the active absorber's VMR profile for this pressure level.
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
    // evaluatePreparedLineAbsorber -------------------------------------------------------------------------- |
    // Evaluate one prepared line absorber and attach a finite-difference temperature derivative.              |
    //                                                                                                         |
    // hot path                                                                                                |
    // direct prepared-line route for an active absorber/support row.                                          |
    //                                                                                                         |
    // math                                                                                                    |
    // d_sigma/dT = (sigma(T + 0.5 K) - sigma(max(T - 0.5 K, 150 K))) / 1 K.                                   |
    // ------------------------------------------------------------------------------------------------------- |

    var evaluation = evaluate_line: {
        if (line_absorber.strong_line_states) |states| {
            states[write_index] = (try line_absorber.line_list.prepareStrongLineState(
                allocator,
                temperature,
                pressure,
            )).?;
            line_absorber.strong_line_state_initialized.?[write_index] = true;
            line_absorber.strong_line_state_count += 1;
            break :evaluate_line line_absorber.line_list.evaluateAtPrepared(
                midpoint_nm,
                temperature,
                pressure,
                &states[write_index],
            );
        }

        break :evaluate_line line_absorber.line_list.evaluateAt(
            midpoint_nm,
            temperature,
            pressure,
        );
    };

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
    // resolveSingleLineEvaluation --------------------------------------------------------------------------- |
    // Resolve one retained line-list route for layer preparation.                                             |
    //                                                                                                         |
    // hot path                                                                                                |
    // used when no prepared active-line absorber array is present.                                            |
    // ------------------------------------------------------------------------------------------------------- |

    const absorber_mixing_ratio = activeLineMixingRatio(context, absorbers, pressure);
    absorber_density_cm3.* = density * absorber_mixing_ratio;

    if (context.operational_o2_lut.enabled()) {
        return operationalO2EvaluationAtContext(context, temperature, pressure);
    }

    if (absorbers.owned_lines) |*line_list| {
        if (profile_cache) |cache| {
            const altitude_km = context.vertical_grid.sublayer_mid_altitudes_km[write_index];
            if (cache.evaluationAtAltitude(altitude_km)) |evaluation| return evaluation;
        }

        if (absorbers.strong_line_states) |states| {
            states[write_index] = (try line_list.prepareStrongLineState(
                allocator,
                temperature,
                pressure,
            )).?;
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

    return zeroSpectroscopyEvaluation();
}

fn activeLineMixingRatio(
    context: *const Context,
    absorbers: *const Absorbers.AbsorberBuildState,
    pressure: f64,
) f64 {
    // activeLineMixingRatio --------------------------------------------------------------------------------- |
    // Resolve the active single-line species mixing ratio at pressure, falling back to O2.                    |
    // ------------------------------------------------------------------------------------------------------- |

    const active_species = absorbers.active_line_species orelse return oxygen_volume_mixing_ratio;
    const volume_mixing_ratio_profile = if (absorbers.single_active_line_absorber) |line_absorber|
        line_absorber.volume_mixing_ratio_profile_ppmv
    else
        &.{};

    return Spectroscopy.speciesMixingRatioAtPressure(
        context.scene,
        active_species,
        volume_mixing_ratio_profile,
        pressure,
        if (active_species == .o2) oxygen_volume_mixing_ratio else null,
    ) orelse oxygen_volume_mixing_ratio;
}

fn operationalO2EvaluationAtContext(
    context: *const Context,
    temperature: f64,
    pressure: f64,
) ReferenceData.SpectroscopyEvaluation {
    // operationalO2EvaluationAtContext ---------------------------------------------------------------------- |
    // Build the standard operational O2 evaluation at the preparation midpoint wavelength.                    |
    // ------------------------------------------------------------------------------------------------------- |

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

fn zeroSpectroscopyEvaluation() ReferenceData.SpectroscopyEvaluation {
    return .{
        .weak_line_sigma_cm2_per_molecule = 0.0,
        .strong_line_sigma_cm2_per_molecule = 0.0,
        .line_sigma_cm2_per_molecule = 0.0,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = 0.0,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}
