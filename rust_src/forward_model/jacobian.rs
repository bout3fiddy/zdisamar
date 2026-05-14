pub const STATE_COUNT: usize = 3;
pub type Vector = [f64; STATE_COUNT];
pub type StateMask = u8;
pub const ALL_STATES_MASK: StateMask = (1 << STATE_COUNT) - 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    SurfaceAlbedo,
    AerosolOpticalDepth,
    AerosolLayerMidPressureHpa,
}

pub mod state_names {
    pub const SURFACE_ALBEDO: &str = "surface_albedo";
    pub const AEROSOL_OPTICAL_DEPTH: &str = "aerosol_optical_depth";
    pub const AEROSOL_LAYER_MID_PRESSURE_HPA: &str = "aerosol_layer_mid_pressure_hpa";
}

pub fn zero() -> Vector {
    [0.0; STATE_COUNT]
}

pub fn state_index(state: State) -> usize {
    match state {
        State::SurfaceAlbedo => 0,
        State::AerosolOpticalDepth => 1,
        State::AerosolLayerMidPressureHpa => 2,
    }
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
    for (slot, value) in accumulator.iter_mut().zip(vector) {
        *slot += factor * value;
    }
}

pub fn scale(mut vector: Vector, factor: f64) -> Vector {
    for value in &mut vector {
        *value *= factor;
    }
    vector
}
