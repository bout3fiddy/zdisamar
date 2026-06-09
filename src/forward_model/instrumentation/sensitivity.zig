const build_options = @import("build_options");
const sink = @import("perturbation_sensitivity_sink");

// sensitivity.zig ----------------------------------------------------------------------------------------------|
// Perturbation-sensitivity facade for ablation sweeps around selected LABOS decisions.                          |
//                                                                                                               |
// called from                                                                                                   |
//   LABOS execute wraps Fourier contribution, Fourier tail-stop, and aerosol tangent contributions.             |
//   LABOS layers wraps q-series skip plus downstream R-D, T-U, and T-D product gates.                           |
//   LABOS orders wraps initial and multiple-scattering convergence decisions.                                   |
//   The active sweep implementation lives in scaffolding/instrumentation/perturbation; normal builds import     |
//   the disabled sink stub.                                                                                     |
//                                                                                                               |
// main paths                                                                                                    |
//   requested reads build_options.enable_perturbation_sensitivity. enabled also requires the selected sink to   |
//   report available=true.                                                                                      |
//   Channel stores stable numeric hook ids used by the sweep sink. Coord stores the local hook coordinates;     |
//   -1 means the coordinate does not apply at that hook.                                                        |
//   scalar returns the baseline f64 unless an enabled sweep replaces it. decision returns the baseline branch   |
//   unless an enabled sweep replaces it.                                                                        |
//                                                                                                               |
// runtime shape                                                                                                 |
//   Disabled builds preserve physics and branch behavior exactly. Enabled perturbation runs are deliberately    |
//   allowed to change scalar values or branch decisions for ablation evidence, but the sink stays outside this  |
//   production-facing facade.                                                                                   |
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
