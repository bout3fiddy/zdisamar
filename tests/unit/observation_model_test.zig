const std = @import("std");
const zdisamar = @import("zdisamar");

const Scene = zdisamar.Input;
const empty_scene: Scene = .{};
const ObservationModel = @TypeOf(empty_scene.observation_model);
const empty_model: ObservationModel = .{};
const OperationalBandSupport = std.meta.Child(@TypeOf(empty_model.operational_band_support));
const empty_support: OperationalBandSupport = .{};
const InstrumentLineShape = @TypeOf(empty_support.instrument_line_shape);
const InstrumentLineShapeTable = @TypeOf(empty_support.instrument_line_shape_table);

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
        .multiplicative_offset = 1.002,
        .stray_light = 0.0007,
        .adaptive_reference_grid = .{
            .points_per_fwhm = 5,
            .strong_line_min_divisions = 3,
            .strong_line_max_divisions = 8,
        },
    };

    try std.testing.expectEqual(@TypeOf(model.sampling).operational, model.sampling);
    try model.validate();
}

test "observation model carries explicit measured-channel wavelengths" {
    const measured_wavelengths = [_]f64{ 760.8, 761.02, 761.31 };
    const model: ObservationModel = .{
        .instrument = .tropomi,
        .sampling = .measured_channels,
        .measured_wavelengths_nm = &measured_wavelengths,
    };

    try model.validate();
    try std.testing.expectEqual(@as(f64, 761.02), model.measured_wavelengths_nm[1]);
}

test "observation model explicit integration mode overrides adaptive default" {
    const model: ObservationModel = .{
        .instrument = .tropomi,
        .instrument_line_fwhm_nm = 0.38,
        .integration_mode = .disamar_hr_grid,
        .adaptive_reference_grid = .{
            .points_per_fwhm = 5,
            .strong_line_min_divisions = 3,
            .strong_line_max_divisions = 8,
        },
    };

    const response = model.resolvedChannelControls(.radiance).response;
    try std.testing.expectEqual(@TypeOf(response.integration_mode).disamar_hr_grid, response.integration_mode);
}

test "observation model auto integration resolves to a concrete default kernel" {
    const model: ObservationModel = .{
        .instrument = .tropomi,
        .instrument_line_fwhm_nm = 0.38,
    };

    const response = model.resolvedChannelControls(.radiance).response;
    try std.testing.expectEqual(@TypeOf(response.integration_mode).default_kernel, response.integration_mode);
}

test "observation model explicit HR integration requires grid metadata" {
    const model: ObservationModel = .{
        .instrument = .tropomi,
        .instrument_line_fwhm_nm = 0.38,
        .integration_mode = .explicit_hr_grid,
    };

    try std.testing.expectError(error.InvalidRequest, model.validate());
}

test "observation model spectral response borrows owned support line-shape carriers" {
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

    const support = [_]OperationalBandSupport{.{
        .id = "primary",
        .instrument_line_shape = line_shape,
        .instrument_line_shape_table = line_shape_table,
    }};
    var model: ObservationModel = .{
        .instrument = .tropomi,
        .builtin_line_shape = .gaussian,
        .instrument_line_fwhm_nm = 0.38,
        .operational_band_support = support[0..],
    };

    const radiance = model.resolvedChannelControls(.radiance);

    try std.testing.expect(!radiance.response.instrument_line_shape.owns_memory);
    try std.testing.expect(!radiance.response.instrument_line_shape_table.owns_memory);
    try std.testing.expectEqual(
        @intFromPtr(support[0].instrument_line_shape.offsets_nm.ptr),
        @intFromPtr(radiance.response.instrument_line_shape.offsets_nm.ptr),
    );
    try std.testing.expectEqual(
        @intFromPtr(support[0].instrument_line_shape_table.weights.ptr),
        @intFromPtr(radiance.response.instrument_line_shape_table.weights.ptr),
    );

    line_shape.deinitOwned(std.testing.allocator);
    line_shape_table.deinitOwned(std.testing.allocator);
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
