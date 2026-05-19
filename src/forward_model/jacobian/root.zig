pub const state_count: usize = 3;

pub const State = enum(u8) {
    surface_albedo = 0,
    aerosol_optical_depth = 1,
    aerosol_layer_mid_pressure_hpa = 2,
};

pub const Vector = [state_count]f64;
pub const StateMask = u8;
pub const all_states_mask: StateMask = (1 << state_count) - 1;

// layout(64-bit):
//   size: 0 B, align: 1 B
//   field storage: 0 B; padding: 0 B (0 bits)
//   footprint: no runtime field storage; namespace/type declarations only
pub const StateNames = struct {
    pub const surface_albedo = "surface_albedo";
    pub const aerosol_optical_depth = "aerosol_optical_depth";
    pub const aerosol_layer_mid_pressure_hpa = "aerosol_layer_mid_pressure_hpa";
};

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

// hot path:
//   when: integrated forward samples accumulate active Jacobian vectors
//   work: adds a scaled fixed-size derivative vector into an accumulator
//   data: jacobian vector cells, accumulator cells, scalar factor
//   follow: spectral_eval.integrateForwardAtNominal and reflectance assembly
pub fn addScaled(accumulator: *Vector, vector: Vector, factor: f64) void {
    for (0..state_count) |index| accumulator[index] += factor * vector[index];
}

// hot path:
//   when: simulation summaries compute mean Jacobian vectors
//   work: multiplies the fixed-size derivative vector by one scalar
//   data: jacobian vector cells and scalar factor
//   follow: simulate.processJacobianSamples summary return path
pub fn scale(vector: Vector, factor: f64) Vector {
    var result = vector;
    for (&result) |*value| value.* *= factor;
    return result;
}
