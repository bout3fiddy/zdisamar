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
    scene: Scene,
    line_list: ReferenceData.SpectroscopyLineList,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
) LineBandMeans {
    const sample_count = @max(scene.spectral_grid.sample_count, @as(u32, 1));
    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const wavelength_step = if (sample_count <= 1) 0.0 else span_nm / @as(f64, @floatFromInt(sample_count - 1));

    var line_sum: f64 = 0.0;
    var line_mixing_sum: f64 = 0.0;
    for (0..sample_count) |index| {
        const wavelength_nm = scene.spectral_grid.start_nm + wavelength_step * @as(f64, @floatFromInt(index));
        const evaluation = line_list.evaluateAt(
            wavelength_nm,
            @max(effective_temperature_k, 150.0),
            @max(effective_pressure_hpa, 1.0),
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
    scene: Scene,
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
