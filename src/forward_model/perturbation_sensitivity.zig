const build_options = @import("build_options");
const sink = @import("perturbation_sensitivity_sink");

pub const requested: bool = if (@hasDecl(build_options, "enable_perturbation_sensitivity"))
    build_options.enable_perturbation_sensitivity
else
    false;

pub const enabled: bool = requested and sink.available;

pub const Channel = enum(u8) {
    fourier_weighted_reflectance = 0,
    fourier_tail_break = 1,
    qseries_skip = 2,
    qseries_rd_product = 3,
    qseries_tu_product = 4,
    qseries_td_product = 5,
    orders_initial_convergence = 6,
    orders_multiple_convergence = 7,
    aerosol_aod_tangent = 8,
    aerosol_pressure_tangent = 9,
};

// Compact coordinate payload for sensitivity hooks. The research sink interprets
// negative indices as "not applicable" so product code never formats labels.
pub const Coord = struct {
    layer_index: i32 = -1,
    fourier_index: i32 = -1,
    order_index: i32 = -1,
    state_index: i32 = -1,
    branch: i32 = -1,
};

pub inline fn scalar(comptime channel: Channel, coord: Coord, baseline: f64) f64 {
    if (comptime !enabled) return baseline;
    return sink.scalar(
        @intFromEnum(channel),
        coord.layer_index,
        coord.fourier_index,
        coord.order_index,
        coord.state_index,
        coord.branch,
        baseline,
    );
}

pub inline fn decision(comptime channel: Channel, coord: Coord, baseline: bool) bool {
    if (comptime !enabled) return baseline;
    return sink.decision(
        @intFromEnum(channel),
        coord.layer_index,
        coord.fourier_index,
        coord.order_index,
        coord.state_index,
        coord.branch,
        baseline,
    );
}
