const std = @import("std");

const o2_case = @import("../input/o2_case.zig");

pub const coefficient_count: usize = 151;
pub const vendor_hg_max_phase_index: usize = coefficient_count - 1;
pub const vendor_hg_truncation_threshold: f64 = 1.0e-8;

// phase_table.zig --------------------------------------------------------------------------------------------|
// Prepared aerosol phase-function coefficients consumed by LABOS phase-basis and layer builders.              |
//                                                                                                             |
// provenance                                                                                                  |
//   Ports main:`src/forward_model/optical_properties/shared/phase_functions.zig` HG coefficient preparation:  |
//   fixed [151] coefficient storage, vendor max phase index 150, and case truncation threshold.               |
//                                                                                                             |
// math                                                                                                        |
//   coefficient[0] = 1                                                                                        |
//   coefficient[l] = (2l + 1) * g^l while the normalized HG tail remains above the threshold                  |
//                                                                                                             |
// memory                                                                                                      |
//   PhaseTable stores the full fixed aerosol coefficient row inline so wavelength-time transport can borrow   |
//   the row without allocation or recomputing the setup-only HG series.                                       |
// ------------------------------------------------------------------------------------------------------------|

// PhaseTable -------------------------------------------------------------------------------------------------|
// Prepared Henyey-Greenstein aerosol phase row for one setup case.                                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 1224 B (1.195 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..1207] aerosol_phase_coefficients : [151]f64                                                          |
// [1208..1215] aerosol_phase_max_index    : usize                                                             |
// [1216..1223] aerosol_asymmetry_factor   : f64                                                               |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 20 cache line(s) at 64 B per line                                                               |
// footprint: per instance = 1224 B (1.195 KiB); inline setup table row                                        |
pub const PhaseTable = struct {
    aerosol_phase_coefficients: [coefficient_count]f64,
    aerosol_phase_max_index: usize,
    aerosol_asymmetry_factor: f64,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn build(case: o2_case.O2Case) PhaseTable {
    // build --------------------------------------------------------------------------------------------------|
    // Prepare the case aerosol HG phase row for later LABOS phase-kernel construction.                        |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Multi-layer profile collapse follows main:`state_build/layer_accumulation.zig`                        |
    //   profileEquivalentPhaseCoefficients: one equivalent HG g is weighted by midpoint-wavelength            |
    //   scattering optical depth.                                                                             |
    // --------------------------------------------------------------------------------------------------------|
    const asymmetry_factor = if (case.aerosol.profile.len == 0)
        case.aerosol.asymmetry_factor
    else
        profileEquivalentAsymmetryFactor(case);
    const coefficients = hgPhaseCoefficientsWithThreshold(
        asymmetry_factor,
        case.rtm.performance_thresholds.phase_function_truncation_threshold,
    );
    return .{
        .aerosol_phase_coefficients = coefficients,
        .aerosol_phase_max_index = maxPhaseCoefficientIndex(&coefficients),
        .aerosol_asymmetry_factor = asymmetry_factor,
    };
}

pub fn zeroPhaseCoefficients() [coefficient_count]f64 {
    // zeroPhaseCoefficients ----------------------------------------------------------------------------------|
    // Return the old fixed phase row with only the isotropic l=0 term active.                                 |
    // --------------------------------------------------------------------------------------------------------|
    var coefficients = [_]f64{0.0} ** coefficient_count;
    coefficients[0] = 1.0;
    return coefficients;
}

pub fn hgPhaseCoefficients(asymmetry_factor: f64) [coefficient_count]f64 {
    // hgPhaseCoefficients ------------------------------------------------------------------------------------|
    // Build the old vendor-threshold Henyey-Greenstein aerosol coefficient row.                               |
    // --------------------------------------------------------------------------------------------------------|
    return hgPhaseCoefficientsWithThreshold(asymmetry_factor, vendor_hg_truncation_threshold);
}

pub fn hgPhaseCoefficientsWithThreshold(
    asymmetry_factor: f64,
    truncation_threshold: f64,
) [coefficient_count]f64 {
    // hgPhaseCoefficientsWithThreshold ---------------------------------------------------------------------- |
    // Fill the Henyey-Greenstein coefficient tail until the normalized tail falls below the threshold.        |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Formula and tail gate port old `phase_functions.zig` `hgPhaseCoefficientsWithThreshold`.              |
    //                                                                                                         |
    // math                                                                                                    |
    //   coefficient[l] = (2l + 1) * g^l                                                                       |
    //   normalized_tail *= abs(g) * (2l - 1) / (2l + 1)                                                       |
    // --------------------------------------------------------------------------------------------------------|
    var coefficients = zeroPhaseCoefficients();
    const truncation_g = @abs(asymmetry_factor);
    if (truncation_g <= 0.0) return coefficients;

    const threshold = @max(truncation_threshold, 0.0);
    var normalized_tail: f64 = 1.0;
    for (1..coefficient_count) |index| {
        const order: f64 = @floatFromInt(index);
        normalized_tail *= truncation_g * (2.0 * order - 1.0) / (2.0 * order + 1.0);
        if (normalized_tail < threshold) break;
        coefficients[index] =
            (2.0 * order + 1.0) *
            std.math.pow(f64, asymmetry_factor, order);
    }

    return coefficients;
}

pub fn maxPhaseCoefficientIndex(coefficients: *const [coefficient_count]f64) usize {
    // maxPhaseCoefficientIndex ------------------------------------------------------------------------------ |
    // Return the highest non-negligible coefficient index used by old LABOS phase support.                    |
    // --------------------------------------------------------------------------------------------------------|
    var index = coefficient_count;
    while (index > 1) {
        index -= 1;
        if (@abs(coefficients[index]) > 1.0e-12) return index;
    }
    return 0;
}

fn profileEquivalentAsymmetryFactor(case: o2_case.O2Case) f64 {
    // profileEquivalentAsymmetryFactor -----------------------------------------------------------------------|
    // Collapse explicit aerosol profile layers into one midpoint-wavelength HG asymmetry value.               |
    //                                                                                                         |
    // math                                                                                                    |
    //   midpoint_nm = 0.5 * (spectral_grid.start_nm + spectral_grid.end_nm)                                   |
    //   scattering_i = scaled_tau_i(midpoint_nm) * single_scatter_albedo_i                                    |
    //   g_equiv = sum(scattering_i * asymmetry_i) / sum(scattering_i)                                         |
    // --------------------------------------------------------------------------------------------------------|
    const midpoint_nm = 0.5 * (case.spectral_grid.start_nm + case.spectral_grid.end_nm);
    var scattering_sum: f64 = 0.0;
    var asymmetry_sum: f64 = 0.0;

    for (case.aerosol.profile) |layer| {
        const scattering = scaleOpticalDepth(
            layer.optical_depth,
            layer.reference_wavelength_nm,
            layer.angstrom_exponent,
            midpoint_nm,
        ) * layer.single_scatter_albedo;
        if (scattering <= 0.0) continue;

        scattering_sum += scattering;
        asymmetry_sum += scattering * layer.asymmetry_factor;
    }

    return if (scattering_sum > 0.0) asymmetry_sum / scattering_sum else case.aerosol.asymmetry_factor;
}

fn scaleOpticalDepth(
    optical_depth: f64,
    reference_wavelength_nm: f64,
    angstrom_exponent: f64,
    wavelength_nm: f64,
) f64 {
    // scaleOpticalDepth --------------------------------------------------------------------------------------|
    // Apply old aerosol Angstrom scaling with the same safe wavelength/reference guard.                       |
    // --------------------------------------------------------------------------------------------------------|
    if (optical_depth == 0.0 or angstrom_exponent == 0.0 or reference_wavelength_nm == wavelength_nm) {
        return optical_depth;
    }

    const safe_wavelength_nm = @max(wavelength_nm, 1.0);
    const safe_reference_nm = @max(reference_wavelength_nm, 1.0);
    return optical_depth * std.math.pow(f64, safe_reference_nm / safe_wavelength_nm, angstrom_exponent);
}
