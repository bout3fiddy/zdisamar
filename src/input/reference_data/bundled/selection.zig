const std = @import("std");
const Scene = @import("../../Scene.zig").Scene;
const AbsorberModel = @import("../../Absorber.zig");
const ReferenceData = @import("../../ReferenceData.zig");
const assets = @import("assets.zig");

const Allocator = std.mem.Allocator;
const AbsorberSpecies = AbsorberModel.AbsorberSpecies;

// selection.zig ---------------------------------------------------------------------------------------------|
// Scene-to-reference selection rules used before optical preparation and LUT generation. This file answers   |
// which reference rows a Scene is allowed to use; assets.zig performs concrete loads/clones and workflows.zig|
// may mutate a working Scene copy after this policy has selected the inputs.                                 |
//                                                                                                            |
// call routes                                                                                                |
//   bundled/load.zig calls loadContinuumForScene, loadSpectroscopyForScene, and                              |
//   loadCollisionInducedAbsorptionForScene while hydrating the Data owner used by prepare().                 |
//   bundled/workflows.zig calls sampleSceneWavelengthsOwned only for generated LUT modes that need support   |
//   wavelengths shaped like the source scene.                                                                |
//                                                                                                            |
// selection order                                                                                            |
//   continuum   : resolved cross-section requests are accepted; unresolved cross-section requests reject;    |
//                 otherwise an owned zero-continuum table covers the scene spectral span.                    |
//   spectroscopy: resolved scene line list wins; explicit unresolved bindings reject; bundled O2 A defaults  |
//                 load only for O2 A line-by-line requests overlapping the bundled line-list range.          |
//   O2-O2 CIA   : resolved scene CIA wins; explicit unresolved CIA bindings reject; operational LUT support  |
//                 suppresses the sidecar unless the scene is currently generating that LUT.                  |
//   wavelengths : generated LUTs prefer high-resolution LUT sampling, then measured wavelengths, then a      |
//                 uniform scene grid from spectral_grid start/end/sample_count.                              |
//                                                                                                            |
// failure boundary                                                                                           |
//   If the scene explicitly asks for an asset binding, this file either returns that resolved asset or       |
//   rejects the request. Bundled defaults are only for absent bindings on supported O2 A default paths.      |
//   Operational O2-O2 LUT support suppresses the bundled CIA sidecar unless the current workflow is          |
//   generating the operational LUT and therefore needs the source table.                                     |
//                                                                                                            |
// memory and ownership                                                                                       |
//   Selectors may allocate owned tables or wavelength arrays for setup code. They do not parse files, run    |
//   the RTM, or retain hidden global state; callers own every returned buffer and deinitialize it. The       |
//   wavelength support helper returns owned f64 rows and leaves the source Scene borrowed.                   |
// -----------------------------------------------------------------------------------------------------------|

pub fn loadContinuumForScene(allocator: Allocator, scene: *const Scene) !ReferenceData.CrossSectionTable {
    if (requestsUnresolvedCrossSectionSpectroscopy(scene)) {
        return error.UnsupportedSpectroscopyConfiguration;
    }

    // The fallback table keeps the scene spectral grid in nanometers and leaves the continuum coefficient at
    // exactly zero.
    return assets.zeroContinuumTable(allocator, scene.spectral_grid.start_nm, scene.spectral_grid.end_nm);
}

pub fn loadSpectroscopyForScene(allocator: Allocator, scene: *const Scene) !?ReferenceData.SpectroscopyLineList {
    if (try assets.cloneResolvedSpectroscopyLineList(allocator, scene)) |line_list| {
        return line_list;
    }

    if (assets.hasExplicitSpectroscopyBindings(scene)) {

        // Explicit asset bindings must resolve. Falling back here would hide a broken scene configuration.
        return error.UnresolvedSpectroscopyBinding;
    }

    if (assets.shouldLoadBundledO2ALineList(scene) and
        assets.overlapsRange(scene.spectral_grid.start_nm, scene.spectral_grid.end_nm, 760.8, 771.5))
    {
        return try assets.loadO2aSpectroscopyLineList(allocator);
    }

    if (requestsLineByLineSpectroscopy(scene)) {
        return error.UnsupportedSpectroscopyConfiguration;
    }

    return null;
}

fn requestsLineByLineSpectroscopy(scene: *const Scene) bool {
    for (scene.absorbers.items) |absorber| {
        if (absorber.spectroscopy.mode == .line_by_line) return true;
    }
    return false;
}

fn requestsUnresolvedCrossSectionSpectroscopy(scene: *const Scene) bool {
    for (scene.absorbers.items) |absorber| {
        if (absorber.spectroscopy.mode != .cross_sections) continue;

        switch (absorber.spectroscopy.resolvedAbsorptionRepresentation()) {
            .xsec_table, .xsec_lut => continue,
            .line_abs, .none => return true,
        }
    }

    return false;
}

pub fn loadCollisionInducedAbsorptionForScene(
    allocator: Allocator,
    scene: *const Scene,
) !?ReferenceData.CollisionInducedAbsorptionTable {
    const requests_explicit_cia = assets.sceneRequestsSpectroscopyMode(scene, .o2_o2, .cia);
    const generating_o2o2_lut = requests_explicit_cia and scene.lut_controls.xsec.mode == .generate;
    const has_explicit_cia_bindings = assets.hasExplicitCiaBindings(scene);

    if (requests_explicit_cia) {
        if (assets.resolvedCollisionInducedAbsorptionTable(scene)) |table| {
            return try table.clone(allocator);
        }
    }

    if (has_explicit_cia_bindings) {

        // Explicit CIA bindings must be materialized or the scene configuration is incomplete.
        return error.UnresolvedCollisionInducedAbsorptionBinding;
    }

    const uses_operational_o2o2_lut =
        scene.observation_model.primaryOperationalBandSupport().o2o2_operational_lut.enabled();
    if (uses_operational_o2o2_lut and !generating_o2o2_lut) {

        // The operational LUT takes precedence over the bundled O2-O2 CIA sidecar because that is the runtime
        // control path requested by the scene.
        return null;
    }

    if (!assets.shouldLoadBundledO2ACia(scene) or
        !assets.overlapsRange(scene.spectral_grid.start_nm, scene.spectral_grid.end_nm, 760.8, 771.5))
    {
        return null;
    }

    return try assets.loadO2ACollisionInducedAbsorptionTable(allocator);
}

pub fn sampleSceneWavelengthsOwned(allocator: Allocator, scene: *const Scene) ![]f64 {
    // sampleSceneWavelengthsOwned ---------------------------------------------------------------------------|
    // Build the wavelength support used while generating operational O2 or O2-O2 LUTs from the source scene. |
    //                                                                                                        |
    // call path                                                                                              |
    //   workflows.zig calls this only for .generate LUT modes before replacing the working scene LUT handle. |
    //                                                                                                        |
    // route order                                                                                            |
    //   1. high-resolution LUT sampling expands nominal bounds by the instrument response half-span          |
    //   2. measured-channel scenes clone the measured wavelength list exactly                                |
    //   3. ordinary scenes build a uniform grid from spectral_grid start/end/sample_count                    |
    //                                                                                                        |
    // ownership                                                                                              |
    //   The returned slice is owned by the caller and freed after the generated LUT is built. The source     |
    //   Scene is borrowed and is not mutated here.                                                           |
    //                                                                                                        |
    // math                                                                                                   |
    //   lambda_i = start_nm + i * (end_nm - start_nm) / (sample_count - 1)                                   |
    // -------------------------------------------------------------------------------------------------------|

    const support = scene.observation_model.primaryOperationalBandSupport();
    const nominal_bounds = scene.lutNominalWavelengthBounds();
    const support_half_span_nm = scene.observation_model.lutSamplingHalfSpanNm();
    if (scene.usesHighResolutionLutSampling()) {
        return uniformWavelengthGridOwned(
            allocator,
            nominal_bounds.start_nm - support_half_span_nm,
            nominal_bounds.end_nm + support_half_span_nm,
            support.high_resolution_step_nm,
        );
    }

    if (scene.observation_model.measured_wavelengths_nm.len != 0) {
        return allocator.dupe(f64, scene.observation_model.measured_wavelengths_nm);
    }

    const sample_count: usize = scene.spectral_grid.sample_count;
    if (sample_count == 0) return error.InvalidRequest;

    const wavelengths_nm = try allocator.alloc(f64, sample_count);
    if (sample_count == 1) {
        wavelengths_nm[0] = scene.spectral_grid.start_nm;
        return wavelengths_nm;
    }

    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const step_nm = span_nm / @as(f64, @floatFromInt(sample_count - 1));
    for (wavelengths_nm, 0..) |*wavelength_nm, index| {
        wavelength_nm.* = scene.spectral_grid.start_nm + step_nm * @as(f64, @floatFromInt(index));
    }
    return wavelengths_nm;
}

fn uniformWavelengthGridOwned(
    allocator: Allocator,
    start_nm: f64,
    end_nm: f64,
    step_nm: f64,
) ![]f64 {
    // uniformWavelengthGridOwned ----------------------------------------------------------------------------|
    // Allocate an inclusive uniform grid for high-resolution LUT sampling.                                   |
    //                                                                                                        |
    // boundary                                                                                               |
    //   Invalid spans or non-positive steps are rejected before LUT generation can allocate empty or         |
    //   backwards support rows.                                                                              |
    //                                                                                                        |
    // math                                                                                                   |
    //   interval_count = ceil((end_nm - start_nm) / step_nm - 1.0e-12)                                       |
    //   lambda_i       = min(start_nm + i * step_nm, end_nm)                                                 |
    //                                                                                                        |
    // The small epsilon keeps an exact multiple of step_nm from gaining one extra endpoint from roundoff.    |
    // -------------------------------------------------------------------------------------------------------|

    if (!(step_nm > 0.0) or !std.math.isFinite(start_nm) or !std.math.isFinite(end_nm) or end_nm < start_nm) {
        return error.InvalidRequest;
    }

    const span_nm = end_nm - start_nm;
    const interval_count = @as(usize, @intFromFloat(@ceil((span_nm / step_nm) - 1.0e-12)));
    const sample_count = interval_count + 1;
    const wavelengths_nm = try allocator.alloc(f64, sample_count);
    for (wavelengths_nm, 0..) |*wavelength_nm, index| {
        wavelength_nm.* = @min(start_nm + step_nm * @as(f64, @floatFromInt(index)), end_nm);
    }
    return wavelengths_nm;
}
