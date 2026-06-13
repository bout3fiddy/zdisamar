const std = @import("std");

const errors = @import("../common/errors.zig");
const o2_case = @import("o2_case.zig");

const profile_pressure_tolerance_hpa: f64 = 1.0e-9;
const profile_spectral_tolerance: f64 = 1.0e-12;

pub fn o2Case(case: o2_case.O2Case) !void {
    // o2Case -------------------------------------------------------------------------------------------------|
    // Validate every control WP2 consumes so unsupported or malformed setup input cannot pass inertly.        |
    // --------------------------------------------------------------------------------------------------------|
    if (case.spectral_grid.sample_count < 2) return errors.Error.InvalidControl;
    if (case.spectral_grid.end_nm <= case.spectral_grid.start_nm) return errors.Error.InvalidControl;
    if (case.surface_albedo < 0.0 or case.surface_albedo > 1.0) return errors.Error.InvalidControl;

    if (case.atmosphere.layer_count == 0) return errors.Error.InvalidControl;
    if (case.atmosphere.sublayer_divisions == 0) return errors.Error.InvalidControl;
    if (case.atmosphere.intervals.len != case.atmosphere.layer_count) return errors.Error.InvalidControl;
    if (case.atmosphere.fit_interval_index_1based == 0) return errors.Error.InvalidControl;
    if (case.atmosphere.fit_interval_index_1based > case.atmosphere.intervals.len) {
        return errors.Error.InvalidControl;
    }

    for (case.atmosphere.intervals, 0..) |interval, index| {
        if (interval.index_1based != index + 1) return errors.Error.InvalidControl;
        if (interval.altitude_divisions == 0) return errors.Error.InvalidControl;
        if (interval.bottom_pressure_hpa <= interval.top_pressure_hpa) return errors.Error.InvalidControl;
    }

    if (case.aerosol.optical_depth < 0.0) return errors.Error.InvalidControl;
    if (case.aerosol.single_scatter_albedo < 0.0 or case.aerosol.single_scatter_albedo > 1.0) {
        return errors.Error.InvalidControl;
    }
    try aerosolProfile(case.aerosol.profile, case.atmosphere.intervals);

    if (case.observation.instrument_line_fwhm_nm <= 0.0) return errors.Error.InvalidControl;
    if (case.observation.high_resolution_step_nm <= 0.0) return errors.Error.InvalidControl;

    if (case.line_gas.isotopes_sim.len == 0) return errors.Error.InvalidControl;
    if (case.line_gas.threshold_line_sim <= 0.0) return errors.Error.InvalidControl;
    if (case.line_gas.cutoff_sim_cm1 <= 0.0) return errors.Error.InvalidControl;

    if (!case.cia.enabled) return errors.Error.InvalidControl;
    if (case.rtm.stream_count == 0) return errors.Error.InvalidControl;
    case.rtm.performance_thresholds.validate() catch return errors.Error.InvalidControl;
}

fn aerosolProfile(
    profile: []const o2_case.AerosolProfileLayer,
    intervals: []const o2_case.VerticalInterval,
) !void {
    // aerosolProfile -----------------------------------------------------------------------------------------|
    // Validate explicit aerosol profile rows against the pressure route consumed by setup tables.             |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Mirrors main:`src/input/Aerosol.zig` ProfileLayer.validate and the pressure-overlap rejection in      |
    //   main:`state_build/layer_accumulation.zig` buildAerosolProfileSublayerProperties.                      |
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

fn aerosolProfileLayer(layer: o2_case.AerosolProfileLayer) !void {
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
    layer: o2_case.AerosolProfileLayer,
    intervals: []const o2_case.VerticalInterval,
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
    left: o2_case.AerosolProfileLayer,
    right: o2_case.AerosolProfileLayer,
) bool {
    // profileLayersOverlap -----------------------------------------------------------------------------------|
    // Return whether two profile pressure spans contribute to any common support row.                         |
    // --------------------------------------------------------------------------------------------------------|
    return @min(left.bottom_pressure_hpa, right.bottom_pressure_hpa) >
        @max(left.top_pressure_hpa, right.top_pressure_hpa);
}

fn profileSpectralScalingMatches(
    left: o2_case.AerosolProfileLayer,
    right: o2_case.AerosolProfileLayer,
) bool {
    // profileSpectralScalingMatches --------------------------------------------------------------------------|
    // Keep overlapping profile rows on one wavelength-scaling law, matching the old profile merge gate.       |
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
