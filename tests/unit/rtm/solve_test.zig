const std = @import("std");

const internal = @import("internal");

const controls = internal.rtm.controls;
const jacobian_states = internal.rtm.jacobian_states;
const layer_depths = internal.optics.layer_depths;
const phase_basis = internal.rtm.phase_basis;
const phase_table = internal.setup.phase_table;
const rows = internal.rtm.rows;
const solve = internal.rtm.solve;
const source_levels = internal.optics.source_levels;

const tangent_step: f64 = 1.0e-5;

test "direct surface solve applies scalar formula without retrieval Jacobian lanes" {
    var storage = TestSolveWorkStorage{};
    var work = storage.work();
    const layers = [_]layer_depths.LayerOptics{
        .{ .total_optical_depth = 0.12 },
        .{ .total_optical_depth = 0.08 },
    };
    const angles = solve.ViewAngles{
        .solar_mu = 0.5,
        .view_mu = 0.25,
    };
    const config = controls.SolveConfig{
        .derivative_mode = .semi_analytical,
        .derivative_state_mask = jacobian_states.all_states_mask,
        .controls = .{ .scattering = .none },
    };
    const result = try solve.solveReflectance(
        angles,
        0.3,
        &layers,
        &.{},
        &.{},
        testPhase(),
        0.5,
        config,
        &work,
    );
    const direct = std.math.exp(-0.2 / 0.5) * std.math.exp(-0.2 / 0.25);

    try std.testing.expectApproxEqAbs(0.3 * direct, result.reflectance, 1.0e-15);
    try std.testing.expectEqual(jacobian_states.zero(), result.jacobian);
}

test "direct surface solve keeps retrieval Jacobian zero and respects public clamp" {
    const masked = solve.directSurfaceOnly(
        .{ .solar_mu = 1.0, .view_mu = 1.0 },
        0.3,
        0.0,
        .semi_analytical,
        jacobian_states.stateMask(.aerosol_optical_depth),
    );
    const clamped = solve.directSurfaceOnly(
        .{ .solar_mu = 1.0, .view_mu = 1.0 },
        3.0,
        0.0,
        .semi_analytical,
        jacobian_states.all_states_mask,
    );

    try std.testing.expectEqual(@as(f64, 0.3), masked.reflectance);
    try std.testing.expectEqual(jacobian_states.zero(), masked.jacobian);
    try std.testing.expectEqual(@as(f64, 2.0), clamped.reflectance);
    try std.testing.expectEqual(jacobian_states.zero(), clamped.jacobian);
}

test "solveReflectance rejects malformed integrated and spherical direct controls" {
    var storage = TestSolveWorkStorage{};
    var work = storage.work();

    try std.testing.expectError(
        error.UnsupportedRadiativeTransferControls,
        solve.solveReflectance(
            .{ .solar_mu = 0.5, .view_mu = 0.25 },
            0.3,
            &.{},
            &.{},
            &.{},
            testPhase(),
            0.5,
            .{ .controls = .{ .scattering = .multiple, .integrate_source_function = true } },
            &work,
        ),
    );
    try std.testing.expectError(
        error.UnsupportedRadiativeTransferControls,
        solve.solveReflectance(
            .{ .solar_mu = 0.5, .view_mu = 0.25 },
            0.3,
            &.{},
            &.{},
            &.{},
            testPhase(),
            0.5,
            .{ .controls = .{ .scattering = .none, .use_spherical_correction = true } },
            &work,
        ),
    );
}

test "non-integrated scattering route runs Fourier surface term without allocation" {
    var storage = TestSolveWorkStorage{};
    var work = storage.work();
    const layers = [_]layer_depths.LayerOptics{
        .{},
    };
    const result = try solve.solveReflectance(
        .{ .solar_mu = 0.58, .view_mu = 0.64 },
        0.3,
        &layers,
        &.{},
        &.{},
        testPhase(),
        0.5,
        .{
            .derivative_mode = .none,
            .controls = .{
                .scattering = .single,
                .n_streams = 8,
                .integrate_source_function = false,
            },
        },
        &work,
    );

    try std.testing.expectApproxEqAbs(0.3, result.reflectance, 1.0e-14);
    try std.testing.expectEqual(jacobian_states.zero(), result.jacobian);
}

test "nadir scattering route keeps scalar Fourier ceiling" {
    var storage = TestSolveWorkStorage{};
    var work = storage.work();
    const layers = [_]layer_depths.LayerOptics{
        .{
            .aerosol_optical_depth = 0.02,
            .aerosol_scattering_optical_depth = 0.01,
            .total_optical_depth = 0.03,
            .total_scattering_optical_depth = 0.01,
            .single_scatter_albedo = 1.0 / 3.0,
        },
    };
    const result = try solve.solveReflectance(
        .{ .solar_mu = 0.58, .view_mu = 1.0 },
        0.3,
        &layers,
        &.{},
        &.{},
        anisotropicPhase(),
        0.5,
        .{
            .derivative_mode = .none,
            .controls = .{
                .scattering = .single,
                .n_streams = 8,
                .integrate_source_function = false,
            },
        },
        &work,
    );
    try std.testing.expectApproxEqAbs(0.28011854766306493, result.reflectance, 1.0e-15);
    try std.testing.expect(storage.plm_basis_cache_valid[0]);
    try std.testing.expect(!storage.plm_basis_cache_valid[1]);
    try std.testing.expect(!storage.plm_basis_cache_valid[2]);
}

test "scattering route reuses geometry and invalidates PLM rows on geometry changes" {
    var storage = TestSolveWorkStorage{};
    var work = storage.work();
    const layers = [_]layer_depths.LayerOptics{
        .{},
    };
    const config = controls.SolveConfig{
        .derivative_mode = .none,
        .controls = .{
            .scattering = .single,
            .n_streams = 8,
            .integrate_source_function = false,
        },
    };

    _ = try solve.solveReflectance(
        .{ .solar_mu = 0.58, .view_mu = 0.64 },
        0.3,
        &layers,
        &.{},
        &.{},
        testPhase(),
        0.5,
        config,
        &work,
    );
    try std.testing.expect(storage.geometry_valid);
    try std.testing.expect(storage.plm_basis_cache_valid[0]);

    const sentinel_index = phase_table.coefficient_count - 1;
    storage.plm_basis_cache_valid[sentinel_index] = true;
    _ = try solve.solveReflectance(
        .{ .solar_mu = 0.58, .view_mu = 0.64 },
        0.3,
        &layers,
        &.{},
        &.{},
        testPhase(),
        0.5,
        config,
        &work,
    );
    try std.testing.expect(storage.plm_basis_cache_valid[sentinel_index]);

    _ = try solve.solveReflectance(
        .{ .solar_mu = 0.58, .view_mu = 0.63 },
        0.3,
        &layers,
        &.{},
        &.{},
        testPhase(),
        0.5,
        config,
        &work,
    );
    try std.testing.expect(!storage.plm_basis_cache_valid[sentinel_index]);
}

test "integrated scattering route accepts source rows and pseudo-spherical metadata" {
    var storage = TestSolveWorkStorage{};
    var work = storage.work();
    const curved_starts = [_]usize{ 0, 0, 0 };
    const curved_altitudes = [_]f64{ 10.0, 5.0, 0.0 };
    work.curved_level_starts = curved_starts[0..];
    work.curved_level_altitudes_km = curved_altitudes[0..];

    const layers = [_]layer_depths.LayerOptics{
        .{},
        .{},
    };
    const levels = [_]internal.optics.source_levels.SourceLevel{
        .{},
        .{},
        .{},
    };
    work.orders.ud_sum_local[0].U.col[0].set(0, 999.0);
    const result = try solve.solveReflectance(
        .{ .solar_mu = 0.58, .view_mu = 0.64 },
        0.3,
        &layers,
        &levels,
        &.{},
        testPhase(),
        0.5,
        .{
            .derivative_mode = .none,
            .controls = .{
                .scattering = .single,
                .n_streams = 8,
                .integrate_source_function = true,
                .use_spherical_correction = true,
            },
        },
        &work,
    );

    try std.testing.expectApproxEqAbs(0.3, result.reflectance, 1.0e-14);
    try std.testing.expect(work.orders.ud_sum_local.len >= layers.len + 1);
}

test "integrated scattering route propagates aerosol AOD and pressure tangents" {
    var storage = TestSolveWorkStorage{};
    var work = storage.work();
    const layers = integratedAerosolLayers();
    const levels = integratedAerosolSourceLevels();
    const mask =
        jacobian_states.stateMask(.aerosol_optical_depth) |
        jacobian_states.stateMask(.aerosol_layer_mid_pressure_hpa);

    const result = try solve.solveReflectance(
        .{ .solar_mu = 0.58, .view_mu = 0.64 },
        0.3,
        &layers,
        &levels,
        &.{},
        testPhase(),
        0.5,
        .{
            .derivative_mode = .semi_analytical,
            .derivative_state_mask = mask,
            .controls = .{
                .scattering = .single,
                .n_streams = 8,
                .integrate_source_function = true,
            },
        },
        &work,
    );
    const aod = jacobian_states.get(result.jacobian, .aerosol_optical_depth);
    const pressure = jacobian_states.get(result.jacobian, .aerosol_layer_mid_pressure_hpa);

    try std.testing.expectApproxEqAbs(0.1977623662914089, result.reflectance, 1.0e-15);
    try std.testing.expectApproxEqAbs(-0.15212842251966158, aod, 1.0e-14);
    try std.testing.expectApproxEqAbs(0.00926416296449234, pressure, 1.0e-15);
}

test "scattering route propagates AOD tangent and rejects pressure lane" {
    var storage = TestSolveWorkStorage{};
    var work = storage.work();
    var layers = [_]layer_depths.LayerOptics{
        .{
            .gas_absorption_optical_depth = 0.08,
            .aerosol_optical_depth = 0.02,
            .aerosol_scattering_optical_depth = 0.01,
            .total_optical_depth = 0.10,
            .total_scattering_optical_depth = 0.01,
            .single_scatter_albedo = 0.10,
        },
    };
    jacobian_states.set(&layers[0].optical_depth_jacobian, .aerosol_optical_depth, 1.0);
    jacobian_states.set(&layers[0].scattering_optical_depth_jacobian, .aerosol_optical_depth, 0.5);
    jacobian_states.set(&layers[0].single_scatter_albedo_jacobian, .aerosol_optical_depth, 4.0);

    const aod = try solve.solveReflectance(
        .{ .solar_mu = 0.58, .view_mu = 0.64 },
        0.3,
        &layers,
        &.{},
        &.{},
        testPhase(),
        0.5,
        .{
            .derivative_mode = .semi_analytical,
            .derivative_state_mask = jacobian_states.stateMask(.aerosol_optical_depth),
            .controls = .{
                .scattering = .single,
                .n_streams = 8,
                .integrate_source_function = false,
            },
        },
        &work,
    );
    var plus_layers = layers;
    var minus_layers = layers;
    perturbAodLayer(&plus_layers[0], tangent_step);
    perturbAodLayer(&minus_layers[0], -tangent_step);
    const plus = try solve.solveReflectance(
        .{ .solar_mu = 0.58, .view_mu = 0.64 },
        0.3,
        &plus_layers,
        &.{},
        &.{},
        testPhase(),
        0.5,
        .{ .controls = .{ .scattering = .single, .n_streams = 8, .integrate_source_function = false } },
        &work,
    );
    const minus = try solve.solveReflectance(
        .{ .solar_mu = 0.58, .view_mu = 0.64 },
        0.3,
        &minus_layers,
        &.{},
        &.{},
        testPhase(),
        0.5,
        .{ .controls = .{ .scattering = .single, .n_streams = 8, .integrate_source_function = false } },
        &work,
    );
    const expected_aod_tangent = (plus.reflectance - minus.reflectance) / (2.0 * tangent_step);
    try std.testing.expectApproxEqAbs(
        expected_aod_tangent,
        aod.jacobian[jacobian_states.stateIndex(.aerosol_optical_depth)],
        1.0e-8,
    );

    try std.testing.expectError(
        error.UnsupportedDerivativeMode,
        solve.solveReflectance(
            .{ .solar_mu = 0.58, .view_mu = 0.64 },
            0.3,
            &layers,
            &.{},
            &.{},
            testPhase(),
            0.5,
            .{
                .derivative_mode = .semi_analytical,
                .derivative_state_mask = jacobian_states.stateMask(.aerosol_layer_mid_pressure_hpa),
                .controls = .{
                    .scattering = .single,
                    .n_streams = 8,
                    .integrate_source_function = false,
                },
            },
            &work,
        ),
    );
}

test "solve route rows keep explicit layout" {
    const expected_layout = if (internal.instrumentation.cost_timing.enabled)
        .{ .work_size = 384, .orders_offset = 224 }
    else
        .{ .work_size = 368, .orders_offset = 216 };

    try std.testing.expectEqual(@as(usize, 24), @sizeOf(solve.ViewAngles));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(solve.ReflectanceResult));
    try std.testing.expectEqual(@as(usize, expected_layout.work_size), @sizeOf(solve.TransportWorkArrays));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(solve.ViewAngles, "solar_mu"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(solve.ViewAngles, "view_mu"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(solve.ViewAngles, "relative_azimuth_rad"));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(solve.TransportWorkArrays, "geometry"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(solve.TransportWorkArrays, "dynamic_attenuation_data"));
    try std.testing.expectEqual(
        @as(usize, 24),
        @offsetOf(solve.TransportWorkArrays, "dynamic_attenuation_tangent_data"),
    );
    try std.testing.expectEqual(
        @as(usize, expected_layout.orders_offset),
        @offsetOf(solve.TransportWorkArrays, "orders"),
    );
    try std.testing.expectEqual(
        @as(usize, expected_layout.work_size - 8),
        @offsetOf(solve.TransportWorkArrays, "geometry_valid"),
    );
}

// TestSolveWorkStorage -------------------------------------------------------------------------------------  |
// Stack backing for solve.TransportWorkArrays.                                                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: compiler-owned test fixture, align: 8                                                                 |
//                                                                                                             |
// memory                                                                                                      |
//   geometry, attenuation, RT, phase, PLM, and order rows for tiny solve tests                                |
const TestSolveWorkStorage = struct {
    geometry: internal.rtm.gauss_angles.GaussGeometry = undefined,
    geometry_valid: bool = false,
    dynamic_attenuation_data: [72]f64 = undefined,
    dynamic_attenuation_tangent_data: [72]f64 = undefined,
    layer_transmittance: [12]f64 = undefined,
    top_to_level_attenuation: [24]f64 = undefined,
    rt_layers: [3]rows.LayerRT = undefined,
    rt_layers_tangent: [3]rows.LayerRT = undefined,
    layer_phase_max_indices: [2]usize = undefined,
    effective_scattering_suffixes: [phase_table.coefficient_count * 2]f64 = undefined,
    source_phase_max_indices: [3]usize = undefined,
    phase_row_cache: [3]phase_basis.PhaseKernelRow = undefined,
    phase_row_valid: [3]bool = .{ false, false, false },
    cost_timing_state: internal.instrumentation.cost_timing.WorkspaceState = .{},
    order_ud: [3]rows.UDField = undefined,
    order_ud_sum_local: [3]rows.UDLocal = undefined,
    order_ud_orde: [3]rows.UDLocal = undefined,
    order_ud_local: [3]rows.UDLocal = undefined,
    order_ud_tangent_orde: [3]rows.UDLocal = undefined,
    order_ud_tangent_local: [3]rows.UDLocal = undefined,
    rt_active: [3]bool = .{ false, false, false },
    plm_basis_cache: [phase_table.coefficient_count]phase_basis.FourierPlmBasis = undefined,
    plm_basis_cache_valid: [phase_table.coefficient_count]bool = [_]bool{false} ** phase_table.coefficient_count,

    fn work(self: *TestSolveWorkStorage) solve.TransportWorkArrays {
        // TestSolveWorkStorage.work ------------------------------------------------------------------------  |
        // Borrow all stack rows in the shape expected by solveReflectance.                                    |
        // ----------------------------------------------------------------------------------------------------|
        return .{
            .geometry = &self.geometry,
            .dynamic_attenuation_data = self.dynamic_attenuation_data[0..],
            .dynamic_attenuation_tangent_data = self.dynamic_attenuation_tangent_data[0..],
            .layer_transmittance = self.layer_transmittance[0..],
            .top_to_level_attenuation = self.top_to_level_attenuation[0..],
            .rt_layers = self.rt_layers[0..],
            .rt_layers_tangent = self.rt_layers_tangent[0..],
            .layer_phase_max_indices = self.layer_phase_max_indices[0..],
            .effective_scattering_suffixes = self.effective_scattering_suffixes[0..],
            .source_phase_max_indices = self.source_phase_max_indices[0..],
            .phase_row_cache = self.phase_row_cache[0..],
            .phase_row_valid = self.phase_row_valid[0..],
            .cost_timing_state = self.cost_timing_state,
            .curved_level_starts = &.{},
            .curved_level_altitudes_km = &.{},
            .orders = .{
                .ud = self.order_ud[0..],
                .ud_sum_local = self.order_ud_sum_local[0..],
                .ud_orde = self.order_ud_orde[0..],
                .ud_local = self.order_ud_local[0..],
                .ud_tangent_orde = self.order_ud_tangent_orde[0..],
                .ud_tangent_local = self.order_ud_tangent_local[0..],
                .rt_active = self.rt_active[0..],
            },
            .plm_basis_cache = self.plm_basis_cache[0..],
            .plm_basis_cache_valid = self.plm_basis_cache_valid[0..],
            .geometry_valid = &self.geometry_valid,
        };
    }
};
// ------------------------------------------------------------------------------------------------------------|

fn testPhase() phase_table.PhaseTable {
    // testPhase --------------------------------------------------------------------------------------------- |
    // Return isotropic aerosol phase coefficients for tiny transport tests.                                   |
    // --------------------------------------------------------------------------------------------------------|
    const coefficients = phase_table.zeroPhaseCoefficients();
    return .{
        .aerosol_phase_coefficients = coefficients,
        .aerosol_phase_max_index = 0,
        .aerosol_asymmetry_factor = 0.0,
    };
}

fn anisotropicPhase() phase_table.PhaseTable {
    // anisotropicPhase -------------------------------------------------------------------------------------- |
    // Return a tiny aerosol phase row with active m=1 and m=2 terms for Fourier-ceiling tests.                |
    // --------------------------------------------------------------------------------------------------------|
    var coefficients = phase_table.zeroPhaseCoefficients();
    coefficients[1] = 0.2;
    coefficients[2] = 0.1;
    return .{
        .aerosol_phase_coefficients = coefficients,
        .aerosol_phase_max_index = 2,
        .aerosol_asymmetry_factor = 0.0,
    };
}

fn perturbAodLayer(layer: *layer_depths.LayerOptics, signed_step: f64) void {
    // perturbAodLayer --------------------------------------------------------------------------------------- |
    // Apply the non-integrated AOD finite-difference variables to one layer row.                              |
    // --------------------------------------------------------------------------------------------------------|
    layer.total_optical_depth = @max(
        layer.total_optical_depth +
            signed_step * jacobian_states.get(layer.optical_depth_jacobian, .aerosol_optical_depth),
        0.0,
    );
    layer.total_scattering_optical_depth = @max(
        layer.total_scattering_optical_depth +
            signed_step * jacobian_states.get(layer.scattering_optical_depth_jacobian, .aerosol_optical_depth),
        0.0,
    );
    layer.single_scatter_albedo = std.math.clamp(
        layer.single_scatter_albedo +
            signed_step * jacobian_states.get(layer.single_scatter_albedo_jacobian, .aerosol_optical_depth),
        0.0,
        1.0,
    );
}

fn integratedAerosolLayers() [2]layer_depths.LayerOptics {
    // integratedAerosolLayers ------------------------------------------------------------------------------  |
    // Synthetic positive-scattering layers for solve-level integrated aerosol derivative tests.               |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .{
            .gas_absorption_optical_depth = 0.04,
            .gas_scattering_optical_depth = 0.01,
            .aerosol_optical_depth = 0.08,
            .aerosol_scattering_optical_depth = 0.04,
            .total_optical_depth = 0.13,
            .total_scattering_optical_depth = 0.05,
            .single_scatter_albedo = 0.38,
        },
        .{
            .gas_absorption_optical_depth = 0.03,
            .gas_scattering_optical_depth = 0.01,
            .aerosol_optical_depth = 0.06,
            .aerosol_scattering_optical_depth = 0.03,
            .total_optical_depth = 0.10,
            .total_scattering_optical_depth = 0.04,
            .single_scatter_albedo = 0.40,
        },
    };
}

fn integratedAerosolSourceLevels() [3]source_levels.SourceLevel {
    // integratedAerosolSourceLevels ------------------------------------------------------------------------  |
    // Three RTM source levels with one active aerosol derivative node bounded by bottom/top interfaces.       |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .{
            .altitude_km = 0.0,
            .aerosol_ksca_above_per_km = 0.07,
        },
        .{
            .altitude_km = 1.0,
            .weight_km = 1.0,
            .scattering_per_km = 0.09,
            .aerosol_ksca_above_per_km = 0.07,
            .aerosol_ksca_below_per_km = 0.07,
            .aerosol_ksca_jacobian = 0.18,
            .phase_aerosol_weight = 1.0,
        },
        .{
            .altitude_km = 2.0,
            .aerosol_ksca_below_per_km = 0.07,
        },
    };
}
