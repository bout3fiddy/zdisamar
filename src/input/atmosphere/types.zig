// types.zig --------------------------------------------------------------------------------------------------|
// Shared atmosphere enum vocabulary for interval grids, aerosol placement, and fraction controls.             |
//                                                                                                             |
// called by                                                                                                   |
//   Atmosphere.zig re-exports these names as part of the public input model                                   |
//   atmosphere/interval_grid.zig uses interval and particle-placement semantics for vertical contracts        |
//   atmosphere/fraction_control.zig uses fraction target/kind for wavelength-dependent aerosol fractions      |
//   prepared optical state stores the chosen interval semantics for RTM layer construction                    |
//                                                                                                             |
// enum roles                                                                                                  |
//   IntervalSemantics          says how atmosphere layers map to pressure/altitude intervals                  |
//   ParticlePlacementSemantics says how aerosol placement should be interpreted                               |
//   FractionTarget             says which physical quantity receives a fractional split                       |
//   FractionKind               says whether that fraction is constant or wavelength dependent                 |
//                                                                                                             |
// memory                                                                                                      |
//   These are tag-only public enums. This file owns no buffers and has no runtime state.                      |
// ------------------------------------------------------------------------------------------------------------|

pub const IntervalSemantics = enum {
    none,
    altitude_layering_approximation,
    explicit_pressure_bounds,
};

pub const ParticlePlacementSemantics = enum {
    none,
    altitude_center_width_approximation,
    explicit_interval_bounds,
};

pub const FractionTarget = enum {
    none,
    aerosol,
};

pub const FractionKind = enum {
    none,
    wavel_independent,
    wavel_dependent,
};
