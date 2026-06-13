// jacobian_states.zig --------------------------------------------------------------------------------------- |
// Fixed RTM Jacobian state vocabulary used by optics, LABOS RTM, and spectrum convolution.                    |
//                                                                                                             |
// route map                                                                                                   |
//   optics/   writes per-layer derivative vectors in this state order                                         |
//   rtm/      propagates the same fixed vector through one solveReflectance call                              |
//   spectrum/  convolves active columns with the same instrument weights as reflectance                       |
//                                                                                                             |
// memory                                                                                                      |
//   Vector is [2]f64. StateMask is u8 and uses the low two bits. This file owns no heap storage and has no    |
//   hidden mutable state. Surface albedo remains a forward scalar; it is intentionally not a retrieval lane.  |
// ------------------------------------------------------------------------------------------------------------|

pub const state_count: usize = 2;

pub const State = enum(u8) {
    aerosol_optical_depth = 0,
    aerosol_layer_mid_pressure_hpa = 1,
};

pub const Vector = [state_count]f64;
pub const StateMask = u8;
pub const all_states_mask: StateMask = (1 << state_count) - 1;

// StateNames -------------------------------------------------------------------------------------------------|
// Namespace for public Jacobian state labels.                                                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields                                                                                          |
pub const StateNames = struct {
    pub const aerosol_optical_depth = "aerosol_optical_depth";
    pub const aerosol_layer_mid_pressure_hpa = "aerosol_layer_mid_pressure_hpa";
};
// ------------------------------------------------------------------------------------------------------------|

pub fn zero() Vector {
    // zero -------------------------------------------------------------------------------------------------- |
    // Return the all-zero fixed Jacobian vector.                                                              |
    // --------------------------------------------------------------------------------------------------------|
    return .{0.0} ** state_count;
}

pub fn stateIndex(state: State) usize {
    // stateIndex -------------------------------------------------------------------------------------------- |
    // Map the fixed state enum to its vector lane.                                                            |
    // --------------------------------------------------------------------------------------------------------|
    return @intFromEnum(state);
}

pub fn stateMask(state: State) StateMask {
    // stateMask --------------------------------------------------------------------------------------------- |
    // Build the single-bit mask for one fixed Jacobian state.                                                 |
    // --------------------------------------------------------------------------------------------------------|
    return @as(StateMask, 1) << @intCast(stateIndex(state));
}

pub fn includes(mask: StateMask, state: State) bool {
    // includes ---------------------------------------------------------------------------------------------- |
    // Test whether a state bit is set after the caller chooses an active Jacobian mask.                       |
    // --------------------------------------------------------------------------------------------------------|
    return (mask & stateMask(state)) != 0;
}

pub fn sanitizedMask(mask: StateMask) StateMask {
    // sanitizedMask ----------------------------------------------------------------------------------------- |
    // Keep only the low bits owned by the fixed two-state Jacobian vector.                                    |
    // --------------------------------------------------------------------------------------------------------|
    return mask & all_states_mask;
}

pub fn activeStateCount(mask: StateMask) usize {
    // activeStateCount -------------------------------------------------------------------------------------- |
    // Count requested Jacobian columns after dropping unknown future mask bits.                               |
    // --------------------------------------------------------------------------------------------------------|
    const active_mask = sanitizedMask(mask);
    var count: usize = 0;
    for (0..state_count) |index| {
        if ((active_mask & (@as(StateMask, 1) << @intCast(index))) != 0) count += 1;
    }
    return count;
}

pub fn get(vector: Vector, state: State) f64 {
    // get --------------------------------------------------------------------------------------------------- |
    // Read one derivative lane by fixed state.                                                                |
    // --------------------------------------------------------------------------------------------------------|
    return vector[stateIndex(state)];
}

pub fn set(vector: *Vector, state: State, value: f64) void {
    // set --------------------------------------------------------------------------------------------------- |
    // Write one derivative lane by fixed state.                                                               |
    // --------------------------------------------------------------------------------------------------------|
    vector[stateIndex(state)] = value;
}

pub fn addScaledMasked(accumulator: *Vector, vector: Vector, factor: f64, mask: StateMask) void {
    // addScaledMasked ----------------------------------------------------------------------------------------|
    // Add requested derivative lanes into a fixed-size accumulator.                                           |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Spectrum assembly and LABOS propagation use this for active Jacobian columns.                         |
    //                                                                                                         |
    // math                                                                                                    |
    //   accumulator_i += factor * vector_i for active lanes i                                                 |
    // --------------------------------------------------------------------------------------------------------|
    const active_mask = sanitizedMask(mask);
    for (0..state_count) |index| {
        if ((active_mask & (@as(StateMask, 1) << @intCast(index))) == 0) continue;
        accumulator[index] += factor * vector[index];
    }
}

pub fn scale(vector: Vector, factor: f64) Vector {
    // scale ------------------------------------------------------------------------------------------------- |
    // Multiply every fixed derivative lane by one scalar.                                                     |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports main:`src/forward_model/jacobian/root.zig` `scale`; spectrum summaries keep the same unmasked   |
    //   fixed-vector scale over the retained two O2 A retrieval lanes.                                        |
    //                                                                                                         |
    // math                                                                                                    |
    //   result_i = factor * vector_i                                                                          |
    // --------------------------------------------------------------------------------------------------------|
    var result = vector;
    for (&result) |*value| value.* *= factor;
    return result;
}

pub fn scaleMasked(vector: Vector, factor: f64, mask: StateMask) Vector {
    // scaleMasked ------------------------------------------------------------------------------------------- |
    // Scale requested derivative lanes and leave inactive lanes zero.                                         |
    // --------------------------------------------------------------------------------------------------------|
    const active_mask = sanitizedMask(mask);
    var result = zero();
    for (0..state_count) |index| {
        if ((active_mask & (@as(StateMask, 1) << @intCast(index))) == 0) continue;
        result[index] = vector[index] * factor;
    }
    return result;
}
