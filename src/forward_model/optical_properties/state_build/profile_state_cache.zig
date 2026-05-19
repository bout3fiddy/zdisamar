const std = @import("std");
const ReferenceData = @import("../../../input/ReferenceData.zig");
const SpectroscopyTypes = @import("../../../input/reference/spectroscopy/types.zig");

const Allocator = std.mem.Allocator;

// layout(64-bit):
//   size: 40 B, align: 8 B
//   field storage: key=8 B, strong_states=16 B, weak_states=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: strong_states, weak_states carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 40 B (0.039 KiB); total also includes referenced storage above
const Entry = struct {
    key: u64,
    strong_states: []ReferenceData.StrongLinePreparedState,
    weak_states: []ReferenceData.WeakLinePreparedState,

    fn deinit(self: *Entry, allocator: Allocator) void {
        for (self.strong_states) |*state| state.deinit(allocator);
        allocator.free(self.strong_states);
        for (self.weak_states) |*state| state.deinit(allocator);
        allocator.free(self.weak_states);
        self.* = undefined;
    }
};

var mutex = std.Thread.Mutex{};
var cached_entry: ?Entry = null;

// hot path:
//   when: spectroscopy profile prepared states can be reused across preparation runs
//   work: checks cache key and clones prepared weak/strong line states into caller storage
//   data: line list, temperature/pressure profile arrays, cached prepared states
//   follow: absorbers.prepareProfileLineStates and profile-state cache key shape
pub fn load(
    allocator: Allocator,
    line_list: ReferenceData.SpectroscopyLineList,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    weak_out: []ReferenceData.WeakLinePreparedState,
    strong_out: []ReferenceData.StrongLinePreparedState,
) !bool {
    if (!compatibleShape(temperatures_k, pressures_hpa, weak_out, strong_out)) return false;

    const key = computeKey(line_list, temperatures_k, pressures_hpa);
    mutex.lock();
    defer mutex.unlock();

    const entry = cached_entry orelse return false;
    if (entry.key != key or entry.weak_states.len != weak_out.len or entry.strong_states.len != strong_out.len) return false;

    var weak_count: usize = 0;
    errdefer {
        for (weak_out[0..weak_count]) |*state| state.deinit(allocator);
    }
    for (entry.weak_states, weak_out) |source, *target| {
        target.* = try cloneWeakState(allocator, source);
        weak_count += 1;
    }

    var strong_count: usize = 0;
    errdefer {
        for (strong_out[0..strong_count]) |*state| state.deinit(allocator);
    }
    for (entry.strong_states, strong_out) |source, *target| {
        target.* = try cloneStrongState(allocator, source);
        strong_count += 1;
    }

    return true;
}

// hot path:
//   when: spectroscopy profile prepared states are saved after preparation
//   work: clones weak/strong prepared line states into the process cache
//   data: line list, temperature/pressure profile arrays, prepared weak/strong states
//   follow: future profile_state_cache.load calls and cache key computation
pub fn store(
    line_list: ReferenceData.SpectroscopyLineList,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    weak_states: []const ReferenceData.WeakLinePreparedState,
    strong_states: []const ReferenceData.StrongLinePreparedState,
) !void {
    if (!compatibleShape(temperatures_k, pressures_hpa, weak_states, strong_states)) return;

    const allocator = std.heap.smp_allocator;
    const key = computeKey(line_list, temperatures_k, pressures_hpa);
    var entry = Entry{
        .key = key,
        .strong_states = try allocator.alloc(ReferenceData.StrongLinePreparedState, strong_states.len),
        .weak_states = &.{},
    };
    errdefer {
        for (entry.strong_states[0..0]) |*state| state.deinit(allocator);
        allocator.free(entry.strong_states);
    }

    var strong_count: usize = 0;
    errdefer {
        for (entry.strong_states[0..strong_count]) |*state| state.deinit(allocator);
    }
    for (strong_states, entry.strong_states) |source, *target| {
        target.* = try cloneStrongState(allocator, source);
        strong_count += 1;
    }

    entry.weak_states = try allocator.alloc(ReferenceData.WeakLinePreparedState, weak_states.len);
    errdefer allocator.free(entry.weak_states);
    var weak_count: usize = 0;
    errdefer {
        for (entry.weak_states[0..weak_count]) |*state| state.deinit(allocator);
    }
    for (weak_states, entry.weak_states) |source, *target| {
        target.* = try cloneWeakState(allocator, source);
        weak_count += 1;
    }

    mutex.lock();
    defer mutex.unlock();
    if (cached_entry) |*old| old.deinit(allocator);
    cached_entry = entry;
}

fn compatibleShape(
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    weak_states: anytype,
    strong_states: anytype,
) bool {
    return temperatures_k.len != 0 and
        temperatures_k.len == pressures_hpa.len and
        temperatures_k.len == weak_states.len and
        temperatures_k.len == strong_states.len;
}

fn cloneStrongState(
    allocator: Allocator,
    source: ReferenceData.StrongLinePreparedState,
) !ReferenceData.StrongLinePreparedState {
    const population_t = try allocator.dupe(f64, source.population_t);
    errdefer allocator.free(population_t);
    const dipole_t = try allocator.dupe(f64, source.dipole_t);
    errdefer allocator.free(dipole_t);
    const mod_sig_cm1 = try allocator.dupe(f64, source.mod_sig_cm1);
    errdefer allocator.free(mod_sig_cm1);
    const half_width_cm1_at_t = try allocator.dupe(f64, source.half_width_cm1_at_t);
    errdefer allocator.free(half_width_cm1_at_t);
    const line_mixing_coefficients = try allocator.dupe(f64, source.line_mixing_coefficients);
    return .{
        .line_count = source.line_count,
        .sig_moy_cm1 = source.sig_moy_cm1,
        .population_t = population_t,
        .dipole_t = dipole_t,
        .mod_sig_cm1 = mod_sig_cm1,
        .half_width_cm1_at_t = half_width_cm1_at_t,
        .line_mixing_coefficients = line_mixing_coefficients,
    };
}

fn cloneWeakState(
    allocator: Allocator,
    source: ReferenceData.WeakLinePreparedState,
) !ReferenceData.WeakLinePreparedState {
    return .{
        .line_count = source.line_count,
        .safe_temperature = source.safe_temperature,
        .safe_pressure = source.safe_pressure,
        .lines = try allocator.dupe(SpectroscopyTypes.WeakLinePreparedLineState, source.lines),
    };
}

fn computeKey(
    line_list: ReferenceData.SpectroscopyLineList,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
) u64 {
    var hash = std.hash.Wyhash.init(0);
    updateInt(&hash, temperatures_k.len);
    hash.update(std.mem.sliceAsBytes(temperatures_k));
    hash.update(std.mem.sliceAsBytes(pressures_hpa));

    updateInt(&hash, line_list.lines.len);
    for (line_list.lines) |line| {
        updateInt(&hash, line.gas_index);
        updateInt(&hash, line.isotope_number);
        updateFloat(&hash, line.center_wavelength_nm);
        updateFloat(&hash, line.center_wavenumber_cm1);
        updateFloat(&hash, line.line_strength_cm2_per_molecule);
        updateFloat(&hash, line.air_half_width_cm1);
        updateFloat(&hash, line.temperature_exponent);
        updateFloat(&hash, line.lower_state_energy_cm1);
        updateFloat(&hash, line.pressure_shift_cm1);
        updateInt(&hash, line.branch_ic1 orelse 0);
        updateInt(&hash, line.branch_ic2 orelse 0);
        updateInt(&hash, line.rotational_nf orelse 0);
    }

    if (line_list.strong_lines) |strong_lines| {
        updateInt(&hash, strong_lines.len);
        for (strong_lines) |line| {
            updateFloat(&hash, line.center_wavenumber_cm1);
            updateFloat(&hash, line.population_t0);
            updateFloat(&hash, line.dipole_ratio);
            updateFloat(&hash, line.dipole_t0);
            updateFloat(&hash, line.lower_state_energy_cm1);
            updateFloat(&hash, line.air_half_width_cm1);
            updateFloat(&hash, line.temperature_exponent);
            updateFloat(&hash, line.pressure_shift_cm1);
            updateInt(&hash, line.rotational_index_m1);
        }
    } else {
        updateInt(&hash, @as(usize, 0));
    }

    if (line_list.relaxation_matrix) |matrix| {
        updateInt(&hash, matrix.line_count);
        hash.update(std.mem.sliceAsBytes(matrix.wt0));
        hash.update(std.mem.sliceAsBytes(matrix.bw));
    } else {
        updateInt(&hash, @as(usize, 0));
    }

    const controls = line_list.runtime_controls;
    updateOptionalInt(&hash, controls.gas_index);
    hash.update(controls.active_isotopes);
    updateOptionalFloat(&hash, controls.threshold_line_scale);
    updateOptionalFloat(&hash, controls.cutoff_cm1);
    updateFloat(&hash, controls.line_mixing_factor);
    return hash.final();
}

fn updateFloat(hash: *std.hash.Wyhash, value: f64) void {
    var bits = @as(u64, @bitCast(value));
    hash.update(std.mem.asBytes(&bits));
}

fn updateOptionalFloat(hash: *std.hash.Wyhash, value: ?f64) void {
    updateInt(hash, value != null);
    if (value) |payload| updateFloat(hash, payload);
}

fn updateOptionalInt(hash: *std.hash.Wyhash, value: anytype) void {
    updateInt(hash, value != null);
    if (value) |payload| updateInt(hash, payload);
}

fn updateInt(hash: *std.hash.Wyhash, value: anytype) void {
    var bits = value;
    hash.update(std.mem.asBytes(&bits));
}
