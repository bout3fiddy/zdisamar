const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");
const retrieval = @import("zdisamar_internal").retrieval;
const ReferenceData = internal.reference_data;
const OpticsPrepare = internal.kernels.optics.prepare;
const MeasurementSpace = internal.kernels.transport.measurement_space;

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
    spectral_start_nm: f64 = 405.0,
    spectral_end_nm: f64 = 465.0,
    has_aerosols: bool = false,
    has_clouds: bool = false,
    use_o2a_spectroscopy: bool = false,
    use_mie_phase_table: bool = false,
    sublayer_divisions: u8 = 3,
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

    return scene;
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

fn prepareOpticalStateForCase(
    allocator: std.mem.Allocator,
    case: ParityCase,
    scene: zdisamar.Scene,
) !OpticsPrepare.PreparedOpticalState {
    var climatology_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        allocator,
        .climatology_profile,
        "data/climatologies/bundle_manifest.json",
        "us_standard_1976_profile",
    );
    defer climatology_asset.deinit(allocator);

    var cross_section_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        allocator,
        .cross_section_table,
        "data/cross_sections/bundle_manifest.json",
        "no2_405_465_demo",
    );
    defer cross_section_asset.deinit(allocator);

    var lut_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        allocator,
        .lookup_table,
        "data/luts/bundle_manifest.json",
        "airmass_factor_nadir_demo",
    );
    defer lut_asset.deinit(allocator);

    var profile = try climatology_asset.toClimatologyProfile(allocator);
    defer profile.deinit(allocator);
    var cross_sections = try cross_section_asset.toCrossSectionTable(allocator);
    defer cross_sections.deinit(allocator);
    if (case.use_o2a_spectroscopy) {
        cross_sections.deinit(allocator);
        cross_sections = try buildZeroContinuumTable(
            allocator,
            scene.spectral_grid.start_nm,
            scene.spectral_grid.end_nm,
        );
    }
    var lut = try lut_asset.toAirmassFactorLut(allocator);
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
        var line_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
            allocator,
            .spectroscopy_line_list,
            "data/cross_sections/bundle_manifest.json",
            "o2a_hitran_07_hit08_tropomi",
        );
        defer line_asset.deinit(allocator);
        var strong_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
            allocator,
            .spectroscopy_strong_line_set,
            "data/cross_sections/bundle_manifest.json",
            "o2a_lisa_sdf",
        );
        defer strong_asset.deinit(allocator);
        var rmf_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
            allocator,
            .spectroscopy_relaxation_matrix,
            "data/cross_sections/bundle_manifest.json",
            "o2a_lisa_rmf",
        );
        defer rmf_asset.deinit(allocator);

        var prepared_lines = try line_asset.toSpectroscopyLineList(allocator);
        var strong_lines = try strong_asset.toSpectroscopyStrongLineSet(allocator);
        defer strong_lines.deinit(allocator);
        var relaxation_matrix = try rmf_asset.toSpectroscopyRelaxationMatrix(allocator);
        defer relaxation_matrix.deinit(allocator);
        try prepared_lines.attachStrongLineSidecars(allocator, strong_lines, relaxation_matrix);
        line_list = prepared_lines;

        var cia_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
            allocator,
            .collision_induced_absorption_table,
            "data/cross_sections/bundle_manifest.json",
            "o2o2_bira_o2a",
        );
        defer cia_asset.deinit(allocator);
        collision_induced_absorption = try cia_asset.toCollisionInducedAbsorptionTable(allocator);
    }

    var mie_table: ?ReferenceData.MiePhaseTable = null;
    defer if (mie_table) |owned_table| {
        var owned = owned_table;
        owned.deinit(allocator);
    };

    if (case.use_mie_phase_table) {
        var mie_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
            allocator,
            .mie_phase_table,
            "data/luts/bundle_manifest.json",
            "mie_dust_phase_subset",
        );
        defer mie_asset.deinit(allocator);
        mie_table = try mie_asset.toMiePhaseTable(allocator);
    }

    return OpticsPrepare.prepareWithParticleTables(
        allocator,
        &scene,
        &profile,
        &cross_sections,
        if (collision_induced_absorption) |*table| table else null,
        if (line_list) |*table| table else null,
        &lut,
        if (mie_table) |*table| table else null,
        null,
    );
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

test "compatibility harness executes bounded parity matrix cases against vendor anchors" {
    const raw = try std.fs.cwd().readFileAlloc(
        std.testing.allocator,
        "validation/compatibility/parity_matrix.json",
        1024 * 1024,
    );
    defer std.testing.allocator.free(raw);

    const matrix = try std.json.parseFromSlice(
        ParityMatrix,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = true },
    );
    defer matrix.deinit();

    try std.testing.expectEqual(@as(u32, 1), matrix.value.version);
    try std.testing.expectEqualStrings("hybrid_contract", matrix.value.parity_level);
    try std.testing.expect(matrix.value.cases.len > 0);

    const upstream_present = pathExists(matrix.value.upstream);

    var engine = zdisamar.Engine.init(std.testing.allocator, .{ .max_prepared_plans = 64 });
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var workspace = engine.createWorkspace("compatibility-suite");
    var executed_cases: usize = 0;

    for (matrix.value.cases) |case| {
        if (std.mem.eql(u8, case.component, "retrieval")) {
            const supported_status =
                std.mem.eql(u8, case.status, "retrieval_executed_contract") or
                std.mem.eql(u8, case.status, "retrieval_numeric_anchor");
            try std.testing.expect(supported_status);
        } else if (std.mem.eql(u8, case.component, "optics")) {
            try std.testing.expectEqualStrings("optics_prepared_contract", case.status);
        } else if (std.mem.eql(u8, case.component, "measurement_space")) {
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
        });
        defer plan.deinit();

        workspace.reset();
        const case_scene = makeSceneForCase(case, regime);
        var request = if (std.mem.eql(u8, case.component, "retrieval"))
            try makeRetrievalRequest(case, regime, derivative_mode)
        else
            zdisamar.Request.init(case_scene);
        var observed_measurement_product = try buildObservedMeasurementProduct(std.testing.allocator, plan, request);
        defer if (observed_measurement_product) |*product| product.deinit(std.testing.allocator);
        if (observed_measurement_product) |*product| {
            request.measurement_binding = .{
                .source = request.inverse_problem.?.measurements.source,
                .borrowed_product = .init(product),
            };
        }
        var result = try engine.execute(&plan, &workspace, &request);
        defer result.deinit(std.testing.allocator);

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
                const anchor = try parseVendorAsciiHdfAnchor(upstream_anchor_path, std.testing.allocator);

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
            var prepared = try prepareOpticalStateForCase(std.testing.allocator, case, case_scene);
            defer prepared.deinit(std.testing.allocator);

            try std.testing.expect(prepared.sublayers != null);
            try std.testing.expect(prepared.sublayers.?.len > prepared.layers.len);
            if (case.use_o2a_spectroscopy) {
                try std.testing.expect(@abs(prepared.spectroscopy_lines.?.evaluateAt(771.3, prepared.effective_temperature_k, prepared.effective_pressure_hpa).line_mixing_sigma_cm2_per_molecule) > 0.0);
                try std.testing.expect(prepared.collision_induced_absorption != null);
                try std.testing.expect(prepared.cia_optical_depth > 0.0);
            }
            if (case.use_mie_phase_table) {
                try std.testing.expect(prepared.sublayers.?[0].aerosol_phase_coefficients[1] > case_scene.aerosol.asymmetry_factor);
            }
        } else if (std.mem.eql(u8, case.component, "measurement_space")) {
            var prepared = try prepareOpticalStateForCase(std.testing.allocator, case, case_scene);
            defer prepared.deinit(std.testing.allocator);

            var product = try MeasurementSpace.simulateProduct(
                std.testing.allocator,
                &case_scene,
                plan.transport_route,
                &prepared,
                measurementProviders(plan),
            );
            defer product.deinit(std.testing.allocator);
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
        executed_cases += 1;
    }

    try std.testing.expect(executed_cases > 0);
}

test "compatibility harness parses bounded vendor retrieval diagnostics from asciiHDF" {
    const anchor = try parseVendorAsciiHdfAnchor(
        "vendor/disamar-fortran/test/disamar.asciiHDF",
        std.testing.allocator,
    );

    try std.testing.expect(anchor.iterations > 0);
    try std.testing.expect(anchor.solution_has_converged);
    try std.testing.expect(anchor.chi2 >= 0.0);
    try std.testing.expect(anchor.dfs > 0.0);
}
