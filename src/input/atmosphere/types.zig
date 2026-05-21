const std = @import("std");

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
