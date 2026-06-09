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
    _ = channel_id;
    _ = layer_index;
    _ = fourier_index;
    _ = order_index;
    _ = state_index;
    _ = branch;
    return baseline;
}
