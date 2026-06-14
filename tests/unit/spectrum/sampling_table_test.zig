const std = @import("std");

const internal = @import("internal");

const radiance_wavelengths = internal.spectrum.radiance_wavelengths;
const sampling_table = internal.spectrum.sampling_table;

test "IntegrationKernelRef keeps direct inline and side sample contracts" {
    const direct = sampling_table.IntegrationKernelRef.disabled();
    const direct_storage_values = [_]f64{0.0};
    const direct_storage = sampling_table.IntegrationKernelStorage{
        .offsets_nm = direct_storage_values[0..],
        .weights = direct_storage_values[0..],
    };
    try std.testing.expectEqual(false, direct.enabled());
    try std.testing.expectEqual(@as(usize, 1), direct.activeSampleCount());
    try std.testing.expectApproxEqAbs(0.0, direct.offsetNm(direct_storage, 0), 0.0);
    try std.testing.expectApproxEqAbs(1.0, direct.weight(direct_storage, 0), 0.0);

    var inline_ref = sampling_table.IntegrationKernelRef{
        .sample_count = 3,
        .encoding = .inline_samples,
    };
    inline_ref.inline_offsets_nm[0..3].* = .{ -0.02, 0.0, 0.02 };
    inline_ref.inline_weights[0..3].* = .{ 0.25, 0.5, 0.25 };
    const inline_samples = inline_ref.samples(.{});
    try std.testing.expectEqual(@as(usize, 3), inline_ref.activeSampleCount());
    try std.testing.expectApproxEqAbs(-0.02, inline_samples.offsets_nm[0], 0.0);
    try std.testing.expectApproxEqAbs(0.5, inline_ref.weight(direct_storage, 1), 0.0);

    const side_offsets = [_]f64{ 1.0, 1.5, 2.0, 2.5 };
    const side_weights = [_]f64{ 0.1, 0.2, 0.3, 0.4 };
    const side_ref = sampling_table.IntegrationKernelRef{
        .side_start = 1,
        .sample_count = 2,
        .encoding = .side_samples,
    };
    const side_storage = sampling_table.IntegrationKernelStorage{
        .offsets_nm = side_offsets[0..],
        .weights = side_weights[0..],
    };
    const side_samples = side_ref.samples(side_storage);
    try std.testing.expectApproxEqAbs(1.5, side_samples.offsets_nm[0], 0.0);
    try std.testing.expectApproxEqAbs(2.0, side_ref.offsetNm(side_storage, 1), 0.0);
    try std.testing.expectApproxEqAbs(0.2, side_ref.weight(side_storage, 0), 0.0);
}

test "SpectrumSamplingTable summary matches O2 A aggregate sampling evidence shape" {
    const side_offsets = [_]f64{ -0.02, 0.0, 0.02, -0.01, 0.01 };
    const side_weights = [_]f64{ 0.25, 0.5, 0.25, 0.5, 0.5 };
    const rows = [_]sampling_table.SpectrumSamplingRow{
        .{
            .nominal_wavelength_nm = 760.0,
            .radiance_wavelength_nm = 760.0,
            .irradiance_wavelength_nm = 760.0,
            .radiance_integration = .disabled(),
            .irradiance_integration = .disabled(),
        },
        .{
            .nominal_wavelength_nm = 760.1,
            .radiance_wavelength_nm = 760.1,
            .irradiance_wavelength_nm = 760.1,
            .radiance_integration = .{
                .side_start = 0,
                .sample_count = 3,
                .encoding = .side_samples,
            },
            .irradiance_integration = .{
                .side_start = 3,
                .sample_count = 2,
                .encoding = .side_samples,
            },
        },
    };
    const table = sampling_table.SpectrumSamplingTable{
        .rows = rows[0..],
        .kernel_storage = .{
            .offsets_nm = side_offsets[0..],
            .weights = side_weights[0..],
        },
    };

    const summary = sampling_table.summarize(table);
    try std.testing.expectEqual(@as(usize, 2), summary.row_count);
    try std.testing.expectEqual(@as(usize, 1), summary.radiance_integrated_rows);
    try std.testing.expectEqual(@as(usize, 1), summary.irradiance_integrated_rows);
    try std.testing.expectEqual(@as(usize, 4), summary.radiance_sample_count);
    try std.testing.expectEqual(@as(usize, 3), summary.irradiance_sample_count);
    try std.testing.expectEqual(@as(usize, 5), summary.side_sample_count);
    try std.testing.expectEqual(@as(usize, 3), summary.max_kernel_sample_count);

    // Source: canonical O2 A sampling evidence fixtures.
    // Canonical expected values owned by this repository.
    try std.testing.expectEqual(@as(usize, 701), sampling_evidence.row_count);
    try std.testing.expectEqual(@as(usize, 565776), sampling_evidence.kernel_offsets_len);
    try std.testing.expectEqual(@as(usize, 282888), sampling_evidence.radiance_sample_count);
    try std.testing.expectEqual(@as(usize, 3874), sampling_evidence.forward_miss_count);
}

test "O2 SpectrumSamplingTable builder matches O2 A aggregate and exact-key evidence" {
    var tables = try internal.setup.run_tables.buildRunTables(
        std.testing.allocator,
        internal.input.defaults.referenceScene(),
    );
    defer tables.deinit(std.testing.allocator);

    var owned = try sampling_table.buildSpectrumSamplingTable(
        std.testing.allocator,
        internal.input.defaults.referenceScene(),
        tables.instrument,
        tables.lines,
    );
    defer owned.deinit(std.testing.allocator);

    const table = owned.view();
    const summary = sampling_table.summarize(table);

    // Source: canonical O2 A sampling evidence fixtures.
    // Canonical expected values owned by this repository.
    try std.testing.expectEqual(@as(usize, 701), summary.row_count);
    try std.testing.expectEqual(@as(usize, 701), summary.radiance_integrated_rows);
    try std.testing.expectEqual(@as(usize, 701), summary.irradiance_integrated_rows);
    try std.testing.expectEqual(@as(usize, 282888), summary.radiance_sample_count);
    try std.testing.expectEqual(@as(usize, 282888), summary.irradiance_sample_count);
    try std.testing.expectEqual(@as(usize, 565776), summary.side_sample_count);

    var list = try radiance_wavelengths.buildRadianceWavelengthList(std.testing.allocator, table);
    defer list.deinit(std.testing.allocator);

    // Source: same O2 A internal dump, sampling_table.forward_misses first/last rows.
    try std.testing.expectEqual(@as(usize, 3874), list.wavelengths.len);
    try std.testing.expectEqual(@as(u64, 4649845583965292708), list.wavelengths[0].key);
    try std.testing.expectApproxEqAbs(754.240334835155, list.wavelengths[0].wavelength_nm, 0.0);
    try std.testing.expectEqual(@as(u64, 4650044237975911787), list.wavelengths[list.wavelengths.len - 1].key);
    try std.testing.expectApproxEqAbs(776.8246811031544, list.wavelengths[list.wavelengths.len - 1].wavelength_nm, 0.0);
}

test "O2 SpectrumSamplingTable consumes explicit sparse measured wavelengths" {
    const explicit_wavelengths = [_]f64{ 758.0, 758.06, 758.21, 758.27 };
    var scene = internal.input.defaults.referenceScene();
    scene.spectral_grid = .{
        .start_nm = explicit_wavelengths[0],
        .end_nm = explicit_wavelengths[explicit_wavelengths.len - 1],
        .sample_count = explicit_wavelengths.len,
    };
    scene.observation.measured_wavelengths_nm = explicit_wavelengths[0..];

    try internal.input.validate.sceneControls(scene);

    var tables = try internal.setup.run_tables.buildRunTables(std.testing.allocator, scene);
    defer tables.deinit(std.testing.allocator);

    var owned = try sampling_table.buildSpectrumSamplingTable(
        std.testing.allocator,
        scene,
        tables.instrument,
        tables.lines,
    );
    defer owned.deinit(std.testing.allocator);

    const table = owned.view();
    try std.testing.expectEqual(explicit_wavelengths.len, table.rows.len);
    for (explicit_wavelengths, table.rows) |expected_wavelength_nm, row| {
        try std.testing.expectApproxEqAbs(expected_wavelength_nm, row.nominal_wavelength_nm, 0.0);
        try std.testing.expectApproxEqAbs(expected_wavelength_nm, row.radiance_wavelength_nm, 0.0);
        try std.testing.expectApproxEqAbs(expected_wavelength_nm, row.irradiance_wavelength_nm, 0.0);
    }
}

test "O2 SpectrumSamplingTable parallel fill keeps resolved samples deterministic" {
    var tables = try internal.setup.run_tables.buildRunTables(
        std.testing.allocator,
        internal.input.defaults.referenceScene(),
    );
    defer tables.deinit(std.testing.allocator);

    var first = try sampling_table.buildSpectrumSamplingTable(
        std.testing.allocator,
        internal.input.defaults.referenceScene(),
        tables.instrument,
        tables.lines,
    );
    defer first.deinit(std.testing.allocator);

    var second = try sampling_table.buildSpectrumSamplingTable(
        std.testing.allocator,
        internal.input.defaults.referenceScene(),
        tables.instrument,
        tables.lines,
    );
    defer second.deinit(std.testing.allocator);

    try expectResolvedSamplingTablesEqual(first.view(), second.view());

    var first_list = try radiance_wavelengths.buildRadianceWavelengthList(std.testing.allocator, first.view());
    defer first_list.deinit(std.testing.allocator);
    var second_list = try radiance_wavelengths.buildRadianceWavelengthList(std.testing.allocator, second.view());
    defer second_list.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(
        u8,
        std.mem.sliceAsBytes(first_list.rows),
        std.mem.sliceAsBytes(second_list.rows),
    );
    try std.testing.expectEqualSlices(
        u8,
        std.mem.sliceAsBytes(first_list.sample_indices),
        std.mem.sliceAsBytes(second_list.sample_indices),
    );
    try std.testing.expectEqualSlices(
        u8,
        std.mem.sliceAsBytes(first_list.wavelengths),
        std.mem.sliceAsBytes(second_list.wavelengths),
    );
}

fn expectResolvedSamplingTablesEqual(
    expected: sampling_table.SpectrumSamplingTable,
    actual: sampling_table.SpectrumSamplingTable,
) !void {
    // expectResolvedSamplingTablesEqual ----------------------------------------------------------------------|
    // Compare sampling tables through row-resolved kernels. Parallel side-array appends may choose different  |
    // raw storage positions; row-visible offsets and weights must remain identical.                           |
    // --------------------------------------------------------------------------------------------------------|
    try std.testing.expectEqual(expected.rows.len, actual.rows.len);
    for (expected.rows, actual.rows) |expected_row, actual_row| {
        try std.testing.expectApproxEqAbs(
            expected_row.nominal_wavelength_nm,
            actual_row.nominal_wavelength_nm,
            0.0,
        );
        try std.testing.expectApproxEqAbs(
            expected_row.radiance_wavelength_nm,
            actual_row.radiance_wavelength_nm,
            0.0,
        );
        try std.testing.expectApproxEqAbs(
            expected_row.irradiance_wavelength_nm,
            actual_row.irradiance_wavelength_nm,
            0.0,
        );
        try expectResolvedKernelEqual(
            &expected_row.radiance_integration,
            expected.kernel_storage,
            &actual_row.radiance_integration,
            actual.kernel_storage,
        );
        try expectResolvedKernelEqual(
            &expected_row.irradiance_integration,
            expected.kernel_storage,
            &actual_row.irradiance_integration,
            actual.kernel_storage,
        );
    }
}

fn expectResolvedKernelEqual(
    expected: *const sampling_table.IntegrationKernelRef,
    expected_storage: sampling_table.IntegrationKernelStorage,
    actual: *const sampling_table.IntegrationKernelRef,
    actual_storage: sampling_table.IntegrationKernelStorage,
) !void {
    // expectResolvedKernelEqual ------------------------------------------------------------------------------|
    // Compare one compact kernel by active samples instead of side-array offsets.                             |
    // --------------------------------------------------------------------------------------------------------|
    const count = expected.activeSampleCount();
    try std.testing.expectEqual(count, actual.activeSampleCount());
    try std.testing.expectEqual(expected.enabled(), actual.enabled());
    for (0..count) |sample_index| {
        try std.testing.expectApproxEqAbs(
            expected.offsetNm(expected_storage, sample_index),
            actual.offsetNm(actual_storage, sample_index),
            0.0,
        );
        try std.testing.expectApproxEqAbs(
            expected.weight(expected_storage, sample_index),
            actual.weight(actual_storage, sample_index),
            0.0,
        );
    }
}

// SamplingEvidence ------------------------------------------------------------------------------------------ |
// Aggregate canonical sampling-table evidence from the O2 A internal dump.                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] row_count            : usize                                                                       |
// [ 8..15] kernel_offsets_len   : usize                                                                       |
// [16..23] radiance_sample_count: usize                                                                       |
// [24..31] forward_miss_count   : usize                                                                       |
const SamplingEvidence = struct {
    row_count: usize,
    kernel_offsets_len: usize,
    radiance_sample_count: usize,
    forward_miss_count: usize,
};
// ------------------------------------------------------------------------------------------------------------|

const sampling_evidence = SamplingEvidence{
    .row_count = 701,
    .kernel_offsets_len = 565776,
    .radiance_sample_count = 282888,
    .forward_miss_count = 3874,
};
