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
        \\      num_div_points_fwhm_sim: 5
        \\      num_div_points_max_sim: 8
        \\      num_div_points_min_sim: 3
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
    try std.testing.expectEqual(@as(?u32, 5), rt.num_div_points_fwhm_sim);
    try std.testing.expect(rt.use_adding_sim);
    try std.testing.expect(!rt.use_polarization_correction);
    try std.testing.expectEqual(@as(u16, 5), sim_stage.scene.observation_model.adaptive_reference_grid.points_per_fwhm);
    try std.testing.expectEqual(@as(u16, 3), sim_stage.scene.observation_model.adaptive_reference_grid.strong_line_min_divisions);
    try std.testing.expectEqual(@as(u16, 8), sim_stage.scene.observation_model.adaptive_reference_grid.strong_line_max_divisions);
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

test "canonical config hydrates separate radiance and irradiance instrument pipelines" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: explicit-instrument-pipeline
        \\experiment:
        \\  simulation:
        \\    instrument:
        \\      add_noise_rad_sim: true
        \\      add_noise_irr_sim: true
        \\      bands:
        \\        - slit_index_radiance_sim: 2
        \\          slit_index_irradiance_sim: 0
        \\          fwhm_radiance_sim: 0.38
        \\          fwhm_irradiance_sim: 0.22
        \\          wavelength_shift_radiance_sim: 0.02
        \\          wavelength_shift_irradiance_sim: -0.01
        \\          simple_offset_mul_radiance_sim: 1.5
        \\          simple_offset_add_radiance_sim: 0.25
        \\          smear_percent_radiance_sim: 1.0
        \\          snr_radiance_sim: 250.0
        \\          snr_irradiance_sim: 500.0
        \\          pol_scrambler_radiance_sim: false
        \\          calibration_error_reflectance_mul_sim: 1.0
        \\          calibration_error_reflectance_add_sim: 0.5
        \\    rrs_ring:
        \\      sim:
        \\        - use_rrs: true
        \\          approximate_rrs: true
        \\          differential: false
        \\          ring_coefficient: 0.02
        \\          fraction_raman_lines: 0.5
        \\          use_cabannes: false
        \\          degree_poly: 4
        \\          include_absorption: true
        \\    plan:
        \\      model_family: disamar_standard
        \\      transport:
        \\        solver: dispatcher
        \\      execution:
        \\        solver_mode: scalar
        \\        derivative_mode: none
        \\    scene:
        \\      id: explicit_instrument_scene
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

    const sim_stage = resolved.simulation orelse return error.TestUnexpectedResult;
    const radiance = sim_stage.scene.observation_model.measurement_pipeline.radiance;
    const irradiance = sim_stage.scene.observation_model.measurement_pipeline.irradiance;
    const ring = sim_stage.scene.observation_model.measurement_pipeline.ring;
    const reflectance_calibration = sim_stage.scene.observation_model.measurement_pipeline.reflectance_calibration;

    try std.testing.expect(radiance.explicit);
    try std.testing.expect(irradiance.explicit);
    try std.testing.expectEqual(zdisamar.Instrument.SlitIndex.triple_flat_top_n4, radiance.response.slit_index);
    try std.testing.expectEqual(zdisamar.Instrument.SlitIndex.gaussian_modulated, irradiance.response.slit_index);
    try std.testing.expectApproxEqRel(@as(f64, 0.38), radiance.response.fwhm_nm, 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.22), irradiance.response.fwhm_nm, 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.02), radiance.wavelength_shift_nm, 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, -0.01), irradiance.wavelength_shift_nm, 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 1.5), radiance.simple_offsets.multiplicative_percent, 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.25), radiance.simple_offsets.additive_percent_of_first, 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 1.0), radiance.smear_percent, 1.0e-12);
    try std.testing.expect(radiance.noise.enabled);
    try std.testing.expect(irradiance.noise.enabled);
    try std.testing.expectEqual(zdisamar.Instrument.NoiseModelKind.shot_noise, radiance.noise.model);
    try std.testing.expectEqual(zdisamar.Instrument.NoiseModelKind.shot_noise, irradiance.noise.model);
    try std.testing.expectEqual(@as(usize, 1), radiance.noise.snr_values.len);
    try std.testing.expectEqual(@as(usize, 1), irradiance.noise.snr_values.len);
    try std.testing.expectApproxEqRel(@as(f64, 250.0), radiance.noise.snr_values[0], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 500.0), irradiance.noise.snr_values[0], 1.0e-12);
    try std.testing.expect(!radiance.use_polarization_scrambler);

    try std.testing.expect(ring.explicit);
    try std.testing.expect(ring.enabled);
    try std.testing.expect(!ring.differential);
    try std.testing.expect(ring.approximate_rrs);
    try std.testing.expectApproxEqRel(@as(f64, 0.02), ring.coefficient, 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.5), ring.fraction_raman_lines, 1.0e-12);
    try std.testing.expectEqual(@as(u32, 4), ring.degree_poly);
    try std.testing.expect(ring.include_absorption);

    try std.testing.expect(reflectance_calibration.multiplicative_error.enabled());
    try std.testing.expect(reflectance_calibration.additive_error.enabled());
    try std.testing.expectApproxEqRel(@as(f64, 1.0), reflectance_calibration.multiplicative_error.values[0], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.5), reflectance_calibration.additive_error.values[0], 1.0e-12);
}

test "canonical config keeps the default Ring coefficient independent from Raman fraction" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: default-ring-coefficient
        \\experiment:
        \\  simulation:
        \\    rrs_ring:
        \\      sim:
        \\        - use_rrs: true
        \\          fraction_raman_lines: 0.5
        \\    plan:
        \\      model_family: disamar_standard
        \\      transport:
        \\        solver: dispatcher
        \\      execution:
        \\        solver_mode: scalar
        \\        derivative_mode: none
        \\    scene:
        \\      id: default_ring_scene
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

    const sim_stage = resolved.simulation orelse return error.TestUnexpectedResult;
    const ring = sim_stage.scene.observation_model.measurement_pipeline.ring;

    try std.testing.expect(ring.enabled);
    try std.testing.expectApproxEqRel(@as(f64, 0.01), ring.coefficient, 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.5), ring.fraction_raman_lines, 1.0e-12);
}

test "canonical config compiles interval grids, aerosol fractions, and subcolumns into scene state" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: interval-fraction-subcolumns
        \\experiment:
        \\  simulation:
        \\    general:
        \\      num_interval_fit: 2
        \\    radiative_transfer:
        \\      num_div_points_alt_sim: [2, 3, 1]
        \\    surface_config:
        \\      surf_pressure_sim: 1013.0
        \\    atmospheric_intervals:
        \\      sim:
        \\        - top_pressure_hpa: 120.0
        \\          bottom_pressure_hpa: 350.0
        \\          top_altitude_km: 16.0
        \\          bottom_altitude_km: 8.0
        \\        - top_pressure_hpa: 350.0
        \\          bottom_pressure_hpa: 800.0
        \\          top_altitude_km: 8.0
        \\          bottom_altitude_km: 2.0
        \\        - top_pressure_hpa: 800.0
        \\          bottom_pressure_hpa: 1013.0
        \\          top_altitude_km: 2.0
        \\          bottom_altitude_km: 0.0
        \\    cloud_aerosol_fraction:
        \\      target_sim: aerosol
        \\      kind_sim: wavel_independent
        \\      values_sim: [0.25]
        \\    aerosol_config:
        \\      aerosol_type_sim: hg_scattering
        \\      hg_optical_thickness_sim: 0.24
        \\      hg_angstrom_coefficient_sim: 1.1
        \\      hg_single_scattering_albedo_sim: 0.95
        \\      hg_parameter_g_sim: 0.71
        \\    subcolumns:
        \\      enabled: true
        \\      boundary_layer_top_pressure_hpa: 800.0
        \\      boundary_layer_top_altitude_km: 2.0
        \\      tropopause_pressure_hpa: 350.0
        \\      tropopause_altitude_km: 8.0
        \\      entries:
        \\        - label: boundary_layer
        \\          bottom_altitude_km: 0.0
        \\          top_altitude_km: 2.0
        \\        - label: free_troposphere
        \\          bottom_altitude_km: 2.0
        \\          top_altitude_km: 8.0
        \\        - label: stratosphere
        \\          bottom_altitude_km: 8.0
        \\          top_altitude_km: 16.0
        \\    scene:
        \\      id: interval_scene
        \\      geometry:
        \\        model: pseudo_spherical
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          sublayer_divisions: 2
        \\      bands:
        \\        a_band:
        \\          start_nm: 760.0
        \\          end_nm: 762.0
        \\          step_nm: 0.2
        \\      absorbers: {}
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
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

    var resolved = try document.resolve(std.testing.allocator);
    defer resolved.deinit();

    const stage = resolved.simulation orelse return error.TestUnexpectedResult;
    const interval_grid = stage.scene.atmosphere.interval_grid;
    try std.testing.expect(interval_grid.enabled());
    try std.testing.expectEqual(.explicit_pressure_bounds, interval_grid.semantics);
    try std.testing.expectEqual(@as(u32, 2), interval_grid.fit_interval_index_1based);
    try std.testing.expectEqual(@as(usize, 3), interval_grid.intervals.len);
    try std.testing.expectEqual(@as(u32, 3), interval_grid.intervals[1].altitude_divisions);
    try std.testing.expectApproxEqAbs(@as(f64, 1013.0), stage.scene.surface.pressure_hpa, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1013.0), stage.scene.atmosphere.surface_pressure_hpa, 1.0e-12);
    try std.testing.expect(stage.scene.aerosol.enabled);
    try std.testing.expectEqual(.hg_scattering, stage.scene.aerosol.aerosol_type);
    try std.testing.expectEqual(@as(u32, 2), stage.scene.aerosol.placement.interval_index_1based);
    try std.testing.expectApproxEqAbs(@as(f64, 350.0), stage.scene.aerosol.placement.top_pressure_hpa, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 800.0), stage.scene.aerosol.placement.bottom_pressure_hpa, 1.0e-12);
    try std.testing.expect(stage.scene.aerosol.fraction.enabled);
    try std.testing.expectEqual(.aerosol, stage.scene.aerosol.fraction.target);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), stage.scene.aerosol.fraction.values[0], 1.0e-12);
    try std.testing.expect(stage.scene.atmosphere.subcolumns.enabled);
    try std.testing.expectEqual(@as(usize, 3), stage.scene.atmosphere.subcolumns.subcolumns.len);
    try std.testing.expectEqual(.boundary_layer, stage.scene.atmosphere.subcolumns.subcolumns[0].label);
    try std.testing.expectEqual(.stratosphere, stage.scene.atmosphere.subcolumns.subcolumns[2].label);
    try std.testing.expectEqual(@as(u32, 3), stage.plan.scene_blueprint.layer_count_hint);
}

test "canonical config normalizes wrapped relative azimuth inputs" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: wrapped-relative-azimuth
        \\experiment:
        \\  simulation:
        \\    geometry:
        \\      solar_zenith_angle_sim: 31.7
        \\      instrument_nadir_angle_sim: 7.9
        \\      solar_azimuth_angle_sim: 350.0
        \\      instrument_azimuth_angle_sim: 10.0
        \\    scene:
        \\      id: wrapped_geometry_scene
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 0.0
        \\        viewing_zenith_deg: 0.0
        \\        relative_azimuth_deg: 0.0
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 1
        \\      bands:
        \\        a_band:
        \\          start_nm: 760.0
        \\          end_nm: 761.0
        \\          step_nm: 0.5
        \\      absorbers: {}
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
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

    const stage = resolved.simulation orelse return error.TestUnexpectedResult;
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), stage.scene.geometry.relative_azimuth_deg, 1.0e-12);
}

test "canonical config treats explicit none cloud-aerosol targets as a no-op" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: fraction-target-none
        \\experiment:
        \\  simulation:
        \\    cloud_aerosol_fraction:
        \\      target_sim: none
        \\    scene:
        \\      id: noop_fraction_scene
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 1
        \\      bands:
        \\        a_band:
        \\          start_nm: 760.0
        \\          end_nm: 761.0
        \\          step_nm: 0.5
        \\      absorbers: {}
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
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

    const stage = resolved.simulation orelse return error.TestUnexpectedResult;
    try std.testing.expect(!stage.scene.aerosol.fraction.enabled);
    try std.testing.expect(!stage.scene.cloud.fraction.enabled);
}

test "canonical config rejects cloud-aerosol fraction inputs without a stage target" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: fraction-target-missing
        \\experiment:
        \\  simulation:
        \\    cloud_aerosol_fraction:
        \\      kind_sim: wavel_independent
        \\      values_sim: [0.25]
        \\    scene:
        \\      id: missing_fraction_target_scene
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 1
        \\      bands:
        \\        a_band:
        \\          start_nm: 760.0
        \\          end_nm: 761.0
        \\          step_nm: 0.5
        \\      absorbers: {}
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
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

test "canonical config rejects threshold-only cloud-aerosol fraction inputs without a stage target" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: fraction-threshold-target-missing
        \\experiment:
        \\  simulation:
        \\    cloud_aerosol_fraction:
        \\      threshold_cloud_fraction: 0.25
        \\      threshold_variance: 0.05
        \\    scene:
        \\      id: missing_fraction_threshold_target_scene
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 1
        \\      bands:
        \\        a_band:
        \\          start_nm: 760.0
        \\          end_nm: 761.0
        \\          step_nm: 0.5
        \\      absorbers: {}
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
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

test "canonical config infers retrieval HG aerosols as hg_scattering" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: retrieval-hg-aerosol
        \\experiment:
        \\  simulation:
        \\    scene:
        \\      id: retrieval_hg_aerosol_truth
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 1
        \\      bands:
        \\        a_band:
        \\          start_nm: 760.0
        \\          end_nm: 761.0
        \\          step_nm: 0.5
        \\      absorbers: {}
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
        \\    products:
        \\      truth_radiance:
        \\        kind: measurement_space
        \\        observable: radiance
        \\  retrieval:
        \\    from: experiment.simulation
        \\    aerosol_config:
        \\      hg_optical_thickness_retr: 0.12
        \\    scene:
        \\      id: retrieval_hg_aerosol_scene
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

    const stage = resolved.retrieval orelse return error.TestUnexpectedResult;
    try std.testing.expect(stage.scene.aerosol.enabled);
    try std.testing.expectEqual(.hg_scattering, stage.scene.aerosol.aerosol_type);
    try std.testing.expectApproxEqAbs(@as(f64, 0.12), stage.scene.aerosol.optical_depth, 1.0e-12);
}

test "canonical config infers retrieval HG clouds as hg_scattering" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: retrieval-hg-cloud
        \\experiment:
        \\  simulation:
        \\    scene:
        \\      id: retrieval_hg_cloud_truth
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 1
        \\      bands:
        \\        a_band:
        \\          start_nm: 760.0
        \\          end_nm: 761.0
        \\          step_nm: 0.5
        \\      absorbers: {}
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
        \\    products:
        \\      truth_radiance:
        \\        kind: measurement_space
        \\        observable: radiance
        \\  retrieval:
        \\    from: experiment.simulation
        \\    cloud_config:
        \\      hg_optical_thickness_retr: 0.18
        \\    scene:
        \\      id: retrieval_hg_cloud_scene
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

    const stage = resolved.retrieval orelse return error.TestUnexpectedResult;
    try std.testing.expect(stage.scene.cloud.enabled);
    try std.testing.expectEqual(.hg_scattering, stage.scene.cloud.cloud_type);
    try std.testing.expectApproxEqAbs(@as(f64, 0.18), stage.scene.cloud.optical_thickness, 1.0e-12);
}

test "canonical config compiles absorbing-gas HITRAN controls onto line absorbers" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: absorbing-gas-hitran
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
        \\      id: absorbing_gas_scene
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 30.0
        \\        viewing_zenith_deg: 8.0
        \\        relative_azimuth_deg: 145.0
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        o2a:
        \\          start_nm: 760.8
        \\          end_nm: 771.0
        \\          step_nm: 0.2
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
        \\    absorbing_gas:
        \\      gases:
        \\        - species: o2
        \\          hitran:
        \\            factor_lm_sim: 0.35
        \\            factor_lm_retr: 0.10
        \\            isotopes_sim: [1, 2]
        \\            isotopes_retr: [1]
        \\            threshold_line_sim: 0.02
        \\            threshold_line_retr: 0.05
        \\            cutoff_sim_cm1: 8.0
        \\            cutoff_retr_cm1: 6.0
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

    const sim_stage = resolved.simulation orelse return error.TestUnexpectedResult;
    const absorbing_gas = sim_stage.absorbing_gas orelse return error.TestUnexpectedResult;
    const gases = absorbing_gas.gases orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 1), gases.len);
    try std.testing.expectEqualStrings("o2", @tagName(gases[0].species.?));
    try std.testing.expectApproxEqAbs(@as(f64, 0.35), gases[0].hitran.?.factor_lm_sim.?, 1.0e-12);

    try std.testing.expectEqual(@as(usize, 1), sim_stage.scene.absorbers.items.len);
    const controls = sim_stage.scene.absorbers.items[0].spectroscopy.line_gas_controls;
    try std.testing.expectEqualStrings("o2", @tagName(sim_stage.scene.absorbers.items[0].resolved_species.?));
    try std.testing.expectEqualStrings("simulation", @tagName(controls.active_stage));
    try std.testing.expectApproxEqAbs(@as(f64, 0.35), controls.factor_lm_sim.?, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.10), controls.factor_lm_retr.?, 1.0e-12);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, controls.isotopes_sim);
    try std.testing.expectEqualSlices(u8, &.{1}, controls.isotopes_retr);
    try std.testing.expectApproxEqAbs(@as(f64, 0.02), controls.threshold_line_sim.?, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), controls.cutoff_retr_cm1.?, 1.0e-12);
}

test "canonical config keeps profile_sim scoped to the simulation stage" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: absorbing-gas-profile-stage-scope
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
        \\      id: sim_scene
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 30.0
        \\        viewing_zenith_deg: 8.0
        \\        relative_azimuth_deg: 145.0
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        o2a:
        \\          start_nm: 760.8
        \\          end_nm: 771.0
        \\          step_nm: 0.2
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
        \\    absorbing_gas:
        \\      gases:
        \\        - species: o2
        \\          profile_sim:
        \\            - [1000.0, 209500.0]
        \\            - [500.0, 209500.0]
        \\    products:
        \\      truth_radiance:
        \\        kind: measurement_space
        \\        observable: radiance
        \\  retrieval:
        \\    from: experiment.simulation
        \\    scene:
        \\      id: retr_scene
        \\    absorbing_gas:
        \\      gases:
        \\        - species: o2
        \\          profile_sim:
        \\            - [1000.0, 209500.0]
        \\            - [500.0, 209500.0]
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
        \\            mean: 0.04
        \\            sigma: 0.02
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

    const sim_stage = resolved.simulation orelse return error.TestUnexpectedResult;
    const retr_stage = resolved.retrieval orelse return error.TestUnexpectedResult;

    try std.testing.expectEqual(@as(usize, 2), sim_stage.scene.absorbers.items[0].volume_mixing_ratio_profile_ppmv.len);
    try std.testing.expectEqual(@as(usize, 0), retr_stage.scene.absorbers.items[0].volume_mixing_ratio_profile_ppmv.len);
}

test "canonical config overwrites duplicate HITRAN gas controls without leaking owned isotope slices" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: absorbing-gas-hitran-duplicate-species
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
        \\      id: absorbing_gas_scene
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 30.0
        \\        viewing_zenith_deg: 8.0
        \\        relative_azimuth_deg: 145.0
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        o2a:
        \\          start_nm: 760.8
        \\          end_nm: 771.0
        \\          step_nm: 0.2
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
        \\    absorbing_gas:
        \\      gases:
        \\        - species: o2
        \\          hitran:
        \\            isotopes_sim: [1, 2]
        \\        - species: o2
        \\          hitran:
        \\            factor_lm_sim: 0.45
        \\            isotopes_sim: [7]
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

    const sim_stage = resolved.simulation orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 1), sim_stage.scene.absorbers.items.len);
    const controls = sim_stage.scene.absorbers.items[0].spectroscopy.line_gas_controls;
    try std.testing.expectApproxEqAbs(@as(f64, 0.45), controls.factor_lm_sim.?, 1.0e-12);
    try std.testing.expectEqualSlices(u8, &.{7}, controls.isotopes_sim);
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

test "canonical config rejects oversized adaptive reference grid controls" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: oversized-adaptive-grid
        \\experiment:
        \\  simulation:
        \\    radiative_transfer:
        \\      num_div_points_fwhm_sim: 70000
        \\      num_div_points_min_sim: 3
        \\      num_div_points_max_sim: 8
        \\    plan:
        \\      model_family: disamar_standard
        \\      transport:
        \\        solver: dispatcher
        \\      execution:
        \\        solver_mode: scalar
        \\        derivative_mode: none
        \\    scene:
        \\      id: oversized_adaptive_grid_scene
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

test "canonical config compiles cross-section assets and effective-xsec controls into the scene" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: cross-section-controls
        \\inputs:
        \\  assets:
        \\    no2_cross_section:
        \\      kind: file
        \\      format: csv
        \\      path: data/cross_sections/no2_405_465_demo.csv
        \\experiment:
        \\  simulation:
        \\    general:
        \\      useEffXsec_OE_sim: true
        \\      usePolyExpXsecSim: true
        \\      XsecStrongAbsSim: [true]
        \\      degreePolySim: [5]
        \\    scene:
        \\      id: no2-xsec-scene
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        uv:
        \\          start_nm: 405.0
        \\          end_nm: 465.0
        \\          step_nm: 2.5
        \\      absorbers:
        \\        no2:
        \\          species: no2
        \\          spectroscopy:
        \\            model: cross_sections
        \\            cross_section_asset: no2_cross_section
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
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

    const stage = resolved.simulation.?;
    const absorber = stage.scene.absorbers.items[0];
    try std.testing.expectEqual(zdisamar.SpectroscopyMode.cross_sections, absorber.spectroscopy.mode);
    try std.testing.expect(absorber.spectroscopy.resolved_cross_section_table != null);
    try std.testing.expect(stage.scene.observation_model.cross_section_fit.use_effective_cross_section_oe);
    try std.testing.expect(stage.scene.observation_model.cross_section_fit.use_polynomial_expansion);
    try std.testing.expect(stage.scene.observation_model.cross_section_fit.strongAbsorptionForBand(0));
    try std.testing.expectEqual(@as(u32, 5), stage.scene.observation_model.cross_section_fit.polynomialOrderForBand(0));
}

test "canonical config maps explicit LUT controls into the scene and prepared blueprint" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: explicit-lut-controls
        \\experiment:
        \\  simulation:
        \\    general:
        \\      usePolyExpXsecSim: true
        \\      create_lut:
        \\        reflectance_mode: generate
        \\        correction_mode: consume
        \\        use_chandra_formula: true
        \\        surface_albedo: 0.11
        \\      create_xsec_lut:
        \\        mode: generate
        \\        min_temperature_k: 180.0
        \\        max_temperature_k: 325.0
        \\        min_pressure_hpa: 0.03
        \\        max_pressure_hpa: 1050.0
        \\        temperature_grid_count: 10
        \\        pressure_grid_count: 20
        \\        temperature_coefficient_count: 5
        \\        pressure_coefficient_count: 10
        \\    scene:
        \\      id: o2a-lut-scene
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
        \\          start_nm: 760.8
        \\          end_nm: 771.5
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

    var resolved = try document.resolve(std.testing.allocator);
    defer resolved.deinit();

    const stage = resolved.simulation.?;
    try std.testing.expectEqual(zdisamar.LutMode.generate, stage.scene.lut_controls.reflectance.reflectance_mode);
    try std.testing.expectEqual(zdisamar.LutMode.consume, stage.scene.lut_controls.reflectance.correction_mode);
    try std.testing.expect(stage.scene.lut_controls.reflectance.use_chandra_formula);
    try std.testing.expectApproxEqAbs(@as(f64, 0.11), stage.scene.lut_controls.reflectance.surface_albedo, 1.0e-12);
    try std.testing.expectEqual(zdisamar.LutMode.generate, stage.scene.lut_controls.xsec.mode);
    try std.testing.expectEqual(@as(u8, 10), stage.scene.lut_controls.xsec.temperature_grid_count);
    try std.testing.expectEqual(@as(u8, 20), stage.scene.lut_controls.xsec.pressure_grid_count);
    try std.testing.expectEqual(@as(u8, 5), stage.scene.lut_controls.xsec.temperature_coefficient_count);
    try std.testing.expectEqual(@as(u8, 10), stage.scene.lut_controls.xsec.pressure_coefficient_count);

    const compatibility = stage.plan.scene_blueprint.lut_compatibility;
    try std.testing.expect(compatibility.enabled());
    try std.testing.expect(compatibility.matches(stage.scene.lutCompatibilityKey()));
    try std.testing.expectEqual(zdisamar.LutMode.generate, compatibility.controls.reflectance.reflectance_mode);
    try std.testing.expectEqual(zdisamar.LutMode.consume, compatibility.controls.reflectance.correction_mode);
    try std.testing.expectEqual(zdisamar.LutMode.generate, compatibility.controls.xsec.mode);
    try std.testing.expectApproxEqAbs(@as(f64, 0.11), compatibility.controls.reflectance.surface_albedo, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.05), compatibility.surface_albedo, 1.0e-12);
}

test "canonical config preserves explicit zero LUT surface albedo" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: zero-lut-surface-albedo
        \\experiment:
        \\  simulation:
        \\    general:
        \\      create_lut:
        \\        surface_albedo: 0.0
        \\    scene:
        \\      id: zero_lut_surface_albedo_scene
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        a_band:
        \\          start_nm: 760.0
        \\          end_nm: 761.0
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

    var resolved = try document.resolve(std.testing.allocator);
    defer resolved.deinit();

    const stage = resolved.simulation.?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), stage.scene.lut_controls.reflectance.surface_albedo, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), stage.plan.scene_blueprint.lut_compatibility.controls.reflectance.surface_albedo, 1.0e-12);
}

test "canonical config derives implicit LUT albedo from the finalized surface config" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: implicit-lut-surface-albedo-follows-surface-config
        \\experiment:
        \\  simulation:
        \\    general:
        \\      create_lut:
        \\        reflectance_mode: generate
        \\    surface_config:
        \\      surf_albedo_sim: 0.27
        \\    scene:
        \\      id: implicit_lut_surface_albedo_scene
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        a_band:
        \\          start_nm: 760.0
        \\          end_nm: 761.0
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

    var resolved = try document.resolve(std.testing.allocator);
    defer resolved.deinit();

    const stage = resolved.simulation.?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.27), stage.scene.surface.albedo, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.27), stage.scene.lut_controls.reflectance.surface_albedo, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.27), stage.plan.scene_blueprint.lut_compatibility.controls.reflectance.surface_albedo, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.27), stage.plan.scene_blueprint.lut_compatibility.surface_albedo, 1.0e-12);
}

test "canonical config defaults polynomial-expansion xsec LUT mode to direct without explicit LUT controls" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: default-direct-xsec-lut-mode
        \\experiment:
        \\  simulation:
        \\    general:
        \\      usePolyExpXsecSim: true
        \\    scene:
        \\      id: default_direct_xsec_lut_mode_scene
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        a_band:
        \\          start_nm: 760.0
        \\          end_nm: 761.0
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

    var resolved = try document.resolve(std.testing.allocator);
    defer resolved.deinit();

    const stage = resolved.simulation.?;
    try std.testing.expectEqual(zdisamar.LutMode.direct, stage.scene.lut_controls.xsec.mode);
}

test "canonical config rejects negative LUT surface albedo" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: negative-lut-surface-albedo
        \\experiment:
        \\  simulation:
        \\    general:
        \\      create_lut:
        \\        surface_albedo: -0.01
        \\    scene:
        \\      id: negative_lut_surface_albedo_scene
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        a_band:
        \\          start_nm: 760.0
        \\          end_nm: 761.0
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

test "canonical config rejects legacy xsec LUT creation without polynomial expansion" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: xsec-lut-create-without-poly-expansion
        \\experiment:
        \\  simulation:
        \\    general:
        \\      usePolyExpXsecSim: false
        \\      create_xsec_lut:
        \\        create_xsec_poly_lut: true
        \\    scene:
        \\      id: xsec_lut_create_without_poly_expansion_scene
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        a_band:
        \\          start_nm: 760.0
        \\          end_nm: 761.0
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

test "canonical config resolves non-o2 operational LUT ingests into cross-section absorbers" {
    const path = "zig-cache/test-o3-operational-lut.txt";
    defer std.fs.cwd().deleteFile(path) catch {};
    try std.fs.cwd().writeFile(.{
        .sub_path = path,
        .data =
        \\meta o3_refspec_ntemperature 2
        \\meta o3_refspec_npressure 2
        \\meta o3_refspec_temperature_min 220.0
        \\meta o3_refspec_temperature_max 320.0
        \\meta o3_refspec_pressure_min 150.0
        \\meta o3_refspec_pressure_max 1000.0
        \\meta o3_refspec_wavelength_1 430.0
        \\meta o3_refspec_wavelength_2 432.0
        \\meta o3_refspec_coeff_1_1_1 1.1e-19
        \\meta o3_refspec_coeff_2_1_1 0.2e-19
        \\meta o3_refspec_coeff_1_2_1 0.1e-19
        \\meta o3_refspec_coeff_2_2_1 0.03e-19
        \\meta o3_refspec_coeff_1_1_2 1.4e-19
        \\meta o3_refspec_coeff_2_1_2 0.22e-19
        \\meta o3_refspec_coeff_1_2_2 0.11e-19
        \\meta o3_refspec_coeff_2_2_2 0.04e-19
        \\start_channel_rad
        \\rad 430.0 1485.0 1.116153E+13
        \\rad 432.0 1445.0 1.096153E+13
        \\end_channel_rad
        \\
        ,
    });

    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: o3-operational-lut
        \\inputs:
        \\  assets:
        \\    o3_metadata:
        \\      kind: file
        \\      format: spectral_ascii
        \\      path: zig-cache/test-o3-operational-lut.txt
        \\  ingests:
        \\    demo:
        \\      adapter: spectral_ascii
        \\      asset: o3_metadata
        \\experiment:
        \\  simulation:
        \\    scene:
        \\      id: o3-lut-scene
        \\      geometry:
        \\        model: pseudo_spherical
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        uv:
        \\          start_nm: 405.0
        \\          end_nm: 465.0
        \\          step_nm: 2.5
        \\      absorbers:
        \\        o3:
        \\          species: o3
        \\          spectroscopy:
        \\            model: cross_sections
        \\            operational_lut:
        \\              from_ingest: demo.o3_operational_lut
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
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

    const stage = resolved.simulation.?;
    const absorber = stage.scene.absorbers.items[0];
    try std.testing.expectEqual(zdisamar.SpectroscopyMode.cross_sections, absorber.spectroscopy.mode);
    const lut = absorber.spectroscopy.resolved_cross_section_lut orelse unreachable;
    try std.testing.expect(lut.enabled());
    try std.testing.expect(lut.sigmaAt(431.0, 260.0, 700.0) > 0.0);
    try std.testing.expect(!stage.scene.observation_model.o2_operational_lut.enabled());
    try std.testing.expect(!stage.scene.observation_model.o2o2_operational_lut.enabled());
}

test "canonical config keeps O2 cross-section operational LUTs off the observation model" {
    const path = "zig-cache/test-o2-cross-section-operational-lut.txt";
    defer std.fs.cwd().deleteFile(path) catch {};
    try std.fs.cwd().writeFile(.{
        .sub_path = path,
        .data =
        \\meta o2_refspec_ntemperature 2
        \\meta o2_refspec_npressure 2
        \\meta o2_refspec_temperature_min 220.0
        \\meta o2_refspec_temperature_max 320.0
        \\meta o2_refspec_pressure_min 150.0
        \\meta o2_refspec_pressure_max 1000.0
        \\meta o2_refspec_wavelength_1 760.8
        \\meta o2_refspec_wavelength_2 761.0
        \\meta o2_refspec_wavelength_3 761.2
        \\meta o2_refspec_coeff_1_1_1 2.0e-24
        \\meta o2_refspec_coeff_2_1_1 0.3e-24
        \\meta o2_refspec_coeff_1_2_1 0.2e-24
        \\meta o2_refspec_coeff_2_2_1 0.05e-24
        \\meta o2_refspec_coeff_1_1_2 2.6e-24
        \\meta o2_refspec_coeff_2_1_2 0.35e-24
        \\meta o2_refspec_coeff_1_2_2 0.25e-24
        \\meta o2_refspec_coeff_2_2_2 0.06e-24
        \\meta o2_refspec_coeff_1_1_3 2.2e-24
        \\meta o2_refspec_coeff_2_1_3 0.32e-24
        \\meta o2_refspec_coeff_1_2_3 0.22e-24
        \\meta o2_refspec_coeff_2_2_3 0.05e-24
        \\start_channel_rad
        \\rad 760.8 1485.0 1.116153E+13
        \\rad 761.0 1445.0 1.096153E+13
        \\rad 761.2 1405.0 1.076153E+13
        \\end_channel_rad
        \\
        ,
    });

    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: o2-cross-section-operational-lut
        \\inputs:
        \\  assets:
        \\    o2_metadata:
        \\      kind: file
        \\      format: spectral_ascii
        \\      path: zig-cache/test-o2-cross-section-operational-lut.txt
        \\  ingests:
        \\    demo:
        \\      adapter: spectral_ascii
        \\      asset: o2_metadata
        \\experiment:
        \\  simulation:
        \\    scene:
        \\      id: o2-cross-section-scene
        \\      geometry:
        \\        model: pseudo_spherical
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        a_band:
        \\          start_nm: 760.0
        \\          end_nm: 762.0
        \\          step_nm: 0.2
        \\      absorbers:
        \\        o2:
        \\          species: o2
        \\          spectroscopy:
        \\            model: cross_sections
        \\            operational_lut:
        \\              from_ingest: demo.o2_operational_lut
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
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

    const stage = resolved.simulation.?;
    const absorber = stage.scene.absorbers.items[0];
    try std.testing.expectEqual(zdisamar.SpectroscopyMode.cross_sections, absorber.spectroscopy.mode);
    const lut = absorber.spectroscopy.resolved_cross_section_lut orelse unreachable;
    try std.testing.expect(lut.enabled());
    try std.testing.expect(lut.sigmaAt(761.0, 260.0, 700.0) > 0.0);
    try std.testing.expect(!stage.scene.observation_model.o2_operational_lut.enabled());
    try std.testing.expect(!stage.scene.observation_model.o2o2_operational_lut.enabled());
}

test "canonical config wires O2-O2 operational LUTs for o2_o2 CIA aliases" {
    const path = "zig-cache/test-o2o2-operational-lut.txt";
    defer std.fs.cwd().deleteFile(path) catch {};
    try std.fs.cwd().writeFile(.{
        .sub_path = path,
        .data =
        \\meta o2_o2_refspec_ntemperature 2
        \\meta o2_o2_refspec_npressure 2
        \\meta o2_o2_refspec_temperature_min 220.0
        \\meta o2_o2_refspec_temperature_max 320.0
        \\meta o2_o2_refspec_pressure_min 150.0
        \\meta o2_o2_refspec_pressure_max 1000.0
        \\meta o2_o2_refspec_wavelength_1 760.8
        \\meta o2_o2_refspec_wavelength_2 761.0
        \\meta o2_o2_refspec_wavelength_3 761.2
        \\meta o2_o2_refspec_coeff_1_1_1 1.2e-46
        \\meta o2_o2_refspec_coeff_2_1_1 0.2e-46
        \\meta o2_o2_refspec_coeff_1_2_1 0.1e-46
        \\meta o2_o2_refspec_coeff_2_2_1 0.03e-46
        \\meta o2_o2_refspec_coeff_1_1_2 1.5e-46
        \\meta o2_o2_refspec_coeff_2_1_2 0.2e-46
        \\meta o2_o2_refspec_coeff_1_2_2 0.1e-46
        \\meta o2_o2_refspec_coeff_2_2_2 0.03e-46
        \\meta o2_o2_refspec_coeff_1_1_3 1.1e-46
        \\meta o2_o2_refspec_coeff_2_1_3 0.18e-46
        \\meta o2_o2_refspec_coeff_1_2_3 0.08e-46
        \\meta o2_o2_refspec_coeff_2_2_3 0.02e-46
        \\start_channel_rad
        \\rad 760.8 1485.0 1.116153E+13
        \\rad 761.0 1445.0 1.096153E+13
        \\rad 761.2 1405.0 1.076153E+13
        \\end_channel_rad
        \\
        ,
    });

    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: o2o2-operational-lut
        \\inputs:
        \\  assets:
        \\    o2o2_metadata:
        \\      kind: file
        \\      format: spectral_ascii
        \\      path: zig-cache/test-o2o2-operational-lut.txt
        \\  ingests:
        \\    demo:
        \\      adapter: spectral_ascii
        \\      asset: o2o2_metadata
        \\experiment:
        \\  simulation:
        \\    scene:
        \\      id: o2o2-cia-scene
        \\      geometry:
        \\        model: pseudo_spherical
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        a_band:
        \\          start_nm: 760.0
        \\          end_nm: 762.0
        \\          step_nm: 0.2
        \\      absorbers:
        \\        o2_o2:
        \\          species: o2_o2
        \\          spectroscopy:
        \\            model: cia
        \\            operational_lut:
        \\              from_ingest: demo.o2_o2_operational_lut
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
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

    const stage = resolved.simulation.?;
    const absorber = stage.scene.absorbers.items[0];
    try std.testing.expectEqual(zdisamar.SpectroscopyMode.cia, absorber.spectroscopy.mode);
    const lut = absorber.spectroscopy.resolved_cross_section_lut orelse unreachable;
    try std.testing.expect(lut.enabled());
    try std.testing.expect(!stage.scene.observation_model.o2_operational_lut.enabled());
    try std.testing.expect(stage.scene.observation_model.o2o2_operational_lut.enabled());
    try std.testing.expect(stage.scene.observation_model.o2o2_operational_lut.sigmaAt(761.0, 260.0, 700.0) > 0.0);
}

test "canonical config rejects mismatched O2 operational LUT output names" {
    const path = "zig-cache/test-o2-mismatched-operational-lut.txt";
    defer std.fs.cwd().deleteFile(path) catch {};
    try std.fs.cwd().writeFile(.{
        .sub_path = path,
        .data =
        \\meta o3_refspec_ntemperature 2
        \\meta o3_refspec_npressure 2
        \\meta o3_refspec_temperature_min 220.0
        \\meta o3_refspec_temperature_max 320.0
        \\meta o3_refspec_pressure_min 150.0
        \\meta o3_refspec_pressure_max 1000.0
        \\meta o3_refspec_wavelength_1 430.0
        \\meta o3_refspec_wavelength_2 432.0
        \\meta o3_refspec_coeff_1_1_1 1.1e-19
        \\meta o3_refspec_coeff_2_1_1 0.2e-19
        \\meta o3_refspec_coeff_1_2_1 0.1e-19
        \\meta o3_refspec_coeff_2_2_1 0.03e-19
        \\meta o3_refspec_coeff_1_1_2 1.4e-19
        \\meta o3_refspec_coeff_2_1_2 0.22e-19
        \\meta o3_refspec_coeff_1_2_2 0.11e-19
        \\meta o3_refspec_coeff_2_2_2 0.04e-19
        \\start_channel_rad
        \\rad 430.0 1485.0 1.116153E+13
        \\rad 432.0 1445.0 1.096153E+13
        \\end_channel_rad
        \\
        ,
    });

    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: o2-mismatched-operational-lut
        \\inputs:
        \\  assets:
        \\    o3_metadata:
        \\      kind: file
        \\      format: spectral_ascii
        \\      path: zig-cache/test-o2-mismatched-operational-lut.txt
        \\  ingests:
        \\    demo:
        \\      adapter: spectral_ascii
        \\      asset: o3_metadata
        \\experiment:
        \\  simulation:
        \\    scene:
        \\      id: o2-lut-scene
        \\      geometry:
        \\        model: pseudo_spherical
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        a_band:
        \\          start_nm: 760.0
        \\          end_nm: 762.0
        \\          step_nm: 0.2
        \\      absorbers:
        \\        o2:
        \\          species: o2
        \\          spectroscopy:
        \\            model: line_by_line
        \\            operational_lut:
        \\              from_ingest: demo.o3_operational_lut
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
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
        zdisamar.canonical_config.Error.MissingIngestOutput,
        document.resolve(std.testing.allocator),
    );
}
