const std = @import("std");
const calibration = @import("../../kernels/spectra/calibration.zig");
const max_line_shape_samples = @import("../../model/Instrument.zig").max_line_shape_samples;
const Scene = @import("../../model/Scene.zig").Scene;

pub const default_integration_sample_count: usize = 5;
pub const max_integration_sample_count: usize = 17;

pub const IntegrationKernel = struct {
    enabled: bool,
    sample_count: usize,
    offsets_nm: [max_integration_sample_count]f64,
    weights: [max_integration_sample_count]f64,
};

pub const Provider = struct {
    id: []const u8,
    calibrationForScene: *const fn (scene: Scene) calibration.Calibration,
    usesIntegratedSampling: *const fn (scene: Scene) bool,
    integrationForWavelength: *const fn (scene: Scene, nominal_wavelength_nm: f64) IntegrationKernel,
    slitKernelForScene: *const fn (scene: Scene) [5]f64,
};

pub fn resolve(provider_id: []const u8) ?Provider {
    if (std.mem.eql(u8, provider_id, "builtin.generic_response")) {
        return genericProvider(provider_id);
    }
    if (std.mem.eql(u8, provider_id, "builtin.tropomi_response")) {
        return genericProvider(provider_id);
    }
    return null;
}

fn genericProvider(provider_id: []const u8) Provider {
    return .{
        .id = provider_id,
        .calibrationForScene = calibrationForScene,
        .usesIntegratedSampling = usesIntegratedInstrumentSampling,
        .integrationForWavelength = integrationForWavelength,
        .slitKernelForScene = slitKernelForScene,
    };
}

fn calibrationForScene(scene: Scene) calibration.Calibration {
    return .{
        .gain = switch (scene.observation_model.regime) {
            .nadir => 1.0,
            .limb => 1.04,
            .occultation => 1.02,
        },
        .offset = 0.0,
        .wavelength_shift_nm = if (scene.observation_model.wavelength_shift_nm != 0.0)
            scene.observation_model.wavelength_shift_nm
        else if (std.mem.eql(u8, scene.observation_model.sampling, "operational"))
            0.02
        else
            0.0,
    };
}

fn usesIntegratedInstrumentSampling(scene: Scene) bool {
    return scene.observation_model.instrument_line_fwhm_nm > 0.0 or
        scene.observation_model.instrument_line_shape.sample_count > 0 or
        scene.observation_model.instrument_line_shape_table.nominal_count > 0;
}

fn integrationForWavelength(scene: Scene, nominal_wavelength_nm: f64) IntegrationKernel {
    if (!usesIntegratedInstrumentSampling(scene)) {
        return .{
            .enabled = false,
            .sample_count = 1,
            .offsets_nm = [_]f64{0.0} ** max_integration_sample_count,
            .weights = [_]f64{0.0} ** max_integration_sample_count,
        };
    }

    if (scene.observation_model.instrument_line_shape_table.nearestNominalIndex(nominal_wavelength_nm)) |nominal_index| {
        const table = scene.observation_model.instrument_line_shape_table;
        var offsets_nm = [_]f64{0.0} ** max_integration_sample_count;
        var weights = [_]f64{0.0} ** max_integration_sample_count;
        const sample_count = @min(@as(usize, table.sample_count), max_line_shape_samples);
        var weight_sum: f64 = 0.0;
        for (0..sample_count) |index| {
            offsets_nm[index] = table.offsets_nm[index];
            weights[index] = table.weightAt(nominal_index, index);
            weight_sum += weights[index];
        }
        if (weight_sum > 0.0) {
            for (0..sample_count) |index| weights[index] /= weight_sum;
        } else {
            weights[0] = 1.0;
            return .{
                .enabled = true,
                .sample_count = 1,
                .offsets_nm = offsets_nm,
                .weights = weights,
            };
        }
        return .{
            .enabled = true,
            .sample_count = sample_count,
            .offsets_nm = offsets_nm,
            .weights = weights,
        };
    }

    if (scene.observation_model.instrument_line_shape.sample_count > 0) {
        var offsets_nm = [_]f64{0.0} ** max_integration_sample_count;
        var weights = [_]f64{0.0} ** max_integration_sample_count;
        const sample_count = @min(
            @as(usize, scene.observation_model.instrument_line_shape.sample_count),
            max_line_shape_samples,
        );
        var weight_sum: f64 = 0.0;
        for (0..sample_count) |index| {
            offsets_nm[index] = scene.observation_model.instrument_line_shape.offsets_nm[index];
            weights[index] = scene.observation_model.instrument_line_shape.weights[index];
            weight_sum += weights[index];
        }
        if (weight_sum > 0.0) {
            for (0..sample_count) |index| weights[index] /= weight_sum;
        } else {
            weights[0] = 1.0;
            return .{
                .enabled = true,
                .sample_count = 1,
                .offsets_nm = offsets_nm,
                .weights = weights,
            };
        }
        return .{
            .enabled = true,
            .sample_count = sample_count,
            .offsets_nm = offsets_nm,
            .weights = weights,
        };
    }

    if (scene.observation_model.high_resolution_step_nm > 0.0 and scene.observation_model.high_resolution_half_span_nm > 0.0) {
        var offsets_nm = [_]f64{0.0} ** max_integration_sample_count;
        var weights = [_]f64{0.0} ** max_integration_sample_count;
        const sigma_nm = @max(scene.observation_model.instrument_line_fwhm_nm / 2.354820045, 1.0e-4);
        const step_nm = scene.observation_model.high_resolution_step_nm;
        const half_span_nm = scene.observation_model.high_resolution_half_span_nm;
        var sample_count: usize = 0;
        var offset_nm = -half_span_nm;
        while (offset_nm <= half_span_nm + (step_nm * 0.5) and sample_count < max_integration_sample_count) : (offset_nm += step_nm) {
            offsets_nm[sample_count] = offset_nm;
            weights[sample_count] = @exp(-0.5 * std.math.pow(f64, offset_nm / sigma_nm, 2.0));
            sample_count += 1;
        }
        if (sample_count == 0) sample_count = 1;
        var total_weight: f64 = 0.0;
        for (0..sample_count) |index| total_weight += weights[index];
        if (total_weight <= 0.0) {
            offsets_nm[0] = 0.0;
            weights[0] = 1.0;
            sample_count = 1;
        } else {
            for (0..sample_count) |index| weights[index] /= total_weight;
        }
        return .{
            .enabled = true,
            .sample_count = sample_count,
            .offsets_nm = offsets_nm,
            .weights = weights,
        };
    }

    const sigma_nm = @max(scene.observation_model.instrument_line_fwhm_nm / 2.354820045, 1.0e-4);
    const offsets_nm: [default_integration_sample_count]f64 = .{
        -2.0 * sigma_nm,
        -1.0 * sigma_nm,
        0.0,
        1.0 * sigma_nm,
        2.0 * sigma_nm,
    };

    var full_offsets_nm = [_]f64{0.0} ** max_integration_sample_count;
    var weights = [_]f64{0.0} ** max_integration_sample_count;
    var total_weight: f64 = 0.0;
    for (offsets_nm, 0..) |offset_nm, index| {
        full_offsets_nm[index] = offset_nm;
        weights[index] = @exp(-0.5 * std.math.pow(f64, offset_nm / sigma_nm, 2.0));
        total_weight += weights[index];
    }
    for (0..default_integration_sample_count) |index| weights[index] /= total_weight;

    return .{
        .enabled = true,
        .sample_count = default_integration_sample_count,
        .offsets_nm = full_offsets_nm,
        .weights = weights,
    };
}

fn slitKernelForScene(scene: Scene) [5]f64 {
    if (scene.observation_model.instrument_line_fwhm_nm <= 0.0) {
        return .{ 1.0, 4.0, 6.0, 4.0, 1.0 };
    }

    const sample_spacing_nm = if (scene.spectral_grid.sample_count <= 1)
        1.0
    else
        (scene.spectral_grid.end_nm - scene.spectral_grid.start_nm) / @as(f64, @floatFromInt(scene.spectral_grid.sample_count - 1));
    const sigma_samples = std.math.clamp(
        scene.observation_model.instrument_line_fwhm_nm / @max(sample_spacing_nm, 1e-6) / 2.354820045,
        0.3,
        2.5,
    );

    var kernel: [5]f64 = undefined;
    var sum: f64 = 0.0;
    for (0..kernel.len) |index| {
        const offset = @as(f64, @floatFromInt(@as(i32, @intCast(index)) - 2));
        const value = @exp(-0.5 * std.math.pow(f64, offset / sigma_samples, 2.0));
        kernel[index] = value;
        sum += value;
    }
    for (&kernel) |*value| value.* /= sum;
    return kernel;
}
