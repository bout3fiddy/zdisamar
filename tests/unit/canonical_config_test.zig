const std = @import("std");
const zdisamar = @import("zdisamar");

test "canonical config rejects unresolved stage product references in strict mode" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: missing-stage-product
        \\experiment:
        \\  simulation:
        \\    scene:
        \\      id: truth_scene
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        o2a:
        \\          start_nm: 758.0
        \\          end_nm: 759.0
        \\          step_nm: 0.5
        \\      absorbers:
        \\        o2:
        \\          species: o2
        \\          spectroscopy:
        \\            model: line_by_line
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: tropomi
        \\    products:
        \\      truth_radiance:
        \\        kind: measurement_space
        \\        observable: radiance
        \\  retrieval:
        \\    from: experiment.simulation
        \\    scene:
        \\      id: retrieval_scene
        \\    inverse:
        \\      algorithm:
        \\        name: oe
        \\      measurement:
        \\        source: missing_product
        \\        observable: radiance
        \\      state:
        \\        surface_albedo:
        \\          target: scene.surface.albedo
        \\          prior:
        \\            mean: 0.04
        \\            sigma: 0.02
        \\validation:
        \\  strict_unknown_fields: true
        \\  require_resolved_stage_references: true
    ;

    var document = try zdisamar.canonical_config.Document.parse(
        std.testing.allocator,
        "inline.yaml",
        ".",
        source,
    );
    defer document.deinit();

    try std.testing.expectError(
        zdisamar.canonical_config.Error.MissingStageProduct,
        document.resolve(std.testing.allocator),
    );
}

test "canonical config rejects unknown fields in strict mode" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: strict-unknown-fields
        \\experiment:
        \\  simulation:
        \\    scene:
        \\      id: truth_scene
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        o2a:
        \\          start_nm: 758.0
        \\          end_nm: 759.0
        \\          step_nm: 0.5
        \\      absorbers: {}
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: tropomi
        \\      unexpected_scene_field: true
        \\validation:
        \\  strict_unknown_fields: true
    ;

    var document = try zdisamar.canonical_config.Document.parse(
        std.testing.allocator,
        "inline.yaml",
        ".",
        source,
    );
    defer document.deinit();

    try std.testing.expectError(
        zdisamar.canonical_config.Error.UnknownField,
        document.resolve(std.testing.allocator),
    );
}

test "canonical config emits inverse-crime warning for identical synthetic stages" {
    const source =
        \\schema_version: 1
        \\
        \\metadata:
        \\  id: identical-stages
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
        \\      absorbers: {}
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
        \\      truth_radiance:
        \\        kind: measurement_space
        \\        observable: radiance
        \\  retrieval:
        \\    from: experiment.simulation
        \\    inverse:
        \\      algorithm:
        \\        name: oe
        \\      measurement:
        \\        source: truth_radiance
        \\        observable: radiance
        \\      state:
        \\        surface_albedo:
        \\          target: scene.surface.albedo
        \\          prior:
        \\            mean: 0.05
        \\            sigma: 0.02
        \\
        \\validation:
        \\  strict_unknown_fields: true
        \\  require_resolved_stage_references: true
        \\  synthetic_retrieval:
        \\    warn_if_models_are_identical: true
    ;

    var document = try zdisamar.canonical_config.Document.parse(
        std.testing.allocator,
        "inline.yaml",
        ".",
        source,
    );
    defer document.deinit();

    var resolved = try document.resolve(std.testing.allocator);
    defer resolved.deinit();

    try std.testing.expectEqual(@as(usize, 1), resolved.warnings.len);
    try std.testing.expectEqualStrings(
        "simulation and retrieval model contexts are identical; review inverse-crime risk",
        resolved.warnings[0].message,
    );
}
