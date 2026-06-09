const ReferenceData = @import("../../../input/ReferenceData.zig");
const OperationalCrossSectionLut = @import("../../../input/Instrument.zig").OperationalCrossSectionLut;

// operational_o2.zig ----------------------------------------------------------------------------------------- |
// Adapts the operational O2 lookup table to the spectroscopy evaluation shape used by state builders.          |
//                                                                                                              |
// called by                                                                                                    |
//   spectroscopy.zig exposes this through the state-build spectroscopy facade                                  |
//   state_spectroscopy.zig uses it for continuum/profile spectroscopy when operational O2 LUTs replace lines   |
//   layer_spectroscopy.zig uses the same evaluation shape for support-row and profile-node line values         |
//                                                                                                              |
// main path                                                                                                    |
//   operationalO2EvaluationAtWavelength                                                                        |
//     -> evaluate sigma from OperationalCrossSectionLut                                                        |
//     -> evaluate d_sigma/dT from the same LUT                                                                 |
//     -> fill the ReferenceData.SpectroscopyEvaluation fields expected by line-spectroscopy callers            |
//                                                                                                              |
// hot path                                                                                                     |
//   Support-row spectroscopy calls this for one wavelength and thermodynamic state before carrier rows reuse   |
//   the resulting sigma and temperature derivative.                                                            |
//                                                                                                              |
// memory                                                                                                       |
//   Returns one value row. The LUT storage stays borrowed from PreparedOpticalState/Context.                   |
// ------------------------------------------------------------------------------------------------------------ |

pub fn operationalO2EvaluationAtWavelength(
    operational_o2_lut: OperationalCrossSectionLut,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) ReferenceData.SpectroscopyEvaluation {
    // operationalO2EvaluationAtWavelength -------------------------------------------------------------------- |
    // Evaluates LUT sigma and temperature derivative for one wavelength/thermodynamic state.                   |
    //                                                                                                          |
    // calls                                                                                                    |
    //   OperationalCrossSectionLut.sigmaAt                                                                     |
    //   OperationalCrossSectionLut.dSigmaDTemperatureAt                                                        |
    // -------------------------------------------------------------------------------------------------------- |

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
