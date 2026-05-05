const std = @import("std");
const Scene = @import("../../../input/Scene.zig").Scene;
const Accumulation = @import("accumulation.zig");
const Absorbers = @import("absorbers.zig");
const Context = @import("context.zig");
const Finalize = @import("finalize.zig");
const State = @import("state.zig");

const Allocator = std.mem.Allocator;

pub const PreparationInputs = Context.PreparationInputs;

pub fn prepare(
    allocator: Allocator,
    scene: *const Scene,
    inputs: PreparationInputs,
) !State.PreparedOpticalState {
    var context = try Context.init(allocator, scene, inputs);
    defer context.deinit(allocator);

    var absorber_state = try Absorbers.build(allocator, &context);
    defer absorber_state.deinit(allocator);

    const accumulation = try Accumulation.accumulate(allocator, &context, &absorber_state);

    var prepared = Finalize.assemble(&context, &absorber_state, accumulation);
    errdefer prepared.deinit(allocator);

    try prepared.ensureSharedRtmGeometryCache(allocator);
    return prepared;
}
