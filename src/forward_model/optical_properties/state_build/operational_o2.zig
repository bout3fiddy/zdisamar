const ReferenceData = @import("../../../input/ReferenceData.zig");
const OperationalCrossSectionLut = @import("../../../input/Instrument.zig").OperationalCrossSectionLut;

// hot path:
//   when: support-row spectroscopy uses the operational O2 LUT rtm_config
//   work: evaluates LUT sigma and temperature derivative for one wavelength/thermodynamic state
//   data: operational O2 LUT, wavelength, temperature, pressure
//   follow: cross_section_lut_eval.evaluate and carrier_eval support-row spectroscopy fields
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
