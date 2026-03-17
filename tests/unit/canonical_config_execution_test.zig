const std = @import("std");
const zdisamar = @import("zdisamar");

fn resolveExperiment(source: []const u8) !*zdisamar.canonical_config.ResolvedExperiment {
    var document = try zdisamar.canonical_config.Document.parse(
        std.testing.allocator,
        "inline.yaml",
        ".",
        source,
    );
    defer document.deinit();
    return document.resolve(std.testing.allocator);
}

test "canonical execution rejects diagnostics outputs as unsupported targets" {
    const source =
        \\schema_version: 1
        \\
        \\metadata:
        \\  id: unsupported-output
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
        \\        albedo: 0.05
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
        \\      truth_diagnostics:
        \\        kind: diagnostics
        \\
        \\outputs:
        \\  - from: truth_diagnostics
        \\    format: zarr
        \\    destination_uri: file://out/diag.zarr
        \\
        \\validation:
        \\  strict_unknown_fields: true
        \\  require_resolved_stage_references: true
    ;

    var experiment = try resolveExperiment(source);
    defer experiment.deinit();

    try std.testing.expectError(
        zdisamar.canonical_config.execution.Error.UnsupportedOutputTarget,
        zdisamar.canonical_config.compileResolved(std.testing.allocator, experiment),
    );
}

test "canonical measurement binding reports unresolved stage references" {
    const source =
        \\schema_version: 1
        \\
        \\metadata:
        \\  id: unresolved-binding
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
        \\      measurement:
        \\        source: missing_truth
        \\        observable: radiance
        \\      state:
        \\        surface_albedo:
        \\          target: scene.surface.albedo
        \\          prior:
        \\            mean: 0.05
        \\            sigma: 0.02
        \\    products:
        \\      retrieved_state:
        \\        kind: state_vector
        \\
        \\outputs: []
        \\
        \\validation:
        \\  strict_unknown_fields: true
        \\  require_resolved_stage_references: true
    ;

    try std.testing.expectError(
        zdisamar.canonical_config.Error.MissingStageProduct,
        resolveExperiment(source),
    );
}
