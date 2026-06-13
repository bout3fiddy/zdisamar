const std = @import("std");

const internal = @import("internal");

const controls = internal.rtm.controls;
const gauss_angles = internal.rtm.gauss_angles;
const layer_depths = internal.optics.layer_depths;
const phase_basis = internal.rtm.phase_basis;
const phase_table = internal.setup.phase_table;
const reflectance = internal.rtm.reflectance;
const rows = internal.rtm.rows;
const source_levels = internal.optics.source_levels;
const sensitivity = internal.instrumentation.sensitivity;

test "top reflectance coefficient reads solar column at viewing stream" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    var fields = zeroFields(3, geometry.stream_count);
    const top_level: usize = 2;
    const expected = 0.0375;
    fields[top_level].U.col[1].set(geometry.viewIndex(), expected);
    fields[top_level].U.col[0].set(geometry.viewIndex(), -9.0);
    fields[top_level].U.col[1].set(geometry.solarIndex(), 12.0);

    try std.testing.expectEqual(
        expected,
        reflectance.topReflectanceCoefficient(&fields, top_level, &geometry),
    );
}

test "Fourier contribution applies old azimuthal weight and tail floor" {
    const thresholds = controls.PerformanceThresholds{
        .fourier_tail_reflectance_epsilon = 1.0e-6,
        .fourier_floor_scalar = 2,
    };
    const contribution = reflectance.weightedFourierContribution(
        3,
        0.25,
        0.125,
        thresholds,
    );
    const expected_weight = 2.0 * std.math.cos(3.0 * 0.25);

    try std.testing.expectApproxEqAbs(expected_weight, contribution.weight, 1.0e-15);
    try std.testing.expectApproxEqAbs(0.125, contribution.rho_m, 0.0);
    try std.testing.expectApproxEqAbs(expected_weight * 0.125, contribution.weighted, 1.0e-15);
    try std.testing.expectEqual(false, contribution.tail_break);

    const tail = reflectance.weightedFourierContribution(2, 0.25, -5.0e-7, thresholds);
    try std.testing.expectEqual(true, tail.tail_break);
    try std.testing.expectApproxEqAbs(2.0 * std.math.cos(0.5), tail.weight, 1.0e-15);
}

test "Fourier zero weight and floor prevent early tail stop" {
    const thresholds = controls.PerformanceThresholds{
        .fourier_tail_reflectance_epsilon = 1.0e-6,
        .fourier_floor_scalar = 2,
    };
    const coord = sensitivity.Coord{ .fourier_index = 1 };

    try std.testing.expectEqual(@as(f64, 1.0), reflectance.fourierWeight(0, 1.25));
    try std.testing.expectEqual(
        false,
        reflectance.fourierTailBreak(1, 1.0e-12, thresholds, coord),
    );
}

test "integrated aerosol paired weighting matches separate helper routes" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    const plm_basis = phase_basis.FourierPlmBasis.init(0, 0, &geometry);
    const layers = aerosolLayers();
    const levels = aerosolSourceLevels();
    var fields = zeroFields(3, geometry.stream_count);
    var local = zeroLocal(3, geometry.stream_count);
    fillAerosolWeightingFields(&fields, &local, &geometry);

    const paired = reflectance.integratedAerosolDerivativeWeighting(
        &layers,
        &levels,
        &fields,
        &local,
        2,
        0,
        false,
        &geometry,
        &plm_basis,
        testPhase(),
    );
    const aod = reflectance.integratedAerosolOpticalDepthWeighting(
        &layers,
        &levels,
        &fields,
        &local,
        2,
        0,
        false,
        &geometry,
        &plm_basis,
        testPhase(),
    );
    const pressure = reflectance.integratedAerosolLayerPressureShiftWeighting(
        &layers,
        &levels,
        &fields,
        &local,
        2,
        0,
        false,
        &geometry,
        &plm_basis,
        testPhase(),
    );

    try std.testing.expectApproxEqAbs(aod, paired.aerosol_optical_depth, 1.0e-15);
    try std.testing.expect(std.math.isFinite(paired.aerosol_optical_depth));
    try std.testing.expect(std.math.isFinite(paired.aerosol_layer_mid_pressure_hpa));
    try std.testing.expect(std.math.isFinite(pressure));
    try std.testing.expect(@abs(paired.aerosol_optical_depth) > 1.0e-12);
    try std.testing.expect(@abs(paired.aerosol_layer_mid_pressure_hpa) > 1.0e-12);
    try std.testing.expect(@abs(pressure) > 1.0e-12);
}

test "public reflectance clamp keeps old output range" {
    try std.testing.expectEqual(@as(f64, 0.0), reflectance.clampPublicReflectance(-0.25));
    try std.testing.expectEqual(@as(f64, 0.5), reflectance.clampPublicReflectance(0.5));
    try std.testing.expectEqual(@as(f64, 2.0), reflectance.clampPublicReflectance(2.5));
}

fn zeroFields(level_count: usize, stream_count: usize) [3]rows.UDField {
    // zeroFields -------------------------------------------------------------------------------------------- |
    // Build zeroed U/D/E rows for reflectance helper tests.                                                   |
    // --------------------------------------------------------------------------------------------------------|
    var fields: [3]rows.UDField = undefined;
    for (0..level_count) |level| {
        fields[level] = .{
            .E = rows.Vec.zero(stream_count),
            .U = rows.Vec2.zero(stream_count),
            .D = rows.Vec2.zero(stream_count),
        };
    }
    return fields;
}

fn zeroLocal(level_count: usize, stream_count: usize) [3]rows.UDLocal {
    // zeroLocal --------------------------------------------------------------------------------------------- |
    // Build zeroed local U/D rows for integrated-source weighting tests.                                      |
    // --------------------------------------------------------------------------------------------------------|
    var local: [3]rows.UDLocal = undefined;
    for (0..level_count) |level| {
        local[level] = .{
            .U = rows.Vec2.zero(stream_count),
            .D = rows.Vec2.zero(stream_count),
        };
    }
    return local;
}

fn fillAerosolWeightingFields(
    fields: *[3]rows.UDField,
    local: *[3]rows.UDLocal,
    geometry: *const gauss_angles.GaussGeometry,
) void {
    // fillAerosolWeightingFields ---------------------------------------------------------------------------- |
    // Seed deterministic nonzero fields for source, absorption, and pressure weighting checks.                |
    // --------------------------------------------------------------------------------------------------------|
    for (0..3) |level| {
        const level_scale = @as(f64, @floatFromInt(level + 1));
        for (0..geometry.stream_count) |stream_index| {
            const stream_scale = @as(f64, @floatFromInt(stream_index + 1));
            fields[level].E.set(stream_index, 0.10 * level_scale + 0.01 * stream_scale);
            fields[level].U.col[0].set(stream_index, 0.02 * level_scale + 0.003 * stream_scale);
            fields[level].U.col[1].set(stream_index, 0.03 * level_scale + 0.004 * stream_scale);
            fields[level].D.col[0].set(stream_index, 0.04 * level_scale + 0.002 * stream_scale);
            fields[level].D.col[1].set(stream_index, 0.05 * level_scale + 0.001 * stream_scale);
            local[level].U.col[0].set(stream_index, 0.015 * level_scale + 0.002 * stream_scale);
            local[level].U.col[1].set(stream_index, 0.016 * level_scale + 0.002 * stream_scale);
            local[level].D.col[0].set(stream_index, 0.017 * level_scale + 0.002 * stream_scale);
            local[level].D.col[1].set(stream_index, 0.018 * level_scale + 0.002 * stream_scale);
        }
    }
}

fn aerosolLayers() [2]layer_depths.LayerOptics {
    // aerosolLayers ----------------------------------------------------------------------------------------- |
    // Tiny aerosol-bearing layer rows for integrated-source weighting tests.                                  |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .{
            .aerosol_optical_depth = 0.40,
            .aerosol_scattering_optical_depth = 0.20,
            .total_optical_depth = 0.50,
            .total_scattering_optical_depth = 0.20,
            .single_scatter_albedo = 0.40,
        },
        .{
            .aerosol_optical_depth = 0.20,
            .aerosol_scattering_optical_depth = 0.10,
            .total_optical_depth = 0.30,
            .total_scattering_optical_depth = 0.10,
            .single_scatter_albedo = 0.33,
        },
    };
}

fn aerosolSourceLevels() [3]source_levels.SourceLevel {
    // aerosolSourceLevels ----------------------------------------------------------------------------------- |
    // Three source interfaces with one active aerosol derivative level bounded by bottom/top interfaces.      |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .{
            .altitude_km = 0.0,
            .aerosol_ksca_above_per_km = 0.08,
        },
        .{
            .altitude_km = 1.0,
            .weight_km = 1.0,
            .scattering_per_km = 0.10,
            .aerosol_ksca_above_per_km = 0.08,
            .aerosol_ksca_below_per_km = 0.08,
            .aerosol_ksca_jacobian = 0.20,
            .phase_aerosol_weight = 1.0,
        },
        .{
            .altitude_km = 2.0,
            .aerosol_ksca_below_per_km = 0.08,
        },
    };
}

fn testPhase() phase_table.PhaseTable {
    // testPhase --------------------------------------------------------------------------------------------- |
    // Isotropic phase row used by the scalar integrated-source helper tests.                                  |
    // --------------------------------------------------------------------------------------------------------|
    const coefficients = phase_table.zeroPhaseCoefficients();
    return .{
        .aerosol_phase_coefficients = coefficients,
        .aerosol_phase_max_index = 0,
        .aerosol_asymmetry_factor = 0.0,
    };
}
