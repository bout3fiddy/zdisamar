const ReferenceData = @import("../../../input/ReferenceData.zig");
const OperationalCrossSectionLut = @import("../../../input/Instrument.zig").OperationalCrossSectionLut;

// operational_o2.zig ----------------------------------------------------------------------------------------- |
// Adapts an operational O2 cross-section LUT into the SpectroscopyEvaluation shape used by prepared optics.    |
//                                                                                                              |
// called by                                                                                                    |
//   spectroscopy.zig exposes this through the state-build spectroscopy facade.                                 |
//   state_spectroscopy.zig calls it when an operational O2 LUT replaces line-by-line O2 spectroscopy.          |
//   carrier_eval.zig and layer_spectroscopy.zig then density-weight the returned evaluation with other active  |
//   line absorbers for support-row, profile-node, and altitude carrier routes.                                 |
//                                                                                                              |
// mapping                                                                                                      |
//   OperationalCrossSectionLut.sigmaAt becomes weak_line_sigma, line_sigma, and total_sigma. Strong-line and   |
//   line-mixing fields are zero because the LUT is already the operational cross-section product, not a split  |
//   HITRAN weak/strong-line decomposition. d_sigma_d_temperature comes from the same LUT.                      |
//                                                                                                              |
// hot path                                                                                                     |
//   Runs at wavelength time for each O2 operational thermodynamic sample. Keep this as one borrowed-LUT value  |
//   adapter; setup ownership and LUT generation/consumption live in input/instrument and state_build/context.  |
//                                                                                                              |
// memory                                                                                                       |
//   Returns one ReferenceData.SpectroscopyEvaluation value row. The LUT rows stay borrowed from                |
//   PreparedOpticalState or the setup Context; no allocation or retained state is created here.                |
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
