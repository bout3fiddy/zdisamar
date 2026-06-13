const std = @import("std");
const build_options = @import("build_options");

// cost_timing.zig ------------------------------------------------------------------------------------------- |
// Opt-in per-stage cost counters for trace builds. Product, test, telemetry, and perturbation builds keep the |
// same source calls, but comptime enabled=false turns workspace cost state into a zero-size type and makes    |
// start/finish/count return before any clock read, counter write, or worker merge.                            |
//                                                                                                             |
//   cost timing calls without inventing a new instrumentation shape.                                          |
//                                                                                                             |
// build route                                                                                                 |
//   build.zig sets enable_cost_timing=false for normal artifacts. Enabled trace/test builds set it true and   |
//   attach one worker-local StageCost row through WorkspaceState.                                             |
//                                                                                                             |
// hot path                                                                                                    |
//   The call sites sit inside high-resolution wavelength, Fourier, layer-doubling, and scattering-order       |
//   loops. In trace builds, each worker writes only its own StageCost row, so the loop path takes no locks;   |
//   cross-worker aggregation happens after workers finish. Counter updates saturate so long traces cannot     |
//   wrap elapsed-time or event totals.                                                                        |
//                                                                                                             |
// memory                                                                                                      |
//   StageCost is 456 B: 24 elapsed-time Counter rows plus 9 event Count rows. WorkspaceState is 0 B normally  |
//   and one 8 B optional StageCost pointer in the trace build. Active is a borrowed 8 B pointer handle        |
//   threaded through measured calls; no cost-timing type owns heap storage.                                   |
// ----------------------------------------------------------------------------------------------------------- |

pub const enabled: bool = enabled_by_build: {
    if (!@hasDecl(build_options, "enable_cost_timing")) break :enabled_by_build false;
    break :enabled_by_build build_options.enable_cost_timing;
};

// Counter --------------------------------------------------------------------------------------------------- |
// Elapsed-time bucket for one LABOS phase.                                                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] ns    : u64                                                                                        |
// [ 8..15] count : u64                                                                                        |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total = per timed stage in StageCost                            |
pub const Counter = struct {
    ns: u64 = 0,
    count: u64 = 0,

    pub fn add(self: *Counter, elapsed_ns: u64) void {
        // Counter.add --------------------------------------------------------------------------------------- |
        // Saturating elapsed-time accumulation for trace runs that span many LABOS worker phases.             |
        // --------------------------------------------------------------------------------------------------- |
        self.ns +|= elapsed_ns;
        self.count +|= 1;
    }

    pub fn merge(self: *Counter, other: Counter) void {
        // Counter.merge ------------------------------------------------------------------------------------- |
        // Merge one worker bucket into the retained run summary with saturating totals.                       |
        // --------------------------------------------------------------------------------------------------- |
        self.ns +|= other.ns;
        self.count +|= other.count;
    }
};
// ----------------------------------------------------------------------------------------------------------- |

// Count ----------------------------------------------------------------------------------------------------- |
// Event-count bucket for fixed-kernel decisions that do not need elapsed time.                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 8 B (0.008 KiB), align: 8 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
// [0..7] count : u64                                                                                          |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 8 B (0.008 KiB); total = per counted event in StageCost                           |
pub const Count = struct {
    count: u64 = 0,

    pub fn add(self: *Count, amount: u64) void {
        // Count.add ----------------------------------------------------------------------------------------- |
        // Saturating event accumulation for fixed-kernel skip/retain counters.                                |
        // --------------------------------------------------------------------------------------------------- |
        self.count +|= amount;
    }

    pub fn merge(self: *Count, other: Count) void {
        // Count.merge --------------------------------------------------------------------------------------- |
        // Merge one worker event bucket into the retained run summary.                                        |
        // --------------------------------------------------------------------------------------------------- |
        self.count +|= other.count;
    }
};
// ----------------------------------------------------------------------------------------------------------- |

// StageCost --------------------------------------------------------------------------------------------------|
// Per-worker LABOS trace payload merged into the product-level trace summary after forward prefetch.          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 456 B (0.445 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 15] execute                  : Counter                                                               |
// [ 16.. 31] attenuation_fill         : Counter                                                               |
// [ 32.. 47] fourier_loop             : Counter                                                               |
// [ 48.. 63] plm_basis                : Counter                                                               |
// [ 64.. 79] rt_layer_build           : Counter                                                               |
// [ 80.. 95] rt_layer_phase_matrix    : Counter                                                               |
// [ 96..111] rt_layer_doubling        : Counter                                                               |
// [112..127] fixed_qseries_work       : Counter                                                               |
// [128..143] fixed_rd_update          : Counter                                                               |
// [144..159] fixed_tu_update          : Counter                                                               |
// [160..175] fixed_td_update          : Counter                                                               |
// [176..191] orders_total             : Counter                                                               |
// [192..207] orders_initial_sources   : Counter                                                               |
// [208..223] orders_initial_transport : Counter                                                               |
// [224..239] orders_local_down        : Counter                                                               |
// [240..255] orders_local_up          : Counter                                                               |
// [256..271] orders_transport         : Counter                                                               |
// [272..287] orders_accumulate        : Counter                                                               |
// [288..303] reflectance_integral     : Counter                                                               |
// [304..319] optics_assembly          : Counter                                                               |
// [320..335] spectroscopy_sigma       : Counter                                                               |
// [336..351] partition_interp         : Counter                                                               |
// [352..367] profile_interp           : Counter                                                               |
// [368..383] quadrature_build         : Counter                                                               |
// [384..391] fixed_doubling_steps     : Count                                                                 |
// [392..399] fixed_qseries_skipped    : Count                                                                 |
// [400..407] fixed_qseries_retained   : Count                                                                 |
// [408..415] fixed_rd_skipped         : Count                                                                 |
// [416..423] fixed_rd_retained        : Count                                                                 |
// [424..431] fixed_tu_skipped         : Count                                                                 |
// [432..439] fixed_tu_retained        : Count                                                                 |
// [440..447] fixed_td_skipped         : Count                                                                 |
// [448..455] fixed_td_retained        : Count                                                                 |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 8 cache lines at 64 B per line                                                                  |
// footprint: per instance = 456 B (0.445 KiB); total = one per active forward worker in trace builds          |
pub const StageCost = struct {
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
    optics_assembly: Counter = .{},
    spectroscopy_sigma: Counter = .{},
    partition_interp: Counter = .{},
    profile_interp: Counter = .{},
    quadrature_build: Counter = .{},
    fixed_doubling_steps: Count = .{},
    fixed_qseries_skipped: Count = .{},
    fixed_qseries_retained: Count = .{},
    fixed_rd_skipped: Count = .{},
    fixed_rd_retained: Count = .{},
    fixed_tu_skipped: Count = .{},
    fixed_tu_retained: Count = .{},
    fixed_td_skipped: Count = .{},
    fixed_td_retained: Count = .{},

    pub fn reset(self: *StageCost) void {
        // StageCost.reset ----------------------------------------------------------------------------------- |
        // Clear one worker-local cost row before reuse by a trace run.                                        |
        // --------------------------------------------------------------------------------------------------- |
        self.* = .{};
    }

    pub fn merge(self: *StageCost, other: StageCost) void {
        // StageCost.merge ----------------------------------------------------------------------------------- |
        // Merge every stage bucket from one worker row into the retained run summary.                         |
        // --------------------------------------------------------------------------------------------------- |
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
        self.optics_assembly.merge(other.optics_assembly);
        self.spectroscopy_sigma.merge(other.spectroscopy_sigma);
        self.partition_interp.merge(other.partition_interp);
        self.profile_interp.merge(other.profile_interp);
        self.quadrature_build.merge(other.quadrature_build);
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
// ----------------------------------------------------------------------------------------------------------- |

pub const WorkerStageCost = if (enabled) StageCost else struct {};

pub inline fn resetWorkerStageCost(worker_stage_cost: *WorkerStageCost) void {
    // resetWorkerStageCost ---------------------------------------------------------------------------------- |
    // Reset the per-worker row only in enabled cost-timing builds.                                            |
    // ------------------------------------------------------------------------------------------------------- |

    if (comptime !enabled) return;

    worker_stage_cost.reset();
}

pub inline fn setWorkerWorkspaceState(state: *WorkspaceState, worker_stage_cost: *WorkerStageCost) void {
    // setWorkerWorkspaceState ------------------------------------------------------------------------------- |
    // Attach the per-worker row while keeping disabled worker storage zero-size.                              |
    // ------------------------------------------------------------------------------------------------------- |

    if (comptime !enabled) return;

    setWorkspaceState(state, worker_stage_cost);
}

pub inline fn mergeWorkerStageCost(merged: *StageCost, worker_stage_cost: *const WorkerStageCost) void {
    // mergeWorkerStageCost ---------------------------------------------------------------------------------- |
    // Merge one enabled worker row into the caller-owned summary row.                                         |
    // ------------------------------------------------------------------------------------------------------- |

    if (comptime !enabled) return;

    merged.merge(worker_stage_cost.*);
}

// Active ---------------------------------------------------------------------------------------------------- |
// Small non-owning handle threaded through measured calls that can record stage cost.                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 8 B (0.008 KiB), align: 8 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
// [0..7] stage_cost : *StageCost                                                                              |
//                                                                                                             |
// referenced storage: stage_cost points at the worker-local StageCost row owned by forward worker storage.    |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 8 B (0.008 KiB); total = borrowed handle only                                     |
pub const Active = struct {
    stage_cost: *StageCost,
};
// ----------------------------------------------------------------------------------------------------------- |

// WorkspaceState -------------------------------------------------------------------------------------------- |
// Compile-time selected workspace hook for the optional cost-timing sink.                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// normal build: size 0 B, align 1                                                                             |
// trace build : size 8 B (0.008 KiB), align 8                                                                 |
//                                                                                                             |
// memory, trace build                                                                                         |
// [0..7] stage_cost : ?*StageCost                                                                             |
//                                                                                                             |
// referenced storage: stage_cost points at the worker-local StageCost row, or null when no sink is attached.  |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: normally zero-size; trace build adds one pointer inside each LABOS workspace                     |
pub const WorkspaceState = if (enabled) struct {
    stage_cost: ?*StageCost = null,
} else struct {};
// ----------------------------------------------------------------------------------------------------------- |

pub inline fn setWorkspaceState(state: *WorkspaceState, stage_cost: *StageCost) void {
    // setWorkspaceState ------------------------------------------------------------------------------------- |
    // Attach one worker-local StageCost row to a workspace when cost timing is enabled.                       |
    // ------------------------------------------------------------------------------------------------------- |

    if (comptime !enabled) return;

    state.* = .{
        .stage_cost = stage_cost,
    };
}

pub inline fn clearWorkspaceState(state: *WorkspaceState) void {
    // clearWorkspaceState ----------------------------------------------------------------------------------- |
    // Detach the optional worker StageCost row from a workspace.                                              |
    // ------------------------------------------------------------------------------------------------------- |

    if (comptime !enabled) return;

    state.* = .{};
}

pub inline fn setActiveWorkspaceState(state: *WorkspaceState, active: ?Active) void {
    // setActiveWorkspaceState ------------------------------------------------------------------------------- |
    // Copy an already-resolved active cost handle into another workspace hook.                                |
    // ------------------------------------------------------------------------------------------------------- |

    if (comptime !enabled) return;

    const resolved = active orelse {
        state.* = .{};
        return;
    };
    state.* = .{
        .stage_cost = resolved.stage_cost,
    };
}

pub inline fn activeWorkspaceState(state: *WorkspaceState) ?Active {
    // activeWorkspaceState ---------------------------------------------------------------------------------- |
    // Resolve the borrowed active cost handle for measured calls.                                             |
    // ------------------------------------------------------------------------------------------------------- |

    if (comptime !enabled) return null;

    const stage_cost = state.stage_cost orelse return null;
    return .{
        .stage_cost = stage_cost,
    };
}

pub inline fn start(active: ?Active) ?i128 {
    // start ------------------------------------------------------------------------------------------------- |
    // Return a timestamp only when the trace build and an active worker sink are both present.                |
    // ------------------------------------------------------------------------------------------------------- |

    if (comptime !enabled) return null;

    _ = active orelse return null;
    return std.time.nanoTimestamp();
}

pub inline fn finish(active: ?Active, start_timestamp: ?i128, comptime field_name: []const u8) void {
    // finish ------------------------------------------------------------------------------------------------ |
    // Add elapsed nanoseconds into one named Counter. Non-positive clock deltas are ignored, and very large   |
    // deltas saturate to maxInt(u64) before the Counter performs saturating addition.                         |
    // ------------------------------------------------------------------------------------------------------- |

    if (comptime !enabled) return;

    const resolved = active orelse return;
    const started = start_timestamp orelse return;
    const finished = std.time.nanoTimestamp();
    if (finished <= started) return;

    const elapsed_ns = finished - started;
    if (elapsed_ns <= 0) return;
    @field(resolved.stage_cost, field_name).add(std.math.cast(u64, elapsed_ns) orelse std.math.maxInt(u64));
}

pub inline fn count(active: ?Active, comptime field_name: []const u8, amount: u64) void {
    // count ------------------------------------------------------------------------------------------------- |
    // Add one event count into a named Count bucket when cost timing is active.                               |
    // ------------------------------------------------------------------------------------------------------- |

    if (comptime !enabled) return;

    const resolved = active orelse return;
    @field(resolved.stage_cost, field_name).add(amount);
}

pub inline fn dumpMergedStageCostToStderr(stage_cost: StageCost) void {
    // dumpMergedStageCostToStderr --------------------------------------------------------------------------- |
    // Emit one fixed-field merged row from the instrumentation facade, never from the product path.           |
    // ------------------------------------------------------------------------------------------------------- |

    if (comptime !enabled) return;

    std.debug.print("cost_timing", .{});
    dumpCounter("execute", stage_cost.execute);
    dumpCounter("attenuation_fill", stage_cost.attenuation_fill);
    dumpCounter("fourier_loop", stage_cost.fourier_loop);
    dumpCounter("plm_basis", stage_cost.plm_basis);
    dumpCounter("rt_layer_build", stage_cost.rt_layer_build);
    dumpCounter("rt_layer_phase_matrix", stage_cost.rt_layer_phase_matrix);
    dumpCounter("rt_layer_doubling", stage_cost.rt_layer_doubling);
    dumpCounter("fixed_qseries_work", stage_cost.fixed_qseries_work);
    dumpCounter("fixed_rd_update", stage_cost.fixed_rd_update);
    dumpCounter("fixed_tu_update", stage_cost.fixed_tu_update);
    dumpCounter("fixed_td_update", stage_cost.fixed_td_update);
    dumpCounter("orders_total", stage_cost.orders_total);
    dumpCounter("orders_initial_sources", stage_cost.orders_initial_sources);
    dumpCounter("orders_initial_transport", stage_cost.orders_initial_transport);
    dumpCounter("orders_local_down", stage_cost.orders_local_down);
    dumpCounter("orders_local_up", stage_cost.orders_local_up);
    dumpCounter("orders_transport", stage_cost.orders_transport);
    dumpCounter("orders_accumulate", stage_cost.orders_accumulate);
    dumpCounter("reflectance_integral", stage_cost.reflectance_integral);
    dumpCounter("optics_assembly", stage_cost.optics_assembly);
    dumpCounter("spectroscopy_sigma", stage_cost.spectroscopy_sigma);
    dumpCounter("partition_interp", stage_cost.partition_interp);
    dumpCounter("profile_interp", stage_cost.profile_interp);
    dumpCounter("quadrature_build", stage_cost.quadrature_build);
    dumpCount("fixed_doubling_steps", stage_cost.fixed_doubling_steps);
    dumpCount("fixed_qseries_skipped", stage_cost.fixed_qseries_skipped);
    dumpCount("fixed_qseries_retained", stage_cost.fixed_qseries_retained);
    dumpCount("fixed_rd_skipped", stage_cost.fixed_rd_skipped);
    dumpCount("fixed_rd_retained", stage_cost.fixed_rd_retained);
    dumpCount("fixed_tu_skipped", stage_cost.fixed_tu_skipped);
    dumpCount("fixed_tu_retained", stage_cost.fixed_tu_retained);
    dumpCount("fixed_td_skipped", stage_cost.fixed_td_skipped);
    dumpCount("fixed_td_retained", stage_cost.fixed_td_retained);
    std.debug.print("\n", .{});
}

fn dumpCounter(comptime name: []const u8, counter: Counter) void {
    // dumpCounter ------------------------------------------------------------------------------------------- |
    // Append one elapsed-time field pair to the current stderr row.                                           |
    // ------------------------------------------------------------------------------------------------------- |
    std.debug.print(" {s}.ns={} {s}.count={}", .{ name, counter.ns, name, counter.count });
}

fn dumpCount(comptime name: []const u8, counter: Count) void {
    // dumpCount --------------------------------------------------------------------------------------------- |
    // Append one event-count field to the current stderr row.                                                 |
    // ------------------------------------------------------------------------------------------------------- |
    std.debug.print(" {s}.count={}", .{ name, counter.count });
}
