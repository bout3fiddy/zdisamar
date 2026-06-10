const std = @import("std");
const Rayleigh = @import("../../../input/reference/rayleigh.zig");
const Scene = @import("../../../input/Scene.zig").Scene;

// phase_functions.zig ---------------------------------------------------------------------------------------  |
// Builds Rayleigh, aerosol, and mixed phase-coefficient rows for optical state and LABOS transport.            |
//                                                                                                              |
// called by                                                                                                    |
//   radiative_transfer/root.zig re-exports phase_coefficient_count and LayerPhase                              |
//   state_build/context.zig prepares aerosol HG coefficients from Scene controls                               |
//   shared_carrier.zig, carrier_eval.zig, rtm_quadrature.zig, and forward_layers.zig store PhaseMixture rows   |
//   LABOS phase_basis.zig reads the final coefficient arrays and max retained phase index                      |
//                                                                                                              |
// main paths                                                                                                   |
//   phaseCoefficientsFromCompact expands short input rows into the fixed [151] coefficient layout              |
//   hgPhaseCoefficients builds truncated Henyey-Greenstein aerosol coefficients                                |
//   PhaseMixture stores gas/aerosol mixture weights plus a borrowed aerosol coefficient pointer                |
//   weightedPhaseCoefficient reads one mixed coefficient without materializing the full row                    |
//                                                                                                              |
// hot path                                                                                                     |
//   Carrier and layer-accumulation paths keep mixture weights plus a borrowed pointer to prepared aerosol      |
//   coefficients. LABOS expands the [151]f64 row only where its basis and layer math consume it.               |
//                                                                                                              |
// memory                                                                                                       |
//   The full phase row is [151]f64. PhaseMixture is a 24 B borrowed view over shared prepared coefficients.    |
// ------------------------------------------------------------------------------------------------------------ |

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

// PhaseMixture ----------------------------------------------------------------------------------------------  |
// Encoded phase-coefficient mixture for rows that are a gas/aerosol blend.                                     |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 24 B (0.023 KiB), align: 8 B                                                                           |
//                                                                                                              |
// memory                                                                                                       |
// [ 0.. 7] aerosol_weight              : f64                                                                   |
// [ 8..15] rayleigh2_weight            : f64                                                                   |
// [16..23] aerosol_phase_coefficients  : *const [151]f64                                                       |
//                                                                                                              |
// out-of-line                                                                                                  |
//   aerosol_phase_coefficients points at shared prepared phase rows; referenced storage is not included.       |
//                                                                                                              |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                       |
// cache span: 1 cache line at 64 B per line                                                                    |
// footprint: per instance = 24 B plus borrowed coefficient storage                                             |
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
// ------------------------------------------------------------------------------------------------------------ |

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
    // weightedPhaseCoefficient --------------------------------------------------------------------------------|
    // Reads one coefficient from the compact gas/aerosol mixture without materializing the full [151]f64 row.  |
    //                                                                                                          |
    // math                                                                                                     |
    //   P_l = aerosol_weight * P_l,aerosol + rayleigh2_weight when l = 2                                       |
    //   P_0 = 1                                                                                                |
    // -------------------------------------------------------------------------------------------------------- |

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

pub fn gasPhaseCoefficientsFromRayleigh2(rayleigh_coef2: f64) [phase_coefficient_count]f64 {
    var coefficients = zeroPhaseCoefficients();
    coefficients[2] = rayleigh_coef2;
    return coefficients;
}

pub fn rayleighPhaseCoefficient2AtWavelength(wavelength_nm: f64) f64 {
    // rayleighPhaseCoefficient2AtWavelength ------------------------------------------------------------------ |
    // Converts wavelength-dependent air depolarization to the Rayleigh l=2 phase coefficient.                  |
    //                                                                                                          |
    // math                                                                                                     |
    //   eps = 45 * depolarization / (6 - 7 * depolarization)                                                   |
    //   P2  = (45 + eps) / (90 + 20 * eps)                                                                     |
    // -------------------------------------------------------------------------------------------------------- |

    const depolarization = Rayleigh.depolarizationFactorAir(wavelength_nm);
    const eps = 45.0 * depolarization / (6.0 - 7.0 * depolarization);
    return (45.0 + eps) / (90.0 + 20.0 * eps);
}

pub fn computeSingleScatterAlbedo(scene: *const Scene, wavelength_nm: f64) f64 {
    // computeSingleScatterAlbedo ----------------------------------------------------------------------------- |
    // Blends the gas floor and aerosol single-scatter albedo into the effective scene value.                   |
    //                                                                                                          |
    // math                                                                                                     |
    //   effective SSA = clamp(gas_weight * gas_ssa + aerosol_weight * aerosol_ssa, 0.3, 0.999)                 |
    // -------------------------------------------------------------------------------------------------------- |

    const gas_ssa: f64 = 0.92;

    const aerosol_ssa = choose_aerosol_ssa: {
        if (scene.atmosphere.has_aerosols) break :choose_aerosol_ssa scene.aerosol.single_scatter_albedo;
        break :choose_aerosol_ssa gas_ssa;
    };

    const aerosol_fraction = choose_aerosol_fraction: {
        if (scene.aerosol.fraction.enabled) {
            break :choose_aerosol_fraction scene.aerosol.fraction.valueAtWavelength(wavelength_nm);
        }
        break :choose_aerosol_fraction 1.0;
    };

    const aerosol_weight: f64 = choose_aerosol_weight: {
        if (scene.atmosphere.has_aerosols) break :choose_aerosol_weight 0.20 * aerosol_fraction;
        break :choose_aerosol_weight 0.0;
    };

    const gas_weight: f64 = 1.0 - aerosol_weight;

    return std.math.clamp(gas_weight * gas_ssa + aerosol_weight * aerosol_ssa, 0.3, 0.999);
}

pub fn hgPhaseCoefficients(asymmetry_factor: f64) [phase_coefficient_count]f64 {
    return hgPhaseCoefficientsWithThreshold(asymmetry_factor, vendor_hg_truncation_threshold);
}

pub fn hgPhaseCoefficientsWithThreshold(
    asymmetry_factor: f64,
    truncation_threshold: f64,
) [phase_coefficient_count]f64 {
    // hgPhaseCoefficientsWithThreshold ----------------------------------------------------------------------  |
    // Fills the Henyey-Greenstein coefficient tail until the truncation threshold.                             |
    //                                                                                                          |
    // hot path                                                                                                 |
    //   Runs during optical-state preparation, before wavelength-time LABOS phase-basis builders consume the   |
    //   prepared coefficient rows.                                                                             |
    //                                                                                                          |
    // math                                                                                                     |
    //   P_l = (2l + 1) * g^l                                                                                   |
    //   truncation_tail *= |g| * (2l - 1) / (2l + 1)                                                           |
    // -------------------------------------------------------------------------------------------------------  |

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

pub fn computeLayerDepolarization(
    scene: *const Scene,
    gas_scattering_tau: f64,
    aerosol_scattering_tau: f64,
) f64 {
    // computeLayerDepolarization ----------------------------------------------------------------------------- |
    // Blends gas and aerosol depolarization by scattering optical depth.                                       |
    //                                                                                                          |
    // math                                                                                                     |
    //   depol = gas_fraction * 0.0279 + aerosol_fraction * (0.04 + 0.02 * (1 - asymmetry_factor))              |
    // -------------------------------------------------------------------------------------------------------- |

    const total = gas_scattering_tau + aerosol_scattering_tau;
    if (total == 0.0) return 0.0;

    const gas_fraction = gas_scattering_tau / total;
    const aerosol_fraction = aerosol_scattering_tau / total;

    return gas_fraction * 0.0279 +
        aerosol_fraction * (0.04 + 0.02 * (1.0 - scene.aerosol.asymmetry_factor));
}
