//! Purpose:
//!   Define the typed phase-function coefficient carriers used by optics
//!   preparation and scalar transport.
//!
//! Physics:
//!   Encodes the Rayleigh proxy coefficients, vendor-style analytic HG
//!   expansion, and weighted coefficient mixing used to prepare transport
//!   layers.
//!
//! Vendor:
//!   `propAtmosphereModule::getNumberPhasefcoef` and
//!   `propAtmosphereModule::getOptPropAtm`
//!
//! Design:
//!   The Zig path keeps a fixed-capacity coefficient carrier so the transport
//!   API remains typed while still allowing the active HG tail to follow the
//!   DISAMAR truncation rule instead of a hard four-term cutoff.
//!
//! Invariants:
//!   Coefficient index `0` remains `1.0`, inactive tail entries remain zero,
//!   and the active HG budget follows the vendor truncation recurrence.
//!
//! Validation:
//!   `tests/unit/optics_preparation_test.zig`,
//!   `tests/validation/disamar_compatibility_harness_test.zig`, and the O2A
//!   vendor-parity function-diff harness.

const std = @import("std");
const Scene = @import("../../../model/Scene.zig").Scene;

pub const legacy_phase_coefficient_count: usize = 4;
pub const vendor_hg_max_phase_index: usize = 150;
pub const vendor_hg_truncation_threshold: f64 = 1.0e-8;
pub const phase_coefficient_count: usize = vendor_hg_max_phase_index + 1;

pub fn zeroPhaseCoefficients() [phase_coefficient_count]f64 {
    var coefficients = [_]f64{0.0} ** phase_coefficient_count;
    coefficients[0] = 1.0;
    return coefficients;
}

pub fn phaseCoefficientsFromLegacy(
    legacy_coefficients: [legacy_phase_coefficient_count]f64,
) [phase_coefficient_count]f64 {
    var coefficients = zeroPhaseCoefficients();
    inline for (0..legacy_phase_coefficient_count) |index| {
        coefficients[index] = legacy_coefficients[index];
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
    var coefficients = zeroPhaseCoefficients();
    coefficients[2] = 0.05;
    return coefficients;
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
    gas_scattering_optical_depth: f64,
    aerosol_scattering_optical_depth: f64,
    cloud_scattering_optical_depth: f64,
    aerosol_phase_coefficients: [phase_coefficient_count]f64,
    cloud_phase_coefficients: [phase_coefficient_count]f64,
) [phase_coefficient_count]f64 {
    const gas_phase_coefficients = gasPhaseCoefficients();
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

test "layer depolarization uses already-fraction-scaled particle taus" {
    const scene: Scene = .{
        .aerosol = .{
            .enabled = true,
            .asymmetry_factor = 0.70,
            .fraction = .{
                .enabled = true,
                .target = .aerosol,
                .kind = .wavel_independent,
                .values = &.{0.25},
            },
        },
        .cloud = .{
            .enabled = true,
            .asymmetry_factor = 0.85,
            .fraction = .{
                .enabled = true,
                .target = .cloud,
                .kind = .wavel_independent,
                .values = &.{0.50},
            },
        },
    };

    const depolarization = computeLayerDepolarization(&scene, 0.60, 0.20, 0.20);
    const expected =
        0.60 * 0.0279 +
        0.20 * (0.04 + 0.02 * (1.0 - scene.aerosol.asymmetry_factor)) +
        0.20 * (0.01 + 0.01 * (1.0 - scene.cloud.asymmetry_factor));

    try std.testing.expectApproxEqRel(expected, depolarization, 1.0e-12);
}

test "analytic HG phase coefficients follow vendor normalization" {
    const coefficients = hgPhaseCoefficients(0.7);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), coefficients[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0 * 0.7), coefficients[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0 * 0.7 * 0.7), coefficients[2], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 7.0 * 0.7 * 0.7 * 0.7), coefficients[3], 1.0e-12);
}

test "analytic HG phase coefficients follow vendor truncation budget" {
    const coefficients = hgPhaseCoefficients(0.7);
    try std.testing.expectEqual(@as(usize, 39), maxPhaseCoefficientIndex(coefficients));
    try std.testing.expectApproxEqAbs(
        @as(f64, 79.0 * std.math.pow(f64, 0.7, 39.0)),
        coefficients[39],
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), coefficients[40], 1.0e-12);
}
