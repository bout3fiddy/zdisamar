const std = @import("std");
const Rayleigh = @import("../../../input/reference/rayleigh.zig");
const Scene = @import("../../../input/Scene.zig").Scene;

pub const compact_phase_coefficient_count: usize = 4;
pub const vendor_hg_max_phase_index: usize = 150;
pub const vendor_hg_truncation_threshold: f64 = 1.0e-8;
pub const phase_coefficient_count: usize = vendor_hg_max_phase_index + 1;

pub fn zeroPhaseCoefficients() [phase_coefficient_count]f64 {
    var coefficients = [_]f64{0.0} ** phase_coefficient_count;
    coefficients[0] = 1.0;
    return coefficients;
}

pub fn phaseCoefficientsFromCompact(
    compact_coefficients: [compact_phase_coefficient_count]f64,
) [phase_coefficient_count]f64 {
    var coefficients = zeroPhaseCoefficients();
    inline for (0..compact_phase_coefficient_count) |index| {
        coefficients[index] = compact_coefficients[index];
    }
    coefficients[0] = 1.0;
    return coefficients;
}

pub fn maxPhaseCoefficientIndex(phase_coefficients: [phase_coefficient_count]f64) usize {
    var max_index: usize = 0;
    for (1..phase_coefficient_count) |idx| {
        if (@abs(phase_coefficients[idx]) > 1.0e-12) {
            max_index = idx;
        }
    }
    return max_index;
}

pub fn gasPhaseCoefficients() [phase_coefficient_count]f64 {
    return gasPhaseCoefficientsAtWavelength(760.0);
}

pub fn gasPhaseCoefficientsAtWavelength(wavelength_nm: f64) [phase_coefficient_count]f64 {
    var coefficients = zeroPhaseCoefficients();
    coefficients[2] = rayleighPhaseCoefficient2AtWavelength(wavelength_nm);
    return coefficients;
}

pub fn rayleighPhaseCoefficient2AtWavelength(wavelength_nm: f64) f64 {
    const depolarization = Rayleigh.depolarizationFactorAir(wavelength_nm);
    const eps = 45.0 * depolarization / (6.0 - 7.0 * depolarization);
    return (45.0 + eps) / (90.0 + 20.0 * eps);
}

pub fn computeSingleScatterAlbedo(scene: *const Scene, wavelength_nm: f64) f64 {
    const gas_ssa: f64 = 0.92;
    const aerosol_ssa = if (scene.atmosphere.has_aerosols) scene.aerosol.single_scatter_albedo else gas_ssa;
    const cloud_ssa = if (scene.atmosphere.has_clouds) scene.cloud.single_scatter_albedo else gas_ssa;
    const aerosol_fraction = if (scene.aerosol.fraction.enabled)
        scene.aerosol.fraction.valueAtWavelength(wavelength_nm)
    else
        1.0;
    const cloud_fraction = if (scene.cloud.fraction.enabled)
        scene.cloud.fraction.valueAtWavelength(wavelength_nm)
    else
        1.0;
    const aerosol_weight: f64 = if (scene.atmosphere.has_aerosols) 0.20 * aerosol_fraction else 0.0;
    const cloud_weight: f64 = if (scene.atmosphere.has_clouds) 0.30 * cloud_fraction else 0.0;
    const gas_weight: f64 = 1.0 - aerosol_weight - cloud_weight;
    return std.math.clamp(gas_weight * gas_ssa + aerosol_weight * aerosol_ssa + cloud_weight * cloud_ssa, 0.3, 0.999);
}

pub fn hgPhaseCoefficients(asymmetry_factor: f64) [phase_coefficient_count]f64 {
    var coefficients = zeroPhaseCoefficients();
    const truncation_g = @abs(asymmetry_factor);
    if (truncation_g <= 0.0) return coefficients;

    var normalized_tail: f64 = 1.0;
    for (1..phase_coefficient_count) |index| {
        const order: f64 = @floatFromInt(index);
        normalized_tail *= truncation_g * (2.0 * order - 1.0) / (2.0 * order + 1.0);
        if (normalized_tail < vendor_hg_truncation_threshold) break;
        coefficients[index] =
            (2.0 * order + 1.0) *
            std.math.pow(f64, asymmetry_factor, order);
    }
    return coefficients;
}

pub fn combinePhaseCoefficients(
    wavelength_nm: f64,
    gas_scattering_optical_depth: f64,
    aerosol_scattering_optical_depth: f64,
    cloud_scattering_optical_depth: f64,
    aerosol_phase_coefficients: [phase_coefficient_count]f64,
    cloud_phase_coefficients: [phase_coefficient_count]f64,
) [phase_coefficient_count]f64 {
    const gas_phase_coefficients = gasPhaseCoefficientsAtWavelength(wavelength_nm);
    const total_scattering = gas_scattering_optical_depth + aerosol_scattering_optical_depth + cloud_scattering_optical_depth;
    if (total_scattering == 0.0) return gas_phase_coefficients;

    var combined = zeroPhaseCoefficients();
    for (0..phase_coefficient_count) |index| {
        combined[index] =
            (gas_scattering_optical_depth * gas_phase_coefficients[index] +
                aerosol_scattering_optical_depth * aerosol_phase_coefficients[index] +
                cloud_scattering_optical_depth * cloud_phase_coefficients[index]) / total_scattering;
    }
    combined[0] = 1.0;
    return combined;
}

pub fn backscatterFraction(phase_coefficients: [phase_coefficient_count]f64) f64 {
    return backscatterFractionFromAsymmetry(phase_coefficients[1]);
}

pub fn backscatterFractionFromAsymmetry(asymmetry_factor: f64) f64 {
    const clamped_asymmetry = std.math.clamp(asymmetry_factor, -0.95, 0.95);
    return std.math.clamp(0.5 * (1.0 - clamped_asymmetry), 0.02, 0.95);
}

pub fn computeLayerDepolarization(
    scene: *const Scene,
    gas_scattering_tau: f64,
    aerosol_scattering_tau: f64,
    cloud_scattering_tau: f64,
) f64 {
    const total = gas_scattering_tau + aerosol_scattering_tau + cloud_scattering_tau;
    if (total == 0.0) return 0.0;
    const gas_fraction = gas_scattering_tau / total;
    const aerosol_fraction = aerosol_scattering_tau / total;
    const cloud_fraction = cloud_scattering_tau / total;
    return gas_fraction * 0.0279 +
        aerosol_fraction * (0.04 + 0.02 * (1.0 - scene.aerosol.asymmetry_factor)) +
        cloud_fraction * (0.01 + 0.01 * (1.0 - scene.cloud.asymmetry_factor));
}
