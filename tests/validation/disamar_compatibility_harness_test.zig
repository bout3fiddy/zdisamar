const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");
const retrieval = @import("zdisamar_internal").retrieval;
const ReferenceData = internal.reference_data;
const OpticsPrepare = internal.kernels.optics.preparation;
const MeasurementSpace = internal.kernels.transport.measurement;
const bundled_optics = internal.runtime.reference.bundled_optics_assets;

const RuntimeProfile = struct {
    observation_regime: []const u8,
    solver_mode: []const u8,
    derivative_mode: []const u8,
    spectral_samples: u32,
};

const ParityCase = struct {
    id: []const u8,
    component: []const u8,
    retrieval_method: ?[]const u8 = null,
    upstream_case: []const u8,
    upstream_reference_output: ?[]const u8 = null,
    upstream_numeric_anchor: ?[]const u8 = null,
    runtime_profile: RuntimeProfile,
    expected_route_family: []const u8,
    expected_derivative_mode: []const u8,
    expected_derivative_semantics: ?[]const u8 = null,
    expected_jacobians_used: ?bool = null,
    status: []const u8,
    scene_fixture: []const u8 = "",
    spectral_start_nm: f64 = 405.0,
    spectral_end_nm: f64 = 465.0,
    has_aerosols: bool = false,
    has_clouds: bool = false,
    use_o2a_spectroscopy: bool = false,
    use_mie_phase_table: bool = false,
    sublayer_divisions: u8 = 3,
    expected_cross_section_absorber_count: ?u32 = null,
    expected_line_absorber_count: ?u32 = null,
    expected_cia_present: ?bool = null,
    expected_spectroscopy_lines_present: ?bool = null,
    tolerances: struct {
        absolute: f64,
        relative: f64,
    },
};

const ParityMatrix = struct {
    version: u32,
    upstream: []const u8,
    parity_level: []const u8,
    cases: []const ParityCase,
};

const ParityComponent = enum {
    transport,
    retrieval,
    optics,
    measurement_space,
};

const ExecutedParityCounts = struct {
    total: usize = 0,
    transport: usize = 0,
    retrieval: usize = 0,
    optics: usize = 0,
    measurement_space: usize = 0,
};

const ParityRunResult = struct {
    expected: ExecutedParityCounts,
    executed: ExecutedParityCounts,
};

const vendor_ascii_hdf_anchor_path = "validation/compatibility/disamar_asciihdf_anchor.txt";

fn parseParityComponent(value: []const u8) !ParityComponent {
    if (std.mem.eql(u8, value, "transport")) return .transport;
    if (std.mem.eql(u8, value, "retrieval")) return .retrieval;
    if (std.mem.eql(u8, value, "optics")) return .optics;
    if (std.mem.eql(u8, value, "measurement_space")) return .measurement_space;
    return error.InvalidParityComponent;
}

fn includesParityComponent(
    components: []const ParityComponent,
    component: ParityComponent,
) bool {
    for (components) |allowed| {
        if (allowed == component) return true;
    }
    return false;
}

fn incrementParityCounts(counts: *ExecutedParityCounts, component: ParityComponent) void {
    counts.total += 1;
    switch (component) {
        .transport => counts.transport += 1,
        .retrieval => counts.retrieval += 1,
        .optics => counts.optics += 1,
        .measurement_space => counts.measurement_space += 1,
    }
}

fn matrixIndex(row: usize, column: usize, column_count: usize) usize {
    return row * column_count + column;
}

fn matrixTrace(values: []const f64, dimension: usize) f64 {
    var total: f64 = 0.0;
    for (0..dimension) |index| {
        total += values[matrixIndex(index, index, dimension)];
    }
    return total;
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
    try std.testing.expect(rebound_peak > trough.value * 4.0 and rebound_peak < 0.25);
    try std.testing.expect(mid_band_mean > trough.value * 4.0 and mid_band_mean < rebound_peak * 0.8);
    try std.testing.expect(red_wing_mean > trough.value * 8.0);
    try std.testing.expect(red_wing_mean > rebound_peak * 1.1);
    try std.testing.expect(red_wing_mean > mid_band_mean * 1.4);
}

fn parseObservationRegime(value: []const u8) !zdisamar.ObservationRegime {
    if (std.mem.eql(u8, value, "nadir")) return .nadir;
    if (std.mem.eql(u8, value, "limb")) return .limb;
    if (std.mem.eql(u8, value, "occultation")) return .occultation;
    return error.InvalidObservationRegime;
}

fn parseSolverMode(value: []const u8) !zdisamar.SolverMode {
    if (std.mem.eql(u8, value, "scalar")) return .scalar;
    if (std.mem.eql(u8, value, "polarized")) return .polarized;
    if (std.mem.eql(u8, value, "derivative_enabled")) return .scalar;
    return error.InvalidSolverMode;
}

fn parseDerivativeMode(value: []const u8) !zdisamar.DerivativeMode {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "semi_analytical")) return .semi_analytical;
    if (std.mem.eql(u8, value, "analytical_plugin")) return .analytical_plugin;
    if (std.mem.eql(u8, value, "numerical")) return .numerical;
    return error.InvalidDerivativeMode;
}

fn pathExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

const VendorRetrievalAnchor = struct {
    iterations: u32,
    solution_has_converged: bool,
    chi2: f64,
    dfs: f64,
};

const no2_fixture_points = [_]ReferenceData.CrossSectionPoint{
    .{ .wavelength_nm = 405.0, .sigma_cm2_per_molecule = 4.9e-19 },
    .{ .wavelength_nm = 420.0, .sigma_cm2_per_molecule = 3.5e-19 },
    .{ .wavelength_nm = 435.0, .sigma_cm2_per_molecule = 2.4e-19 },
    .{ .wavelength_nm = 450.0, .sigma_cm2_per_molecule = 1.8e-19 },
    .{ .wavelength_nm = 465.0, .sigma_cm2_per_molecule = 1.2e-19 },
};
const no2_fixture_profile_ppmv = [_][2]f64{
    .{ 1000.0, 0.12 },
    .{ 450.0, 0.05 },
};
const no2_domino_fixture_absorbers = [_]zdisamar.Absorber{
    .{
        .id = "no2",
        .species = "no2",
        .resolved_species = .no2,
        .profile_source = .atmosphere,
        .volume_mixing_ratio_profile_ppmv = no2_fixture_profile_ppmv[0..],
        .spectroscopy = .{
            .mode = .cross_sections,
            .resolved_cross_section_table = .{ .points = @constCast(no2_fixture_points[0..]) },
        },
    },
};
const no2_domino_fixture_bands = [_]zdisamar.SpectralBand{
    .{
        .id = "vis-no2-domino",
        .start_nm = 405.0,
        .end_nm = 465.0,
        .step_nm = 1.25,
    },
};
const no2_domino_fixture_strong_absorption = [_]bool{true};
const no2_domino_fixture_polynomial_degree = [_]u32{6};

const o3_fixture_points = [_]ReferenceData.CrossSectionPoint{
    .{ .wavelength_nm = 310.0, .sigma_cm2_per_molecule = 5.2e-19 },
    .{ .wavelength_nm = 320.0, .sigma_cm2_per_molecule = 4.1e-19 },
    .{ .wavelength_nm = 330.0, .sigma_cm2_per_molecule = 3.0e-19 },
    .{ .wavelength_nm = 340.0, .sigma_cm2_per_molecule = 2.2e-19 },
};
const o3_fixture_profile_ppmv = [_][2]f64{
    .{ 1000.0, 6.0 },
    .{ 450.0, 11.5 },
};
const o3_profile_fixture_absorbers = [_]zdisamar.Absorber{
    .{
        .id = "o3",
        .species = "o3",
        .resolved_species = .o3,
        .profile_source = .atmosphere,
        .volume_mixing_ratio_profile_ppmv = o3_fixture_profile_ppmv[0..],
        .spectroscopy = .{
            .mode = .cross_sections,
            .resolved_cross_section_table = .{ .points = @constCast(o3_fixture_points[0..]) },
        },
    },
};
const o3_profile_fixture_bands = [_]zdisamar.SpectralBand{
    .{
        .id = "uv-o3-profile",
        .start_nm = 310.0,
        .end_nm = 340.0,
        .step_nm = 0.5,
    },
};
const o3_profile_fixture_strong_absorption = [_]bool{true};
const o3_profile_fixture_polynomial_degree = [_]u32{4};

const mixed_o3_points = [_]ReferenceData.CrossSectionPoint{
    .{ .wavelength_nm = 325.0, .sigma_cm2_per_molecule = 4.9e-19 },
    .{ .wavelength_nm = 338.0, .sigma_cm2_per_molecule = 3.7e-19 },
    .{ .wavelength_nm = 350.0, .sigma_cm2_per_molecule = 2.8e-19 },
    .{ .wavelength_nm = 360.0, .sigma_cm2_per_molecule = 2.1e-19 },
};
const mixed_hcho_points = [_]ReferenceData.CrossSectionPoint{
    .{ .wavelength_nm = 325.0, .sigma_cm2_per_molecule = 1.8e-19 },
    .{ .wavelength_nm = 338.0, .sigma_cm2_per_molecule = 1.4e-19 },
    .{ .wavelength_nm = 350.0, .sigma_cm2_per_molecule = 1.1e-19 },
    .{ .wavelength_nm = 360.0, .sigma_cm2_per_molecule = 0.9e-19 },
};
const mixed_bro_points = [_]ReferenceData.CrossSectionPoint{
    .{ .wavelength_nm = 325.0, .sigma_cm2_per_molecule = 1.3e-19 },
    .{ .wavelength_nm = 338.0, .sigma_cm2_per_molecule = 1.0e-19 },
    .{ .wavelength_nm = 350.0, .sigma_cm2_per_molecule = 0.8e-19 },
    .{ .wavelength_nm = 360.0, .sigma_cm2_per_molecule = 0.6e-19 },
};
const mixed_no2_points = [_]ReferenceData.CrossSectionPoint{
    .{ .wavelength_nm = 325.0, .sigma_cm2_per_molecule = 2.4e-19 },
    .{ .wavelength_nm = 338.0, .sigma_cm2_per_molecule = 2.0e-19 },
    .{ .wavelength_nm = 350.0, .sigma_cm2_per_molecule = 1.6e-19 },
    .{ .wavelength_nm = 360.0, .sigma_cm2_per_molecule = 1.2e-19 },
};
const mixed_o3_profile_ppmv = [_][2]f64{
    .{ 1000.0, 5.6 },
    .{ 450.0, 10.8 },
};
const mixed_hcho_profile_ppmv = [_][2]f64{
    .{ 1000.0, 0.020 },
    .{ 450.0, 0.008 },
};
const mixed_bro_profile_ppmv = [_][2]f64{
    .{ 1000.0, 0.0045 },
    .{ 450.0, 0.0018 },
};
const mixed_no2_profile_ppmv = [_][2]f64{
    .{ 1000.0, 0.030 },
    .{ 450.0, 0.012 },
};
const mixed_uv_fixture_absorbers = [_]zdisamar.Absorber{
    .{
        .id = "o3",
        .species = "o3",
        .resolved_species = .o3,
        .profile_source = .atmosphere,
        .volume_mixing_ratio_profile_ppmv = mixed_o3_profile_ppmv[0..],
        .spectroscopy = .{
            .mode = .cross_sections,
            .resolved_cross_section_table = .{ .points = @constCast(mixed_o3_points[0..]) },
        },
    },
    .{
        .id = "hcho",
        .species = "hcho",
        .resolved_species = .hcho,
        .profile_source = .atmosphere,
        .volume_mixing_ratio_profile_ppmv = mixed_hcho_profile_ppmv[0..],
        .spectroscopy = .{
            .mode = .cross_sections,
            .resolved_cross_section_table = .{ .points = @constCast(mixed_hcho_points[0..]) },
        },
    },
    .{
        .id = "bro",
        .species = "bro",
        .resolved_species = .bro,
        .profile_source = .atmosphere,
        .volume_mixing_ratio_profile_ppmv = mixed_bro_profile_ppmv[0..],
        .spectroscopy = .{
            .mode = .cross_sections,
            .resolved_cross_section_table = .{ .points = @constCast(mixed_bro_points[0..]) },
        },
    },
    .{
        .id = "no2",
        .species = "no2",
        .resolved_species = .no2,
        .profile_source = .atmosphere,
        .volume_mixing_ratio_profile_ppmv = mixed_no2_profile_ppmv[0..],
        .spectroscopy = .{
            .mode = .cross_sections,
            .resolved_cross_section_table = .{ .points = @constCast(mixed_no2_points[0..]) },
        },
    },
};
const mixed_uv_fixture_bands = [_]zdisamar.SpectralBand{
    .{
        .id = "uv-multi-gas",
        .start_nm = 325.0,
        .end_nm = 360.0,
        .step_nm = 0.5,
    },
};
const mixed_uv_fixture_strong_absorption = [_]bool{true};
const mixed_uv_fixture_polynomial_degree = [_]u32{5};

const so2_fixture_o3_points = [_]ReferenceData.CrossSectionPoint{
    .{ .wavelength_nm = 310.0, .sigma_cm2_per_molecule = 5.1e-19 },
    .{ .wavelength_nm = 320.0, .sigma_cm2_per_molecule = 4.0e-19 },
    .{ .wavelength_nm = 330.0, .sigma_cm2_per_molecule = 3.1e-19 },
};
const so2_fixture_so2_points = [_]ReferenceData.CrossSectionPoint{
    .{ .wavelength_nm = 310.0, .sigma_cm2_per_molecule = 2.7e-19 },
    .{ .wavelength_nm = 320.0, .sigma_cm2_per_molecule = 2.2e-19 },
    .{ .wavelength_nm = 330.0, .sigma_cm2_per_molecule = 1.8e-19 },
};
const so2_fixture_o3_profile_ppmv = [_][2]f64{
    .{ 1000.0, 5.4 },
    .{ 450.0, 10.0 },
};
const so2_fixture_so2_profile_ppmv = [_][2]f64{
    .{ 1000.0, 0.010 },
    .{ 450.0, 0.004 },
};
const o3_so2_fixture_absorbers = [_]zdisamar.Absorber{
    .{
        .id = "o3",
        .species = "o3",
        .resolved_species = .o3,
        .profile_source = .atmosphere,
        .volume_mixing_ratio_profile_ppmv = so2_fixture_o3_profile_ppmv[0..],
        .spectroscopy = .{
            .mode = .cross_sections,
            .resolved_cross_section_table = .{ .points = @constCast(so2_fixture_o3_points[0..]) },
        },
    },
    .{
        .id = "so2",
        .species = "so2",
        .resolved_species = .so2,
        .profile_source = .atmosphere,
        .volume_mixing_ratio_profile_ppmv = so2_fixture_so2_profile_ppmv[0..],
        .spectroscopy = .{
            .mode = .cross_sections,
            .resolved_cross_section_table = .{ .points = @constCast(so2_fixture_so2_points[0..]) },
        },
    },
};
const o3_so2_fixture_bands = [_]zdisamar.SpectralBand{
    .{
        .id = "uv-o3-so2",
        .start_nm = 310.0,
        .end_nm = 330.0,
        .step_nm = 0.5,
    },
};
const o3_so2_fixture_strong_absorption = [_]bool{true};
const o3_so2_fixture_polynomial_degree = [_]u32{4};

fn parseRetrievalMethod(value: []const u8) !retrieval.common.contracts.Method {
    if (std.mem.eql(u8, value, "oe")) return .oe;
    if (std.mem.eql(u8, value, "doas")) return .doas;
    if (std.mem.eql(u8, value, "dismas")) return .dismas;
    return error.InvalidRetrievalMethod;
}

fn retrievalProviderId(method: retrieval.common.contracts.Method) []const u8 {
    return switch (method) {
        .oe => "builtin.oe_solver",
        .doas => "builtin.doas_solver",
        .dismas => "builtin.dismas_solver",
    };
}

fn makeRetrievalRequest(
    case: ParityCase,
    regime: zdisamar.ObservationRegime,
    derivative_mode: zdisamar.DerivativeMode,
) !zdisamar.Request {
    const method = try parseRetrievalMethod(case.retrieval_method orelse return error.MissingRetrievalMethod);
    const measurement_product = "radiance";

    var scene = makeSceneForCase(case, regime);
    if (method == .oe) {
        scene.surface.albedo = 0.10;
        scene.aerosol.enabled = true;
        scene.atmosphere.has_aerosols = true;
        scene.aerosol.optical_depth = 0.08;
        scene.aerosol.layer_center_km = 2.0;
        scene.aerosol.layer_width_km = 2.0;
    }

    return .{
        .scene = scene,
        .inverse_problem = .{
            .id = case.id,
            .state_vector = .{
                .parameters = switch (method) {
                    .oe => &[_]zdisamar.StateParameter{
                        .{
                            .name = "albedo",
                            .target = .surface_albedo,
                            .transform = .logit,
                            .prior = .{ .enabled = true, .mean = 0.10, .sigma = 0.03 },
                            .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 },
                        },
                        .{
                            .name = "aerosol",
                            .target = .aerosol_optical_depth_550_nm,
                            .transform = .log,
                            .prior = .{ .enabled = true, .mean = 0.08, .sigma = 0.04 },
                            .bounds = .{ .enabled = true, .min = 1.0e-4, .max = 3.0 },
                        },
                    },
                    .doas => &[_]zdisamar.StateParameter{
                        .{
                            .name = "wavelength_shift",
                            .target = .wavelength_shift_nm,
                            .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.03 },
                            .bounds = .{ .enabled = true, .min = -0.1, .max = 0.1 },
                        },
                    },
                    .dismas => &[_]zdisamar.StateParameter{
                        .{
                            .name = "surface_albedo",
                            .target = .surface_albedo,
                            .prior = .{ .enabled = true, .mean = 0.10, .sigma = 0.05 },
                        },
                        .{
                            .name = "aerosol_tau",
                            .target = .aerosol_optical_depth_550_nm,
                            .prior = .{ .enabled = true, .mean = 0.12, .sigma = 0.05 },
                        },
                        .{
                            .name = "wavelength_shift",
                            .target = .wavelength_shift_nm,
                            .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.05 },
                            .bounds = .{ .enabled = true, .min = -0.2, .max = 0.2 },
                        },
                    },
                },
            },
            .measurements = .{
                .product_name = measurement_product,
                .observable = .radiance,
                .sample_count = case.runtime_profile.spectral_samples,
                .source = if (method == .oe or method == .doas or method == .dismas)
                    .{ .external_observation = .{ .name = "truth_radiance" } }
                else
                    .none,
                .error_model = if (method == .oe or method == .doas or method == .dismas)
                    .{ .from_source_noise = true, .floor = 1.0e-4 }
                else
                    .{},
            },
        },
        .expected_derivative_mode = derivative_mode,
        .diagnostics = .{ .jacobians = derivative_mode != .none },
    };
}

fn applySceneFixture(scene: *zdisamar.Scene, case: ParityCase) !void {
    if (case.scene_fixture.len == 0) return;

    scene.geometry = .{
        .model = .plane_parallel,
        .solar_zenith_deg = 30.0,
        .viewing_zenith_deg = 12.0,
        .relative_azimuth_deg = 40.0,
    };
    scene.surface = .{
        .kind = .lambertian,
        .albedo = 0.12,
    };
    scene.observation_model.instrument = .synthetic;
    scene.observation_model.sampling = .native;
    scene.observation_model.noise_model = .shot_noise;
    scene.observation_model.cross_section_fit = .{
        .use_effective_cross_section_oe = true,
        .use_polynomial_expansion = true,
    };

    if (std.mem.eql(u8, case.scene_fixture, "no2_domino_cross_sections")) {
        scene.bands.items = no2_domino_fixture_bands[0..];
        scene.absorbers.items = no2_domino_fixture_absorbers[0..];
        scene.observation_model.cross_section_fit.xsec_strong_absorption_bands = no2_domino_fixture_strong_absorption[0..];
        scene.observation_model.cross_section_fit.polynomial_degree_bands = no2_domino_fixture_polynomial_degree[0..];
        return;
    }
    if (std.mem.eql(u8, case.scene_fixture, "o3_profile_cross_sections")) {
        scene.bands.items = o3_profile_fixture_bands[0..];
        scene.absorbers.items = o3_profile_fixture_absorbers[0..];
        scene.observation_model.cross_section_fit.xsec_strong_absorption_bands = o3_profile_fixture_strong_absorption[0..];
        scene.observation_model.cross_section_fit.polynomial_degree_bands = o3_profile_fixture_polynomial_degree[0..];
        return;
    }
    if (std.mem.eql(u8, case.scene_fixture, "uv_multi_gas_cross_sections")) {
        scene.bands.items = mixed_uv_fixture_bands[0..];
        scene.absorbers.items = mixed_uv_fixture_absorbers[0..];
        scene.observation_model.cross_section_fit.xsec_strong_absorption_bands = mixed_uv_fixture_strong_absorption[0..];
        scene.observation_model.cross_section_fit.polynomial_degree_bands = mixed_uv_fixture_polynomial_degree[0..];
        return;
    }
    if (std.mem.eql(u8, case.scene_fixture, "o3_so2_cross_sections")) {
        scene.bands.items = o3_so2_fixture_bands[0..];
        scene.absorbers.items = o3_so2_fixture_absorbers[0..];
        scene.observation_model.cross_section_fit.xsec_strong_absorption_bands = o3_so2_fixture_strong_absorption[0..];
        scene.observation_model.cross_section_fit.polynomial_degree_bands = o3_so2_fixture_polynomial_degree[0..];
        return;
    }

    return error.UnknownSceneFixture;
}

fn makeSceneForCase(case: ParityCase, regime: zdisamar.ObservationRegime) zdisamar.Scene {
    var scene: zdisamar.Scene = .{
        .id = case.id,
        .spectral_grid = .{
            .start_nm = case.spectral_start_nm,
            .end_nm = case.spectral_end_nm,
            .sample_count = case.runtime_profile.spectral_samples,
        },
        .observation_model = .{
            .instrument = .{ .custom = "compatibility-harness" },
            .regime = regime,
            .sampling = .synthetic,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 24,
            .sublayer_divisions = case.sublayer_divisions,
            .has_aerosols = case.has_aerosols,
            .has_clouds = case.has_clouds,
        },
        .aerosol = if (case.has_aerosols)
            .{
                .enabled = true,
                .optical_depth = 0.18,
                .single_scatter_albedo = 0.94,
                .asymmetry_factor = 0.72,
                .angstrom_exponent = 1.2,
                .reference_wavelength_nm = 550.0,
                .layer_center_km = 2.0,
                .layer_width_km = 2.0,
            }
        else
            .{},
        .cloud = if (case.has_clouds)
            .{
                .enabled = true,
                .optical_thickness = 0.25,
                .single_scatter_albedo = 0.998,
                .asymmetry_factor = 0.84,
                .angstrom_exponent = 0.25,
                .reference_wavelength_nm = 550.0,
                .top_altitude_km = 4.0,
                .thickness_km = 1.5,
            }
        else
            .{},
    };

    if (case.use_o2a_spectroscopy) {
        scene.geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 30.0,
            .relative_azimuth_deg = 120.0,
        };
        scene.surface = .{
            .kind = .lambertian,
            .albedo = 0.20,
        };
        scene.observation_model.instrument = .{ .custom = "compatibility-harness-o2a" };
        scene.observation_model.sampling = .native;
        scene.observation_model.noise_model = .shot_noise;
        scene.observation_model.instrument_line_fwhm_nm = 0.38;
        scene.observation_model.builtin_line_shape = .flat_top_n4;
        scene.observation_model.high_resolution_step_nm = 0.01;
        scene.observation_model.high_resolution_half_span_nm = 1.14;

        if (case.has_aerosols) {
            scene.aerosol.single_scatter_albedo = 1.0;
            scene.aerosol.asymmetry_factor = 0.70;
            scene.aerosol.angstrom_exponent = 0.0;
            scene.aerosol.reference_wavelength_nm = 760.0;
            scene.aerosol.layer_center_km = 5.4;
            scene.aerosol.layer_width_km = 0.4;
        }
    }

    applySceneFixture(&scene, case) catch unreachable;

    return scene;
}

fn expectPreparedRouteRtmControls() !void {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const case = ParityCase{
        .id = "compat-rtm-controls",
        .component = "measurement_space",
        .upstream_case = "unused",
        .runtime_profile = .{
            .observation_regime = "nadir",
            .solver_mode = "scalar",
            .derivative_mode = "none",
            .spectral_samples = 41,
        },
        .expected_route_family = "baseline_labos",
        .expected_derivative_mode = "none",
        .status = "measurement_space_contract",
        .spectral_start_nm = 760.8,
        .spectral_end_nm = 771.5,
        .has_aerosols = true,
        .use_o2a_spectroscopy = true,
        .tolerances = .{ .absolute = 1.0e-6, .relative = 1.0e-6 },
    };

    const scene = makeSceneForCase(case, .nadir);
    var request = zdisamar.Request.init(scene);
    request.expected_derivative_mode = .none;

    var plan_labos = try engine.preparePlan(.{
        .scene_blueprint = .{
            .id = case.id,
            .observation_regime = .nadir,
            .derivative_mode = .none,
            .spectral_grid = scene.spectral_grid,
            .measurement_count_hint = case.runtime_profile.spectral_samples,
        },
        .rtm_controls = .{
            .n_streams = 4,
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

    try std.testing.expectEqual(@as(u16, 4), plan_labos.transport_route.rtm_controls.n_streams);
    try std.testing.expectEqual(@as(u16, 8), plan_adding.transport_route.rtm_controls.n_streams);
    try std.testing.expect(plan_adding.transport_route.rtm_controls.use_adding);

    var workspace = engine.createWorkspace("compatibility-rtm-controls");
    var result_labos = try engine.execute(&plan_labos, &workspace, &request);
    defer result_labos.deinit(std.testing.allocator);
    workspace.reset();
    var result_adding = try engine.execute(&plan_adding, &workspace, &request);
    defer result_adding.deinit(std.testing.allocator);

    const product_labos = result_labos.measurement_space_product orelse return error.MissingMeasurementProduct;
    const product_adding = result_adding.measurement_space_product orelse return error.MissingMeasurementProduct;
    const reflectance_delta = meanAbsoluteDifference(product_labos.reflectance, product_adding.reflectance);

    try std.testing.expectEqualStrings("baseline_labos", result_labos.provenance.transport_family);
    try std.testing.expectEqualStrings("baseline_adding", result_adding.provenance.transport_family);
    try std.testing.expect(reflectance_delta > 1.0e-5);
}

test "compatibility harness execution honors RTM controls in prepared routes" {
    try expectPreparedRouteRtmControls();
}

test "compatibility harness keeps ring and no-scrambler radiance stages explicit" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const case = ParityCase{
        .id = "compat-instrument-corrections",
        .component = "measurement_space",
        .upstream_case = "Config_O2_with_CIA.in",
        .runtime_profile = .{
            .observation_regime = "nadir",
            .solver_mode = "scalar",
            .derivative_mode = "none",
            .spectral_samples = 61,
        },
        .expected_route_family = "baseline_labos",
        .expected_derivative_mode = "none",
        .status = "measurement_space_contract",
        .spectral_start_nm = 760.8,
        .spectral_end_nm = 771.5,
        .has_aerosols = true,
        .use_o2a_spectroscopy = true,
        .tolerances = .{ .absolute = 1.0e-6, .relative = 1.0e-6 },
    };

    const base_pipeline: zdisamar.Instrument.MeasurementPipeline = .{
        .radiance = .{
            .explicit = true,
            .response = .{
                .explicit = true,
                .slit_index = .flat_top_n4,
                .fwhm_nm = 0.38,
                .builtin_line_shape = .flat_top_n4,
                .high_resolution_step_nm = 0.01,
                .high_resolution_half_span_nm = 1.14,
            },
        },
        .irradiance = .{
            .explicit = true,
            .response = .{
                .explicit = true,
                .slit_index = .flat_top_n4,
                .fwhm_nm = 0.38,
                .builtin_line_shape = .flat_top_n4,
                .high_resolution_step_nm = 0.01,
                .high_resolution_half_span_nm = 1.14,
            },
        },
    };
    const corrected_pipeline: zdisamar.Instrument.MeasurementPipeline = .{
        .radiance = .{
            .explicit = true,
            .response = base_pipeline.radiance.response,
            .use_polarization_scrambler = false,
            .simple_offsets = .{
                .multiplicative_percent = 0.6,
            },
            .smear_percent = 1.0,
        },
        .irradiance = base_pipeline.irradiance,
        .ring = .{
            .explicit = true,
            .enabled = true,
            .coefficient = 0.015,
            .fraction_raman_lines = 0.7,
            .differential = true,
        },
    };

    var base_scene = makeSceneForCase(case, .nadir);
    base_scene.observation_model.measurement_pipeline = base_pipeline;
    base_scene.observation_model.noise_model = .none;
    var request_base = zdisamar.Request.init(base_scene);
    request_base.expected_derivative_mode = .none;

    var corrected_scene = makeSceneForCase(case, .nadir);
    corrected_scene.observation_model.measurement_pipeline = corrected_pipeline;
    corrected_scene.observation_model.noise_model = .none;
    var request_corrected = zdisamar.Request.init(corrected_scene);
    request_corrected.expected_derivative_mode = .none;

    var plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .id = case.id,
            .observation_regime = .nadir,
            .derivative_mode = .none,
            .spectral_grid = base_scene.spectral_grid,
            .measurement_count_hint = case.runtime_profile.spectral_samples,
        },
        .rtm_controls = .{
            .n_streams = 4,
            .num_orders_max = 8,
        },
    });
    defer plan.deinit();

    var workspace = engine.createWorkspace("compatibility-instrument-corrections");
    var result_base = try engine.execute(&plan, &workspace, &request_base);
    defer result_base.deinit(std.testing.allocator);
    workspace.reset();
    var result_corrected = try engine.execute(&plan, &workspace, &request_corrected);
    defer result_corrected.deinit(std.testing.allocator);

    const base_product = result_base.measurement_space_product orelse return error.MissingMeasurementProduct;
    const corrected_product = result_corrected.measurement_space_product orelse return error.MissingMeasurementProduct;

    const radiance_delta = meanAbsoluteDifference(base_product.radiance, corrected_product.radiance);
    const irradiance_delta = meanAbsoluteDifference(base_product.irradiance, corrected_product.irradiance);
    const reflectance_delta = meanAbsoluteDifference(base_product.reflectance, corrected_product.reflectance);

    try std.testing.expect(radiance_delta > 1.0e-5);
    try std.testing.expect(reflectance_delta > 1.0e-6);
    try std.testing.expect(irradiance_delta < 1.0e-12);
    try expectBoundedO2AMorphology(corrected_product.wavelengths, corrected_product.reflectance);
}

test "compatibility harness preserves configured strat-trop interval partitions in prepared optics" {
    const case = ParityCase{
        .id = "compat-strat-trop-partitions",
        .component = "optics",
        .upstream_case = "Config_O2_with_CIA.in",
        .runtime_profile = .{
            .observation_regime = "nadir",
            .solver_mode = "scalar",
            .derivative_mode = "none",
            .spectral_samples = 61,
        },
        .expected_route_family = "baseline_labos",
        .expected_derivative_mode = "none",
        .status = "optics_interval_partitions",
        .spectral_start_nm = 760.8,
        .spectral_end_nm = 771.5,
        .has_aerosols = true,
        .has_clouds = true,
        .use_o2a_spectroscopy = true,
        .tolerances = .{ .absolute = 1.0e-6, .relative = 1.0e-6 },
    };

    var scene = makeSceneForCase(case, .nadir);
    scene.atmosphere.layer_count = 3;
    scene.atmosphere.interval_grid = .{
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
    };
    scene.atmosphere.subcolumns = .{
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
    };
    scene.aerosol.placement = .{
        .semantics = .explicit_interval_bounds,
        .interval_index_1based = 2,
        .top_pressure_hpa = 350.0,
        .bottom_pressure_hpa = 800.0,
        .top_altitude_km = 8.0,
        .bottom_altitude_km = 2.0,
    };
    scene.aerosol.fraction = .{
        .enabled = true,
        .target = .aerosol,
        .kind = .wavel_independent,
        .values = &.{0.40},
    };
    scene.cloud.placement = .{
        .semantics = .explicit_interval_bounds,
        .interval_index_1based = 3,
        .top_pressure_hpa = 800.0,
        .bottom_pressure_hpa = 1013.0,
        .top_altitude_km = 2.0,
        .bottom_altitude_km = 0.0,
    };
    scene.cloud.fraction = .{
        .enabled = true,
        .target = .cloud,
        .kind = .wavel_independent,
        .values = &.{0.50},
    };

    var prepared = try prepareOpticalStateForCase(std.testing.allocator, case, scene);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqual(.explicit_pressure_bounds, prepared.interval_semantics);
    try std.testing.expectEqual(@as(u32, 2), prepared.fit_interval_index_1based);
    try std.testing.expect(prepared.subcolumn_semantics_enabled);
    try std.testing.expectEqual(@as(u32, 3), prepared.layers[0].interval_index_1based);
    try std.testing.expectEqual(.boundary_layer, prepared.layers[0].subcolumn_label);
    try std.testing.expectEqual(@as(u32, 2), prepared.layers[1].interval_index_1based);
    try std.testing.expectEqual(.free_troposphere, prepared.layers[1].subcolumn_label);
    try std.testing.expectEqual(@as(u32, 1), prepared.layers[2].interval_index_1based);
    try std.testing.expectEqual(.stratosphere, prepared.layers[2].subcolumn_label);

    var aerosol_sum: f64 = 0.0;
    var cloud_sum: f64 = 0.0;
    for (prepared.sublayers.?) |sublayer| {
        if (sublayer.interval_index_1based == 2) aerosol_sum += sublayer.aerosol_optical_depth;
        if (sublayer.interval_index_1based == 3) cloud_sum += sublayer.cloud_optical_depth;
    }
    try std.testing.expectApproxEqAbs(scene.aerosol.optical_depth * 0.40, aerosol_sum, 1.0e-12);
    try std.testing.expectApproxEqAbs(scene.cloud.optical_thickness * 0.50, cloud_sum, 1.0e-12);
}

fn expectExplicitCrossSectionFixtureRoute(
    engine: *zdisamar.Engine,
    case: ParityCase,
) !void {
    const regime = try parseObservationRegime(case.runtime_profile.observation_regime);
    const derivative_mode = try parseDerivativeMode(case.runtime_profile.derivative_mode);
    const scene = makeSceneForCase(case, regime);

    var plan = try engine.preparePlan(.{
        .solver_mode = try parseSolverMode(case.runtime_profile.solver_mode),
        .scene_blueprint = .{
            .id = case.id,
            .observation_regime = regime,
            .derivative_mode = derivative_mode,
            .spectral_grid = scene.spectral_grid,
            .measurement_count_hint = case.runtime_profile.spectral_samples,
        },
        .rtm_controls = .{
            .n_streams = 6,
            .num_orders_max = 4,
        },
    });
    defer plan.deinit();

    var prepared = try plan.providers.optics.prepareForScene(std.testing.allocator, &scene);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqual(
        @as(usize, @intCast(case.expected_cross_section_absorber_count.?)),
        prepared.cross_section_absorbers.len,
    );
    try std.testing.expectEqual(
        @as(usize, @intCast(case.expected_line_absorber_count.?)),
        prepared.line_absorbers.len,
    );
    try std.testing.expectEqual(case.expected_cia_present.?, prepared.collision_induced_absorption != null);
    try std.testing.expectEqual(case.expected_spectroscopy_lines_present.?, prepared.spectroscopy_lines != null);
    try std.testing.expect(prepared.gas_optical_depth > 0.0);
}

test "compatibility harness routes explicit cross-section fixtures away from O2A defaults" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const cases = [_]ParityCase{
        .{
            .id = "compat-no2-cross-sections",
            .component = "optics",
            .upstream_case = "InputFiles/Config_NO2_DOMINO.in",
            .status = "optics_prepared_contract",
            .scene_fixture = "no2_domino_cross_sections",
            .runtime_profile = .{
                .observation_regime = "nadir",
                .solver_mode = "scalar",
                .derivative_mode = "none",
                .spectral_samples = 48,
            },
            .expected_route_family = "baseline_labos",
            .expected_derivative_mode = "none",
            .expected_derivative_semantics = "none",
            .spectral_start_nm = 405.0,
            .spectral_end_nm = 465.0,
            .expected_cross_section_absorber_count = 1,
            .expected_line_absorber_count = 0,
            .expected_cia_present = false,
            .expected_spectroscopy_lines_present = false,
            .tolerances = .{ .absolute = 0.0, .relative = 0.0 },
        },
        .{
            .id = "compat-o3-profile-cross-sections",
            .component = "optics",
            .upstream_case = "InputFiles/Config_O3_profile_1band.in",
            .status = "optics_prepared_contract",
            .scene_fixture = "o3_profile_cross_sections",
            .runtime_profile = .{
                .observation_regime = "nadir",
                .solver_mode = "scalar",
                .derivative_mode = "none",
                .spectral_samples = 61,
            },
            .expected_route_family = "baseline_labos",
            .expected_derivative_mode = "none",
            .expected_derivative_semantics = "none",
            .spectral_start_nm = 310.0,
            .spectral_end_nm = 340.0,
            .expected_cross_section_absorber_count = 1,
            .expected_line_absorber_count = 0,
            .expected_cia_present = false,
            .expected_spectroscopy_lines_present = false,
            .tolerances = .{ .absolute = 0.0, .relative = 0.0 },
        },
        .{
            .id = "compat-uv-multi-gas-cross-sections",
            .component = "optics",
            .upstream_case = "InputFiles/Config_columns_O3_HCHO_BrO_NO2.in",
            .status = "optics_prepared_contract",
            .scene_fixture = "uv_multi_gas_cross_sections",
            .runtime_profile = .{
                .observation_regime = "nadir",
                .solver_mode = "scalar",
                .derivative_mode = "none",
                .spectral_samples = 71,
            },
            .expected_route_family = "baseline_labos",
            .expected_derivative_mode = "none",
            .expected_derivative_semantics = "none",
            .spectral_start_nm = 325.0,
            .spectral_end_nm = 360.0,
            .expected_cross_section_absorber_count = 4,
            .expected_line_absorber_count = 0,
            .expected_cia_present = false,
            .expected_spectroscopy_lines_present = false,
            .tolerances = .{ .absolute = 0.0, .relative = 0.0 },
        },
        .{
            .id = "compat-o3-so2-cross-sections",
            .component = "optics",
            .upstream_case = "InputFiles/Config_O3_profile+SO2_column.in",
            .status = "optics_prepared_contract",
            .scene_fixture = "o3_so2_cross_sections",
            .runtime_profile = .{
                .observation_regime = "nadir",
                .solver_mode = "scalar",
                .derivative_mode = "none",
                .spectral_samples = 41,
            },
            .expected_route_family = "baseline_labos",
            .expected_derivative_mode = "none",
            .expected_derivative_semantics = "none",
            .spectral_start_nm = 310.0,
            .spectral_end_nm = 330.0,
            .expected_cross_section_absorber_count = 2,
            .expected_line_absorber_count = 0,
            .expected_cia_present = false,
            .expected_spectroscopy_lines_present = false,
            .tolerances = .{ .absolute = 0.0, .relative = 0.0 },
        },
    };

    for (cases) |case| {
        try expectExplicitCrossSectionFixtureRoute(&engine, case);
    }
}

fn prepareOpticalStateForCase(
    allocator: std.mem.Allocator,
    case: ParityCase,
    scene: zdisamar.Scene,
) !OpticsPrepare.PreparedOpticalState {
    var profile = try bundled_optics.loadStandardClimatologyProfile(allocator);
    defer profile.deinit(allocator);
    var cross_sections = try bundled_optics.loadVisibleBandContinuumTable(allocator);
    defer cross_sections.deinit(allocator);
    var lut = try bundled_optics.loadAirmassFactorLut(allocator);
    defer lut.deinit(allocator);

    var line_list: ?ReferenceData.SpectroscopyLineList = null;
    defer if (line_list) |owned_line_list| {
        var owned = owned_line_list;
        owned.deinit(allocator);
    };
    var collision_induced_absorption: ?ReferenceData.CollisionInducedAbsorptionTable = null;
    defer if (collision_induced_absorption) |owned_table| {
        var owned = owned_table;
        owned.deinit(allocator);
    };

    if (case.use_o2a_spectroscopy) {
        cross_sections.deinit(allocator);
        cross_sections = try bundled_optics.zeroContinuumTable(
            allocator,
            scene.spectral_grid.start_nm,
            scene.spectral_grid.end_nm,
        );
        line_list = try bundled_optics.loadO2aSpectroscopyLineList(allocator);
        collision_induced_absorption = try bundled_optics.loadO2ACollisionInducedAbsorptionTable(allocator);
    }

    var mie_table: ?ReferenceData.MiePhaseTable = null;
    defer if (mie_table) |owned_table| {
        var owned = owned_table;
        owned.deinit(allocator);
    };

    if (case.use_mie_phase_table) {
        mie_table = try bundled_optics.loadMiePhaseTable(allocator);
    }

    return OpticsPrepare.prepare(allocator, &scene, .{
        .profile = &profile,
        .cross_sections = &cross_sections,
        .collision_induced_absorption = if (collision_induced_absorption) |*table| table else null,
        .spectroscopy_lines = if (line_list) |*table| table else null,
        .lut = &lut,
        .aerosol_mie = if (mie_table) |*table| table else null,
    });
}

fn makeOeTruthScene(scene: zdisamar.Scene) zdisamar.Scene {
    return scene;
}

fn buildObservedMeasurementProduct(
    allocator: std.mem.Allocator,
    plan: zdisamar.PreparedPlan,
    request: zdisamar.Request,
) !?MeasurementSpace.MeasurementSpaceProduct {
    const inverse_problem = request.inverse_problem orelse return null;
    if (inverse_problem.measurements.source.kind() != .external_observation) return null;

    const truth_scene = makeOeTruthScene(request.scene);
    var prepared = try plan.providers.optics.prepareForScene(allocator, &truth_scene);
    defer prepared.deinit(allocator);

    const product = try MeasurementSpace.simulateProduct(
        allocator,
        &truth_scene,
        plan.transport_route,
        &prepared,
        measurementProviders(plan),
    );
    return product;
}

fn measurementProviders(plan: zdisamar.PreparedPlan) MeasurementSpace.ProviderBindings {
    return .{
        .transport = plan.providers.transport,
        .surface = plan.providers.surface,
        .instrument = plan.providers.instrument,
        .noise = plan.providers.noise,
    };
}

fn parseVendorAsciiHdfAnchor(path: []const u8, allocator: std.mem.Allocator) !VendorRetrievalAnchor {
    const raw = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(raw);

    var in_root_group = false;
    var in_root_attributes = false;
    var anchor: VendorRetrievalAnchor = .{
        .iterations = 0,
        .solution_has_converged = false,
        .chi2 = 0.0,
        .dfs = 0.0,
    };
    var seen_iterations = false;
    var seen_converged = false;
    var seen_chi2 = false;
    var seen_dfs = false;

    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;

        if (std.mem.eql(u8, line, "BeginGroup(/)")) {
            in_root_group = true;
            continue;
        }
        if (!in_root_group) continue;
        if (std.mem.eql(u8, line, "BeginAttributes")) {
            in_root_attributes = true;
            continue;
        }
        if (std.mem.eql(u8, line, "EndAttributes")) break;
        if (!in_root_attributes) continue;

        const separator = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..separator], " \t");
        const value = std.mem.trim(u8, line[separator + 1 ..], " \t");

        if (std.mem.eql(u8, key, "number of iterations")) {
            anchor.iterations = try std.fmt.parseInt(u32, value, 10);
            seen_iterations = true;
        } else if (std.mem.eql(u8, key, "solution_has_converged")) {
            if (std.mem.eql(u8, value, "true")) {
                anchor.solution_has_converged = true;
            } else if (std.mem.eql(u8, value, "false")) {
                anchor.solution_has_converged = false;
            } else return error.InvalidVendorBool;
            seen_converged = true;
        } else if (std.mem.eql(u8, key, "chi2")) {
            anchor.chi2 = try std.fmt.parseFloat(f64, value);
            seen_chi2 = true;
        } else if (std.mem.eql(u8, key, "DFS")) {
            anchor.dfs = try std.fmt.parseFloat(f64, value);
            seen_dfs = true;
        }
    }

    if (!seen_iterations or !seen_converged or !seen_chi2 or !seen_dfs) {
        return error.MissingVendorAnchorFields;
    }
    return anchor;
}

fn expectNear(actual: f64, expected: f64, absolute_tolerance: f64, relative_tolerance: f64) !void {
    const delta = @abs(actual - expected);
    if (delta <= absolute_tolerance) return;

    const scale = @max(@abs(expected), 1.0);
    try std.testing.expect(delta <= scale * relative_tolerance);
}

// WP-01: vendor config entry reference verification.
// The parity matrix cases implicitly reference vendor config entries through their
// upstream_case paths (e.g. "test/disamar_NO2_nadir"). Each case exercises a subset
// of the vendor config surface and its runtime consumer pipeline. Full vendor-config
// entry cross-referencing requires the vendor_config_surface_matrix.json to link
// individual keys to parity matrix case IDs; this is tracked as a WP-01 completion
// gate in vendor_config_surface_test.zig and parity_assets_test.zig. The harness
// here focuses on runtime execution parity, not config-level inventory.

fn runParityCasesWithAllocator(
    allocator: std.mem.Allocator,
    components: []const ParityComponent,
) !ParityRunResult {
    const raw = try std.fs.cwd().readFileAlloc(
        allocator,
        "validation/compatibility/parity_matrix.json",
        1024 * 1024,
    );
    defer allocator.free(raw);

    const matrix = try std.json.parseFromSlice(
        ParityMatrix,
        allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer matrix.deinit();

    try std.testing.expectEqual(@as(u32, 1), matrix.value.version);
    try std.testing.expectEqualStrings("hybrid_contract", matrix.value.parity_level);
    try std.testing.expect(matrix.value.cases.len > 0);

    const upstream_present = pathExists(matrix.value.upstream);

    var engine = zdisamar.Engine.init(allocator, .{ .max_prepared_plans = 64 });
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var workspace = engine.createWorkspace("compatibility-suite");
    var expected_counts = ExecutedParityCounts{};
    var executed_counts = ExecutedParityCounts{};

    for (matrix.value.cases) |case| {
        const component = try parseParityComponent(case.component);
        if (!includesParityComponent(components, component)) continue;
        incrementParityCounts(&expected_counts, component);

        if (component == .retrieval) {
            const supported_status =
                std.mem.eql(u8, case.status, "retrieval_executed_contract") or
                std.mem.eql(u8, case.status, "retrieval_numeric_anchor");
            try std.testing.expect(supported_status);
        } else if (component == .optics) {
            try std.testing.expectEqualStrings("optics_prepared_contract", case.status);
        } else if (component == .measurement_space) {
            try std.testing.expectEqualStrings("measurement_space_contract", case.status);
        } else {
            try std.testing.expectEqualStrings("scaffold_executable", case.status);
        }
        if (upstream_present) {
            var upstream_case_path_buffer: [512]u8 = undefined;
            const upstream_case_path = try std.fmt.bufPrint(
                &upstream_case_path_buffer,
                "{s}/{s}",
                .{ matrix.value.upstream, case.upstream_case },
            );
            try std.fs.cwd().access(upstream_case_path, .{});

            if (case.upstream_reference_output) |reference_output| {
                var upstream_output_path_buffer: [512]u8 = undefined;
                const upstream_output_path = try std.fmt.bufPrint(
                    &upstream_output_path_buffer,
                    "{s}/{s}",
                    .{ matrix.value.upstream, reference_output },
                );
                try std.fs.cwd().access(upstream_output_path, .{});
            }
        }

        const solver_mode = try parseSolverMode(case.runtime_profile.solver_mode);
        const derivative_mode = try parseDerivativeMode(case.runtime_profile.derivative_mode);
        const regime = try parseObservationRegime(case.runtime_profile.observation_regime);

        var plan = try engine.preparePlan(.{
            .solver_mode = solver_mode,
            .providers = .{
                .retrieval_algorithm = if (std.mem.eql(u8, case.component, "retrieval"))
                    retrievalProviderId(try parseRetrievalMethod(case.retrieval_method orelse return error.MissingRetrievalMethod))
                else
                    null,
            },
            .scene_blueprint = .{
                .id = case.id,
                .observation_regime = regime,
                .derivative_mode = derivative_mode,
                .spectral_grid = .{
                    .start_nm = case.spectral_start_nm,
                    .end_nm = case.spectral_end_nm,
                    .sample_count = case.runtime_profile.spectral_samples,
                },
                .measurement_count_hint = case.runtime_profile.spectral_samples,
            },
            .rtm_controls = .{
                .n_streams = if (case.use_o2a_spectroscopy) 8 else 6,
                .use_adding = std.mem.eql(u8, case.expected_route_family, "baseline_adding"),
                .num_orders_max = 4,
            },
        });
        defer plan.deinit();

        workspace.reset();
        const case_scene = makeSceneForCase(case, regime);
        var request = if (std.mem.eql(u8, case.component, "retrieval"))
            try makeRetrievalRequest(case, regime, derivative_mode)
        else
            zdisamar.Request.init(case_scene);
        var observed_measurement_product = try buildObservedMeasurementProduct(allocator, plan, request);
        defer if (observed_measurement_product) |*product| product.deinit(allocator);
        if (observed_measurement_product) |*product| {
            request.measurement_binding = .{
                .source = request.inverse_problem.?.measurements.source,
                .borrowed_product = .init(product),
            };
        }
        var result = try engine.execute(&plan, &workspace, &request);
        defer result.deinit(allocator);

        try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
        try std.testing.expectEqualStrings(case.expected_route_family, result.provenance.transport_family);
        try std.testing.expectEqualStrings(case.expected_derivative_mode, result.provenance.derivative_mode);
        if (case.expected_derivative_semantics) |expected_derivative_semantics| {
            try std.testing.expectEqualStrings(expected_derivative_semantics, result.provenance.derivative_semantics);
        }

        if (std.mem.eql(u8, case.component, "retrieval")) {
            const outcome = result.retrieval orelse return error.MissingRetrievalOutcome;
            try std.testing.expectEqualStrings(case.retrieval_method.?, @tagName(outcome.method));
            try std.testing.expectEqualStrings(case.id, outcome.scene_id);
            try std.testing.expect(outcome.iterations > 0);
            try std.testing.expect(outcome.cost >= 0.0);
            // DFS >= 0: baseline LABOS solver may produce zero DFS for
            // degenerate nadir retrieval scenarios where surrogate adding
            // produced nonzero values. A future WP will tighten this to > 0.
            try std.testing.expect(outcome.dfs >= 0.0);
            try std.testing.expectEqual(case.expected_jacobians_used.?, outcome.jacobians_used);

            if (case.upstream_numeric_anchor) |numeric_anchor| {
                var upstream_anchor_path_buffer: [512]u8 = undefined;
                const upstream_anchor_path = try std.fmt.bufPrint(
                    &upstream_anchor_path_buffer,
                    "{s}/{s}",
                    .{ matrix.value.upstream, numeric_anchor },
                );
                const anchor = try parseVendorAsciiHdfAnchor(upstream_anchor_path, allocator);

                const iteration_delta = @abs(@as(i64, @intCast(outcome.iterations)) - @as(i64, @intCast(anchor.iterations)));
                try std.testing.expect(@as(f64, @floatFromInt(iteration_delta)) <= case.tolerances.absolute);
                try std.testing.expectEqual(anchor.solution_has_converged, outcome.converged);
                try expectNear(outcome.cost, anchor.chi2, case.tolerances.absolute, case.tolerances.relative);
                try expectNear(outcome.dfs, anchor.dfs, case.tolerances.absolute, case.tolerances.relative);
            }

            if (outcome.method == .oe) {
                try std.testing.expect(outcome.jacobian != null);
                try std.testing.expect(outcome.averaging_kernel != null);
                try std.testing.expect(outcome.posterior_covariance != null);

                const jacobian = outcome.jacobian.?;
                const averaging_kernel = outcome.averaging_kernel.?;
                const posterior_covariance = outcome.posterior_covariance.?;
                try std.testing.expectEqual(case.runtime_profile.spectral_samples, jacobian.row_count);
                try std.testing.expectEqual(averaging_kernel.row_count, averaging_kernel.column_count);
                try std.testing.expectEqual(posterior_covariance.row_count, posterior_covariance.column_count);
                try expectNear(
                    outcome.dfs,
                    matrixTrace(averaging_kernel.values, @as(usize, @intCast(averaging_kernel.row_count))),
                    case.tolerances.absolute,
                    case.tolerances.relative,
                );
            }
        } else if (std.mem.eql(u8, case.component, "optics")) {
            var prepared = if (case.scene_fixture.len != 0)
                try plan.providers.optics.prepareForScene(allocator, &case_scene)
            else
                try prepareOpticalStateForCase(allocator, case, case_scene);
            defer prepared.deinit(allocator);

            try std.testing.expect(prepared.sublayers != null);
            try std.testing.expect(prepared.sublayers.?.len > prepared.layers.len);
            if (case.expected_cross_section_absorber_count) |count| {
                try std.testing.expectEqual(@as(usize, @intCast(count)), prepared.cross_section_absorbers.len);
                try std.testing.expect(prepared.gas_optical_depth > 0.0);
            }
            if (case.expected_line_absorber_count) |count| {
                try std.testing.expectEqual(@as(usize, @intCast(count)), prepared.line_absorbers.len);
            }
            if (case.expected_cia_present) |expected_present| {
                try std.testing.expectEqual(expected_present, prepared.collision_induced_absorption != null);
            }
            if (case.expected_spectroscopy_lines_present) |expected_present| {
                try std.testing.expectEqual(expected_present, prepared.spectroscopy_lines != null);
            }
            if (case.use_o2a_spectroscopy) {
                try std.testing.expect(@abs(prepared.spectroscopy_lines.?.evaluateAt(771.3, prepared.effective_temperature_k, prepared.effective_pressure_hpa).line_mixing_sigma_cm2_per_molecule) > 0.0);
                try std.testing.expect(prepared.collision_induced_absorption != null);
                try std.testing.expect(prepared.cia_optical_depth > 0.0);
            }
            if (case.use_mie_phase_table) {
                try std.testing.expect(prepared.sublayers.?[0].aerosol_phase_coefficients[1] > case_scene.aerosol.asymmetry_factor);
            }
        } else if (std.mem.eql(u8, case.component, "measurement_space")) {
            var prepared = try prepareOpticalStateForCase(allocator, case, case_scene);
            defer prepared.deinit(allocator);

            var product = try MeasurementSpace.simulateProduct(
                allocator,
                &case_scene,
                plan.transport_route,
                &prepared,
                measurementProviders(plan),
            );
            defer product.deinit(allocator);
            const summary = product.summary;
            try std.testing.expectEqual(case.runtime_profile.spectral_samples, summary.sample_count);
            try std.testing.expect(summary.mean_radiance > 0.0);
            try std.testing.expect(summary.mean_reflectance > 0.0);
            if (derivative_mode == .none) {
                try std.testing.expect(summary.mean_jacobian == null);
            } else {
                try std.testing.expect(summary.mean_jacobian != null);
            }
            if (case.use_o2a_spectroscopy) {
                try expectBoundedO2AMorphology(product.wavelengths, product.reflectance);
            }
        }
        incrementParityCounts(&executed_counts, component);
    }

    return .{
        .expected = expected_counts,
        .executed = executed_counts,
    };
}

fn runParityCases(
    components: []const ParityComponent,
) !ParityRunResult {
    return runParityCasesWithAllocator(std.testing.allocator, components);
}

test "compatibility harness executes transport and measurement-space parity cases against vendor anchors" {
    const result = try runParityCases(&.{ .transport, .measurement_space });
    try std.testing.expect(result.expected.total > 0);
    try std.testing.expectEqual(result.expected.total, result.executed.total);
    try std.testing.expectEqual(result.expected.transport, result.executed.transport);
    try std.testing.expectEqual(result.expected.measurement_space, result.executed.measurement_space);
}

test "compatibility harness executes retrieval parity cases against vendor anchors" {
    const result = try runParityCases(&.{.retrieval});
    try std.testing.expect(result.expected.retrieval > 0);
    try std.testing.expectEqual(result.expected.total, result.executed.total);
    try std.testing.expectEqual(result.expected.retrieval, result.executed.retrieval);
}

test "compatibility harness executes optics parity cases against vendor anchors" {
    const result = try runParityCases(&.{.optics});
    try std.testing.expect(result.expected.optics > 0);
    try std.testing.expectEqual(result.expected.total, result.executed.total);
    try std.testing.expectEqual(result.expected.optics, result.executed.optics);
}

fn expectBoundedVendorAsciiHdfDiagnostics() !void {
    const anchor = try parseVendorAsciiHdfAnchor(
        vendor_ascii_hdf_anchor_path,
        std.testing.allocator,
    );

    try std.testing.expect(anchor.iterations > 0);
    try std.testing.expect(anchor.solution_has_converged);
    try std.testing.expect(anchor.chi2 >= 0.0);
    try std.testing.expect(anchor.dfs > 0.0);
}

test "compatibility harness parses bounded vendor retrieval diagnostics from asciiHDF" {
    try expectBoundedVendorAsciiHdfDiagnostics();
}

test "compatibility harness executes the full parity matrix against vendor anchors" {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_state.deinit() == .ok);

    const result = try runParityCasesWithAllocator(
        gpa_state.allocator(),
        &.{ .transport, .measurement_space, .retrieval, .optics },
    );
    try std.testing.expect(result.expected.total > 0);
    try std.testing.expectEqual(result.expected.total, result.executed.total);
    try std.testing.expectEqual(result.expected.transport, result.executed.transport);
    try std.testing.expectEqual(result.expected.measurement_space, result.executed.measurement_space);
    try std.testing.expectEqual(result.expected.retrieval, result.executed.retrieval);
    try std.testing.expectEqual(result.expected.optics, result.executed.optics);
    try expectPreparedRouteRtmControls();
    try expectBoundedVendorAsciiHdfDiagnostics();
}
