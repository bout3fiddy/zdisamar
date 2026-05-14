#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum IntervalSemantics {
    #[default]
    None,
    AltitudeLayeringApproximation,
    ExplicitPressureBounds,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum ParticlePlacementSemantics {
    #[default]
    None,
    AltitudeCenterWidthApproximation,
    ExplicitIntervalBounds,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum FractionTarget {
    #[default]
    None,
    Cloud,
    Aerosol,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum FractionKind {
    #[default]
    None,
    WavelIndependent,
    WavelDependent,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum PartitionLabel {
    #[default]
    Unspecified,
    BoundaryLayer,
    FreeTroposphere,
    FitInterval,
    Stratosphere,
}
