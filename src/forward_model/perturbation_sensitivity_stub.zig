// instrumentation: perturbation stub
// captures: nothing
// why: return baseline values in every non-research build.
pub const available = false;

// instrumentation: perturbation
// captures: disabled scalar channel
// why: preserve product math exactly.
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

// instrumentation: perturbation
// captures: disabled decision channel
// why: preserve product branch choices exactly.
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
