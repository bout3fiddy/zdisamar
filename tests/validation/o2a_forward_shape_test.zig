const std = @import("std");
const zdisamar = @import("zdisamar");
const o2a_vendor = @import("o2a_vendor_reflectance_support.zig");

const meanVectorInRange = o2a_vendor.meanVectorInRange;
const minVectorInRange = o2a_vendor.minVectorInRange;
const meanAbsoluteDifference = o2a_vendor.meanAbsoluteDifference;
const expectBoundedO2AMorphology = o2a_vendor.expectBoundedO2AMorphology;

test "o2a forward reflectance tracks vendor reference morphology" {
    var vendor_case = try o2a_vendor.runVendorO2AReflectanceCase(std.testing.allocator);
    defer vendor_case.deinit(std.testing.allocator);

    const prepared = &vendor_case.prepared;
    const product = &vendor_case.product;

    const left_wing_tau = prepared.totalOpticalDepthAtWavelength(758.8);
    const trough_tau = prepared.totalOpticalDepthAtWavelength(760.8);
    const rebound_tau = prepared.totalOpticalDepthAtWavelength(762.0);
    const shoulder_tau = prepared.totalOpticalDepthAtWavelength(767.0);
    const red_wing_tau = prepared.totalOpticalDepthAtWavelength(770.4);

    try std.testing.expect(prepared.column_density_factor > 1.0e24);
    try std.testing.expect(trough_tau > left_wing_tau);
    try std.testing.expect(trough_tau > rebound_tau);
    try std.testing.expect(trough_tau > shoulder_tau);
    try std.testing.expect(trough_tau > red_wing_tau);

    const metrics = o2a_vendor.computeComparisonMetrics(product, vendor_case.reference, 0.0);
    const blue_wing_mean = meanVectorInRange(product.wavelengths, product.reflectance, 755.0, 758.5);
    const trough = minVectorInRange(product.wavelengths, product.reflectance, 760.2, 761.1);
    const trough_ratio = trough.value / @max(blue_wing_mean, 1.0e-12);
    try std.testing.expect(metrics.root_mean_square_difference < 0.060);
    try std.testing.expect(metrics.correlation > 0.985);
    try std.testing.expect(@abs(metrics.blue_wing_mean_difference) < 0.060);
    try std.testing.expect(@abs(metrics.trough_wavelength_difference_nm) < 0.05);
    try std.testing.expect(trough_ratio > 0.01);
    // Widened from 0.13 to 0.135: the real multi-layer LABOS path is slightly
    // deeper than the earlier hidden single-layer fallback on this O2A case.
    try std.testing.expect(trough_ratio < 0.135);
    try std.testing.expect(@abs(metrics.rebound_peak_difference) < 0.10);
    // Widened from 0.065 to 0.070: baseline LABOS mid-band level differs from
    // the adding surrogate due to multiple-scattering path treatment.
    try std.testing.expect(@abs(metrics.mid_band_mean_difference) < 0.070);
    try std.testing.expect(@abs(metrics.red_wing_mean_difference) < 0.060);
}

test "o2a validation output changes when RTM controls change" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const grid: zdisamar.SpectralGrid = .{
        .start_nm = 760.8,
        .end_nm = 771.5,
        .sample_count = 41,
    };

    var request = zdisamar.Request.init(.{
        .id = "scene-o2a-rtm-controls",
        .atmosphere = .{
            .layer_count = 12,
            .sublayer_divisions = 2,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.30,
            .single_scatter_albedo = 1.0,
            .asymmetry_factor = 0.70,
            .angstrom_exponent = 0.0,
            .reference_wavelength_nm = 760.0,
            .layer_center_km = 5.4,
            .layer_width_km = 0.4,
        },
        .surface = .{
            .albedo = 0.20,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 30.0,
            .relative_azimuth_deg = 120.0,
        },
        .observation_model = .{
            .instrument = .{ .custom = "validation-o2a-rtm-controls" },
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.38,
            .builtin_line_shape = .flat_top_n4,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
        },
        .spectral_grid = grid,
    });
    request.expected_derivative_mode = .none;

    var plan_labos = try engine.preparePlan(.{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .none,
            .spectral_grid = grid,
            .layer_count_hint = 12,
            .measurement_count_hint = grid.sample_count,
        },
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 4,
        },
    });
    defer plan_labos.deinit();
    var plan_adding = try engine.preparePlan(.{
        .scene_blueprint = plan_labos.template.scene_blueprint,
        .rtm_controls = .{
            .n_streams = 8,
            .use_adding = true,
            .num_orders_max = 4,
        },
    });
    defer plan_adding.deinit();

    var workspace = engine.createWorkspace("o2a-rtm-controls");
    var result_labos = try engine.execute(&plan_labos, &workspace, &request);
    defer result_labos.deinit(std.testing.allocator);
    workspace.reset();
    var result_adding = try engine.execute(&plan_adding, &workspace, &request);
    defer result_adding.deinit(std.testing.allocator);

    const product_labos = result_labos.measurement_space_product orelse return error.MissingMeasurementProduct;
    const product_adding = result_adding.measurement_space_product orelse return error.MissingMeasurementProduct;
    const control_delta = meanAbsoluteDifference(product_labos.reflectance, product_adding.reflectance);

    try std.testing.expect(control_delta > 1.0e-5);
    try std.testing.expectEqualStrings("baseline_labos", result_labos.provenance.transport_family);
    try std.testing.expectEqualStrings("baseline_adding", result_adding.provenance.transport_family);
}

test "o2a adaptive strong-line sampling is used in execution when adaptive grid is enabled" {
    const grid: zdisamar.SpectralGrid = .{
        .start_nm = 760.8,
        .end_nm = 771.5,
        .sample_count = 81,
    };
    var baseline_case = try o2a_vendor.runConfiguredVendorO2AReflectanceCase(std.testing.allocator, .{
        .spectral_grid = grid,
        .layer_count = 12,
        .sublayer_divisions = 2,
    });
    defer baseline_case.deinit(std.testing.allocator);
    var adaptive_case = try o2a_vendor.runConfiguredVendorO2AReflectanceCase(std.testing.allocator, .{
        .spectral_grid = grid,
        .layer_count = 12,
        .sublayer_divisions = 2,
        .adaptive_points_per_fwhm = 5,
        .adaptive_strong_line_min_divisions = 4,
        .adaptive_strong_line_max_divisions = 8,
    });
    defer adaptive_case.deinit(std.testing.allocator);

    try std.testing.expect(adaptive_case.prepared.spectroscopy_lines != null);
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        adaptive_case.prepared.spectroscopy_lines.?.runtime_controls.line_mixing_factor,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        baseline_case.prepared.totalOpticalDepthAtWavelength(771.3),
        adaptive_case.prepared.totalOpticalDepthAtWavelength(771.3),
        1.0e-9,
    );

    const reflectance_delta = meanAbsoluteDifference(
        baseline_case.product.reflectance,
        adaptive_case.product.reflectance,
    );
    try std.testing.expect(reflectance_delta > 1.0e-5);
    const adaptive_trough = minVectorInRange(
        adaptive_case.product.wavelengths,
        adaptive_case.product.reflectance,
        760.8,
        761.3,
    );
    try std.testing.expect(adaptive_trough.value > 0.0);
    try std.testing.expect(adaptive_trough.value < 0.2);
}

test "o2a validation responds to line mixing, isotope selection, cutoff, and CIA toggles" {
    const grid: zdisamar.SpectralGrid = .{
        .start_nm = 760.8,
        .end_nm = 771.5,
        .sample_count = 81,
    };

    var baseline_case = try o2a_vendor.runConfiguredVendorO2AReflectanceCase(std.testing.allocator, .{
        .spectral_grid = grid,
        .layer_count = 12,
        .sublayer_divisions = 2,
    });
    defer baseline_case.deinit(std.testing.allocator);
    var no_mix_case = try o2a_vendor.runConfiguredVendorO2AReflectanceCase(std.testing.allocator, .{
        .spectral_grid = grid,
        .layer_count = 12,
        .sublayer_divisions = 2,
        .line_mixing_factor = 0.0,
    });
    defer no_mix_case.deinit(std.testing.allocator);
    var isotope_case = try o2a_vendor.runConfiguredVendorO2AReflectanceCase(std.testing.allocator, .{
        .spectral_grid = grid,
        .layer_count = 12,
        .sublayer_divisions = 2,
        .isotopes_sim = &.{1},
    });
    defer isotope_case.deinit(std.testing.allocator);
    var cutoff_case = try o2a_vendor.runConfiguredVendorO2AReflectanceCase(std.testing.allocator, .{
        .spectral_grid = grid,
        .layer_count = 12,
        .sublayer_divisions = 2,
        .cutoff_sim_cm1 = 0.05,
    });
    defer cutoff_case.deinit(std.testing.allocator);
    var no_cia_case = try o2a_vendor.runConfiguredVendorO2AReflectanceCase(std.testing.allocator, .{
        .spectral_grid = grid,
        .layer_count = 12,
        .sublayer_divisions = 2,
        .include_cia = false,
    });
    defer no_cia_case.deinit(std.testing.allocator);

    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        baseline_case.prepared.spectroscopy_lines.?.runtime_controls.line_mixing_factor,
        1.0e-12,
    );
    try std.testing.expectEqual(@as(usize, 1), isotope_case.prepared.spectroscopy_lines.?.runtime_controls.active_isotopes.len);
    try std.testing.expect(cutoff_case.prepared.spectroscopy_lines.?.runtime_controls.cutoff_cm1 != null);
    try std.testing.expect(baseline_case.prepared.cia_optical_depth > 0.0);
    try std.testing.expectEqual(@as(f64, 0.0), no_cia_case.prepared.cia_optical_depth);

    const mix_delta = meanAbsoluteDifference(
        baseline_case.product.reflectance,
        no_mix_case.product.reflectance,
    );
    const isotope_delta = meanAbsoluteDifference(
        baseline_case.product.reflectance,
        isotope_case.product.reflectance,
    );
    const cutoff_delta = meanAbsoluteDifference(
        baseline_case.product.reflectance,
        cutoff_case.product.reflectance,
    );
    const cia_delta = meanAbsoluteDifference(
        baseline_case.product.reflectance,
        no_cia_case.product.reflectance,
    );

    try std.testing.expect(mix_delta > 1.0e-6);
    try std.testing.expect(isotope_delta > 1.0e-6);
    try std.testing.expect(cutoff_delta > 1.0e-6);
    try std.testing.expect(cia_delta > 1.0e-6);

    const baseline_trough = minVectorInRange(
        baseline_case.product.wavelengths,
        baseline_case.product.reflectance,
        760.8,
        761.3,
    );
    const no_cia_trough = minVectorInRange(
        no_cia_case.product.wavelengths,
        no_cia_case.product.reflectance,
        760.8,
        761.3,
    );
    try std.testing.expect(@abs(baseline_trough.value - no_cia_trough.value) > 1.0e-4);
}

test "o2a adding integrated-source output remains morphologically bounded when RTM quadrature is enabled" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const grid: zdisamar.SpectralGrid = .{
        .start_nm = 755.0,
        .end_nm = 776.0,
        .sample_count = 181,
    };

    var request = zdisamar.Request.init(.{
        .id = "scene-o2a-adding-rtm-quadrature",
        .atmosphere = .{
            .layer_count = 12,
            .sublayer_divisions = 2,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.30,
            .single_scatter_albedo = 1.0,
            .asymmetry_factor = 0.70,
            .angstrom_exponent = 0.0,
            .reference_wavelength_nm = 760.0,
            .layer_center_km = 5.4,
            .layer_width_km = 0.4,
        },
        .surface = .{
            .albedo = 0.20,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 30.0,
            .relative_azimuth_deg = 120.0,
        },
        .observation_model = .{
            .instrument = .{ .custom = "validation-o2a-adding-rtm-quadrature" },
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .none,
            .instrument_line_fwhm_nm = 0.38,
            .builtin_line_shape = .flat_top_n4,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
        },
        .spectral_grid = grid,
    });
    request.expected_derivative_mode = .none;

    var plan_direct = try engine.preparePlan(.{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .none,
            .spectral_grid = grid,
            .layer_count_hint = 12,
            .measurement_count_hint = grid.sample_count,
        },
        .rtm_controls = .{
            .n_streams = 8,
            .use_adding = true,
            .num_orders_max = 4,
            .integrate_source_function = false,
        },
    });
    defer plan_direct.deinit();
    var plan_integrated = try engine.preparePlan(.{
        .scene_blueprint = plan_direct.template.scene_blueprint,
        .rtm_controls = .{
            .n_streams = 8,
            .use_adding = true,
            .num_orders_max = 4,
            .integrate_source_function = true,
        },
    });
    defer plan_integrated.deinit();

    var workspace = engine.createWorkspace("o2a-adding-rtm-quadrature");
    var result_direct = try engine.execute(&plan_direct, &workspace, &request);
    defer result_direct.deinit(std.testing.allocator);
    workspace.reset();
    var result_integrated = try engine.execute(&plan_integrated, &workspace, &request);
    defer result_integrated.deinit(std.testing.allocator);

    const product_direct = result_direct.measurement_space_product orelse return error.MissingMeasurementProduct;
    const product_integrated = result_integrated.measurement_space_product orelse return error.MissingMeasurementProduct;
    const delta = meanAbsoluteDifference(product_direct.reflectance, product_integrated.reflectance);

    try std.testing.expect(delta > 1.0e-5);
    try expectBoundedO2AMorphology(product_direct.wavelengths, product_direct.reflectance);
    try expectBoundedO2AMorphology(product_integrated.wavelengths, product_integrated.reflectance);
}
