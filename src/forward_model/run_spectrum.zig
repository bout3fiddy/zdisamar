const std = @import("std");
const common = @import("radiative_transfer/root.zig");
const measurement = @import("instrument_grid/root.zig");
const Method = @import("method.zig").Method;
const providers = @import("builtins/root.zig");
const Scene = @import("../input/Scene.zig").Scene;
const SummaryWorkspace = @import("instrument_grid/grid_calculation/workspace.zig").SummaryWorkspace;
const PreparedOpticalState = @import("optical_properties/root.zig").PreparedOpticalState;

pub const Result = measurement.MeasurementSpaceProduct;

pub fn run(
    allocator: std.mem.Allocator,
    case: *const Scene,
    optics: *const PreparedOpticalState,
    work: ?*SummaryWorkspace,
    method: Method,
    rtm_controls: common.RadiativeTransferControls,
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
        );
        return view.toOwned(allocator);
    }

    return measurement.simulateProduct(
        allocator,
        case,
        route,
        optics,
        providers.exact(),
    );
}
