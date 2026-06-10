const std = @import("std");
const AbsorberModel = @import("../../../input/Absorber.zig");
const OperationalCrossSectionLut = @import("../../../input/Instrument.zig").OperationalCrossSectionLut;
const ReferenceData = @import("../../../input/ReferenceData.zig");
const Scene = @import("../../../input/Scene.zig").Scene;
const Context = @import("context.zig").PreparationContext;
const ProfileStateCache = @import("profile_state_cache.zig");
const Spectroscopy = @import("spectroscopy.zig");
const State = @import("state.zig");
const Trace = @import("../../instrumentation/trace.zig");
const work_partition = @import("../../work_partition.zig");

const Allocator = std.mem.Allocator;
const min_parallel_profile_line_state_count: usize = 4;
const profile_line_state_chunk_size: usize = 2;
const max_profile_spectroscopy_cache_nodes: usize = 64;

// absorbers.zig ---------------------------------------------------------------------------------------------    |
// Absorber preparation stage for optical-property state construction.                                            |
//                                                                                                                |
// called by                                                                                                      |
//   root.prepare after Context.init and before layer_accumulation.populate.                                      |
//                                                                                                                |
// main path                                                                                                      |
//   Scene absorber controls -> active line/cross-section descriptors                                             |
//   reference line list -> runtime filtering, strong-line match index, and optional per-species line lists       |
//   cross-section table/LUT sources -> cloned prepared absorber rows                                             |
//   profile T/P nodes -> weak/strong prepared line states, loaded from ProfileStateCache when available          |
//   resolved species/continuum metadata -> scalar fields consumed by layer_spectroscopy.zig                      |
//                                                                                                                |
// hot path                                                                                                       |
//   This stage runs once per prepared scene so wavelength-time carrier evaluation does not repeat absorber       |
//   selection, line-list filtering, strong-line partitioning, or profile-node state setup. Profile line-state    |
//   preparation can split profile nodes across workers; worker rows borrow profile arrays and write into         |
//   caller-owned prepared-state slices.                                                                          |
//                                                                                                                |
// limits                                                                                                         |
//   Single-list profile spectroscopy without an operational O2 LUT accepts at most                               |
//   max_profile_spectroscopy_cache_nodes profile nodes so the downstream profile cache stays bounded.            |
//                                                                                                                |
// memory                                                                                                         |
//   AbsorberBuildState owns the active descriptor slices, cloned prepared absorber rows, density columns,        |
//   optional line-state arrays, and any line-list storage moved out of Context. Deinit releases only initialized |
//   prefixes tracked by the count fields; Finalize.assemble later transfers surviving ownership into             |
//   PreparedOpticalState.                                                                                        |
// ------------------------------------------------------------------------------------------------------------   |

// ProfileLineStateWorker ------------------------------------------------------------------------------------    |
// Per-thread descriptor for profile line-state preparation.                                                      |
//                                                                                                                |
// layout(64-bit)                                                                                                 |
// size: 304 B (0.297 KiB), align: 8 B                                                                            |
//                                                                                                                |
// memory                                                                                                         |
// [  0..207] line_list                 : SpectroscopyLineList                                                    |
// [208..223] temperatures_k            : []const f64                                                             |
// [224..239] pressures_hpa             : []const f64                                                             |
// [240..255] weak_states               : ?[]WeakLinePreparedState                                                |
// [256..271] strong_states             : ?[]StrongLinePreparedState                                              |
// [272..287] strong_relaxation_weights : []f64                                                                   |
// [288..295] queue                     : *ChunkQueue                                                             |
// [296..303] worker_index              : usize                                                                   |
//                                                                                                                |
// out-of-line                                                                                                    |
//   profile arrays, state arrays, relaxation weights, and queue storage are borrowed by the worker.              |
//   line_list carries descriptors for spectroscopy line storage; ownership stays outside this worker row.        |
//                                                                                                                |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                         |
// cache span: 5 cache lines at 64 B per line                                                                     |
// footprint: per instance = 304 B plus borrowed storage                                                          |
const ProfileLineStateWorker = struct {
    line_list: ReferenceData.SpectroscopyLineList,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    weak_states: ?[]ReferenceData.WeakLinePreparedState,
    strong_states: ?[]ReferenceData.StrongLinePreparedState,
    strong_relaxation_weights: []f64,
    queue: *work_partition.ChunkQueue,
    worker_index: usize,
};
// ------------------------------------------------------------------------------------------------------------   |

// AbsorberBuildState ----------------------------------------------------------------------------------------    |
// Owns the prepared absorber arrays built from one scene and reference-data context.                             |
//                                                                                                                |
// layout(64-bit)                                                                                                 |
// size: 568 B (0.555 KiB), align: 8 B                                                                            |
//                                                                                                                |
// memory                                                                                                         |
// [  0.. 15] active_line_absorbers              : []ActiveLineAbsorber                                           |
// [ 16.. 31] active_cross_section_absorbers     : []ActiveCrossSectionAbsorber                                   |
// [ 32..199] single_active_line_absorber        : ?ActiveLineAbsorber                                            |
// [200..215] owned_cross_section_absorbers      : []PreparedCrossSectionAbsorber                                 |
// [216..223] owned_cross_section_absorber_count : usize                                                          |
// [224..239] owned_line_absorbers               : []PreparedLineAbsorber                                         |
// [240..247] owned_line_absorber_count          : usize                                                          |
// [248..263] strong_line_states                 : ?[]StrongLinePreparedState                                     |
// [264..271] strong_line_state_count            : usize                                                          |
// [272..287] profile_strong_line_states         : ?[]StrongLinePreparedState                                     |
// [288..295] profile_strong_line_state_count    : usize                                                          |
// [296..311] profile_weak_line_states           : ?[]WeakLinePreparedState                                       |
// [312..319] profile_weak_line_state_count      : usize                                                          |
// [320..535] owned_lines                        : ?SpectroscopyLineList                                          |
// [536..543] mean_sigma                         : f64                                                            |
// [544..551] midpoint_continuum_sigma           : f64                                                            |
// [552..559] air_mass_factor                    : f64                                                            |
// [560..560] owns_profile_strong_line_states    : bool                                                           |
// [561..561] owns_profile_weak_line_states      : bool                                                           |
// [562..563] active_line_species                : ?AbsorberSpecies                                               |
// [564..565] continuum_owner_species            : ?AbsorberSpecies                                               |
// [566..566] has_line_absorbers                 : bool                                                           |
// [567..567] padding                            : 1 B                                                            |
//                                                                                                                |
// out-of-line                                                                                                    |
//   active_line_absorbers, active_cross_section_absorbers, owned_cross_section_absorbers,                        |
//   owned_line_absorbers, strong/profile state slices, and owned_lines may own referenced storage.               |
//                                                                                                                |
// unused bits: 8 padding + 21 bool-storage slack = 29 bits                                                       |
// cache span: 9 cache lines at 64 B per line                                                                     |
// footprint: per instance = 568 B plus owned absorber and spectroscopy storage                                   |
pub const AbsorberBuildState = struct {
    active_line_absorbers: []State.ActiveLineAbsorber = &.{},
    active_cross_section_absorbers: []State.ActiveCrossSectionAbsorber = &.{},
    single_active_line_absorber: ?State.ActiveLineAbsorber = null,
    owned_cross_section_absorbers: []State.PreparedCrossSectionAbsorber = &.{},
    owned_cross_section_absorber_count: usize = 0,
    owned_line_absorbers: []State.PreparedLineAbsorber = &.{},
    owned_line_absorber_count: usize = 0,
    strong_line_states: ?[]ReferenceData.StrongLinePreparedState = null,
    strong_line_state_count: usize = 0,
    profile_strong_line_states: ?[]ReferenceData.StrongLinePreparedState = null,
    profile_strong_line_state_count: usize = 0,
    profile_weak_line_states: ?[]ReferenceData.WeakLinePreparedState = null,
    profile_weak_line_state_count: usize = 0,
    owns_profile_strong_line_states: bool = true,
    owns_profile_weak_line_states: bool = true,
    owned_lines: ?ReferenceData.SpectroscopyLineList = null,
    active_line_species: ?AbsorberModel.AbsorberSpecies = null,
    continuum_owner_species: ?AbsorberModel.AbsorberSpecies = null,
    mean_sigma: f64 = 0.0,
    midpoint_continuum_sigma: f64 = 0.0,
    air_mass_factor: f64 = 0.0,
    has_line_absorbers: bool = false,

    pub fn deinit(self: *AbsorberBuildState, allocator: Allocator) void {
        if (self.strong_line_states) |states| {
            for (states[0..self.strong_line_state_count]) |*state| state.deinit(allocator);
            if (states.len != 0) allocator.free(states);
        }
        if (self.profile_strong_line_states) |states| {
            if (self.owns_profile_strong_line_states) {
                for (states[0..self.profile_strong_line_state_count]) |*state| state.deinit(allocator);

                if (states.len != 0) allocator.free(states);
            }
        }
        if (self.profile_weak_line_states) |states| {
            if (self.owns_profile_weak_line_states) {
                for (states[0..self.profile_weak_line_state_count]) |*state| state.deinit(allocator);

                if (states.len != 0) allocator.free(states);
            }
        }
        if (self.owned_line_absorbers.len != 0) {
            for (self.owned_line_absorbers[0..self.owned_line_absorber_count]) |*line_absorber| {
                line_absorber.deinit(allocator);
            }
            allocator.free(self.owned_line_absorbers);
        }
        if (self.owned_cross_section_absorbers.len != 0) {
            for (
                self.owned_cross_section_absorbers[0..self.owned_cross_section_absorber_count],
            ) |*cross_section_absorber| {
                cross_section_absorber.deinit(allocator);
            }
            allocator.free(self.owned_cross_section_absorbers);
        }

        if (self.owned_lines) |line_list| {
            var owned = line_list;
            owned.deinit(allocator);
        }

        if (self.active_line_absorbers.len != 0) allocator.free(self.active_line_absorbers);
        if (self.active_cross_section_absorbers.len != 0) allocator.free(self.active_cross_section_absorbers);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------   |

pub fn build(
    allocator: Allocator,
    context: *Context,
) !AbsorberBuildState {
    // build ---------------------------------------------------------------------------------------------------  |
    // Builds active cross-section and line absorbers for repeated wavelength evaluation.                         |
    //                                                                                                            |
    // hot path                                                                                                   |
    //   Runs once per optical-state preparation and moves absorber selection, line partitioning, and profile     |
    //   line-state setup out of wavelength-time evaluation.                                                      |
    //                                                                                                            |
    // calls                                                                                                      |
    //   buildCrossSectionAbsorbers                                                                               |
    //   buildLineAbsorbers                                                                                       |
    //   prepareProfileLineStates                                                                                 |
    // ---------------------------------------------------------------------------------------------------------  |

    const scene = context.scene;
    const operational_band_support = scene.observation_model.primaryOperationalBandSupport();
    const operational_o2_lut = operational_band_support.o2_operational_lut;

    const active_line_absorbers = try collectActiveLineAbsorbers(allocator, scene);
    const active_cross_section_absorbers = try collectActiveCrossSectionAbsorbers(
        allocator,
        scene,
        context.cross_sections,
    );
    const single_active_line_absorber = if (active_line_absorbers.len == 1)
        active_line_absorbers[0]
    else
        null;

    var owned_lines = context.spectroscopy_lines;
    context.spectroscopy_lines = null;
    errdefer if (owned_lines) |line_list| {
        var owned = line_list;
        owned.deinit(allocator);
    };

    var state: AbsorberBuildState = .{
        .active_line_absorbers = active_line_absorbers,
        .active_cross_section_absorbers = active_cross_section_absorbers,
        .single_active_line_absorber = single_active_line_absorber,
    };
    errdefer state.deinit(allocator);

    try buildCrossSectionAbsorbers(allocator, context, &state);
    try buildLineAbsorbers(allocator, context, &state, &owned_lines, operational_o2_lut);
    if (state.owned_line_absorbers.len == 0 and
        state.owned_lines != null and
        !operational_o2_lut.enabled() and
        context.spectroscopy_profile_altitudes_km.len > max_profile_spectroscopy_cache_nodes)
    {
        return error.InvalidRequest;
    }

    const can_prepare_single_line_profile =
        state.owned_line_absorbers.len == 0 and !operational_o2_lut.enabled();
    if (can_prepare_single_line_profile) {
        if (state.owned_lines) |line_list| {
            if (line_list.hasStrongLineSidecars() and context.spectroscopy_profile_temperatures_k.len == 0) {
                state.strong_line_states = try allocator.alloc(
                    ReferenceData.StrongLinePreparedState,
                    context.vertical_grid.sublayer_mid_altitudes_km.len,
                );
            }
        }
    }

    const should_prepare_profile_line_states = state.owned_line_absorbers.len == 0 and
        state.owned_lines != null and
        !operational_o2_lut.enabled() and
        state.owned_lines.?.hasStrongLineSidecars() and
        context.spectroscopy_profile_temperatures_k.len != 0;
    var loaded_profile_states = false;

    if (should_prepare_profile_line_states) {
        if (context.borrowed_profile_strong_line_states) |strong_states| {
            const weak_states = context.borrowed_profile_weak_line_states orelse return error.InvalidRequest;
            if (strong_states.len != context.spectroscopy_profile_temperatures_k.len or
                weak_states.len != context.spectroscopy_profile_temperatures_k.len)
            {
                return error.InvalidRequest;
            }
            state.profile_strong_line_states = strong_states;
            state.profile_weak_line_states = weak_states;
            state.profile_strong_line_state_count = strong_states.len;
            state.profile_weak_line_state_count = weak_states.len;
            state.owns_profile_strong_line_states = false;

            state.owns_profile_weak_line_states = false;
            loaded_profile_states = true;
        } else {
            if (context.borrowed_profile_weak_line_states != null) return error.InvalidRequest;
            state.profile_strong_line_states = try allocator.alloc(
                ReferenceData.StrongLinePreparedState,
                context.spectroscopy_profile_temperatures_k.len,
            );

            state.profile_weak_line_states = try allocator.alloc(
                ReferenceData.WeakLinePreparedState,
                context.spectroscopy_profile_temperatures_k.len,
            );
        }
    }
    if (!loaded_profile_states) {
        if (state.profile_weak_line_states) |weak_states| {
            if (state.profile_strong_line_states) |strong_states| {
                const line_list = state.owned_lines.?;

                loaded_profile_states = try ProfileStateCache.load(
                    allocator,
                    line_list,
                    context.spectroscopy_profile_temperatures_k,
                    context.spectroscopy_profile_pressures_hpa,
                    weak_states,
                    strong_states,
                );

                if (loaded_profile_states) {
                    state.profile_weak_line_state_count = weak_states.len;
                    state.profile_strong_line_state_count = strong_states.len;
                }
            }
        }
    }
    if (!loaded_profile_states and
        (state.profile_weak_line_states != null or state.profile_strong_line_states != null))
    {

        // instrumentation: trace zone
        // captures: profile line-state preparation wall time
        // why: expose expensive spectroscopy state setup not covered by cache hits.
        const zone = Trace.staticZone(@src(), "optical_prepare.profile_line_states");
        defer zone.end();
        try prepareProfileLineStates(
            allocator,
            state.owned_lines.?,
            context.spectroscopy_profile_temperatures_k,
            context.spectroscopy_profile_pressures_hpa,
            state.profile_weak_line_states,
            state.profile_strong_line_states,
        );

        if (state.profile_weak_line_states) |states| state.profile_weak_line_state_count = states.len;
        if (state.profile_strong_line_states) |states| state.profile_strong_line_state_count = states.len;
    }
    if (!loaded_profile_states) {
        if (state.profile_weak_line_states) |weak_states| {
            if (state.profile_strong_line_states) |strong_states| {
                try ProfileStateCache.store(
                    state.owned_lines.?,
                    context.spectroscopy_profile_temperatures_k,
                    context.spectroscopy_profile_pressures_hpa,
                    weak_states,
                    strong_states,
                );
            }
        }
    }

    state.active_line_species = if (state.owned_line_absorbers.len == 0)
        try Spectroscopy.resolveActiveLineSpecies(single_active_line_absorber, state.owned_lines, operational_o2_lut)
    else
        null;
    state.continuum_owner_species = Spectroscopy.resolveContinuumOwnerSpecies(
        state.active_line_species,
        state.owned_line_absorbers,
        operational_o2_lut,
    );

    state.has_line_absorbers = single_active_line_absorber != null or state.owned_line_absorbers.len != 0;
    state.mean_sigma = choose_value: {
        break :choose_value if (state.owned_cross_section_absorbers.len == 0)
            context.cross_sections.meanSigmaInRange(
                context.scene.spectral_grid.start_nm,
                context.scene.spectral_grid.end_nm,
            )
        else
            0.0;
    };

    state.midpoint_continuum_sigma = if (state.owned_cross_section_absorbers.len == 0)
        context.cross_sections.interpolateSigma(context.midpoint_nm)
    else
        0.0;
    state.air_mass_factor = context.lut.nearest(
        scene.geometry.solar_zenith_deg,
        scene.geometry.viewing_zenith_deg,
        scene.geometry.relative_azimuth_deg,
    );

    return state;
}

fn prepareProfileLineStates(
    allocator: Allocator,
    line_list: ReferenceData.SpectroscopyLineList,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    weak_states: ?[]ReferenceData.WeakLinePreparedState,
    strong_states: ?[]ReferenceData.StrongLinePreparedState,
) !void {
    // prepareProfileLineStates --------------------------------------------------------------------------------  |
    // Allocates and initializes prepared weak and strong line-state arrays for profile-resolved scenes.          |
    //                                                                                                            |
    // hot path                                                                                                   |
    //   Runs during spectroscopy absorber preparation. The returned profile-node states are later indexed by     |
    //   altitude-aware spectroscopy and carrier evaluation paths.                                                |
    //                                                                                                            |
    // calls                                                                                                      |
    //   fillProfileLineStates                                                                                    |
    // ---------------------------------------------------------------------------------------------------------  |

    if (temperatures_k.len != pressures_hpa.len) return error.InvalidRequest;

    var weak_initialized: usize = 0;
    errdefer if (weak_states) |states| {
        for (states[0..weak_initialized]) |*state| state.deinit(allocator);
    };
    if (weak_states) |states| {
        if (states.len != temperatures_k.len) return error.InvalidRequest;

        // instrumentation: trace zone
        // captures: weak line-state allocation wall time
        // why: distinguish allocation cost from per-profile spectroscopy preparation.
        const zone = Trace.staticZone(@src(), "optical_prepare.profile_weak_alloc");
        defer zone.end();
        for (states) |*slot| {
            slot.* = try line_list.allocWeakLinePreparedState(allocator);
            weak_initialized += 1;
        }
    }

    var strong_initialized: usize = 0;
    errdefer if (strong_states) |states| {
        for (states[0..strong_initialized]) |*state| state.deinit(allocator);
    };
    if (strong_states) |states| {
        if (states.len != temperatures_k.len) return error.InvalidRequest;

        // instrumentation: trace zone
        // captures: strong line-state allocation wall time
        // why: distinguish allocation cost from per-profile spectroscopy preparation.
        const zone = Trace.staticZone(@src(), "optical_prepare.profile_strong_alloc");
        defer zone.end();
        for (states) |*slot| {
            slot.* = (try line_list.allocStrongLinePreparedState(allocator)).?;
            strong_initialized += 1;
        }
    }

    const worker_count = preferredProfileLineStateWorkerCount(temperatures_k.len);
    const strong_weight_count = if (strong_states != null) line_list.strongLinePreparedWeightCount() else 0;
    var empty_strong_relaxation_weight_scratch: [0]f64 = .{};
    const strong_relaxation_weight_scratch: []f64 = if (strong_weight_count != 0)
        try allocator.alloc(f64, worker_count * strong_weight_count)
    else
        empty_strong_relaxation_weight_scratch[0..];
    defer if (strong_relaxation_weight_scratch.len != 0) allocator.free(strong_relaxation_weight_scratch);

    fillProfileLineStates(
        line_list,
        temperatures_k,
        pressures_hpa,
        weak_states,
        strong_states,
        strong_relaxation_weight_scratch,
        strong_weight_count,
    );
}

fn fillProfileLineStates(
    line_list: ReferenceData.SpectroscopyLineList,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    weak_states: ?[]ReferenceData.WeakLinePreparedState,
    strong_states: ?[]ReferenceData.StrongLinePreparedState,
    strong_relaxation_weight_scratch: []f64,
    strong_weight_count: usize,
) void {
    // fillProfileLineStates -----------------------------------------------------------------------------------  |
    // Fills prepared weak and strong line states for each thermodynamic profile node.                            |
    //                                                                                                            |
    // hot path                                                                                                   |
    //   Often splits profile nodes across worker chunks. Each worker reads shared pressure/temperature arrays    |
    //   and writes into caller-owned prepared-state slices.                                                      |
    //                                                                                                            |
    // calls                                                                                                      |
    //   profileLineStateWorkerMain                                                                               |
    //   fillProfileLineStateRange                                                                                |
    // ---------------------------------------------------------------------------------------------------------  |

    const worker_count = preferredProfileLineStateWorkerCount(temperatures_k.len);
    if (worker_count == 1) {
        fillProfileLineStateRange(
            line_list,
            temperatures_k,
            pressures_hpa,
            weak_states,
            strong_states,
            strong_relaxation_weight_scratch[0..strong_weight_count],
            0,
            temperatures_k.len,
        );
        return;
    }

    var queue = work_partition.ChunkQueue.init(temperatures_k.len, profile_line_state_chunk_size);
    var worker_buffer: [work_partition.max_workers]ProfileLineStateWorker = undefined;
    var thread_buffer: [work_partition.max_workers - 1]std.Thread = undefined;
    const workers = worker_buffer[0..worker_count];
    const threads = thread_buffer[0 .. worker_count - 1];
    var started_thread_count: usize = 0;
    var empty_strong_relaxation_weights: [0]f64 = .{};

    for (0..worker_count) |worker_index| {
        const strong_relaxation_weights = if (strong_weight_count != 0)
            strong_relaxation_weight_scratch[worker_index * strong_weight_count ..][0..strong_weight_count]
        else
            empty_strong_relaxation_weights[0..];

        workers[worker_index] = .{
            .line_list = line_list,
            .temperatures_k = temperatures_k,
            .pressures_hpa = pressures_hpa,
            .weak_states = weak_states,
            .strong_states = strong_states,
            .strong_relaxation_weights = strong_relaxation_weights,

            .queue = &queue,
            .worker_index = worker_index,
        };
        if (worker_index + 1 < worker_count) {
            threads[started_thread_count] = std.Thread.spawn(
                .{},

                profileLineStateWorkerMain,
                .{&workers[worker_index]},
            ) catch {
                profileLineStateWorkerMain(&workers[worker_index]);
                continue;
            };

            started_thread_count += 1;
        } else {
            profileLineStateWorkerMain(&workers[worker_index]);
        }
    }
    for (threads[0..started_thread_count]) |thread| thread.join();
}

fn profileLineStateWorkerMain(worker: *ProfileLineStateWorker) void {
    var thread_name_buffer: [64]u8 = undefined;
    const thread_name = std.fmt.bufPrintZ(
        &thread_name_buffer,
        "zdisamar-optics-{d}",
        .{worker.worker_index},
    ) catch "zdisamar-optics-worker";

    // instrumentation: trace thread label
    // captures: profile line-state worker identity
    // why: make parallel spectroscopy-preparation lanes separable in timeline traces.
    Trace.setThreadName(thread_name);

    // instrumentation: trace zone
    // captures: profile line-state worker wall time
    // why: expose work distribution across thermodynamic profile nodes.
    const worker_zone = Trace.staticZone(@src(), "optical_prepare.profile_line_state_worker");
    worker_zone.value(@intCast(worker.worker_index));
    defer worker_zone.end();

    while (worker.queue.next()) |chunk| {
        {

            // instrumentation: trace zone
            // captures: profile line-state chunk wall time and node count
            // why: identify chunking overhead and imbalance in parallel line preparation.
            const chunk_zone = Trace.deepStaticZone(@src(), "optical_prepare.profile_line_state_chunk");
            chunk_zone.value(@intCast(chunk.end - chunk.start));
            defer chunk_zone.end();

            fillProfileLineStateRange(
                worker.line_list,
                worker.temperatures_k,
                worker.pressures_hpa,
                worker.weak_states,
                worker.strong_states,
                worker.strong_relaxation_weights,
                chunk.start,
                chunk.end,
            );
        }
    }
}

fn fillProfileLineStateRange(
    line_list: ReferenceData.SpectroscopyLineList,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    weak_states: ?[]ReferenceData.WeakLinePreparedState,
    strong_states: ?[]ReferenceData.StrongLinePreparedState,
    strong_relaxation_weights: []f64,
    start: usize,
    end: usize,
) void {
    for (start..end) |index| {
        if (weak_states) |states| {
            line_list.prepareWeakLineStateInto(
                &states[index],
                temperatures_k[index],
                pressures_hpa[index],
            );
        }
        if (strong_states) |states| {
            line_list.prepareStrongLineStateIntoWithScratch(
                &states[index],
                strong_relaxation_weights,
                temperatures_k[index],
                pressures_hpa[index],
            );
        }
    }
}

fn preferredProfileLineStateWorkerCount(profile_count: usize) usize {
    return work_partition.preferredWorkerCount(profile_count, min_parallel_profile_line_state_count);
}

fn buildCrossSectionAbsorbers(
    allocator: Allocator,
    context: *Context,
    state: *AbsorberBuildState,
) !void {
    // buildCrossSectionAbsorbers ------------------------------------------------------------------------------  |
    // Collects LUT/table-backed absorbers used by wavelength carrier evaluation.                                 |
    //                                                                                                            |
    // hot path                                                                                                   |
    //   Runs once during absorber preparation and clones only the active cross-section sources. Carrier          |
    //   evaluation then streams the prepared active set without rechecking scene absorber descriptors.           |
    // ---------------------------------------------------------------------------------------------------------  |

    if (state.active_cross_section_absorbers.len == 0) return;
    state.owned_cross_section_absorbers = try allocator.alloc(
        State.PreparedCrossSectionAbsorber,
        state.active_cross_section_absorbers.len,
    );

    for (state.active_cross_section_absorbers, 0..) |cross_section_absorber, index| {
        const representation = switch (cross_section_absorber.representation) {
            .xsec_table => |table| State.PreparedCrossSectionRepresentation{
                .table = .{
                    .points = try allocator.dupe(ReferenceData.CrossSectionPoint, table.points),
                },
            },

            .xsec_lut => |cross_section_lut| State.PreparedCrossSectionRepresentation{
                .lut = try cross_section_lut.clone(allocator),
            },
            .line_abs, .none => unreachable,
        };
        errdefer switch (representation) {
            .table => |table| {
                var owned = table;

                owned.deinit(allocator);
            },
            .lut => |cross_section_lut| {
                var owned = cross_section_lut;
                owned.deinitOwned(allocator);
            },
        };
        const number_densities_cm3 = try allocator.alloc(f64, context.vertical_grid.sublayer_mid_altitudes_km.len);
        errdefer if (number_densities_cm3.len != 0) allocator.free(number_densities_cm3);

        state.owned_cross_section_absorbers[index] = .{
            .species = cross_section_absorber.species,
            .representation = representation,
            .number_densities_cm3 = number_densities_cm3,
        };
        @memset(state.owned_cross_section_absorbers[index].number_densities_cm3, 0.0);
        state.owned_cross_section_absorber_count += 1;
    }
}

fn buildLineAbsorbers(
    allocator: Allocator,
    context: *Context,
    state: *AbsorberBuildState,
    owned_lines: *?ReferenceData.SpectroscopyLineList,
    operational_o2_lut: OperationalCrossSectionLut,
) !void {
    // buildLineAbsorbers --------------------------------------------------------------------------------------  |
    // Applies line controls, partitions strong/weak lines, and prepares match indexes.                           |
    //                                                                                                            |
    // hot path                                                                                                   |
    //   Runs once while preparing spectroscopy line absorbers. Layer spectroscopy and line-list evaluation       |
    //   reuse the filtered lists and prepared sidecars at wavelength time.                                       |
    // ---------------------------------------------------------------------------------------------------------  |

    const line_list = owned_lines.*;
    if (line_list == null) return;
    var line_list_value = line_list.?;

    if (state.active_line_absorbers.len > 1 or
        (operational_o2_lut.enabled() and state.active_line_absorbers.len != 0))
    {
        state.owned_line_absorbers = try allocator.alloc(State.PreparedLineAbsorber, state.active_line_absorbers.len);

        for (state.active_line_absorbers, 0..) |line_absorber, index| {
            var filtered = try line_list_value.clone(allocator);
            errdefer filtered.deinit(allocator);
            const use_operational_o2_lut = operational_o2_lut.enabled() and line_absorber.species == .o2;

            try applyRuntimeControls(
                allocator,
                &filtered,
                line_absorber,
                use_operational_o2_lut,
            );

            if (!use_operational_o2_lut and filtered.lines.len == 0) {
                return error.InvalidRequest;
            }
            sortLineList(&filtered);
            if (!use_operational_o2_lut) {
                try filtered.buildStrongLineMatchIndex(allocator);
            }
            const has_strong_line_states = !use_operational_o2_lut and filtered.hasStrongLineSidecars();
            var strong_line_states: ?[]ReferenceData.StrongLinePreparedState = null;
            var strong_line_state_initialized: ?[]bool = null;
            if (has_strong_line_states) {
                strong_line_states = try allocator.alloc(
                    ReferenceData.StrongLinePreparedState,
                    context.vertical_grid.sublayer_mid_altitudes_km.len,
                );
                errdefer if (strong_line_states) |states| allocator.free(states);
                strong_line_state_initialized = try allocator.alloc(
                    bool,
                    context.vertical_grid.sublayer_mid_altitudes_km.len,
                );
            }

            errdefer if (strong_line_state_initialized) |initialized| allocator.free(initialized);

            state.owned_line_absorbers[index] = .{
                .species = line_absorber.species,
                .line_list = filtered,
                .number_densities_cm3 = try allocator.alloc(
                    f64,
                    context.vertical_grid.sublayer_mid_altitudes_km.len,
                ),
                .strong_line_states = strong_line_states,
                .strong_line_state_initialized = strong_line_state_initialized,
            };
            @memset(state.owned_line_absorbers[index].number_densities_cm3, 0.0);
            if (state.owned_line_absorbers[index].strong_line_state_initialized) |initialized| {
                @memset(initialized, false);
            }
            state.owned_line_absorber_count += 1;
        }

        var owned = line_list_value;
        owned.deinit(allocator);
        owned_lines.* = null;
        state.owned_lines = null;
        return;
    }

    if (state.single_active_line_absorber) |line_absorber| {
        try applyRuntimeControls(
            allocator,
            &line_list_value,
            line_absorber,
            operational_o2_lut.enabled() and line_absorber.species == .o2,
        );
        if (!operational_o2_lut.enabled() and line_list_value.lines.len == 0) {
            return error.InvalidRequest;
        }
    }
    sortLineList(&line_list_value);
    if (!operational_o2_lut.enabled()) {
        try line_list_value.buildStrongLineMatchIndex(allocator);
    }
    state.owned_lines = line_list_value;
    owned_lines.* = null;
}

fn applyRuntimeControls(
    allocator: Allocator,
    line_list: *ReferenceData.SpectroscopyLineList,
    line_absorber: State.ActiveLineAbsorber,
    use_operational_o2_lut: bool,
) !void {
    const active_line_controls = line_absorber.controls.active();

    var hitran_index: ?u16 = null;
    if (line_absorber.species.hitranIndex()) |index| {
        hitran_index = @as(u16, index);
    }

    var line_mixing_factor: f64 = 0.0;
    if (line_absorber.species == .o2) {
        line_mixing_factor = active_line_controls.line_mixing_factor;
    }

    try line_list.applyRuntimeControls(
        allocator,
        hitran_index,
        active_line_controls.isotopes,
        active_line_controls.threshold_line,
        active_line_controls.cutoff_cm1,
        line_mixing_factor,
    );
    if (use_operational_o2_lut) {
        return;
    }
}

fn sortLineList(line_list: *ReferenceData.SpectroscopyLineList) void {
    std.sort.pdq(
        ReferenceData.SpectroscopyLine,
        line_list.lines,
        {},

        // sortLineList comparator --------------------------------------------------------------------------     |
        // Anonymous namespace only. No runtime field storage is passed to pdq; the function body is the          |
        // comparator.                                                                                            |
        // --------------------------------------------------------------------------------------------------     |
        struct {
            fn lessThan(
                _: void,
                left: ReferenceData.SpectroscopyLine,
                right: ReferenceData.SpectroscopyLine,
            ) bool {
                return left.center_wavelength_nm < right.center_wavelength_nm;
            }
        }.lessThan,
    );
    line_list.lines_sorted_ascending = true;
}

fn collectActiveLineAbsorbers(allocator: Allocator, scene: *const Scene) ![]State.ActiveLineAbsorber {
    var active = std.ArrayList(State.ActiveLineAbsorber).empty;
    defer active.deinit(allocator);

    for (scene.absorbers.items) |absorber| {
        const species = Spectroscopy.resolvedAbsorberSpecies(absorber) orelse continue;
        if (!species.isLineAbsorbing()) continue;
        if (absorber.spectroscopy.mode != .line_by_line) continue;

        try active.append(allocator, .{
            .species = species,
            .controls = absorber.spectroscopy.line_gas_controls,
            .volume_mixing_ratio_profile_ppmv = absorber.volume_mixing_ratio_profile_ppmv,
        });
    }
    return active.toOwnedSlice(allocator);
}

fn collectActiveCrossSectionAbsorbers(
    allocator: Allocator,
    scene: *const Scene,
    fallback_cross_sections: *const ReferenceData.CrossSectionTable,
) ![]State.ActiveCrossSectionAbsorber {
    var active = std.ArrayList(State.ActiveCrossSectionAbsorber).empty;
    defer active.deinit(allocator);

    for (scene.absorbers.items) |absorber| {
        const species = Spectroscopy.resolvedAbsorberSpecies(absorber) orelse continue;
        if (absorber.spectroscopy.mode != .cross_sections) continue;

        const representation = switch (absorber.spectroscopy.resolvedAbsorptionRepresentation()) {
            .xsec_table => |table| AbsorberModel.AbsorptionRepresentation{ .xsec_table = table },
            .xsec_lut => |lut| AbsorberModel.AbsorptionRepresentation{ .xsec_lut = lut },
            .line_abs, .none => AbsorberModel.AbsorptionRepresentation{ .xsec_table = fallback_cross_sections },
        };

        try active.append(allocator, .{
            .species = species,
            .representation = representation,
            .volume_mixing_ratio_profile_ppmv = absorber.volume_mixing_ratio_profile_ppmv,
        });
    }

    return active.toOwnedSlice(allocator);
}
