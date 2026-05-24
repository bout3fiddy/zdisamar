const build_options = @import("build_options");
const sink = @import("perturbation_sensitivity_sink");

// instrumentation: perturbation facade
// captures: selected expression outputs/decisions
// why: compile ablation hooks out unless the research sweep opts in.
pub const requested: bool = if (@hasDecl(build_options, "enable_perturbation_sensitivity"))
    build_options.enable_perturbation_sensitivity
else
    false;

pub const enabled: bool = requested and sink.available;

pub const Channel = enum(u8) {
    // instrumentation: perturbation
    // captures: c_m * rho_m
    // why: test late Fourier contribution pruning.
    fourier_weighted_reflectance = 0,
    // instrumentation: perturbation
    // captures: Fourier tail-stop decision
    // why: test earlier loop termination.
    fourier_tail_break = 1,
    // instrumentation: perturbation
    // captures: q-series skip decision
    // why: test whether more doubling steps can bypass Q work.
    qseries_skip = 2,
    // instrumentation: perturbation
    // captures: R-D product gate
    // why: test downstream work removal inside q-zero branches.
    qseries_rd_product = 3,
    // instrumentation: perturbation
    // captures: T-U product gate
    // why: test downstream work removal inside q-zero branches.
    qseries_tu_product = 4,
    // instrumentation: perturbation
    // captures: T-D product gate
    // why: test downstream work removal inside q-zero branches.
    qseries_td_product = 5,
    // instrumentation: perturbation
    // captures: first-order convergence decision
    // why: test single-scattering exit sensitivity.
    orders_initial_convergence = 6,
    // instrumentation: perturbation
    // captures: multiple-order convergence decision
    // why: test earlier scattering-order stop.
    orders_multiple_convergence = 7,
    // instrumentation: perturbation
    // captures: AOD tangent contribution
    // why: test OE sensitivity to late derivative terms.
    aerosol_aod_tangent = 8,
    // instrumentation: perturbation
    // captures: aerosol-pressure tangent contribution
    // why: test OE sensitivity to late derivative terms.
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

// instrumentation: perturbation
// captures: scalar replacement under active plan
// why: compare final outputs after zero/scale experiments.
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

// instrumentation: perturbation
// captures: boolean replacement under active plan
// why: compare final outputs after forced gate decisions.
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
