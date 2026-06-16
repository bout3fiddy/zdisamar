// jacobian_states.zig --------------------------------------------------------------------------------------- |
// Fixed RTM Jacobian state vocabulary used by optics, LABOS RTM, and spectrum convolution.                    |
//                                                                                                             |
// route map                                                                                                   |
//   optics/   writes per-layer derivative vectors in this state order                                         |
//   rtm/      propagates the same fixed vector through one solveReflectance call                              |
//   spectrum/  convolves active columns with the same instrument weights as reflectance                       |
//                                                                                                             |
// memory                                                                                                      |
//   Vector is [2]f64. This file owns no heap storage and has no                                               |
//   hidden mutable state. Surface albedo remains a forward scalar; it is intentionally not a retrieval lane.  |
// ------------------------------------------------------------------------------------------------------------|

pub const state_count: usize = 2;

pub const State = enum(u8) {
    aerosol_optical_depth = 0,
    aerosol_layer_mid_pressure_hpa = 1,
};

pub const Vector = [state_count]f64;

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

pub fn addScaled(accumulator: *Vector, vector: Vector, factor: f64) void {
    // addScaled ----------------------------------------------------------------------------------------------|
    // Add both derivative lanes into a fixed-size accumulator.                                                |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Spectrum assembly and LABOS propagation use this for the fixed Jacobian columns.                      |
    //                                                                                                         |
    // math                                                                                                    |
    //   accumulator_i += factor * vector_i                                                                    |
    // --------------------------------------------------------------------------------------------------------|
    for (0..state_count) |index| {
        accumulator[index] += factor * vector[index];
    }
}

pub fn scale(vector: Vector, factor: f64) Vector {
    // scale ------------------------------------------------------------------------------------------------- |
    // Multiply every fixed derivative lane by one scalar.                                                     |
    //                                                                                                         |
    //   fixed-vector scale over the retained two O2 A retrieval lanes.                                        |
    //                                                                                                         |
    // math                                                                                                    |
    //   result_i = factor * vector_i                                                                          |
    // --------------------------------------------------------------------------------------------------------|
    var result = vector;
    for (&result) |*value| value.* *= factor;
    return result;
}
