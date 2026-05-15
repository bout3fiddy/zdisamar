pub const STATE_COUNT: usize = 3;

// The order becomes observable once Jacobian columns cross the C/Python boundary.
// Keep new states explicit instead of sorting names alphabetically.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum State {
    SurfaceAlbedo = 0,
    AerosolOpticalDepth = 1,
    AerosolLayerMidPressureHpa = 2,
}

pub type Vector = [f64; STATE_COUNT];
pub type StateMask = u8;
pub const ALL_STATES_MASK: StateMask = (1 << STATE_COUNT) - 1;

pub mod state_names {
    pub const SURFACE_ALBEDO: &str = "surface_albedo";
    pub const AEROSOL_OPTICAL_DEPTH: &str = "aerosol_optical_depth";
    pub const AEROSOL_LAYER_MID_PRESSURE_HPA: &str = "aerosol_layer_mid_pressure_hpa";
}

pub fn zero() -> Vector {
    [0.0; STATE_COUNT]
}

pub fn state_index(state: State) -> usize {
    state as usize
}

pub fn state_mask(state: State) -> StateMask {
    1 << state_index(state)
}

pub fn includes(mask: StateMask, state: State) -> bool {
    (mask & state_mask(state)) != 0
}

pub fn sanitized_mask(mask: StateMask) -> StateMask {
    mask & ALL_STATES_MASK
}

pub fn get(vector: Vector, state: State) -> f64 {
    vector[state_index(state)]
}

pub fn set(vector: &mut Vector, state: State, value: f64) {
    vector[state_index(state)] = value;
}

pub fn add_scaled(accumulator: &mut Vector, vector: Vector, factor: f64) {
    for index in 0..STATE_COUNT {
        accumulator[index] += factor * vector[index];
    }
}

pub fn scale(mut vector: Vector, factor: f64) -> Vector {
    for value in &mut vector {
        *value *= factor;
    }
    vector
}
