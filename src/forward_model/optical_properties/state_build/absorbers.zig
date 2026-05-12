const std = @import("std");
const AbsorberModel = @import("../../../input/Absorber.zig");
const OperationalCrossSectionLut = @import("../../../input/Instrument.zig").OperationalCrossSectionLut;
const ReferenceData = @import("../../../input/ReferenceData.zig");
const Scene = @import("../../../input/Scene.zig").Scene;
const Context = @import("context.zig").PreparationContext;
const ProfileStateCache = @import("profile_state_cache.zig");
const Spectroscopy = @import("spectroscopy.zig");
const State = @import("state.zig");
const Trace = @import("../../performance_trace.zig");

const Allocator = std.mem.Allocator;
const min_parallel_profile_line_state_count: usize = 4;
const profile_line_state_chunk_size: usize = 2;

const ProfileLineStateQueue = struct {
    mutex: std.Thread.Mutex = .{},
    next_index: usize = 0,
    len: usize,

    fn next(self: *ProfileLineStateQueue) ?struct { start: usize, end: usize } {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.next_index >= self.len) return null;
        const start = self.next_index;
        const end = @min(start + profile_line_state_chunk_size, self.len);
        self.next_index = end;
        return .{ .start = start, .end = end };
    }
};

const ProfileLineStateWorker = struct {
    line_list: ReferenceData.SpectroscopyLineList,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    weak_states: ?[]ReferenceData.WeakLinePreparedState,
    strong_states: ?[]ReferenceData.StrongLinePreparedState,
    queue: *ProfileLineStateQueue,
    worker_index: usize,
};

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
            for (states[0..self.profile_strong_line_state_count]) |*state| state.deinit(allocator);
            if (states.len != 0) allocator.free(states);
        }
        if (self.profile_weak_line_states) |states| {
            for (states[0..self.profile_weak_line_state_count]) |*state| state.deinit(allocator);
            if (states.len != 0) allocator.free(states);
        }
        if (self.owned_line_absorbers.len != 0) {
            for (self.owned_line_absorbers[0..self.owned_line_absorber_count]) |*line_absorber| {
                line_absorber.deinit(allocator);
            }
            allocator.free(self.owned_line_absorbers);
        }
        if (self.owned_cross_section_absorbers.len != 0) {
            for (self.owned_cross_section_absorbers[0..self.owned_cross_section_absorber_count]) |*cross_section_absorber| {
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

pub fn build(
    allocator: Allocator,
    context: *Context,
) !AbsorberBuildState {
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

    state.strong_line_states = if (state.owned_line_absorbers.len == 0)
        if (state.owned_lines) |line_list|
            if (!operational_o2_lut.enabled() and line_list.hasStrongLineSidecars() and context.spectroscopy_profile_temperatures_k.len == 0)
                try allocator.alloc(ReferenceData.StrongLinePreparedState, context.vertical_grid.sublayer_mid_altitudes_km.len)
            else
                null
        else
            null
    else
        null;
    state.profile_strong_line_states = if (state.owned_line_absorbers.len == 0)
        if (state.owned_lines) |line_list|
            if (!operational_o2_lut.enabled() and line_list.hasStrongLineSidecars() and context.spectroscopy_profile_temperatures_k.len != 0)
                try allocator.alloc(ReferenceData.StrongLinePreparedState, context.spectroscopy_profile_temperatures_k.len)
            else
                null
        else
            null
    else
        null;
    state.profile_weak_line_states = if (state.owned_line_absorbers.len == 0)
        if (state.owned_lines) |line_list|
            if (!operational_o2_lut.enabled() and line_list.hasStrongLineSidecars() and context.spectroscopy_profile_temperatures_k.len != 0)
                try allocator.alloc(ReferenceData.WeakLinePreparedState, context.spectroscopy_profile_temperatures_k.len)
            else
                null
        else
            null
    else
        null;
    var loaded_profile_states = false;
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
    if (!loaded_profile_states and (state.profile_weak_line_states != null or state.profile_strong_line_states != null)) {
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
    state.mean_sigma = if (state.owned_cross_section_absorbers.len == 0)
        context.cross_sections.meanSigmaInRange(
            context.scene.spectral_grid.start_nm,
            context.scene.spectral_grid.end_nm,
        )
    else
        0.0;
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
    if (temperatures_k.len != pressures_hpa.len) return error.InvalidRequest;

    var weak_initialized: usize = 0;
    errdefer if (weak_states) |states| {
        for (states[0..weak_initialized]) |*state| state.deinit(allocator);
    };
    if (weak_states) |states| {
        if (states.len != temperatures_k.len) return error.InvalidRequest;
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
        const zone = Trace.staticZone(@src(), "optical_prepare.profile_strong_alloc");
        defer zone.end();
        for (states) |*slot| {
            slot.* = (try line_list.allocStrongLinePreparedState(allocator)).?;
            strong_initialized += 1;
        }
    }

    fillProfileLineStates(
        line_list,
        temperatures_k,
        pressures_hpa,
        weak_states,
        strong_states,
    );
}

fn fillProfileLineStates(
    line_list: ReferenceData.SpectroscopyLineList,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    weak_states: ?[]ReferenceData.WeakLinePreparedState,
    strong_states: ?[]ReferenceData.StrongLinePreparedState,
) void {
    const worker_count = preferredProfileLineStateWorkerCount(temperatures_k.len);
    if (worker_count == 1) {
        fillProfileLineStateRange(
            line_list,
            temperatures_k,
            pressures_hpa,
            weak_states,
            strong_states,
            0,
            temperatures_k.len,
        );
        return;
    }

    var queue: ProfileLineStateQueue = .{ .len = temperatures_k.len };
    var worker_buffer: [Trace.max_workers]ProfileLineStateWorker = undefined;
    var thread_buffer: [Trace.max_workers - 1]std.Thread = undefined;
    const workers = worker_buffer[0..worker_count];
    const threads = thread_buffer[0 .. worker_count - 1];
    var started_thread_count: usize = 0;

    for (0..worker_count) |worker_index| {
        workers[worker_index] = .{
            .line_list = line_list,
            .temperatures_k = temperatures_k,
            .pressures_hpa = pressures_hpa,
            .weak_states = weak_states,
            .strong_states = strong_states,
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
    Trace.setThreadName(thread_name);

    const worker_zone = Trace.staticZone(@src(), "optical_prepare.profile_line_state_worker");
    worker_zone.value(@intCast(worker.worker_index));
    defer worker_zone.end();

    while (worker.queue.next()) |chunk| {
        {
            const chunk_zone = Trace.deepStaticZone(@src(), "optical_prepare.profile_line_state_chunk");
            chunk_zone.value(@intCast(chunk.end - chunk.start));
            defer chunk_zone.end();

            fillProfileLineStateRange(
                worker.line_list,
                worker.temperatures_k,
                worker.pressures_hpa,
                worker.weak_states,
                worker.strong_states,
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
            line_list.prepareStrongLineStateInto(
                &states[index],
                temperatures_k[index],
                pressures_hpa[index],
            );
        }
    }
}

fn preferredProfileLineStateWorkerCount(profile_count: usize) usize {
    if (profile_count < min_parallel_profile_line_state_count) return 1;
    const cpu_count = std.Thread.getCpuCount() catch 1;
    return @min(Trace.max_workers, @min(cpu_count, @max(@as(usize, 1), profile_count / min_parallel_profile_line_state_count)));
}

fn buildCrossSectionAbsorbers(
    allocator: Allocator,
    context: *Context,
    state: *AbsorberBuildState,
) !void {
    if (state.active_cross_section_absorbers.len == 0) return;
    state.owned_cross_section_absorbers = try allocator.alloc(
        State.PreparedCrossSectionAbsorber,
        state.active_cross_section_absorbers.len,
    );

    for (state.active_cross_section_absorbers, 0..) |cross_section_absorber, index| {
        const representation_kind = switch (cross_section_absorber.representation) {
            .xsec_table => if (cross_section_absorber.use_effective_cross_section)
                State.CrossSectionRepresentationKind.effective_table
            else
                State.CrossSectionRepresentationKind.table,
            .xsec_lut => if (cross_section_absorber.use_effective_cross_section)
                State.CrossSectionRepresentationKind.effective_lut
            else
                State.CrossSectionRepresentationKind.lut,
            .line_abs, .none => unreachable,
        };
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
            .representation_kind = representation_kind,
            .polynomial_order = cross_section_absorber.polynomial_order,
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
    const line_list = owned_lines.*;
    if (line_list == null) return;
    var line_list_value = line_list.?;

    if (state.active_line_absorbers.len > 1 or (operational_o2_lut.enabled() and state.active_line_absorbers.len != 0)) {
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
            const strong_line_states = if (has_strong_line_states)
                try allocator.alloc(ReferenceData.StrongLinePreparedState, context.vertical_grid.sublayer_mid_altitudes_km.len)
            else
                null;
            errdefer if (strong_line_states) |states| allocator.free(states);
            const strong_line_state_initialized = if (has_strong_line_states)
                try allocator.alloc(bool, context.vertical_grid.sublayer_mid_altitudes_km.len)
            else
                null;
            errdefer if (strong_line_state_initialized) |initialized| allocator.free(initialized);

            state.owned_line_absorbers[index] = .{
                .species = line_absorber.species,
                .line_list = filtered,
                .number_densities_cm3 = try allocator.alloc(f64, context.vertical_grid.sublayer_mid_altitudes_km.len),
                .strong_line_states = strong_line_states,
                .strong_line_state_initialized = strong_line_state_initialized,
            };
            @memset(state.owned_line_absorbers[index].number_densities_cm3, 0.0);
            if (state.owned_line_absorbers[index].strong_line_state_initialized) |initialized| @memset(initialized, false);
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
    try line_list.applyRuntimeControls(
        allocator,
        if (line_absorber.species.hitranIndex()) |hitran_index|
            @as(u16, hitran_index)
        else
            null,
        line_absorber.controls.activeIsotopes(),
        line_absorber.controls.activeThresholdLine(),
        line_absorber.controls.activeCutoffCm1(),
        if (line_absorber.species == .o2)
            line_absorber.controls.activeLineMixingFactor()
        else
            0.0,
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
        struct {
            fn lessThan(_: void, left: ReferenceData.SpectroscopyLine, right: ReferenceData.SpectroscopyLine) bool {
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

    var any_strong_absorption_band = false;
    for (scene.bands.items, 0..) |_, band_index| {
        if (scene.observation_model.cross_section_fit.strongAbsorptionForBand(band_index)) {
            any_strong_absorption_band = true;
            break;
        }
    }
    const use_effective_cross_section = scene.observation_model.cross_section_fit.use_effective_cross_section_oe or
        scene.observation_model.cross_section_fit.use_polynomial_expansion or
        any_strong_absorption_band;
    const polynomial_order = scene.observation_model.cross_section_fit.maximumPolynomialOrder();

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
            .use_effective_cross_section = use_effective_cross_section,
            .polynomial_order = polynomial_order,
        });
    }

    return active.toOwnedSlice(allocator);
}
