const std = @import("std");
const zdisamar = @import("zdisamar");
const legacy_config = @import("legacy_config");

test "legacy import preserves flat adapter semantics through canonical execution" {
    const source =
        \\workspace = import-smoke
        \\model_family = disamar_standard
        \\transport = transport.dispatcher
        \\retrieval = none
        \\solver_mode = scalar
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

    var prepared = try legacy_config.parse(std.testing.allocator, source);
    defer prepared.deinit(std.testing.allocator);

    var imported = try legacy_config.importSource(std.testing.allocator, "legacy_config.in", source);
    defer imported.deinit(std.testing.allocator);

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    if (std.mem.endsWith(u8, prepared.plan_template.providers.transport_solver, "dispatcher")) {
        prepared.plan_template.providers.transport_solver = "builtin.dispatcher";
    }
    var legacy_plan = try engine.preparePlan(prepared.plan_template);
    defer legacy_plan.deinit();
    var legacy_workspace = engine.createWorkspace(prepared.workspace_label);
    var legacy_request = prepared.toRequest();
    var legacy_result = try engine.execute(&legacy_plan, &legacy_workspace, &legacy_request);
    defer legacy_result.deinit(std.testing.allocator);

    var document = try zdisamar.canonical_config.Document.parse(
        std.testing.allocator,
        "imported.yaml",
        ".",
        imported.yaml,
    );
    defer document.deinit();

    var resolved: ?*zdisamar.canonical_config.ResolvedExperiment = try document.resolve(std.testing.allocator);
    errdefer if (resolved) |owned| owned.deinit();
    const program = try zdisamar.canonical_config.compileResolved(std.testing.allocator, resolved.?);
    resolved = null;
    defer {
        var owned = program;
        owned.deinit();
    }

    var canonical_outcome = try program.execute(std.testing.allocator, &engine);
    defer canonical_outcome.deinit();

    try std.testing.expectEqual(@as(usize, 1), canonical_outcome.stage_outcomes.len);
    const canonical_result = canonical_outcome.stage_outcomes[0].result;
    try std.testing.expectEqual(legacy_result.status, canonical_result.status);
    try std.testing.expectEqualStrings(legacy_result.workspace_label, canonical_result.workspace_label);
    try std.testing.expectEqualStrings(legacy_result.scene_id, canonical_result.scene_id);
    try std.testing.expectEqualStrings(legacy_result.provenance.model_family, canonical_result.provenance.model_family);
    try std.testing.expectEqualStrings(legacy_result.provenance.solver_route, canonical_result.provenance.solver_route);
    try std.testing.expect(legacy_result.measurement_space != null);
    try std.testing.expect(canonical_result.measurement_space != null);
    try std.testing.expectEqual(
        legacy_result.measurement_space.?.sample_count,
        canonical_result.measurement_space.?.sample_count,
    );
}
