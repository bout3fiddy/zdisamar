// jacobian_states.zig --------------------------------------------------------------------------------------- |
// Fixed RTM Jacobian state vocabulary used by optics, LABOS transport, and spectrum convolution.              |
//                                                                                                             |
// route map                                                                                                   |
//   optics/   writes per-layer derivative vectors in this state order                                         |
//   transport/ propagates the same fixed vector through one solveReflectance call                             |
//   spectrum/  convolves active columns with the same instrument weights as reflectance                       |
//                                                                                                             |
// memory                                                                                                      |
//   Vector is [3]f64. StateMask is u8 and uses the low three bits. This file owns no heap storage and has no  |
//   hidden mutable state. The order follows main:`src/forward_model/jacobian/root.zig`.                       |
// ------------------------------------------------------------------------------------------------------------|

pub const state_count: usize = 3;

pub const State = enum(u8) {
    surface_albedo = 0,
    aerosol_optical_depth = 1,
    aerosol_layer_mid_pressure_hpa = 2,
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
    pub const surface_albedo = "surface_albedo";
    pub const aerosol_optical_depth = "aerosol_optical_depth";
    pub const aerosol_layer_mid_pressure_hpa = "aerosol_layer_mid_pressure_hpa";
};
// ------------------------------------------------------------------------------------------------------------|

pub fn zero() Vector {
    return .{0.0} ** state_count;
}

pub fn stateIndex(state: State) usize {
    return @intFromEnum(state);
}

pub fn stateMask(state: State) StateMask {
    return @as(StateMask, 1) << @intCast(stateIndex(state));
}

pub fn includes(mask: StateMask, state: State) bool {
    return (mask & stateMask(state)) != 0;
}

pub fn sanitizedMask(mask: StateMask) StateMask {
    return mask & all_states_mask;
}

pub fn activeStateCount(mask: StateMask) usize {
    const active_mask = sanitizedMask(mask);
    var count: usize = 0;
    for (0..state_count) |index| {
        if ((active_mask & (@as(StateMask, 1) << @intCast(index))) != 0) count += 1;
    }
    return count;
}

pub fn activeStateIndex(mask: StateMask, state: State) ?usize {
    const active_mask = sanitizedMask(mask);
    const target_index = stateIndex(state);
    var active_index: usize = 0;

    for (0..state_count) |index| {
        if ((active_mask & (@as(StateMask, 1) << @intCast(index))) == 0) continue;
        if (index == target_index) return active_index;

        active_index += 1;
    }

    return null;
}

pub fn activeStateAt(mask: StateMask, active_index: usize) ?State {
    const active_mask = sanitizedMask(mask);
    var current: usize = 0;

    for (0..state_count) |index| {
        if ((active_mask & (@as(StateMask, 1) << @intCast(index))) == 0) continue;
        if (current == active_index) return @enumFromInt(index);

        current += 1;
    }

    return null;
}

pub fn get(vector: Vector, state: State) f64 {
    return vector[stateIndex(state)];
}

pub fn set(vector: *Vector, state: State, value: f64) void {
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
