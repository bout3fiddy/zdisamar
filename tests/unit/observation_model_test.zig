const std = @import("std");
const zdisamar = @import("zdisamar");

const Scene = zdisamar.Input;
const empty_scene: Scene = .{};
const ObservationModel = @TypeOf(empty_scene.observation_model);
const empty_model: ObservationModel = .{};
const CrossSectionFitControls = @TypeOf(empty_model.cross_section_fit);
const OperationalBandSupport = std.meta.Child(@TypeOf(empty_model.operational_band_support));
const InstrumentLineShape = @TypeOf(empty_model.instrument_line_shape);
const InstrumentLineShapeTable = @TypeOf(empty_model.instrument_line_shape_table);

test "observation model carries calibration and supporting-data bindings" {
    const model: ObservationModel = .{
        .instrument = .tropomi,
        .solar_spectrum_source = .bundle_default,
        .weighted_reference_grid_source = .{ .ingest = .{
            .full_name = "refspec_demo.grid",
            .ingest_name = "refspec_demo",
            .output_name = "grid",
        } },
        .sampling = .operational,
        .noise_model = .shot_noise,
        .multiplicative_offset = 1.002,
        .stray_light = 0.0007,
        .adaptive_reference_grid = .{
            .points_per_fwhm = 5,
            .strong_line_min_divisions = 3,
            .strong_line_max_divisions = 8,
        },
    };

    try std.testing.expectEqual(@TypeOf(model.sampling).operational, model.sampling);
    try std.testing.expectEqual(@TypeOf(model.noise_model).shot_noise, model.noise_model);
    try model.validate();
}

test "observation model carries explicit measured-channel wavelengths" {
    const measured_wavelengths = [_]f64{ 760.8, 761.02, 761.31 };
    const model: ObservationModel = .{
        .instrument = .tropomi,
        .sampling = .measured_channels,
        .noise_model = .snr_from_input,
        .measured_wavelengths_nm = &measured_wavelengths,
        .reference_radiance = &.{ 1.2, 1.1, 1.0 },
        .ingested_noise_sigma = &.{ 0.02, 0.03, 0.025 },
    };

    try model.validate();
    try std.testing.expectEqual(@as(f64, 761.02), model.measured_wavelengths_nm[1]);
}

test "observation model rejects lab operational noise without explicit LAB coefficients" {
    const invalid_model: ObservationModel = .{
        .noise_model = .lab_operational,
    };

    try std.testing.expectError(error.InvalidRequest, invalid_model.validate());
}

test "observation model keeps borrowed legacy noise references when SNR tables are owned" {
    const measured_wavelengths = [_]f64{760.8};
    const reference_radiance = [_]f64{1.2};
    const ingested_noise_sigma = [_]f64{0.02};
    const model: ObservationModel = .{
        .instrument = .tropomi,
        .noise_model = .s5p_operational,
        .measured_wavelengths_nm = &measured_wavelengths,
        .reference_radiance = &reference_radiance,
        .ingested_noise_sigma = &ingested_noise_sigma,
    };

    var controls = model.resolvedChannelControls(.radiance);
    const snr_wavelengths_nm = try std.testing.allocator.dupe(f64, &.{760.8});
    errdefer std.testing.allocator.free(snr_wavelengths_nm);
    const snr_values = try std.testing.allocator.dupe(f64, &.{250.0});
    errdefer std.testing.allocator.free(snr_values);

    controls.noise.snr_wavelengths_nm = snr_wavelengths_nm;
    controls.noise.snr_values = snr_values;
    controls.noise.owns_snr_memory = true;
    defer controls.noise.deinitOwned(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), controls.noise.reference_signal.len);
    try std.testing.expectEqual(@as(usize, 1), controls.noise.reference_sigma.len);
}

test "observation model legacy spectral response borrows owned line-shape carriers" {
    var line_shape: InstrumentLineShape = .{
        .sample_count = 2,
        .offsets_nm = try std.testing.allocator.dupe(f64, &.{ -0.1, 0.1 }),
        .weights = try std.testing.allocator.dupe(f64, &.{ 0.4, 0.6 }),
        .owns_memory = true,
    };
    errdefer line_shape.deinitOwned(std.testing.allocator);

    var line_shape_table: InstrumentLineShapeTable = .{
        .nominal_count = 1,
        .sample_count = 2,
        .nominal_wavelengths_nm = try std.testing.allocator.dupe(f64, &.{760.8}),
        .offsets_nm = try std.testing.allocator.dupe(f64, &.{ -0.1, 0.1 }),
        .weights = try std.testing.allocator.dupe(f64, &.{ 0.45, 0.55 }),
        .owns_memory = true,
    };
    errdefer line_shape_table.deinitOwned(std.testing.allocator);

    var model: ObservationModel = .{
        .instrument = .tropomi,
        .builtin_line_shape = .gaussian,
        .instrument_line_fwhm_nm = 0.38,
        .instrument_line_shape = line_shape,
        .instrument_line_shape_table = line_shape_table,
        .noise_model = .none,
    };
    defer model.deinitOwned(std.testing.allocator);

    var radiance = model.resolvedChannelControls(.radiance);
    radiance.explicit = true;
    model.measurement_pipeline.radiance = radiance;

    try std.testing.expect(!radiance.response.instrument_line_shape.owns_memory);
    try std.testing.expect(!radiance.response.instrument_line_shape_table.owns_memory);
    try std.testing.expectEqual(
        @intFromPtr(model.instrument_line_shape.offsets_nm.ptr),
        @intFromPtr(radiance.response.instrument_line_shape.offsets_nm.ptr),
    );
    try std.testing.expectEqual(
        @intFromPtr(model.instrument_line_shape_table.weights.ptr),
        @intFromPtr(radiance.response.instrument_line_shape_table.weights.ptr),
    );
}

test "cross-section fit controls validate band-scoped settings" {
    const valid: CrossSectionFitControls = .{
        .use_effective_cross_section_oe = true,
        .use_polynomial_expansion = true,
        .xsec_strong_absorption_bands = &.{ true, false },
        .polynomial_degree_bands = &.{ 5, 3 },
    };

    try valid.validateForBandCount(2);
    try std.testing.expect(valid.strongAbsorptionForBand(0));
    try std.testing.expectEqual(@as(u32, 3), valid.polynomialOrderForBand(1));
    try std.testing.expectEqual(@as(u32, 0), valid.polynomialOrderForBand(3));
    try std.testing.expectEqual(@as(u32, 5), valid.maximumPolynomialOrder());

    try std.testing.expectError(
        error.InvalidRequest,
        (CrossSectionFitControls{
            .polynomial_degree_bands = &.{ 4, 2 },
        }).validateForBandCount(1),
    );
    try std.testing.expectError(
        error.InvalidRequest,
        (CrossSectionFitControls{
            .polynomial_degree_bands = &.{8},
        }).validate(),
    );
}

fn cloneCrossSectionFitControlsWithAllocator(allocator: std.mem.Allocator) !void {
    const controls: CrossSectionFitControls = .{
        .use_effective_cross_section_oe = true,
        .use_polynomial_expansion = true,
        .xsec_strong_absorption_bands = &.{ true, false },
        .polynomial_degree_bands = &.{ 5, 3 },
    };

    var cloned = try controls.clone(allocator);
    defer cloned.deinitOwned(allocator);
}

test "cross-section fit controls clone cleans up across allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        cloneCrossSectionFitControlsWithAllocator,
        .{},
    );
}

test "observation model rejects multi-band operational support until runtime becomes band-indexed" {
    const support = [_]OperationalBandSupport{
        .{ .id = "band-0" },
        .{ .id = "band-1" },
    };
    var model: ObservationModel = .{
        .operational_band_support = &support,
    };

    try std.testing.expectError(error.InvalidRequest, model.validate());
}

test "observation model merges partial explicit operational support with legacy replacements" {
    const support = [_]OperationalBandSupport{.{
        .id = "band-0",
        .instrument_line_shape = .{
            .sample_count = 3,
            .offsets_nm = &.{ -0.1, 0.0, 0.1 },
            .weights = &.{ 0.25, 0.5, 0.25 },
        },
    }};
    var model: ObservationModel = .{
        .instrument = .tropomi,
        .high_resolution_step_nm = 0.08,
        .high_resolution_half_span_nm = 0.32,
        .operational_solar_spectrum = .{
            .wavelengths_nm = &.{ 760.8, 761.0, 761.2 },
            .irradiance = &.{ 2.7e14, 2.8e14, 2.75e14 },
        },
        .operational_band_support = &support,
    };

    const resolved = model.primaryOperationalBandSupport();
    try std.testing.expectEqualStrings("band-0", resolved.id);
    try std.testing.expectEqual(@as(f64, 0.08), resolved.high_resolution_step_nm);
    try std.testing.expectEqual(@as(f64, 0.32), resolved.high_resolution_half_span_nm);
    try std.testing.expectEqual(@as(u8, 3), resolved.instrument_line_shape.sample_count);
    try std.testing.expect(resolved.operational_solar_spectrum.enabled());
    try std.testing.expectApproxEqAbs(@as(f64, 2.8e14), resolved.operational_solar_spectrum.interpolateIrradiance(761.0), 1.0e9);
}
