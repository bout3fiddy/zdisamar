const measurement = @import("../instrument_grid/grid_calculation/types.zig");
const instrument = @import("instrument.zig");

pub const Bindings = measurement.Implementations;

pub fn exact() Bindings {
    return .{
        .instrument = instrument.resolve("builtin.generic_response").?,
    };
}
