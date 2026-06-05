const std = @import("std");
const build_options = @import("build_options");

// phase_timing.zig ------------------------------------------------------------------------------------------|
// Low-overhead LABOS phase clock used by trace research harnesses.                                           |
//                                                                                                            |
// Normal product and test builds set enable_trace_phase_timing=false, so start/finish calls compile to       |
// no-ops. The trace executable opts in, attaches one Timing object per forward worker through Workspace,     |
// and merges those counters into the retained JSON summary after the worker batch finishes.                  |
// -----------------------------------------------------------------------------------------------------------|

pub const enabled: bool = enabled_by_build: {
    if (!@hasDecl(build_options, "enable_trace_phase_timing")) break :enabled_by_build false;
    break :enabled_by_build build_options.enable_trace_phase_timing;
};

pub const Counter = struct {
    ns: u64 = 0,
    count: u64 = 0,

    pub fn add(self: *Counter, elapsed_ns: u64) void {
        self.ns +|= elapsed_ns;
        self.count +|= 1;
    }

    pub fn merge(self: *Counter, other: Counter) void {
        self.ns +|= other.ns;
        self.count +|= other.count;
    }
};

pub const Count = struct {
    count: u64 = 0,

    pub fn add(self: *Count, amount: u64) void {
        self.count +|= amount;
    }

    pub fn merge(self: *Count, other: Count) void {
        self.count +|= other.count;
    }
};

pub const Timing = struct {
    execute: Counter = .{},
    attenuation_fill: Counter = .{},
    fourier_loop: Counter = .{},
    plm_basis: Counter = .{},
    rt_layer_build: Counter = .{},
    rt_layer_phase_matrix: Counter = .{},
    rt_layer_doubling: Counter = .{},
    fixed_qseries_work: Counter = .{},
    fixed_rd_update: Counter = .{},
    fixed_tu_update: Counter = .{},
    fixed_td_update: Counter = .{},
    orders_total: Counter = .{},
    orders_initial_sources: Counter = .{},
    orders_initial_transport: Counter = .{},
    orders_local_down: Counter = .{},
    orders_local_up: Counter = .{},
    orders_transport: Counter = .{},
    orders_accumulate: Counter = .{},
    reflectance_integral: Counter = .{},
    fixed_doubling_steps: Count = .{},
    fixed_qseries_skipped: Count = .{},
    fixed_qseries_retained: Count = .{},
    fixed_rd_skipped: Count = .{},
    fixed_rd_retained: Count = .{},
    fixed_tu_skipped: Count = .{},
    fixed_tu_retained: Count = .{},
    fixed_td_skipped: Count = .{},
    fixed_td_retained: Count = .{},

    pub fn reset(self: *Timing) void {
        self.* = .{};
    }

    pub fn merge(self: *Timing, other: Timing) void {
        self.execute.merge(other.execute);
        self.attenuation_fill.merge(other.attenuation_fill);
        self.fourier_loop.merge(other.fourier_loop);
        self.plm_basis.merge(other.plm_basis);
        self.rt_layer_build.merge(other.rt_layer_build);
        self.rt_layer_phase_matrix.merge(other.rt_layer_phase_matrix);
        self.rt_layer_doubling.merge(other.rt_layer_doubling);
        self.fixed_qseries_work.merge(other.fixed_qseries_work);
        self.fixed_rd_update.merge(other.fixed_rd_update);
        self.fixed_tu_update.merge(other.fixed_tu_update);
        self.fixed_td_update.merge(other.fixed_td_update);
        self.orders_total.merge(other.orders_total);
        self.orders_initial_sources.merge(other.orders_initial_sources);
        self.orders_initial_transport.merge(other.orders_initial_transport);
        self.orders_local_down.merge(other.orders_local_down);
        self.orders_local_up.merge(other.orders_local_up);
        self.orders_transport.merge(other.orders_transport);
        self.orders_accumulate.merge(other.orders_accumulate);
        self.reflectance_integral.merge(other.reflectance_integral);
        self.fixed_doubling_steps.merge(other.fixed_doubling_steps);
        self.fixed_qseries_skipped.merge(other.fixed_qseries_skipped);
        self.fixed_qseries_retained.merge(other.fixed_qseries_retained);
        self.fixed_rd_skipped.merge(other.fixed_rd_skipped);
        self.fixed_rd_retained.merge(other.fixed_rd_retained);
        self.fixed_tu_skipped.merge(other.fixed_tu_skipped);
        self.fixed_tu_retained.merge(other.fixed_tu_retained);
        self.fixed_td_skipped.merge(other.fixed_td_skipped);
        self.fixed_td_retained.merge(other.fixed_td_retained);
    }
};

pub const Active = struct {
    io: std.Io,
    timing: *Timing,
};

pub const WorkspaceState = if (enabled) struct {
    io: ?std.Io = null,
    timing: ?*Timing = null,
} else struct {};

pub inline fn setWorkspaceState(
    state: *WorkspaceState,
    io: std.Io,
    timing: *Timing,
) void {
    if (comptime !enabled) {
        return;
    }

    state.* = .{
        .io = io,
        .timing = timing,
    };
}

pub inline fn clearWorkspaceState(state: *WorkspaceState) void {
    if (comptime !enabled) {
        return;
    }

    state.* = .{};
}

pub inline fn setActiveWorkspaceState(state: *WorkspaceState, active: ?Active) void {
    if (comptime !enabled) {
        return;
    }

    const resolved = active orelse {
        state.* = .{};
        return;
    };
    state.* = .{
        .io = resolved.io,
        .timing = resolved.timing,
    };
}

pub inline fn activeWorkspaceState(state: *WorkspaceState) ?Active {
    if (comptime !enabled) {
        return null;
    }

    const timing = state.timing orelse return null;
    const io = state.io orelse return null;
    return .{
        .io = io,
        .timing = timing,
    };
}

pub inline fn start(active: ?Active) ?std.Io.Timestamp {
    if (comptime !enabled) {
        return null;
    }

    const resolved = active orelse return null;
    return std.Io.Clock.boot.now(resolved.io);
}

pub inline fn finish(
    active: ?Active,
    start_timestamp: ?std.Io.Timestamp,
    comptime field_name: []const u8,
) void {
    if (comptime !enabled) {
        return;
    }

    const resolved = active orelse return;
    const started = start_timestamp orelse return;
    const elapsed_ns = started.durationTo(std.Io.Clock.boot.now(resolved.io)).toNanoseconds();
    if (elapsed_ns <= 0) return;
    @field(resolved.timing, field_name).add(std.math.cast(u64, elapsed_ns) orelse std.math.maxInt(u64));
}

pub inline fn count(
    active: ?Active,
    comptime field_name: []const u8,
    amount: u64,
) void {
    if (comptime !enabled) {
        return;
    }

    const resolved = active orelse return;
    @field(resolved.timing, field_name).add(amount);
}
