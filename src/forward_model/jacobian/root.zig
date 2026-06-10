// root.zig ---------------------------------------------------------------------------------------------------|
// Fixed RTM Jacobian state vocabulary and tiny vector helpers.                                                |
//                                                                                                             |
// called by                                                                                                   |
//   radiative_transfer/root.zig re-exports this namespace as RadiativeTransfer.Jacobian                       |
//   LABOS execute/layer/attenuation code reads per-layer derivative lanes by state                            |
//   instrument-grid storage, simulation, and product cloning pack active state-major columns                  |
//   optimal_estimation/retrieval.zig maps native RTM columns into OE state-vector columns                     |
//   src/api/c.zig validates external state ids against this enum and mask shape                               |
//                                                                                                             |
// state order                                                                                                 |
//   surface_albedo                    : direct surface term                                                   |
//   aerosol_optical_depth             : aerosol extinction/scattering amount                                  |
//   aerosol_layer_mid_pressure_hpa    : pressure placement of the aerosol layer                               |
//                                                                                                             |
// mask shape                                                                                                  |
//   StateMask uses the low state_count bits. sanitizedMask drops unknown future bits so callers can pass      |
//   masks through public boundaries without indexing outside Vector. activeState* helpers translate between   |
//   sparse masks and compact active-column indexes used by workspace Jacobian buffers.                        |
//                                                                                                             |
// hot path                                                                                                    |
//   The helpers are deliberately branch-light over three fixed lanes. They sit in sample loops, LABOS         |
//   Jacobian packing, and OE residual projection, so they avoid allocation, dynamic lookup, and string names. |
//                                                                                                             |
// memory                                                                                                      |
//   Vector is [3]f64: 24 B per value. StateMask is u8. This module owns no heap storage and no retained       |
//   mutable state; public names live in StateNames for API/report labels only.                                |
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

// StateNames ------------------------------------------------------------------------------------------------ |
// Namespace for public Jacobian state labels.                                                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B, align: 1 B                                                                                       |
//                                                                                                             |
// memory                                                                                                      |
// no runtime field storage                                                                                    |
//                                                                                                             |
// footprint: namespace/type declarations only                                                                 |
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
    // addScaledMasked --------------------------------------------------------------------------------------- |
    // Adds requested derivative lanes into a fixed-size accumulator.                                          |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Active derivative routes integrate high-resolution forward samples through this masked vector add.    |
    //                                                                                                         |
    // math                                                                                                    |
    //   accumulator_i += factor * vector_i for active lanes i                                                 |
    // ------------------------------------------------------------------------------------------------------- |

    const active_mask = sanitizedMask(mask);
    for (0..state_count) |index| {
        if ((active_mask & (@as(StateMask, 1) << @intCast(index))) == 0) continue;
        accumulator[index] += factor * vector[index];
    }
}

pub fn scale(vector: Vector, factor: f64) Vector {
    // scale ------------------------------------------------------------------------------------------------- |
    // Multiplies the fixed-size derivative vector by one scalar.                                              |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Simulation summaries use this for mean Jacobian vectors.                                              |
    //                                                                                                         |
    // math                                                                                                    |
    //   result_i = factor * vector_i                                                                          |
    // ------------------------------------------------------------------------------------------------------- |

    var result = vector;
    for (&result) |*value| value.* *= factor;
    return result;
}

pub fn scaleMasked(vector: Vector, factor: f64, mask: StateMask) Vector {
    // scaleMasked ------------------------------------------------------------------------------------------  |
    // Scales requested derivative lanes and leaves inactive lanes zero.                                       |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Spectral forward samples use this when converting active reflectance derivatives to radiance lanes.   |
    //                                                                                                         |
    // math                                                                                                    |
    //   result_i = factor * vector_i for active lanes, otherwise 0                                            |
    // ------------------------------------------------------------------------------------------------------- |

    const active_mask = sanitizedMask(mask);
    var result = zero();
    for (0..state_count) |index| {
        if ((active_mask & (@as(StateMask, 1) << @intCast(index))) == 0) continue;
        result[index] = vector[index] * factor;
    }
    return result;
}
