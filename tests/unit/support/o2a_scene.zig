const std = @import("std");
const internal = @import("internal");

const scene_input = internal.input.scene_input;

const reference_intervals = [_]scene_input.VerticalInterval{
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

const reference_isotopes = [_]u8{ 1, 2, 3 };
const output_isotopes = [_]usize{ 1, 2, 3 };

pub fn reference() scene_input.Scene {
    // reference --------------------------------------------------------------------------------------------- |
    // Test fixture matching the Python-owned default scene. Product code must receive scenes as input.   |
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
            .profile = scene_input.asset(
                "atmosphere_profile",
                "data/reference_data/climatologies/vendor_config_o2a_profile.csv",
                "profile_csv",
            ),
            .surface_pressure_hpa = 1013.25,
            .layer_count = 3,
            .sublayer_divisions = 4,
            .fit_interval_index_1based = 2,
            .intervals = reference_intervals[0..],
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
            .solar_reference = scene_input.asset(
                "raw_solar_reference",
                "data/reference_data/solar/o2a_solar_reference_753_778.csv",
                "solar_reference_csv",
            ),
            .measured_wavelengths_nm = &.{},
        },
        .line_gas = .{
            .line_list = scene_input.asset(
                "o2_hitran",
                "data/reference_data/cross_sections/o2a_hitran_07_hit08_tropomi.par",
                "hitran_par_o2a",
            ),
            .line_mixing = scene_input.asset(
                "o2_line_mixing",
                "data/reference_data/cross_sections/o2a_lisa_rmf.dat",
                "lisa_rmf",
            ),
            .strong_lines = scene_input.asset(
                "o2_strong_lines",
                "data/reference_data/cross_sections/o2a_lisa_sdf.dat",
                "lisa_sdf",
            ),
            .line_mixing_factor = 1.0,
            .isotopes_sim = reference_isotopes[0..],
            .threshold_line_sim = 3.0e-5,
            .cutoff_sim_cm1 = 200.0,
        },
        .cia = .{
            .enabled = true,
            .table = scene_input.asset(
                "o2o2_cia",
                "data/reference_data/cross_sections/o2o2_bira_o2a.dat",
                "bira_cia",
            ),
        },
        .rtm = .{
            .stream_count = 20,
            .fourier_term_limit = 20,
            .performance_thresholds = .o2a_default,
        },
    };
}

pub fn nativeJson(allocator: std.mem.Allocator) ![]u8 {
    // nativeJson -------------------------------------------------------------------------------------------- |
    // Render the test fixture through the same native JSON shape used by the Python input boundary.           |
    // --------------------------------------------------------------------------------------------------------|
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    try std.json.Stringify.value(nativeJsonPayload(reference()), .{}, &out.writer);
    return out.toOwnedSlice();
}

fn nativeJsonPayload(scene: scene_input.Scene) NativeSceneJson {
    const geometry_model = if (scene.geometry.pseudo_spherical) "pseudo_spherical" else "plane_parallel";

    return .{
        .metadata = .{
            .id = "disamar_reference_o2a",
            .storage = "disamar-reference-o2a",
            .description = "DISAMAR O2A reference scene defined in Python.",
        },
        .plan = .{ .derivative_mode = "none" },

        .inputs = .{
            .atmosphere_profile = scene.atmosphere.profile,
            .vendor_reference_csv = scene_input.asset(
                "vendor_reference_csv",
                "data/reference_data/validation/o2a_with_cia_disamar_reference.csv",
                "disamar_o2a_reference_csv",
            ),
            .raw_solar_reference = scene.observation.solar_reference,
            .airmass_factor_lut = scene_input.asset(
                "airmass_factor_lut",
                "data/reference_data/luts/airmass_factor_nadir_demo.csv",
                "csv",
            ),
        },

        .scene_id = scene.id,
        .spectral_grid = scene.spectral_grid,
        .layer_count = scene.atmosphere.layer_count,
        .sublayer_divisions = scene.atmosphere.sublayer_divisions,
        .surface_pressure_hpa = scene.atmosphere.surface_pressure_hpa,
        .fit_interval_index_1based = scene.atmosphere.fit_interval_index_1based,
        .intervals = scene.atmosphere.intervals,
        .surface_albedo = scene.surface_albedo,

        .geometry = .{
            .model = geometry_model,
            .solar_zenith_deg = scene.geometry.solar_zenith_deg,
            .viewing_zenith_deg = scene.geometry.viewing_zenith_deg,
            .relative_azimuth_deg = scene.geometry.relative_azimuth_deg,
        },

        .aerosol = .{
            .optical_depth = scene.aerosol.optical_depth,
            .single_scatter_albedo = scene.aerosol.single_scatter_albedo,
            .asymmetry_factor = scene.aerosol.asymmetry_factor,
            .angstrom_exponent = scene.aerosol.angstrom_exponent,
            .reference_wavelength_nm = scene.aerosol.reference_wavelength_nm,
            .placement = .{
                .semantics = "explicit_interval_bounds",
                .interval_index_1based = scene.aerosol.interval_index_1based,
                .top_pressure_hpa = scene.aerosol.top_pressure_hpa,
                .bottom_pressure_hpa = scene.aerosol.bottom_pressure_hpa,
            },
        },

        .observation = .{
            .instrument_name = scene.observation.instrument_name,
            .regime = "nadir",
            .sampling = "native",
            .instrument_line_fwhm_nm = scene.observation.instrument_line_fwhm_nm,
            .builtin_line_shape = "flat_top_n4",
            .high_resolution_step_nm = scene.observation.high_resolution_step_nm,
            .high_resolution_half_span_nm = scene.observation.high_resolution_half_span_nm,
            .adaptive_reference_grid = .{
                .points_per_fwhm = scene.observation.adaptive_points_per_fwhm,
                .strong_line_min_divisions = scene.observation.strong_line_min_divisions,
                .strong_line_max_divisions = scene.observation.strong_line_max_divisions,
            },
            .solar_reference_asset_id = scene.observation.solar_reference.id,
            .measured_wavelengths_nm = scene.observation.measured_wavelengths_nm,
        },

        .o2 = .{
            .line_list_asset = scene.line_gas.line_list,
            .line_mixing_asset = scene.line_gas.line_mixing,
            .strong_lines_asset = scene.line_gas.strong_lines,
            .line_mixing_factor = scene.line_gas.line_mixing_factor,
            .isotopes_sim = output_isotopes[0..],
            .threshold_line_sim = scene.line_gas.threshold_line_sim,
            .cutoff_sim_cm1 = scene.line_gas.cutoff_sim_cm1,
        },

        .o2o2 = .{
            .enabled = scene.cia.enabled,
            .cia_asset = scene.cia.table,
        },

        .rtm_controls = .{
            .scattering = "multiple",
            .n_streams = scene.rtm.stream_count,
            .performance_thresholds = .{},
            .use_spherical_correction = scene.geometry.pseudo_spherical,
            .integrate_source_function = true,
            .renorm_phase_function = true,
        },
    };
}

const MetadataJson = struct {
    id: []const u8,
    storage: []const u8,
    description: []const u8,
};

const PlanJson = struct {
    derivative_mode: []const u8,
};

const InputsJson = struct {
    atmosphere_profile: scene_input.Asset,
    vendor_reference_csv: scene_input.Asset,
    raw_solar_reference: scene_input.Asset,
    airmass_factor_lut: scene_input.Asset,
};

const GeometryJson = struct {
    model: []const u8,
    solar_zenith_deg: f64,
    viewing_zenith_deg: f64,
    relative_azimuth_deg: f64,
};

const AerosolPlacementJson = struct {
    semantics: []const u8,
    interval_index_1based: usize,
    top_pressure_hpa: f64,
    bottom_pressure_hpa: f64,
    top_altitude_km: ?f64 = null,
    bottom_altitude_km: ?f64 = null,
};

const AerosolJson = struct {
    optical_depth: f64,
    single_scatter_albedo: f64,
    asymmetry_factor: f64,
    angstrom_exponent: f64,
    reference_wavelength_nm: f64,
    placement: AerosolPlacementJson,
    profile: []const scene_input.AerosolProfileLayer = &.{},
};

const AdaptiveGridJson = struct {
    points_per_fwhm: usize,
    strong_line_min_divisions: usize,
    strong_line_max_divisions: usize,
};

const ObservationJson = struct {
    instrument_name: []const u8,
    regime: []const u8,
    sampling: []const u8,
    instrument_line_fwhm_nm: f64,
    builtin_line_shape: []const u8,
    high_resolution_step_nm: f64,
    high_resolution_half_span_nm: f64,
    adaptive_reference_grid: AdaptiveGridJson,
    solar_reference_asset_id: []const u8,
    measured_wavelengths_nm: []const f64 = &.{},
};

const OutputLineGasJson = struct {
    line_list_asset: scene_input.Asset,
    line_mixing_asset: scene_input.Asset,
    strong_lines_asset: scene_input.Asset,
    line_mixing_factor: f64,
    isotopes_sim: []const usize,
    threshold_line_sim: f64,
    cutoff_sim_cm1: f64,
};

const CiaJson = struct {
    enabled: bool,
    cia_asset: scene_input.Asset,
};

const PerformanceThresholdsJson = struct {
    num_orders_max: usize = 0,
    fourier_floor_scalar: usize = 2,
    fourier_order_cap: ?usize = null,
    aerosol_tangent_order_cap: ?usize = null,
    fourier_tail_reflectance_epsilon: f64 = 3.0e-14,
    threshold_conv_first: f64 = 1.5e-7,
    threshold_conv_mult: f64 = 1.5e-9,
    threshold_doubl: f64 = 1.0e-6,
    threshold_mul: f64 = 1.0e-8,
    phase_function_truncation_threshold: f64 = 1.0e-8,
};

const RtmControlsJson = struct {
    scattering: []const u8,
    n_streams: usize,
    performance_thresholds: PerformanceThresholdsJson,
    use_spherical_correction: bool,
    integrate_source_function: bool,
    renorm_phase_function: bool,
};

const NativeSceneJson = struct {
    metadata: MetadataJson,
    plan: PlanJson,
    inputs: InputsJson,
    scene_id: []const u8,
    spectral_grid: scene_input.SpectralGrid,
    layer_count: usize,
    sublayer_divisions: usize,
    surface_pressure_hpa: f64,
    fit_interval_index_1based: usize,
    intervals: []const scene_input.VerticalInterval,
    surface_albedo: f64,
    geometry: GeometryJson,
    aerosol: AerosolJson,
    observation: ObservationJson,
    o2: OutputLineGasJson,
    o2o2: CiaJson,
    rtm_controls: RtmControlsJson,
};
