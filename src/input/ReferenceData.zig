// Typed reference-data root.

const climatology = @import("reference/climatology.zig");
const cross_section_types = @import("reference/cross_sections.zig");
const cia = @import("reference/cia.zig");
const airmass_phase = @import("reference/airmass_phase.zig");
const rayleigh = @import("reference/rayleigh.zig");
const demo_builders = @import("reference/demo_builders.zig");
pub const spectroscopy = @import("reference/spectroscopy/root.zig");

pub const ClimatologyPoint = climatology.ClimatologyPoint;
pub const ClimatologyProfile = climatology.ClimatologyProfile;
pub const CrossSectionPoint = cross_section_types.CrossSectionPoint;
pub const CrossSectionTable = cross_section_types.CrossSectionTable;
pub const CollisionInducedAbsorptionPoint = cia.CollisionInducedAbsorptionPoint;
pub const CollisionInducedAbsorptionTable = cia.CollisionInducedAbsorptionTable;
pub const Rayleigh = rayleigh;

pub const SpectroscopyLine = spectroscopy.SpectroscopyLine;
pub const SpectroscopyStrongLine = spectroscopy.SpectroscopyStrongLine;
pub const SpectroscopyStrongLineSet = spectroscopy.SpectroscopyStrongLineSet;
pub const RelaxationMatrix = spectroscopy.RelaxationMatrix;
pub const SpectroscopyEvaluation = spectroscopy.SpectroscopyEvaluation;
pub const SpectroscopyRuntimeControls = spectroscopy.SpectroscopyRuntimeControls;
pub const StrongLinePreparedState = spectroscopy.StrongLinePreparedState;
pub const SpectroscopyLineList = spectroscopy.SpectroscopyLineList;

pub const AirmassFactorPoint = airmass_phase.AirmassFactorPoint;
pub const MiePhasePoint = airmass_phase.MiePhasePoint;
pub const MiePhaseTable = airmass_phase.MiePhaseTable;
pub const AirmassFactorLut = airmass_phase.AirmassFactorLut;

pub const buildDemoClimatology = demo_builders.buildDemoClimatology;
pub const buildDemoCrossSections = demo_builders.buildDemoCrossSections;
pub const buildDemoAirmassFactorLut = demo_builders.buildDemoAirmassFactorLut;
pub const buildDemoSpectroscopyLines = spectroscopy.buildDemoSpectroscopyLines;
