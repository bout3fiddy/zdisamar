const std = @import("std");
const build_options = @import("build_options");

// phase_timing.zig ------------------------------------------------------------------------------------------|
// Opt-in LABOS phase timers for trace builds. Product, test, telemetry, and perturbation builds keep the     |
// same source calls, but comptime enabled=false turns workspace timing state into a zero-size type and makes |
// start/finish/count return before any clock read, counter write, or worker merge.                           |
//                                                                                                            |
// provenance                                                                                                 |
//   Ports main:`src/forward_model/radiative_transfer/labos/phase_timing.zig`. The field set matches the old  |
//   LABOS trace sink so later layer-doubling, order, execute, and spectrum worker ports can preserve their   |
//   phase timing calls without inventing a new instrumentation shape.                                        |
//                                                                                                            |
// build route                                                                                                |
//   build.zig sets enable_trace_phase_timing=false for normal artifacts. Enabled trace/test builds set it    |
//   true and attach one worker-local Timing row through WorkspaceState.                                      |
//                                                                                                            |
// hot path                                                                                                   |
//   The call sites sit inside high-resolution wavelength, Fourier, layer-doubling, and scattering-order      |
//   loops. In trace builds, each worker writes only its own Timing row, so the loop path takes no locks;     |
//   cross-worker aggregation happens after workers finish. Counter updates saturate so long traces cannot    |
//   wrap elapsed-time or event totals.                                                                       |
//                                                                                                            |
// memory                                                                                                     |
//   Timing is 376 B: 19 elapsed-time Counter rows plus 9 event Count rows. WorkspaceState is 0 B normally    |
//   and one 8 B optional Timing pointer in the trace build. Active is a borrowed 8 B pointer handle threaded |
//   through LABOS calls; no timing type owns heap storage.                                                   |
// -----------------------------------------------------------------------------------------------------------|

pub const enabled: bool = enabled_by_build: {
    if (!@hasDecl(build_options, "enable_trace_phase_timing")) break :enabled_by_build false;
    break :enabled_by_build build_options.enable_trace_phase_timing;
};

// Counter ---------------------------------------------------------------------------------------------------|
// Elapsed-time bucket for one LABOS phase.                                                                   |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 16 B (0.016 KiB), align: 8 B                                                                         |
//                                                                                                            |
// memory                                                                                                     |
// [ 0.. 7] ns    : u64                                                                                       |
// [ 8..15] count : u64                                                                                       |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// footprint: per instance = 16 B (0.016 KiB); total = per timed phase in Timing                              |
pub const Counter = struct {
    ns: u64 = 0,
    count: u64 = 0,

    pub fn add(self: *Counter, elapsed_ns: u64) void {
        // Counter.add ---------------------------------------------------------------------------------------|
        // Saturating elapsed-time accumulation for trace runs that span many LABOS worker phases.            |
        // ---------------------------------------------------------------------------------------------------|
        self.ns +|= elapsed_ns;
        self.count +|= 1;
    }

    pub fn merge(self: *Counter, other: Counter) void {
        // Counter.merge -------------------------------------------------------------------------------------|
        // Merge one worker bucket into the retained run summary with saturating totals.                      |
        // ---------------------------------------------------------------------------------------------------|
        self.ns +|= other.ns;
        self.count +|= other.count;
    }
};
// -----------------------------------------------------------------------------------------------------------|

// Count -----------------------------------------------------------------------------------------------------|
// Event-count bucket for fixed-kernel decisions that do not need elapsed time.                               |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 8 B (0.008 KiB), align: 8 B                                                                          |
//                                                                                                            |
// memory                                                                                                     |
// [0..7] count : u64                                                                                         |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// footprint: per instance = 8 B (0.008 KiB); total = per counted event in Timing                             |
pub const Count = struct {
    count: u64 = 0,

    pub fn add(self: *Count, amount: u64) void {
        // Count.add -----------------------------------------------------------------------------------------|
        // Saturating event accumulation for fixed-kernel skip/retain counters.                               |
        // ---------------------------------------------------------------------------------------------------|
        self.count +|= amount;
    }

    pub fn merge(self: *Count, other: Count) void {
        // Count.merge ---------------------------------------------------------------------------------------|
        // Merge one worker event bucket into the retained run summary.                                       |
        // ---------------------------------------------------------------------------------------------------|
        self.count +|= other.count;
    }
};
// -----------------------------------------------------------------------------------------------------------|

// Timing ----------------------------------------------------------------------------------------------------|
// Per-worker LABOS trace payload merged into the product-level trace summary after forward prefetch.         |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 376 B (0.367 KiB), align: 8 B                                                                        |
//                                                                                                            |
// memory                                                                                                     |
// [  0.. 15] execute                  : Counter                                                              |
// [ 16.. 31] attenuation_fill         : Counter                                                              |
// [ 32.. 47] fourier_loop             : Counter                                                              |
// [ 48.. 63] plm_basis                : Counter                                                              |
// [ 64.. 79] rt_layer_build           : Counter                                                              |
// [ 80.. 95] rt_layer_phase_matrix    : Counter                                                              |
// [ 96..111] rt_layer_doubling        : Counter                                                              |
// [112..127] fixed_qseries_work       : Counter                                                              |
// [128..143] fixed_rd_update          : Counter                                                              |
// [144..159] fixed_tu_update          : Counter                                                              |
// [160..175] fixed_td_update          : Counter                                                              |
// [176..191] orders_total             : Counter                                                              |
// [192..207] orders_initial_sources   : Counter                                                              |
// [208..223] orders_initial_transport : Counter                                                              |
// [224..239] orders_local_down        : Counter                                                              |
// [240..255] orders_local_up          : Counter                                                              |
// [256..271] orders_transport         : Counter                                                              |
// [272..287] orders_accumulate        : Counter                                                              |
// [288..303] reflectance_integral     : Counter                                                              |
// [304..311] fixed_doubling_steps     : Count                                                                |
// [312..319] fixed_qseries_skipped    : Count                                                                |
// [320..327] fixed_qseries_retained   : Count                                                                |
// [328..335] fixed_rd_skipped         : Count                                                                |
// [336..343] fixed_rd_retained        : Count                                                                |
// [344..351] fixed_tu_skipped         : Count                                                                |
// [352..359] fixed_tu_retained        : Count                                                                |
// [360..367] fixed_td_skipped         : Count                                                                |
// [368..375] fixed_td_retained        : Count                                                                |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 6 cache lines at 64 B per line                                                                 |
// footprint: per instance = 376 B (0.367 KiB); total = one per active forward worker in trace builds         |
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
        // Timing.reset --------------------------------------------------------------------------------------|
        // Clear one worker-local timing row before reuse by a trace run.                                     |
        // ---------------------------------------------------------------------------------------------------|
        self.* = .{};
    }

    pub fn merge(self: *Timing, other: Timing) void {
        // Timing.merge --------------------------------------------------------------------------------------|
        // Merge every old LABOS phase bucket from one worker row into the retained run summary.              |
        // ---------------------------------------------------------------------------------------------------|
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
// -----------------------------------------------------------------------------------------------------------|

// Active ----------------------------------------------------------------------------------------------------|
// Small non-owning handle threaded through LABOS calls that can record phase timing.                         |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 8 B (0.008 KiB), align: 8 B                                                                          |
//                                                                                                            |
// memory                                                                                                     |
// [0..7] timing : *Timing                                                                                    |
//                                                                                                            |
// referenced storage: timing points at the worker-local Timing row owned by spectrum trace storage.          |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// footprint: per instance = 8 B (0.008 KiB); total = borrowed handle only                                    |
pub const Active = struct {
    timing: *Timing,
};
// -----------------------------------------------------------------------------------------------------------|

// WorkspaceState --------------------------------------------------------------------------------------------|
// Compile-time selected LABOS workspace hook for the optional phase-timing sink.                             |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// normal build: size 0 B, align 1                                                                            |
// trace build : size 8 B (0.008 KiB), align 8                                                                |
//                                                                                                            |
// memory, trace build                                                                                        |
// [0..7] timing : ?*Timing                                                                                   |
//                                                                                                            |
// referenced storage: timing points at the worker-local Timing row, or null when no trace sink is attached.  |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// footprint: normally zero-size; trace build adds one pointer inside each LABOS workspace                    |
pub const WorkspaceState = if (enabled) struct {
    timing: ?*Timing = null,
} else struct {};
// -----------------------------------------------------------------------------------------------------------|

pub inline fn setWorkspaceState(state: *WorkspaceState, timing: *Timing) void {
    // setWorkspaceState -------------------------------------------------------------------------------------|
    // Attach one worker-local Timing row to a LABOS workspace when phase timing is enabled.                  |
    // -------------------------------------------------------------------------------------------------------|

    if (comptime !enabled) return;

    state.* = .{
        .timing = timing,
    };
}

pub inline fn clearWorkspaceState(state: *WorkspaceState) void {
    // clearWorkspaceState -----------------------------------------------------------------------------------|
    // Detach the optional worker timing row from a LABOS workspace.                                          |
    // -------------------------------------------------------------------------------------------------------|

    if (comptime !enabled) return;

    state.* = .{};
}

pub inline fn setActiveWorkspaceState(state: *WorkspaceState, active: ?Active) void {
    // setActiveWorkspaceState -------------------------------------------------------------------------------|
    // Copy an already-resolved active timing handle into another workspace hook.                             |
    // -------------------------------------------------------------------------------------------------------|

    if (comptime !enabled) return;

    const resolved = active orelse {
        state.* = .{};
        return;
    };
    state.* = .{
        .timing = resolved.timing,
    };
}

pub inline fn activeWorkspaceState(state: *WorkspaceState) ?Active {
    // activeWorkspaceState ----------------------------------------------------------------------------------|
    // Resolve the borrowed active timing handle for LABOS calls.                                             |
    // -------------------------------------------------------------------------------------------------------|

    if (comptime !enabled) return null;

    const timing = state.timing orelse return null;
    return .{
        .timing = timing,
    };
}

pub inline fn start(active: ?Active) ?i128 {
    // start -------------------------------------------------------------------------------------------------|
    // Return a timestamp only when the trace build and an active worker sink are both present.               |
    // -------------------------------------------------------------------------------------------------------|

    if (comptime !enabled) return null;

    _ = active orelse return null;
    return std.time.nanoTimestamp();
}

pub inline fn finish(active: ?Active, start_timestamp: ?i128, comptime field_name: []const u8) void {
    // finish ------------------------------------------------------------------------------------------------|
    // Add elapsed nanoseconds into one named Counter. Non-positive clock deltas are ignored, and very large  |
    // deltas saturate to maxInt(u64) before the Counter performs saturating addition.                        |
    // -------------------------------------------------------------------------------------------------------|

    if (comptime !enabled) return;

    const resolved = active orelse return;
    const started = start_timestamp orelse return;
    const finished = std.time.nanoTimestamp();
    if (finished <= started) return;

    const elapsed_ns = finished - started;
    if (elapsed_ns <= 0) return;
    @field(resolved.timing, field_name).add(std.math.cast(u64, elapsed_ns) orelse std.math.maxInt(u64));
}

pub inline fn count(active: ?Active, comptime field_name: []const u8, amount: u64) void {
    // count -------------------------------------------------------------------------------------------------|
    // Add one event count into a named Count bucket when phase timing is active.                             |
    // -------------------------------------------------------------------------------------------------------|

    if (comptime !enabled) return;

    const resolved = active orelse return;
    @field(resolved.timing, field_name).add(amount);
}
