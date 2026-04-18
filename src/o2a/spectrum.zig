const std = @import("std");
const common = @import("../kernels/transport/common.zig");
const measurement = @import("../kernels/transport/measurement.zig");
const Method = @import("method.zig").Method;
const providers = @import("providers/root.zig");
const Scene = @import("../model/Scene.zig").Scene;
const SummaryWorkspace = @import("../kernels/transport/measurement/workspace.zig").SummaryWorkspace;
const PreparedOpticalState = @import("../kernels/optics/preparation.zig").PreparedOpticalState;

pub const Result = measurement.MeasurementSpaceProduct;
pub const ForwardProfile = measurement.ForwardProfile;

pub fn run(
    allocator: std.mem.Allocator,
    case: *const Scene,
    optics: *const PreparedOpticalState,
    work: ?*SummaryWorkspace,
    method: Method,
    rtm_controls: common.RtmControls,
    profile: ?*ForwardProfile,
) !Result {
    switch (method) {
        .exact => {},
    }

    const route = try common.prepareRoute(.{
        .regime = case.observation_model.regime,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = rtm_controls,
    });

    if (work) |workspace| {
        const view = try measurement.simulateProductWithWorkspace(
            allocator,
            workspace,
            case,
            route,
            optics,
            providers.exact(),
            profile,
        );
        return view.toOwned(allocator);
    }

    return measurement.simulateProductWithProfile(
        allocator,
        case,
        route,
        optics,
        providers.exact(),
        profile,
    );
}
