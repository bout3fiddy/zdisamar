const std = @import("std");
const zdisamar = @import("zdisamar");
const legacy_config = @import("legacy_config");

pub const CliError = error{
    MissingValue,
    UnknownOption,
};

pub const Overrides = struct {
    workspace_label: ?[]const u8 = null,
    config_path: ?[]const u8 = null,
    scene_id: ?[]const u8 = null,
    model_family: ?[]const u8 = null,
    transport: ?[]const u8 = null,
    retrieval: ?[]const u8 = null,
    solver_mode: ?zdisamar.SolverMode = null,
    diagnostics: DiagnosticOverrides = .{},
    show_help: bool = false,
    requested_products: std.ArrayListUnmanaged([]const u8) = .{},

    pub fn deinit(self: *Overrides, allocator: std.mem.Allocator) void {
        self.requested_products.deinit(allocator);
        self.* = .{};
    }
};

pub const DiagnosticOverrides = struct {
    jacobians: ?bool = null,
    internal_fields: ?bool = null,
    materialize_cache_keys: ?bool = null,
};

pub fn run(allocator: std.mem.Allocator, argv: []const []const u8, writer: anytype) !void {
    var overrides = try parseArgs(allocator, argv);
    defer overrides.deinit(allocator);

    if (overrides.show_help) {
        try printHelp(writer);
        return;
    }

    var config_bytes: ?[]u8 = null;
    defer if (config_bytes) |bytes| allocator.free(bytes);

    var prepared = legacy_config.PreparedRun{};
    defer prepared.deinit(allocator);

    if (overrides.config_path) |config_path| {
        config_bytes = try std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024);
        prepared = try legacy_config.parse(allocator, config_bytes.?);
    }

    try applyOverrides(allocator, &prepared, &overrides);

    var engine = zdisamar.Engine.init(allocator, .{});
    defer engine.deinit();

    try engine.bootstrapBuiltinCatalog();

    const plan = try engine.preparePlan(prepared.plan_template);
    var workspace = engine.createWorkspace(prepared.workspace_label);
    const request = prepared.toRequest();
    var result = try engine.execute(&plan, &workspace, request);
    defer result.deinit(allocator);

    try writer.print(
        "zdisamar adapter run: workspace={s} scene={s} model={s} plan_id={d} status={s} route={s}\n",
        .{
            prepared.workspace_label,
            result.scene_id,
            result.provenance.model_family,
            result.plan_id,
            @tagName(result.status),
            result.provenance.solver_route,
        },
    );
}

pub fn parseArgs(allocator: std.mem.Allocator, argv: []const []const u8) !Overrides {
    var overrides = Overrides{};
    errdefer overrides.deinit(allocator);

    var index: usize = 1;
    while (index < argv.len) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            overrides.show_help = true;
            index += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, "--config")) {
            overrides.config_path = try nextValue(argv, &index);
            continue;
        }

        if (std.mem.eql(u8, arg, "--workspace")) {
            overrides.workspace_label = try nextValue(argv, &index);
            continue;
        }

        if (std.mem.eql(u8, arg, "--scene")) {
            overrides.scene_id = try nextValue(argv, &index);
            continue;
        }

        if (std.mem.eql(u8, arg, "--model-family")) {
            overrides.model_family = try nextValue(argv, &index);
            continue;
        }

        if (std.mem.eql(u8, arg, "--transport")) {
            overrides.transport = try nextValue(argv, &index);
            continue;
        }

        if (std.mem.eql(u8, arg, "--retrieval")) {
            overrides.retrieval = try nextValue(argv, &index);
            continue;
        }

        if (std.mem.eql(u8, arg, "--solver-mode")) {
            overrides.solver_mode = try parseSolverMode(try nextValue(argv, &index));
            continue;
        }

        if (std.mem.eql(u8, arg, "--product")) {
            try overrides.requested_products.append(allocator, try nextValue(argv, &index));
            continue;
        }

        if (std.mem.eql(u8, arg, "--jacobians")) {
            overrides.diagnostics.jacobians = true;
            index += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, "--internal-fields")) {
            overrides.diagnostics.internal_fields = true;
            index += 1;
            continue;
        }

        if (std.mem.eql(u8, arg, "--materialize-cache-keys")) {
            overrides.diagnostics.materialize_cache_keys = true;
            index += 1;
            continue;
        }

        return CliError.UnknownOption;
    }

    return overrides;
}

fn nextValue(argv: []const []const u8, index: *usize) ![]const u8 {
    const value_index = index.* + 1;
    if (value_index >= argv.len) return CliError.MissingValue;
    index.* = value_index + 1;
    return argv[value_index];
}

fn applyOverrides(
    allocator: std.mem.Allocator,
    prepared: *legacy_config.PreparedRun,
    overrides: *Overrides,
) !void {
    if (overrides.workspace_label) |workspace_label| prepared.workspace_label = workspace_label;
    if (overrides.scene_id) |scene_id| {
        prepared.scene.id = scene_id;
        prepared.plan_template.scene_blueprint.id = scene_id;
    }
    if (overrides.model_family) |model_family| prepared.plan_template.model_family = model_family;
    if (overrides.transport) |transport| prepared.plan_template.transport = transport;
    if (overrides.retrieval) |retrieval| {
        prepared.plan_template.retrieval = if (std.mem.eql(u8, retrieval, "none")) null else retrieval;
    }
    if (overrides.solver_mode) |solver_mode| prepared.plan_template.solver_mode = solver_mode;
    if (overrides.diagnostics.jacobians) |jacobians| prepared.diagnostics.jacobians = jacobians;
    if (overrides.diagnostics.internal_fields) |internal_fields| prepared.diagnostics.internal_fields = internal_fields;
    if (overrides.diagnostics.materialize_cache_keys) |materialize_cache_keys| {
        prepared.diagnostics.materialize_cache_keys = materialize_cache_keys;
    }

    if (overrides.requested_products.items.len != 0) {
        prepared.requested_products.deinit(allocator);
        prepared.requested_products = overrides.requested_products;
        overrides.requested_products = .{};
    }
}

fn parseSolverMode(value: []const u8) !zdisamar.SolverMode {
    if (std.mem.eql(u8, value, "scalar")) return .scalar;
    if (std.mem.eql(u8, value, "polarized")) return .polarized;
    if (std.mem.eql(u8, value, "derivative_enabled")) return .derivative_enabled;
    return legacy_config.ParseError.InvalidSolverMode;
}

fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: zdisamar [--config PATH] [--workspace LABEL] [--scene ID]
        \\                [--model-family NAME] [--transport NAME]
        \\                [--retrieval NAME|none] [--solver-mode MODE]
        \\                [--product NAME] [--jacobians]
        \\                [--internal-fields] [--materialize-cache-keys]
        \\
        \\The CLI is an adapter over the typed Engine -> Plan -> Workspace -> Request -> Result API.
        \\Legacy Config.in-style files can be translated with --config.
        \\
    );
}

test "cli parser captures config path and typed overrides" {
    const argv = [_][]const u8{
        "zdisamar",
        "--config",
        "data/examples/legacy_config.in",
        "--workspace",
        "cli",
        "--scene",
        "scene-inline",
        "--solver-mode",
        "polarized",
        "--product",
        "radiance",
        "--jacobians",
    };

    var parsed = try parseArgs(std.testing.allocator, &argv);
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("data/examples/legacy_config.in", parsed.config_path.?);
    try std.testing.expectEqualStrings("cli", parsed.workspace_label.?);
    try std.testing.expectEqualStrings("scene-inline", parsed.scene_id.?);
    try std.testing.expectEqual(zdisamar.SolverMode.polarized, parsed.solver_mode.?);
    try std.testing.expect(parsed.diagnostics.jacobians.?);
    try std.testing.expectEqual(@as(usize, 1), parsed.requested_products.items.len);
    try std.testing.expectEqualStrings("radiance", parsed.requested_products.items[0]);
}
