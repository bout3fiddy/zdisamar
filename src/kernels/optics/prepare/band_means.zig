const std = @import("std");
const Scene = @import("../../../model/Scene.zig").Scene;
const ReferenceData = @import("../../../model/ReferenceData.zig");
const OperationalReferenceGrid = @import("../../../model/Instrument.zig").OperationalReferenceGrid;
const OperationalCrossSectionLut = @import("../../../model/Instrument.zig").OperationalCrossSectionLut;

pub const LineBandMeans = struct {
    line_mean_cross_section_cm2_per_molecule: f64 = 0.0,
    line_mixing_mean_cross_section_cm2_per_molecule: f64 = 0.0,
};

pub fn computeBandLineMeans(
    allocator: std.mem.Allocator,
    scene: *const Scene,
    line_list: *const ReferenceData.SpectroscopyLineList,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
) !LineBandMeans {
    const sample_count = @max(scene.spectral_grid.sample_count, @as(u32, 1));
    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const wavelength_step = if (sample_count <= 1) 0.0 else span_nm / @as(f64, @floatFromInt(sample_count - 1));
    var prepared_state = try line_list.prepareStrongLineState(
        allocator,
        @max(effective_temperature_k, 150.0),
        @max(effective_pressure_hpa, 1.0),
    );
    defer if (prepared_state) |*state| state.deinit(allocator);

    var line_sum: f64 = 0.0;
    var line_mixing_sum: f64 = 0.0;
    for (0..sample_count) |index| {
        const wavelength_nm = scene.spectral_grid.start_nm + wavelength_step * @as(f64, @floatFromInt(index));
        const evaluation = line_list.evaluateAtPrepared(
            wavelength_nm,
            @max(effective_temperature_k, 150.0),
            @max(effective_pressure_hpa, 1.0),
            if (prepared_state) |*state| state else null,
        );
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
    if (scene.observation_model.operational_refspec_grid.enabled()) {
        return computeWeightedOperationalBandMean(
            scene.observation_model.operational_refspec_grid,
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
    if (values.len == 0 or values.len != weights.len) return 0.0;

    var numerator: f64 = 0.0;
    var denominator: f64 = 0.0;
    for (values, weights) |value, weight| {
        numerator += value * weight;
        denominator += weight;
    }
    return numerator / @max(denominator, 1.0e-12);
}

test "band means support generic weighted fit windows" {
    const values = [_]f64{ 1.0, 3.0, 5.0 };
    const weights = [_]f64{ 1.0, 2.0, 1.0 };
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), computeWeightedWindowMean(&values, &weights), 1.0e-12);
}
