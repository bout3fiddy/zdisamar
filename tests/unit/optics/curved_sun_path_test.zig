const std = @import("std");
const internal = @import("internal");

const curved_sun_path = internal.optics.curved_sun_path;
const defaults = internal.input.defaults;
const layer_depths = internal.optics.layer_depths;
const setup = internal.setup.o2_run_tables;

const allocator = std.testing.allocator;

// CurvedSampleEvidence ---------------------------------------------------------------------------------------|
// Test-local pseudo-spherical evidence from O2 A baseline artifacts:                                          |
// Canonical expected values owned by this repository.                                                         |
// internal-dump-baseline.json .probe_forward_inputs[].pseudo_spherical.samples plus                           |
// public-python-baseline.json .diagnostics.atmospheric_budget.rows for the line-absorption support values.    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 56 B (0.055 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_nm          : f64                                                                       |
// [ 8..15] altitude_km            : f64                                                                       |
// [16..23] thickness_km           : f64                                                                       |
// [24..31] optical_depth          : f64                                                                       |
// [32..39] gas_absorption_depth   : f64                                                                       |
// [40..43] sample_index           : u32                                                                       |
// [44..47] support_index          : u32                                                                       |
// [48..55] trailing padding       : 8 B                                                                       |
const CurvedSampleEvidence = struct {
    wavelength_nm: f64,
    altitude_km: f64,
    thickness_km: f64,
    optical_depth: f64,
    gas_absorption_depth: f64,
    sample_index: u32,
    support_index: u32,
};
// ------------------------------------------------------------------------------------------------------------|

const curved_samples = [_]CurvedSampleEvidence{
    .{
        .wavelength_nm = 758.0,
        .sample_index = 0,
        .support_index = 1,
        .altitude_km = 0.00750665821081170,
        .thickness_km = 0.01889535449482717,
        .optical_depth = 0.00008526373793855,
        .gas_absorption_depth = 0.000014827869850978738,
    },
    .{
        .wavelength_nm = 758.0,
        .sample_index = 36,
        .support_index = 46,
        .altitude_km = 5.47228857611588550,
        .thickness_km = 0.00177871579768035,
        .optical_depth = 0.00176573855575988,
        .gas_absorption_depth = 4.2897357349395436e-7,
    },
    .{
        .wavelength_nm = 760.0,
        .sample_index = 0,
        .support_index = 1,
        .altitude_km = 0.00750665821081170,
        .thickness_km = 0.01889535449482717,
        .optical_depth = 0.00393143472191721,
        .gas_absorption_depth = 0.003851103825908674,
    },
    .{
        .wavelength_nm = 760.0,
        .sample_index = 36,
        .support_index = 46,
        .altitude_km = 5.47228857611588550,
        .thickness_km = 0.00177871579768035,
        .optical_depth = 0.00186499577590851,
        .gas_absorption_depth = 0.00009939575717554341,
    },
    .{
        .wavelength_nm = 765.0,
        .sample_index = 0,
        .support_index = 1,
        .altitude_km = 0.00750665821081170,
        .thickness_km = 0.01889535449482717,
        .optical_depth = 0.00073121424798936,
        .gas_absorption_depth = 0.0006483670238492417,
    },
    .{
        .wavelength_nm = 765.0,
        .sample_index = 36,
        .support_index = 46,
        .altitude_km = 5.47228857611588550,
        .thickness_km = 0.00177871579768035,
        .optical_depth = 0.00178369648632854,
        .gas_absorption_depth = 0.000018053471548296597,
    },
    .{
        .wavelength_nm = 767.0,
        .sample_index = 0,
        .support_index = 1,
        .altitude_km = 0.00750665821081170,
        .thickness_km = 0.01889535449482717,
        .optical_depth = 0.00014822301585020,
        .gas_absorption_depth = 0.00007927523435585222,
    },
    .{
        .wavelength_nm = 767.0,
        .sample_index = 36,
        .support_index = 46,
        .altitude_km = 5.47228857611588550,
        .thickness_km = 0.00177871579768035,
        .optical_depth = 0.00176705882708530,
        .gas_absorption_depth = 0.0000018570602314331646,
    },
    .{
        .wavelength_nm = 776.0,
        .sample_index = 0,
        .support_index = 1,
        .altitude_km = 0.00750665821081170,
        .thickness_km = 0.01889535449482717,
        .optical_depth = 0.00005362539954467,
        .gas_absorption_depth = 5.35307046857685e-7,
    },
    .{
        .wavelength_nm = 776.0,
        .sample_index = 36,
        .support_index = 46,
        .altitude_km = 5.47228857611588550,
        .thickness_km = 0.00177871579768035,
        .optical_depth = 0.00176466967713843,
        .gas_absorption_depth = 1.4403791004503387e-8,
    },
};

test "curved sun-path samples reuse active support rows in evidence order" {
    var tables = try setup.buildO2RunTables(allocator, defaults.referenceCase());
    defer tables.deinit(allocator);

    const line_sigma = try allocator.alloc(f64, tables.layers.support_mid_altitudes_km.len);
    defer allocator.free(line_sigma);
    const support_rows = try allocator.alloc(layer_depths.SupportOptics, tables.layers.support_mid_altitudes_km.len);
    defer allocator.free(support_rows);
    const samples = try allocator.alloc(curved_sun_path.CurvedSunPathSample, 180);
    defer allocator.free(samples);
    const starts = try allocator.alloc(usize, tables.layers.layer_pressures_hpa.len + 1);
    defer allocator.free(starts);
    const level_altitudes = try allocator.alloc(f64, tables.layers.layer_pressures_hpa.len + 1);
    defer allocator.free(level_altitudes);

    var previous_wavelength_nm: f64 = -1.0;
    for (curved_samples) |expected| {
        if (expected.wavelength_nm != previous_wavelength_nm) {
            @memset(line_sigma, 0.0);
            for (curved_samples) |line_expected| {
                if (line_expected.wavelength_nm != expected.wavelength_nm) continue;

                const support_index: usize = @intCast(line_expected.support_index);
                line_sigma[support_index] =
                    line_expected.gas_absorption_depth /
                    (tables.layers.support_o2_number_densities_cm3[support_index] *
                        tables.layers.support_path_lengths_cm[support_index]);
            }

            try layer_depths.fillSupportOpticsAtWavelength(
                expected.wavelength_nm,
                tables.layers,
                line_sigma,
                tables.cia,
                tables.aerosol,
                support_rows,
            );
            const sample_count = try curved_sun_path.fillCurvedSunPathSamples(
                tables.layers,
                support_rows,
                samples,
                starts,
                level_altitudes,
            );
            try std.testing.expectEqual(@as(usize, 180), sample_count);
            try std.testing.expectEqual(@as(usize, 0), starts[0]);
            try std.testing.expectEqual(@as(usize, 36), starts[9]);
            try std.testing.expectEqual(@as(usize, 180), starts[45]);
            try expectClose(-0.00003636916272619, level_altitudes[0], 1.0e-14);
            try expectClose(5.471578512594435, level_altitudes[9], 1.0e-14);

            previous_wavelength_nm = expected.wavelength_nm;
        }

        const actual = samples[@intCast(expected.sample_index)];
        try expectClose(expected.altitude_km, actual.altitude_km, 1.0e-14);
        try expectClose(expected.thickness_km, actual.thickness_km, 1.0e-14);
        try expectClose(expected.optical_depth, actual.optical_depth, 1.0e-14);
    }
}

fn expectClose(expected: f64, actual: f64, tolerance: f64) !void {
    // expectClose --------------------------------------------------------------------------------------------|
    // Compare evidence decimals after JSON parsing and Zig floating-point recomputation.                      |
    // --------------------------------------------------------------------------------------------------------|
    try std.testing.expectApproxEqAbs(expected, actual, tolerance);
}
