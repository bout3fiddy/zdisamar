// Mutation and selection helpers for spectroscopy line lists.

const std = @import("std");
const LineList = @import("line_list.zig");
const Physics = @import("physics.zig");
const Support = @import("support.zig");
const Types = @import("types.zig");

const SpectroscopyLineList = LineList.SpectroscopyLineList;

pub fn attachStrongLineSidecars(
    self: *SpectroscopyLineList,
    allocator: Types.Allocator,
    strong_lines: Types.SpectroscopyStrongLineSet,
    relaxation_matrix: Types.RelaxationMatrix,
) !void {
    if (self.strong_lines) |owned_strong_lines| allocator.free(owned_strong_lines);
    if (self.relaxation_matrix) |*owned_relaxation_matrix| owned_relaxation_matrix.deinit(allocator);
    if (self.strong_line_match_by_line) |matches| allocator.free(matches);
    self.strong_line_match_by_line = null;

    self.strong_lines = try allocator.dupe(Types.SpectroscopyStrongLine, strong_lines.lines);
    errdefer {
        if (self.strong_lines) |owned_strong_lines| allocator.free(owned_strong_lines);
        self.strong_lines = null;
    }
    self.relaxation_matrix = try relaxation_matrix.clone(allocator);
    self.vendor_strong_line_partition = detectVendorStrongLinePartition(self.*);
    try validateStrongLinePartition(self);
}

pub fn buildStrongLineMatchIndex(self: *SpectroscopyLineList, allocator: Types.Allocator) !void {
    if (self.strong_line_match_by_line) |matches| {
        allocator.free(matches);
        self.strong_line_match_by_line = null;
    }
    if (!self.hasStrongLineSidecars() or self.lines.len == 0) return;
    try validateStrongLinePartition(self);

    const matches = try allocator.alloc(?u16, self.lines.len);
    errdefer allocator.free(matches);
    for (self.lines, 0..) |line, line_index| {
        if (usesVendorStrongLinePartition(self.*) and !Support.isVendorO2AStrongCandidateFromSource(line)) {
            matches[line_index] = null;
            continue;
        }
        matches[line_index] = if (findStrongLineMatch(self.*, line.center_wavelength_nm)) |strong_index|
            @intCast(strong_index)
        else
            null;
    }
    self.strong_line_match_by_line = matches;
}

// hot path:
//   when: spectroscopy line lists are prepared for a scene/session
//   work: filters and partitions lines according to runtime controls
//   data: source lines, control thresholds, strong-line sidecars, filtered line storage
//   follow: line-list shape consumed by relevantLineWindowForWavelength
pub fn applyRuntimeControls(
    self: *SpectroscopyLineList,
    allocator: Types.Allocator,
    gas_index: ?u16,
    active_isotopes: []const u8,
    threshold_line_scale: ?f64,
    cutoff_cm1: ?f64,
    line_mixing_factor: f64,
) !void {
    const replacement_active_isotopes = if (active_isotopes.len != 0)
        try allocator.dupe(u8, active_isotopes)
    else
        &.{};
    self.runtime_controls.deinitOwned(allocator);
    self.runtime_controls = .{
        .gas_index = gas_index,
        .active_isotopes = replacement_active_isotopes,
        .threshold_line_scale = threshold_line_scale,
        .cutoff_cm1 = cutoff_cm1,
        .line_mixing_factor = line_mixing_factor,
    };

    if (gas_index != null or active_isotopes.len != 0) {
        var retained_count: usize = 0;
        for (self.lines) |line| {
            if (Support.runtimeControlsMatchLine(gas_index, active_isotopes, line)) retained_count += 1;
        }
        if (retained_count != self.lines.len) {
            const retained = try allocator.alloc(Types.SpectroscopyLine, retained_count);
            errdefer allocator.free(retained);
            var write_index: usize = 0;
            for (self.lines) |line| {
                if (!Support.runtimeControlsMatchLine(gas_index, active_isotopes, line)) continue;
                retained[write_index] = line;
                write_index += 1;
            }
            allocator.free(self.lines);
            self.lines = retained;
            self.lines_sorted_ascending = false;
        }
    }

    if (self.strong_line_match_by_line) |matches| {
        allocator.free(matches);
        self.strong_line_match_by_line = null;
    }
    if (self.strong_lines != null and !Support.runtimeControlsKeepStrongLineSidecars(gas_index, active_isotopes)) {
        disableStrongLineSidecars(self, allocator);
        return;
    }
    self.vendor_strong_line_partition = detectVendorStrongLinePartition(self.*);
    try validateStrongLinePartition(self);
}

pub fn prepareStrongLineState(
    self: SpectroscopyLineList,
    allocator: Types.Allocator,
    temperature_k: f64,
    pressure_hpa: f64,
) !?Types.StrongLinePreparedState {
    if (!self.hasStrongLineSidecars()) return null;
    var prepared = (try allocStrongLinePreparedState(self, allocator)).?;
    errdefer prepared.deinit(allocator);
    prepareStrongLineStateInto(self, &prepared, temperature_k, pressure_hpa);
    return prepared;
}

pub fn allocStrongLinePreparedState(
    self: SpectroscopyLineList,
    allocator: Types.Allocator,
) !?Types.StrongLinePreparedState {
    if (!self.hasStrongLineSidecars()) return null;
    const line_count = strongLinePreparedLineCount(self);
    const population_t = try allocator.alloc(f64, line_count);
    errdefer allocator.free(population_t);
    const dipole_t = try allocator.alloc(f64, line_count);
    errdefer allocator.free(dipole_t);
    const mod_sig_cm1 = try allocator.alloc(f64, line_count);
    errdefer allocator.free(mod_sig_cm1);
    const half_width_cm1_at_t = try allocator.alloc(f64, line_count);
    errdefer allocator.free(half_width_cm1_at_t);
    const line_mixing_coefficients = try allocator.alloc(f64, line_count);
    errdefer allocator.free(line_mixing_coefficients);
    const relaxation_weights = try allocator.alloc(f64, line_count * line_count);
    return .{
        .line_count = line_count,
        .sig_moy_cm1 = 0.0,
        .population_t = population_t,
        .dipole_t = dipole_t,
        .mod_sig_cm1 = mod_sig_cm1,
        .half_width_cm1_at_t = half_width_cm1_at_t,
        .line_mixing_coefficients = line_mixing_coefficients,
        .relaxation_weights = relaxation_weights,
    };
}

// hot path:
//   when: preparing strong-line spectroscopy state for profile nodes or effective state
//   work: fills pressure/temperature-dependent strong-line relaxation state
//   data: strong-line sidecars, relaxation matrix, pressure/temperature inputs, state output
//   follow: strongLineContributionPrepared and prepared sidecar ordering
pub fn prepareStrongLineStateInto(
    self: SpectroscopyLineList,
    prepared: *Types.StrongLinePreparedState,
    temperature_k: f64,
    pressure_hpa: f64,
) void {
    std.debug.assert(self.hasStrongLineSidecars());
    const pressure_scale = @max(pressure_hpa / 1013.25, Types.min_spectroscopy_pressure_atm);
    const stack_state = Physics.prepareStrongLineConvTPState(
        self.strong_lines.?,
        self.relaxation_matrix.?,
        @max(temperature_k, 150.0),
        pressure_scale,
    );
    const line_count = stack_state.line_count;
    std.debug.assert(prepared.population_t.len >= line_count);
    std.debug.assert(prepared.dipole_t.len >= line_count);
    std.debug.assert(prepared.mod_sig_cm1.len >= line_count);
    std.debug.assert(prepared.half_width_cm1_at_t.len >= line_count);
    std.debug.assert(prepared.line_mixing_coefficients.len >= line_count);
    std.debug.assert(prepared.relaxation_weights.len >= line_count * line_count);

    prepared.line_count = line_count;
    prepared.sig_moy_cm1 = stack_state.sig_moy_cm1;
    @memcpy(prepared.population_t[0..line_count], stack_state.population_t[0..line_count]);
    @memcpy(prepared.dipole_t[0..line_count], stack_state.dipole_t[0..line_count]);
    @memcpy(prepared.mod_sig_cm1[0..line_count], stack_state.mod_sig_cm1[0..line_count]);
    @memcpy(prepared.half_width_cm1_at_t[0..line_count], stack_state.half_width_cm1_at_t[0..line_count]);
    @memcpy(prepared.line_mixing_coefficients[0..line_count], stack_state.line_mixing_coefficients[0..line_count]);
    for (0..line_count) |row_index| {
        for (0..line_count) |column_index| {
            prepared.relaxation_weights[row_index * line_count + column_index] =
                stack_state.weightAt(row_index, column_index);
        }
    }
}

pub fn prepareWeakLineState(
    self: SpectroscopyLineList,
    allocator: Types.Allocator,
    temperature_k: f64,
    pressure_hpa: f64,
) !Types.WeakLinePreparedState {
    var prepared = try allocWeakLinePreparedState(self, allocator);
    prepareWeakLineStateInto(self, &prepared, temperature_k, pressure_hpa);
    return prepared;
}

pub fn allocWeakLinePreparedState(
    self: SpectroscopyLineList,
    allocator: Types.Allocator,
) !Types.WeakLinePreparedState {
    return .{
        .line_count = self.lines.len,
        .lines = try allocator.alloc(Types.WeakLinePreparedLineState, self.lines.len),
    };
}

// hot path:
//   when: preparing weak-line spectroscopy state for profile nodes or effective state
//   work: fills thermodynamic weak-line state for repeated wavelength evaluation
//   data: weak-line array, pressure/temperature inputs, prepared weak-line state output
//   follow: weakLineSigmaPreparedWithStimulatedEmissionScale and cutoff helpers
pub fn prepareWeakLineStateInto(
    self: SpectroscopyLineList,
    prepared: *Types.WeakLinePreparedState,
    temperature_k: f64,
    pressure_hpa: f64,
) void {
    std.debug.assert(prepared.lines.len >= self.lines.len);
    const pressure_scale = @max(pressure_hpa / 1013.25, Types.min_spectroscopy_pressure_atm);
    for (self.lines, prepared.lines[0..self.lines.len]) |line, *slot| {
        slot.* = Physics.prepareWeakLinePreparedLineState(
            line,
            temperature_k,
            pressure_scale,
            Types.hitran_reference_temperature_k,
        );
    }
    prepared.line_count = self.lines.len;
}

fn strongLinePreparedLineCount(self: SpectroscopyLineList) usize {
    return @min(
        @min(self.strong_lines.?.len, self.relaxation_matrix.?.line_count),
        Types.max_strong_line_sidecars,
    );
}

pub fn findStrongLineMatch(self: SpectroscopyLineList, wavelength_nm: f64) ?usize {
    const strong_lines = self.strong_lines orelse return null;

    var best_index: ?usize = null;
    var best_delta = std.math.inf(f64);
    for (strong_lines, 0..) |strong_line, index| {
        const delta = @abs(strong_line.center_wavelength_nm - wavelength_nm);
        const tolerance_nm = @max(self.strong_line_tolerance_nm, strong_line.air_half_width_nm * 4.0);
        if (delta > tolerance_nm or delta >= best_delta) continue;
        best_index = index;
        best_delta = delta;
    }
    return best_index;
}

pub const RelevantLineWindow = struct {
    lines: []const Types.SpectroscopyLine,
    start_index: usize,
};

// hot path:
//   when: every wavelength/support-row line-list evaluation selects weak lines
//   work: maps wavelength to a compact relevant-line window
//   data: sorted line centers, vendor cutoff bounds, line-list window metadata
//   follow: totalSigma* loops that iterate the returned window
pub fn relevantLineWindowForWavelength(self: SpectroscopyLineList, wavelength_nm: f64) RelevantLineWindow {
    if (!self.lines_sorted_ascending) {
        return .{
            .lines = self.lines,
            .start_index = 0,
        };
    }
    const cutoff_cm1 = self.runtime_controls.cutoff_cm1 orelse {
        return .{
            .lines = self.lines,
            .start_index = 0,
        };
    };
    const vendor_discrete_cutoff_cm1 = cutoff_cm1 + Types.vendor_cutoff_prewindow_margin_cm1;
    const evaluation_wavenumber_cm1 = Physics.wavelengthToWavenumberCm1(wavelength_nm);
    const minimum_wavenumber_cm1 = @max(evaluation_wavenumber_cm1 - vendor_discrete_cutoff_cm1, 1.0e-6);
    const maximum_wavenumber_cm1 = evaluation_wavenumber_cm1 + vendor_discrete_cutoff_cm1;
    const minimum_wavelength_nm = Support.wavenumberCm1ToWavelengthNm(maximum_wavenumber_cm1);
    const maximum_wavelength_nm = Support.wavenumberCm1ToWavelengthNm(minimum_wavenumber_cm1);
    const lower = Physics.lowerBoundLineIndex(self.lines, minimum_wavelength_nm);
    const upper = Physics.upperBoundLineIndex(self.lines, maximum_wavelength_nm);
    return .{
        .lines = self.lines[lower..upper],
        .start_index = lower,
    };
}

// hot path:
//   when: line-mixing evaluation prepares weak-to-strong anchor matches
//   work: selects nearby strong-line anchors for the current weak-line window
//   data: strong-line match index, relevant weak lines, window start index, anchor array
//   follow: weakLineRow/totalSigmaWithStrongLineSidecars anchor lookups
pub fn selectStrongLineAnchors(
    self: SpectroscopyLineList,
    relevant_lines: []const Types.SpectroscopyLine,
    start_index: usize,
) [Types.max_strong_line_sidecars]?usize {
    var anchors = [_]?usize{null} ** Types.max_strong_line_sidecars;
    const strong_lines = self.strong_lines orelse return anchors;
    if (usesVendorStrongLinePartition(self)) return anchors;

    var deltas = [_]f64{std.math.inf(f64)} ** Types.max_strong_line_sidecars;
    for (relevant_lines, 0..) |line, line_index| {
        const strong_index = matchedStrongIndexForRelevantLine(self, start_index, line, line_index) orelse continue;
        const delta = @abs(strong_lines[strong_index].center_wavelength_nm - line.center_wavelength_nm);
        if (delta > deltas[strong_index]) continue;
        if (delta == deltas[strong_index] and anchors[strong_index] != null) {
            const incumbent = relevant_lines[anchors[strong_index].?];
            if (incumbent.line_strength_cm2_per_molecule >= line.line_strength_cm2_per_molecule) continue;
        }
        anchors[strong_index] = line_index;
        deltas[strong_index] = delta;
    }
    return anchors;
}

pub fn matchedStrongIndexForRelevantLine(
    self: SpectroscopyLineList,
    start_index: usize,
    line: Types.SpectroscopyLine,
    line_index: usize,
) ?usize {
    if (self.strong_line_match_by_line) |matches| {
        const global_index = start_index + line_index;
        if (global_index < matches.len) {
            if (matches[global_index]) |strong_index| return @as(usize, strong_index);
            return null;
        }
    }
    if (usesVendorStrongLinePartition(self)) {
        if (!Support.isVendorO2AStrongCandidateFromSource(line)) return null;
        return findStrongLineMatch(self, line.center_wavelength_nm);
    }
    return findStrongLineMatch(self, line.center_wavelength_nm);
}

// hot path:
//   when: weak-line sigma loops decide whether a line is covered by a strong sidecar
//   work: checks vendor partition rules and strong-line anchor matches for one relevant weak line
//   data: relevant-window start index, line metadata, strong-line anchor array, match index
//   follow: totalSigmaWithStrongLineSidecars and diagnostic weak-line row expansion
pub fn shouldExcludeWeakLine(
    self: SpectroscopyLineList,
    start_index: usize,
    line: Types.SpectroscopyLine,
    line_index: usize,
    strong_line_anchors: *const [Types.max_strong_line_sidecars]?usize,
) bool {
    if (usesVendorStrongLinePartition(self)) {
        if (self.preserve_anchor_weak_lines) return false;
        if (!Support.isVendorO2AStrongCandidateFromSource(line)) return false;
        return matchedStrongIndexForRelevantLine(self, start_index, line, line_index) != null;
    }
    const strong_index = matchedStrongIndexForRelevantLine(self, start_index, line, line_index) orelse return false;
    if (self.preserve_anchor_weak_lines) return false;
    if (strong_line_anchors[strong_index]) |anchor_line_index| {
        return anchor_line_index == line_index;
    }
    return false;
}

pub fn validateStrongLinePartition(self: *const SpectroscopyLineList) !void {
    if (!usesVendorStrongLinePartition(self.*)) return;

    const strong_lines = self.strong_lines orelse return;
    if (strong_lines.len > Types.max_strong_line_sidecars) return error.TooManyStrongLineSidecars;

    var saw_candidate = false;
    var matched_candidate = false;
    for (self.lines) |line| {
        if (!Support.isVendorO2AStrongCandidateFromSource(line)) continue;
        saw_candidate = true;
        _ = findStrongLineMatch(self.*, line.center_wavelength_nm) orelse continue;
        matched_candidate = true;
    }
    if (saw_candidate and !matched_candidate) return error.UnmatchedStrongLineCandidate;
}

pub fn usesVendorStrongLinePartition(self: SpectroscopyLineList) bool {
    return self.hasStrongLineSidecars() and self.vendor_strong_line_partition;
}

pub fn disableStrongLineSidecars(self: *SpectroscopyLineList, allocator: Types.Allocator) void {
    if (self.strong_lines) |strong_lines| allocator.free(strong_lines);
    self.strong_lines = null;
    if (self.relaxation_matrix) |*relaxation_matrix| relaxation_matrix.deinit(allocator);
    self.relaxation_matrix = null;
    if (self.strong_line_match_by_line) |matches| allocator.free(matches);
    self.strong_line_match_by_line = null;
    self.vendor_strong_line_partition = false;
}

fn detectVendorStrongLinePartition(self: SpectroscopyLineList) bool {
    if (!self.hasStrongLineSidecars()) return false;
    if (self.runtime_controls.gas_index) |gas_index| {
        if (gas_index != 7) return false;
    }
    for (self.lines) |line| {
        if (line.gas_index != 7) continue;
        if (Support.lineHasVendorStrongLineMetadata(line)) return true;
    }
    return false;
}
