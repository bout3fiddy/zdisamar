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
pub const BorrowedProfilePreparation = Context.BorrowedProfilePreparation;

// hot path:
//   when: once per prepared scene/session before repeated forward solves
//   work: builds absorbers, accumulated layers, finalized optical state, and shared RTM geometry
//   data: scene/reference inputs, absorber state, layer accumulation buffers, prepared optical state
//   follow: absorbers.build, accumulation.populate, finalize.buildPreparedOpticalState, shared geometry
pub fn prepare(
    allocator: Allocator,
    scene: *const Scene,
    inputs: PreparationInputs,
) !State.PreparedOpticalState {
    var context = context: {
        const zone = Trace.staticZone(@src(), "optical_prepare.context_init");
        defer zone.end();
        break :context try Context.init(allocator, scene, inputs);
    };
    defer context.deinit(allocator);

    var absorber_state = absorber_state: {
        const zone = Trace.staticZone(@src(), "optical_prepare.absorbers_build");
        defer zone.end();
        break :absorber_state try Absorbers.build(allocator, &context);
    };
    defer absorber_state.deinit(allocator);

    const accumulation = accumulation: {
        const zone = Trace.staticZone(@src(), "optical_prepare.accumulation");
        defer zone.end();
        break :accumulation try Accumulation.accumulate(allocator, &context, &absorber_state);
    };

    var prepared = prepared: {
        const zone = Trace.staticZone(@src(), "optical_prepare.finalize");
        defer zone.end();
        break :prepared Finalize.assemble(&context, &absorber_state, accumulation);
    };
    errdefer prepared.deinit(allocator);

    {
        const zone = Trace.staticZone(@src(), "optical_prepare.shared_geometry");
        defer zone.end();
        try prepared.ensureSharedRtmGeometryCache(allocator);
    }
    return prepared;
}
