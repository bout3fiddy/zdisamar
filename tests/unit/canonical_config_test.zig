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

test "canonical config parses typed vendor sections into resolved stage" {
    // WP-01: vendor_compat, radiative_transfer, rrs_ring, and additional_output
    // must parse from canonical YAML into typed config objects on the resolved stage.
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: typed-vendor-sections
        \\experiment:
        \\  simulation:
        \\    vendor_compat:
        \\      simulation_method: oe_lbl
        \\      simulation_only: true
        \\    radiative_transfer:
        \\      nstreams_sim: 8
        \\      nstreams_retr: 16
        \\      scattering_mode_sim: multiple
        \\      use_adding_sim: true
        \\      use_polarization_correction: false
        \\    rrs_ring:
        \\      sim:
        \\        - use_rrs: true
        \\          approximate_rrs: false
        \\          fraction_raman_lines: 0.5
        \\          use_cabannes: true
        \\          degree_poly: 3
        \\          include_absorption: true
        \\    additional_output:
        \\      refl_hr_grid_sim: true
        \\      signal_to_noise_ratio: true
        \\      ring_spectra: true
        \\    plan:
        \\      model_family: disamar_standard
        \\      transport:
        \\        solver: dispatcher
        \\      execution:
        \\        solver_mode: scalar
        \\        derivative_mode: none
        \\    scene:
        \\      id: typed_sections_scene
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
        \\          start_nm: 758.0
        \\          end_nm: 771.0
        \\          step_nm: 0.5
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
        \\    products:
        \\      sim_radiance:
        \\        kind: measurement_space
        \\        observable: radiance
        \\  retrieval:
        \\    from: experiment.simulation
        \\    radiative_transfer:
        \\      nstreams_sim: 8
        \\      nstreams_retr: 16
        \\      scattering_mode_retr: none
        \\      use_adding_sim: true
        \\      use_adding_retr: false
        \\    inverse:
        \\      algorithm:
        \\        name: oe
        \\      measurement:
        \\        source: sim_radiance
        \\        observable: radiance
        \\      state:
        \\        surface_albedo:
        \\          target: scene.surface.albedo
        \\          prior:
        \\            mean: 0.05
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

    var resolved = try document.resolve(std.testing.allocator);
    defer resolved.deinit();

    // Verify the typed vendor sections are populated on the simulation stage.
    const sim_stage = resolved.simulation orelse return error.TestUnexpectedResult;

    // vendor_compat
    const vc = sim_stage.vendor_compat orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(vc.simulation_method.?, .oe_lbl);
    try std.testing.expect(vc.simulation_only);

    // radiative_transfer
    const rt = sim_stage.radiative_transfer orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 8), rt.nstreams_sim);
    try std.testing.expectEqual(@as(u32, 16), rt.nstreams_retr);
    try std.testing.expect(rt.use_adding_sim);
    try std.testing.expect(!rt.use_polarization_correction);
    try std.testing.expectEqual(@as(u16, 8), sim_stage.plan.rtm_controls.n_streams);
    try std.testing.expect(sim_stage.plan.rtm_controls.use_adding);
    try std.testing.expect(sim_stage.plan.rtm_controls.integrate_source_function);

    // rrs_ring
    const rrs = sim_stage.rrs_ring orelse return error.TestUnexpectedResult;
    const sim_rrs = rrs.sim orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 1), sim_rrs.len);
    try std.testing.expect(sim_rrs[0].use_rrs);
    try std.testing.expect(!sim_rrs[0].approximate_rrs);
    try std.testing.expect(sim_rrs[0].use_cabannes);
    try std.testing.expectEqual(@as(u32, 3), sim_rrs[0].degree_poly);
    try std.testing.expect(sim_rrs[0].include_absorption);

    // additional_output
    const ao = sim_stage.additional_output orelse return error.TestUnexpectedResult;
    try std.testing.expect(ao.refl_hr_grid_sim);
    try std.testing.expect(ao.signal_to_noise_ratio);
    try std.testing.expect(ao.ring_spectra);
    try std.testing.expect(!ao.contrib_refl_sim);

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(sim_stage.plan);
    defer plan.deinit();
    try std.testing.expectEqual(@as(u16, 8), plan.transport_route.rtm_controls.n_streams);
    try std.testing.expect(plan.transport_route.rtm_controls.use_adding);
    try std.testing.expectEqualStrings("baseline_adding", plan.transport_route.family.provenanceLabel());

    const retr_stage = resolved.retrieval orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u16, 16), retr_stage.plan.rtm_controls.n_streams);
    try std.testing.expectEqual(zdisamar.test_support.kernels.transport.common.ScatteringMode.none, retr_stage.plan.rtm_controls.scattering);
    try std.testing.expect(!retr_stage.plan.rtm_controls.use_adding);
    try std.testing.expect(!retr_stage.plan.rtm_controls.integrate_source_function);

    var retr_plan = try engine.preparePlan(retr_stage.plan);
    defer retr_plan.deinit();
    try std.testing.expectEqual(@as(u16, 16), retr_plan.transport_route.rtm_controls.n_streams);
    try std.testing.expectEqual(zdisamar.test_support.kernels.transport.common.ScatteringMode.none, retr_plan.transport_route.rtm_controls.scattering);
    try std.testing.expectEqualStrings("baseline_labos", retr_plan.transport_route.family.provenanceLabel());
}

test "canonical config rejects table spectral responses without a table binding" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: missing-spectral-response-table
        \\experiment:
        \\  simulation:
        \\    plan:
        \\      model_family: disamar_standard
        \\      transport:
        \\        solver: dispatcher
        \\      execution:
        \\        solver_mode: scalar
        \\        derivative_mode: none
        \\    scene:
        \\      id: spectral_response_scene
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 30.0
        \\        viewing_zenith_deg: 8.0
        \\        relative_azimuth_deg: 145.0
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        band_1:
        \\          start_nm: 758.0
        \\          end_nm: 771.0
        \\          step_nm: 0.5
        \\      absorbers: {}
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: tropomi
        \\        spectral_response:
        \\          shape: table
        \\    products:
        \\      truth_radiance:
        \\        kind: measurement_space
        \\        observable: radiance
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
        zdisamar.canonical_config.Error.MissingField,
        document.resolve(std.testing.allocator),
    );
}

test "canonical config rejects unsupported radiative transfer controls that cannot be honored" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: unsupported-rtm-controls
        \\experiment:
        \\  simulation:
        \\    radiative_transfer:
        \\      threshold_trunc_phase_sim: 0.1
        \\      use_polarization_correction: true
        \\      threshold_cloud_fraction: 0.25
        \\    plan:
        \\      model_family: disamar_standard
        \\      transport:
        \\        solver: dispatcher
        \\      execution:
        \\        solver_mode: scalar
        \\        derivative_mode: none
        \\    scene:
        \\      id: unsupported_rtm_scene
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 30.0
        \\        viewing_zenith_deg: 8.0
        \\        relative_azimuth_deg: 145.0
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        band_1:
        \\          start_nm: 758.0
        \\          end_nm: 771.0
        \\          step_nm: 0.5
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
        zdisamar.canonical_config.Error.InvalidValue,
        document.resolve(std.testing.allocator),
    );
}

test "canonical execution rejects multiple measurement-space products in one stage" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: duplicate-measurement-space
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
        \\            model: cross_sections
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
        \\      truth_reflectance:
        \\        kind: measurement_space
        \\        observable: reflectance
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

    var resolved = try document.resolve(std.testing.allocator);
    defer resolved.deinit();

    try std.testing.expectError(
        zdisamar.canonical_config.execution.Error.MultipleMeasurementSpaceProducts,
        zdisamar.canonical_config.compileResolved(std.testing.allocator, resolved),
    );
}
