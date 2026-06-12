const o2_case = @import("o2_case.zig");

const default_intervals = [_]o2_case.VerticalInterval{
    .{
        .index_1based = 1,
        .top_pressure_hpa = 0.3,
        .bottom_pressure_hpa = 500.0,
        .altitude_divisions = 28,
    },
    .{
        .index_1based = 2,
        .top_pressure_hpa = 500.0,
        .bottom_pressure_hpa = 520.0,
        .altitude_divisions = 6,
    },
    .{
        .index_1based = 3,
        .top_pressure_hpa = 520.0,
        .bottom_pressure_hpa = 1013.25,
        .altitude_divisions = 8,
    },
};

const default_isotopes = [_]u8{ 1, 2, 3 };

pub fn referenceCase() o2_case.O2Case {
    // referenceCase ------------------------------------------------------------------------------------------|
    // Return the default product O2 A case used by Python and public forward runs.                            |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .id = "o2a_disamar_reference_python",
        .spectral_grid = .{
            .start_nm = 755.0,
            .end_nm = 776.0,
            .sample_count = 701,
        },
        .surface_albedo = 0.2,
        .atmosphere = .{
            .profile = o2_case.asset(
                "atmosphere_profile",
                "data/reference_data/climatologies/vendor_config_o2a_profile.csv",
                "profile_csv",
            ),
            .surface_pressure_hpa = 1013.25,
            .layer_count = 3,
            .sublayer_divisions = 4,
            .fit_interval_index_1based = 2,
            .intervals = default_intervals[0..],
        },
        .geometry = .{
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 30.0,
            .relative_azimuth_deg = 120.0,
            .pseudo_spherical = true,
        },
        .aerosol = .{
            .optical_depth = 0.3,
            .single_scatter_albedo = 1.0,
            .asymmetry_factor = 0.7,
            .angstrom_exponent = 0.0,
            .reference_wavelength_nm = 550.0,
            .interval_index_1based = 2,
            .top_pressure_hpa = 500.0,
            .bottom_pressure_hpa = 520.0,
            .profile = &.{},
        },
        .observation = .{
            .instrument_name = "disamar-o2a-compare",
            .instrument_line_fwhm_nm = 0.38,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
            .adaptive_points_per_fwhm = 20,
            .strong_line_min_divisions = 8,
            .strong_line_max_divisions = 40,
            .solar_reference = o2_case.asset(
                "raw_solar_reference",
                "data/reference_data/solar/o2a_solar_reference_753_778.csv",
                "solar_reference_csv",
            ),
        },
        .line_gas = .{
            .line_list = o2_case.asset(
                "o2_hitran",
                "data/reference_data/cross_sections/o2a_hitran_07_hit08_tropomi.par",
                "hitran_par_o2a",
            ),
            .line_mixing = o2_case.asset(
                "o2_line_mixing",
                "data/reference_data/cross_sections/o2a_lisa_rmf.dat",
                "lisa_rmf",
            ),
            .strong_lines = o2_case.asset(
                "o2_strong_lines",
                "data/reference_data/cross_sections/o2a_lisa_sdf.dat",
                "lisa_sdf",
            ),
            .line_mixing_factor = 1.0,
            .isotopes_sim = default_isotopes[0..],
            .threshold_line_sim = 3.0e-5,
            .cutoff_sim_cm1 = 200.0,
        },
        .cia = .{
            .enabled = true,
            .table = o2_case.asset(
                "o2o2_cia",
                "data/reference_data/cross_sections/o2o2_bira_o2a.dat",
                "bira_cia",
            ),
        },
        .rtm = .{
            .stream_count = 20,
            .fourier_term_limit = 20,
        },
    };
}
