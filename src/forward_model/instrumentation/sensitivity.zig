const build_options = @import("build_options");
const sink = @import("perturbation_sensitivity_sink");

// sensitivity.zig ----------------------------------------------------------------------------------------------|
// Perturbation facade for ablation sweeps. Disabled builds keep baselines and branches.                         |
//                                                                                                               |
// inserted in                                                                                                   |
//   LABOS Fourier loop: weighted rho_m and tail-stop decisions                                                  |
//   LABOS layer doubling: q-series skip and downstream R-D/T-U/T-D product gates                                |
//   LABOS scattering orders: first-order and multiple-order convergence decisions                               |
//   aerosol Jacobians: optical-depth and pressure weighting contributions                                       |
//                                                                                                               |
// enabled by                                                                                                    |
//   enable_perturbation_sensitivity plus the perturbation_sensitivity_sink research module                      |
//                                                                                                               |
// public hooks                                                                                                  |
//   scalar   passes a measured scalar to the active sweep plan                                                  |
//   decision passes a branch decision to the active sweep plan                                                  |
// --------------------------------------------------------------------------------------------------------------|
pub const requested: bool = requested_by_build: {
    if (!@hasDecl(build_options, "enable_perturbation_sensitivity")) break :requested_by_build false;
    break :requested_by_build build_options.enable_perturbation_sensitivity;
};

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

// Compact hook coordinates. Negative indices mean "not applicable".
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
