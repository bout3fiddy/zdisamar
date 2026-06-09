const std = @import("std");
const Scene = @import("../../../input/Scene.zig").Scene;
const ReferenceData = @import("../../../input/ReferenceData.zig");
const LineListEval = @import("../../../input/reference/spectroscopy/line_list.zig");
const OperationalReferenceGrid = @import("../../../input/Instrument.zig").OperationalReferenceGrid;
const OperationalCrossSectionLut = @import("../../../input/Instrument.zig").OperationalCrossSectionLut;

// band_means.zig --------------------------------------------------------------------------------------------   |
// Computes wavelength-band mean cross sections used during absorber preparation.                                |
//                                                                                                               |
// hot path                                                                                                      |
//   Band means move repeated spectroscopy work out of layer accumulation. The returned two-field row is kept    |
//   small because absorber setup only needs the mean line and line-mixing cross sections.                       |
// ------------------------------------------------------------------------------------------------------------  |

// LineBandMeans ---------------------------------------------------------------------------------------------   |
// Mean line and line-mixing cross sections over one spectral band.                                              |
//                                                                                                               |
// layout(64-bit)                                                                                                |
// size: 16 B (0.016 KiB), align: 8 B                                                                            |
//                                                                                                               |
// memory                                                                                                        |
// [ 0.. 7] line_mean_cross_section_cm2_per_molecule        : f64                                                |
// [ 8..15] line_mixing_mean_cross_section_cm2_per_molecule : f64                                                |
//                                                                                                               |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                        |
// cache span: 1 cache line at 64 B per line                                                                     |
// footprint: per instance = 16 B; stack return value                                                            |
pub const LineBandMeans = struct {
    line_mean_cross_section_cm2_per_molecule: f64 = 0.0,
    line_mixing_mean_cross_section_cm2_per_molecule: f64 = 0.0,
};
// ------------------------------------------------------------------------------------------------------------  |

pub fn computeBandLineMeans(
    allocator: std.mem.Allocator,
    scene: *const Scene,
    line_list: *const ReferenceData.SpectroscopyLineList,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
) !LineBandMeans {
    // computeBandLineMeans ----------------------------------------------------------------------------------   |
    // Scans the spectral grid and accumulates mean line spectroscopy values for one band.                       |
    //                                                                                                           |
    // hot path                                                                                                  |
    //   Runs in absorber preparation. Strong-line and weak-line prepared states are built once here and         |
    //   reused across the wavelength samples in this mean.                                                      |
    //                                                                                                           |
    // math                                                                                                      |
    //   mean_sigma = sum_i sigma(lambda_i, T, p) / N                                                            |
    // -------------------------------------------------------------------------------------------------------   |

    const sample_count = @max(scene.spectral_grid.sample_count, @as(u32, 1));
    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const wavelength_step = if (sample_count <= 1) 0.0 else span_nm / @as(f64, @floatFromInt(sample_count - 1));
    var prepared_state = try line_list.prepareStrongLineState(
        allocator,
        @max(effective_temperature_k, 150.0),
        @max(effective_pressure_hpa, 1.0),
    );
    defer if (prepared_state) |*state| state.deinit(allocator);

    var prepared_weak_state = prepare_weak_state: {
        if (prepared_state == null) break :prepare_weak_state null;

        break :prepare_weak_state try line_list.prepareWeakLineState(
            allocator,
            @max(effective_temperature_k, 150.0),
            @max(effective_pressure_hpa, 1.0),
        );
    };
    defer if (prepared_weak_state) |*state| state.deinit(allocator);

    var line_sum: f64 = 0.0;
    var line_mixing_sum: f64 = 0.0;
    for (0..sample_count) |index| {
        const wavelength_nm = scene.spectral_grid.start_nm + wavelength_step * @as(f64, @floatFromInt(index));
        const evaluation = evaluate_sample: {
            if (prepared_state) |*state| {
                var anchor_storage: [ReferenceData.max_strong_line_sidecars]ReferenceData.StrongLineAnchorIndex =
                    undefined;
                const window = LineListEval.prepareStrongLineWavelengthWindow(
                    line_list.*,
                    wavelength_nm,
                    &anchor_storage,
                );

                break :evaluate_sample LineListEval.totalSigmaWithPreparedStrongLineStateAndWindow(
                    line_list.*,
                    wavelength_nm,
                    @max(effective_temperature_k, 150.0),
                    @max(effective_pressure_hpa, 1.0),
                    state,
                    if (prepared_weak_state) |*weak_state| weak_state else null,
                    &window,
                );
            }

            break :evaluate_sample line_list.evaluateAtPrepared(
                wavelength_nm,
                @max(effective_temperature_k, 150.0),
                @max(effective_pressure_hpa, 1.0),
                null,
            );
        };
        line_sum += evaluation.line_sigma_cm2_per_molecule;
        line_mixing_sum += evaluation.line_mixing_sigma_cm2_per_molecule;
    }

    return .{
        .line_mean_cross_section_cm2_per_molecule = line_sum / @as(f64, @floatFromInt(sample_count)),
        .line_mixing_mean_cross_section_cm2_per_molecule = line_mixing_sum / @as(f64, @floatFromInt(sample_count)),
    };
}

pub fn computeOperationalBandMean(
    scene: *const Scene,
    lut: OperationalCrossSectionLut,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
) f64 {
    // computeOperationalBandMean ------------------------------------------------------------------------------ |
    // Returns the operational O2/O2-O2 band mean for the active observation support.                            |
    //                                                                                                           |
    // math                                                                                                      |
    //   unweighted mean = sum_i sigma(lambda_i, T, p) / N                                                       |
    // --------------------------------------------------------------------------------------------------------  |

    const operational_band_support = scene.observation_model.primaryOperationalBandSupport();
    if (operational_band_support.operational_refspec_grid.enabled()) {
        return computeWeightedOperationalBandMean(
            operational_band_support.operational_refspec_grid,
            lut,
            effective_temperature_k,
            effective_pressure_hpa,
        );
    }

    const sample_count = @max(scene.spectral_grid.sample_count, @as(u32, 1));
    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const wavelength_step = if (sample_count <= 1) 0.0 else span_nm / @as(f64, @floatFromInt(sample_count - 1));

    var sigma_sum: f64 = 0.0;
    for (0..sample_count) |index| {
        const wavelength_nm = scene.spectral_grid.start_nm + wavelength_step * @as(f64, @floatFromInt(index));
        sigma_sum += lut.sigmaAt(
            wavelength_nm,
            @max(effective_temperature_k, 150.0),
            @max(effective_pressure_hpa, 1.0),
        );
    }

    return sigma_sum / @as(f64, @floatFromInt(sample_count));
}

pub fn computeWeightedOperationalBandMean(
    refspec_grid: OperationalReferenceGrid,
    lut: OperationalCrossSectionLut,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
) f64 {
    // computeWeightedOperationalBandMean ---------------------------------------------------------------------- |
    // Computes the reference-spectrum weighted operational mean.                                                |
    //                                                                                                           |
    // math                                                                                                      |
    //   weighted mean = sum_i weight_i * sigma(lambda_i, T, p) / sum_i weight_i                                 |
    // --------------------------------------------------------------------------------------------------------  |

    var sigma_sum: f64 = 0.0;
    var weight_sum: f64 = 0.0;
    for (refspec_grid.wavelengths_nm, refspec_grid.weights) |wavelength_nm, weight| {
        sigma_sum += weight * lut.sigmaAt(
            wavelength_nm,
            @max(effective_temperature_k, 150.0),
            @max(effective_pressure_hpa, 1.0),
        );
        weight_sum += weight;
    }

    return sigma_sum / @max(weight_sum, 1e-12);
}

pub fn computeWeightedWindowMean(values: []const f64, weights: []const f64) f64 {
    // computeWeightedWindowMean ------------------------------------------------------------------------------- |
    // Generic weighted mean helper for already sampled window values.                                           |
    //                                                                                                           |
    // math                                                                                                      |
    //   mean = sum_i value_i * weight_i / sum_i weight_i                                                        |
    // --------------------------------------------------------------------------------------------------------  |

    if (values.len == 0 or values.len != weights.len) return 0.0;

    var numerator: f64 = 0.0;
    var denominator: f64 = 0.0;
    for (values, weights) |value, weight| {
        numerator += value * weight;
        denominator += weight;
    }

    return numerator / @max(denominator, 1.0e-12);
}
