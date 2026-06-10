const climatology = @import("reference/climatology.zig");
const cross_section_types = @import("reference/cross_sections.zig");
const cia = @import("reference/cia.zig");
const airmass_phase = @import("reference/airmass_phase.zig");
const rayleigh = @import("reference/rayleigh.zig");
const spectroscopy_types = @import("reference/spectroscopy/types.zig");
const spectroscopy_line_list = @import("reference/spectroscopy/line_list.zig");

// ReferenceData.zig -----------------------------------------------------------------------------------------|
// Public typed-reference-data facade for loaders, input bindings, preparation, diagnostics, and tests.       |
//                                                                                                            |
// called by                                                                                                  |
//   input/reference_data loaders return the concrete owner rows re-exported here after manifest conversion.  |
//   input/Absorber.zig stores resolved line-list, cross-section, and CIA payloads on scene absorbers.        |
//   optical_properties/state_build consumes profile, LUT, cross-section, CIA, Rayleigh, and spectroscopy     |
//   rows while preparing per-wavelength optical state.                                                       |
//   output/o2_line_contributions.zig and tests import these names as the stable public row vocabulary.       |
//                                                                                                            |
// export map                                                                                                 |
//   climatology.zig      -> ClimatologyPoint/Profile and pressure-grid helpers                               |
//   cross_sections.zig   -> continuum/cross-section point tables                                             |
//   cia.zig              -> O2-O2 collision-induced absorption polynomial tables                             |
//   airmass_phase.zig    -> airmass-factor LUT rows                                                          |
//   rayleigh.zig         -> Rayleigh scalar helper namespace                                                 |
//   spectroscopy/types   -> line, sidecar, relaxation, runtime-control, and prepared-state structs           |
//   spectroscopy/line_list.zig -> SpectroscopyLineList owner and evaluation entrypoint                       |
//                                                                                                            |
// boundary and ownership                                                                                     |
//   This file is the public facade for the imported reference modules. Owner/deinit behavior and math        |
//   routines live there; callers use these re-exported names as the stable row vocabulary.                   |
//                                                                                                            |
// -----------------------------------------------------------------------------------------------------------|

pub const ClimatologyPoint = climatology.ClimatologyPoint;
pub const ClimatologyProfile = climatology.ClimatologyProfile;
pub const CrossSectionPoint = cross_section_types.CrossSectionPoint;
pub const CrossSectionTable = cross_section_types.CrossSectionTable;
pub const CollisionInducedAbsorptionPoint = cia.CollisionInducedAbsorptionPoint;
pub const CollisionInducedAbsorptionTable = cia.CollisionInducedAbsorptionTable;
pub const Rayleigh = rayleigh;

pub const max_strong_line_sidecars = spectroscopy_types.max_strong_line_sidecars;
pub const StrongLineAnchorIndex = spectroscopy_types.StrongLineAnchorIndex;
pub const hitran_hc_over_kb_cm_k = spectroscopy_types.hitran_hc_over_kb_cm_k;
pub const hitran_o2_line_mixing_hc_over_kb_cm_k = spectroscopy_types.hitran_o2_line_mixing_hc_over_kb_cm_k;
pub const SpectroscopyLine = spectroscopy_types.SpectroscopyLine;
pub const SpectroscopyStrongLine = spectroscopy_types.SpectroscopyStrongLine;
pub const SpectroscopyStrongLineSet = spectroscopy_types.SpectroscopyStrongLineSet;
pub const RelaxationMatrix = spectroscopy_types.RelaxationMatrix;
pub const SpectroscopyEvaluation = spectroscopy_types.SpectroscopyEvaluation;
pub const SpectroscopyRuntimeControls = spectroscopy_types.SpectroscopyRuntimeControls;
pub const StrongLinePreparedState = spectroscopy_types.StrongLinePreparedState;
pub const WeakLinePreparedState = spectroscopy_types.WeakLinePreparedState;
pub const SpectroscopyLineList = spectroscopy_line_list.SpectroscopyLineList;

pub const AirmassFactorPoint = airmass_phase.AirmassFactorPoint;
pub const AirmassFactorLut = airmass_phase.AirmassFactorLut;
