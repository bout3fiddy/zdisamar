const std = @import("std");
const calibration = @import("../../kernels/spectra/calibration.zig");
const BuiltinLineShapeKind = @import("../../model/Instrument.zig").BuiltinLineShapeKind;
const max_line_shape_samples = @import("../../model/Instrument.zig").max_line_shape_samples;
const Scene = @import("../../model/Scene.zig").Scene;

pub const default_integration_sample_count: usize = 5;
pub const max_integration_sample_count: usize = max_line_shape_samples;

pub const IntegrationKernel = struct {
    enabled: bool,
    sample_count: usize,
    offsets_nm: [max_integration_sample_count]f64,
    weights: [max_integration_sample_count]f64,
};

pub const Provider = struct {
    id: []const u8,
    calibrationForScene: *const fn (scene: *const Scene) calibration.Calibration,
    usesIntegratedSampling: *const fn (scene: *const Scene) bool,
    integrationForWavelength: *const fn (scene: *const Scene, nominal_wavelength_nm: f64, kernel: *IntegrationKernel) void,
    slitKernelForScene: *const fn (scene: *const Scene) [5]f64,
};

pub fn resolve(provider_id: []const u8) ?Provider {
    if (std.mem.eql(u8, provider_id, "builtin.generic_response")) {
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

fn calibrationForScene(scene: *const Scene) calibration.Calibration {
    return .{
        .gain = scene.observation_model.multiplicative_offset,
        .offset = 0.0,
        .wavelength_shift_nm = scene.observation_model.wavelength_shift_nm,
        .stray_light = scene.observation_model.stray_light,
    };
}

fn usesIntegratedInstrumentSampling(scene: *const Scene) bool {
    const mode_requires_native_integration = switch (scene.observation_model.sampling) {
        .operational, .measured_channels => true,
        .native, .synthetic => false,
    };
    return mode_requires_native_integration or
        scene.observation_model.instrument_line_fwhm_nm > 0.0 or
        scene.observation_model.instrument_line_shape.sample_count > 0 or
        scene.observation_model.instrument_line_shape_table.nominal_count > 0;
}

fn integrationForWavelength(scene: *const Scene, nominal_wavelength_nm: f64, kernel: *IntegrationKernel) void {
    resetKernel(kernel);
    if (!usesIntegratedInstrumentSampling(scene)) {
        kernel.sample_count = 1;
        return;
    }

    if (scene.observation_model.instrument_line_shape_table.nominal_count > 0) {
        kernel.sample_count = scene.observation_model.instrument_line_shape_table.writeNormalizedKernelForNominal(
            nominal_wavelength_nm,
            kernel.offsets_nm[0..],
            kernel.weights[0..],
        );
        if (kernel.sample_count == 0) {
            resetKernel(kernel);
            kernel.enabled = true;
            kernel.sample_count = 1;
            kernel.weights[0] = 1.0;
            return;
        }
        kernel.enabled = true;
        return;
    }

    if (scene.observation_model.instrument_line_shape.sample_count > 0) {
        kernel.sample_count = scene.observation_model.instrument_line_shape.writeNormalizedKernel(
            kernel.offsets_nm[0..],
            kernel.weights[0..],
        );
        if (kernel.sample_count == 0) {
            resetKernel(kernel);
            kernel.enabled = true;
            kernel.sample_count = 1;
            kernel.weights[0] = 1.0;
            return;
        }
        kernel.enabled = true;
        return;
    }

    if (scene.observation_model.high_resolution_step_nm > 0.0 and scene.observation_model.high_resolution_half_span_nm > 0.0) {
        const step_nm = scene.observation_model.high_resolution_step_nm;
        const half_span_nm = scene.observation_model.high_resolution_half_span_nm;
        const shape = scene.observation_model.builtin_line_shape;
        var sample_count: usize = 0;
        var offset_nm = -half_span_nm;
        while (offset_nm <= half_span_nm + (step_nm * 0.5) and sample_count < max_integration_sample_count) : (offset_nm += step_nm) {
            kernel.offsets_nm[sample_count] = offset_nm;
            kernel.weights[sample_count] = builtinLineShapeWeight(
                shape,
                scene.observation_model.instrument_line_fwhm_nm,
                offset_nm,
            );
            sample_count += 1;
        }
        if (sample_count == 0) sample_count = 1;
        var total_weight: f64 = 0.0;
        for (0..sample_count) |index| total_weight += kernel.weights[index];
        if (total_weight <= 0.0) {
            resetKernel(kernel);
            kernel.offsets_nm[0] = 0.0;
            kernel.weights[0] = 1.0;
            sample_count = 1;
        } else {
            for (0..sample_count) |index| kernel.weights[index] /= total_weight;
        }
        kernel.enabled = true;
        kernel.sample_count = sample_count;
        return;
    }

    switch (scene.observation_model.sampling) {
        .operational, .measured_channels => {
            kernel.sample_count = 1;
            return;
        },
        .native, .synthetic => {},
    }

    const default_half_span_nm = defaultKernelHalfSpanNm(scene.observation_model.instrument_line_fwhm_nm);
    const offsets_nm: [default_integration_sample_count]f64 = .{
        -default_half_span_nm,
        -0.5 * default_half_span_nm,
        0.0,
        0.5 * default_half_span_nm,
        default_half_span_nm,
    };

    var total_weight: f64 = 0.0;
    for (offsets_nm, 0..) |offset_nm, index| {
        kernel.offsets_nm[index] = offset_nm;
        kernel.weights[index] = builtinLineShapeWeight(
            scene.observation_model.builtin_line_shape,
            scene.observation_model.instrument_line_fwhm_nm,
            offset_nm,
        );
        total_weight += kernel.weights[index];
    }
    for (0..default_integration_sample_count) |index| kernel.weights[index] /= total_weight;
    kernel.enabled = true;
    kernel.sample_count = default_integration_sample_count;
}

fn resetKernel(kernel: *IntegrationKernel) void {
    kernel.enabled = false;
    kernel.sample_count = 0;
    @memset(kernel.offsets_nm[0..], 0.0);
    @memset(kernel.weights[0..], 0.0);
}

fn slitKernelForScene(scene: *const Scene) [5]f64 {
    if (scene.observation_model.instrument_line_fwhm_nm <= 0.0) {
        return .{ 1.0, 4.0, 6.0, 4.0, 1.0 };
    }

    const sample_spacing_nm = if (scene.spectral_grid.sample_count <= 1)
        1.0
    else
        (scene.spectral_grid.end_nm - scene.spectral_grid.start_nm) / @as(f64, @floatFromInt(scene.spectral_grid.sample_count - 1));
    var kernel: [5]f64 = undefined;
    var sum: f64 = 0.0;
    for (0..kernel.len) |index| {
        const offset_samples = @as(f64, @floatFromInt(@as(i32, @intCast(index)) - 2));
        const offset_nm = offset_samples * sample_spacing_nm;
        const value = builtinLineShapeWeight(
            scene.observation_model.builtin_line_shape,
            scene.observation_model.instrument_line_fwhm_nm,
            offset_nm,
        );
        kernel[index] = value;
        sum += value;
    }
    for (&kernel) |*value| value.* /= sum;
    return kernel;
}

fn defaultKernelHalfSpanNm(fwhm_nm: f64) f64 {
    return @max(3.0 * @max(fwhm_nm, 1.0e-4), 1.0e-4);
}

fn builtinLineShapeWeight(shape: BuiltinLineShapeKind, fwhm_nm: f64, offset_nm: f64) f64 {
    const safe_fwhm_nm = @max(fwhm_nm, 1.0e-4);
    return switch (shape) {
        .gaussian => {
            const sigma_nm = safe_fwhm_nm / 2.354820045;
            return @exp(-0.5 * std.math.pow(f64, offset_nm / sigma_nm, 2.0));
        },
        .flat_top_n4 => flatTopN4Weight(safe_fwhm_nm, offset_nm),
        .triple_flat_top_n4 => flatTopN4Weight(safe_fwhm_nm, offset_nm) +
            flatTopN4Weight(safe_fwhm_nm, offset_nm - 0.1) +
            flatTopN4Weight(safe_fwhm_nm, offset_nm + 0.1),
    };
}

fn flatTopN4Weight(fwhm_nm: f64, offset_nm: f64) f64 {
    const w_nm = fwhm_nm / 1.681793;
    return std.math.pow(f64, 2.0, -2.0 * std.math.pow(f64, offset_nm / @max(w_nm, 1.0e-6), 4.0));
}

test "high-resolution integration retains the full symmetric sampling span" {
    const scene: Scene = .{
        .spectral_grid = .{
            .start_nm = 758.0,
            .end_nm = 771.0,
            .sample_count = 1301,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 0.40,
        },
    };

    var kernel: IntegrationKernel = undefined;
    integrationForWavelength(&scene, 760.5, &kernel);
    try std.testing.expect(kernel.enabled);
    try std.testing.expectEqual(@as(usize, 81), kernel.sample_count);
    try std.testing.expectApproxEqAbs(@as(f64, -0.40), kernel.offsets_nm[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.40), kernel.offsets_nm[kernel.sample_count - 1], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), kernel.offsets_nm[kernel.sample_count / 2], 1e-12);
    try std.testing.expectApproxEqAbs(kernel.weights[0], kernel.weights[kernel.sample_count - 1], 1e-12);
}

test "flat-top line shape spreads weight more broadly than gaussian for the same FWHM" {
    const gaussian_scene: Scene = .{
        .spectral_grid = .{
            .start_nm = 758.0,
            .end_nm = 771.0,
            .sample_count = 1301,
        },
        .observation_model = .{
            .instrument = .{ .custom = "compare" },
            .sampling = .native,
            .noise_model = .none,
            .instrument_line_fwhm_nm = 0.38,
            .builtin_line_shape = .gaussian,
            .high_resolution_step_nm = 0.19,
            .high_resolution_half_span_nm = 1.14,
        },
    };
    const flat_top_scene: Scene = .{
        .spectral_grid = gaussian_scene.spectral_grid,
        .observation_model = .{
            .instrument = .{ .custom = "compare" },
            .sampling = .native,
            .noise_model = .none,
            .instrument_line_fwhm_nm = 0.38,
            .builtin_line_shape = .flat_top_n4,
            .high_resolution_step_nm = 0.19,
            .high_resolution_half_span_nm = 1.14,
        },
    };

    var gaussian_kernel: IntegrationKernel = undefined;
    integrationForWavelength(&gaussian_scene, 760.5, &gaussian_kernel);
    var flat_top_kernel: IntegrationKernel = undefined;
    integrationForWavelength(&flat_top_scene, 760.5, &flat_top_kernel);

    try std.testing.expectEqual(gaussian_kernel.sample_count, flat_top_kernel.sample_count);
    try std.testing.expect(flat_top_kernel.weights[flat_top_kernel.sample_count / 2] < gaussian_kernel.weights[gaussian_kernel.sample_count / 2]);
    try std.testing.expect(flat_top_kernel.weights[0] > gaussian_kernel.weights[0]);
}

test "measured-channel sampling bypasses legacy post-convolution even without explicit slit metadata" {
    const scene: Scene = .{
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 761.2,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .{ .custom = "measured" },
            .sampling = .measured_channels,
            .noise_model = .snr_from_input,
            .measured_wavelengths_nm = &.{ 760.81, 761.03, 761.19 },
            .ingested_noise_sigma = &.{ 0.02, 0.02, 0.02 },
        },
    };

    try std.testing.expect(usesIntegratedInstrumentSampling(&scene));

    var kernel: IntegrationKernel = undefined;
    integrationForWavelength(&scene, 761.03, &kernel);
    try std.testing.expectEqual(@as(usize, 1), kernel.sample_count);
    try std.testing.expect(!kernel.enabled);
}
