//! Purpose:
//!   Provide the operational O2 cross-section evaluation hook used during
//!   optics preparation.
//!
//! Physics:
//!   Converts the operational O2 lookup table into the spectroscopy evaluation
//!   shape expected by the transport kernels.
//!
//! Vendor:
//!   `operational O2` lookup path
//!
//! Design:
//!   Keeps the operational O2 shortcut isolated so the generic spectroscopy
//!   path stays unchanged when the lookup is disabled.
//!
//! Invariants:
//!   The O2 lookup must populate the same spectroscopy fields as the generic
//!   evaluation path.
//!
//! Validation:
//!   Optics-preparation transport tests.

const ReferenceData = @import("../../../model/ReferenceData.zig");
const OperationalCrossSectionLut = @import("../../../model/Instrument.zig").OperationalCrossSectionLut;

/// Purpose:
///   Evaluate the operational O2 lookup at one wavelength and state.
pub fn operationalO2EvaluationAtWavelength(
    operational_o2_lut: OperationalCrossSectionLut,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) ReferenceData.SpectroscopyEvaluation {
    const sigma = operational_o2_lut.sigmaAt(wavelength_nm, temperature_k, pressure_hpa);
    return .{
        .weak_line_sigma_cm2_per_molecule = sigma,
        .strong_line_sigma_cm2_per_molecule = 0.0,
        .line_sigma_cm2_per_molecule = sigma,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = sigma,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = operational_o2_lut.dSigmaDTemperatureAt(
            wavelength_nm,
            temperature_k,
            pressure_hpa,
        ),
    };
}
