const std = @import("std");
const adaptive_cache = @import("adaptive_cache.zig");
const adaptive_plan = @import("adaptive_plan.zig");
const response_support = @import("response.zig");
const types = @import("types.zig");
const PreparedOpticalState = @import("../../../kernels/optics/preparation.zig").PreparedOpticalState;
const InstrumentModel = @import("../../../model/Instrument.zig").Instrument;
const Scene = @import("../../../model/Scene.zig").Scene;
const SpectralChannel = @import("../../../model/Instrument.zig").SpectralChannel;

pub const IntegrationKernel = types.IntegrationKernel;
pub const default_integration_sample_count = types.default_integration_sample_count;
pub const max_integration_sample_count = types.max_integration_sample_count;
pub const AdaptiveKernelCache = adaptive_cache.AdaptiveKernelCache;

pub fn usesIntegratedInstrumentSampling(scene: *const Scene, channel: SpectralChannel) bool {
    const response = scene.observation_model.resolvedChannelControls(channel).response;
    // DECISION:
    //   Integrated sampling is driven by the observation model first; explicit
    //   line-shape metadata also forces integration so the legacy convolution
    //   path does not silently handle modern measured channels.
    const mode_requires_native_integration = switch (scene.observation_model.sampling) {
        .operational, .measured_channels => true,
        .native, .synthetic => false,
    };
    return mode_requires_native_integration or
        response.fwhm_nm > 0.0 or
        response.instrument_line_shape.sample_count > 0 or
        response.instrument_line_shape_table.nominal_count > 0;
}

pub fn integrationForWavelength(
    scene: *const Scene,
    prepared: ?*const PreparedOpticalState,
    channel: SpectralChannel,
    nominal_wavelength_nm: f64,
    kernel: *IntegrationKernel,
) void {
    integrationForWavelengthWithAdaptiveCache(
        scene,
        prepared,
        channel,
        nominal_wavelength_nm,
        null,
        kernel,
    );
}

pub fn integrationForWavelengthWithAdaptiveCache(
    scene: *const Scene,
    prepared: ?*const PreparedOpticalState,
    channel: SpectralChannel,
    nominal_wavelength_nm: f64,
    cached_adaptive_kernel: ?*const AdaptiveKernelCache,
    kernel: *IntegrationKernel,
) void {
    response_support.resetKernel(kernel);
    const response = scene.observation_model.resolvedChannelControls(channel).response;
    if (!usesIntegratedInstrumentSampling(scene, channel)) {
        kernel.sample_count = 1;
        return;
    }

    if (response.instrument_line_shape_table.nominal_count > 0) {
        kernel.sample_count = response.instrument_line_shape_table.writeNormalizedKernelForNominal(
            nominal_wavelength_nm,
            kernel.offsets_nm[0..],
            kernel.weights[0..],
        );
        if (kernel.sample_count == 0) {
            response_support.resetKernel(kernel);
            kernel.enabled = true;
            kernel.sample_count = 1;
            kernel.weights[0] = 1.0;
            return;
        }
        // PARITY:
        //   Strong-line table kernels bypass the legacy slit convolution when
        //   the table can provide a normalized kernel directly.
        kernel.enabled = true;
        return;
    }

    if (response.instrument_line_shape.sample_count > 0) {
        kernel.sample_count = response.instrument_line_shape.writeNormalizedKernel(
            kernel.offsets_nm[0..],
            kernel.weights[0..],
        );
        if (kernel.sample_count == 0) {
            response_support.resetKernel(kernel);
            kernel.enabled = true;
            kernel.sample_count = 1;
            kernel.weights[0] = 1.0;
            return;
        }
        kernel.enabled = true;
        return;
    }

    if (response.integration_mode == .disamar_hr_grid) {
        if (adaptive_plan.buildDisamarRealizedKernel(
            scene,
            response,
            nominal_wavelength_nm,
            kernel,
        )) {
            return;
        }
    }

    const prefer_explicit_hr_grid = switch (response.integration_mode) {
        .auto, .explicit_hr_grid => true,
        .adaptive => false,
        .disamar_hr_grid => false,
    };
    const prefer_adaptive_grid = response.integration_mode == .adaptive;

    if (prefer_explicit_hr_grid and response.high_resolution_step_nm > 0.0 and response.high_resolution_half_span_nm > 0.0) {
        const step_nm = response.high_resolution_step_nm;
        const half_span_nm = response.high_resolution_half_span_nm;
        var sample_count: usize = 0;
        var offset_nm = -half_span_nm;
        while (offset_nm <= half_span_nm + (step_nm * 0.5) and sample_count < max_integration_sample_count) : (offset_nm += step_nm) {
            kernel.offsets_nm[sample_count] = offset_nm;
            const response_weight = response_support.spectralResponseWeight(response, offset_nm);
            kernel.weights[sample_count] = response_weight;
            sample_count += 1;
        }
        if (sample_count == 0) sample_count = 1;
        var total_weight: f64 = 0.0;
        for (0..sample_count) |index| total_weight += kernel.weights[index];
        if (total_weight <= 0.0) {
            response_support.resetKernel(kernel);
            kernel.offsets_nm[0] = 0.0;
            kernel.weights[0] = 1.0;
            sample_count = 1;
        } else {
            for (0..sample_count) |index| kernel.weights[index] /= total_weight;
        }
        // PARITY:
        //   High-resolution measurement kernels are normalized in place rather
        //   than routed through the legacy slit-convolution stage.
        kernel.enabled = true;
        kernel.sample_count = sample_count;
        return;
    }

    if (prepared) |prepared_state| {
        if (cached_adaptive_kernel) |cache| {
            if (adaptive_cache.buildAdaptiveIntegrationKernelFromCache(
                response,
                nominal_wavelength_nm,
                cache,
                kernel,
            )) {
                return;
            }
        }
        if (prefer_adaptive_grid or response.high_resolution_step_nm == 0.0 or response.high_resolution_half_span_nm == 0.0) {
            if (adaptive_plan.buildAdaptiveIntegrationKernel(
                scene,
                prepared_state,
                response,
                nominal_wavelength_nm,
                kernel,
            )) {
                return;
            }
        }
    }

    switch (scene.observation_model.sampling) {
        .operational, .measured_channels => {
            kernel.sample_count = 1;
            return;
        },
        .native, .synthetic => {},
    }

    const default_half_span_nm = response_support.defaultKernelHalfSpanNm(response.fwhm_nm);
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
        kernel.weights[index] = response_support.spectralResponseWeight(response, offset_nm);
        total_weight += kernel.weights[index];
    }
    for (0..default_integration_sample_count) |index| kernel.weights[index] /= total_weight;
    kernel.enabled = true;
    kernel.sample_count = default_integration_sample_count;
}

pub fn prepareAdaptiveKernelCache(
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    channel: SpectralChannel,
    cache: *AdaptiveKernelCache,
) bool {
    const response = scene.observation_model.resolvedChannelControls(channel).response;
    return adaptive_cache.prepareAdaptiveKernelCache(scene, prepared, response, cache);
}

pub fn slitKernelForScene(scene: *const Scene, channel: SpectralChannel) [5]f64 {
    const response = scene.observation_model.resolvedChannelControls(channel).response;
    // PARITY:
    //   The default slit kernel remains a five-point symmetric kernel so the
    //   legacy convolution shape stays recognizable when explicit line-shape
    //   metadata is absent.
    if (response.fwhm_nm <= 0.0) {
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
        const value = response_support.spectralResponseWeight(response, offset_nm);
        kernel[index] = value;
        sum += value;
    }
    for (&kernel) |*value| value.* /= sum;
    return kernel;
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
    integrationForWavelength(&scene, null, .radiance, 760.5, &kernel);
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
    integrationForWavelength(&gaussian_scene, null, .radiance, 760.5, &gaussian_kernel);
    var flat_top_kernel: IntegrationKernel = undefined;
    integrationForWavelength(&flat_top_scene, null, .radiance, 760.5, &flat_top_kernel);

    try std.testing.expectEqual(gaussian_kernel.sample_count, flat_top_kernel.sample_count);
    try std.testing.expect(flat_top_kernel.weights[flat_top_kernel.sample_count / 2] < gaussian_kernel.weights[gaussian_kernel.sample_count / 2]);
    try std.testing.expect(flat_top_kernel.weights[0] > gaussian_kernel.weights[0]);
}

test "disamar hr grid realizes Gauss-weighted support instead of the uniform explicit lattice" {
    const scene: Scene = .{
        .spectral_grid = .{
            .start_nm = 755.0,
            .end_nm = 765.0,
            .sample_count = 101,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.38,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
            .adaptive_reference_grid = .{
                .points_per_fwhm = 40,
                .strong_line_min_divisions = 40,
                .strong_line_max_divisions = 40,
            },
            .measurement_pipeline = .{
                .irradiance = .{
                    .explicit = true,
                    .response = .{
                        .explicit = true,
                        .integration_mode = .disamar_hr_grid,
                        .fwhm_nm = 0.38,
                        .high_resolution_step_nm = 0.01,
                        .high_resolution_half_span_nm = 1.14,
                    },
                },
            },
        },
    };

    var kernel: IntegrationKernel = undefined;
    integrationForWavelength(&scene, null, .irradiance, 755.0, &kernel);

    try std.testing.expect(kernel.enabled);
    try std.testing.expectEqual(@as(usize, 201), kernel.sample_count);
    try std.testing.expectApproxEqAbs(@as(f64, -0.759665164845), kernel.offsets_nm[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.1403348351549), kernel.offsets_nm[kernel.sample_count - 1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), kernel.weights[kernel.sample_count - 1], 1.0e-12);
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

    try std.testing.expect(usesIntegratedInstrumentSampling(&scene, .radiance));

    var kernel: IntegrationKernel = undefined;
    integrationForWavelength(&scene, null, .radiance, 761.03, &kernel);
    try std.testing.expectEqual(@as(usize, 1), kernel.sample_count);
    try std.testing.expect(!kernel.enabled);
}

test "adaptive strong-line sampling injects refined centers from prepared spectroscopy" {
    var prepared = std.mem.zeroInit(PreparedOpticalState, .{
        .layers = &.{},
        .continuum_points = &.{},
        .spectroscopy_lines = @import("../../../model/ReferenceData.zig").SpectroscopyLineList{
            .lines = try std.testing.allocator.dupe(@import("../../../model/ReferenceData.zig").SpectroscopyLine, &.{
                .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 760.52, .line_strength_cm2_per_molecule = 1.0e-20, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
                .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 761.10, .line_strength_cm2_per_molecule = 2.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
            }),
            .runtime_controls = .{
                .gas_index = 7,
                .threshold_line_scale = 0.5,
            },
        },
    });
    defer if (prepared.spectroscopy_lines) |*line_list| line_list.deinit(std.testing.allocator);

    const scene: Scene = .{
        .spectral_grid = .{
            .start_nm = 759.0,
            .end_nm = 762.0,
            .sample_count = 121,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.4,
            .adaptive_reference_grid = .{
                .points_per_fwhm = 3,
                .strong_line_min_divisions = 5,
                .strong_line_max_divisions = 9,
            },
        },
    };

    var kernel: IntegrationKernel = undefined;
    integrationForWavelength(&scene, &prepared, .radiance, 760.5, &kernel);
    try std.testing.expect(kernel.enabled);
    try std.testing.expect(kernel.sample_count > 18);

    var found_strong_center = false;
    for (kernel.offsets_nm[0..kernel.sample_count]) |offset_nm| {
        if (@abs(offset_nm - 0.02) <= 1.0e-6) {
            found_strong_center = true;
            break;
        }
    }
    try std.testing.expect(found_strong_center);
}

test "dense adaptive strong-line windows do not fall back to the five-point kernel" {
    const line_count = 125;
    const lines = try std.testing.allocator.alloc(@import("../../../model/ReferenceData.zig").SpectroscopyLine, line_count);
    defer std.testing.allocator.free(lines);

    for (lines, 0..) |*line, index| {
        line.* = .{
            .gas_index = 7,
            .isotope_number = 1,
            .center_wavelength_nm = 759.575 + (0.0085 * @as(f64, @floatFromInt(index))),
            .line_strength_cm2_per_molecule = 1.0e-24,
            .air_half_width_nm = 0.001,
            .temperature_exponent = 0.7,
            .lower_state_energy_cm1 = 120.0,
            .pressure_shift_nm = 0.0,
            .line_mixing_coefficient = 0.0,
        };
    }

    var prepared = std.mem.zeroInit(PreparedOpticalState, .{
        .layers = &.{},
        .continuum_points = &.{},
        .spectroscopy_lines = @import("../../../model/ReferenceData.zig").SpectroscopyLineList{
            .lines = lines,
            .runtime_controls = .{
                .gas_index = 7,
                .threshold_line_scale = 0.5,
            },
        },
    });

    const scene: Scene = .{
        .spectral_grid = .{
            .start_nm = 755.0,
            .end_nm = 776.0,
            .sample_count = 701,
        },
        .observation_model = .{
            .instrument = .{ .custom = "dense-adaptive" },
            .sampling = .native,
            .noise_model = .none,
            .instrument_line_fwhm_nm = 0.38,
            .adaptive_reference_grid = .{
                .points_per_fwhm = 20,
                .strong_line_min_divisions = 8,
                .strong_line_max_divisions = 40,
            },
        },
    };

    var kernel: IntegrationKernel = undefined;
    integrationForWavelength(&scene, &prepared, .radiance, 759.53, &kernel);
    try std.testing.expect(kernel.enabled);
    try std.testing.expect(kernel.sample_count > 1000);
    try std.testing.expect(kernel.sample_count != default_integration_sample_count);
}
