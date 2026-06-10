const std = @import("std");
const internal = @import("internal");

const labos = internal.forward_model.radiative_transfer.labos;
const Geometry = labos.Geometry;
const LayerRT = labos.LayerRT;
const Mat = labos.Mat;
const OrdersWorkspace = labos.OrdersWorkspace;
const ordersScatInto = labos.ordersScatInto;
const ordersScatIntoWithLocalSum = labos.ordersScatIntoWithLocalSum;

const default_layer_phase: [labos.max_phase_coef]f64 = .{ 1.0, 0.22, 0.05 } ++ .{0.0} ** (labos.max_phase_coef - 3);
const pressure_layer_phase: [labos.max_phase_coef]f64 = .{ 1.0, 0.18, 0.04 } ++ .{0.0} ** (labos.max_phase_coef - 3);

test "labos semi-analytical surface albedo tangent matches local finite difference" {
    const allocator = std.testing.allocator;
    const common = internal.forward_model.radiative_transfer;
    const jacobian = common.Jacobian;
    const controls: common.RadiativeTransferControls = .{
        .scattering = .multiple,
        .n_streams = 4,
        .integrate_source_function = false,
        .performance_thresholds = .{
            .threshold_conv_first = 1.0e-12,
            .threshold_conv_mult = 1.0e-12,
            .num_orders_max = 8,
        },
    };
    const rtm_config: common.SolveConfig = .{
        .derivative_mode = .semi_analytical,
        .rtm_controls = controls,
    };
    var layer = common.LayerInput{
        .optical_depth = 0.18,
        .scattering_optical_depth = 0.12,
        .single_scatter_albedo = 0.7,
        .solar_mu = 0.61,
        .view_mu = 0.72,
        .phase = common.LayerPhase.fromUnitPhase(&default_layer_phase),
    };
    jacobian.set(&layer.optical_depth_jacobian, .aerosol_layer_mid_pressure_hpa, 0.002);
    jacobian.set(&layer.scattering_optical_depth_jacobian, .aerosol_layer_mid_pressure_hpa, 0.001);
    jacobian.set(&layer.single_scatter_albedo_jacobian, .aerosol_layer_mid_pressure_hpa, -0.0005);
    const layers = [_]common.LayerInput{layer};
    const base_input: common.ForwardInput = .{
        .mu0 = 0.61,
        .muv = 0.72,
        .surface_albedo = 0.21,
        .relative_azimuth_rad = 0.0,
        .layers = &layers,
        .optical_depth = 0.18,
        .rtm_controls = controls,
    };

    const tangent_result = try labos.execute(allocator, rtm_config, base_input);
    const tangent = jacobian.get(tangent_result.jacobian.?, .surface_albedo);

    var plus_input = base_input;
    plus_input.surface_albedo += 1.0e-6;
    var minus_input = base_input;
    minus_input.surface_albedo -= 1.0e-6;
    var value_route = rtm_config;
    value_route.derivative_mode = .none;
    const plus = try labos.execute(allocator, value_route, plus_input);
    const minus = try labos.execute(allocator, value_route, minus_input);
    const finite_difference = (plus.toa_reflectance_factor - minus.toa_reflectance_factor) / 2.0e-6;

    try std.testing.expectApproxEqAbs(finite_difference, tangent, 3.0e-6);
}

test "labos no-scattering rtm_config returns surface albedo tangent" {
    const allocator = std.testing.allocator;
    const common = internal.forward_model.radiative_transfer;
    const jacobian = common.Jacobian;
    const controls: common.RadiativeTransferControls = .{
        .scattering = .none,
        .n_streams = 4,
    };
    const rtm_config: common.SolveConfig = .{
        .derivative_mode = .semi_analytical,
        .rtm_controls = controls,
    };
    const input: common.ForwardInput = .{
        .mu0 = 0.62,
        .muv = 0.74,
        .surface_albedo = 0.23,
        .optical_depth = 0.31,
        .rtm_controls = controls,
    };

    const tangent_result = try labos.execute(allocator, rtm_config, input);
    const tangent = jacobian.get(tangent_result.jacobian.?, .surface_albedo);

    var plus_input = input;
    plus_input.surface_albedo += 1.0e-6;
    var minus_input = input;
    minus_input.surface_albedo -= 1.0e-6;
    var value_route = rtm_config;
    value_route.derivative_mode = .none;
    const plus = try labos.execute(allocator, value_route, plus_input);
    const minus = try labos.execute(allocator, value_route, minus_input);
    const finite_difference = (plus.toa_reflectance_factor - minus.toa_reflectance_factor) / 2.0e-6;

    try std.testing.expect(tangent > 0.0);
    try std.testing.expectApproxEqAbs(finite_difference, tangent, 1.0e-10);
}

test "labos no-scattering surface albedo tangent is active at zero albedo" {
    const allocator = std.testing.allocator;
    const common = internal.forward_model.radiative_transfer;
    const jacobian = common.Jacobian;
    const controls: common.RadiativeTransferControls = .{
        .scattering = .none,
        .n_streams = 4,
    };
    const rtm_config: common.SolveConfig = .{
        .derivative_mode = .semi_analytical,
        .rtm_controls = controls,
    };
    const input: common.ForwardInput = .{
        .mu0 = 0.62,
        .muv = 0.74,
        .surface_albedo = 0.0,
        .optical_depth = 0.31,
        .rtm_controls = controls,
    };

    const tangent_result = try labos.execute(allocator, rtm_config, input);
    const tangent = jacobian.get(tangent_result.jacobian.?, .surface_albedo);

    var plus_input = input;
    plus_input.surface_albedo += 1.0e-6;
    var value_route = rtm_config;
    value_route.derivative_mode = .none;
    const plus = try labos.execute(allocator, value_route, plus_input);
    const base = try labos.execute(allocator, value_route, input);
    const finite_difference = (plus.toa_reflectance_factor - base.toa_reflectance_factor) / 1.0e-6;

    try std.testing.expect(tangent > 0.0);
    try std.testing.expectApproxEqAbs(finite_difference, tangent, 1.0e-10);
}

test "labos rejects no-scattering with layer-resolved input" {
    const allocator = std.testing.allocator;
    const common = internal.forward_model.radiative_transfer;
    const controls: common.RadiativeTransferControls = .{
        .scattering = .none,
        .n_streams = 4,
    };
    const rtm_config: common.SolveConfig = .{
        .derivative_mode = .none,
        .rtm_controls = controls,
    };
    const layers = [_]common.LayerInput{.{
        .optical_depth = 0.18,
        .scattering_optical_depth = 0.0,
        .single_scatter_albedo = 0.0,
        .solar_mu = 0.61,
        .view_mu = 0.72,
    }};
    const input: common.ForwardInput = .{
        .mu0 = 0.61,
        .muv = 0.72,
        .surface_albedo = 0.21,
        .layers = &layers,
        .optical_depth = 0.18,
        .rtm_controls = controls,
    };

    try std.testing.expectError(
        error.UnsupportedRadiativeTransferControls,
        labos.execute(allocator, rtm_config, input),
    );
}

test "labos rejects spherical correction without pseudo-spherical grid" {
    const allocator = std.testing.allocator;
    const common = internal.forward_model.radiative_transfer;
    const controls: common.RadiativeTransferControls = .{
        .scattering = .multiple,
        .n_streams = 4,
        .use_spherical_correction = true,
        .integrate_source_function = false,
    };
    const rtm_config: common.SolveConfig = .{
        .derivative_mode = .none,
        .rtm_controls = controls,
    };
    const layers = [_]common.LayerInput{.{
        .optical_depth = 0.18,
        .scattering_optical_depth = 0.12,
        .single_scatter_albedo = 0.7,
        .solar_mu = 0.61,
        .view_mu = 0.72,
        .phase = common.LayerPhase.fromUnitPhase(&default_layer_phase),
    }};
    const input: common.ForwardInput = .{
        .mu0 = 0.61,
        .muv = 0.72,
        .surface_albedo = 0.21,
        .relative_azimuth_rad = 0.0,
        .layers = &layers,
        .optical_depth = 0.18,
        .rtm_controls = controls,
    };

    try std.testing.expectError(
        error.UnsupportedRadiativeTransferControls,
        labos.execute(allocator, rtm_config, input),
    );
}

test "labos rejects non-integrated pressure tangent without layer pressure jacobians" {
    const allocator = std.testing.allocator;
    const common = internal.forward_model.radiative_transfer;
    const controls: common.RadiativeTransferControls = .{
        .scattering = .multiple,
        .n_streams = 4,
        .integrate_source_function = false,
        .performance_thresholds = .{
            .threshold_conv_first = 1.0e-12,
            .threshold_conv_mult = 1.0e-12,
            .num_orders_max = 8,
        },
    };
    const rtm_config: common.SolveConfig = .{
        .derivative_mode = .semi_analytical,
        .rtm_controls = controls,
    };
    const layers = [_]common.LayerInput{.{
        .optical_depth = 0.18,
        .scattering_optical_depth = 0.12,
        .single_scatter_albedo = 0.7,
        .solar_mu = 0.61,
        .view_mu = 0.72,
        .phase = common.LayerPhase.fromUnitPhase(&default_layer_phase),
    }};
    const input: common.ForwardInput = .{
        .mu0 = 0.61,
        .muv = 0.72,
        .surface_albedo = 0.21,
        .relative_azimuth_rad = 0.0,
        .layers = &layers,
        .optical_depth = 0.18,
        .rtm_controls = controls,
    };

    try std.testing.expectError(error.UnsupportedDerivativeMode, labos.execute(allocator, rtm_config, input));
}

test "labos synthetic single-layer rtm_config returns surface albedo tangent" {
    const allocator = std.testing.allocator;
    const common = internal.forward_model.radiative_transfer;
    const jacobian = common.Jacobian;
    const controls: common.RadiativeTransferControls = .{
        .scattering = .multiple,
        .n_streams = 4,
        .integrate_source_function = false,
        .performance_thresholds = .{
            .threshold_conv_first = 1.0e-12,
            .threshold_conv_mult = 1.0e-12,
            .num_orders_max = 8,
        },
    };
    const rtm_config: common.SolveConfig = .{
        .derivative_mode = .semi_analytical,
        .rtm_controls = controls,
    };
    const input: common.ForwardInput = .{
        .mu0 = 0.58,
        .muv = 0.69,
        .surface_albedo = 0.18,
        .optical_depth = 0.24,
        .single_scatter_albedo = 0.74,
        .relative_azimuth_rad = 0.0,
        .rtm_controls = controls,
    };

    const tangent_result = try labos.execute(allocator, rtm_config, input);
    const tangent = jacobian.get(tangent_result.jacobian.?, .surface_albedo);

    var plus_input = input;
    plus_input.surface_albedo += 1.0e-6;
    var minus_input = input;
    minus_input.surface_albedo -= 1.0e-6;
    var value_route = rtm_config;
    value_route.derivative_mode = .none;
    const plus = try labos.execute(allocator, value_route, plus_input);
    const minus = try labos.execute(allocator, value_route, minus_input);
    const finite_difference = (plus.toa_reflectance_factor - minus.toa_reflectance_factor) / 2.0e-6;

    try std.testing.expect(tangent > 0.0);
    try std.testing.expectApproxEqAbs(finite_difference, tangent, 3.0e-6);
}

test "labos rejects scalar spherical correction without pseudo-spherical grid" {
    const allocator = std.testing.allocator;
    const common = internal.forward_model.radiative_transfer;
    const controls: common.RadiativeTransferControls = .{
        .scattering = .multiple,
        .n_streams = 4,
        .use_spherical_correction = true,
    };
    const rtm_config: common.SolveConfig = .{
        .derivative_mode = .none,
        .rtm_controls = controls,
    };
    const input: common.ForwardInput = .{
        .mu0 = 0.58,
        .muv = 0.69,
        .surface_albedo = 0.18,
        .optical_depth = 0.24,
        .single_scatter_albedo = 0.74,
        .relative_azimuth_rad = 0.0,
        .rtm_controls = controls,
    };

    try std.testing.expectError(
        error.UnsupportedRadiativeTransferControls,
        labos.execute(allocator, rtm_config, input),
    );
}

test "labos rejects non-integrated pseudo-spherical jacobian tangent" {
    const allocator = std.testing.allocator;
    const common = internal.forward_model.radiative_transfer;
    const controls: common.RadiativeTransferControls = .{
        .scattering = .multiple,
        .n_streams = 4,
        .integrate_source_function = false,
        .use_spherical_correction = true,
        .performance_thresholds = .{
            .threshold_conv_first = 1.0e-12,
            .threshold_conv_mult = 1.0e-12,
            .num_orders_max = 8,
        },
    };
    const rtm_config: common.SolveConfig = .{
        .derivative_mode = .semi_analytical,
        .rtm_controls = controls,
    };
    const layers = [_]common.LayerInput{.{
        .optical_depth = 0.18,
        .scattering_optical_depth = 0.12,
        .single_scatter_albedo = 0.7,
        .solar_mu = 0.61,
        .view_mu = 0.72,
        .phase = common.LayerPhase.fromUnitPhase(&default_layer_phase),
    }};
    const pseudo_samples = [_]common.PseudoSphericalSample{.{
        .altitude_km = 5.0,
        .thickness_km = 5.0,
        .optical_depth = 0.18,
    }};
    const pseudo_starts = [_]usize{ 0, 1 };
    const pseudo_altitudes = [_]f64{ 10.0, 0.0 };
    const input: common.ForwardInput = .{
        .mu0 = 0.61,
        .muv = 0.72,
        .surface_albedo = 0.21,
        .relative_azimuth_rad = 0.0,
        .layers = &layers,
        .optical_depth = 0.18,
        .pseudo_spherical_grid = .{
            .samples = &pseudo_samples,
            .level_sample_starts = &pseudo_starts,
            .level_altitudes_km = &pseudo_altitudes,
        },
        .rtm_controls = controls,
    };

    try std.testing.expectError(error.UnsupportedDerivativeMode, labos.execute(allocator, rtm_config, input));
}

test "labos non-integrated aerosol layer pressure tangent follows layer jacobian" {
    const allocator = std.testing.allocator;
    const common = internal.forward_model.radiative_transfer;
    const jacobian = common.Jacobian;
    const controls: common.RadiativeTransferControls = .{
        .scattering = .multiple,
        .n_streams = 4,
        .integrate_source_function = false,
        .performance_thresholds = .{
            .threshold_conv_first = 1.0e-12,
            .threshold_conv_mult = 1.0e-12,
            .num_orders_max = 8,
        },
    };
    const rtm_config: common.SolveConfig = .{
        .derivative_mode = .semi_analytical,
        .rtm_controls = controls,
    };
    var layer = common.LayerInput{
        .optical_depth = 0.20,
        .scattering_optical_depth = 0.13,
        .single_scatter_albedo = 0.65,
        .solar_mu = 0.63,
        .view_mu = 0.71,
        .phase = common.LayerPhase.fromUnitPhase(&pressure_layer_phase),
    };
    jacobian.set(&layer.optical_depth_jacobian, .aerosol_layer_mid_pressure_hpa, 0.003);
    jacobian.set(&layer.scattering_optical_depth_jacobian, .aerosol_layer_mid_pressure_hpa, 0.002);
    jacobian.set(&layer.single_scatter_albedo_jacobian, .aerosol_layer_mid_pressure_hpa, -0.001);
    const layers = [_]common.LayerInput{layer};
    const base_input: common.ForwardInput = .{
        .mu0 = 0.63,
        .muv = 0.71,
        .surface_albedo = 0.19,
        .relative_azimuth_rad = 0.0,
        .layers = &layers,
        .optical_depth = layer.optical_depth,
        .rtm_controls = controls,
    };

    const tangent_result = try labos.execute(allocator, rtm_config, base_input);
    const tangent = jacobian.get(tangent_result.jacobian.?, .aerosol_layer_mid_pressure_hpa);

    const eps = 1.0e-5;
    var plus_layer = layer;
    plus_layer.optical_depth += eps * jacobian.get(layer.optical_depth_jacobian, .aerosol_layer_mid_pressure_hpa);
    plus_layer.scattering_optical_depth +=
        eps * jacobian.get(layer.scattering_optical_depth_jacobian, .aerosol_layer_mid_pressure_hpa);
    plus_layer.single_scatter_albedo +=
        eps * jacobian.get(layer.single_scatter_albedo_jacobian, .aerosol_layer_mid_pressure_hpa);
    var minus_layer = layer;
    minus_layer.optical_depth -= eps * jacobian.get(layer.optical_depth_jacobian, .aerosol_layer_mid_pressure_hpa);
    minus_layer.scattering_optical_depth -=
        eps * jacobian.get(layer.scattering_optical_depth_jacobian, .aerosol_layer_mid_pressure_hpa);
    minus_layer.single_scatter_albedo -=
        eps * jacobian.get(layer.single_scatter_albedo_jacobian, .aerosol_layer_mid_pressure_hpa);

    const plus_layers = [_]common.LayerInput{plus_layer};
    const minus_layers = [_]common.LayerInput{minus_layer};
    var plus_input = base_input;
    plus_input.layers = &plus_layers;
    var minus_input = base_input;
    minus_input.layers = &minus_layers;
    var value_route = rtm_config;
    value_route.derivative_mode = .none;
    const plus = try labos.execute(allocator, value_route, plus_input);
    const minus = try labos.execute(allocator, value_route, minus_input);
    const finite_difference = (plus.toa_reflectance_factor - minus.toa_reflectance_factor) / (2.0 * eps);

    try std.testing.expect(@abs(tangent) > 1.0e-10);
    try std.testing.expectApproxEqAbs(finite_difference, tangent, 3.0e-6);
}

test "multiple scattering drops the first below-threshold order" {
    const allocator = std.testing.allocator;
    const geo = Geometry.init(2, 0.58, 0.64);
    const nlevel = 2;
    const nmutot = geo.nmutot;
    const UnitAtten = struct {
        pub fn get(_: @This(), _: usize, _: usize, _: usize) f64 {
            return 1.0;
        }
    };

    var rt = [_]LayerRT{
        .{
            .R = Mat.zero(nmutot),
            .T = Mat.zero(nmutot),
        },
        .{
            .R = Mat.zero(nmutot),
            .T = Mat.zero(nmutot),
        },
    };
    for (0..nmutot) |imu| {
        for (0..2) |extra| {
            const source_col = geo.n_gauss + extra;
            rt[0].R.set(imu, source_col, 0.02);
            rt[1].R.set(imu, source_col, 0.01);
            rt[1].T.set(imu, source_col, 0.03);
        }
        for (0..geo.n_gauss) |gauss_col| {
            rt[0].R.set(imu, gauss_col, 0.02);
            rt[1].R.set(imu, gauss_col, 0.01);
            rt[1].T.set(imu, gauss_col, 0.03);
        }
    }

    var single_workspace = try OrdersWorkspace.init(allocator, nlevel);
    defer single_workspace.deinit();
    var multiple_workspace = try OrdersWorkspace.init(allocator, nlevel);
    defer multiple_workspace.deinit();
    var local_sum_workspace = try OrdersWorkspace.init(allocator, nlevel);
    defer local_sum_workspace.deinit();
    var no_local_sum_workspace = try OrdersWorkspace.initWithLocalSumStorage(allocator, nlevel, false);
    defer no_local_sum_workspace.deinit();
    try std.testing.expectEqual(@as(usize, 0), no_local_sum_workspace.ud_sum_local.len);

    const single_result = ordersScatInto(
        &single_workspace,
        0,
        1,
        &geo,
        UnitAtten{},
        &rt,
        .{
            .scattering = .single,
            .performance_thresholds = .{
                .threshold_conv_first = 1.0e-12,
                .threshold_conv_mult = 1.0,
            },
        },
        20,
    );
    const multiple_result = ordersScatInto(
        &multiple_workspace,
        0,
        1,
        &geo,
        UnitAtten{},
        &rt,
        .{
            .scattering = .multiple,
            .performance_thresholds = .{
                .threshold_conv_first = 1.0e-12,
                .threshold_conv_mult = 1.0,
            },
        },
        20,
    );
    const local_sum_result = ordersScatIntoWithLocalSum(
        &local_sum_workspace,
        0,
        1,
        &geo,
        UnitAtten{},
        &rt,
        .{
            .scattering = .multiple,
            .performance_thresholds = .{
                .threshold_conv_first = 1.0e-12,
                .threshold_conv_mult = 1.0,
            },
        },
        20,
    );
    const no_local_sum_result = ordersScatInto(
        &no_local_sum_workspace,
        0,
        1,
        &geo,
        UnitAtten{},
        &rt,
        .{
            .scattering = .multiple,
            .performance_thresholds = .{
                .threshold_conv_first = 1.0e-12,
                .threshold_conv_mult = 1.0,
            },
        },
        20,
    );

    try std.testing.expectEqual(@as(usize, 0), single_result.ud_sum_local.len);
    try std.testing.expectEqual(@as(usize, 0), multiple_result.ud_sum_local.len);
    try std.testing.expectEqual(@as(usize, 0), no_local_sum_result.ud_sum_local.len);
    try std.testing.expectEqual(@as(usize, nlevel), local_sum_result.ud_sum_local.len);

    try no_local_sum_workspace.ensureLocalSumCapacity(nlevel);
    try std.testing.expectEqual(@as(usize, nlevel), no_local_sum_workspace.ud_sum_local.len);

    for (0..nlevel) |ilevel| {
        for (0..2) |col| {
            for (0..nmutot) |imu| {
                try std.testing.expectApproxEqAbs(
                    single_result.ud[ilevel].U.col[col].get(imu),
                    multiple_result.ud[ilevel].U.col[col].get(imu),
                    1.0e-15,
                );
                try std.testing.expectApproxEqAbs(
                    single_result.ud[ilevel].D.col[col].get(imu),
                    multiple_result.ud[ilevel].D.col[col].get(imu),
                    1.0e-15,
                );
            }
        }
    }
}
