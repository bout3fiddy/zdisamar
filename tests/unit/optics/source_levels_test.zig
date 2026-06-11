const std = @import("std");
const internal = @import("internal");

const defaults = internal.input.defaults;
const layer_depths = internal.optics.layer_depths;
const setup = internal.setup.o2_run_tables;
const source_levels = internal.optics.source_levels;

const allocator = std.testing.allocator;

// SourceLevelEvidence ----------------------------------------------------------------------------------------|
// Test-local RTM source-level evidence from WP1 baseline artifact:                                            |
// scratch/refactor/2026-06-11-explicit-dataflow-refactor/evidence/baseline-main-56605387/                     |
// internal-dump-baseline.json .probe_forward_inputs[].rtm_quadrature_levels.                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_nm             : f64                                                                    |
// [ 8..15] altitude_km               : f64                                                                    |
// [16..23] weight_km                 : f64                                                                    |
// [24..31] scattering_per_km         : f64                                                                    |
// [32..39] aerosol_above_per_km      : f64                                                                    |
// [40..47] aerosol_below_per_km      : f64                                                                    |
// [48..55] aerosol_jacobian          : f64                                                                    |
// [56..63] phase_aerosol_weight      : f64                                                                    |
// [64..71] phase_rayleigh2_weight    : f64                                                                    |
// [72..75] level_index               : u32                                                                    |
// [76..79] trailing padding          : 4 B                                                                    |
const SourceLevelEvidence = struct {
    wavelength_nm: f64,
    altitude_km: f64,
    weight_km: f64,
    scattering_per_km: f64,
    aerosol_above_per_km: f64,
    aerosol_below_per_km: f64,
    aerosol_jacobian: f64,
    phase_aerosol_weight: f64,
    phase_rayleigh2_weight: f64,
    level_index: u32,
};
// ------------------------------------------------------------------------------------------------------------|

const source_probe_levels = [_]SourceLevelEvidence{
    .{
        .wavelength_nm = 758.0,
        .level_index = 0,
        .altitude_km = -0.00003636916272619,
        .weight_km = 0.0,
        .scattering_per_km = 0.00305937727037848,
        .aerosol_above_per_km = 0.0,
        .aerosol_below_per_km = 0.0,
        .aerosol_jacobian = 0.0,
        .phase_aerosol_weight = 0.0,
        .phase_rayleigh2_weight = 0.47949656030102394,
    },
    .{
        .wavelength_nm = 758.0,
        .level_index = 1,
        .altitude_km = 0.10860293690967149,
        .weight_km = 0.27694178281245890,
        .scattering_per_km = 0.00302279042336847,
        .aerosol_above_per_km = 0.0,
        .aerosol_below_per_km = 0.0,
        .aerosol_jacobian = 0.0,
        .phase_aerosol_weight = 0.0,
        .phase_rayleigh2_weight = 0.47949656030102394,
    },
    .{
        .wavelength_nm = 758.0,
        .level_index = 9,
        .altitude_km = 5.471578512594435,
        .weight_km = 0.0,
        .scattering_per_km = 0.99224376262759910,
        .aerosol_above_per_km = 0.99049578533935790,
        .aerosol_below_per_km = 0.0,
        .aerosol_jacobian = 0.0,
        .phase_aerosol_weight = 0.99823835900604470,
        .phase_rayleigh2_weight = 0.00084470079708681,
    },
    .{
        .wavelength_nm = 758.0,
        .level_index = 10,
        .altitude_km = 5.481805282884080,
        .weight_km = 0.02594526320782963,
        .scattering_per_km = 0.99224186003154770,
        .aerosol_above_per_km = 0.99049578533935790,
        .aerosol_below_per_km = 0.99049578533935790,
        .aerosol_jacobian = 3.30165261779785930,
        .phase_aerosol_weight = 0.99824027310021550,
        .phase_rayleigh2_weight = 0.00084378299551588,
    },
    .{
        .wavelength_nm = 760.0,
        .level_index = 0,
        .altitude_km = -0.00003636916272619,
        .weight_km = 0.0,
        .scattering_per_km = 0.00302696546309659,
        .aerosol_above_per_km = 0.0,
        .aerosol_below_per_km = 0.0,
        .aerosol_jacobian = 0.0,
        .phase_aerosol_weight = 0.0,
        .phase_rayleigh2_weight = 0.47949897135222913,
    },
    .{
        .wavelength_nm = 760.0,
        .level_index = 1,
        .altitude_km = 0.10860293690967149,
        .weight_km = 0.27694178281245890,
        .scattering_per_km = 0.00299076622628616,
        .aerosol_above_per_km = 0.0,
        .aerosol_below_per_km = 0.0,
        .aerosol_jacobian = 0.0,
        .phase_aerosol_weight = 0.0,
        .phase_rayleigh2_weight = 0.47949897135222910,
    },
    .{
        .wavelength_nm = 760.0,
        .level_index = 9,
        .altitude_km = 5.471578512594435,
        .weight_km = 0.0,
        .scattering_per_km = 0.99222524411942160,
        .aerosol_above_per_km = 0.99049578533935790,
        .aerosol_below_per_km = 0.0,
        .aerosol_jacobian = 0.0,
        .phase_aerosol_weight = 0.99825698974067280,
        .phase_rayleigh2_weight = 0.00083577162640381,
    },
    .{
        .wavelength_nm = 760.0,
        .level_index = 10,
        .altitude_km = 5.481805282884080,
        .weight_km = 0.02594526320782963,
        .scattering_per_km = 0.99222336167994820,
        .aerosol_above_per_km = 0.99049578533935790,
        .aerosol_below_per_km = 0.99049578533935790,
        .aerosol_jacobian = 3.30165261779785930,
        .phase_aerosol_weight = 0.99825888362710470,
        .phase_rayleigh2_weight = 0.00083486350980786,
    },
    .{
        .wavelength_nm = 765.0,
        .level_index = 0,
        .altitude_km = -0.00003636916272619,
        .weight_km = 0.0,
        .scattering_per_km = 0.00294779793766349,
        .aerosol_above_per_km = 0.0,
        .aerosol_below_per_km = 0.0,
        .aerosol_jacobian = 0.0,
        .phase_aerosol_weight = 0.0,
        .phase_rayleigh2_weight = 0.47950490768768306,
    },
    .{
        .wavelength_nm = 765.0,
        .level_index = 1,
        .altitude_km = 0.10860293690967149,
        .weight_km = 0.27694178281245890,
        .scattering_per_km = 0.00291254545893001,
        .aerosol_above_per_km = 0.0,
        .aerosol_below_per_km = 0.0,
        .aerosol_jacobian = 0.0,
        .phase_aerosol_weight = 0.0,
        .phase_rayleigh2_weight = 0.47950490768768306,
    },
    .{
        .wavelength_nm = 765.0,
        .level_index = 9,
        .altitude_km = 5.471578512594435,
        .weight_km = 0.0,
        .scattering_per_km = 0.99218001169981670,
        .aerosol_above_per_km = 0.99049578533935790,
        .aerosol_below_per_km = 0.0,
        .aerosol_jacobian = 0.0,
        .phase_aerosol_weight = 0.99830249920317040,
        .phase_rayleigh2_weight = 0.00081395996288352,
    },
    .{
        .wavelength_nm = 765.0,
        .level_index = 10,
        .altitude_km = 5.481805282884080,
        .weight_km = 0.02594526320782963,
        .scattering_per_km = 0.99217817849383360,
        .aerosol_above_per_km = 0.99049578533935790,
        .aerosol_below_per_km = 0.99049578533935790,
        .aerosol_jacobian = 3.30165261779785930,
        .phase_aerosol_weight = 0.99830434372480400,
        .phase_rayleigh2_weight = 0.00081307550570797,
    },
    .{
        .wavelength_nm = 767.0,
        .level_index = 0,
        .altitude_km = -0.00003636916272619,
        .weight_km = 0.0,
        .scattering_per_km = 0.00291685809527106,
        .aerosol_above_per_km = 0.0,
        .aerosol_below_per_km = 0.0,
        .aerosol_jacobian = 0.0,
        .phase_aerosol_weight = 0.0,
        .phase_rayleigh2_weight = 0.47950724634312770,
    },
    .{
        .wavelength_nm = 767.0,
        .level_index = 1,
        .altitude_km = 0.10860293690967149,
        .weight_km = 0.27694178281245890,
        .scattering_per_km = 0.00288197562362729,
        .aerosol_above_per_km = 0.0,
        .aerosol_below_per_km = 0.0,
        .aerosol_jacobian = 0.0,
        .phase_aerosol_weight = 0.0,
        .phase_rayleigh2_weight = 0.47950724634312775,
    },
    .{
        .wavelength_nm = 767.0,
        .level_index = 9,
        .altitude_km = 5.471578512594435,
        .weight_km = 0.0,
        .scattering_per_km = 0.99216233419978180,
        .aerosol_above_per_km = 0.99049578533935790,
        .aerosol_below_per_km = 0.0,
        .aerosol_jacobian = 0.0,
        .phase_aerosol_weight = 0.99832028610341460,
        .phase_rayleigh2_weight = 0.00080543498519593,
    },
    .{
        .wavelength_nm = 767.0,
        .level_index = 10,
        .altitude_km = 5.481805282884080,
        .weight_km = 0.02594526320782963,
        .scattering_per_km = 0.99216052023497660,
        .aerosol_above_per_km = 0.99049578533935790,
        .aerosol_below_per_km = 0.99049578533935790,
        .aerosol_jacobian = 3.30165261779785930,
        .phase_aerosol_weight = 0.99832211133010580,
        .phase_rayleigh2_weight = 0.00080455977577134,
    },
    .{
        .wavelength_nm = 776.0,
        .level_index = 0,
        .altitude_km = -0.00003636916272619,
        .weight_km = 0.0,
        .scattering_per_km = 0.00278255834267577,
        .aerosol_above_per_km = 0.0,
        .aerosol_below_per_km = 0.0,
        .aerosol_jacobian = 0.0,
        .phase_aerosol_weight = 0.0,
        .phase_rayleigh2_weight = 0.47951752434192885,
    },
    .{
        .wavelength_nm = 776.0,
        .level_index = 1,
        .altitude_km = 0.10860293690967149,
        .weight_km = 0.27694178281245890,
        .scattering_per_km = 0.00274928195098469,
        .aerosol_above_per_km = 0.0,
        .aerosol_below_per_km = 0.0,
        .aerosol_jacobian = 0.0,
        .phase_aerosol_weight = 0.0,
        .phase_rayleigh2_weight = 0.47951752434192890,
    },
    .{
        .wavelength_nm = 776.0,
        .level_index = 9,
        .altitude_km = 5.471578512594435,
        .weight_km = 0.0,
        .scattering_per_km = 0.99208560194461800,
        .aerosol_above_per_km = 0.99049578533935790,
        .aerosol_below_per_km = 0.0,
        .aerosol_jacobian = 0.0,
        .phase_aerosol_weight = 0.99839750057641820,
        .phase_rayleigh2_weight = 0.00076842655635536,
    },
    .{
        .wavelength_nm = 776.0,
        .level_index = 10,
        .altitude_km = 5.481805282884080,
        .weight_km = 0.02594526320782963,
        .scattering_per_km = 0.99208387149948240,
        .aerosol_above_per_km = 0.99049578533935790,
        .aerosol_below_per_km = 0.99049578533935790,
        .aerosol_jacobian = 3.30165261779785930,
        .phase_aerosol_weight = 0.99839924203411940,
        .phase_rayleigh2_weight = 0.00076759149686973,
    },
};

test "source levels reproduce shared RTM quadrature evidence rows" {
    var tables = try setup.buildReferenceO2RunTables(allocator, defaults.referenceCase());
    defer tables.deinit(allocator);

    const line_sigma = try allocator.alloc(f64, tables.layers.support_mid_altitudes_km.len);
    defer allocator.free(line_sigma);
    @memset(line_sigma, 0.0);

    const support_rows = try allocator.alloc(layer_depths.SupportOptics, tables.layers.support_mid_altitudes_km.len);
    defer allocator.free(support_rows);
    const levels = try allocator.alloc(source_levels.SourceLevel, tables.layers.layer_pressures_hpa.len + 1);
    defer allocator.free(levels);

    var previous_wavelength_nm: f64 = -1.0;
    for (source_probe_levels) |expected| {
        if (expected.wavelength_nm != previous_wavelength_nm) {
            try layer_depths.fillSupportOpticsAtWavelength(
                expected.wavelength_nm,
                tables.layers,
                line_sigma,
                tables.cia,
                tables.aerosol,
                support_rows,
            );
            try source_levels.fillSourceLevelsAtWavelength(
                expected.wavelength_nm,
                tables.layers,
                support_rows,
                tables.aerosol,
                levels,
            );
            previous_wavelength_nm = expected.wavelength_nm;
        }

        const actual = levels[@intCast(expected.level_index)];
        try expectClose(expected.altitude_km, actual.altitude_km, 1.0e-14);
        try expectClose(expected.weight_km, actual.weight_km, 1.0e-14);
        try expectClose(expected.scattering_per_km, actual.scattering_per_km, 1.0e-14);
        try expectClose(expected.aerosol_above_per_km, actual.aerosol_ksca_above_per_km, 1.0e-14);
        try expectClose(expected.aerosol_below_per_km, actual.aerosol_ksca_below_per_km, 1.0e-14);
        try expectClose(expected.aerosol_jacobian, actual.aerosol_ksca_jacobian, 1.0e-14);
        try expectClose(expected.phase_aerosol_weight, actual.phase_aerosol_weight, 1.0e-14);
        try expectClose(expected.phase_rayleigh2_weight, actual.phase_rayleigh2_weight, 1.0e-14);
    }
}

fn expectClose(expected: f64, actual: f64, tolerance: f64) !void {
    // expectClose --------------------------------------------------------------------------------------------|
    // Compare evidence decimals after JSON parsing and Zig floating-point recomputation.                      |
    // --------------------------------------------------------------------------------------------------------|
    try std.testing.expectApproxEqAbs(expected, actual, tolerance);
}
