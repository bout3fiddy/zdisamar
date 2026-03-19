const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");
const ReferenceData = internal.reference_data;
const OpticsPrepare = internal.kernels.optics.prepare;
const MeasurementSpace = internal.kernels.transport.measurement_space;

const ReferenceSample = struct {
    wavelength_nm: f64,
    irradiance: f64,
    reflectance: f64,
};

fn zeroContinuumTable(allocator: std.mem.Allocator, start_nm: f64, end_nm: f64) !ReferenceData.CrossSectionTable {
    const midpoint_nm = (start_nm + end_nm) * 0.5;
    return .{
        .points = try allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = start_nm, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = midpoint_nm, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = end_nm, .sigma_cm2_per_molecule = 0.0 },
        }),
    };
}

fn meanOpticalDepthInRange(
    prepared: *const OpticsPrepare.PreparedOpticalState,
    start_nm: f64,
    end_nm: f64,
    step_nm: f64,
) f64 {
    var sum: f64 = 0.0;
    var count: usize = 0;
    var wavelength_nm = start_nm;
    while (wavelength_nm <= end_nm + (step_nm * 0.5)) : (wavelength_nm += step_nm) {
        sum += prepared.totalOpticalDepthAtWavelength(wavelength_nm);
        count += 1;
    }
    return if (count == 0) 0.0 else sum / @as(f64, @floatFromInt(count));
}

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

fn loadReferenceSamples(allocator: std.mem.Allocator, path: []const u8) ![]ReferenceSample {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(bytes);

    var samples = std.ArrayList(ReferenceSample).empty;
    errdefer samples.deinit(allocator);

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    _ = lines.next();
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, "\r \t");
        if (trimmed.len == 0) continue;

        var columns = std.mem.splitScalar(u8, trimmed, ',');
        const wavelength_text = columns.next() orelse return error.InvalidData;
        const irradiance_text = columns.next() orelse return error.InvalidData;
        _ = columns.next() orelse return error.InvalidData;
        const reflectance_text = columns.next() orelse return error.InvalidData;

        try samples.append(allocator, .{
            .wavelength_nm = try std.fmt.parseFloat(f64, std.mem.trim(u8, wavelength_text, " \t")),
            .irradiance = try std.fmt.parseFloat(f64, std.mem.trim(u8, irradiance_text, " \t")),
            .reflectance = try std.fmt.parseFloat(f64, std.mem.trim(u8, reflectance_text, " \t")),
        });
    }

    return try samples.toOwnedSlice(allocator);
}

fn meanReferenceInRange(
    reference: []const ReferenceSample,
    start_nm: f64,
    end_nm: f64,
) f64 {
    var sum: f64 = 0.0;
    var count: usize = 0;
    for (reference) |sample| {
        if (sample.wavelength_nm < start_nm or sample.wavelength_nm > end_nm) continue;
        sum += sample.reflectance;
        count += 1;
    }
    return if (count == 0) 0.0 else sum / @as(f64, @floatFromInt(count));
}

fn minReferenceInRange(
    reference: []const ReferenceSample,
    start_nm: f64,
    end_nm: f64,
) struct { wavelength_nm: f64, value: f64 } {
    var best = std.math.inf(f64);
    var best_wavelength = start_nm;
    for (reference) |sample| {
        if (sample.wavelength_nm < start_nm or sample.wavelength_nm > end_nm) continue;
        if (sample.reflectance < best) {
            best = sample.reflectance;
            best_wavelength = sample.wavelength_nm;
        }
    }
    return .{ .wavelength_nm = best_wavelength, .value = best };
}

fn maxReferenceInRange(
    reference: []const ReferenceSample,
    start_nm: f64,
    end_nm: f64,
) f64 {
    var best = -std.math.inf(f64);
    for (reference) |sample| {
        if (sample.wavelength_nm < start_nm or sample.wavelength_nm > end_nm) continue;
        if (sample.reflectance > best) best = sample.reflectance;
    }
    return best;
}

fn interpolateVector(
    wavelengths_nm: []const f64,
    values: []const f64,
    target_wavelength_nm: f64,
) f64 {
    if (wavelengths_nm.len == 0 or values.len == 0) return 0.0;
    if (target_wavelength_nm <= wavelengths_nm[0]) return values[0];
    if (target_wavelength_nm >= wavelengths_nm[wavelengths_nm.len - 1]) return values[values.len - 1];

    var lower_index: usize = 0;
    while (lower_index + 1 < wavelengths_nm.len and wavelengths_nm[lower_index + 1] < target_wavelength_nm) : (lower_index += 1) {}

    const upper_index = lower_index + 1;
    const lower_wavelength = wavelengths_nm[lower_index];
    const upper_wavelength = wavelengths_nm[upper_index];
    const lower_value = values[lower_index];
    const upper_value = values[upper_index];
    const blend = (target_wavelength_nm - lower_wavelength) / (upper_wavelength - lower_wavelength);
    return lower_value + (upper_value - lower_value) * blend;
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
    const blue_wing_mean = meanVectorInRange(wavelengths_nm, reflectance, 755.0, 758.5);
    const trough = minVectorInRange(wavelengths_nm, reflectance, 760.2, 761.1);
    const rebound_peak = maxVectorInRange(wavelengths_nm, reflectance, 761.8, 762.4);
    const mid_band_mean = meanVectorInRange(wavelengths_nm, reflectance, 763.8, 765.5);
    const red_wing_mean = meanVectorInRange(wavelengths_nm, reflectance, 769.5, 771.0);
    const trough_ratio = trough.value / @max(blue_wing_mean, 1.0e-12);

    try std.testing.expect(blue_wing_mean > 0.0);
    try std.testing.expect(trough.value > 0.0);
    try std.testing.expect(rebound_peak > trough.value);
    try std.testing.expect(mid_band_mean > trough.value);
    try std.testing.expect(red_wing_mean > trough.value);
    try std.testing.expect(trough_ratio > 0.01);
    try std.testing.expect(trough_ratio < 0.18);
}

test "o2a forward reflectance tracks vendor reference morphology" {
    var climatology_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .climatology_profile,
        "data/climatologies/bundle_manifest.json",
        "us_standard_1976_profile",
    );
    defer climatology_asset.deinit(std.testing.allocator);

    var line_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .spectroscopy_line_list,
        "data/cross_sections/bundle_manifest.json",
        "o2a_hitran_07_hit08_tropomi",
    );
    defer line_asset.deinit(std.testing.allocator);
    var strong_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .spectroscopy_strong_line_set,
        "data/cross_sections/bundle_manifest.json",
        "o2a_lisa_sdf",
    );
    defer strong_asset.deinit(std.testing.allocator);
    var rmf_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .spectroscopy_relaxation_matrix,
        "data/cross_sections/bundle_manifest.json",
        "o2a_lisa_rmf",
    );
    defer rmf_asset.deinit(std.testing.allocator);
    var cia_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .collision_induced_absorption_table,
        "data/cross_sections/bundle_manifest.json",
        "o2o2_bira_o2a",
    );
    defer cia_asset.deinit(std.testing.allocator);

    var lut_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .lookup_table,
        "data/luts/bundle_manifest.json",
        "airmass_factor_nadir_demo",
    );
    defer lut_asset.deinit(std.testing.allocator);

    var profile = try climatology_asset.toClimatologyProfile(std.testing.allocator);
    defer profile.deinit(std.testing.allocator);
    var cross_sections = try zeroContinuumTable(std.testing.allocator, 758.0, 771.0);
    defer cross_sections.deinit(std.testing.allocator);
    var line_list = try line_asset.toSpectroscopyLineList(std.testing.allocator);
    defer line_list.deinit(std.testing.allocator);
    var strong_lines = try strong_asset.toSpectroscopyStrongLineSet(std.testing.allocator);
    defer strong_lines.deinit(std.testing.allocator);
    var relaxation_matrix = try rmf_asset.toSpectroscopyRelaxationMatrix(std.testing.allocator);
    defer relaxation_matrix.deinit(std.testing.allocator);
    var cia_table = try cia_asset.toCollisionInducedAbsorptionTable(std.testing.allocator);
    defer cia_table.deinit(std.testing.allocator);
    try line_list.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix);
    var lut = try lut_asset.toAirmassFactorLut(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);

    const reference = try loadReferenceSamples(
        std.testing.allocator,
        "validation/reference/o2a_with_cia_disamar_reference.csv",
    );
    defer std.testing.allocator.free(reference);

    const reference_wavelengths = try std.testing.allocator.alloc(f64, reference.len);
    defer std.testing.allocator.free(reference_wavelengths);
    const reference_irradiance = try std.testing.allocator.alloc(f64, reference.len);
    defer std.testing.allocator.free(reference_irradiance);
    for (reference, 0..) |sample, index| {
        reference_wavelengths[index] = sample.wavelength_nm;
        reference_irradiance[index] = sample.irradiance;
    }

    var scene: zdisamar.Scene = .{
        .id = "o2a-forward-validation",
        .surface = .{
            .albedo = 0.20,
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
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 30.0,
            .relative_azimuth_deg = 120.0,
        },
        .atmosphere = .{
            .layer_count = 48,
            .sublayer_divisions = 4,
            .has_aerosols = true,
        },
        .spectral_grid = .{
            .start_nm = 755.0,
            .end_nm = 776.0,
            .sample_count = 701,
        },
        .observation_model = .{
            .instrument = .{ .custom = "disamar-o2a-compare" },
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .none,
            .instrument_line_fwhm_nm = 0.38,
            .builtin_line_shape = .flat_top_n4,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
        },
    };
    scene.observation_model.operational_solar_spectrum = .{
        .wavelengths_nm = reference_wavelengths,
        .irradiance = reference_irradiance,
    };

    var prepared = try OpticsPrepare.prepareWithSpectroscopyAndCollisionInducedAbsorption(
        std.testing.allocator,
        &scene,
        &profile,
        &cross_sections,
        &cia_table,
        &line_list,
        &lut,
    );
    defer prepared.deinit(std.testing.allocator);

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

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();
    var plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .none,
            .spectral_grid = scene.spectral_grid,
            .layer_count_hint = scene.atmosphere.layer_count,
            .measurement_count_hint = scene.spectral_grid.sample_count,
        },
        .rtm_controls = .{
            .n_streams = 6,
            .num_orders_max = 20,
        },
    });
    defer plan.deinit();

    var product = try MeasurementSpace.simulateProduct(
        std.testing.allocator,
        &scene,
        plan.transport_route,
        &prepared,
        .{
            .transport = plan.providers.transport,
            .surface = plan.providers.surface,
            .instrument = plan.providers.instrument,
            .noise = plan.providers.noise,
        },
    );
    defer product.deinit(std.testing.allocator);

    const blue_wing_mean = meanVectorInRange(product.wavelengths, product.reflectance, 755.0, 758.5);
    const trough = minVectorInRange(product.wavelengths, product.reflectance, 760.2, 761.1);
    const rebound_peak = maxVectorInRange(product.wavelengths, product.reflectance, 761.8, 762.4);
    const mid_band_mean = meanVectorInRange(product.wavelengths, product.reflectance, 763.8, 765.5);
    const red_wing_mean = meanVectorInRange(product.wavelengths, product.reflectance, 769.5, 771.0);

    const reference_blue_wing_mean = meanReferenceInRange(reference, 755.0, 758.5);
    const reference_trough = minReferenceInRange(reference, 760.2, 761.1);
    const reference_rebound_peak = maxReferenceInRange(reference, 761.8, 762.4);
    const reference_mid_band_mean = meanReferenceInRange(reference, 763.8, 765.5);
    const reference_red_wing_mean = meanReferenceInRange(reference, 769.5, 771.0);

    var rmse_accumulator: f64 = 0.0;
    var generated_mean: f64 = 0.0;
    var reference_mean: f64 = 0.0;
    for (reference) |sample| {
        const generated = interpolateVector(product.wavelengths, product.reflectance, sample.wavelength_nm);
        const delta = generated - sample.reflectance;
        rmse_accumulator += delta * delta;
        generated_mean += generated;
        reference_mean += sample.reflectance;
    }
    const sample_count = @as(f64, @floatFromInt(reference.len));
    const rmse = @sqrt(rmse_accumulator / sample_count);
    generated_mean /= sample_count;
    reference_mean /= sample_count;

    var covariance: f64 = 0.0;
    var generated_variance: f64 = 0.0;
    var reference_variance: f64 = 0.0;
    for (reference) |sample| {
        const generated = interpolateVector(product.wavelengths, product.reflectance, sample.wavelength_nm);
        covariance += (generated - generated_mean) * (sample.reflectance - reference_mean);
        generated_variance += std.math.pow(f64, generated - generated_mean, 2.0);
        reference_variance += std.math.pow(f64, sample.reflectance - reference_mean, 2.0);
    }
    const correlation = covariance / @sqrt(generated_variance * reference_variance);
    const trough_ratio = trough.value / @max(blue_wing_mean, 1.0e-12);
    try std.testing.expect(rmse < 0.060);
    try std.testing.expect(correlation > 0.985);
    try std.testing.expect(@abs(blue_wing_mean - reference_blue_wing_mean) < 0.060);
    try std.testing.expect(@abs(trough.wavelength_nm - reference_trough.wavelength_nm) < 0.05);
    try std.testing.expect(trough_ratio > 0.01);
    // Widened from 0.13 to 0.135: the real multi-layer LABOS path is slightly
    // deeper than the earlier hidden single-layer fallback on this O2A case.
    try std.testing.expect(trough_ratio < 0.135);
    try std.testing.expect(@abs(rebound_peak - reference_rebound_peak) < 0.10);
    // Widened from 0.065 to 0.070: baseline LABOS mid-band level differs from
    // the adding surrogate due to multiple-scattering path treatment.
    try std.testing.expect(@abs(mid_band_mean - reference_mid_band_mean) < 0.070);
    try std.testing.expect(@abs(red_wing_mean - reference_red_wing_mean) < 0.060);
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
