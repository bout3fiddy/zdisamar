const std = @import("std");
const Scene = @import("../../model/Scene.zig").Scene;
const AbsorberModel = @import("../../model/Absorber.zig");
const ReferenceData = @import("../../model/ReferenceData.zig");
const assets = @import("assets.zig");

const Allocator = std.mem.Allocator;
const AbsorberSpecies = AbsorberModel.AbsorberSpecies;

pub fn loadContinuumForScene(allocator: Allocator, scene: *const Scene) !ReferenceData.CrossSectionTable {
    if (assets.shouldLoadVisibleBandContinuum(scene)) {
        return try assets.loadVisibleBandContinuumTable(allocator);
    }

    // UNITS:
    //   The fallback table preserves the scene's spectral grid in nanometers while keeping the
    //   continuum coefficient identically zero.
    return assets.zeroContinuumTable(allocator, scene.spectral_grid.start_nm, scene.spectral_grid.end_nm);
}

pub fn loadSpectroscopyForScene(allocator: Allocator, scene: *const Scene) !?ReferenceData.SpectroscopyLineList {
    if (try assets.cloneResolvedSpectroscopyLineList(allocator, scene)) |line_list| {
        return line_list;
    }
    if (assets.hasExplicitSpectroscopyBindings(scene)) {
        // GOTCHA:
        //   Explicit asset bindings must resolve; otherwise a missing asset would silently mask a
        //   configuration problem if we fell back to bundled defaults here.
        return error.UnresolvedSpectroscopyBinding;
    }

    if (assets.shouldLoadBundledO2ALineList(scene) and
        assets.overlapsRange(scene.spectral_grid.start_nm, scene.spectral_grid.end_nm, 760.8, 771.5))
    {
        return try assets.loadO2aSpectroscopyLineList(allocator);
    }

    if (assets.shouldLoadVisibleBandLineList(scene)) {
        return try assets.loadVisibleBandLineList(allocator);
    }

    return null;
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
        // GOTCHA:
        //   Explicit CIA bindings must be materialized or the scene configuration is incomplete.
        return error.UnresolvedCollisionInducedAbsorptionBinding;
    }
    if (scene.observation_model.primaryOperationalBandSupport().o2o2_operational_lut.enabled() and !generating_o2o2_lut) {
        // DECISION:
        //   The operational LUT takes precedence over the bundled O2-O2 CIA sidecar to preserve
        //   the runtime control path expected by the scene configuration.
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
