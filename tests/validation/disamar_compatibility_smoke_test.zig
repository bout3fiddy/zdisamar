const std = @import("std");
const zdisamar = @import("zdisamar");

const VendorRetrievalAnchor = struct {
    iterations: u32,
    solution_has_converged: bool,
    chi2: f64,
    dfs: f64,
};

const vendor_ascii_hdf_anchor_path = "validation/compatibility/disamar_asciihdf_anchor.txt";

fn meanAbsoluteDifference(values_a: []const f64, values_b: []const f64) f64 {
    var sum: f64 = 0.0;
    for (values_a, values_b) |value_a, value_b| {
        sum += @abs(value_a - value_b);
    }
    return sum / @as(f64, @floatFromInt(values_a.len));
}

fn buildCompatibilityHarnessO2AScene() zdisamar.Scene {
    return .{
        .id = "compat-rtm-controls",
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 771.5,
            .sample_count = 41,
        },
        .observation_model = .{
            .instrument = .{ .custom = "compatibility-harness-o2a" },
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.38,
            .builtin_line_shape = .flat_top_n4,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
        },
        .atmosphere = .{
            .layer_count = 24,
            .sublayer_divisions = 3,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.18,
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
        .surface = .{
            .kind = .lambertian,
            .albedo = 0.20,
        },
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

test "compatibility harness execution honors RTM controls in prepared routes" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const scene = buildCompatibilityHarnessO2AScene();
    var request = zdisamar.Request.init(scene);
    request.expected_derivative_mode = .none;

    var plan_labos = try engine.preparePlan(.{
        .scene_blueprint = .{
            .id = scene.id,
            .observation_regime = .nadir,
            .derivative_mode = .none,
            .spectral_grid = scene.spectral_grid,
            .measurement_count_hint = scene.spectral_grid.sample_count,
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

test "compatibility harness parses bounded vendor retrieval diagnostics from asciiHDF" {
    const anchor = try parseVendorAsciiHdfAnchor(
        vendor_ascii_hdf_anchor_path,
        std.testing.allocator,
    );

    try std.testing.expect(anchor.iterations > 0);
    try std.testing.expect(anchor.solution_has_converged);
    try std.testing.expect(anchor.chi2 >= 0.0);
    try std.testing.expect(anchor.dfs > 0.0);
}
