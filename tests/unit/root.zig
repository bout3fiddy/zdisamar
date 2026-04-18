const std = @import("std");
const zdisamar = @import("zdisamar");
const _observation_model_tests = @import("observation_model_test.zig");

const Scene = zdisamar.Case;
const empty_scene: Scene = .{};
const ObservationModel = @TypeOf(empty_scene.observation_model);
const Aerosol = @TypeOf(empty_scene.aerosol);
const Cloud = @TypeOf(empty_scene.cloud);
const Placement = @TypeOf(empty_scene.aerosol.placement);
const empty_observation_model: ObservationModel = .{};
const OperationalBandSupport = std.meta.Child(@TypeOf(empty_observation_model.operational_band_support));

test "unit suite keeps the public surface literal" {
    try std.testing.expect(@hasDecl(zdisamar, "Case"));
    try std.testing.expect(@hasDecl(zdisamar, "Data"));
    try std.testing.expect(@hasDecl(zdisamar, "Optics"));
    try std.testing.expect(@hasDecl(zdisamar, "runSpectrum"));
    try std.testing.expect(!@hasDecl(zdisamar, "compat"));
    try std.testing.expect(!@hasDecl(zdisamar, "Engine"));
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
