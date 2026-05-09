pub const state_count: usize = 3;

pub const State = enum(u8) {
    surface_albedo = 0,
    aerosol_optical_depth = 1,
    aerosol_layer_mid_pressure_hpa = 2,
};

pub const Vector = [state_count]f64;
pub const StateMask = u8;
pub const all_states_mask: StateMask = (1 << state_count) - 1;

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

pub fn get(vector: Vector, state: State) f64 {
    return vector[stateIndex(state)];
}

pub fn set(vector: *Vector, state: State, value: f64) void {
    vector[stateIndex(state)] = value;
}

pub fn addScaled(accumulator: *Vector, vector: Vector, factor: f64) void {
    for (0..state_count) |index| accumulator[index] += factor * vector[index];
}

pub fn scale(vector: Vector, factor: f64) Vector {
    var result = vector;
    for (&result) |*value| value.* *= factor;
    return result;
}
