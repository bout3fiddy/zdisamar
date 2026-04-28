const std = @import("std");
const zdisamar = @import("zdisamar");

// See tests/unit/internal_root.zig for the rationale: a `test` block is
// required to force Zig to analyze the imported test files.
test {
    _ = @import("observation_model_test.zig");
}

const Scene = zdisamar.Input;
const empty_scene: Scene = .{};
const ObservationModel = @TypeOf(empty_scene.observation_model);
const Aerosol = @TypeOf(empty_scene.aerosol);
const Cloud = @TypeOf(empty_scene.cloud);
const Placement = @TypeOf(empty_scene.aerosol.placement);
const Absorber = std.meta.Child(@TypeOf(empty_scene.absorbers.items));
const empty_observation_model: ObservationModel = .{};
const OperationalBandSupport = std.meta.Child(@TypeOf(empty_observation_model.operational_band_support));

test "unit suite keeps the public surface literal" {
    try std.testing.expect(@hasDecl(zdisamar, "Input"));
    try std.testing.expect(@hasDecl(zdisamar, "ReferenceData"));
    try std.testing.expect(@hasDecl(zdisamar, "OpticalProperties"));
    try std.testing.expect(@hasDecl(zdisamar, "PreparedInput"));
    try std.testing.expect(@hasDecl(zdisamar, "prepare"));
    try std.testing.expect(@hasDecl(zdisamar, "run"));
    try std.testing.expect(!@hasDecl(zdisamar, "loadData"));
    try std.testing.expect(!@hasDecl(zdisamar, "buildOptics"));
    try std.testing.expect(!@hasDecl(zdisamar, "runSpectrum"));
    try std.testing.expect(!@hasDecl(zdisamar, "compat"));
    try std.testing.expect(!@hasDecl(zdisamar, "Engine"));
}

test "prepared lifecycle owns resolved O2A state" {
    var input: zdisamar.Input = .{
        .id = "prepared-lifecycle",
        .spectral_grid = .{ .start_nm = 758.0, .end_nm = 771.0, .sample_count = 3 },
        .observation_model = .{
            .instrument = .tropomi,
            .instrument_line_fwhm_nm = 0.38,
        },
    };

    var prepared = try zdisamar.prepare(std.testing.allocator, &input);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("prepared-lifecycle", prepared.input.id);
    try std.testing.expect(prepared.optical_properties.total_optical_depth >= 0.0);
}

test "generated O2A LUTs live only in operational band support" {
    const support = [_]OperationalBandSupport{.{
        .id = "primary",
        .high_resolution_step_nm = 0.05,
        .high_resolution_half_span_nm = 0.25,
    }};
    const absorbers = [_]Absorber{.{
        .id = "o2",
        .species = "o2",
        .resolved_species = .o2,
        .profile_source = .atmosphere,
        .spectroscopy = .{
            .mode = .line_by_line,
            .line_gas_controls = .{
                .active_stage = .simulation,
            },
        },
    }};
    var input: zdisamar.Input = .{
        .id = "generated-lut-ownership",
        .spectral_grid = .{ .start_nm = 758.0, .end_nm = 771.0, .sample_count = 3 },
        .absorbers = .{ .items = absorbers[0..] },
        .observation_model = .{
            .instrument = .tropomi,
            .instrument_line_fwhm_nm = 0.38,
            .operational_band_support = support[0..],
        },
        .lut_controls = .{
            .xsec = .{
                .mode = .generate,
                .min_temperature_k = 180.0,
                .max_temperature_k = 325.0,
                .min_pressure_hpa = 0.03,
                .max_pressure_hpa = 1050.0,
                .temperature_grid_count = 3,
                .pressure_grid_count = 3,
                .temperature_coefficient_count = 2,
                .pressure_coefficient_count = 2,
            },
        },
    };

    var prepared = try zdisamar.prepare(std.testing.allocator, &input);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expect(!prepared.input.observation_model.o2_operational_lut.enabled());
    try std.testing.expect(prepared.input.observation_model.primaryOperationalBandSupport().o2_operational_lut.enabled());
}

test "observation model resolves legacy operational support through the public methods" {
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
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.8e14),
        resolved.operational_solar_spectrum.interpolateIrradiance(761.0),
        1.0e9,
    );
}

test "particle placement falls back only when explicit placement is absent" {
    const aerosol: Aerosol = .{
        .layer_center_km = 2.5,
        .layer_width_km = 3.0,
    };
    const aerosol_placement = aerosol.resolvedPlacement();
    try std.testing.expectEqual(Placement{
        .semantics = .altitude_center_width_approximation,
        .top_altitude_km = 4.0,
        .bottom_altitude_km = 1.0,
    }, aerosol_placement);

    const cloud: Cloud = .{
        .top_altitude_km = 6.0,
        .thickness_km = 1.5,
        .placement = .{
            .semantics = .explicit_interval_bounds,
            .interval_index_1based = 2,
            .top_pressure_hpa = 300.0,
            .bottom_pressure_hpa = 450.0,
            .top_altitude_km = 6.0,
            .bottom_altitude_km = 4.5,
        },
    };
    const cloud_placement = cloud.resolvedPlacement();
    try std.testing.expectEqual(@as(u32, 2), cloud_placement.interval_index_1based);
    try std.testing.expectEqual(@as(f64, 300.0), cloud_placement.top_pressure_hpa);
    try std.testing.expectEqual(@as(f64, 4.5), cloud_placement.bottom_altitude_km);
}

test "public root exposes the O2A forward lab surface" {
    try std.testing.expect(@hasDecl(zdisamar, "Input"));
    try std.testing.expect(@hasDecl(zdisamar, "ReferenceData"));
    try std.testing.expect(@hasDecl(zdisamar, "OpticalProperties"));
    try std.testing.expect(@hasDecl(zdisamar, "Method"));
    try std.testing.expect(@hasDecl(zdisamar, "CalculationStorage"));
    try std.testing.expect(@hasDecl(zdisamar, "Output"));
    try std.testing.expect(@hasDecl(zdisamar, "DiagnosticReport"));
    try std.testing.expect(@hasDecl(zdisamar, "PreparedInput"));
    try std.testing.expect(@hasDecl(zdisamar, "disamar_reference"));
    try std.testing.expect(@hasDecl(zdisamar, "prepare"));
    try std.testing.expect(@hasDecl(zdisamar, "run"));
    try std.testing.expect(@hasDecl(zdisamar, "writeReport"));
}

test "public root no longer exposes removed framework scaffolding" {
    try std.testing.expect(!@hasDecl(zdisamar, "Engine"));
    try std.testing.expect(!@hasDecl(zdisamar, "PreparedPlan"));
    try std.testing.expect(!@hasDecl(zdisamar, "Workspace"));
    try std.testing.expect(!@hasDecl(zdisamar, "Request"));
    try std.testing.expect(!@hasDecl(zdisamar, "canonical_config"));
    try std.testing.expect(!@hasDecl(zdisamar, "mission_s5p"));
    try std.testing.expect(!@hasDecl(zdisamar, "exporters"));
    try std.testing.expect(!@hasDecl(zdisamar, "test_support"));
    try std.testing.expect(!@hasDecl(zdisamar, "vendor_case"));
    try std.testing.expect(!@hasDecl(zdisamar, "Case"));
    try std.testing.expect(!@hasDecl(zdisamar, "Data"));
    try std.testing.expect(!@hasDecl(zdisamar, "Optics"));
    try std.testing.expect(!@hasDecl(zdisamar, "RunStorage"));
    try std.testing.expect(!@hasDecl(zdisamar, "Result"));
    try std.testing.expect(!@hasDecl(zdisamar, "Report"));
    try std.testing.expect(!@hasDecl(zdisamar, "Prepared"));
    try std.testing.expect(!@hasDecl(zdisamar, "parity"));
    try std.testing.expect(!@hasDecl(zdisamar, "loadData"));
    try std.testing.expect(!@hasDecl(zdisamar, "buildOptics"));
    try std.testing.expect(!@hasDecl(zdisamar, "runSpectrum"));
}
