#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct SpectroscopyLine {
    pub gas_index: u8,
    pub isotope_number: u8,
    pub center_wavelength_nm: f64,
    pub line_strength_cm2_per_molecule: f64,
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct SpectroscopyLineList {
    pub lines: Vec<SpectroscopyLine>,
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct CrossSectionPoint {
    pub wavelength_nm: f64,
    pub sigma_cm2_per_molecule: f64,
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct CrossSectionTable {
    pub points: Vec<CrossSectionPoint>,
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct CollisionInducedAbsorptionPoint {
    pub wavelength_nm: f64,
    pub a0: f64,
    pub a1: f64,
    pub a2: f64,
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct CollisionInducedAbsorptionTable {
    pub points: Vec<CollisionInducedAbsorptionPoint>,
    pub scale_factor_cm5_per_molecule2: f64,
}
