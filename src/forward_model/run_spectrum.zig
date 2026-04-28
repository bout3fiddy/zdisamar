const std = @import("std");
const common = @import("radiative_transfer/root.zig");
const measurement = @import("instrument_grid/root.zig");
const Method = @import("method.zig").Method;
const implementations = @import("implementations/root.zig");
const Scene = @import("../input/Scene.zig").Scene;
const SummaryStorage = @import("instrument_grid/grid_calculation/storage.zig").SummaryStorage;
const PreparedOpticalState = @import("optical_properties/root.zig").PreparedOpticalState;

pub const Result = measurement.InstrumentGridProduct;

pub fn run(
    allocator: std.mem.Allocator,
    case: *const Scene,
    optics: *const PreparedOpticalState,
    work: ?*SummaryStorage,
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

    if (work) |storage| {
        const view = try measurement.simulateProductWithWorkspace(
            allocator,
            storage,
            case,
            route,
            optics,
            implementations.exact(),
        );
        return view.toOwned(allocator);
    }

    return measurement.simulateProduct(
        allocator,
        case,
        route,
        optics,
        implementations.exact(),
    );
}
