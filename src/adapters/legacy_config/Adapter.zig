const std = @import("std");
const zdisamar = @import("zdisamar");

pub const ParseError = error{
    InvalidLine,
    UnknownKey,
    InvalidBoolean,
    InvalidSolverMode,
};

pub const PreparedRun = struct {
    workspace_label: []const u8 = "legacy-config",
    plan_template: zdisamar.PlanTemplate = .{
        .scene_blueprint = .{
            .spectral_grid = .{ .sample_count = 1 },
        },
    },
    scene: zdisamar.Scene = .{
        .spectral_grid = .{ .sample_count = 1 },
    },
    diagnostics: zdisamar.DiagnosticsSpec = .{},
    requested_products: std.ArrayListUnmanaged([]const u8) = .{},

    pub fn deinit(self: *PreparedRun, allocator: std.mem.Allocator) void {
        self.requested_products.deinit(allocator);
        self.* = .{};
    }

    pub fn toRequest(self: *const PreparedRun) zdisamar.Request {
        var request = zdisamar.Request.init(self.scene);
        request.expected_derivative_mode = self.plan_template.scene_blueprint.derivative_mode;
        request.diagnostics = self.diagnostics;
        request.requested_products = self.requested_products.items;
        return request;
    }
};

pub fn parse(allocator: std.mem.Allocator, contents: []const u8) !PreparedRun {
    var prepared = PreparedRun{};
    errdefer prepared.deinit(allocator);

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const line = trimWhitespace(raw_line);
        if (line.len == 0 or line[0] == '#' or line[0] == '!') continue;

        const separator = std.mem.indexOfScalar(u8, line, '=') orelse return ParseError.InvalidLine;
        const key = trimWhitespace(line[0..separator]);
        const value = trimWhitespace(line[separator + 1 ..]);
        if (key.len == 0 or value.len == 0) return ParseError.InvalidLine;

        try applyValue(allocator, &prepared, key, value);
    }

    prepared.plan_template.scene_blueprint.id = prepared.scene.id;
    prepared.plan_template.scene_blueprint.spectral_grid = prepared.scene.spectral_grid;
    return prepared;
}

fn applyValue(
    allocator: std.mem.Allocator,
    prepared: *PreparedRun,
    key: []const u8,
    value: []const u8,
) !void {
    if (std.mem.eql(u8, key, "workspace")) {
        prepared.workspace_label = value;
        return;
    }

    if (std.mem.eql(u8, key, "model_family")) {
        prepared.plan_template.model_family = value;
        return;
    }

    if (std.mem.eql(u8, key, "transport")) {
        prepared.plan_template.transport = value;
        return;
    }

    if (std.mem.eql(u8, key, "retrieval")) {
        prepared.plan_template.retrieval = if (std.mem.eql(u8, value, "none")) null else value;
        return;
    }

    if (std.mem.eql(u8, key, "solver_mode")) {
        prepared.plan_template.solver_mode = try parseSolverMode(value);
        return;
    }

    if (std.mem.eql(u8, key, "scene_id")) {
        prepared.scene.id = value;
        return;
    }

    if (std.mem.eql(u8, key, "spectral_start_nm")) {
        prepared.scene.spectral_grid.start_nm = try std.fmt.parseFloat(f64, value);
        return;
    }

    if (std.mem.eql(u8, key, "spectral_end_nm")) {
        prepared.scene.spectral_grid.end_nm = try std.fmt.parseFloat(f64, value);
        return;
    }

    if (std.mem.eql(u8, key, "spectral_samples")) {
        prepared.scene.spectral_grid.sample_count = try std.fmt.parseUnsigned(u32, value, 10);
        return;
    }

    if (std.mem.eql(u8, key, "atmosphere_layers")) {
        prepared.scene.atmosphere.layer_count = try std.fmt.parseUnsigned(u32, value, 10);
        return;
    }

    if (std.mem.eql(u8, key, "has_clouds")) {
        prepared.scene.atmosphere.has_clouds = try parseBool(value);
        return;
    }

    if (std.mem.eql(u8, key, "has_aerosols")) {
        prepared.scene.atmosphere.has_aerosols = try parseBool(value);
        return;
    }

    if (std.mem.eql(u8, key, "solar_zenith_deg")) {
        prepared.scene.geometry.solar_zenith_deg = try std.fmt.parseFloat(f64, value);
        return;
    }

    if (std.mem.eql(u8, key, "viewing_zenith_deg")) {
        prepared.scene.geometry.viewing_zenith_deg = try std.fmt.parseFloat(f64, value);
        return;
    }

    if (std.mem.eql(u8, key, "relative_azimuth_deg")) {
        prepared.scene.geometry.relative_azimuth_deg = try std.fmt.parseFloat(f64, value);
        return;
    }

    if (std.mem.eql(u8, key, "instrument")) {
        prepared.scene.observation_model.instrument = value;
        return;
    }

    if (std.mem.eql(u8, key, "sampling")) {
        prepared.scene.observation_model.sampling = value;
        return;
    }

    if (std.mem.eql(u8, key, "noise_model")) {
        prepared.scene.observation_model.noise_model = value;
        return;
    }

    if (std.mem.eql(u8, key, "derivative_mode")) {
        prepared.plan_template.scene_blueprint.derivative_mode = try parseDerivativeMode(value);
        return;
    }

    if (std.mem.eql(u8, key, "requested_product") or std.mem.eql(u8, key, "requested_products")) {
        try appendRequestedProducts(allocator, &prepared.requested_products, value);
        return;
    }

    if (std.mem.eql(u8, key, "diagnostics.provenance")) {
        prepared.diagnostics.provenance = try parseBool(value);
        return;
    }

    if (std.mem.eql(u8, key, "diagnostics.jacobians")) {
        prepared.diagnostics.jacobians = try parseBool(value);
        return;
    }

    if (std.mem.eql(u8, key, "diagnostics.internal_fields")) {
        prepared.diagnostics.internal_fields = try parseBool(value);
        return;
    }

    if (std.mem.eql(u8, key, "diagnostics.materialize_cache_keys")) {
        prepared.diagnostics.materialize_cache_keys = try parseBool(value);
        return;
    }

    return ParseError.UnknownKey;
}

fn appendRequestedProducts(
    allocator: std.mem.Allocator,
    products: *std.ArrayListUnmanaged([]const u8),
    value: []const u8,
) !void {
    var items = std.mem.splitScalar(u8, value, ',');
    while (items.next()) |raw_item| {
        const item = trimWhitespace(raw_item);
        if (item.len == 0) continue;
        try products.append(allocator, item);
    }
}

fn trimWhitespace(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r");
}

fn parseBool(value: []const u8) !bool {
    if (std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes") or
        std.mem.eql(u8, value, "1"))
    {
        return true;
    }

    if (std.ascii.eqlIgnoreCase(value, "false") or
        std.ascii.eqlIgnoreCase(value, "no") or
        std.mem.eql(u8, value, "0"))
    {
        return false;
    }

    return ParseError.InvalidBoolean;
}

fn parseSolverMode(value: []const u8) !zdisamar.SolverMode {
    if (std.mem.eql(u8, value, "scalar")) return .scalar;
    if (std.mem.eql(u8, value, "polarized")) return .polarized;
    if (std.mem.eql(u8, value, "derivative_enabled")) return .derivative_enabled;
    return ParseError.InvalidSolverMode;
}

fn parseDerivativeMode(value: []const u8) ParseError!zdisamar.DerivativeMode {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "semi_analytical")) return .semi_analytical;
    if (std.mem.eql(u8, value, "analytical_plugin")) return .analytical_plugin;
    if (std.mem.eql(u8, value, "numerical")) return .numerical;
    return ParseError.InvalidLine;
}

test "legacy config parser maps fields onto typed runtime inputs" {
    const fixture =
        \\# sample legacy configuration
        \\workspace = import-smoke
        \\model_family = disamar_standard
        \\transport = transport.dispatcher
        \\retrieval = none
        \\solver_mode = polarized
        \\scene_id = s5p-no2
        \\spectral_start_nm = 405.0
        \\spectral_end_nm = 465.0
        \\spectral_samples = 121
        \\atmosphere_layers = 48
        \\has_clouds = yes
        \\has_aerosols = no
        \\solar_zenith_deg = 32.5
        \\viewing_zenith_deg = 9.0
        \\relative_azimuth_deg = 145.0
        \\instrument = tropomi
        \\sampling = native
        \\noise_model = shot_noise
        \\derivative_mode = semi_analytical
        \\requested_products = radiance, slant_column
        \\diagnostics.provenance = true
        \\diagnostics.jacobians = true
    ;

    var prepared = try parse(std.testing.allocator, fixture);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("import-smoke", prepared.workspace_label);
    try std.testing.expectEqualStrings("disamar_standard", prepared.plan_template.model_family);
    try std.testing.expectEqual(zdisamar.SolverMode.polarized, prepared.plan_template.solver_mode);
    try std.testing.expectEqualStrings("s5p-no2", prepared.scene.id);
    try std.testing.expectEqual(@as(u32, 121), prepared.scene.spectral_grid.sample_count);
    try std.testing.expect(prepared.scene.atmosphere.has_clouds);
    try std.testing.expect(!prepared.scene.atmosphere.has_aerosols);
    try std.testing.expect(prepared.diagnostics.jacobians);
    try std.testing.expectEqual(@as(usize, 2), prepared.requested_products.items.len);
    try std.testing.expectEqualStrings("radiance", prepared.requested_products.items[0]);
    try std.testing.expectEqualStrings("slant_column", prepared.requested_products.items[1]);
    try std.testing.expectEqual(zdisamar.DerivativeMode.semi_analytical, prepared.plan_template.scene_blueprint.derivative_mode);

    const request = prepared.toRequest();
    try std.testing.expectEqualStrings("s5p-no2", request.scene.id);
    try std.testing.expect(request.diagnostics.jacobians);
    try std.testing.expectEqual(@as(usize, 2), request.requested_products.len);
    try std.testing.expectEqual(zdisamar.DerivativeMode.semi_analytical, request.expected_derivative_mode.?);
}
