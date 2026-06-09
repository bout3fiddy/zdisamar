const std = @import("std");
const Scene = @import("../../Scene.zig").Scene;
const AbsorberModel = @import("../../Absorber.zig");
const ReferenceData = @import("../../ReferenceData.zig");
const assets = @import("assets.zig");

const Allocator = std.mem.Allocator;
const AbsorberSpecies = AbsorberModel.AbsorberSpecies;

// selection.zig ---------------------------------------------------------------------------------------------|
// Chooses bundled reference assets for a typed Scene when no explicit asset binding is present.              |
//                                                                                                            |
// boundary                                                                                                   |
//   This file may load bundled input assets, but it does not parse user control files. Explicit unresolved   |
//   bindings are rejected instead of falling back to defaults.                                               |
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
