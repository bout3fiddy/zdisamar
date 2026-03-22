const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");

const ReferenceData = internal.reference_data;
const OpticsPrepare = internal.kernels.optics.prepare;
const MeasurementSpace = internal.kernels.transport.measurement_space;
const AbsorberSpecies = @typeInfo(@TypeOf(@as(zdisamar.Absorber, .{}).resolved_species)).optional.child;

const SimulatedCase = struct {
    prepared: OpticsPrepare.PreparedOpticalState,
    product: MeasurementSpace.MeasurementSpaceProduct,

    fn deinit(self: *SimulatedCase, allocator: std.mem.Allocator) void {
        self.product.deinit(allocator);
        self.prepared.deinit(allocator);
        self.* = undefined;
    }
};

fn buildSyntheticProfile(allocator: std.mem.Allocator) !ReferenceData.ClimatologyProfile {
    return .{
        .rows = try allocator.dupe(ReferenceData.ClimatologyPoint, &.{
            .{ .altitude_km = 0.0, .pressure_hpa = 1000.0, .temperature_k = 290.0, .air_number_density_cm3 = 2.0e19 },
            .{ .altitude_km = 4.0, .pressure_hpa = 820.0, .temperature_k = 275.0, .air_number_density_cm3 = 1.7e19 },
            .{ .altitude_km = 8.0, .pressure_hpa = 620.0, .temperature_k = 255.0, .air_number_density_cm3 = 1.3e19 },
            .{ .altitude_km = 12.0, .pressure_hpa = 430.0, .temperature_k = 235.0, .air_number_density_cm3 = 9.0e18 },
        }),
    };
}

fn buildZeroContinuumTable(
    allocator: std.mem.Allocator,
    start_nm: f64,
    end_nm: f64,
) !ReferenceData.CrossSectionTable {
    const midpoint_nm = (start_nm + end_nm) * 0.5;
    return .{
        .points = try allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = start_nm, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = midpoint_nm, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = end_nm, .sigma_cm2_per_molecule = 0.0 },
        }),
    };
}

fn buildCo2LineList(allocator: std.mem.Allocator) !ReferenceData.SpectroscopyLineList {
    return .{
        .lines = try allocator.dupe(ReferenceData.SpectroscopyLine, &.{
            .{
                .gas_index = 2,
                .isotope_number = 1,
                .center_wavelength_nm = 1600.14,
                .line_strength_cm2_per_molecule = 2.5e-16,
                .air_half_width_nm = 0.001,
                .temperature_exponent = 0.72,
                .lower_state_energy_cm1 = 90.0,
                .pressure_shift_nm = 0.0,
                .line_mixing_coefficient = 0.0,
            },
            .{
                .gas_index = 2,
                .isotope_number = 1,
                .center_wavelength_nm = 1600.22,
                .line_strength_cm2_per_molecule = 1.2e-16,
                .air_half_width_nm = 0.001,
                .temperature_exponent = 0.70,
                .lower_state_energy_cm1 = 120.0,
                .pressure_shift_nm = 0.0,
                .line_mixing_coefficient = 0.0,
            },
        }),
    };
}

fn minValueInRange(
    wavelengths_nm: []const f64,
    values: []const f64,
    start_nm: f64,
    end_nm: f64,
) f64 {
    var best = std.math.inf(f64);
    for (wavelengths_nm, values) |wavelength_nm, value| {
        if (wavelength_nm < start_nm or wavelength_nm > end_nm) continue;
        if (value < best) best = value;
    }
    return best;
}

fn meanAbsoluteDifference(left: []const f64, right: []const f64) f64 {
    const count = @min(left.len, right.len);
    if (count == 0) return 0.0;

    var sum: f64 = 0.0;
    for (left[0..count], right[0..count]) |lhs, rhs| {
        sum += @abs(lhs - rhs);
    }
    return sum / @as(f64, @floatFromInt(count));
}

fn simulateCo2LineGasCase(
    allocator: std.mem.Allocator,
    volume_mixing_ratio_profile_ppmv: []const [2]f64,
) !SimulatedCase {
    var profile = try buildSyntheticProfile(allocator);
    defer profile.deinit(allocator);
    var cross_sections = try buildZeroContinuumTable(allocator, 1600.0, 1600.35);
    defer cross_sections.deinit(allocator);
    var line_list = try buildCo2LineList(allocator);
    defer line_list.deinit(allocator);
    var lut = try ReferenceData.buildDemoAirmassFactorLut(allocator);
    defer lut.deinit(allocator);

    const scene: zdisamar.Scene = .{
        .id = "validation-co2-line-gas",
        .surface = .{
            .albedo = 0.28,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 35.0,
            .viewing_zenith_deg = 15.0,
            .relative_azimuth_deg = 40.0,
        },
        .atmosphere = .{
            .layer_count = 3,
            .sublayer_divisions = 2,
        },
        .spectral_grid = .{
            .start_nm = 1600.0,
            .end_nm = 1600.35,
            .sample_count = 61,
        },
        .absorbers = .{
            .items = &.{
                zdisamar.Absorber{
                    .id = "co2",
                    .species = "co2",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "co2").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = volume_mixing_ratio_profile_ppmv,
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .active_stage = .simulation,
                        },
                    },
                },
            },
        },
        .observation_model = .{
            .instrument = .{ .custom = "validation-co2-line-gas" },
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .none,
            .instrument_line_fwhm_nm = 0.08,
            .builtin_line_shape = .gaussian,
            .high_resolution_step_nm = 0.002,
            .high_resolution_half_span_nm = 0.08,
        },
    };

    var prepared = try OpticsPrepare.prepareWithSpectroscopy(
        allocator,
        &scene,
        &profile,
        &cross_sections,
        &line_list,
        &lut,
    );
    errdefer prepared.deinit(allocator);

    var engine = zdisamar.Engine.init(allocator, .{});
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
            .n_streams = 4,
            .num_orders_max = 4,
        },
    });
    defer plan.deinit();

    var product = try MeasurementSpace.simulateProduct(
        allocator,
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
    errdefer product.deinit(allocator);

    return .{
        .prepared = prepared,
        .product = product,
    };
}

fn buildVendorAnchoredH2ONH3LineList(allocator: std.mem.Allocator) !ReferenceData.SpectroscopyLineList {
    return .{
        .lines = try allocator.dupe(ReferenceData.SpectroscopyLine, &.{
            .{ .gas_index = 11, .isotope_number = 1, .center_wavelength_nm = 2349.82, .line_strength_cm2_per_molecule = 5.5e-15, .air_half_width_nm = 0.0010, .temperature_exponent = 0.72, .lower_state_energy_cm1 = 110.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
            .{ .gas_index = 11, .isotope_number = 3, .center_wavelength_nm = 2349.98, .line_strength_cm2_per_molecule = 4.8e-15, .air_half_width_nm = 0.0010, .temperature_exponent = 0.72, .lower_state_energy_cm1 = 118.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
            .{ .gas_index = 1, .isotope_number = 1, .center_wavelength_nm = 2347.18, .line_strength_cm2_per_molecule = 1.8e-15, .air_half_width_nm = 0.0011, .temperature_exponent = 0.69, .lower_state_energy_cm1 = 95.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
            .{ .gas_index = 1, .isotope_number = 7, .center_wavelength_nm = 2347.34, .line_strength_cm2_per_molecule = 1.4e-15, .air_half_width_nm = 0.0011, .temperature_exponent = 0.69, .lower_state_energy_cm1 = 102.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
            .{ .gas_index = 6, .isotope_number = 1, .center_wavelength_nm = 2352.36, .line_strength_cm2_per_molecule = 9.0e-16, .air_half_width_nm = 0.0012, .temperature_exponent = 0.68, .lower_state_energy_cm1 = 130.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
            .{ .gas_index = 6, .isotope_number = 4, .center_wavelength_nm = 2352.58, .line_strength_cm2_per_molecule = 8.5e-16, .air_half_width_nm = 0.0012, .temperature_exponent = 0.68, .lower_state_energy_cm1 = 138.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
            .{ .gas_index = 5, .isotope_number = 1, .center_wavelength_nm = 2342.42, .line_strength_cm2_per_molecule = 6.5e-16, .air_half_width_nm = 0.0010, .temperature_exponent = 0.70, .lower_state_energy_cm1 = 90.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
            .{ .gas_index = 5, .isotope_number = 7, .center_wavelength_nm = 2342.68, .line_strength_cm2_per_molecule = 5.8e-16, .air_half_width_nm = 0.0010, .temperature_exponent = 0.70, .lower_state_energy_cm1 = 98.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
        }),
    };
}

fn simulateVendorAnchoredH2ONH3Case(
    allocator: std.mem.Allocator,
    nh3_scale: f64,
    adaptive_enabled: bool,
) !SimulatedCase {
    var profile = try buildSyntheticProfile(allocator);
    defer profile.deinit(allocator);
    var cross_sections = try buildZeroContinuumTable(allocator, 2340.0, 2360.0);
    defer cross_sections.deinit(allocator);
    var line_list = try buildVendorAnchoredH2ONH3LineList(allocator);
    defer line_list.deinit(allocator);
    var lut = try ReferenceData.buildDemoAirmassFactorLut(allocator);
    defer lut.deinit(allocator);

    const scene: zdisamar.Scene = .{
        .id = "validation-vendor-anchored-h2o-nh3",
        .surface = .{
            .albedo = 0.18,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 35.0,
            .viewing_zenith_deg = 15.0,
            .relative_azimuth_deg = 40.0,
        },
        .atmosphere = .{
            .layer_count = 3,
            .sublayer_divisions = 2,
        },
        .spectral_grid = .{
            .start_nm = 2340.0,
            .end_nm = 2360.0,
            .sample_count = 81,
        },
        .absorbers = .{
            .items = &.{
                zdisamar.Absorber{
                    .id = "nh3",
                    .species = "nh3",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "nh3").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = &.{
                        .{ 1000.0, 12.0 * nh3_scale },
                        .{ 430.0, 3.0 * nh3_scale },
                    },
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .isotopes_sim = &.{ 1, 2 },
                            .threshold_line_sim = 3.0e-5,
                            .cutoff_sim_cm1 = 10.0,
                            .active_stage = .simulation,
                        },
                    },
                },
                zdisamar.Absorber{
                    .id = "h2o",
                    .species = "h2o",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "h2o").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = &.{
                        .{ 1000.0, 12000.0 },
                        .{ 430.0, 3500.0 },
                    },
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .isotopes_sim = &.{ 1, 2, 3, 4, 5, 6 },
                            .threshold_line_sim = 3.0e-5,
                            .cutoff_sim_cm1 = 10.0,
                            .active_stage = .simulation,
                        },
                    },
                },
                zdisamar.Absorber{
                    .id = "ch4",
                    .species = "ch4",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "ch4").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = &.{
                        .{ 1000.0, 1800.0 },
                        .{ 430.0, 950.0 },
                    },
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .isotopes_sim = &.{ 1, 2, 3 },
                            .threshold_line_sim = 3.0e-5,
                            .cutoff_sim_cm1 = 10.0,
                            .active_stage = .simulation,
                        },
                    },
                },
                zdisamar.Absorber{
                    .id = "co",
                    .species = "co",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "co").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = &.{
                        .{ 1000.0, 120.0 },
                        .{ 430.0, 65.0 },
                    },
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .isotopes_sim = &.{ 1, 2, 3, 4, 5, 6 },
                            .threshold_line_sim = 3.0e-5,
                            .cutoff_sim_cm1 = 10.0,
                            .active_stage = .simulation,
                        },
                    },
                },
            },
        },
        .observation_model = .{
            .instrument = .{ .custom = "validation-vendor-anchored-h2o-nh3" },
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .none,
            .instrument_line_fwhm_nm = 0.25,
            .builtin_line_shape = .flat_top_n4,
            .high_resolution_step_nm = 0.020833333333333332,
            .high_resolution_half_span_nm = 0.75,
            .adaptive_reference_grid = if (adaptive_enabled)
                .{
                    .points_per_fwhm = 12,
                    .strong_line_min_divisions = 4,
                    .strong_line_max_divisions = 16,
                }
            else
                .{},
        },
    };

    var prepared = try OpticsPrepare.prepareWithSpectroscopy(
        allocator,
        &scene,
        &profile,
        &cross_sections,
        &line_list,
        &lut,
    );
    errdefer prepared.deinit(allocator);

    var engine = zdisamar.Engine.init(allocator, .{});
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
            .n_streams = 8,
            .num_orders_max = 4,
        },
    });
    defer plan.deinit();

    var product = try MeasurementSpace.simulateProduct(
        allocator,
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
    errdefer product.deinit(allocator);

    return .{
        .prepared = prepared,
        .product = product,
    };
}

test "validation non-o2 staged line-gas profiles change prepared optics and downstream spectra" {
    var low_case = try simulateCo2LineGasCase(std.testing.allocator, &.{
        .{ 1000.0, 400.0 },
        .{ 430.0, 200.0 },
    });
    defer low_case.deinit(std.testing.allocator);
    var high_case = try simulateCo2LineGasCase(std.testing.allocator, &.{
        .{ 1000.0, 4000.0 },
        .{ 430.0, 2000.0 },
    });
    defer high_case.deinit(std.testing.allocator);

    try std.testing.expect(high_case.prepared.air_column_density_factor > high_case.prepared.column_density_factor);
    try std.testing.expect(high_case.prepared.column_density_factor < high_case.prepared.air_column_density_factor * 1.0e-2);
    try std.testing.expect(high_case.prepared.sublayers.?[0].absorber_number_density_cm3 < high_case.prepared.sublayers.?[0].oxygen_number_density_cm3);
    try std.testing.expect(high_case.prepared.totalOpticalDepthAtWavelength(1600.14) > low_case.prepared.totalOpticalDepthAtWavelength(1600.14));

    const low_trough = minValueInRange(
        low_case.product.wavelengths,
        low_case.product.reflectance,
        1600.10,
        1600.24,
    );
    const high_trough = minValueInRange(
        high_case.product.wavelengths,
        high_case.product.reflectance,
        1600.10,
        1600.24,
    );
    try std.testing.expect(high_trough < low_trough);
}

test "validation vendor-anchored h2o_nh3 swir line-gas family combines nh3 h2o ch4 and co contributions" {
    var adaptive_case = try simulateVendorAnchoredH2ONH3Case(std.testing.allocator, 1.0, true);
    defer adaptive_case.deinit(std.testing.allocator);
    var no_nh3_case = try simulateVendorAnchoredH2ONH3Case(std.testing.allocator, 0.0, true);
    defer no_nh3_case.deinit(std.testing.allocator);
    var coarse_case = try simulateVendorAnchoredH2ONH3Case(std.testing.allocator, 1.0, false);
    defer coarse_case.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), adaptive_case.prepared.line_absorbers.len);
    try std.testing.expect(adaptive_case.prepared.spectroscopy_lines == null);
    try std.testing.expectEqual(@as(usize, 1), adaptive_case.prepared.line_absorbers[0].line_list.lines.len);
    try std.testing.expectEqual(@as(usize, 1), adaptive_case.prepared.line_absorbers[1].line_list.lines.len);
    try std.testing.expectEqual(@as(usize, 1), adaptive_case.prepared.line_absorbers[2].line_list.lines.len);
    try std.testing.expectEqual(@as(usize, 1), adaptive_case.prepared.line_absorbers[3].line_list.lines.len);

    const nh3_tau_delta =
        adaptive_case.prepared.totalOpticalDepthAtWavelength(2349.82) -
        no_nh3_case.prepared.totalOpticalDepthAtWavelength(2349.82);
    const h2o_tau_delta = @abs(
        adaptive_case.prepared.totalOpticalDepthAtWavelength(2347.18) -
            no_nh3_case.prepared.totalOpticalDepthAtWavelength(2347.18),
    );
    const ch4_tau_delta = @abs(
        adaptive_case.prepared.totalOpticalDepthAtWavelength(2352.36) -
            no_nh3_case.prepared.totalOpticalDepthAtWavelength(2352.36),
    );
    const co_tau = adaptive_case.prepared.totalOpticalDepthAtWavelength(2342.42);
    const h2o_tau = adaptive_case.prepared.totalOpticalDepthAtWavelength(2347.18);
    const ch4_tau = adaptive_case.prepared.totalOpticalDepthAtWavelength(2352.36);

    try std.testing.expect(nh3_tau_delta > 0.0);
    try std.testing.expect(nh3_tau_delta > h2o_tau_delta * 10.0);
    try std.testing.expect(nh3_tau_delta > ch4_tau_delta * 10.0);
    try std.testing.expect(co_tau > 0.0);
    try std.testing.expect(h2o_tau > 0.0);
    try std.testing.expect(ch4_tau > 0.0);

    const adaptive_delta = meanAbsoluteDifference(
        adaptive_case.product.reflectance,
        coarse_case.product.reflectance,
    );
    const adaptive_nh3_trough = minValueInRange(
        adaptive_case.product.wavelengths,
        adaptive_case.product.reflectance,
        2349.60,
        2350.05,
    );
    const no_nh3_trough = minValueInRange(
        no_nh3_case.product.wavelengths,
        no_nh3_case.product.reflectance,
        2349.60,
        2350.05,
    );

    try std.testing.expect(adaptive_delta > 1.0e-6);
    try std.testing.expect(adaptive_nh3_trough < no_nh3_trough);
}
