const std = @import("std");
const zdisamar = @import("zdisamar");

fn makeOutputRoot(prefix: []const u8, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "zig-cache/canonical-config-exec/{s}-{d}",
        .{ prefix, @as(u64, @intCast(@abs(std.time.nanoTimestamp()))) },
    );
}

fn replaceAllAlloc(
    allocator: std.mem.Allocator,
    haystack: []const u8,
    needle: []const u8,
    replacement: []const u8,
) ![]u8 {
    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);

    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, cursor, needle)) |match_index| {
        try output.appendSlice(allocator, haystack[cursor..match_index]);
        try output.appendSlice(allocator, replacement);
        cursor = match_index + needle.len;
    }
    try output.appendSlice(allocator, haystack[cursor..]);
    return output.toOwnedSlice(allocator);
}

fn executeResolvedSource(
    source_name: []const u8,
    base_dir: []const u8,
    source: []const u8,
    engine: *zdisamar.Engine,
) !struct { program: zdisamar.canonical_config.ExecutionProgram, outcome: zdisamar.canonical_config.ExecutionOutcome } {
    var document = try zdisamar.canonical_config.Document.parse(
        std.testing.allocator,
        source_name,
        base_dir,
        source,
    );
    defer document.deinit();

    const resolved = try document.resolve(std.testing.allocator);
    const program = try zdisamar.canonical_config.compileResolved(std.testing.allocator, resolved);
    errdefer {
        var owned = program;
        owned.deinit();
    }
    const outcome = try program.execute(std.testing.allocator, engine);
    return .{ .program = program, .outcome = outcome };
}

test "canonical execution runs a forward-only program and writes outputs" {
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = try makeOutputRoot("forward", &root_buffer);
    defer std.fs.cwd().deleteTree(root) catch {};

    const yaml = try std.fmt.allocPrint(
        std.testing.allocator,
        \\schema_version: 1
        \\
        \\metadata:
        \\  id: forward-only
        \\  workspace: exec-forward
        \\
        \\templates:
        \\  base:
        \\    plan:
        \\      model_family: disamar_standard
        \\      transport:
        \\        solver: dispatcher
        \\      execution:
        \\        solver_mode: scalar
        \\        derivative_mode: none
        \\    scene:
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 30.0
        \\        viewing_zenith_deg: 8.0
        \\        relative_azimuth_deg: 145.0
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 16
        \\      bands:
        \\        band_1:
        \\          start_nm: 405.0
        \\          end_nm: 465.0
        \\          step_nm: 2.5
        \\      absorbers:
        \\        o2:
        \\          species: o2
        \\          spectroscopy:
        \\            model: cross_sections
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.07
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
        \\        sampling:
        \\          mode: native
        \\
        \\experiment:
        \\  simulation:
        \\    from: base
        \\    scene:
        \\      id: truth_scene
        \\    products:
        \\      truth_radiance:
        \\        kind: measurement_space
        \\        observable: radiance
        \\
        \\outputs:
        \\  - from: truth_radiance
        \\    format: netcdf_cf
        \\    destination_uri: file://{s}/truth.nc
        \\
        \\validation:
        \\  strict_unknown_fields: true
        \\  require_resolved_stage_references: true
    ,
        .{root},
    );
    defer std.testing.allocator.free(yaml);

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const execution = try executeResolvedSource("forward.yaml", ".", yaml, &engine);
    defer {
        var outcome = execution.outcome;
        outcome.deinit();
        var program = execution.program;
        program.deinit();
    }

    try std.testing.expectEqual(@as(usize, 1), execution.outcome.stage_outcomes.len);
    try std.testing.expect(execution.outcome.stage_outcomes[0].result.measurement_space_product != null);
    try std.testing.expectEqual(@as(usize, 1), execution.outcome.outputs.len);
    const truth_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/truth.nc", .{root});
    defer std.testing.allocator.free(truth_path);
    try std.fs.cwd().access(truth_path, .{});
}

test "canonical execution runs a retrieval-only program" {
    const yaml =
        \\schema_version: 1
        \\
        \\metadata:
        \\  id: retrieval-only
        \\  workspace: exec-retrieval
        \\
        \\templates:
        \\  base:
        \\    plan:
        \\      model_family: disamar_standard
        \\      transport:
        \\        solver: dispatcher
        \\      execution:
        \\        solver_mode: scalar
        \\        derivative_mode: semi_analytical
        \\    scene:
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 30.0
        \\        viewing_zenith_deg: 8.0
        \\        relative_azimuth_deg: 145.0
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 16
        \\      bands:
        \\        band_1:
        \\          start_nm: 405.0
        \\          end_nm: 465.0
        \\          step_nm: 2.5
        \\      absorbers:
        \\        o2:
        \\          species: o2
        \\          spectroscopy:
        \\            model: cross_sections
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
        \\        sampling:
        \\          mode: native
        \\
        \\experiment:
        \\  retrieval:
        \\    from: base
        \\    scene:
        \\      id: retrieval_scene
        \\    inverse:
        \\      algorithm:
        \\        name: oe
        \\        provider: builtin.oe_solver
        \\      measurement:
        \\        source: observed_radiance
        \\        observable: radiance
        \\      state:
        \\        surface_albedo:
        \\          target: scene.surface.albedo
        \\          prior:
        \\            mean: 0.05
        \\            sigma: 0.02
        \\        aerosol_tau:
        \\          target: scene.aerosols.plume.optical_depth_550_nm
        \\          prior:
        \\            mean: 0.10
        \\            sigma: 0.05
        \\    products:
        \\      retrieved_state:
        \\        kind: state_vector
        \\      fitted_radiance:
        \\        kind: fitted_measurement
        \\      jacobian:
        \\        kind: jacobian
        \\
        \\outputs: []
        \\
        \\validation:
        \\  strict_unknown_fields: true
    ;

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const execution = try executeResolvedSource("retrieval.yaml", ".", yaml, &engine);
    defer {
        var outcome = execution.outcome;
        outcome.deinit();
        var program = execution.program;
        program.deinit();
    }

    try std.testing.expectEqual(@as(usize, 1), execution.outcome.stage_outcomes.len);
    const result = execution.outcome.stage_outcomes[0].result;
    try std.testing.expect(result.retrieval != null);
    try std.testing.expect(result.retrieval_products.state_vector != null);
    try std.testing.expect(result.retrieval_products.fitted_measurement != null);
    try std.testing.expect(result.retrieval_products.jacobian != null);
}

test "canonical execution runs revised twin examples with routed outputs" {
    var common_root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const common_root = try makeOutputRoot("common", &common_root_buffer);
    defer std.fs.cwd().deleteTree(common_root) catch {};

    var expert_root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const expert_root = try makeOutputRoot("expert", &expert_root_buffer);
    defer std.fs.cwd().deleteTree(expert_root) catch {};

    const common_bytes = try std.fs.cwd().readFileAlloc(
        std.testing.allocator,
        "data/examples/zdisamar_common_use.yaml",
        64 * 1024,
    );
    defer std.testing.allocator.free(common_bytes);
    const common_replacement = try std.fmt.allocPrint(std.testing.allocator, "file://{s}/", .{common_root});
    defer std.testing.allocator.free(common_replacement);
    const common_yaml = try replaceAllAlloc(std.testing.allocator, common_bytes, "file://out/", common_replacement);
    defer std.testing.allocator.free(common_yaml);

    const expert_bytes = try std.fs.cwd().readFileAlloc(
        std.testing.allocator,
        "data/examples/zdisamar_expert_o2a.yaml",
        128 * 1024,
    );
    defer std.testing.allocator.free(expert_bytes);
    const expert_replacement = try std.fmt.allocPrint(std.testing.allocator, "file://{s}/", .{expert_root});
    defer std.testing.allocator.free(expert_replacement);
    const expert_yaml = try replaceAllAlloc(std.testing.allocator, expert_bytes, "file://out/", expert_replacement);
    defer std.testing.allocator.free(expert_yaml);

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const common_execution = try executeResolvedSource(
        "zdisamar_common_use.yaml",
        "data/examples",
        common_yaml,
        &engine,
    );
    defer {
        var outcome = common_execution.outcome;
        outcome.deinit();
        var program = common_execution.program;
        program.deinit();
    }

    try std.testing.expectEqual(@as(usize, 2), common_execution.outcome.stage_outcomes.len);
    try std.testing.expectEqual(@as(usize, 2), common_execution.outcome.outputs.len);
    try std.testing.expect(common_execution.outcome.stage_outcomes[1].result.retrieval_products.state_vector != null);

    const expert_execution = try executeResolvedSource(
        "zdisamar_expert_o2a.yaml",
        "data/examples",
        expert_yaml,
        &engine,
    );
    defer {
        var outcome = expert_execution.outcome;
        outcome.deinit();
        var program = expert_execution.program;
        program.deinit();
    }

    try std.testing.expectEqual(@as(usize, 2), expert_execution.outcome.stage_outcomes.len);
    try std.testing.expectEqual(@as(usize, 3), expert_execution.outcome.outputs.len);
    const expert_result = expert_execution.outcome.stage_outcomes[1].result;
    try std.testing.expect(expert_result.retrieval_products.state_vector != null);
    try std.testing.expect(expert_result.retrieval_products.fitted_measurement != null);
    try std.testing.expect(expert_result.retrieval_products.averaging_kernel != null);
    try std.testing.expect(expert_result.retrieval_products.jacobian != null);
}
