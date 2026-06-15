const std = @import("std");

const errors = @import("../common/errors.zig");
const scene_input = @import("scene.zig");

const profile_pressure_tolerance_hpa: f64 = 1.0e-9;
const profile_spectral_tolerance: f64 = 1.0e-12;

pub fn sceneControls(scene: scene_input.Scene) !void {
    // sceneControls ------------------------------------------------------------------------------------------|
    // Validate every control O2 A consumes so unsupported or malformed setup input cannot pass inertly.       |
    // --------------------------------------------------------------------------------------------------------|
    if (scene.spectral_grid.sample_count < 2) return errors.Error.InvalidControl;

    if (!std.math.isFinite(scene.spectral_grid.start_nm) or
        !std.math.isFinite(scene.spectral_grid.end_nm) or
        scene.spectral_grid.end_nm <= scene.spectral_grid.start_nm)
    {
        return errors.Error.InvalidControl;
    }

    if (!std.math.isFinite(scene.surface_albedo) or
        scene.surface_albedo < 0.0 or
        scene.surface_albedo > 1.0)
    {
        return errors.Error.InvalidControl;
    }
    try measuredWavelengths(scene.spectral_grid, scene.observation.measured_wavelengths_nm);

    if (scene.atmosphere.layer_count == 0) return errors.Error.InvalidControl;
    if (scene.atmosphere.sublayer_divisions == 0) return errors.Error.InvalidControl;
    if (scene.atmosphere.intervals.len != scene.atmosphere.layer_count) return errors.Error.InvalidControl;
    if (scene.atmosphere.fit_interval_index_1based == 0) return errors.Error.InvalidControl;
    if (scene.atmosphere.fit_interval_index_1based > scene.atmosphere.intervals.len) {
        return errors.Error.InvalidControl;
    }

    for (scene.atmosphere.intervals, 0..) |interval, index| {
        if (interval.index_1based != index + 1) return errors.Error.InvalidControl;

        if (interval.altitude_divisions == 0) return errors.Error.InvalidControl;

        if (!std.math.isFinite(interval.top_pressure_hpa) or
            !std.math.isFinite(interval.bottom_pressure_hpa) or
            interval.bottom_pressure_hpa <= interval.top_pressure_hpa)
        {
            return errors.Error.InvalidControl;
        }

        if (index != 0 and
            !std.math.approxEqAbs(
                f64,
                scene.atmosphere.intervals[index - 1].bottom_pressure_hpa,
                interval.top_pressure_hpa,
                profile_pressure_tolerance_hpa,
            ))
        {
            return errors.Error.InvalidControl;
        }
    }

    try aerosolScalar(scene.aerosol, scene.atmosphere.intervals);
    try aerosolProfile(scene.aerosol.profile, scene.atmosphere.intervals);

    if (!std.math.isFinite(scene.observation.instrument_line_fwhm_nm) or
        !std.math.isFinite(scene.observation.high_resolution_step_nm) or
        !std.math.isFinite(scene.observation.high_resolution_half_span_nm) or
        scene.observation.instrument_line_fwhm_nm <= 0.0 or
        scene.observation.high_resolution_step_nm <= 0.0 or
        scene.observation.high_resolution_half_span_nm < 0.0)
    {
        return errors.Error.InvalidControl;
    }

    if (scene.line_gas.isotopes_sim.len == 0) return errors.Error.InvalidControl;

    for (scene.line_gas.isotopes_sim) |isotope| {
        if (isotope == 0) return errors.Error.InvalidControl;
    }

    if (!std.math.isFinite(scene.line_gas.line_mixing_factor) or
        !std.math.isFinite(scene.line_gas.threshold_line_sim) or
        !std.math.isFinite(scene.line_gas.cutoff_sim_cm1) or
        scene.line_gas.threshold_line_sim <= 0.0 or
        scene.line_gas.cutoff_sim_cm1 <= 0.0)
    {
        return errors.Error.InvalidControl;
    }

    if (!scene.cia.enabled) return errors.Error.InvalidControl;
    if (scene.rtm.stream_count == 0) return errors.Error.InvalidControl;
    if (scene.rtm.fourier_term_limit == 0 or
        scene.rtm.fourier_term_limit > @as(usize, std.math.maxInt(u16)) + 1)
    {
        return errors.Error.InvalidControl;
    }
    scene.rtm.performance_thresholds.validate() catch return errors.Error.InvalidControl;
}

fn aerosolScalar(
    aerosol: scene_input.AerosolControls,
    intervals: []const scene_input.VerticalInterval,
) !void {
    // aerosolScalar ------------------------------------------------------------------------------------------|
    // Validate the scalar aerosol controls and their declared pressure interval.                              |
    // --------------------------------------------------------------------------------------------------------|
    if (!std.math.isFinite(aerosol.optical_depth) or aerosol.optical_depth < 0.0) {
        return errors.Error.InvalidControl;
    }

    if (!std.math.isFinite(aerosol.single_scatter_albedo) or
        aerosol.single_scatter_albedo < 0.0 or
        aerosol.single_scatter_albedo > 1.0)
    {
        return errors.Error.InvalidControl;
    }

    if (!std.math.isFinite(aerosol.asymmetry_factor) or
        aerosol.asymmetry_factor < -1.0 or
        aerosol.asymmetry_factor > 1.0)
    {
        return errors.Error.InvalidControl;
    }

    if (!std.math.isFinite(aerosol.angstrom_exponent) or
        !std.math.isFinite(aerosol.reference_wavelength_nm) or
        aerosol.reference_wavelength_nm <= 0.0)
    {
        return errors.Error.InvalidControl;
    }

    if (aerosol.interval_index_1based == 0 or aerosol.interval_index_1based > intervals.len) {
        return errors.Error.InvalidControl;
    }

    if (!std.math.isFinite(aerosol.top_pressure_hpa) or
        !std.math.isFinite(aerosol.bottom_pressure_hpa) or
        !(aerosol.top_pressure_hpa < aerosol.bottom_pressure_hpa))
    {
        return errors.Error.InvalidControl;
    }

    if (!scalarAerosolMatchesInterval(aerosol, intervals[aerosol.interval_index_1based - 1])) {
        return errors.Error.InvalidRequest;
    }
}

fn scalarAerosolMatchesInterval(
    aerosol: scene_input.AerosolControls,
    interval: scene_input.VerticalInterval,
) bool {
    // scalarAerosolMatchesInterval ---------------------------------------------------------------------------|
    // Ensure the enabled scalar aerosol layer belongs to the selected atmosphere interval.                    |
    // --------------------------------------------------------------------------------------------------------|
    return aerosol.top_pressure_hpa + profile_pressure_tolerance_hpa >= interval.top_pressure_hpa and
        aerosol.bottom_pressure_hpa <= interval.bottom_pressure_hpa + profile_pressure_tolerance_hpa;
}

fn measuredWavelengths(
    grid: scene_input.SpectralGrid,
    wavelengths_nm: []const f64,
) !void {
    // measuredWavelengths ----------------------------------------------------------------------------------- |
    // Validate the optional sparse product axis consumed by fastmode and correction routes.                   |
    //                                                                                                         |
    // contract                                                                                                |
    //   An empty slice means the endpoint-inclusive uniform SpectralGrid is the product axis. A non-empty     |
    //   slice is the exact product axis; its count and endpoints must agree with SpectralGrid so support      |
    //   planning still has one global wavelength span.                                                        |
    // --------------------------------------------------------------------------------------------------------|
    if (wavelengths_nm.len == 0) return;
    if (wavelengths_nm.len != grid.sample_count) return errors.Error.InvalidControl;

    for (wavelengths_nm, 0..) |wavelength_nm, index| {
        if (!std.math.isFinite(wavelength_nm)) return errors.Error.InvalidControl;
        if (index != 0 and wavelength_nm <= wavelengths_nm[index - 1]) {
            return errors.Error.InvalidControl;
        }
    }

    if (!std.math.approxEqAbs(f64, wavelengths_nm[0], grid.start_nm, profile_spectral_tolerance) or
        !std.math.approxEqAbs(
            f64,
            wavelengths_nm[wavelengths_nm.len - 1],
            grid.end_nm,
            profile_spectral_tolerance,
        ))
    {
        return errors.Error.InvalidControl;
    }
}

fn aerosolProfile(
    profile: []const scene_input.AerosolProfileLayer,
    intervals: []const scene_input.VerticalInterval,
) !void {
    // aerosolProfile -----------------------------------------------------------------------------------------|
    // Validate explicit aerosol profile rows against the pressure route consumed by setup tables.             |
    //                                                                                                         |
    // --------------------------------------------------------------------------------------------------------|
    for (profile) |layer| {
        try aerosolProfileLayer(layer);
        if (layer.optical_depth == 0.0) continue;
        if (!profileLayerCoveredByIntervals(layer, intervals)) return errors.Error.InvalidRequest;
    }

    for (profile, 0..) |left, left_index| {
        if (left.optical_depth == 0.0) continue;
        for (profile[left_index + 1 ..]) |right| {
            if (right.optical_depth == 0.0) continue;
            if (!profileLayersOverlap(left, right)) continue;
            if (!profileSpectralScalingMatches(left, right)) return errors.Error.InvalidRequest;
        }
    }
}

fn aerosolProfileLayer(layer: scene_input.AerosolProfileLayer) !void {
    // aerosolProfileLayer ------------------------------------------------------------------------------------|
    // Enforce physical bounds for one explicit aerosol profile layer.                                         |
    // --------------------------------------------------------------------------------------------------------|
    if (!std.math.isFinite(layer.top_pressure_hpa) or
        !std.math.isFinite(layer.bottom_pressure_hpa) or
        !(layer.top_pressure_hpa < layer.bottom_pressure_hpa) or
        layer.top_pressure_hpa < 0.0)
    {
        return errors.Error.InvalidRequest;
    }

    if (!std.math.isFinite(layer.optical_depth) or layer.optical_depth < 0.0) {
        return errors.Error.InvalidRequest;
    }

    if (!std.math.isFinite(layer.single_scatter_albedo) or
        layer.single_scatter_albedo < 0.0 or
        layer.single_scatter_albedo > 1.0)
    {
        return errors.Error.InvalidRequest;
    }

    if (!std.math.isFinite(layer.asymmetry_factor) or
        layer.asymmetry_factor < -1.0 or
        layer.asymmetry_factor > 1.0)
    {
        return errors.Error.InvalidRequest;
    }

    if (!std.math.isFinite(layer.angstrom_exponent) or
        !std.math.isFinite(layer.reference_wavelength_nm) or
        layer.reference_wavelength_nm <= 0.0)
    {
        return errors.Error.InvalidRequest;
    }
}

fn profileLayerCoveredByIntervals(
    layer: scene_input.AerosolProfileLayer,
    intervals: []const scene_input.VerticalInterval,
) bool {
    // profileLayerCoveredByIntervals -------------------------------------------------------------------------|
    // Check that the public profile pressure span is covered by configured atmosphere interval bounds.        |
    // --------------------------------------------------------------------------------------------------------|
    const layer_pressure_span = layer.bottom_pressure_hpa - layer.top_pressure_hpa;
    if (layer_pressure_span <= 0.0) return false;

    var covered_pressure_span: f64 = 0.0;
    for (intervals) |interval| {
        const overlap_top = @max(layer.top_pressure_hpa, interval.top_pressure_hpa);
        const overlap_bottom = @min(layer.bottom_pressure_hpa, interval.bottom_pressure_hpa);
        covered_pressure_span += @max(overlap_bottom - overlap_top, 0.0);
    }
    return covered_pressure_span + profile_pressure_tolerance_hpa >= layer_pressure_span;
}

fn profileLayersOverlap(
    left: scene_input.AerosolProfileLayer,
    right: scene_input.AerosolProfileLayer,
) bool {
    // profileLayersOverlap -----------------------------------------------------------------------------------|
    // Return whether two profile pressure spans contribute to any common support row.                         |
    // --------------------------------------------------------------------------------------------------------|
    return @min(left.bottom_pressure_hpa, right.bottom_pressure_hpa) >
        @max(left.top_pressure_hpa, right.top_pressure_hpa);
}

fn profileSpectralScalingMatches(
    left: scene_input.AerosolProfileLayer,
    right: scene_input.AerosolProfileLayer,
) bool {
    // profileSpectralScalingMatches --------------------------------------------------------------------------|
    // Keep overlapping profile rows on one wavelength-scaling law, matching the profile merge gate.           |
    // --------------------------------------------------------------------------------------------------------|
    return std.math.approxEqAbs(
        f64,
        left.reference_wavelength_nm,
        right.reference_wavelength_nm,
        profile_spectral_tolerance,
    ) and std.math.approxEqAbs(
        f64,
        left.angstrom_exponent,
        right.angstrom_exponent,
        profile_spectral_tolerance,
    );
}
