const measurement = @import("../instrument_grid/grid_calculation/types.zig");
const instrument = @import("instrument.zig");
const surface = @import("surface.zig");
const transport = @import("transport.zig");

pub const Bindings = measurement.Implementations;

pub fn exact() Bindings {
    return .{
        .transport = transport.resolve("builtin.dispatcher").?,
        .surface = surface.resolve("builtin.lambertian_surface").?,
        .instrument = instrument.resolve("builtin.generic_response").?,
    };
}
