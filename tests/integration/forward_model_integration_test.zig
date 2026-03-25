const std = @import("std");
const zdisamar = @import("zdisamar");

fn meanVectorInRange(
    wavelengths_nm: []const f64,
    values: []const f64,
    start_nm: f64,
    end_nm: f64,
) f64 {
    var sum: f64 = 0.0;
    var count: usize = 0;
    for (wavelengths_nm, values) |wavelength_nm, value| {
        if (wavelength_nm < start_nm or wavelength_nm > end_nm) continue;
        sum += value;
        count += 1;
    }
    return if (count == 0) 0.0 else sum / @as(f64, @floatFromInt(count));
}

fn minVectorInRange(
    wavelengths_nm: []const f64,
    values: []const f64,
    start_nm: f64,
    end_nm: f64,
) struct { wavelength_nm: f64, value: f64 } {
    var best = std.math.inf(f64);
    var best_wavelength = start_nm;
    for (wavelengths_nm, values) |wavelength_nm, value| {
        if (wavelength_nm < start_nm or wavelength_nm > end_nm) continue;
        if (value < best) {
            best = value;
            best_wavelength = wavelength_nm;
        }
    }
    return .{ .wavelength_nm = best_wavelength, .value = best };
}

fn maxVectorInRange(
    wavelengths_nm: []const f64,
    values: []const f64,
    start_nm: f64,
    end_nm: f64,
) f64 {
    var best = -std.math.inf(f64);
    for (wavelengths_nm, values) |wavelength_nm, value| {
        if (wavelength_nm < start_nm or wavelength_nm > end_nm) continue;
        if (value > best) best = value;
    }
    return best;
}

fn meanAbsoluteDifference(values_a: []const f64, values_b: []const f64) f64 {
    var sum: f64 = 0.0;
    for (values_a, values_b) |value_a, value_b| {
        sum += @abs(value_a - value_b);
    }
    return sum / @as(f64, @floatFromInt(values_a.len));
}

fn expectBoundedO2AMorphology(
    wavelengths_nm: []const f64,
    reflectance: []const f64,
) !void {
    const trough = minVectorInRange(wavelengths_nm, reflectance, 760.8, 761.2);
    const rebound_peak = maxVectorInRange(wavelengths_nm, reflectance, 761.8, 762.4);
    const mid_band_mean = meanVectorInRange(wavelengths_nm, reflectance, 763.8, 765.5);
    const red_wing_mean = meanVectorInRange(wavelengths_nm, reflectance, 769.8, 770.6);

    try std.testing.expect(trough.wavelength_nm >= 760.8 and trough.wavelength_nm < 761.2);
    try std.testing.expect(trough.value > 0.002 and trough.value < 0.12);
    try std.testing.expect(rebound_peak > trough.value * 4.0 and rebound_peak < 0.35);
    try std.testing.expect(mid_band_mean > trough.value * 3.0 and mid_band_mean < rebound_peak * 0.8);
    try std.testing.expect(red_wing_mean > trough.value * 6.0);
    try std.testing.expect(red_wing_mean > rebound_peak * 1.1);
    try std.testing.expect(red_wing_mean > mid_band_mean * 1.4);
}

test "engine execute materializes measurement-space summaries through the typed forward path" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .observation_regime = .limb,
            .derivative_mode = .semi_analytical,
            .spectral_grid = .{
                .start_nm = 405.0,
                .end_nm = 465.0,
                .sample_count = 48,
            },
            .layer_count_hint = 24,
            .measurement_count_hint = 48,
        },
    });
    defer plan.deinit();

    var workspace = engine.createWorkspace("forward-integration");
    var request = zdisamar.Request.init(.{
        .id = "scene-forward-integration",
        .atmosphere = .{
            .layer_count = 24,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.15,
        },
        .surface = .{
            .albedo = 0.08,
        },
        .observation_model = .{
            .instrument = .{ .custom = "integration-synthetic" },
            .regime = .limb,
            .sampling = .operational,
            .noise_model = .shot_noise,
        },
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 48,
        },
    });
    request.expected_derivative_mode = .semi_analytical;
    request.diagnostics = .{
        .provenance = true,
        .jacobians = true,
    };

    var result = try engine.execute(&plan, &workspace, &request);
    defer result.deinit(std.testing.allocator);
    const measurement_space = result.measurement_space orelse return error.MissingMeasurementSummary;
    const measurement_product = result.measurement_space_product orelse return error.MissingMeasurementProduct;

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expectEqual(@as(u32, 48), measurement_space.sample_count);
    try std.testing.expect(measurement_space.mean_radiance > 0.0);
    try std.testing.expect(measurement_space.mean_irradiance > 0.0);
    try std.testing.expect(measurement_space.mean_reflectance > 0.0);
    try std.testing.expect(measurement_space.mean_noise_sigma > 0.0);
    try std.testing.expect(measurement_space.mean_jacobian != null);
    try std.testing.expectEqual(measurement_space.sample_count, @as(u32, @intCast(measurement_product.wavelengths.len)));
    try std.testing.expectEqual(@as(usize, 48), measurement_product.radiance.len);
    try std.testing.expect(measurement_product.radiance[0] > 0.0);
    try std.testing.expect(measurement_product.radiance[0] != measurement_product.radiance[measurement_product.radiance.len - 1]);
    try std.testing.expect(measurement_product.reflectance[0] != measurement_product.reflectance[measurement_product.reflectance.len - 1]);
    try std.testing.expect(measurement_product.wavelengths[0] < measurement_product.wavelengths[measurement_product.wavelengths.len - 1]);
    for (measurement_product.wavelengths, measurement_product.radiance, measurement_product.irradiance, measurement_product.reflectance, 0..) |wavelength_nm, radiance, irradiance, reflectance, index| {
        if (index > 0) try std.testing.expect(wavelength_nm > measurement_product.wavelengths[index - 1]);
        try std.testing.expect(std.math.isFinite(radiance) and radiance > 0.0);
        try std.testing.expect(std.math.isFinite(irradiance) and irradiance > 0.0);
        try std.testing.expect(std.math.isFinite(reflectance) and reflectance > 0.0 and reflectance < 1.0);
    }
    try std.testing.expect(measurement_product.jacobian != null);
}

test "engine execute annotates provenance and responds to explicit interval aerosol fractions" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const grid: zdisamar.SpectralGrid = .{
        .start_nm = 405.0,
        .end_nm = 465.0,
        .sample_count = 41,
    };

    var plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .none,
            .spectral_grid = grid,
            .layer_count_hint = 3,
            .measurement_count_hint = grid.sample_count,
        },
    });
    defer plan.deinit();

    const base_scene: zdisamar.Scene = .{
        .id = "forward-explicit-intervals",
        .atmosphere = .{
            .layer_count = 3,
            .has_clouds = true,
            .has_aerosols = true,
            .interval_grid = .{
                .semantics = .explicit_pressure_bounds,
                .fit_interval_index_1based = 2,
                .intervals = &.{
                    .{
                        .index_1based = 1,
                        .top_pressure_hpa = 120.0,
                        .bottom_pressure_hpa = 350.0,
                        .top_altitude_km = 16.0,
                        .bottom_altitude_km = 8.0,
                        .altitude_divisions = 2,
                    },
                    .{
                        .index_1based = 2,
                        .top_pressure_hpa = 350.0,
                        .bottom_pressure_hpa = 800.0,
                        .top_altitude_km = 8.0,
                        .bottom_altitude_km = 2.0,
                        .altitude_divisions = 3,
                    },
                    .{
                        .index_1based = 3,
                        .top_pressure_hpa = 800.0,
                        .bottom_pressure_hpa = 1013.0,
                        .top_altitude_km = 2.0,
                        .bottom_altitude_km = 0.0,
                        .altitude_divisions = 1,
                    },
                },
            },
            .subcolumns = .{
                .enabled = true,
                .boundary_layer_top_altitude_km = 2.0,
                .tropopause_altitude_km = 8.0,
                .subcolumns = &.{
                    .{
                        .index_1based = 1,
                        .label = .boundary_layer,
                        .bottom_altitude_km = 0.0,
                        .top_altitude_km = 2.0,
                    },
                    .{
                        .index_1based = 2,
                        .label = .free_troposphere,
                        .bottom_altitude_km = 2.0,
                        .top_altitude_km = 8.0,
                    },
                    .{
                        .index_1based = 3,
                        .label = .stratosphere,
                        .bottom_altitude_km = 8.0,
                        .top_altitude_km = 16.0,
                    },
                },
            },
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.35,
            .single_scatter_albedo = 0.95,
            .asymmetry_factor = 0.70,
            .angstrom_exponent = 1.0,
            .reference_wavelength_nm = 550.0,
            .placement = .{
                .semantics = .explicit_interval_bounds,
                .interval_index_1based = 2,
                .top_pressure_hpa = 350.0,
                .bottom_pressure_hpa = 800.0,
                .top_altitude_km = 8.0,
                .bottom_altitude_km = 2.0,
            },
        },
        .cloud = .{
            .enabled = true,
            .optical_thickness = 0.10,
            .single_scatter_albedo = 0.998,
            .asymmetry_factor = 0.84,
            .angstrom_exponent = 0.25,
            .reference_wavelength_nm = 550.0,
            .placement = .{
                .semantics = .explicit_interval_bounds,
                .interval_index_1based = 3,
                .top_pressure_hpa = 800.0,
                .bottom_pressure_hpa = 1013.0,
                .top_altitude_km = 2.0,
                .bottom_altitude_km = 0.0,
            },
            .fraction = .{
                .enabled = true,
                .target = .cloud,
                .kind = .wavel_independent,
                .values = &.{0.50},
            },
        },
        .surface = .{
            .albedo = 0.04,
            .pressure_hpa = 1013.0,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 45.0,
            .viewing_zenith_deg = 12.0,
            .relative_azimuth_deg = 35.0,
        },
        .observation_model = .{
            .instrument = .{ .custom = "interval-fraction-integration" },
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .none,
        },
        .spectral_grid = grid,
    };

    var request_full = zdisamar.Request.init(.{
        .id = base_scene.id,
        .atmosphere = base_scene.atmosphere,
        .aerosol = .{
            .id = base_scene.aerosol.id,
            .aerosol_type = base_scene.aerosol.aerosol_type,
            .provider = base_scene.aerosol.provider,
            .enabled = true,
            .optical_depth = base_scene.aerosol.optical_depth,
            .single_scatter_albedo = base_scene.aerosol.single_scatter_albedo,
            .asymmetry_factor = base_scene.aerosol.asymmetry_factor,
            .angstrom_exponent = base_scene.aerosol.angstrom_exponent,
            .reference_wavelength_nm = base_scene.aerosol.reference_wavelength_nm,
            .placement = base_scene.aerosol.placement,
            .fraction = .{
                .enabled = true,
                .target = .aerosol,
                .kind = .wavel_independent,
                .values = &.{1.0},
            },
        },
        .cloud = base_scene.cloud,
        .surface = base_scene.surface,
        .geometry = base_scene.geometry,
        .observation_model = base_scene.observation_model,
        .spectral_grid = base_scene.spectral_grid,
    });
    request_full.diagnostics = .{ .provenance = true };

    var request_reduced = zdisamar.Request.init(.{
        .id = base_scene.id,
        .atmosphere = base_scene.atmosphere,
        .aerosol = .{
            .id = base_scene.aerosol.id,
            .aerosol_type = base_scene.aerosol.aerosol_type,
            .provider = base_scene.aerosol.provider,
            .enabled = true,
            .optical_depth = base_scene.aerosol.optical_depth,
            .single_scatter_albedo = base_scene.aerosol.single_scatter_albedo,
            .asymmetry_factor = base_scene.aerosol.asymmetry_factor,
            .angstrom_exponent = base_scene.aerosol.angstrom_exponent,
            .reference_wavelength_nm = base_scene.aerosol.reference_wavelength_nm,
            .placement = base_scene.aerosol.placement,
            .fraction = .{
                .enabled = true,
                .target = .aerosol,
                .kind = .wavel_independent,
                .values = &.{0.20},
            },
        },
        .cloud = base_scene.cloud,
        .surface = base_scene.surface,
        .geometry = base_scene.geometry,
        .observation_model = base_scene.observation_model,
        .spectral_grid = base_scene.spectral_grid,
    });
    request_reduced.diagnostics = .{ .provenance = true };

    var workspace = engine.createWorkspace("forward-explicit-intervals");
    var result_full = try engine.execute(&plan, &workspace, &request_full);
    defer result_full.deinit(std.testing.allocator);
    workspace.reset();
    var result_reduced = try engine.execute(&plan, &workspace, &request_reduced);
    defer result_reduced.deinit(std.testing.allocator);

    try std.testing.expect(
        result_full.measurement_space.?.mean_reflectance >
            result_reduced.measurement_space.?.mean_reflectance,
    );
    try std.testing.expectEqual(.explicit_pressure_bounds, result_reduced.provenance.interval_semantics);
    try std.testing.expectEqual(.configured_partitions, result_reduced.provenance.subcolumn_semantics);
    try std.testing.expectEqual(.mie_table, result_reduced.provenance.aerosol_phase_support);
    try std.testing.expectEqual(.analytic_hg, result_reduced.provenance.cloud_phase_support);
}

test "engine execute produces bounded O2A morphology through the typed forward path" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .semi_analytical,
            .spectral_grid = .{
                .start_nm = 760.8,
                .end_nm = 771.5,
                .sample_count = 61,
            },
            .layer_count_hint = 12,
            .measurement_count_hint = 61,
        },
        .rtm_controls = .{
            .n_streams = 4,
            .num_orders_max = 12,
        },
    });
    defer plan.deinit();

    var workspace = engine.createWorkspace("forward-o2a-integration");
    var request = zdisamar.Request.init(.{
        .id = "scene-forward-o2a-integration",
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
            .instrument = .{ .custom = "integration-o2a" },
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.38,
            .builtin_line_shape = .flat_top_n4,
            .high_resolution_step_nm = 0.04,
            .high_resolution_half_span_nm = 0.76,
        },
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 771.5,
            .sample_count = 61,
        },
    });
    request.expected_derivative_mode = .semi_analytical;
    request.diagnostics = .{
        .provenance = true,
        .jacobians = true,
    };

    var result = try engine.execute(&plan, &workspace, &request);
    defer result.deinit(std.testing.allocator);
    const product = result.measurement_space_product orelse return error.MissingMeasurementProduct;

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expectEqualStrings("baseline_labos", result.provenance.transport_family);
    try std.testing.expect(product.jacobian != null);
    try expectBoundedO2AMorphology(product.wavelengths, product.reflectance);
}

test "engine execute changes route and reflectance when RTM controls change" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const grid: zdisamar.SpectralGrid = .{
        .start_nm = 760.8,
        .end_nm = 771.5,
        .sample_count = 41,
    };

    var request = zdisamar.Request.init(.{
        .id = "scene-forward-rtm-controls",
        .atmosphere = .{
            .layer_count = 12,
            .sublayer_divisions = 2,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.22,
            .single_scatter_albedo = 0.98,
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
            .instrument = .{ .custom = "integration-o2a-rtm-controls" },
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.38,
            .builtin_line_shape = .flat_top_n4,
            .high_resolution_step_nm = 0.04,
            .high_resolution_half_span_nm = 0.76,
        },
        .spectral_grid = grid,
    });
    request.expected_derivative_mode = .none;
    request.diagnostics = .{ .provenance = true };

    const plan_blueprint: zdisamar.PlanTemplate = .{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .none,
            .spectral_grid = grid,
            .layer_count_hint = 12,
            .measurement_count_hint = grid.sample_count,
        },
    };

    var plan_low_streams = try engine.preparePlan(.{
        .scene_blueprint = plan_blueprint.scene_blueprint,
        .rtm_controls = .{
            .n_streams = 4,
            .num_orders_max = 4,
        },
    });
    defer plan_low_streams.deinit();
    var plan_high_streams = try engine.preparePlan(.{
        .scene_blueprint = plan_blueprint.scene_blueprint,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 4,
        },
    });
    defer plan_high_streams.deinit();
    var plan_adding = try engine.preparePlan(.{
        .scene_blueprint = plan_blueprint.scene_blueprint,
        .rtm_controls = .{
            .n_streams = 8,
            .use_adding = true,
            .num_orders_max = 4,
        },
    });
    defer plan_adding.deinit();

    try std.testing.expectEqualStrings("baseline_labos", plan_low_streams.transport_route.family.provenanceLabel());
    try std.testing.expectEqualStrings("baseline_labos", plan_high_streams.transport_route.family.provenanceLabel());
    try std.testing.expectEqualStrings("baseline_adding", plan_adding.transport_route.family.provenanceLabel());

    var workspace = engine.createWorkspace("forward-rtm-controls");
    var result_low = try engine.execute(&plan_low_streams, &workspace, &request);
    defer result_low.deinit(std.testing.allocator);
    workspace.reset();
    var result_high = try engine.execute(&plan_high_streams, &workspace, &request);
    defer result_high.deinit(std.testing.allocator);
    workspace.reset();
    var result_adding = try engine.execute(&plan_adding, &workspace, &request);
    defer result_adding.deinit(std.testing.allocator);

    const product_low = result_low.measurement_space_product orelse return error.MissingMeasurementProduct;
    const product_high = result_high.measurement_space_product orelse return error.MissingMeasurementProduct;
    const product_adding = result_adding.measurement_space_product orelse return error.MissingMeasurementProduct;

    const stream_delta = meanAbsoluteDifference(product_low.reflectance, product_high.reflectance);
    const family_delta = meanAbsoluteDifference(product_high.reflectance, product_adding.reflectance);

    try std.testing.expect(stream_delta > 1.0e-5);
    try std.testing.expect(family_delta > 1.0e-5);
    try std.testing.expectEqualStrings("baseline_labos", result_high.provenance.transport_family);
    try std.testing.expectEqualStrings("baseline_adding", result_adding.provenance.transport_family);
}

test "engine preparePlan and execute support adding no-scattering routes" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const grid: zdisamar.SpectralGrid = .{
        .start_nm = 758.8,
        .end_nm = 761.2,
        .sample_count = 9,
    };

    var plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .none,
            .spectral_grid = grid,
            .layer_count_hint = 8,
            .measurement_count_hint = grid.sample_count,
        },
        .rtm_controls = .{
            .use_adding = true,
            .scattering = .none,
            .n_streams = 8,
            .use_spherical_correction = true,
        },
    });
    defer plan.deinit();

    try std.testing.expectEqualStrings("baseline_adding", plan.transport_route.family.provenanceLabel());
    try std.testing.expect(plan.transport_route.rtm_controls.use_adding);
    try std.testing.expectEqual(.none, plan.transport_route.rtm_controls.scattering);

    var workspace = engine.createWorkspace("forward-adding-no-scattering");
    var request = zdisamar.Request.init(.{
        .id = "scene-forward-adding-no-scattering",
        .atmosphere = .{
            .layer_count = 8,
            .sublayer_divisions = 2,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.12,
            .single_scatter_albedo = 0.0,
            .asymmetry_factor = 0.0,
            .reference_wavelength_nm = 760.0,
            .layer_center_km = 5.0,
            .layer_width_km = 0.6,
        },
        .surface = .{
            .albedo = 0.18,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 30.0,
            .relative_azimuth_deg = 35.0,
        },
        .observation_model = .{
            .instrument = .{ .custom = "integration-adding-no-scattering" },
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .none,
        },
        .spectral_grid = grid,
    });
    request.expected_derivative_mode = .none;
    request.diagnostics = .{ .provenance = true };

    var result = try engine.execute(&plan, &workspace, &request);
    defer result.deinit(std.testing.allocator);
    const product = result.measurement_space_product orelse return error.MissingMeasurementProduct;

    try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    try std.testing.expectEqualStrings("baseline_adding", result.provenance.transport_family);
    try std.testing.expectEqual(@as(usize, grid.sample_count), product.reflectance.len);
    for (product.reflectance) |value| {
        try std.testing.expect(std.math.isFinite(value));
        try std.testing.expect(value > 0.0);
    }
}

test "engine execute changes labos no-scattering output when spherical correction changes" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const grid: zdisamar.SpectralGrid = .{
        .start_nm = 758.8,
        .end_nm = 761.2,
        .sample_count = 9,
    };

    const blueprint: zdisamar.PlanTemplate = .{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .none,
            .spectral_grid = grid,
            .layer_count_hint = 8,
            .measurement_count_hint = grid.sample_count,
        },
    };

    var plan_plane = try engine.preparePlan(.{
        .scene_blueprint = blueprint.scene_blueprint,
        .rtm_controls = .{
            .scattering = .none,
            .n_streams = 8,
            .use_spherical_correction = false,
        },
    });
    defer plan_plane.deinit();
    var plan_spherical = try engine.preparePlan(.{
        .scene_blueprint = blueprint.scene_blueprint,
        .rtm_controls = .{
            .scattering = .none,
            .n_streams = 8,
            .use_spherical_correction = true,
        },
    });
    defer plan_spherical.deinit();

    var request = zdisamar.Request.init(.{
        .id = "scene-forward-labos-no-scattering",
        .atmosphere = .{
            .layer_count = 8,
            .sublayer_divisions = 2,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.12,
            .single_scatter_albedo = 0.0,
            .asymmetry_factor = 0.0,
            .reference_wavelength_nm = 760.0,
            .layer_center_km = 5.0,
            .layer_width_km = 0.6,
        },
        .surface = .{
            .albedo = 0.18,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 30.0,
            .relative_azimuth_deg = 35.0,
        },
        .observation_model = .{
            .instrument = .{ .custom = "integration-labos-no-scattering" },
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .none,
        },
        .spectral_grid = grid,
    });
    request.expected_derivative_mode = .none;
    request.diagnostics = .{ .provenance = true };

    var workspace = engine.createWorkspace("forward-labos-no-scattering");
    var result_plane = try engine.execute(&plan_plane, &workspace, &request);
    defer result_plane.deinit(std.testing.allocator);
    workspace.reset();
    var result_spherical = try engine.execute(&plan_spherical, &workspace, &request);
    defer result_spherical.deinit(std.testing.allocator);

    const product_plane = result_plane.measurement_space_product orelse return error.MissingMeasurementProduct;
    const product_spherical = result_spherical.measurement_space_product orelse return error.MissingMeasurementProduct;
    const reflectance_delta = meanAbsoluteDifference(product_plane.reflectance, product_spherical.reflectance);

    try std.testing.expectEqualStrings("baseline_labos", result_plane.provenance.transport_family);
    try std.testing.expectEqualStrings("baseline_labos", result_spherical.provenance.transport_family);
    try std.testing.expect(reflectance_delta > 1.0e-6);
    for (product_spherical.reflectance) |value| {
        try std.testing.expect(std.math.isFinite(value));
        try std.testing.expect(value > 0.0);
    }
}

test "engine execute changes prepared adding multiple-scattering output when spherical correction changes" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const grid: zdisamar.SpectralGrid = .{
        .start_nm = 760.8,
        .end_nm = 771.5,
        .sample_count = 31,
    };

    const blueprint: zdisamar.PlanTemplate = .{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .none,
            .spectral_grid = grid,
            .layer_count_hint = 12,
            .measurement_count_hint = grid.sample_count,
        },
    };

    var plan_plane = try engine.preparePlan(.{
        .scene_blueprint = blueprint.scene_blueprint,
        .rtm_controls = .{
            .n_streams = 8,
            .use_adding = true,
            .num_orders_max = 4,
            .use_spherical_correction = false,
        },
    });
    defer plan_plane.deinit();
    var plan_spherical = try engine.preparePlan(.{
        .scene_blueprint = blueprint.scene_blueprint,
        .rtm_controls = .{
            .n_streams = 8,
            .use_adding = true,
            .num_orders_max = 4,
            .use_spherical_correction = true,
        },
    });
    defer plan_spherical.deinit();

    var request = zdisamar.Request.init(.{
        .id = "scene-forward-adding-spherical",
        .atmosphere = .{
            .layer_count = 12,
            .sublayer_divisions = 2,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.22,
            .single_scatter_albedo = 0.98,
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
            .instrument = .{ .custom = "integration-adding-spherical" },
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.38,
            .builtin_line_shape = .flat_top_n4,
            .high_resolution_step_nm = 0.04,
            .high_resolution_half_span_nm = 0.76,
        },
        .spectral_grid = grid,
    });
    request.expected_derivative_mode = .none;
    request.diagnostics = .{ .provenance = true };

    var workspace = engine.createWorkspace("forward-adding-spherical");
    var result_plane = try engine.execute(&plan_plane, &workspace, &request);
    defer result_plane.deinit(std.testing.allocator);
    workspace.reset();
    var result_spherical = try engine.execute(&plan_spherical, &workspace, &request);
    defer result_spherical.deinit(std.testing.allocator);

    const product_plane = result_plane.measurement_space_product orelse return error.MissingMeasurementProduct;
    const product_spherical = result_spherical.measurement_space_product orelse return error.MissingMeasurementProduct;
    const reflectance_delta = meanAbsoluteDifference(product_plane.reflectance, product_spherical.reflectance);

    try std.testing.expectEqualStrings("baseline_adding", result_plane.provenance.transport_family);
    try std.testing.expectEqualStrings("baseline_adding", result_spherical.provenance.transport_family);
    try std.testing.expect(reflectance_delta > 1.0e-6);
    for (product_spherical.reflectance) |value| {
        try std.testing.expect(std.math.isFinite(value));
        try std.testing.expect(value > 0.0);
    }
}

test "engine execute changes prepared adding output when integrated source-function toggles" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const grid: zdisamar.SpectralGrid = .{
        .start_nm = 760.8,
        .end_nm = 771.5,
        .sample_count = 31,
    };

    const blueprint: zdisamar.PlanTemplate = .{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .none,
            .spectral_grid = grid,
            .layer_count_hint = 12,
            .measurement_count_hint = grid.sample_count,
        },
    };

    var plan_direct = try engine.preparePlan(.{
        .scene_blueprint = blueprint.scene_blueprint,
        .rtm_controls = .{
            .n_streams = 8,
            .use_adding = true,
            .num_orders_max = 4,
            .integrate_source_function = false,
        },
    });
    defer plan_direct.deinit();
    var plan_integrated = try engine.preparePlan(.{
        .scene_blueprint = blueprint.scene_blueprint,
        .rtm_controls = .{
            .n_streams = 8,
            .use_adding = true,
            .num_orders_max = 4,
            .integrate_source_function = true,
        },
    });
    defer plan_integrated.deinit();

    var request = zdisamar.Request.init(.{
        .id = "scene-forward-adding-integrated-source",
        .atmosphere = .{
            .layer_count = 12,
            .sublayer_divisions = 2,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.22,
            .single_scatter_albedo = 0.98,
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
            .instrument = .{ .custom = "integration-adding-integrated-source" },
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.38,
            .builtin_line_shape = .flat_top_n4,
            .high_resolution_step_nm = 0.04,
            .high_resolution_half_span_nm = 0.76,
        },
        .spectral_grid = grid,
    });
    request.expected_derivative_mode = .none;
    request.diagnostics = .{ .provenance = true };

    var workspace = engine.createWorkspace("forward-adding-integrated-source");
    var result_direct = try engine.execute(&plan_direct, &workspace, &request);
    defer result_direct.deinit(std.testing.allocator);
    workspace.reset();
    var result_integrated = try engine.execute(&plan_integrated, &workspace, &request);
    defer result_integrated.deinit(std.testing.allocator);

    const product_direct = result_direct.measurement_space_product orelse return error.MissingMeasurementProduct;
    const product_integrated = result_integrated.measurement_space_product orelse return error.MissingMeasurementProduct;
    const reflectance_delta = meanAbsoluteDifference(product_direct.reflectance, product_integrated.reflectance);

    try std.testing.expectEqualStrings("baseline_adding", result_direct.provenance.transport_family);
    try std.testing.expectEqualStrings("baseline_adding", result_integrated.provenance.transport_family);
    try std.testing.expect(reflectance_delta > 1.0e-6);
    for (product_integrated.reflectance) |value| {
        try std.testing.expect(std.math.isFinite(value));
        try std.testing.expect(value > 0.0);
    }
}

test "engine execute changes reflectance with relative azimuth for anisotropic scattering scenes" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const grid: zdisamar.SpectralGrid = .{
        .start_nm = 760.8,
        .end_nm = 771.5,
        .sample_count = 31,
    };

    var plan = try engine.preparePlan(.{
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
    defer plan.deinit();

    const make_request = struct {
        fn f(relative_azimuth_deg: f64) zdisamar.Request {
            return zdisamar.Request.init(.{
                .id = "scene-forward-o2a-azimuth",
                .atmosphere = .{
                    .layer_count = 12,
                    .sublayer_divisions = 2,
                    .has_aerosols = true,
                },
                .aerosol = .{
                    .enabled = true,
                    .optical_depth = 0.22,
                    .single_scatter_albedo = 0.98,
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
                    .relative_azimuth_deg = relative_azimuth_deg,
                },
                .observation_model = .{
                    .instrument = .{ .custom = "integration-o2a-azimuth" },
                    .regime = .nadir,
                    .sampling = .native,
                    .noise_model = .shot_noise,
                    .instrument_line_fwhm_nm = 0.38,
                    .builtin_line_shape = .flat_top_n4,
                    .high_resolution_step_nm = 0.04,
                    .high_resolution_half_span_nm = 0.76,
                },
                .spectral_grid = grid,
            });
        }
    }.f;

    var request_zero = make_request(0.0);
    request_zero.expected_derivative_mode = .none;
    var request_oblique = make_request(120.0);
    request_oblique.expected_derivative_mode = .none;

    var workspace = engine.createWorkspace("forward-o2a-azimuth");
    var result_zero = try engine.execute(&plan, &workspace, &request_zero);
    defer result_zero.deinit(std.testing.allocator);
    workspace.reset();
    var result_oblique = try engine.execute(&plan, &workspace, &request_oblique);
    defer result_oblique.deinit(std.testing.allocator);

    const product_zero = result_zero.measurement_space_product orelse return error.MissingMeasurementProduct;
    const product_oblique = result_oblique.measurement_space_product orelse return error.MissingMeasurementProduct;
    const azimuth_delta = meanAbsoluteDifference(product_zero.reflectance, product_oblique.reflectance);

    try std.testing.expect(azimuth_delta > 1.0e-5);
}
