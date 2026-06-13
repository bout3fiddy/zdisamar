const build_options = @import("build_options");
const sink = @import("perturbation_sensitivity_sink");

// sensitivity.zig ----------------------------------------------------------------------------------------------|
// Perturbation-sensitivity facade for ablation sweeps around selected LABOS decisions.                          |
//                                                                                                               |
// called from                                                                                                   |
//   rtm/reflectance.zig wraps Fourier contribution and Fourier tail-stop decisions.                             |
//   rtm/solve.zig wraps integrated and non-integrated aerosol tangent contributions.                            |
//   rtm/layer_reflect_transmit.zig wraps q-series skip plus downstream R-D, T-U, and T-D product gates.         |
//   rtm/scattering_orders.zig wraps initial and multiple-scattering convergence decisions.                      |
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
//                                                                                                               |
// hot path                                                                                                      |
//   Transport calls scalar/decision inside Fourier, layer-doubling, aerosol-Jacobian, and scattering-order      |
//   loops. The channel is comptime, so disabled builds return the baseline before any sink call. Enabled runs   |
//   pass one compact Coord by value plus the baseline scalar or branch decision to the external sweep sink.     |
//                                                                                                               |
// memory                                                                                                        |
//   Channel is the stable u8 hook id written to the sink. Coord is a five-field i32 row so each hook can name   |
//   only the local indices it has; -1 marks unused coordinates and avoids separate optional fields in the hot   |
//   instrumentation call. This facade owns no buffers and retains no sweep state.                               |
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

// Coord --------------------------------------------------------------------------------------------------------|
// Compact hook coordinates passed from LABOS hot decisions to the perturbation sink.                            |
//                                                                                                               |
// layout(64-bit)                                                                                                |
// size: 20 B (0.020 KiB), align: 4 B                                                                            |
//                                                                                                               |
// memory                                                                                                        |
// [ 0.. 3] layer_index   : i32                                                                                  |
// [ 4.. 7] fourier_index : i32                                                                                  |
// [ 8..11] order_index   : i32                                                                                  |
// [12..15] state_index   : i32                                                                                  |
// [16..19] branch        : i32                                                                                  |
//                                                                                                               |
// encoding                                                                                                      |
//   -1 means the coordinate does not apply at this hook. Callers fill only the axes that identify the local     |
//   perturbation decision being tested.                                                                         |
//                                                                                                               |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                        |
// footprint: per instance = 20 B (0.020 KiB); passed by value to one scalar/decision hook                       |
pub const Coord = struct {
    layer_index: i32 = -1,
    fourier_index: i32 = -1,
    order_index: i32 = -1,
    state_index: i32 = -1,
    branch: i32 = -1,
};
// --------------------------------------------------------------------------------------------------------------|

pub inline fn scalar(comptime channel: Channel, coord: Coord, baseline: f64) f64 {
    // scalar ---------------------------------------------------------------------------------------------------|
    // Return the baseline value unless the perturbation sweep sink is compiled in and active.                   |
    //                                                                                                           |
    // hot path                                                                                                  |
    //   channel is comptime, and disabled builds return before touching the sink. Enabled builds pass Coord     |
    //   fields as plain integers to keep the sink ABI narrow and allocation-free.                               |
    // ----------------------------------------------------------------------------------------------------------|

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
    // decision -------------------------------------------------------------------------------------------------|
    // Return the baseline branch unless an active perturbation sweep overrides this hook.                       |
    //                                                                                                           |
    // hot path                                                                                                  |
    //   Used around LABOS threshold and convergence decisions. The normal product/test build compiles this to   |
    //   the baseline branch so perturbation scaffolding does not enter transport math.                          |
    // ----------------------------------------------------------------------------------------------------------|

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
