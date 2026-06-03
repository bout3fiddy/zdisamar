const measurement = @import("../instrument_grid/grid_calculation/types.zig");
const instrument_implementation = @import("instrument/implementation.zig");

pub const Bindings = measurement.Implementations;

pub fn exact() Bindings {
    return .{
        .instrument = instrument_implementation.resolve("builtin.generic_response").?,
    };
}
