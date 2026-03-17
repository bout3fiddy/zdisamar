const std = @import("std");
const zdisamar = @import("zdisamar");
const legacy_config = @import("legacy_config");

pub const CliError = error{
    MissingCommand,
    UnknownOption,
    UnknownCommand,
    UnexpectedArgument,
};

pub const Command = union(enum) {
    help,
    run: []const u8,
    config_validate: []const u8,
    config_resolve: []const u8,
    config_import: []const u8,
};

pub fn run(allocator: std.mem.Allocator, argv: []const []const u8, stdout: anytype, stderr: anytype) !void {
    const command = try parseArgs(argv);
    switch (command) {
        .help => try printHelp(stdout),
        .run => |path| try runCanonicalConfig(allocator, path, stdout, stderr),
        .config_validate => |path| try validateCanonicalConfig(allocator, path, stdout, stderr),
        .config_resolve => |path| try resolveCanonicalConfig(allocator, path, stdout, stderr),
        .config_import => |path| try importLegacyConfig(allocator, path, stdout, stderr),
    }
}

pub fn parseArgs(argv: []const []const u8) !Command {
    if (argv.len <= 1) return .help;
    if (isHelp(argv[1])) return .help;

    if (std.mem.eql(u8, argv[1], "run")) {
        if (argv.len < 3) return CliError.MissingCommand;
        if (argv.len != 3) return CliError.UnexpectedArgument;
        return .{ .run = argv[2] };
    }

    if (std.mem.eql(u8, argv[1], "config")) {
        if (argv.len == 2 or isHelp(argv[2])) return .help;
        if (argv.len != 4) return CliError.UnexpectedArgument;
        if (std.mem.eql(u8, argv[2], "validate")) return .{ .config_validate = argv[3] };
        if (std.mem.eql(u8, argv[2], "resolve")) return .{ .config_resolve = argv[3] };
        if (std.mem.eql(u8, argv[2], "import")) return .{ .config_import = argv[3] };
        return CliError.UnknownCommand;
    }

    return CliError.UnknownOption;
}

fn runCanonicalConfig(allocator: std.mem.Allocator, path: []const u8, stdout: anytype, stderr: anytype) !void {
    var engine = zdisamar.Engine.init(allocator, .{});
    defer engine.deinit();

    try engine.bootstrapBuiltinCatalog();

    var execution = try zdisamar.canonical_config.resolveCompileAndExecute(allocator, &engine, path);
    defer {
        execution.outcome.deinit();
        execution.program.deinit();
    }

    try emitCanonicalWarnings(execution.program.experiment.warnings, stderr);
    try stdout.print(
        "zdisamar run: source={s} workspace={s} stages={d} outputs={d} warnings={d} status={s}\n",
        .{
            execution.program.experiment.source_path,
            effectiveWorkspace(execution.program.experiment),
            execution.outcome.stage_outcomes.len,
            execution.outcome.outputs.len,
            execution.program.experiment.warnings.len,
            overallStatus(&execution.outcome),
        },
    );

    for (execution.outcome.stage_outcomes, 0..) |stage_outcome, index| {
        const stage_execution = execution.program.stages[index];
        try stdout.print(
            "  stage={s} scene={s} model={s} plan_id={d} status={s} route={s}\n",
            .{
                @tagName(stage_execution.kind),
                stage_outcome.result.scene_id,
                stage_outcome.result.provenance.model_family,
                stage_outcome.result.plan_id,
                @tagName(stage_outcome.result.status),
                stage_outcome.result.provenance.solver_route,
            },
        );
    }
}

fn validateCanonicalConfig(allocator: std.mem.Allocator, path: []const u8, stdout: anytype, stderr: anytype) !void {
    var experiment = try zdisamar.canonical_config.resolveFile(allocator, path);
    defer experiment.deinit();

    try emitCanonicalWarnings(experiment.warnings, stderr);
    try stdout.print(
        "zdisamar config validate: source={s} stages={d} outputs={d} warnings={d} status=valid\n",
        .{
            experiment.source_path,
            stageCount(experiment),
            experiment.outputs.len,
            experiment.warnings.len,
        },
    );
}

fn resolveCanonicalConfig(allocator: std.mem.Allocator, path: []const u8, stdout: anytype, stderr: anytype) !void {
    var experiment = try zdisamar.canonical_config.resolveFile(allocator, path);
    defer experiment.deinit();

    try emitCanonicalWarnings(experiment.warnings, stderr);
    try stdout.print(
        "source: {s}\nmetadata:\n  id: {s}\n  workspace: {s}\nstages:\n",
        .{
            experiment.source_path,
            experiment.metadata.id,
            effectiveWorkspace(experiment),
        },
    );
    if (experiment.simulation) |stage| {
        try stdout.print(
            "  - kind: {s}\n    scene_id: {s}\n    model_family: {s}\n    transport_provider: {s}\n    solver_mode: {s}\n    derivative_mode: {s}\n",
            .{
                "simulation",
                stage.scene.id,
                stage.plan.model_family,
                stage.plan.providers.transport_solver,
                @tagName(stage.plan.solver_mode),
                @tagName(stage.plan.scene_blueprint.derivative_mode),
            },
        );
        if (stage.plan.providers.retrieval_algorithm) |provider| {
            try stdout.print("    retrieval_provider: {s}\n", .{provider});
        }
        if (stage.products.len == 0) {
            try stdout.writeAll("    products: []\n");
        } else {
            try stdout.writeAll("    products:\n");
            for (stage.products) |product| {
                try stdout.print("      - name: {s}\n        kind: {s}\n", .{ product.name, @tagName(product.kind) });
                if (product.observable.len != 0) {
                    try stdout.print("        observable: {s}\n", .{product.observable});
                }
            }
        }
    }
    if (experiment.retrieval) |stage| {
        try stdout.print(
            "  - kind: {s}\n    scene_id: {s}\n    model_family: {s}\n    transport_provider: {s}\n    solver_mode: {s}\n    derivative_mode: {s}\n",
            .{
                "retrieval",
                stage.scene.id,
                stage.plan.model_family,
                stage.plan.providers.transport_solver,
                @tagName(stage.plan.solver_mode),
                @tagName(stage.plan.scene_blueprint.derivative_mode),
            },
        );
        if (stage.plan.providers.retrieval_algorithm) |provider| {
            try stdout.print("    retrieval_provider: {s}\n", .{provider});
        }
        if (stage.products.len == 0) {
            try stdout.writeAll("    products: []\n");
        } else {
            try stdout.writeAll("    products:\n");
            for (stage.products) |product| {
                try stdout.print("      - name: {s}\n        kind: {s}\n", .{ product.name, @tagName(product.kind) });
                if (product.observable.len != 0) {
                    try stdout.print("        observable: {s}\n", .{product.observable});
                }
            }
        }
    }

    if (experiment.outputs.len == 0) {
        try stdout.writeAll("outputs: []\n");
    } else {
        try stdout.writeAll("outputs:\n");
        for (experiment.outputs) |output| {
            try stdout.print(
                "  - from: {s}\n    kind: {s}\n    format: {s}\n    destination_uri: {s}\n",
                .{
                    output.from,
                    @tagName(findOutputKind(experiment, output.from) orelse .diagnostics),
                    @tagName(output.format),
                    output.destination_uri,
                },
            );
        }
    }
}

fn importLegacyConfig(allocator: std.mem.Allocator, path: []const u8, stdout: anytype, stderr: anytype) !void {
    var imported = try legacy_config.importFile(allocator, path);
    defer imported.deinit(allocator);

    try emitImportWarnings(imported.warnings, stderr);
    try stdout.writeAll(imported.yaml);
}

fn emitCanonicalWarnings(warnings: anytype, stderr: anytype) !void {
    for (warnings) |warning| {
        try stderr.print("warning: {s}\n", .{warning.message});
    }
}

fn emitImportWarnings(warnings: []const legacy_config.ImportWarning, stderr: anytype) !void {
    for (warnings) |warning| {
        try stderr.print("warning: {s}\n", .{warning.message});
    }
}

fn effectiveWorkspace(experiment: *const zdisamar.canonical_config.ResolvedExperiment) []const u8 {
    if (experiment.metadata.workspace.len != 0) return experiment.metadata.workspace;
    if (experiment.metadata.id.len != 0) return experiment.metadata.id;
    return "canonical-config";
}

fn stageCount(experiment: *const zdisamar.canonical_config.ResolvedExperiment) usize {
    var count: usize = 0;
    if (experiment.simulation != null) count += 1;
    if (experiment.retrieval != null) count += 1;
    return count;
}

fn findOutputKind(experiment: *const zdisamar.canonical_config.ResolvedExperiment, name: []const u8) ?zdisamar.canonical_config.ProductKind {
    return if (experiment.findProduct(name)) |product| product.kind else null;
}

fn overallStatus(outcome: *const zdisamar.canonical_config.ExecutionOutcome) []const u8 {
    for (outcome.stage_outcomes) |stage_outcome| {
        if (stage_outcome.result.status != .success) return @tagName(stage_outcome.result.status);
    }
    return "success";
}

fn isHelp(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--help") or
        std.mem.eql(u8, arg, "-h") or
        std.mem.eql(u8, arg, "help");
}

fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage:
        \\  zdisamar run CONFIG.yaml
        \\  zdisamar config validate CONFIG.yaml
        \\  zdisamar config resolve CONFIG.yaml
        \\  zdisamar config import legacy_config.in
        \\
        \\Canonical YAML is the runtime entrypoint.
        \\Legacy Config.in support is import-only migration output on stdout.
        \\
    );
}

test "cli parser captures canonical command surface" {
    const argv = [_][]const u8{
        "zdisamar",
        "config",
        "import",
        "data/examples/legacy_config.in",
    };

    const parsed = try parseArgs(&argv);
    switch (parsed) {
        .config_import => |path| try std.testing.expectEqualStrings("data/examples/legacy_config.in", path),
        else => return error.TestUnexpectedResult,
    }
}

test "cli parser captures run command" {
    const argv = [_][]const u8{
        "zdisamar",
        "run",
        "data/examples/canonical_config.yaml",
    };

    const parsed = try parseArgs(&argv);
    switch (parsed) {
        .run => |path| try std.testing.expectEqualStrings("data/examples/canonical_config.yaml", path),
        else => return error.TestUnexpectedResult,
    }
}
