const std = @import("std");

const telemetry = @import("../instrumentation/telemetry.zig");

pub const Error = error{
    ShapeMismatch,
    InvalidSolarCosine,
};

// instrument_average.zig ------------------------------------------------------------------------------------ |
// Product-grid radiance, irradiance, and reflectance assembly helpers.                                        |
//                                                                                                             |
// provenance                                                                                                  |
//   `assembleReflectance` ports the old final conversion from main:                                           |
//   `src/forward_model/instrument_grid/grid_calculation/simulate.zig` `assembleReflectance`.                  |
//                                                                                                             |
// boundary                                                                                                    |
//   Earlier spectrum steps gather calibrated radiance and irradiance on the public product grid. This file    |
//   performs the shared final conversion and summary accounting. It does not own wavelength planning, solar   |
//   lookup, convolution, or calibration tables.                                                               |
// ------------------------------------------------------------------------------------------------------------|

// reflectance_denominator_floor ----------------------------------------------------------------------------- |
// Minimum denominator for top-of-atmosphere reflectance conversion.                                           |
//                                                                                                             |
// provenance                                                                                                  |
//   Old `simulate.zig` clamps `irradiance * mu0` to `1e-9` before dividing radiance by the solar denominator. |
//   Telemetry still records how often raw denominators cross that guard.                                      |
pub const reflectance_denominator_floor: f64 = 1.0e-9;
// ------------------------------------------------------------------------------------------------------------|

// ReflectanceAssemblySummary -------------------------------------------------------------------------------- |
// Per-spectrum summary from radiance/irradiance-to-reflectance conversion.                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 56 B (0.055 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] radiance_sum           : f64                                                                       |
// [ 8..15] irradiance_sum         : f64                                                                       |
// [16..23] reflectance_sum        : f64                                                                       |
// [24..31] min_denominator        : f64                                                                       |
// [32..39] max_reflectance        : f64                                                                       |
// [40..47] sample_count           : usize                                                                     |
// [48..55] denominator_clamp_count: usize                                                                     |
pub const ReflectanceAssemblySummary = struct {
    radiance_sum: f64 = 0.0,
    irradiance_sum: f64 = 0.0,
    reflectance_sum: f64 = 0.0,
    min_denominator: f64 = 0.0,
    max_reflectance: f64 = 0.0,
    sample_count: usize = 0,
    denominator_clamp_count: usize = 0,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn assembleReflectance(
    solar_cosine: f64,
    radiance: []const f64,
    irradiance: []const f64,
    out_reflectance: []f64,
) Error!ReflectanceAssemblySummary {
    // assembleReflectance ----------------------------------------------------------------------------------- |
    // Convert calibrated radiance and irradiance into top-of-atmosphere reflectance for each output sample.   |
    //                                                                                                         |
    // math                                                                                                    |
    //   rho_i = pi * L_i / max(E0_i * mu0, 1e-9)                                                              |
    //                                                                                                         |
    // relation to forward scaling                                                                             |
    //   The forward radiance prefetch uses L = rho * mu0 * E0 / pi. This step inverts that convention after   |
    //   instrument sampling has produced calibrated radiance and irradiance on the product grid.              |
    //                                                                                                         |
    // numerical guard                                                                                         |
    //   The `1e-9` floor prevents Inf/NaN reflectance when irradiance is near zero. Telemetry reports how     |
    //   often the raw denominator crossed the guard.                                                          |
    // --------------------------------------------------------------------------------------------------------|
    if (radiance.len != irradiance.len or radiance.len != out_reflectance.len) return error.ShapeMismatch;
    if (!std.math.isFinite(solar_cosine)) return error.InvalidSolarCosine;

    var min_denominator: f64 = 0.0;
    var max_reflectance: f64 = 0.0;
    if (radiance.len != 0) {
        min_denominator = std.math.inf(f64);
        max_reflectance = -std.math.inf(f64);
    }

    var summary = ReflectanceAssemblySummary{
        .sample_count = radiance.len,
        .min_denominator = min_denominator,
        .max_reflectance = max_reflectance,
    };

    for (radiance, irradiance, out_reflectance) |radiance_value, irradiance_value, *reflectance| {
        const denominator_raw = irradiance_value * solar_cosine;
        const denominator = @max(denominator_raw, reflectance_denominator_floor);
        reflectance.* = (radiance_value * std.math.pi) / denominator;

        if (denominator_raw <= reflectance_denominator_floor) summary.denominator_clamp_count += 1;
        summary.min_denominator = @min(summary.min_denominator, denominator_raw);
        summary.max_reflectance = @max(summary.max_reflectance, reflectance.*);
        summary.radiance_sum += radiance_value;
        summary.irradiance_sum += irradiance_value;
        summary.reflectance_sum += reflectance.*;
    }

    // instrumentation: calculation telemetry: reflectance assembly -----------------------------------------  |
    // captures: denominator clamps and final reflectance extrema                                              |
    // why: preserves old simulate.reflectanceAssembly telemetry for numerical guard analysis.                 |
    telemetry.reflectanceAssembly(
        summary.sample_count,
        summary.denominator_clamp_count,
        summary.min_denominator,
        summary.max_reflectance,
    );
    // end instrumentation: calculation telemetry: reflectance assembly -------------------------------------  |

    return summary;
}

comptime {
    std.debug.assert(@sizeOf(ReflectanceAssemblySummary) == 56);
}
