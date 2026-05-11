const std = @import("std");
const Scene = @import("../../../input/Scene.zig").Scene;
const Accumulation = @import("accumulation.zig");
const Absorbers = @import("absorbers.zig");
const Context = @import("context.zig");
const Finalize = @import("finalize.zig");
const State = @import("state.zig");
const Trace = @import("../../performance_trace.zig");

const Allocator = std.mem.Allocator;

pub const PreparationInputs = Context.PreparationInputs;
pub const PrepareTrace = struct {
    context_init_ns: u64 = 0,
    absorbers_build_ns: u64 = 0,
    accumulation_ns: u64 = 0,
    finalize_ns: u64 = 0,
    shared_geometry_ns: u64 = 0,
};

pub fn prepare(
    allocator: Allocator,
    scene: *const Scene,
    inputs: PreparationInputs,
) !State.PreparedOpticalState {
    return prepareWithTrace(allocator, scene, inputs, null);
}

pub fn prepareWithTrace(
    allocator: Allocator,
    scene: *const Scene,
    inputs: PreparationInputs,
    trace: ?*PrepareTrace,
) !State.PreparedOpticalState {
    if (trace) |profile| profile.* = .{};

    const context_start = std.time.nanoTimestamp();
    var context = context: {
        const zone = Trace.staticZone(@src(), "optical_prepare.context_init");
        defer zone.end();
        break :context try Context.init(allocator, scene, inputs);
    };
    if (trace) |profile| profile.context_init_ns = elapsedNs(context_start);
    defer context.deinit(allocator);

    const absorber_start = std.time.nanoTimestamp();
    var absorber_state = absorber_state: {
        const zone = Trace.staticZone(@src(), "optical_prepare.absorbers_build");
        defer zone.end();
        break :absorber_state try Absorbers.build(allocator, &context);
    };
    if (trace) |profile| profile.absorbers_build_ns = elapsedNs(absorber_start);
    defer absorber_state.deinit(allocator);

    const accumulation_start = std.time.nanoTimestamp();
    const accumulation = accumulation: {
        const zone = Trace.staticZone(@src(), "optical_prepare.accumulation");
        defer zone.end();
        break :accumulation try Accumulation.accumulate(allocator, &context, &absorber_state);
    };
    if (trace) |profile| profile.accumulation_ns = elapsedNs(accumulation_start);

    const finalize_start = std.time.nanoTimestamp();
    var prepared = prepared: {
        const zone = Trace.staticZone(@src(), "optical_prepare.finalize");
        defer zone.end();
        break :prepared Finalize.assemble(&context, &absorber_state, accumulation);
    };
    if (trace) |profile| profile.finalize_ns = elapsedNs(finalize_start);
    errdefer prepared.deinit(allocator);

    const shared_geometry_start = std.time.nanoTimestamp();
    {
        const zone = Trace.staticZone(@src(), "optical_prepare.shared_geometry");
        defer zone.end();
        try prepared.ensureSharedRtmGeometryCache(allocator);
    }
    if (trace) |profile| profile.shared_geometry_ns = elapsedNs(shared_geometry_start);
    return prepared;
}

fn elapsedNs(start: i128) u64 {
    return @intCast(@max(std.time.nanoTimestamp() - start, 0));
}
