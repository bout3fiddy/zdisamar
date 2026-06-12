const std = @import("std");

const internal = @import("internal");

const readers = internal.assets.readers;
const sampling_table = internal.spectrum.sampling_table;
const solar_lookup = internal.spectrum.solar_lookup;
const solar_table = internal.setup.solar_table;

test "SolarTable prepares old-route spline state for reference solar rows" {
    var tables = try internal.setup.o2_run_tables.buildReferenceO2RunTables(
        std.testing.allocator,
        internal.input.defaults.referenceCase(),
    );
    defer tables.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 32), @sizeOf(solar_table.SolarTable));
    try std.testing.expectEqual(tables.solar.rows.len, tables.solar.spline_second_derivatives.len);

    // Source: old `src/input/instrument/solar_spectrum.zig` prepareInterpolation route run against
    // data/reference_data/solar/o2a_solar_reference_753_778.csv.
    try std.testing.expectApproxEqAbs(
        -7.16441414660904750e14,
        tables.solar.spline_second_derivatives[0],
        1.0e1,
    );
    try std.testing.expectApproxEqAbs(
        -1.19906501663723150e15,
        tables.solar.spline_second_derivatives[1250],
        1.0e1,
    );
    try std.testing.expectApproxEqAbs(
        3.43042204474471375e14,
        tables.solar.spline_second_derivatives[tables.solar.spline_second_derivatives.len - 1],
        1.0e1,
    );
}

test "irradianceAtWavelength matches old operational spline and clamp behavior" {
    var tables = try internal.setup.o2_run_tables.buildReferenceO2RunTables(
        std.testing.allocator,
        internal.input.defaults.referenceCase(),
    );
    defer tables.deinit(std.testing.allocator);

    // Source: old `OperationalSolarSpectrum.interpolateIrradiance` route for the WP1 reference solar asset.
    try expectSolar(4.87640000000000000e14, try solar_lookup.irradianceAtWavelength(tables.solar, 753.0));
    try expectSolar(4.86690022241158375e14, try solar_lookup.irradianceAtWavelength(tables.solar, 753.005));
    try expectSolar(4.87870339978322125e14, try solar_lookup.irradianceAtWavelength(tables.solar, 760.005));
    try expectSolar(4.76600000000000000e14, try solar_lookup.irradianceAtWavelength(tables.solar, 778.5));
    try expectSolar(4.87640000000000000e14, try solar_lookup.irradianceAtWavelength(tables.solar, 752.5));
}

test "integrateIrradianceAtNominalAssumeCapacity weights old cached irradiance samples" {
    var tables = try internal.setup.o2_run_tables.buildReferenceO2RunTables(
        std.testing.allocator,
        internal.input.defaults.referenceCase(),
    );
    defer tables.deinit(std.testing.allocator);

    var memory = internal.cache.solar_irradiance_memory.SolarIrradianceMemory.init(std.testing.allocator);
    defer memory.deinit();
    try memory.reserve(3);

    const offsets = [_]f64{ -0.005, 0.0, 0.005 };
    const weights = [_]f64{ 0.25, 0.5, 0.25 };
    const integration = sampling_table.IntegrationKernelRef{
        .side_start = 0,
        .sample_count = 3,
        .encoding = .side_samples,
    };

    const actual = try solar_lookup.integrateIrradianceAtNominalAssumeCapacity(
        tables.solar,
        &memory,
        760.0,
        &integration,
        .{
            .offsets_nm = offsets[0..],
            .weights = weights[0..],
        },
    );

    // Source: old `spectral_eval.zig` integrateIrradianceAtNominal route with the WP1 reference solar asset.
    try expectSolar(4.87366765517170125e14, actual);
    try std.testing.expectEqual(@as(u32, 3), memory.values.count());
}

test "cachedIrradianceAtWavelengthAssumeCapacity keeps exact f64 bit keys" {
    var rows = [_]readers.SolarAssetRow{
        .{ .wavelength_nm = -1.0, .irradiance = 10.0 },
        .{ .wavelength_nm = 0.0, .irradiance = 20.0 },
        .{ .wavelength_nm = 1.0, .irradiance = 30.0 },
    };
    const table = solar_table.SolarTable{
        .rows = rows[0..],
        .spline_second_derivatives = &.{},
    };

    var memory = internal.cache.solar_irradiance_memory.SolarIrradianceMemory.init(std.testing.allocator);
    defer memory.deinit();
    try memory.reserve(2);

    _ = try solar_lookup.cachedIrradianceAtWavelengthAssumeCapacity(table, &memory, 0.0);
    _ = try solar_lookup.cachedIrradianceAtWavelengthAssumeCapacity(table, &memory, -0.0);

    try std.testing.expectEqual(@as(u32, 2), memory.values.count());
}

test "integrateIrradianceAtNominalAssumeCapacity rejects malformed side storage" {
    var rows = [_]readers.SolarAssetRow{
        .{ .wavelength_nm = 759.0, .irradiance = 10.0 },
        .{ .wavelength_nm = 760.0, .irradiance = 20.0 },
    };
    const table = solar_table.SolarTable{
        .rows = rows[0..],
        .spline_second_derivatives = &.{},
    };
    var memory = internal.cache.solar_irradiance_memory.SolarIrradianceMemory.init(std.testing.allocator);
    defer memory.deinit();
    try memory.reserve(1);

    const integration = sampling_table.IntegrationKernelRef{
        .side_start = 0,
        .sample_count = 2,
        .encoding = .side_samples,
    };
    const offsets = [_]f64{0.0};
    const weights = [_]f64{1.0};

    try std.testing.expectError(
        error.ShapeMismatch,
        solar_lookup.integrateIrradianceAtNominalAssumeCapacity(
            table,
            &memory,
            760.0,
            &integration,
            .{
                .offsets_nm = offsets[0..],
                .weights = weights[0..],
            },
        ),
    );
}

fn expectSolar(expected: f64, actual: f64) !void {
    // expectSolar --------------------------------------------------------------------------------------------|
    // Compare large O2 A irradiance values with an absolute tolerance small enough to catch spline changes.   |
    // --------------------------------------------------------------------------------------------------------|
    try std.testing.expectApproxEqAbs(expected, actual, 1.0e1);
}
