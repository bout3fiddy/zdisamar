// perturbation_sensitivity_sink.zig --------------------------------------------------------------------------|
// Disabled perturbation sink selected by normal product, test, trace, and telemetry builds.                   |
//                                                                                                             |
// called by                                                                                                   |
//   sensitivity.zig imports this module through the build.zig module alias when the perturbation-sensitivity  |
//   research executable is not being built. LABOS code never imports the scaffolding sink directly.           |
//                                                                                                             |
// mirrored sink                                                                                               |
//   scaffolding/instrumentation/perturbation/zig/perturbation_sensitivity_sink.zig owns the active sweep      |
//   plan, per-channel atomic hit counters, changed counters, filters, and replacement modes used by ablation  |
//   experiments.                                                                                              |
//                                                                                                             |
// disabled path                                                                                               |
//   available=false makes sensitivity.zig set enabled=false. The facade still exposes scalar and decision     |
//   hooks, and this stub keeps the exact low-level coordinate tuple that the real sink receives.              |
//                                                                                                             |
// hot path                                                                                                    |
//   LABOS Fourier, layer-doubling, scattering-order, and aerosol-Jacobian hooks can stay at the measured      |
//   scalar or branch decision. Disabled builds return the baseline value exactly and carry no plan lookup,    |
//   atomic counter update, filter test, replacement branch, or result mutation.                               |
//                                                                                                             |
// memory                                                                                                      |
//   No active plan, counters, atomics, or retained buffers live in this disabled variant.                     |
// ------------------------------------------------------------------------------------------------------------|
pub const available = false;

pub inline fn scalar(
    channel_id: u8,
    layer_index: i32,
    fourier_index: i32,
    order_index: i32,
    state_index: i32,
    branch: i32,
    baseline: f64,
) f64 {
    // scalar -------------------------------------------------------------------------------------------------|
    // Disabled scalar perturbation hook. Return the input value unchanged.                                    |
    //                                                                                                         |
    // call path                                                                                               |
    //   sensitivity.zig calls this only in builds that have selected an available sink. In normal builds,     |
    //   the facade returns before calling this stub, but keeping this function baseline-only preserves the    |
    //   same surface for direct import tests and module wiring.                                               |
    //                                                                                                         |
    // hot path                                                                                                |
    //   No plan lookup, counter update, filter branch, or allocation is reachable from this disabled hook.    |
    // --------------------------------------------------------------------------------------------------------|

    _ = channel_id;
    _ = layer_index;
    _ = fourier_index;
    _ = order_index;
    _ = state_index;
    _ = branch;
    return baseline;
}

pub inline fn decision(
    channel_id: u8,
    layer_index: i32,
    fourier_index: i32,
    order_index: i32,
    state_index: i32,
    branch: i32,
    baseline: bool,
) bool {
    // decision -----------------------------------------------------------------------------------------------|
    // Disabled branch perturbation hook. Return the branch decision unchanged.                                |
    //                                                                                                         |
    // call path                                                                                               |
    //   sensitivity.zig wraps LABOS q-series, orders convergence, Fourier tail, and tangent gates with this   |
    //   sink shape when an experiment build is active. The disabled variant keeps those coordinates typed     |
    //   but cannot force a branch outcome.                                                                    |
    //                                                                                                         |
    // hot path                                                                                                |
    //   No sweep state, atomics, or replacement branch is touched here.                                       |
    // --------------------------------------------------------------------------------------------------------|

    _ = channel_id;
    _ = layer_index;
    _ = fourier_index;
    _ = order_index;
    _ = state_index;
    _ = branch;
    return baseline;
}
