const std = @import("std");

const radiance_wavelengths = @import("radiance_wavelengths.zig");
const sampling_table = @import("sampling_table.zig");
const controls = @import("../rtm/controls.zig");
const jacobian_states = @import("../rtm/jacobian_states.zig");
const solve = @import("../rtm/solve.zig");

pub const Error = error{
    ShapeMismatch,
};

// radiance_results.zig -------------------------------------------------------------------------------------- |
// Dense high-resolution radiance rows and nominal-row gathering.                                              |
//                                                                                                             |
// data flow                                                                                                   |
//   RadianceWavelengthList rows give each nominal wavelength a slice of dense result indexes.                 |
//   SpectrumSamplingRow carries the matching integration weights. This module applies those weights exactly   |
//   once to radiance and active Jacobian lanes.                                                               |
//   The dense prefetch route scales top-of-atmosphere reflectance into radiance units.                        |
//                                                                                                             |
// allocation                                                                                                  |
//   This file allocates nothing. The caller owns dense result arrays, sample-index arrays, and kernel storage.|
// ------------------------------------------------------------------------------------------------------------|

// RadianceResult -------------------------------------------------------------------------------------------- |
// One high-resolution or nominal radiance result with fixed Jacobian lanes.                                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] radiance : f64                                                                                     |
// [ 8..23] jacobian : [2]f64                                                                                  |
pub const RadianceResult = struct {
    radiance: f64 = 0.0,
    jacobian: jacobian_states.Vector = jacobian_states.zero(),
};
// ------------------------------------------------------------------------------------------------------------|

pub fn scaleReflectanceToRadiance(
    solve_config: controls.SolveConfig,
    reflectance: solve.ReflectanceResult,
    solar_cosine: f64,
    solar_irradiance: f64,
) RadianceResult {
    // scaleReflectanceToRadiance ---------------------------------------------------------------------------  |
    // Pack one transport reflectance solve into the dense high-resolution radiance row used by spectrum       |
    // gathering.                                                                                              |
    //                                                                                                         |
    //   `radianceScaleFromForward` and `integratedSampleFromForward`.                                         |
    //                                                                                                         |
    // math                                                                                                    |
    //   reflectance_factor = pi * L / (mu0 * E0)                                                              |
    //   L                  = reflectance_factor * mu0 * E0 / pi                                               |
    //   dL/dx              = d(reflectance_factor)/dx * mu0 * E0 / pi for active RTM states x                 |
    //                                                                                                         |
    // why no derivative of scale                                                                              |
    //   The fixed Jacobian states perturb RTM reflectance, not solar irradiance or geometry, so the           |
    //   product rule reduces to scale * d(reflectance_factor)/dx.                                             |
    // --------------------------------------------------------------------------------------------------------|
    const scale = solar_cosine * solar_irradiance / std.math.pi;

    const active_state_count = jacobian_states.activeStateCount(solve_config.derivative_state_mask);
    const wants_jacobian = solve_config.derivative_mode != .none and active_state_count != 0;
    const radiance_jacobian = if (wants_jacobian)
        jacobian_states.scaleMasked(reflectance.jacobian, scale, solve_config.derivative_state_mask)
    else
        jacobian_states.zero();

    return .{
        .radiance = reflectance.reflectance * scale,
        .jacobian = radiance_jacobian,
    };
}

pub fn integratePrefetchedRadianceAtNominal(
    solve_config: controls.SolveConfig,
    results: []const RadianceResult,
    row_ref: radiance_wavelengths.RadianceSampleIndexRef,
    sample_indices: []const u32,
    integration: *const sampling_table.IntegrationKernelRef,
    kernel_storage: sampling_table.IntegrationKernelStorage,
) Error!RadianceResult {
    // integratePrefetchedRadianceAtNominal ------------------------------------------------------------------ |
    // Accumulate one nominal radiance row from already-prefetched high-resolution radiance results.           |
    //                                                                                                         |
    // data flow                                                                                               |
    //   row_ref.start -> sample_indices[start..start + count] -> results[result_index]                        |
    //                                                                                                         |
    // math                                                                                                    |
    //   L_i     = sum_j weight_ij * L(lambda_i + offset_ij)                                                   |
    //   dL_i/dx = sum_j weight_ij * dL(lambda_i + offset_ij)/dx for active derivative states                  |
    //                                                                                                         |
    // disabled-kernel row                                                                                     |
    //   count = 1, weight = 1, offset = 0. The function returns the single prefetched result directly.        |
    //                                                                                                         |
    // integrated row                                                                                          |
    //   The instrument integration builder already normalized the weights. This loop applies them exactly     |
    //   once and does not renormalize.                                                                        |
    // --------------------------------------------------------------------------------------------------------|
    const start: usize = @intCast(row_ref.start);
    const count = integration.activeSampleCount();
    if (count == 0 or start > sample_indices.len or count > sample_indices.len - start) {
        return error.ShapeMismatch;
    }
    const indices = sample_indices[start .. start + count];

    if (!integration.enabled()) {
        const result_index: usize = @intCast(indices[0]);
        if (result_index >= results.len) return error.ShapeMismatch;
        return results[result_index];
    }

    const samples = integration.samples(kernel_storage);
    if (samples.weights.len != indices.len) return error.ShapeMismatch;

    var radiance_sum: f64 = 0.0;
    var jacobian_sum = jacobian_states.zero();
    const active_state_count = jacobian_states.activeStateCount(solve_config.derivative_state_mask);
    const wants_jacobian = solve_config.derivative_mode != .none and active_state_count != 0;
    for (indices, samples.weights) |result_index_u32, weight| {
        const result_index: usize = @intCast(result_index_u32);
        if (result_index >= results.len) return error.ShapeMismatch;
        const sample = results[result_index];
        radiance_sum += weight * sample.radiance;
        if (wants_jacobian) {
            jacobian_states.addScaledMasked(
                &jacobian_sum,
                sample.jacobian,
                weight,
                solve_config.derivative_state_mask,
            );
        }
    }

    return .{
        .radiance = radiance_sum,
        .jacobian = jacobian_sum,
    };
}

comptime {
    std.debug.assert(@sizeOf(RadianceResult) == 24);
}
