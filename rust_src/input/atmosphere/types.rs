#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum IntervalSemantics {
    #[default]
    None,
    AltitudeLayeringApproximation,
    ExplicitPressureBounds,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum ParticlePlacementSemantics {
    #[default]
    None,
    AltitudeCenterWidthApproximation,
    ExplicitIntervalBounds,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum FractionTarget {
    #[default]
    None,
    Cloud,
    Aerosol,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum FractionKind {
    #[default]
    None,
    WavelIndependent,
    WavelDependent,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum PartitionLabel {
    #[default]
    Unspecified,
    BoundaryLayer,
    FreeTroposphere,
    FitInterval,
    Stratosphere,
}
