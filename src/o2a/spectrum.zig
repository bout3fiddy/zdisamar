const std = @import("std");
const common = @import("../kernels/transport/common.zig");
const measurement = @import("../kernels/transport/measurement.zig");
const Method = @import("method.zig").Method;
const providers = @import("providers/root.zig");

pub const Result = measurement.MeasurementSpaceProduct;
pub const ForwardProfile = measurement.ForwardProfile;

pub fn run(
    allocator: std.mem.Allocator,
    case: *const @import("case.zig").Case,
    optics: *const @import("optics.zig").Optics,
    work: ?*@import("work.zig").Work,
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

    _ = work;
    return measurement.simulateProductWithProfile(
        allocator,
        case,
        route,
        optics,
        providers.exact(),
        profile,
    );
}
