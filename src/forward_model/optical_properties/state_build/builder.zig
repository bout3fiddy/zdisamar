const std = @import("std");
const Scene = @import("../../../input/Scene.zig").Scene;
const Accumulation = @import("accumulation.zig");
const Absorbers = @import("absorbers.zig");
const Context = @import("context.zig");
const Finalize = @import("finalize.zig");
const State = @import("state.zig");
const prepare_trace = @import("../../../common/prepare_trace.zig");

const Allocator = std.mem.Allocator;

pub const PreparationInputs = Context.PreparationInputs;

pub fn prepare(
    allocator: Allocator,
    scene: *const Scene,
    inputs: PreparationInputs,
) !State.PreparedOpticalState {
    var trace = prepare_trace.Trace.init();
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
