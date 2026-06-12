const std = @import("std");
const internal = @import("internal");

const defaults = internal.input.defaults;
const layer_depths = internal.optics.layer_depths;
const setup = internal.setup.o2_run_tables;
const jacobian = internal.transport.jacobian_states;

const allocator = std.testing.allocator;

// SupportEvidence ------------------------------------------------------------------------------------------- |
// Test-local support-row optics evidence from WP1 baseline artifact:                                          |
// scratch/refactor/2026-06-11-explicit-dataflow-refactor/evidence/baseline-main-56605387/                     |
// public-python-baseline.json .diagnostics.atmospheric_budget.rows.                                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 96 B (0.094 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_nm                    : f64                                                             |
// [ 8..15] gas_absorption_optical_depth     : f64                                                             |
// [16..23] gas_scattering_optical_depth     : f64                                                             |
// [24..31] cia_optical_depth                : f64                                                             |
// [32..39] total_optical_depth              : f64                                                             |
// [40..47] single_scatter_albedo            : f64                                                             |
// [48..55] path_length_cm                   : f64                                                             |
// [56..63] oxygen_number_density_cm3        : f64                                                             |
// [64..71] pressure_hpa                     : f64                                                             |
// [72..79] temperature_k                    : f64                                                             |
// [80..83] global_sublayer_index            : u32                                                             |
// [84..95] trailing padding                 : 12 B                                                            |
const SupportEvidence = struct {
    wavelength_nm: f64,
    gas_absorption_optical_depth: f64,
    gas_scattering_optical_depth: f64,
    cia_optical_depth: f64,
    total_optical_depth: f64,
    single_scatter_albedo: f64,
    path_length_cm: f64,
    oxygen_number_density_cm3: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    global_sublayer_index: u32,
};
// ------------------------------------------------------------------------------------------------------------|

const probe_row_one = [_]SupportEvidence{
    .{
        .wavelength_nm = 758.0,
        .global_sublayer_index = 1,
        .pressure_hpa = 1012.3624132494756,
        .temperature_k = 294.19449473014873,
        .path_length_cm = 1889.5354494827166,
        .oxygen_number_density_cm3 = 5.220552365887917e18,
        .gas_absorption_optical_depth = 0.000014827869850978738,
        .gas_scattering_optical_depth = 0.000057758864034137354,
        .cia_optical_depth = 0.0000126770040534369,
        .total_optical_depth = 0.00008526373793855298,
        .single_scatter_albedo = 0.6774141672719349,
    },
    .{
        .wavelength_nm = 760.0,
        .global_sublayer_index = 1,
        .pressure_hpa = 1012.3624132494756,
        .temperature_k = 294.19449473014873,
        .path_length_cm = 1889.5354494827166,
        .oxygen_number_density_cm3 = 5.220552365887917e18,
        .gas_absorption_optical_depth = 0.003851103825908674,
        .gas_scattering_optical_depth = 0.00005714695219573125,
        .cia_optical_depth = 0.00002318394381280432,
        .total_optical_depth = 0.00393143472191721,
        .single_scatter_albedo = 0.014535902599919775,
    },
    .{
        .wavelength_nm = 765.0,
        .global_sublayer_index = 1,
        .pressure_hpa = 1012.3624132494756,
        .temperature_k = 294.19449473014873,
        .path_length_cm = 1889.5354494827166,
        .oxygen_number_density_cm3 = 5.220552365887917e18,
        .gas_absorption_optical_depth = 0.0006483670238492417,
        .gas_scattering_optical_depth = 0.00005565232569716804,
        .cia_optical_depth = 0.000027194898442951984,
        .total_optical_depth = 0.0007312142479893617,
        .single_scatter_albedo = 0.0761094656596157,
    },
    .{
        .wavelength_nm = 767.0,
        .global_sublayer_index = 1,
        .pressure_hpa = 1012.3624132494756,
        .temperature_k = 294.19449473014873,
        .path_length_cm = 1889.5354494827166,
        .oxygen_number_density_cm3 = 5.220552365887917e18,
        .gas_absorption_optical_depth = 0.00007927523435585222,
        .gas_scattering_optical_depth = 0.000055068203507569326,
        .cia_optical_depth = 0.00001387957798678322,
        .total_optical_depth = 0.00014822301585020478,
        .single_scatter_albedo = 0.3715226221224755,
    },
    .{
        .wavelength_nm = 776.0,
        .global_sublayer_index = 1,
        .pressure_hpa = 1012.3624132494756,
        .temperature_k = 294.19449473014873,
        .path_length_cm = 1889.5354494827166,
        .oxygen_number_density_cm3 = 5.220552365887917e18,
        .gas_absorption_optical_depth = 5.35307046857685e-7,
        .gas_scattering_optical_depth = 0.000052532719824312994,
        .cia_optical_depth = 5.57372673497254e-7,
        .total_optical_depth = 0.000053625399544667935,
        .single_scatter_albedo = 0.979623840015499,
    },
};

const layer_zero_758_rows = [_]SupportEvidence{
    .{
        .wavelength_nm = 758.0,
        .global_sublayer_index = 1,
        .path_length_cm = 1889.5354494827166,
        .oxygen_number_density_cm3 = 5.220552365887917e18,
        .gas_absorption_optical_depth = 0.000014827869850978738,
        .gas_scattering_optical_depth = 0.000057758864034137354,
        .cia_optical_depth = 0.0000126770040534369,
        .total_optical_depth = 0.00008526373793855298,
        .single_scatter_albedo = 0.6774141672719349,
        .pressure_hpa = 1012.3624132494756,
        .temperature_k = 294.19449473014873,
    },
    .{
        .wavelength_nm = 758.0,
        .global_sublayer_index = 2,
        .path_length_cm = 3542.4298541371663,
        .oxygen_number_density_cm3 = 5.204022049190407e18,
        .gas_absorption_optical_depth = 0.00002762040644799749,
        .gas_scattering_optical_depth = 0.00010794127159646891,
        .cia_optical_depth = 0.00002361611477537931,
        .total_optical_depth = 0.00015917779281984573,
        .single_scatter_albedo = 0.6781176550087907,
        .pressure_hpa = 1009.0377743170635,
        .temperature_k = 294.15977339734,
    },
    .{
        .wavelength_nm = 758.0,
        .global_sublayer_index = 3,
        .path_length_cm = 3542.4298541371663,
        .oxygen_number_density_cm3 = 5.182784258373569e18,
        .gas_absorption_optical_depth = 0.000027391391958245157,
        .gas_scattering_optical_depth = 0.0001075007595992098,
        .cia_optical_depth = 0.00002342377571875226,
        .total_optical_depth = 0.00015831592727620723,
        .single_scatter_albedo = 0.6790268133392396,
        .pressure_hpa = 1004.7153179084555,
        .temperature_k = 294.0999008264475,
    },
    .{
        .wavelength_nm = 758.0,
        .global_sublayer_index = 4,
        .path_length_cm = 1889.5354494827166,
        .oxygen_number_density_cm3 = 5.166748466394038e18,
        .gas_absorption_optical_depth = 0.000014518405013130312,
        .gas_scattering_optical_depth = 0.00005716359136994968,
        .cia_optical_depth = 0.000012417079763928294,
        .total_optical_depth = 0.00008409907614700829,
        .single_scatter_albedo = 0.6797172333977322,
        .pressure_hpa = 1001.4140088615687,
        .temperature_k = 294.0433275118283,
    },
};

// LayerAerosolEvidence ---------------------------------------------------------------------------------------|
// Test-local aerosol layer evidence from WP1 baseline artifact:                                               |
// scratch/refactor/2026-06-11-explicit-dataflow-refactor/evidence/baseline-main-56605387/                     |
// internal-dump-baseline.json .probe_forward_inputs[0].layers.                                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] aerosol_optical_depth           : f64                                                              |
// [ 8..15] aerosol_scattering_optical_depth: f64                                                              |
// [16..19] layer_index                     : u32                                                              |
// [20..23] trailing padding                : 4 B                                                              |
const LayerAerosolEvidence = struct {
    aerosol_optical_depth: f64,
    aerosol_scattering_optical_depth: f64,
    layer_index: u32,
};
// ------------------------------------------------------------------------------------------------------------|

// LayerJacobianEvidence --------------------------------------------------------------------------------------|
// Test-local aerosol Jacobian values derived from old-route evidence and formula.                             |
//                                                                                                             |
// source                                                                                                      |
//   Scalars come from baseline-main-56605387/internal-dump-baseline.json                                      |
//   .probe_forward_inputs[0].layers. The formula is main:`state_build/forward_layers.zig`                     |
//   attachAerosolOpticalDepthJacobian with aerosol optical depth = 0.3.                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] gas_absorption_optical_depth      : f64                                                            |
// [ 8..15] optical_depth_derivative          : f64                                                            |
// [16..23] scattering_optical_depth_derivative: f64                                                           |
// [24..31] single_scatter_albedo_derivative  : f64                                                            |
// [32..35] layer_index                       : u32                                                            |
// [36..47] trailing padding                  : 12 B                                                           |
const LayerJacobianEvidence = struct {
    gas_absorption_optical_depth: f64,
    optical_depth_derivative: f64,
    scattering_optical_depth_derivative: f64,
    single_scatter_albedo_derivative: f64,
    layer_index: u32,
};
// ------------------------------------------------------------------------------------------------------------|

const aerosol_layers_758 = [_]LayerAerosolEvidence{
    .{
        .layer_index = 9,
        .aerosol_optical_depth = 0.01012957286952694,
        .aerosol_scattering_optical_depth = 0.01012957286952694,
    },
    .{
        .layer_index = 10,
        .aerosol_optical_depth = 0.04068901916053303,
        .aerosol_scattering_optical_depth = 0.04068901916053303,
    },
    .{
        .layer_index = 11,
        .aerosol_optical_depth = 0.06338853005746009,
        .aerosol_scattering_optical_depth = 0.06338853005746009,
    },
    .{
        .layer_index = 12,
        .aerosol_optical_depth = 0.07158575582495894,
        .aerosol_scattering_optical_depth = 0.07158575582495894,
    },
    .{
        .layer_index = 13,
        .aerosol_optical_depth = 0.06338853005746009,
        .aerosol_scattering_optical_depth = 0.06338853005746009,
    },
    .{
        .layer_index = 14,
        .aerosol_optical_depth = 0.04068901916053303,
        .aerosol_scattering_optical_depth = 0.04068901916053303,
    },
    .{
        .layer_index = 15,
        .aerosol_optical_depth = 0.01012957286952782,
        .aerosol_scattering_optical_depth = 0.01012957286952782,
    },
};

const aerosol_jacobian_layers_758 = [_]LayerJacobianEvidence{
    .{
        .layer_index = 9,
        .gas_absorption_optical_depth = 0.00000246394159728,
        .optical_depth_derivative = 0.033765242898423135,
        .scattering_optical_depth_derivative = 0.033765242898423135,
        .single_scatter_albedo_derivative = 0.0015414220169939379,
    },
    .{
        .layer_index = 12,
        .gas_absorption_optical_depth = 0.00001684577436891,
        .optical_depth_derivative = 0.23861918608319646,
        .scattering_optical_depth_derivative = 0.23861918608319646,
        .single_scatter_albedo_derivative = 0.0014927223923151265,
    },
    .{
        .layer_index = 15,
        .gas_absorption_optical_depth = 0.00000230590151375,
        .optical_depth_derivative = 0.033765242898426064,
        .scattering_optical_depth_derivative = 0.033765242898426064,
        .single_scatter_albedo_derivative = 0.001445446413616297,
    },
};

test "support-row optics reproduce atmospheric-budget components at probe wavelengths" {
    var tables = try setup.buildO2RunTables(allocator, defaults.referenceCase());
    defer tables.deinit(allocator);

    var line_sigma = try allocator.alloc(f64, tables.layers.support_mid_altitudes_km.len);
    defer allocator.free(line_sigma);
    const support_rows = try allocator.alloc(layer_depths.SupportOptics, tables.layers.support_mid_altitudes_km.len);
    defer allocator.free(support_rows);
    var zero_aerosol = tables.aerosol;
    zero_aerosol.optical_depth = 0.0;

    for (probe_row_one) |expected| {
        @memset(line_sigma, 0.0);
        const support_index: usize = @intCast(expected.global_sublayer_index);
        line_sigma[support_index] =
            expected.gas_absorption_optical_depth /
            (tables.layers.support_o2_number_densities_cm3[support_index] *
                tables.layers.support_path_lengths_cm[support_index]);

        try layer_depths.fillSupportOpticsAtWavelength(
            expected.wavelength_nm,
            tables.layers,
            line_sigma,
            tables.cia,
            zero_aerosol,
            support_rows,
        );

        const actual = support_rows[support_index];
        try expectClose(expected.gas_absorption_optical_depth, actual.gas_absorption_optical_depth, 1.0e-18);
        try expectClose(expected.gas_scattering_optical_depth, actual.gas_scattering_optical_depth, 1.0e-18);
        try expectClose(expected.cia_optical_depth, actual.cia_optical_depth, 1.0e-18);
        try expectClose(expected.total_optical_depth, actual.total_optical_depth, 1.0e-18);
        try expectClose(expected.single_scatter_albedo, actual.single_scatter_albedo, 1.0e-14);
    }
}

test "layer optics reduce active support rows and skip boundary rows" {
    var tables = try setup.buildO2RunTables(allocator, defaults.referenceCase());
    defer tables.deinit(allocator);

    var line_sigma = try allocator.alloc(f64, tables.layers.support_mid_altitudes_km.len);
    defer allocator.free(line_sigma);
    @memset(line_sigma, 0.0);
    for (layer_zero_758_rows) |expected| {
        const support_index: usize = @intCast(expected.global_sublayer_index);
        line_sigma[support_index] =
            expected.gas_absorption_optical_depth /
            (tables.layers.support_o2_number_densities_cm3[support_index] *
                tables.layers.support_path_lengths_cm[support_index]);
    }

    const support_rows = try allocator.alloc(layer_depths.SupportOptics, tables.layers.support_mid_altitudes_km.len);
    defer allocator.free(support_rows);
    var zero_aerosol = tables.aerosol;
    zero_aerosol.optical_depth = 0.0;
    try layer_depths.fillSupportOpticsAtWavelength(
        758.0,
        tables.layers,
        line_sigma,
        tables.cia,
        zero_aerosol,
        support_rows,
    );

    const layers = try allocator.alloc(layer_depths.LayerOptics, tables.layers.layer_pressures_hpa.len);
    defer allocator.free(layers);
    try layer_depths.reduceLayerOpticsFromSupportRows(tables.layers, support_rows, layers);

    try std.testing.expectEqual(@as(usize, 0), layers[0].support_start);
    try std.testing.expectEqual(@as(usize, 6), layers[0].support_count);
    try expectClose(8.435807327035171e-5, layers[0].gas_absorption_optical_depth, 1.0e-18);
    try expectClose(0.0003303644865997658, layers[0].gas_scattering_optical_depth, 1.0e-18);
    try expectClose(7.213397431149677e-5, layers[0].cia_optical_depth, 1.0e-18);
    try expectClose(0.00048685653418161423, layers[0].total_optical_depth, 1.0e-18);
    try expectClose(0.6785664018150539, layers[0].single_scatter_albedo, 1.0e-14);
}

test "layer optics place aerosol optical depth on the configured explicit interval" {
    var tables = try setup.buildO2RunTables(allocator, defaults.referenceCase());
    defer tables.deinit(allocator);

    const line_sigma = try allocator.alloc(f64, tables.layers.support_mid_altitudes_km.len);
    defer allocator.free(line_sigma);
    @memset(line_sigma, 0.0);

    const support_rows = try allocator.alloc(layer_depths.SupportOptics, tables.layers.support_mid_altitudes_km.len);
    defer allocator.free(support_rows);
    try layer_depths.fillSupportOpticsAtWavelength(
        758.0,
        tables.layers,
        line_sigma,
        tables.cia,
        tables.aerosol,
        support_rows,
    );

    const layers = try allocator.alloc(layer_depths.LayerOptics, tables.layers.layer_pressures_hpa.len);
    defer allocator.free(layers);
    try layer_depths.reduceLayerOpticsFromSupportRows(tables.layers, support_rows, layers);

    for (aerosol_layers_758) |expected| {
        const layer_index: usize = @intCast(expected.layer_index);
        try expectClose(expected.aerosol_optical_depth, layers[layer_index].aerosol_optical_depth, 1.0e-16);
        try expectClose(
            expected.aerosol_scattering_optical_depth,
            layers[layer_index].aerosol_scattering_optical_depth,
            1.0e-16,
        );
    }
}

test "layer optics fill aerosol optical-depth jacobian lanes from old route formula" {
    var tables = try setup.buildO2RunTables(allocator, defaults.referenceCase());
    defer tables.deinit(allocator);

    const line_sigma = try allocator.alloc(f64, tables.layers.support_mid_altitudes_km.len);
    defer allocator.free(line_sigma);
    @memset(line_sigma, 0.0);

    for (aerosol_jacobian_layers_758) |expected| {
        const layer_index: usize = @intCast(expected.layer_index);
        const support_index: usize = @intCast(tables.layers.layer_support_starts[layer_index] + 1);
        line_sigma[support_index] =
            expected.gas_absorption_optical_depth /
            (tables.layers.support_o2_number_densities_cm3[support_index] *
                tables.layers.support_path_lengths_cm[support_index]);
    }

    const support_rows = try allocator.alloc(layer_depths.SupportOptics, tables.layers.support_mid_altitudes_km.len);
    defer allocator.free(support_rows);
    try layer_depths.fillSupportOpticsAtWavelength(
        758.0,
        tables.layers,
        line_sigma,
        tables.cia,
        tables.aerosol,
        support_rows,
    );

    const layers = try allocator.alloc(layer_depths.LayerOptics, tables.layers.layer_pressures_hpa.len);
    defer allocator.free(layers);
    try layer_depths.reduceLayerOpticsFromSupportRows(tables.layers, support_rows, layers);
    layer_depths.fillLayerAerosolJacobians(
        tables.aerosol,
        jacobian.stateMask(.aerosol_optical_depth),
        layers,
    );

    for (aerosol_jacobian_layers_758) |expected| {
        const layer_index: usize = @intCast(expected.layer_index);
        const layer = layers[layer_index];
        try expectClose(
            expected.optical_depth_derivative,
            jacobian.get(layer.optical_depth_jacobian, .aerosol_optical_depth),
            1.0e-14,
        );
        try expectClose(
            expected.scattering_optical_depth_derivative,
            jacobian.get(layer.scattering_optical_depth_jacobian, .aerosol_optical_depth),
            1.0e-14,
        );
        try expectClose(
            expected.single_scatter_albedo_derivative,
            jacobian.get(layer.single_scatter_albedo_jacobian, .aerosol_optical_depth),
            1.0e-14,
        );
        try expectClose(0.0, jacobian.get(layer.optical_depth_jacobian, .surface_albedo), 0.0);
        try expectClose(0.0, jacobian.get(layer.aerosol_phase_weight_jacobian, .aerosol_optical_depth), 0.0);
    }
}

fn expectClose(expected: f64, actual: f64, tolerance: f64) !void {
    // expectClose --------------------------------------------------------------------------------------------|
    // Compare evidence decimals after JSON parsing and Zig floating-point recomputation.                      |
    // --------------------------------------------------------------------------------------------------------|
    try std.testing.expectApproxEqAbs(expected, actual, tolerance);
}
