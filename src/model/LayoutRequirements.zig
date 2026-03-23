//! Purpose:
//!   Describe the canonical array-shape requirements implied by a prepared scene and
//!   request before workspace and cache allocation.
//!
//! Physics:
//!   This file records the dimensionality of spectral, vertical-layer, state-vector, and
//!   measurement spaces that later kernels operate on.
//!
//! Vendor:
//!   `scene/workspace layout sizing stage`
//!
//! Design:
//!   The Zig engine carries layout sizing as an explicit typed record so workspace and
//!   cache allocation can stay deterministic and decoupled from mutable global state.
//!
//! Invariants:
//!   Spectral bounds stay in nanometers, counts are non-negative, and downstream callers
//!   must treat zero counts as "not yet sized" until validated by higher layers.
//!
//! Validation:
//!   Populated by scene and plan validation paths before runtime workspace allocation.
/// Purpose:
///   Capture the dimensions required to allocate a workspace for a scene/request pair.
pub const LayoutRequirements = struct {
    spectral_start_nm: f64 = 270.0,
    spectral_end_nm: f64 = 2400.0,
    spectral_sample_count: u32 = 0,
    layer_count: u32 = 0,
    state_parameter_count: u32 = 0,
    measurement_count: u32 = 0,
};
