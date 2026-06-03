const std = @import("std");
const internal = @import("internal");

const Scene = internal.Scene;
const measurement = internal.forward_model.instrument_grid;
const common = internal.forward_model.radiative_transfer;
const PreparedOpticalState = internal.forward_model.optical_properties.PreparedOpticalState;
const instrument_integration = internal.forward_model.instrument_integration;
const IntegrationKernel = internal.forward_model.instrument_types.IntegrationKernel;
const SpectroscopyLine = internal.reference_data.SpectroscopyLine;
const Instrument = internal.instrument.Instrument;

const strong_line_samples = [_]SpectroscopyLine{
    .{
        .gas_index = 7,
        .isotope_number = 1,
        .center_wavelength_nm = 760.52,
        .line_strength_cm2_per_molecule = 1.0e-20,
        .air_half_width_nm = 0.001,
        .temperature_exponent = 0.7,
        .lower_state_energy_cm1 = 120.0,
        .pressure_shift_nm = 0.0,
        .line_mixing_coefficient = 0.0,
    },
    .{
        .gas_index = 7,
        .isotope_number = 1,
        .center_wavelength_nm = 761.10,
        .line_strength_cm2_per_molecule = 2.0e-21,
        .air_half_width_nm = 0.001,
        .temperature_exponent = 0.7,
        .lower_state_energy_cm1 = 120.0,
        .pressure_shift_nm = 0.0,
        .line_mixing_coefficient = 0.0,
    },
};

test "adaptive integration cache matches uncached strong-line kernel" {
    var prepared = std.mem.zeroInit(PreparedOpticalState, .{
        .layers = &.{},
        .continuum_points = &.{},
        .spectroscopy_lines = internal.reference_data.SpectroscopyLineList{
            .lines = try std.testing.allocator.dupe(SpectroscopyLine, &strong_line_samples),
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
            .instrument_line_fwhm_nm = 0.4,
            .adaptive_reference_grid = .{
                .points_per_fwhm = 3,
                .strong_line_min_divisions = 5,
                .strong_line_max_divisions = 9,
            },
        },
    };

    var baseline: IntegrationKernel = undefined;
    try instrument_integration.integrationForWavelengthChecked(&scene, &prepared, .radiance, 760.5, &baseline);

    var cache: instrument_integration.AdaptiveKernelCache = .{};
    try std.testing.expect(
        instrument_integration.prepareAdaptiveKernelCache(
            &scene,
            &prepared,
            .radiance,
            &cache,
        ),
    );

    var cached: IntegrationKernel = undefined;
    try instrument_integration.integrationForWavelengthWithAdaptiveCacheChecked(
        &scene,
        &prepared,
        .radiance,
        760.5,
        &cache,
        &cached,
    );

    try std.testing.expectEqual(baseline.enabled, cached.enabled);
    try std.testing.expectEqual(baseline.sample_count, cached.sample_count);
    for (0..baseline.sample_count) |index| {
        try std.testing.expectApproxEqAbs(baseline.offsets_nm[index], cached.offsets_nm[index], 1.0e-12);
        try std.testing.expectApproxEqAbs(baseline.weights[index], cached.weights[index], 1.0e-12);
    }
}

test "legacy adaptive grid prefers adaptive realization over explicit HR lattice" {
    var prepared = std.mem.zeroInit(PreparedOpticalState, .{
        .layers = &.{},
        .continuum_points = &.{},
        .spectroscopy_lines = internal.reference_data.SpectroscopyLineList{
            .lines = try std.testing.allocator.dupe(SpectroscopyLine, &strong_line_samples),
            .runtime_controls = .{
                .gas_index = 7,
                .threshold_line_scale = 0.5,
            },
        },
    });
    defer if (prepared.spectroscopy_lines) |*line_list| line_list.deinit(std.testing.allocator);

    const support = [_]Instrument.OperationalBandSupport{.{
        .id = "primary",
        .high_resolution_step_nm = 0.01,
        .high_resolution_half_span_nm = 0.40,
    }};
    const scene: Scene = .{
        .spectral_grid = .{
            .start_nm = 759.0,
            .end_nm = 762.0,
            .sample_count = 121,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .sampling = .native,
            .instrument_line_fwhm_nm = 0.4,
            .operational_band_support = support[0..],
            .adaptive_reference_grid = .{
                .points_per_fwhm = 3,
                .strong_line_min_divisions = 5,
                .strong_line_max_divisions = 9,
            },
        },
    };

    var kernel: IntegrationKernel = undefined;
    try instrument_integration.integrationForWavelengthChecked(&scene, &prepared, .radiance, 760.5, &kernel);

    try std.testing.expect(kernel.enabled);
    try std.testing.expect(kernel.sample_count != 81);
    const first_spacing = kernel.offsets_nm[1] - kernel.offsets_nm[0];
    const second_spacing = kernel.offsets_nm[2] - kernel.offsets_nm[1];
    try std.testing.expect(@abs(first_spacing - second_spacing) > 1.0e-6);
}

test "product storage reuses backing buffers across requests" {
    var storage: measurement.ProductStorage = .{};
    defer storage.deinit(std.testing.allocator);

    const scene: Scene = .{
        .spectral_grid = .{
            .start_nm = 760.0,
            .end_nm = 761.0,
            .sample_count = 16,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .sampling = .native,
        },
        .atmosphere = .{
            .layer_count = 4,
            .sublayer_divisions = 1,
        },
    };
    const rtm_config: common.SolveConfig = .{
        .derivative_mode = .none,
    };
    const first = try storage.buffers(std.testing.allocator, &scene, rtm_config);
    const second = try storage.buffers(std.testing.allocator, &scene, rtm_config);

    try std.testing.expectEqual(first.wavelengths.ptr, second.wavelengths.ptr);
    try std.testing.expectEqual(first.radiance.ptr, second.radiance.ptr);
    try std.testing.expectEqual(first.layer_inputs.ptr, second.layer_inputs.ptr);
}
