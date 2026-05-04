const std = @import("std");
const Scene = @import("../../../input/Scene.zig").Scene;
const Accumulation = @import("accumulation.zig");
const Absorbers = @import("absorbers.zig");
const Context = @import("context.zig");
const Finalize = @import("finalize.zig");
const State = @import("state.zig");

const Allocator = std.mem.Allocator;
const trace_env_name = "ZDISAMAR_TRACE_O2A_PREPARE";

pub const PreparationInputs = Context.PreparationInputs;

pub fn prepare(
    allocator: Allocator,
    scene: *const Scene,
    inputs: PreparationInputs,
) !State.PreparedOpticalState {
    var trace = Trace.init();
    var context = try Context.init(allocator, scene, inputs);
    defer context.deinit(allocator);
    trace.mark("optics.context_init");

    var absorber_state = try Absorbers.build(allocator, &context);
    defer absorber_state.deinit(allocator);
    trace.mark("optics.absorbers_build");

    const accumulation = try Accumulation.accumulate(allocator, &context, &absorber_state);
    trace.mark("optics.accumulate");

    var prepared = Finalize.assemble(&context, &absorber_state, accumulation);
    errdefer prepared.deinit(allocator);
    trace.mark("optics.finalize");

    try prepared.ensureSharedRtmGeometryCache(allocator);
    trace.mark("optics.shared_rtm_geometry");
    return prepared;
}

const Trace = struct {
    enabled: bool,
    previous_ns: i128,
    start_ns: i128,

    fn init() Trace {
        const enabled = std.process.hasEnvVarConstant(trace_env_name);
        const now = if (enabled) std.time.nanoTimestamp() else 0;
        return .{
            .enabled = enabled,
            .previous_ns = now,
            .start_ns = now,
        };
    }

    fn mark(self: *Trace, label: []const u8) void {
        if (!self.enabled) return;
        const now = std.time.nanoTimestamp();
        std.debug.print(
            "o2a_prepare_trace {s} delta_ms={d:.3} total_ms={d:.3}\n",
            .{
                label,
                nsToMs(now - self.previous_ns),
                nsToMs(now - self.start_ns),
            },
        );
        self.previous_ns = now;
    }
};

fn nsToMs(ns: i128) f64 {
    return @as(f64, @floatFromInt(ns)) / 1.0e6;
}
