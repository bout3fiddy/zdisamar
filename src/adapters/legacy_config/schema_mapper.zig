const std = @import("std");
const zdisamar = @import("zdisamar");

pub const ParseError = error{
    InvalidLine,
    UnknownKey,
    InvalidBoolean,
    InvalidSolverMode,
};

pub const PreparedRun = struct {
    owned_contents: ?[]u8 = null,
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
        if (self.owned_contents) |contents| allocator.free(contents);
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

pub fn finalize(prepared: *PreparedRun) void {
    prepared.plan_template.scene_blueprint.id = prepared.scene.id;
    prepared.plan_template.scene_blueprint.spectral_grid = prepared.scene.spectral_grid;
}

pub fn applyValue(
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
        prepared.plan_template.providers.transport_solver = value;
        return;
    }

    if (std.mem.eql(u8, key, "retrieval")) {
        prepared.plan_template.providers.retrieval_algorithm = if (std.mem.eql(u8, value, "none")) null else value;
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
        prepared.scene.observation_model.sampling = try zdisamar.Instrument.SamplingMode.parse(value);
        return;
    }

    if (std.mem.eql(u8, key, "noise_model")) {
        prepared.scene.observation_model.noise_model = try zdisamar.Instrument.NoiseModelKind.parse(value);
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

pub fn trimWhitespace(value: []const u8) []const u8 {
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
