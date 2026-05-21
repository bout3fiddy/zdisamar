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

const default_phase_mixture_coefficients = zeroPhaseCoefficients();

// Encoded phase-coefficient mixture for rows that are a gas/aerosol blend.
// layout(64-bit):
//   size: 24 B, align: 8 B
//   field storage: 24 B across 3 fields; largest: aerosol_weight=8 B, rayleigh2_weight=8 B, aerosol_phase_coefficients=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: aerosol_phase_coefficients points at shared prepared phase rows; referenced storage is not included in size
//   cache span: 1 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 24 B (0.023 KiB); total also includes referenced storage above
pub const PhaseMixture = struct {
    aerosol_weight: f64 = 0.0,
    rayleigh2_weight: f64 = 0.0,
    aerosol_phase_coefficients: *const [phase_coefficient_count]f64 = &default_phase_mixture_coefficients,

    pub fn fromUnitPhase(phase_coefficients: *const [phase_coefficient_count]f64) PhaseMixture {
        return .{
            .aerosol_weight = 1.0,
            .aerosol_phase_coefficients = phase_coefficients,
        };
    }

    pub fn fromScatteringMix(
        rayleigh_coef2: f64,
        gas_scattering: f64,
        aerosol_scattering: f64,
        aerosol_phase_coefficients: *const [phase_coefficient_count]f64,
    ) PhaseMixture {
        const total_scattering = gas_scattering + aerosol_scattering;
        if (total_scattering <= 0.0) {
            return .{ .rayleigh2_weight = rayleigh_coef2 };
        }
        const inv_total = 1.0 / total_scattering;
        const aerosol_weight = aerosol_scattering * inv_total;
        const rayleigh2_weight = gas_scattering * inv_total * rayleigh_coef2;
        return .{
            .aerosol_weight = aerosol_weight,
            .rayleigh2_weight = rayleigh2_weight,
            .aerosol_phase_coefficients = aerosol_phase_coefficients,
        };
    }

    pub fn coefficient(self: PhaseMixture, index: usize) f64 {
        return weightedPhaseCoefficient(
            self.aerosol_weight,
            self.rayleigh2_weight,
            self.aerosol_phase_coefficients,
            index,
        );
    }

    pub fn eql(self: PhaseMixture, other: PhaseMixture) bool {
        return self.aerosol_weight == other.aerosol_weight and
            self.rayleigh2_weight == other.rayleigh2_weight and
            self.aerosol_phase_coefficients == other.aerosol_phase_coefficients;
    }

    pub fn maxIndex(self: PhaseMixture) usize {
        return maxWeightedPhaseCoefficientIndex(
            self.aerosol_weight,
            self.rayleigh2_weight,
            self.aerosol_phase_coefficients,
        );
    }

    pub fn coefficients(self: PhaseMixture) [phase_coefficient_count]f64 {
        var values: [phase_coefficient_count]f64 = undefined;
        for (&values, 0..) |*value, index| value.* = self.coefficient(index);
        return values;
    }
};

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

pub fn maxPhaseCoefficientIndex(phase_coefficients: *const [phase_coefficient_count]f64) usize {
    var idx = phase_coefficient_count;
    while (idx > 1) {
        idx -= 1;
        if (@abs(phase_coefficients[idx]) > 1.0e-12) return idx;
    }
    return 0;
}

pub fn weightedPhaseCoefficient(
    aerosol_weight: f64,
    rayleigh2_weight: f64,
    aerosol_phase_coefficients: *const [phase_coefficient_count]f64,
    index: usize,
) f64 {
    if (index == 0) return 1.0;
    var coefficient = aerosol_weight * aerosol_phase_coefficients[index];
    if (index == 2) coefficient += rayleigh2_weight;
    return coefficient;
}

pub fn maxWeightedPhaseCoefficientIndex(
    aerosol_weight: f64,
    rayleigh2_weight: f64,
    aerosol_phase_coefficients: *const [phase_coefficient_count]f64,
) usize {
    var max_index: usize = 0;
    if (@abs(rayleigh2_weight) > 1.0e-12) max_index = 2;
    if (@abs(aerosol_weight) > 1.0e-12) {
        max_index = @max(max_index, maxPhaseCoefficientIndex(aerosol_phase_coefficients));
    }
    return max_index;
}

pub fn gasPhaseCoefficients() [phase_coefficient_count]f64 {
    return gasPhaseCoefficientsAtWavelength(760.0);
}

pub fn gasPhaseCoefficientsAtWavelength(wavelength_nm: f64) [phase_coefficient_count]f64 {
    return gasPhaseCoefficientsFromRayleigh2(rayleighPhaseCoefficient2AtWavelength(wavelength_nm));
}

pub fn gasPhaseCoefficientsFromRayleigh2(rayleigh_coef2: f64) [phase_coefficient_count]f64 {
    var coefficients = zeroPhaseCoefficients();
    coefficients[2] = rayleigh_coef2;
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
    const aerosol_fraction = if (scene.aerosol.fraction.enabled)
        scene.aerosol.fraction.valueAtWavelength(wavelength_nm)
    else
        1.0;
    const aerosol_weight: f64 = if (scene.atmosphere.has_aerosols) 0.20 * aerosol_fraction else 0.0;
    const gas_weight: f64 = 1.0 - aerosol_weight;
    return std.math.clamp(gas_weight * gas_ssa + aerosol_weight * aerosol_ssa, 0.3, 0.999);
}

pub fn hgPhaseCoefficients(asymmetry_factor: f64) [phase_coefficient_count]f64 {
    return hgPhaseCoefficientsWithThreshold(asymmetry_factor, vendor_hg_truncation_threshold);
}

// hot path:
//   when: optical-state preparation builds particle phase coefficients
//   work: fills Henyey-Greenstein coefficient tail until the truncation threshold
//   data: asymmetry factor, truncation threshold, coefficient array
//   follow: combinePhaseCoefficientsWithRayleigh2 and LABOS phase-basis builders
pub fn hgPhaseCoefficientsWithThreshold(
    asymmetry_factor: f64,
    truncation_threshold: f64,
) [phase_coefficient_count]f64 {
    var coefficients = zeroPhaseCoefficients();
    const truncation_g = @abs(asymmetry_factor);
    if (truncation_g <= 0.0) return coefficients;
    const threshold = @max(truncation_threshold, 0.0);

    var normalized_tail: f64 = 1.0;
    for (1..phase_coefficient_count) |index| {
        const order: f64 = @floatFromInt(index);
        normalized_tail *= truncation_g * (2.0 * order - 1.0) / (2.0 * order + 1.0);
        if (normalized_tail < threshold) break;
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
    aerosol_phase_coefficients: *const [phase_coefficient_count]f64,
) [phase_coefficient_count]f64 {
    return combinePhaseCoefficientsWithRayleigh2(
        rayleighPhaseCoefficient2AtWavelength(wavelength_nm),
        gas_scattering_optical_depth,
        aerosol_scattering_optical_depth,
        aerosol_phase_coefficients,
    );
}

// hot path:
//   when: layer/sublayer carrier evaluation combines gas and aerosol scattering
//   work: blends Rayleigh and aerosol phase coefficients by scattering optical depth
//   data: scattering optical depths, Rayleigh coefficient, aerosol coefficient array
//   follow: layer_accumulation phase writes and LABOS phase matrix construction
pub fn combinePhaseCoefficientsWithRayleigh2(
    rayleigh_coef2: f64,
    gas_scattering_optical_depth: f64,
    aerosol_scattering_optical_depth: f64,
    aerosol_phase_coefficients: *const [phase_coefficient_count]f64,
) [phase_coefficient_count]f64 {
    const total_scattering = gas_scattering_optical_depth + aerosol_scattering_optical_depth;
    if (total_scattering == 0.0) return gasPhaseCoefficientsFromRayleigh2(rayleigh_coef2);
    if (aerosol_scattering_optical_depth == 0.0) {
        return gasPhaseCoefficientsFromRayleigh2(rayleigh_coef2);
    }

    var combined: [phase_coefficient_count]f64 = undefined;
    const inv_total = 1.0 / total_scattering;
    const gas_weight = gas_scattering_optical_depth * inv_total;
    const aerosol_weight = aerosol_scattering_optical_depth * inv_total;

    for (0..phase_coefficient_count) |index| {
        combined[index] = aerosol_weight * aerosol_phase_coefficients[index];
    }
    combined[0] = 1.0;
    combined[2] += gas_weight * rayleigh_coef2;
    return combined;
}

pub fn backscatterFraction(phase_coefficients: *const [phase_coefficient_count]f64) f64 {
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
) f64 {
    const total = gas_scattering_tau + aerosol_scattering_tau;
    if (total == 0.0) return 0.0;
    const gas_fraction = gas_scattering_tau / total;
    const aerosol_fraction = aerosol_scattering_tau / total;
    return gas_fraction * 0.0279 +
        aerosol_fraction * (0.04 + 0.02 * (1.0 - scene.aerosol.asymmetry_factor));
}
