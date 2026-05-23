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
//   when: active derivative routes integrate high-resolution forward samples
//   work: adds only requested derivative lanes into a fixed-size accumulator
//   data: route state mask, jacobian vector cells, accumulator cells, scalar factor
//   math: accumulator_i <- accumulator_i + factor * vector_i for active state lanes i
//   follow: spectral_eval.integratePrefetchedForwardAtNominal and active-state product buffers
pub fn addScaledMasked(accumulator: *Vector, vector: Vector, factor: f64, mask: StateMask) void {
    const active_mask = sanitizedMask(mask);
    for (0..state_count) |index| {
        if ((active_mask & (@as(StateMask, 1) << @intCast(index))) == 0) continue;
        accumulator[index] += factor * vector[index];
    }
}

// hot path:
//   when: simulation summaries compute mean Jacobian vectors
//   work: multiplies the fixed-size derivative vector by one scalar
//   data: jacobian vector cells and scalar factor
//   math: result_i = factor * vector_i
//   follow: simulate.processJacobianSamples summary return path
pub fn scale(vector: Vector, factor: f64) Vector {
    var result = vector;
    for (&result) |*value| value.* *= factor;
    return result;
}

// hot path:
//   when: spectral forward samples convert active reflectance derivatives to radiance derivatives
//   work: scales requested lanes and leaves inactive lanes zero for downstream active-column writers
//   data: route state mask, jacobian vector cells, scalar factor
//   math: result_i = factor * vector_i for active lanes, otherwise 0
//   follow: spectral_forward.integratedSampleFromForward
pub fn scaleMasked(vector: Vector, factor: f64, mask: StateMask) Vector {
    const active_mask = sanitizedMask(mask);
    var result = zero();
    for (0..state_count) |index| {
        if ((active_mask & (@as(StateMask, 1) << @intCast(index))) == 0) continue;
        result[index] = vector[index] * factor;
    }
    return result;
}
