const errors = @import("../common/errors.zig");
const o2_case = @import("o2_case.zig");

pub fn referenceCase(case: o2_case.O2Case) !void {
    // referenceCase ------------------------------------------------------------------------------------------|
    // Validate every control WP2 consumes so unsupported or malformed setup input cannot pass inertly.        |
    // --------------------------------------------------------------------------------------------------------|
    if (case.spectral_grid.sample_count < 2) return errors.Error.InvalidControl;
    if (case.spectral_grid.end_nm <= case.spectral_grid.start_nm) return errors.Error.InvalidControl;

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

    if (case.observation.instrument_line_fwhm_nm <= 0.0) return errors.Error.InvalidControl;
    if (case.observation.high_resolution_step_nm <= 0.0) return errors.Error.InvalidControl;

    if (case.line_gas.isotopes_sim.len == 0) return errors.Error.InvalidControl;
    if (case.line_gas.threshold_line_sim <= 0.0) return errors.Error.InvalidControl;
    if (case.line_gas.cutoff_sim_cm1 <= 0.0) return errors.Error.InvalidControl;

    if (!case.cia.enabled) return errors.Error.InvalidControl;
    if (case.rtm.stream_count == 0) return errors.Error.InvalidControl;
}
