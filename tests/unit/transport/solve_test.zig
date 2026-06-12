const std = @import("std");

const internal = @import("internal");

const controls = internal.transport.controls;
const jacobian_states = internal.transport.jacobian_states;
const layer_depths = internal.optics.layer_depths;
const phase_basis = internal.transport.phase_basis;
const phase_table = internal.setup.phase_table;
const rows = internal.transport.rows;
const solve = internal.transport.solve;

const tangent_step: f64 = 1.0e-5;

test "direct surface solve ports old scalar formula and surface Jacobian" {
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
        .derivative_state_mask = jacobian_states.stateMask(.surface_albedo),
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
    try std.testing.expectApproxEqAbs(
        direct,
        jacobian_states.get(result.jacobian, .surface_albedo),
        1.0e-15,
    );
    try std.testing.expectEqual(@as(f64, 0.0), jacobian_states.get(result.jacobian, .aerosol_optical_depth));
}

test "direct surface solve respects active Jacobian mask and public clamp" {
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
        jacobian_states.stateMask(.surface_albedo),
    );

    try std.testing.expectEqual(@as(f64, 0.3), masked.reflectance);
    try std.testing.expectEqual(@as(f64, 0.0), jacobian_states.get(masked.jacobian, .surface_albedo));
    try std.testing.expectEqual(@as(f64, 2.0), clamped.reflectance);
    try std.testing.expectEqual(@as(f64, 0.0), jacobian_states.get(clamped.jacobian, .surface_albedo));
}

test "solveReflectance rejects unported integrated and spherical LABOS controls" {
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
            .derivative_mode = .semi_analytical,
            .derivative_state_mask = jacobian_states.stateMask(.surface_albedo),
            .controls = .{
                .scattering = .single,
                .n_streams = 8,
                .integrate_source_function = false,
            },
        },
        &work,
    );

    try std.testing.expectApproxEqAbs(0.3, result.reflectance, 1.0e-14);
    try std.testing.expect(result.jacobian[jacobian_states.stateIndex(.surface_albedo)] > 0.0);
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
    const expected_work_size: usize =
        if (@sizeOf(internal.transport.scattering_orders.OrdersWorkArrays) == 120) 272 else 264;

    try std.testing.expectEqual(@as(usize, 24), @sizeOf(solve.ViewAngles));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(solve.ReflectanceResult));
    try std.testing.expectEqual(expected_work_size, @sizeOf(solve.TransportWorkArrays));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(solve.ViewAngles, "solar_mu"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(solve.ViewAngles, "view_mu"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(solve.ViewAngles, "relative_azimuth_rad"));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(solve.TransportWorkArrays, "geometry"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(solve.TransportWorkArrays, "dynamic_attenuation_data"));
    try std.testing.expectEqual(
        @as(usize, 24),
        @offsetOf(solve.TransportWorkArrays, "dynamic_attenuation_tangent_data"),
    );
    try std.testing.expectEqual(@as(usize, 120), @offsetOf(solve.TransportWorkArrays, "orders"));
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
    geometry: internal.transport.gauss_angles.GaussGeometry = undefined,
    dynamic_attenuation_data: [72]f64 = undefined,
    dynamic_attenuation_tangent_data: [72]f64 = undefined,
    layer_transmittance: [12]f64 = undefined,
    rt_layers: [3]rows.LayerRT = undefined,
    rt_layers_tangent: [3]rows.LayerRT = undefined,
    layer_phase_max_indices: [2]usize = undefined,
    effective_scattering_suffixes: [phase_table.coefficient_count * 2]f64 = undefined,
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
            .rt_layers = self.rt_layers[0..],
            .rt_layers_tangent = self.rt_layers_tangent[0..],
            .layer_phase_max_indices = self.layer_phase_max_indices[0..],
            .effective_scattering_suffixes = self.effective_scattering_suffixes[0..],
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

fn perturbAodLayer(layer: *layer_depths.LayerOptics, signed_step: f64) void {
    // perturbAodLayer --------------------------------------------------------------------------------------- |
    // Apply the old non-integrated AOD finite-difference variables to one layer row.                          |
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
