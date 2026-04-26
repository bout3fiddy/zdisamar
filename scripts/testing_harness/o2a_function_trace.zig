const std = @import("std");
const internal = @import("zdisamar_internal");
const vendor_support = internal.vendor_o2a_trace_support;

const Measurement = internal.kernels.transport.measurement;
const TransportCommon = internal.kernels.transport.common;
const Labos = internal.kernels.transport.labos;
const Calibration = internal.kernels.spectra.calibration;
const ReferenceData = internal.reference_data;
const InstrumentProviders = internal.plugin_internal.providers.Instrument;
const InstrumentIntegration = internal.plugin_internal.providers.instrument_integration;
const OpticsPrepare = internal.kernels.optics.preparation;

const default_wavelengths_nm = [_]f64{761.75};

const LineCatalogRow = struct {
    source_row_index: usize,
    gas_index: u16,
    isotope_number: u8,
    center_wavelength_nm: f64,
    center_wavenumber_cm1: f64,
    line_strength_cm2_per_molecule: f64,
    air_half_width_nm: f64,
    temperature_exponent: f64,
    lower_state_energy_cm1: f64,
    pressure_shift_nm: f64,
    line_mixing_coefficient: f64,
    branch_ic1: f64,
    branch_ic2: f64,
    rotational_nf: f64,
};

const StrongStateRow = struct {
    pressure_hpa: f64,
    temperature_k: f64,
    strong_index: usize,
    center_wavelength_nm: f64,
    center_wavenumber_cm1: f64,
    sig_moy_cm1: f64,
    population_t: f64,
    dipole_t: f64,
    mod_sig_cm1: f64,
    half_width_cm1_at_t: f64,
    line_mixing_coefficient: f64,
};

const SpectroscopySummaryRow = struct {
    pressure_hpa: f64,
    temperature_k: f64,
    wavelength_nm: f64,
    weak_sigma_cm2_per_molecule: f64,
    strong_sigma_cm2_per_molecule: f64,
    line_mixing_sigma_cm2_per_molecule: f64,
    total_sigma_cm2_per_molecule: f64,
};

const WeakLineContributorRow = struct {
    pressure_hpa: f64,
    temperature_k: f64,
    wavelength_nm: f64,
    sample_wavelength_nm: f64,
    source_row_index: f64,
    contribution_kind: []const u8,
    gas_index: u16,
    isotope_number: u8,
    center_wavelength_nm: f64,
    center_wavenumber_cm1: f64,
    shifted_center_wavenumber_cm1: f64,
    line_strength_cm2_per_molecule: f64,
    air_half_width_nm: f64,
    temperature_exponent: f64,
    lower_state_energy_cm1: f64,
    pressure_shift_nm: f64,
    line_mixing_coefficient: f64,
    branch_ic1: f64,
    branch_ic2: f64,
    rotational_nf: f64,
    matched_strong_index: f64,
    weak_line_sigma_cm2_per_molecule: f64,
};

const SublayerOpticsRow = struct {
    wavelength_nm: f64,
    global_sublayer_index: u32,
    interval_index_1based: u32,
    altitude_km: f64,
    support_weight_km: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    oxygen_number_density_cm3: f64,
    line_cross_section_cm2_per_molecule: f64,
    line_mixing_cross_section_cm2_per_molecule: f64,
    cia_sigma_cm5_per_molecule2: f64,
    gas_absorption_optical_depth: f64,
    gas_scattering_optical_depth: f64,
    cia_optical_depth: f64,
    path_length_cm: f64,
    aerosol_optical_depth: f64,
    aerosol_scattering_optical_depth: f64,
    cloud_optical_depth: f64,
    cloud_scattering_optical_depth: f64,
    total_scattering_optical_depth: f64,
    total_optical_depth: f64,
    combined_phase_coef_0: f64,
    combined_phase_coef_1: f64,
    combined_phase_coef_2: f64,
    combined_phase_coef_3: f64,
    combined_phase_coef_10: f64,
    combined_phase_coef_20: f64,
    combined_phase_coef_39: f64,
};

const IntervalBoundRow = struct {
    nominal_wavelength_nm: f64,
    boundary_index_0based: usize,
    interval_index_1based: u32,
    pressure_hpa: f64,
    altitude_km: f64,
};

const AdaptiveGridRow = struct {
    nominal_wavelength_nm: f64,
    interval_kind: []const u8,
    source_center_wavelength_nm: f64,
    interval_start_nm: f64,
    interval_end_nm: f64,
    division_count: usize,
};

const KernelSampleRow = struct {
    nominal_wavelength_nm: f64,
    sample_index: usize,
    sample_wavelength_nm: f64,
    weight: f64,
};

const TransportSampleRow = struct {
    nominal_wavelength_nm: f64,
    sample_index: usize,
    sample_wavelength_nm: f64,
    radiance: f64,
    irradiance: f64,
    weight: f64,
};

const TransportSummaryRow = struct {
    nominal_wavelength_nm: f64,
    final_radiance: f64,
    final_irradiance: f64,
    final_reflectance: f64,
};

const FourierTermRow = struct {
    nominal_wavelength_nm: f64,
    sample_index: usize,
    sample_wavelength_nm: f64,
    kernel_weight: f64,
    fourier_index: usize,
    refl_fc: f64,
    source_refl_fc: f64,
    surface_refl_fc: f64,
    surface_e_view: f64,
    surface_u_view_solar: f64,
    fourier_weight: f64,
    weighted_refl: f64,
};

const TransportLayerRow = struct {
    nominal_wavelength_nm: f64,
    sample_index: usize,
    sample_wavelength_nm: f64,
    kernel_weight: f64,
    layer_index: usize,
    optical_depth: f64,
    scattering_optical_depth: f64,
    single_scatter_albedo: f64,
    phase_coef_0: f64,
    phase_coef_1: f64,
    phase_coef_2: f64,
    phase_coef_3: f64,
    phase_coef_10: f64,
    phase_coef_20: f64,
    phase_coef_39: f64,
};

const SourceTermRow = struct {
    nominal_wavelength_nm: f64,
    sample_index: usize,
    sample_wavelength_nm: f64,
    kernel_weight: f64,
    fourier_index: usize,
    level_index: usize,
    rtm_weight: f64,
    ksca: f64,
    source_contribution: f64,
    weighted_source_contribution: f64,
};

const AttenuationTermRow = struct {
    nominal_wavelength_nm: f64,
    sample_index: usize,
    sample_wavelength_nm: f64,
    kernel_weight: f64,
    direction_kind: []const u8,
    direction_index: usize,
    level_index: usize,
    sumkext: f64,
    attenuation_top_to_level: f64,
    grid_valid: u8,
};

const PseudoSphericalSampleRow = struct {
    nominal_wavelength_nm: f64,
    sample_index: usize,
    sample_wavelength_nm: f64,
    kernel_weight: f64,
    global_sample_index: usize,
    altitude_km: f64,
    support_weight_km: f64,
    optical_depth: f64,
    radius_weighted_optical_depth: f64,
    grid_valid: u8,
};

const OrderSurfaceRow = struct {
    nominal_wavelength_nm: f64,
    sample_index: usize,
    sample_wavelength_nm: f64,
    kernel_weight: f64,
    fourier_index: usize,
    order_index: usize,
    stop_reason: []const u8,
    max_value: f64,
    surface_u_order: f64,
    surface_u_accumulated: f64,
    surface_d_order: f64,
    surface_e_view: f64,
};

const SourceAngleComponentRow = struct {
    nominal_wavelength_nm: f64,
    sample_index: usize,
    sample_wavelength_nm: f64,
    kernel_weight: f64,
    fourier_index: usize,
    level_index: usize,
    component_kind: []const u8,
    angle_index: usize,
    phase_value: f64,
    field_value: f64,
    angle_contribution: f64,
    weighted_angle_contribution: f64,
};

const ThermodynamicState = struct {
    pressure_hpa: f64,
    temperature_k: f64,
};

const CliConfig = struct {
    trace_root: []const u8,
    wavelengths_nm: []f64,
};

const TraceWavelength = struct {
    nominal_nm: f64,
    sample_nm: f64,
};

const TraceFiles = struct {
    line_catalog: std.fs.File,
    strong_state: std.fs.File,
    spectroscopy_summary: std.fs.File,
    weak_line_contributors: std.fs.File,
    sublayer_optics: std.fs.File,
    interval_bounds: std.fs.File,
    adaptive_grid: std.fs.File,
    kernel_samples: std.fs.File,
    transport_samples: std.fs.File,
    transport_summary: std.fs.File,
    fourier_terms: std.fs.File,
    transport_layers: std.fs.File,
    transport_source_terms: std.fs.File,
    transport_attenuation_terms: std.fs.File,
    transport_pseudo_spherical_samples: std.fs.File,
    transport_radiance_contributions: std.fs.File,
    transport_order_surface: std.fs.File,
    transport_source_components: std.fs.File,
    transport_source_angle_components: std.fs.File,
    transport_pseudo_spherical_terms: std.fs.File,
    transport_optical_depth_components: std.fs.File,

    fn init(
        allocator: std.mem.Allocator,
        trace_root: []const u8,
    ) !TraceFiles {
        const side_root = try std.fs.path.join(allocator, &.{ trace_root, "yaml" });
        defer allocator.free(side_root);
        try std.fs.cwd().makePath(side_root);

        return .{
            .line_catalog = try createCsvFile(allocator, side_root, "line_catalog.csv", "source_row_index,gas_index,isotope_number,center_wavelength_nm,center_wavenumber_cm1,line_strength_cm2_per_molecule,air_half_width_nm,temperature_exponent,lower_state_energy_cm1,pressure_shift_nm,line_mixing_coefficient,branch_ic1,branch_ic2,rotational_nf\n"),
            .strong_state = try createCsvFile(allocator, side_root, "strong_state.csv", "pressure_hpa,temperature_k,strong_index,center_wavelength_nm,center_wavenumber_cm1,sig_moy_cm1,population_t,dipole_t,mod_sig_cm1,half_width_cm1_at_t,line_mixing_coefficient\n"),
            .spectroscopy_summary = try createCsvFile(allocator, side_root, "spectroscopy_summary.csv", "pressure_hpa,temperature_k,wavelength_nm,weak_sigma_cm2_per_molecule,strong_sigma_cm2_per_molecule,line_mixing_sigma_cm2_per_molecule,total_sigma_cm2_per_molecule\n"),
            .weak_line_contributors = try createCsvFile(allocator, side_root, "weak_line_contributors.csv", "pressure_hpa,temperature_k,wavelength_nm,sample_wavelength_nm,source_row_index,contribution_kind,gas_index,isotope_number,center_wavelength_nm,center_wavenumber_cm1,shifted_center_wavenumber_cm1,line_strength_cm2_per_molecule,air_half_width_nm,temperature_exponent,lower_state_energy_cm1,pressure_shift_nm,line_mixing_coefficient,branch_ic1,branch_ic2,rotational_nf,matched_strong_index,weak_line_sigma_cm2_per_molecule\n"),
            .sublayer_optics = try createCsvFile(allocator, side_root, "sublayer_optics.csv", "wavelength_nm,global_sublayer_index,interval_index_1based,altitude_km,support_weight_km,pressure_hpa,temperature_k,number_density_cm3,oxygen_number_density_cm3,line_cross_section_cm2_per_molecule,line_mixing_cross_section_cm2_per_molecule,cia_sigma_cm5_per_molecule2,gas_absorption_optical_depth,gas_scattering_optical_depth,cia_optical_depth,path_length_cm,aerosol_optical_depth,aerosol_scattering_optical_depth,cloud_optical_depth,cloud_scattering_optical_depth,total_scattering_optical_depth,total_optical_depth,combined_phase_coef_0,combined_phase_coef_1,combined_phase_coef_2,combined_phase_coef_3,combined_phase_coef_10,combined_phase_coef_20,combined_phase_coef_39\n"),
            .interval_bounds = try createCsvFile(allocator, side_root, "interval_bounds.csv", "nominal_wavelength_nm,boundary_index_0based,interval_index_1based,pressure_hpa,altitude_km\n"),
            .adaptive_grid = try createCsvFile(allocator, side_root, "adaptive_grid.csv", "nominal_wavelength_nm,interval_kind,source_center_wavelength_nm,interval_start_nm,interval_end_nm,division_count\n"),
            .kernel_samples = try createCsvFile(allocator, side_root, "kernel_samples.csv", "nominal_wavelength_nm,sample_index,sample_wavelength_nm,weight\n"),
            .transport_samples = try createCsvFile(allocator, side_root, "transport_samples.csv", "nominal_wavelength_nm,sample_index,sample_wavelength_nm,radiance,irradiance,weight\n"),
            .transport_summary = try createCsvFile(allocator, side_root, "transport_summary.csv", "nominal_wavelength_nm,final_radiance,final_irradiance,final_reflectance\n"),
            .fourier_terms = try createCsvFile(allocator, side_root, "fourier_terms.csv", "nominal_wavelength_nm,sample_index,sample_wavelength_nm,kernel_weight,fourier_index,refl_fc,source_refl_fc,surface_refl_fc,surface_e_view,surface_u_view_solar,fourier_weight,weighted_refl\n"),
            .transport_layers = try createCsvFile(allocator, side_root, "transport_layers.csv", "nominal_wavelength_nm,sample_index,sample_wavelength_nm,kernel_weight,layer_index,optical_depth,scattering_optical_depth,single_scatter_albedo,phase_coef_0,phase_coef_1,phase_coef_2,phase_coef_3,phase_coef_10,phase_coef_20,phase_coef_39\n"),
            .transport_source_terms = try createCsvFile(allocator, side_root, "transport_source_terms.csv", "nominal_wavelength_nm,sample_index,sample_wavelength_nm,kernel_weight,fourier_index,level_index,rtm_weight,ksca,source_contribution,weighted_source_contribution\n"),
            .transport_attenuation_terms = try createCsvFile(allocator, side_root, "transport_attenuation_terms.csv", "nominal_wavelength_nm,sample_index,sample_wavelength_nm,kernel_weight,direction_kind,direction_index,level_index,sumkext,attenuation_top_to_level,grid_valid\n"),
            .transport_pseudo_spherical_samples = try createCsvFile(allocator, side_root, "transport_pseudo_spherical_samples.csv", "nominal_wavelength_nm,sample_index,sample_wavelength_nm,kernel_weight,global_sample_index,altitude_km,support_weight_km,optical_depth,radius_weighted_optical_depth,grid_valid\n"),
            .transport_radiance_contributions = try createCsvFile(allocator, side_root, "transport_radiance_contributions.csv", "nominal_wavelength_nm,sample_index,sample_wavelength_nm,kernel_weight,reflectance,irradiance,radiance,weighted_radiance_contribution\n"),
            .transport_order_surface = try createCsvFile(allocator, side_root, "transport_order_surface.csv", "nominal_wavelength_nm,sample_index,sample_wavelength_nm,kernel_weight,fourier_index,order_index,stop_reason,max_value,surface_u_order,surface_u_accumulated,surface_d_order,surface_e_view\n"),
            .transport_source_components = try createCsvFile(allocator, side_root, "transport_source_components.csv", "nominal_wavelength_nm,sample_index,sample_wavelength_nm,kernel_weight,fourier_index,level_index,e_view,pmin_ed,pplusst_u,source_over_ksca,source_contribution,weighted_source_contribution\n"),
            .transport_source_angle_components = try createCsvFile(allocator, side_root, "transport_source_angle_components.csv", "nominal_wavelength_nm,sample_index,sample_wavelength_nm,kernel_weight,fourier_index,level_index,component_kind,angle_index,phase_value,field_value,angle_contribution,weighted_angle_contribution\n"),
            .transport_pseudo_spherical_terms = try createCsvFile(allocator, side_root, "transport_pseudo_spherical_terms.csv", "nominal_wavelength_nm,sample_index,sample_wavelength_nm,kernel_weight,direction_kind,direction_index,level_index,global_sample_index,level_altitude_km,level_radius_km,sample_altitude_km,sample_radius_km,numerator,denominator,contribution,cumulative_sumkext,grid_valid\n"),
            .transport_optical_depth_components = try createCsvFile(allocator, side_root, "transport_optical_depth_components.csv", "wavelength_nm,global_sublayer_index,interval_index_1based,line_absorption_optical_depth,cia_optical_depth,gas_scattering_optical_depth,aerosol_optical_depth,cloud_optical_depth,total_absorption_optical_depth,total_scattering_optical_depth,total_optical_depth\n"),
        };
    }

    fn deinit(self: *TraceFiles) void {
        self.line_catalog.close();
        self.strong_state.close();
        self.spectroscopy_summary.close();
        self.weak_line_contributors.close();
        self.sublayer_optics.close();
        self.interval_bounds.close();
        self.adaptive_grid.close();
        self.kernel_samples.close();
        self.transport_samples.close();
        self.transport_summary.close();
        self.fourier_terms.close();
        self.transport_layers.close();
        self.transport_source_terms.close();
        self.transport_attenuation_terms.close();
        self.transport_pseudo_spherical_samples.close();
        self.transport_radiance_contributions.close();
        self.transport_order_surface.close();
        self.transport_source_components.close();
        self.transport_source_angle_components.close();
        self.transport_pseudo_spherical_terms.close();
        self.transport_optical_depth_components.close();
        self.* = undefined;
    }
};

const TransportBuffers = struct {
    layer_inputs: []TransportCommon.LayerInput,
    pseudo_spherical_layers: []TransportCommon.LayerInput,
    source_interfaces: []TransportCommon.SourceInterfaceInput,
    rtm_quadrature_levels: []TransportCommon.RtmQuadratureLevel,
    pseudo_spherical_samples: []TransportCommon.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    evaluation_cache: Measurement.spectral_eval.SpectralEvaluationCache,

    fn init(
        allocator: std.mem.Allocator,
        scene: *const internal.Scene,
        route: TransportCommon.Route,
        prepared: *const OpticsPrepare.PreparedOpticalState,
    ) !TransportBuffers {
        const transport_layer_count = Measurement.workspace.resolvedTransportLayerCount(route, prepared);
        const pseudo_spherical_count = Measurement.workspace.resolvedPseudoSphericalSampleCount(scene, route, prepared);
        return .{
            .layer_inputs = try allocator.alloc(TransportCommon.LayerInput, transport_layer_count),
            .pseudo_spherical_layers = try allocator.alloc(TransportCommon.LayerInput, pseudo_spherical_count),
            .source_interfaces = try allocator.alloc(TransportCommon.SourceInterfaceInput, transport_layer_count + 1),
            .rtm_quadrature_levels = try allocator.alloc(TransportCommon.RtmQuadratureLevel, transport_layer_count + 1),
            .pseudo_spherical_samples = try allocator.alloc(TransportCommon.PseudoSphericalSample, pseudo_spherical_count),
            .pseudo_spherical_level_starts = try allocator.alloc(usize, transport_layer_count + 1),
            .pseudo_spherical_level_altitudes = try allocator.alloc(f64, transport_layer_count + 1),
            .evaluation_cache = Measurement.spectral_eval.SpectralEvaluationCache.init(allocator),
        };
    }

    fn deinit(self: *TransportBuffers, allocator: std.mem.Allocator) void {
        allocator.free(self.layer_inputs);
        allocator.free(self.pseudo_spherical_layers);
        allocator.free(self.source_interfaces);
        allocator.free(self.rtm_quadrature_levels);
        allocator.free(self.pseudo_spherical_samples);
        allocator.free(self.pseudo_spherical_level_starts);
        allocator.free(self.pseudo_spherical_level_altitudes);
        self.evaluation_cache.deinit();
        self.* = undefined;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const config = try parseArgs(allocator, args);
    defer allocator.free(config.trace_root);
    defer allocator.free(config.wavelengths_nm);

    var prepared_case = try vendor_support.prepareTraceCase(allocator);
    defer prepared_case.deinit(allocator);

    var files = try TraceFiles.init(allocator, config.trace_root);
    defer files.deinit();

    var line_list = try prepared_case.prepared.spectroscopy_lines.?.clone(allocator);
    defer line_list.deinit(allocator);
    try line_list.buildStrongLineMatchIndex(allocator);

    const providers = internal.plugin_internal.providers.exact();
    const trace_wavelengths = try resolveTraceWavelengths(
        allocator,
        &prepared_case.scene,
        &prepared_case.prepared,
        providers,
        config.wavelengths_nm,
    );
    defer allocator.free(trace_wavelengths);

    const comparison_states = try loadComparisonThermodynamicStates(allocator, config.trace_root);
    defer if (comparison_states.len != 0) allocator.free(comparison_states);

    try emitLineCatalog(
        &files.line_catalog,
        line_list,
        prepared_case.scene.spectral_grid.start_nm,
        prepared_case.scene.spectral_grid.end_nm,
    );
    if (comparison_states.len != 0) {
        try emitStrongStatesAtThermodynamicGrid(
            &files.strong_state,
            allocator,
            line_list,
            comparison_states,
        );
        try emitSpectroscopySummariesAtThermodynamicGrid(
            &files.spectroscopy_summary,
            allocator,
            line_list,
            comparison_states,
            trace_wavelengths,
        );
        try emitWeakLineContributorsAtThermodynamicGrid(
            &files.weak_line_contributors,
            allocator,
            line_list,
            comparison_states,
            trace_wavelengths,
        );
    } else {
        try emitStrongStates(
            &files.strong_state,
            prepared_case.prepared.spectroscopy_lines.?,
            prepared_case.prepared.sublayers.?,
            prepared_case.prepared.strong_line_states.?,
        );
        try emitSpectroscopySummaries(
            &files.spectroscopy_summary,
            line_list,
            prepared_case.prepared.sublayers.?,
            prepared_case.prepared.strong_line_states.?,
            trace_wavelengths,
        );
        try emitWeakLineContributors(
            &files.weak_line_contributors,
            allocator,
            line_list,
            prepared_case.prepared.sublayers.?,
            prepared_case.prepared.strong_line_states.?,
            trace_wavelengths,
        );
    }
    try emitSublayerOptics(
        &files.sublayer_optics,
        &prepared_case.prepared,
        trace_wavelengths,
    );
    try emitIntervalBounds(
        &files.interval_bounds,
        &prepared_case.prepared,
        trace_wavelengths,
    );

    var transport_buffers = try TransportBuffers.init(
        allocator,
        &prepared_case.scene,
        prepared_case.route,
        &prepared_case.prepared,
    );
    defer transport_buffers.deinit(allocator);

    try emitTransportTraces(
        allocator,
        &files,
        &prepared_case.scene,
        prepared_case.route,
        &prepared_case.prepared,
        providers,
        &transport_buffers,
        config.wavelengths_nm,
    );
}

fn resolveTraceWavelengths(
    allocator: std.mem.Allocator,
    scene: *const internal.Scene,
    prepared: *const OpticsPrepare.PreparedOpticalState,
    providers: Measurement.ProviderBindings,
    nominal_wavelengths_nm: []const f64,
) ![]TraceWavelength {
    const resolved = try allocator.alloc(TraceWavelength, nominal_wavelengths_nm.len);
    errdefer allocator.free(resolved);

    const radiance_calibration = providers.instrument.calibrationForScene(scene, .radiance);
    for (nominal_wavelengths_nm, resolved) |nominal_wavelength_nm, *trace_wavelength| {
        const evaluation_wavelength_nm = Calibration.shiftedWavelength(
            radiance_calibration,
            nominal_wavelength_nm,
        );
        var integration: InstrumentProviders.IntegrationKernel = undefined;
        try InstrumentIntegration.integrationForWavelengthChecked(
            scene,
            prepared,
            .radiance,
            nominal_wavelength_nm,
            &integration,
        );

        var sample_wavelength_nm = evaluation_wavelength_nm;
        if (integration.enabled and integration.sample_count != 0) {
            var best_delta = std.math.inf(f64);
            for (0..integration.sample_count) |sample_index| {
                const candidate = evaluation_wavelength_nm + integration.offsets_nm[sample_index];
                const delta = @abs(candidate - nominal_wavelength_nm);
                if (delta < best_delta) {
                    best_delta = delta;
                    sample_wavelength_nm = candidate;
                }
            }
        }

        trace_wavelength.* = .{
            .nominal_nm = nominal_wavelength_nm,
            .sample_nm = sample_wavelength_nm,
        };
    }

    return resolved;
}

fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !CliConfig {
    var trace_root: ?[]u8 = null;
    var wavelengths = std.ArrayList(f64).empty;
    defer wavelengths.deinit(allocator);

    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--trace-root")) {
            index += 1;
            if (index >= args.len) return error.MissingTraceRoot;
            trace_root = try allocator.dupe(u8, args[index]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--wavelengths")) {
            index += 1;
            if (index >= args.len) return error.MissingWavelengths;
            try parseWavelengthList(allocator, args[index], &wavelengths);
            continue;
        }
        return error.InvalidArguments;
    }

    if (trace_root == null) {
        trace_root = try allocator.dupe(u8, "out/analysis/o2a/function_diff/manual");
    }
    if (wavelengths.items.len == 0) {
        try wavelengths.appendSlice(allocator, &default_wavelengths_nm);
    }

    return .{
        .trace_root = trace_root.?,
        .wavelengths_nm = try wavelengths.toOwnedSlice(allocator),
    };
}

fn parseWavelengthList(
    allocator: std.mem.Allocator,
    value: []const u8,
    wavelengths: *std.ArrayList(f64),
) !void {
    var parts = std.mem.splitScalar(u8, value, ',');
    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t\r\n");
        if (trimmed.len == 0) continue;
        try wavelengths.append(allocator, try std.fmt.parseFloat(f64, trimmed));
    }
}

fn createCsvFile(
    allocator: std.mem.Allocator,
    root: []const u8,
    name: []const u8,
    header: []const u8,
) !std.fs.File {
    const path = try std.fs.path.join(allocator, &.{ root, name });
    defer allocator.free(path);
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    errdefer file.close();
    try file.writeAll(header);
    return file;
}

fn emitLineCatalog(
    file: *std.fs.File,
    line_list: ReferenceData.SpectroscopyLineList,
    support_start_nm: f64,
    support_end_nm: f64,
) !void {
    var rows = std.ArrayList(LineCatalogRow).empty;
    defer rows.deinit(std.heap.page_allocator);

    const vendor_partition = usesVendorStrongLinePartition(line_list);
    var retained_index: usize = 0;
    for (line_list.lines) |line| {
        if (vendor_partition and isVendorStrongCandidateFromSource(line)) continue;
        if (!lineWithinSupportWindow(line, line_list.runtime_controls.cutoff_cm1, support_start_nm, support_end_nm)) continue;
        retained_index += 1;
        try rows.append(std.heap.page_allocator, .{
            .source_row_index = retained_index,
            .gas_index = line.gas_index,
            .isotope_number = line.isotope_number,
            .center_wavelength_nm = line.center_wavelength_nm,
            .center_wavenumber_cm1 = wavelengthToWavenumberCm1(line.center_wavelength_nm),
            .line_strength_cm2_per_molecule = line.line_strength_cm2_per_molecule,
            .air_half_width_nm = line.air_half_width_nm,
            .temperature_exponent = line.temperature_exponent,
            .lower_state_energy_cm1 = line.lower_state_energy_cm1,
            .pressure_shift_nm = line.pressure_shift_nm,
            .line_mixing_coefficient = line.line_mixing_coefficient,
            .branch_ic1 = optionalU8ToF64(line.branch_ic1),
            .branch_ic2 = optionalU8ToF64(line.branch_ic2),
            .rotational_nf = optionalU8ToF64(line.rotational_nf),
        });
    }

    std.sort.block(LineCatalogRow, rows.items, {}, lessThanLineCatalogRow);
    var writer = file.deprecatedWriter();
    for (rows.items) |row| {
        try writer.print(
            "{},{},{},{},{},{},{},{},{},{},{},{},{},{}\n",
            .{
                row.source_row_index,
                row.gas_index,
                row.isotope_number,
                row.center_wavelength_nm,
                row.center_wavenumber_cm1,
                row.line_strength_cm2_per_molecule,
                row.air_half_width_nm,
                row.temperature_exponent,
                row.lower_state_energy_cm1,
                row.pressure_shift_nm,
                row.line_mixing_coefficient,
                row.branch_ic1,
                row.branch_ic2,
                row.rotational_nf,
            },
        );
    }
}

fn emitStrongStates(
    file: *std.fs.File,
    line_list: ReferenceData.SpectroscopyLineList,
    sublayers: []const OpticsPrepare.PreparedSublayer,
    states: []const ReferenceData.StrongLinePreparedState,
) !void {
    var rows = std.ArrayList(StrongStateRow).empty;
    defer rows.deinit(std.heap.page_allocator);

    const strong_lines = line_list.strong_lines orelse return;
    for (states, 0..) |state, state_index| {
        const sublayer = sublayers[state_index];
        for (strong_lines, 0..) |strong_line, strong_index| {
            try rows.append(std.heap.page_allocator, .{
                .pressure_hpa = sublayer.pressure_hpa,
                .temperature_k = sublayer.temperature_k,
                .strong_index = strong_index,
                .center_wavelength_nm = strong_line.center_wavelength_nm,
                .center_wavenumber_cm1 = strong_line.center_wavenumber_cm1,
                .sig_moy_cm1 = state.sig_moy_cm1,
                .population_t = state.population_t[strong_index],
                .dipole_t = state.dipole_t[strong_index],
                .mod_sig_cm1 = state.mod_sig_cm1[strong_index],
                .half_width_cm1_at_t = state.half_width_cm1_at_t[strong_index],
                .line_mixing_coefficient = state.line_mixing_coefficients[strong_index],
            });
        }
    }

    std.sort.block(StrongStateRow, rows.items, {}, lessThanStrongStateRow);
    var writer = file.deprecatedWriter();
    for (rows.items) |row| {
        try writer.print(
            "{},{},{},{},{},{},{},{},{},{},{}\n",
            .{
                row.pressure_hpa,
                row.temperature_k,
                row.strong_index,
                row.center_wavelength_nm,
                row.center_wavenumber_cm1,
                row.sig_moy_cm1,
                row.population_t,
                row.dipole_t,
                row.mod_sig_cm1,
                row.half_width_cm1_at_t,
                row.line_mixing_coefficient,
            },
        );
    }
}

fn emitSpectroscopySummaries(
    file: *std.fs.File,
    line_list: ReferenceData.SpectroscopyLineList,
    sublayers: []const OpticsPrepare.PreparedSublayer,
    states: []const ReferenceData.StrongLinePreparedState,
    trace_wavelengths: []const TraceWavelength,
) !void {
    var rows = std.ArrayList(SpectroscopySummaryRow).empty;
    defer rows.deinit(std.heap.page_allocator);

    for (states, 0..) |state, state_index| {
        const sublayer = sublayers[state_index];
        for (trace_wavelengths) |trace_wavelength| {
            const evaluation = line_list.evaluateAtPrepared(
                trace_wavelength.sample_nm,
                sublayer.temperature_k,
                sublayer.pressure_hpa,
                &state,
            );
            try rows.append(std.heap.page_allocator, .{
                .pressure_hpa = sublayer.pressure_hpa,
                .temperature_k = sublayer.temperature_k,
                .wavelength_nm = trace_wavelength.nominal_nm,
                .weak_sigma_cm2_per_molecule = evaluation.weak_line_sigma_cm2_per_molecule,
                .strong_sigma_cm2_per_molecule = evaluation.strong_line_sigma_cm2_per_molecule,
                .line_mixing_sigma_cm2_per_molecule = evaluation.line_mixing_sigma_cm2_per_molecule,
                .total_sigma_cm2_per_molecule = evaluation.total_sigma_cm2_per_molecule,
            });
        }
    }

    std.sort.block(SpectroscopySummaryRow, rows.items, {}, lessThanSpectroscopySummaryRow);
    var writer = file.deprecatedWriter();
    for (rows.items) |row| {
        try writer.print(
            "{},{},{},{},{},{},{}\n",
            .{
                row.pressure_hpa,
                row.temperature_k,
                row.wavelength_nm,
                row.weak_sigma_cm2_per_molecule,
                row.strong_sigma_cm2_per_molecule,
                row.line_mixing_sigma_cm2_per_molecule,
                row.total_sigma_cm2_per_molecule,
            },
        );
    }
}

fn emitStrongStatesAtThermodynamicGrid(
    file: *std.fs.File,
    allocator: std.mem.Allocator,
    line_list: ReferenceData.SpectroscopyLineList,
    thermodynamic_states: []const ThermodynamicState,
) !void {
    var rows = std.ArrayList(StrongStateRow).empty;
    defer rows.deinit(allocator);

    const strong_lines = line_list.strong_lines orelse return;
    for (thermodynamic_states) |thermodynamic_state| {
        var prepared_state = (try line_list.prepareStrongLineState(
            allocator,
            thermodynamic_state.temperature_k,
            thermodynamic_state.pressure_hpa,
        )) orelse continue;
        defer prepared_state.deinit(allocator);

        for (strong_lines, 0..) |strong_line, strong_index| {
            try rows.append(allocator, .{
                .pressure_hpa = thermodynamic_state.pressure_hpa,
                .temperature_k = thermodynamic_state.temperature_k,
                .strong_index = strong_index,
                .center_wavelength_nm = strong_line.center_wavelength_nm,
                .center_wavenumber_cm1 = strong_line.center_wavenumber_cm1,
                .sig_moy_cm1 = prepared_state.sig_moy_cm1,
                .population_t = prepared_state.population_t[strong_index],
                .dipole_t = prepared_state.dipole_t[strong_index],
                .mod_sig_cm1 = prepared_state.mod_sig_cm1[strong_index],
                .half_width_cm1_at_t = prepared_state.half_width_cm1_at_t[strong_index],
                .line_mixing_coefficient = prepared_state.line_mixing_coefficients[strong_index],
            });
        }
    }

    std.sort.block(StrongStateRow, rows.items, {}, lessThanStrongStateRow);
    var writer = file.deprecatedWriter();
    for (rows.items) |row| {
        try writer.print(
            "{},{},{},{},{},{},{},{},{},{},{}\n",
            .{
                row.pressure_hpa,
                row.temperature_k,
                row.strong_index,
                row.center_wavelength_nm,
                row.center_wavenumber_cm1,
                row.sig_moy_cm1,
                row.population_t,
                row.dipole_t,
                row.mod_sig_cm1,
                row.half_width_cm1_at_t,
                row.line_mixing_coefficient,
            },
        );
    }
}

fn emitSpectroscopySummariesAtThermodynamicGrid(
    file: *std.fs.File,
    allocator: std.mem.Allocator,
    line_list: ReferenceData.SpectroscopyLineList,
    thermodynamic_states: []const ThermodynamicState,
    trace_wavelengths: []const TraceWavelength,
) !void {
    var rows = std.ArrayList(SpectroscopySummaryRow).empty;
    defer rows.deinit(allocator);

    for (thermodynamic_states) |thermodynamic_state| {
        var prepared_state = (try line_list.prepareStrongLineState(
            allocator,
            thermodynamic_state.temperature_k,
            thermodynamic_state.pressure_hpa,
        )) orelse continue;
        defer prepared_state.deinit(allocator);

        for (trace_wavelengths) |trace_wavelength| {
            const evaluation = line_list.evaluateAtPrepared(
                trace_wavelength.sample_nm,
                thermodynamic_state.temperature_k,
                thermodynamic_state.pressure_hpa,
                &prepared_state,
            );
            try rows.append(allocator, .{
                .pressure_hpa = thermodynamic_state.pressure_hpa,
                .temperature_k = thermodynamic_state.temperature_k,
                .wavelength_nm = trace_wavelength.nominal_nm,
                .weak_sigma_cm2_per_molecule = evaluation.weak_line_sigma_cm2_per_molecule,
                .strong_sigma_cm2_per_molecule = evaluation.strong_line_sigma_cm2_per_molecule,
                .line_mixing_sigma_cm2_per_molecule = evaluation.line_mixing_sigma_cm2_per_molecule,
                .total_sigma_cm2_per_molecule = evaluation.total_sigma_cm2_per_molecule,
            });
        }
    }

    std.sort.block(SpectroscopySummaryRow, rows.items, {}, lessThanSpectroscopySummaryRow);
    var writer = file.deprecatedWriter();
    for (rows.items) |row| {
        try writer.print(
            "{},{},{},{},{},{},{}\n",
            .{
                row.pressure_hpa,
                row.temperature_k,
                row.wavelength_nm,
                row.weak_sigma_cm2_per_molecule,
                row.strong_sigma_cm2_per_molecule,
                row.line_mixing_sigma_cm2_per_molecule,
                row.total_sigma_cm2_per_molecule,
            },
        );
    }
}

fn emitWeakLineContributors(
    file: *std.fs.File,
    allocator: std.mem.Allocator,
    line_list: ReferenceData.SpectroscopyLineList,
    sublayers: []const OpticsPrepare.PreparedSublayer,
    states: []const ReferenceData.StrongLinePreparedState,
    trace_wavelengths: []const TraceWavelength,
) !void {
    var rows = std.ArrayList(WeakLineContributorRow).empty;
    defer rows.deinit(allocator);

    for (states, 0..) |state, state_index| {
        const sublayer = sublayers[state_index];
        for (trace_wavelengths) |trace_wavelength| {
            var trace = try line_list.traceAt(
                allocator,
                trace_wavelength.sample_nm,
                sublayer.temperature_k,
                sublayer.pressure_hpa,
                &state,
            );
            defer trace.deinit(allocator);
            try appendWeakContributorTraceRows(allocator, &rows, trace, trace_wavelength.nominal_nm);
        }
    }

    try writeWeakLineContributorRows(file, rows.items);
}

fn emitWeakLineContributorsAtThermodynamicGrid(
    file: *std.fs.File,
    allocator: std.mem.Allocator,
    line_list: ReferenceData.SpectroscopyLineList,
    thermodynamic_states: []const ThermodynamicState,
    trace_wavelengths: []const TraceWavelength,
) !void {
    var rows = std.ArrayList(WeakLineContributorRow).empty;
    defer rows.deinit(allocator);

    for (thermodynamic_states) |thermodynamic_state| {
        var prepared_state = (try line_list.prepareStrongLineState(
            allocator,
            thermodynamic_state.temperature_k,
            thermodynamic_state.pressure_hpa,
        )) orelse continue;
        defer prepared_state.deinit(allocator);

        for (trace_wavelengths) |trace_wavelength| {
            var trace = try line_list.traceAt(
                allocator,
                trace_wavelength.sample_nm,
                thermodynamic_state.temperature_k,
                thermodynamic_state.pressure_hpa,
                &prepared_state,
            );
            defer trace.deinit(allocator);
            try appendWeakContributorTraceRows(allocator, &rows, trace, trace_wavelength.nominal_nm);
        }
    }

    try writeWeakLineContributorRows(file, rows.items);
}

fn appendWeakContributorTraceRows(
    allocator: std.mem.Allocator,
    rows: *std.ArrayList(WeakLineContributorRow),
    trace: ReferenceData.SpectroscopyTrace,
    nominal_wavelength_nm: f64,
) !void {
    for (trace.rows) |row| {
        if (row.contribution_kind == .strong_sidecar) continue;
        try rows.append(allocator, .{
            .pressure_hpa = trace.pressure_hpa,
            .temperature_k = trace.temperature_k,
            .wavelength_nm = nominal_wavelength_nm,
            .sample_wavelength_nm = trace.wavelength_nm,
            .source_row_index = optionalUsizeToF64(row.global_line_index),
            .contribution_kind = @tagName(row.contribution_kind),
            .gas_index = row.gas_index,
            .isotope_number = row.isotope_number,
            .center_wavelength_nm = row.center_wavelength_nm,
            .center_wavenumber_cm1 = row.center_wavenumber_cm1,
            .shifted_center_wavenumber_cm1 = row.shifted_center_wavenumber_cm1,
            .line_strength_cm2_per_molecule = row.line_strength_cm2_per_molecule,
            .air_half_width_nm = row.air_half_width_nm,
            .temperature_exponent = row.temperature_exponent,
            .lower_state_energy_cm1 = row.lower_state_energy_cm1,
            .pressure_shift_nm = row.pressure_shift_nm,
            .line_mixing_coefficient = row.line_mixing_coefficient,
            .branch_ic1 = optionalU8ToF64(row.branch_ic1),
            .branch_ic2 = optionalU8ToF64(row.branch_ic2),
            .rotational_nf = optionalU8ToF64(row.rotational_nf),
            .matched_strong_index = optionalUsizeToF64(row.matched_strong_index),
            .weak_line_sigma_cm2_per_molecule = row.weak_line_sigma_cm2_per_molecule,
        });
    }
}

fn writeWeakLineContributorRows(
    file: *std.fs.File,
    rows: []WeakLineContributorRow,
) !void {
    std.sort.block(WeakLineContributorRow, rows, {}, lessThanWeakLineContributorRow);
    var writer = file.deprecatedWriter();
    for (rows) |row| {
        try writer.print(
            "{},{},{},{},{},{s},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{}\n",
            .{
                row.pressure_hpa,
                row.temperature_k,
                row.wavelength_nm,
                row.sample_wavelength_nm,
                row.source_row_index,
                row.contribution_kind,
                row.gas_index,
                row.isotope_number,
                row.center_wavelength_nm,
                row.center_wavenumber_cm1,
                row.shifted_center_wavenumber_cm1,
                row.line_strength_cm2_per_molecule,
                row.air_half_width_nm,
                row.temperature_exponent,
                row.lower_state_energy_cm1,
                row.pressure_shift_nm,
                row.line_mixing_coefficient,
                row.branch_ic1,
                row.branch_ic2,
                row.rotational_nf,
                row.matched_strong_index,
                row.weak_line_sigma_cm2_per_molecule,
            },
        );
    }
}

fn emitSublayerOptics(
    file: *std.fs.File,
    prepared: *const OpticsPrepare.PreparedOpticalState,
    trace_wavelengths: []const TraceWavelength,
) !void {
    const sublayers = prepared.sublayers orelse return;
    var rows = std.ArrayList(SublayerOpticsRow).empty;
    defer rows.deinit(std.heap.page_allocator);

    for (trace_wavelengths) |trace_wavelength| {
        const evaluation_wavelength_nm = trace_wavelength.sample_nm;
        for (sublayers, 0..) |sublayer, index| {
            var line_sigma: f64 = 0.0;
            var line_mixing_sigma: f64 = 0.0;
            if (prepared.spectroscopy_lines) |line_list| {
                _ = line_list;
                const evaluation = prepared.spectroscopyEvaluationAtAltitude(
                    evaluation_wavelength_nm,
                    sublayer.temperature_k,
                    sublayer.pressure_hpa,
                    sublayer.altitude_km,
                    if (prepared.strong_line_states) |states| &states[index] else null,
                );
                line_sigma = evaluation.line_sigma_cm2_per_molecule;
                line_mixing_sigma = evaluation.line_mixing_sigma_cm2_per_molecule;
            } else if (prepared.operational_o2_lut.enabled()) {
                line_sigma = prepared.operational_o2_lut.sigmaAt(
                    evaluation_wavelength_nm,
                    sublayer.temperature_k,
                    sublayer.pressure_hpa,
                );
            }

            const cia_sigma = if (prepared.operational_o2o2_lut.enabled())
                prepared.operational_o2o2_lut.sigmaAt(
                    evaluation_wavelength_nm,
                    sublayer.temperature_k,
                    sublayer.pressure_hpa,
                )
            else if (prepared.collision_induced_absorption) |cia_table|
                cia_table.sigmaAt(evaluation_wavelength_nm, sublayer.temperature_k)
            else
                0.0;

            const gas_scattering_optical_depth = ReferenceData.Rayleigh.crossSectionCm2(evaluation_wavelength_nm) *
                sublayer.number_density_cm3 *
                sublayer.path_length_cm;
            const aerosol_scattering_optical_depth = sublayer.aerosol_optical_depth * sublayer.aerosol_single_scatter_albedo;
            const cloud_scattering_optical_depth = sublayer.cloud_optical_depth * sublayer.cloud_single_scatter_albedo;
            const gas_absorption_optical_depth = (line_sigma + line_mixing_sigma) *
                sublayer.oxygen_number_density_cm3 *
                sublayer.path_length_cm;
            const cia_optical_depth = cia_sigma *
                sublayer.ciaPairDensityCm6() *
                sublayer.path_length_cm;
            const total_scattering_optical_depth =
                gas_scattering_optical_depth +
                aerosol_scattering_optical_depth +
                cloud_scattering_optical_depth;
            const total_optical_depth =
                gas_absorption_optical_depth +
                gas_scattering_optical_depth +
                cia_optical_depth +
                sublayer.aerosol_optical_depth +
                sublayer.cloud_optical_depth;

            try rows.append(std.heap.page_allocator, .{
                .wavelength_nm = trace_wavelength.nominal_nm,
                .global_sublayer_index = sublayer.global_sublayer_index,
                .interval_index_1based = sublayer.interval_index_1based,
                .altitude_km = sublayer.altitude_km,
                .support_weight_km = sublayer.path_length_cm / 1.0e5,
                .pressure_hpa = sublayer.pressure_hpa,
                .temperature_k = sublayer.temperature_k,
                .number_density_cm3 = sublayer.number_density_cm3,
                .oxygen_number_density_cm3 = sublayer.oxygen_number_density_cm3,
                .line_cross_section_cm2_per_molecule = line_sigma,
                .line_mixing_cross_section_cm2_per_molecule = line_mixing_sigma,
                .cia_sigma_cm5_per_molecule2 = cia_sigma,
                .gas_absorption_optical_depth = gas_absorption_optical_depth,
                .gas_scattering_optical_depth = gas_scattering_optical_depth,
                .cia_optical_depth = cia_optical_depth,
                .path_length_cm = sublayer.path_length_cm,
                .aerosol_optical_depth = sublayer.aerosol_optical_depth,
                .aerosol_scattering_optical_depth = aerosol_scattering_optical_depth,
                .cloud_optical_depth = sublayer.cloud_optical_depth,
                .cloud_scattering_optical_depth = cloud_scattering_optical_depth,
                .total_scattering_optical_depth = total_scattering_optical_depth,
                .total_optical_depth = total_optical_depth,
                .combined_phase_coef_0 = sublayer.combined_phase_coefficients[0],
                .combined_phase_coef_1 = sublayer.combined_phase_coefficients[1],
                .combined_phase_coef_2 = sublayer.combined_phase_coefficients[2],
                .combined_phase_coef_3 = sublayer.combined_phase_coefficients[3],
                .combined_phase_coef_10 = sublayer.combined_phase_coefficients[10],
                .combined_phase_coef_20 = sublayer.combined_phase_coefficients[20],
                .combined_phase_coef_39 = sublayer.combined_phase_coefficients[39],
            });
        }
    }

    std.sort.block(SublayerOpticsRow, rows.items, {}, lessThanSublayerOpticsRow);
    var writer = file.deprecatedWriter();
    for (rows.items) |row| {
        try writer.print(
            "{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{}\n",
            .{
                row.wavelength_nm,
                row.global_sublayer_index,
                row.interval_index_1based,
                row.altitude_km,
                row.support_weight_km,
                row.pressure_hpa,
                row.temperature_k,
                row.number_density_cm3,
                row.oxygen_number_density_cm3,
                row.line_cross_section_cm2_per_molecule,
                row.line_mixing_cross_section_cm2_per_molecule,
                row.cia_sigma_cm5_per_molecule2,
                row.gas_absorption_optical_depth,
                row.gas_scattering_optical_depth,
                row.cia_optical_depth,
                row.path_length_cm,
                row.aerosol_optical_depth,
                row.aerosol_scattering_optical_depth,
                row.cloud_optical_depth,
                row.cloud_scattering_optical_depth,
                row.total_scattering_optical_depth,
                row.total_optical_depth,
                row.combined_phase_coef_0,
                row.combined_phase_coef_1,
                row.combined_phase_coef_2,
                row.combined_phase_coef_3,
                row.combined_phase_coef_10,
                row.combined_phase_coef_20,
                row.combined_phase_coef_39,
            },
        );
    }
}

fn emitIntervalBounds(
    file: *std.fs.File,
    prepared: *const OpticsPrepare.PreparedOpticalState,
    trace_wavelengths: []const TraceWavelength,
) !void {
    if (prepared.layers.len == 0) return;

    var rows = std.ArrayList(IntervalBoundRow).empty;
    defer rows.deinit(std.heap.page_allocator);

    for (trace_wavelengths) |trace_wavelength| {
        const first_layer = prepared.layers[0];
        try rows.append(std.heap.page_allocator, .{
            .nominal_wavelength_nm = trace_wavelength.nominal_nm,
            .boundary_index_0based = 0,
            .interval_index_1based = 0,
            .pressure_hpa = first_layer.bottom_pressure_hpa,
            .altitude_km = first_layer.bottom_altitude_km,
        });

        var interval_start: usize = 0;
        var boundary_index: usize = 1;
        while (interval_start < prepared.layers.len) : (boundary_index += 1) {
            const interval_index_1based = prepared.layers[interval_start].interval_index_1based;
            var interval_stop = interval_start + 1;
            while (interval_stop < prepared.layers.len and
                prepared.layers[interval_stop].interval_index_1based == interval_index_1based)
            {
                interval_stop += 1;
            }

            const last_layer = prepared.layers[interval_stop - 1];
            try rows.append(std.heap.page_allocator, .{
                .nominal_wavelength_nm = trace_wavelength.nominal_nm,
                .boundary_index_0based = boundary_index,
                .interval_index_1based = interval_index_1based,
                .pressure_hpa = last_layer.top_pressure_hpa,
                .altitude_km = last_layer.top_altitude_km,
            });
            interval_start = interval_stop;
        }
    }

    std.sort.block(IntervalBoundRow, rows.items, {}, lessThanIntervalBoundRow);
    var writer = file.deprecatedWriter();
    for (rows.items) |row| {
        try writer.print(
            "{},{},{},{},{}\n",
            .{
                row.nominal_wavelength_nm,
                row.boundary_index_0based,
                row.interval_index_1based,
                row.pressure_hpa,
                row.altitude_km,
            },
        );
    }
}

fn emitTransportTraces(
    allocator: std.mem.Allocator,
    files: *TraceFiles,
    scene: *const internal.Scene,
    route: TransportCommon.Route,
    prepared: *const OpticsPrepare.PreparedOpticalState,
    providers: Measurement.ProviderBindings,
    buffers: *TransportBuffers,
    wavelengths_nm: []const f64,
) !void {
    var adaptive_rows = std.ArrayList(AdaptiveGridRow).empty;
    defer adaptive_rows.deinit(allocator);
    var kernel_rows = std.ArrayList(KernelSampleRow).empty;
    defer kernel_rows.deinit(allocator);
    var transport_rows = std.ArrayList(TransportSampleRow).empty;
    defer transport_rows.deinit(allocator);
    var summary_rows = std.ArrayList(TransportSummaryRow).empty;
    defer summary_rows.deinit(allocator);
    var fourier_rows = std.ArrayList(FourierTermRow).empty;
    defer fourier_rows.deinit(allocator);
    var transport_layer_rows = std.ArrayList(TransportLayerRow).empty;
    defer transport_layer_rows.deinit(allocator);
    var source_rows = std.ArrayList(SourceTermRow).empty;
    defer source_rows.deinit(allocator);
    var order_surface_rows = std.ArrayList(OrderSurfaceRow).empty;
    defer order_surface_rows.deinit(allocator);
    var source_angle_rows = std.ArrayList(SourceAngleComponentRow).empty;
    defer source_angle_rows.deinit(allocator);
    var attenuation_rows = std.ArrayList(AttenuationTermRow).empty;
    defer attenuation_rows.deinit(allocator);
    var pseudo_spherical_rows = std.ArrayList(PseudoSphericalSampleRow).empty;
    defer pseudo_spherical_rows.deinit(allocator);

    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const safe_span = if (span_nm <= 0.0) 1.0 else span_nm;
    const transport_layer_count = Measurement.workspace.resolvedTransportLayerCount(route, prepared);
    const radiance_calibration = providers.instrument.calibrationForScene(scene, .radiance);
    const irradiance_calibration = providers.instrument.calibrationForScene(scene, .irradiance);
    const irradiance_support = scene.observation_model.primaryOperationalBandSupport().operational_solar_spectrum;
    for (wavelengths_nm) |nominal_wavelength_nm| {
        if (try InstrumentProviders.traceAdaptiveIntegrationKernel(
            allocator,
            scene,
            prepared,
            .radiance,
            nominal_wavelength_nm,
        )) |adaptive_trace| {
            var owned_trace = adaptive_trace;
            defer owned_trace.deinit(allocator);
            for (owned_trace.intervals) |interval| {
                try adaptive_rows.append(allocator, .{
                    .nominal_wavelength_nm = nominal_wavelength_nm,
                    .interval_kind = @tagName(interval.kind),
                    .source_center_wavelength_nm = interval.source_center_wavelength_nm orelse std.math.nan(f64),
                    .interval_start_nm = interval.interval_start_nm,
                    .interval_end_nm = interval.interval_end_nm,
                    .division_count = interval.division_count,
                });
            }
        }

        const evaluation_wavelength_nm = Calibration.shiftedWavelength(
            radiance_calibration,
            nominal_wavelength_nm,
        );
        var radiance_integration: InstrumentProviders.IntegrationKernel = undefined;
        try InstrumentIntegration.integrationForWavelengthChecked(
            scene,
            prepared,
            .radiance,
            nominal_wavelength_nm,
            &radiance_integration,
        );
        if (!radiance_integration.enabled) {
            radiance_integration = .{
                .enabled = true,
                .sample_count = 1,
                .offsets_nm = [_]f64{0.0} ++ [_]f64{0.0} ** (InstrumentProviders.max_integration_sample_count - 1),
                .weights = [_]f64{1.0} ++ [_]f64{0.0} ** (InstrumentProviders.max_integration_sample_count - 1),
            };
        }
        const irradiance_evaluation_wavelength_nm = Calibration.shiftedWavelength(
            irradiance_calibration,
            nominal_wavelength_nm,
        );
        var irradiance_integration: InstrumentProviders.IntegrationKernel = undefined;
        try InstrumentIntegration.integrationForWavelengthChecked(
            scene,
            prepared,
            .irradiance,
            nominal_wavelength_nm,
            &irradiance_integration,
        );
        if (!irradiance_integration.enabled) {
            irradiance_integration = .{
                .enabled = true,
                .sample_count = 1,
                .offsets_nm = [_]f64{0.0} ++ [_]f64{0.0} ** (InstrumentProviders.max_integration_sample_count - 1),
                .weights = [_]f64{1.0} ++ [_]f64{0.0} ** (InstrumentProviders.max_integration_sample_count - 1),
            };
        }

        for (0..radiance_integration.sample_count) |sample_index| {
            const sample_wavelength_nm = evaluation_wavelength_nm + radiance_integration.offsets_nm[sample_index];
            const weight = radiance_integration.weights[sample_index];
            const sample = try Measurement.spectral_eval.cachedForwardAtWavelength(
                allocator,
                scene,
                route,
                prepared,
                sample_wavelength_nm,
                safe_span,
                providers,
                buffers.layer_inputs[0..transport_layer_count],
                buffers.pseudo_spherical_layers,
                buffers.source_interfaces[0 .. transport_layer_count + 1],
                buffers.rtm_quadrature_levels[0 .. transport_layer_count + 1],
                buffers.pseudo_spherical_samples,
                buffers.pseudo_spherical_level_starts[0 .. transport_layer_count + 1],
                buffers.pseudo_spherical_level_altitudes[0 .. transport_layer_count + 1],
                &buffers.evaluation_cache,
            );
            try emitLabosFourierRowsForSample(
                allocator,
                &fourier_rows,
                &transport_layer_rows,
                &source_rows,
                &order_surface_rows,
                &source_angle_rows,
                &attenuation_rows,
                &pseudo_spherical_rows,
                scene,
                route,
                prepared,
                sample_wavelength_nm,
                sample_index,
                weight,
                nominal_wavelength_nm,
                buffers,
                transport_layer_count,
            );
            const irradiance = if (irradiance_support.enabled())
                irradiance_support.interpolateIrradiance(sample_wavelength_nm)
            else
                0.0;
            try kernel_rows.append(allocator, .{
                .nominal_wavelength_nm = nominal_wavelength_nm,
                .sample_index = sample_index,
                .sample_wavelength_nm = sample_wavelength_nm,
                .weight = weight,
            });
            try transport_rows.append(allocator, .{
                .nominal_wavelength_nm = nominal_wavelength_nm,
                .sample_index = sample_index,
                .sample_wavelength_nm = sample_wavelength_nm,
                .radiance = sample.radiance,
                .irradiance = irradiance,
                .weight = weight,
            });
        }

        const integrated_radiance = try Measurement.spectral_eval.integrateForwardAtNominal(
            allocator,
            scene,
            route,
            prepared,
            evaluation_wavelength_nm,
            safe_span,
            providers,
            buffers.layer_inputs[0..transport_layer_count],
            buffers.pseudo_spherical_layers,
            buffers.source_interfaces[0 .. transport_layer_count + 1],
            buffers.rtm_quadrature_levels[0 .. transport_layer_count + 1],
            buffers.pseudo_spherical_samples,
            buffers.pseudo_spherical_level_starts[0 .. transport_layer_count + 1],
            buffers.pseudo_spherical_level_altitudes[0 .. transport_layer_count + 1],
            &buffers.evaluation_cache,
            &radiance_integration,
        );
        const integrated_irradiance = try Measurement.spectral_eval.integrateIrradianceAtNominal(
            scene,
            prepared,
            irradiance_evaluation_wavelength_nm,
            safe_span,
            &buffers.evaluation_cache,
            &irradiance_integration,
        );
        try summary_rows.append(allocator, .{
            .nominal_wavelength_nm = nominal_wavelength_nm,
            .final_radiance = integrated_radiance.radiance,
            .final_irradiance = integrated_irradiance,
            .final_reflectance = integrated_radiance.radiance /
                @max(integrated_irradiance, 1.0e-12),
        });
    }

    std.sort.block(AdaptiveGridRow, adaptive_rows.items, {}, lessThanAdaptiveGridRow);
    std.sort.block(KernelSampleRow, kernel_rows.items, {}, lessThanKernelSampleRow);
    std.sort.block(TransportSampleRow, transport_rows.items, {}, lessThanTransportSampleRow);
    std.sort.block(TransportSummaryRow, summary_rows.items, {}, lessThanTransportSummaryRow);
    std.sort.block(FourierTermRow, fourier_rows.items, {}, lessThanFourierTermRow);
    std.sort.block(TransportLayerRow, transport_layer_rows.items, {}, lessThanTransportLayerRow);
    std.sort.block(SourceTermRow, source_rows.items, {}, lessThanSourceTermRow);
    std.sort.block(OrderSurfaceRow, order_surface_rows.items, {}, lessThanOrderSurfaceRow);
    std.sort.block(SourceAngleComponentRow, source_angle_rows.items, {}, lessThanSourceAngleComponentRow);
    std.sort.block(AttenuationTermRow, attenuation_rows.items, {}, lessThanAttenuationTermRow);
    std.sort.block(PseudoSphericalSampleRow, pseudo_spherical_rows.items, {}, lessThanPseudoSphericalSampleRow);

    var adaptive_writer = files.adaptive_grid.deprecatedWriter();
    for (adaptive_rows.items) |row| {
        try adaptive_writer.print(
            "{},{s},{},{},{},{}\n",
            .{
                row.nominal_wavelength_nm,
                row.interval_kind,
                row.source_center_wavelength_nm,
                row.interval_start_nm,
                row.interval_end_nm,
                row.division_count,
            },
        );
    }

    var kernel_writer = files.kernel_samples.deprecatedWriter();
    for (kernel_rows.items) |row| {
        try kernel_writer.print(
            "{},{},{},{}\n",
            .{ row.nominal_wavelength_nm, row.sample_index, row.sample_wavelength_nm, row.weight },
        );
    }

    var transport_writer = files.transport_samples.deprecatedWriter();
    for (transport_rows.items) |row| {
        try transport_writer.print(
            "{},{},{},{},{},{}\n",
            .{
                row.nominal_wavelength_nm,
                row.sample_index,
                row.sample_wavelength_nm,
                row.radiance,
                row.irradiance,
                row.weight,
            },
        );
    }

    var summary_writer = files.transport_summary.deprecatedWriter();
    for (summary_rows.items) |row| {
        try summary_writer.print(
            "{},{},{},{}\n",
            .{
                row.nominal_wavelength_nm,
                row.final_radiance,
                row.final_irradiance,
                row.final_reflectance,
            },
        );
    }

    var fourier_writer = files.fourier_terms.deprecatedWriter();
    for (fourier_rows.items) |row| {
        try fourier_writer.print(
            "{},{},{},{},{},{},{},{},{},{},{},{}\n",
            .{
                row.nominal_wavelength_nm,
                row.sample_index,
                row.sample_wavelength_nm,
                row.kernel_weight,
                row.fourier_index,
                row.refl_fc,
                row.source_refl_fc,
                row.surface_refl_fc,
                row.surface_e_view,
                row.surface_u_view_solar,
                row.fourier_weight,
                row.weighted_refl,
            },
        );
    }

    var transport_layer_writer = files.transport_layers.deprecatedWriter();
    for (transport_layer_rows.items) |row| {
        try transport_layer_writer.print(
            "{},{},{},{},{},{},{},{},{},{},{},{},{},{},{}\n",
            .{
                row.nominal_wavelength_nm,
                row.sample_index,
                row.sample_wavelength_nm,
                row.kernel_weight,
                row.layer_index,
                row.optical_depth,
                row.scattering_optical_depth,
                row.single_scatter_albedo,
                row.phase_coef_0,
                row.phase_coef_1,
                row.phase_coef_2,
                row.phase_coef_3,
                row.phase_coef_10,
                row.phase_coef_20,
                row.phase_coef_39,
            },
        );
    }

    var source_writer = files.transport_source_terms.deprecatedWriter();
    for (source_rows.items) |row| {
        try source_writer.print(
            "{},{},{},{},{},{},{},{},{},{}\n",
            .{
                row.nominal_wavelength_nm,
                row.sample_index,
                row.sample_wavelength_nm,
                row.kernel_weight,
                row.fourier_index,
                row.level_index,
                row.rtm_weight,
                row.ksca,
                row.source_contribution,
                row.weighted_source_contribution,
            },
        );
    }

    var attenuation_writer = files.transport_attenuation_terms.deprecatedWriter();
    for (attenuation_rows.items) |row| {
        try attenuation_writer.print(
            "{},{},{},{},{s},{},{},{},{},{}\n",
            .{
                row.nominal_wavelength_nm,
                row.sample_index,
                row.sample_wavelength_nm,
                row.kernel_weight,
                row.direction_kind,
                row.direction_index,
                row.level_index,
                row.sumkext,
                row.attenuation_top_to_level,
                row.grid_valid,
            },
        );
    }

    var order_surface_writer = files.transport_order_surface.deprecatedWriter();
    for (order_surface_rows.items) |row| {
        try order_surface_writer.print(
            "{},{},{},{},{},{},{s},{},{},{},{},{}\n",
            .{
                row.nominal_wavelength_nm,
                row.sample_index,
                row.sample_wavelength_nm,
                row.kernel_weight,
                row.fourier_index,
                row.order_index,
                row.stop_reason,
                row.max_value,
                row.surface_u_order,
                row.surface_u_accumulated,
                row.surface_d_order,
                row.surface_e_view,
            },
        );
    }

    var source_angle_writer = files.transport_source_angle_components.deprecatedWriter();
    for (source_angle_rows.items) |row| {
        try source_angle_writer.print(
            "{},{},{},{},{},{},{s},{},{},{},{},{}\n",
            .{
                row.nominal_wavelength_nm,
                row.sample_index,
                row.sample_wavelength_nm,
                row.kernel_weight,
                row.fourier_index,
                row.level_index,
                row.component_kind,
                row.angle_index,
                row.phase_value,
                row.field_value,
                row.angle_contribution,
                row.weighted_angle_contribution,
            },
        );
    }

    var pseudo_spherical_writer = files.transport_pseudo_spherical_samples.deprecatedWriter();
    for (pseudo_spherical_rows.items) |row| {
        try pseudo_spherical_writer.print(
            "{},{},{},{},{},{},{},{},{},{}\n",
            .{
                row.nominal_wavelength_nm,
                row.sample_index,
                row.sample_wavelength_nm,
                row.kernel_weight,
                row.global_sample_index,
                row.altitude_km,
                row.support_weight_km,
                row.optical_depth,
                row.radius_weighted_optical_depth,
                row.grid_valid,
            },
        );
    }
}

fn emitLabosFourierRowsForSample(
    allocator: std.mem.Allocator,
    rows: *std.ArrayList(FourierTermRow),
    layer_rows: *std.ArrayList(TransportLayerRow),
    source_rows: *std.ArrayList(SourceTermRow),
    order_surface_rows: *std.ArrayList(OrderSurfaceRow),
    source_angle_rows: *std.ArrayList(SourceAngleComponentRow),
    attenuation_rows: *std.ArrayList(AttenuationTermRow),
    pseudo_spherical_rows: *std.ArrayList(PseudoSphericalSampleRow),
    scene: *const internal.Scene,
    route: TransportCommon.Route,
    prepared: *const OpticsPrepare.PreparedOpticalState,
    sample_wavelength_nm: f64,
    sample_index: usize,
    kernel_weight: f64,
    nominal_wavelength_nm: f64,
    buffers: *TransportBuffers,
    transport_layer_count: usize,
) !void {
    if (route.family != .labos) return;
    const input = try Measurement.forward_input.configuredForwardInput(
        scene,
        route,
        prepared,
        sample_wavelength_nm,
        buffers.layer_inputs[0..transport_layer_count],
        buffers.pseudo_spherical_layers,
        buffers.source_interfaces[0 .. transport_layer_count + 1],
        buffers.rtm_quadrature_levels[0 .. transport_layer_count + 1],
        buffers.pseudo_spherical_samples,
        buffers.pseudo_spherical_level_starts[0 .. transport_layer_count + 1],
        buffers.pseudo_spherical_level_altitudes[0 .. transport_layer_count + 1],
    );
    if (input.layers.len == 0 or route.rtm_controls.scattering == .none) return;

    for (input.layers, 0..) |layer, layer_index| {
        try layer_rows.append(allocator, .{
            .nominal_wavelength_nm = nominal_wavelength_nm,
            .sample_index = sample_index,
            .sample_wavelength_nm = sample_wavelength_nm,
            .kernel_weight = kernel_weight,
            .layer_index = layer_index,
            .optical_depth = layer.optical_depth,
            .scattering_optical_depth = layer.scattering_optical_depth,
            .single_scatter_albedo = layer.single_scatter_albedo,
            .phase_coef_0 = layer.phase_coefficients[0],
            .phase_coef_1 = layer.phase_coefficients[1],
            .phase_coef_2 = layer.phase_coefficients[2],
            .phase_coef_3 = layer.phase_coefficients[3],
            .phase_coef_10 = layer.phase_coefficients[10],
            .phase_coef_20 = layer.phase_coefficients[20],
            .phase_coef_39 = layer.phase_coefficients[39],
        });
    }

    const controls = route.rtm_controls;
    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const geo = Labos.Geometry.init(controls.nGauss(), mu0, muv);
    var atten = try Labos.fillAttenuationDynamicWithGrid(
        allocator,
        input.layers,
        input.pseudo_spherical_grid,
        &geo,
        controls.use_spherical_correction,
    );
    defer atten.deinit();
    try appendAttenuationRowsForSample(
        allocator,
        attenuation_rows,
        input,
        &geo,
        &atten,
        controls.use_spherical_correction,
        nominal_wavelength_nm,
        sample_index,
        sample_wavelength_nm,
        kernel_weight,
    );
    try appendPseudoSphericalRowsForSample(
        allocator,
        pseudo_spherical_rows,
        input,
        controls.use_spherical_correction,
        nominal_wavelength_nm,
        sample_index,
        sample_wavelength_nm,
        kernel_weight,
    );

    var rt = try allocator.alloc(Labos.LayerRT, input.layers.len + 1);
    defer allocator.free(rt);

    var orders_workspace = try Labos.OrdersWorkspace.init(allocator, input.layers.len + 1);
    defer orders_workspace.deinit();
    const use_integrated_source =
        controls.integrate_source_function and
        input.layers.len > 1 and
        (input.source_interfaces.len == input.layers.len + 1 or
            input.rtm_quadrature.isValidFor(input.layers.len));
    const layer_phase_kernels: ?[]Labos.PhaseKernel = if (use_integrated_source)
        try allocator.alloc(Labos.PhaseKernel, input.layers.len + 1)
    else
        null;
    defer if (layer_phase_kernels) |cache| allocator.free(cache);
    const layer_phase_kernel_valid: ?[]bool = if (use_integrated_source)
        try allocator.alloc(bool, input.layers.len + 1)
    else
        null;
    defer if (layer_phase_kernel_valid) |valid| allocator.free(valid);

    const fourier_max = Labos.resolvedFourierMax(input, controls);
    const phase_max = Labos.resolvedPhaseCoefficientMax(input);
    const num_orders_max: usize = @intCast(controls.resolvedNumOrdersMax(Labos.totalScatteringOpticalDepth(input.layers)));
    for (0..fourier_max + 1) |i_fourier| {
        const plm_basis = Labos.FourierPlmBasis.init(i_fourier, phase_max, &geo);
        Labos.calcRTlayersIntoWithBasis(
            rt,
            input.layers,
            i_fourier,
            &geo,
            controls,
            &plm_basis,
            layer_phase_kernels,
            layer_phase_kernel_valid,
        );
        rt[0] = Labos.fillSurface(i_fourier, input.surface_albedo, &geo);
        if (i_fourier == 0) {
            try appendOrderSurfaceRowsForFourier(
                allocator,
                order_surface_rows,
                0,
                input.layers.len,
                &geo,
                &atten,
                rt,
                controls,
                num_orders_max,
                nominal_wavelength_nm,
                sample_index,
                sample_wavelength_nm,
                kernel_weight,
            );
        }
        const orders_result = Labos.ordersScatInto(
            &orders_workspace,
            0,
            input.layers.len,
            &geo,
            &atten,
            rt,
            controls,
            num_orders_max,
        );
        if (use_integrated_source) {
            try appendSourceTermRowsForFourier(
                allocator,
                source_rows,
                source_angle_rows,
                input,
                orders_result.ud,
                i_fourier,
                &geo,
                &plm_basis,
                layer_phase_kernels,
                layer_phase_kernel_valid,
                nominal_wavelength_nm,
                sample_index,
                sample_wavelength_nm,
                kernel_weight,
            );
        }
        const refl_fc = if (use_integrated_source)
            Labos.calcIntegratedReflectanceWithBasis(
                input.layers,
                input.source_interfaces,
                input.rtm_quadrature,
                orders_result.ud,
                input.layers.len,
                i_fourier,
                &geo,
                &plm_basis,
                layer_phase_kernels,
                layer_phase_kernel_valid,
            )
        else
            Labos.calcReflectance(orders_result.ud, input.layers.len, &geo);
        const solar_col: usize = 1;
        const view_idx = geo.viewIdx();
        const surface_e_view = if (i_fourier == 0)
            orders_result.ud[0].E.get(view_idx)
        else
            0.0;
        const surface_u_view_solar = if (i_fourier == 0)
            orders_result.ud[0].U.col[solar_col].get(view_idx)
        else
            0.0;
        const surface_refl_fc = if (i_fourier == 0)
            surface_e_view * surface_u_view_solar
        else
            0.0;
        const fourier_weight = if (i_fourier == 0)
            1.0
        else
            2.0 * std.math.cos(@as(f64, @floatFromInt(i_fourier)) * input.relative_azimuth_rad);
        try rows.append(allocator, .{
            .nominal_wavelength_nm = nominal_wavelength_nm,
            .sample_index = sample_index,
            .sample_wavelength_nm = sample_wavelength_nm,
            .kernel_weight = kernel_weight,
            .fourier_index = i_fourier,
            .refl_fc = refl_fc,
            .source_refl_fc = refl_fc - surface_refl_fc,
            .surface_refl_fc = surface_refl_fc,
            .surface_e_view = surface_e_view,
            .surface_u_view_solar = surface_u_view_solar,
            .fourier_weight = fourier_weight,
            .weighted_refl = fourier_weight * refl_fc,
        });
    }
}

fn appendAttenuationRowsForSample(
    allocator: std.mem.Allocator,
    rows: *std.ArrayList(AttenuationTermRow),
    input: TransportCommon.ForwardInput,
    geo: *const Labos.Geometry,
    atten: *const Labos.DynamicAttenArray,
    use_spherical_correction: bool,
    nominal_wavelength_nm: f64,
    sample_index: usize,
    sample_wavelength_nm: f64,
    kernel_weight: f64,
) !void {
    const Direction = struct {
        label: []const u8,
        index: usize,
    };
    const directions = [_]Direction{
        .{ .label = "view", .index = geo.viewIdx() },
        .{ .label = "solar", .index = geo.n_gauss + 1 },
    };
    const top_level = input.layers.len;
    const grid_valid = use_spherical_correction and input.pseudo_spherical_grid.isValidFor(input.layers.len);

    for (directions) |direction| {
        for (0..top_level + 1) |level| {
            const attenuation_top_to_level = atten.get(direction.index, top_level, level);
            const sumkext = if (grid_valid)
                pseudoSphericalSumkextForLevel(input.pseudo_spherical_grid, geo, direction.index, level)
            else
                -@log(@max(attenuation_top_to_level, 1.0e-300));
            try rows.append(allocator, .{
                .nominal_wavelength_nm = nominal_wavelength_nm,
                .sample_index = sample_index,
                .sample_wavelength_nm = sample_wavelength_nm,
                .kernel_weight = kernel_weight,
                .direction_kind = direction.label,
                .direction_index = direction.index,
                .level_index = level,
                .sumkext = sumkext,
                .attenuation_top_to_level = attenuation_top_to_level,
                .grid_valid = if (grid_valid) 1 else 0,
            });
        }
    }
}

fn appendPseudoSphericalRowsForSample(
    allocator: std.mem.Allocator,
    rows: *std.ArrayList(PseudoSphericalSampleRow),
    input: TransportCommon.ForwardInput,
    use_spherical_correction: bool,
    nominal_wavelength_nm: f64,
    sample_index: usize,
    sample_wavelength_nm: f64,
    kernel_weight: f64,
) !void {
    const rearth_km = 6371.0;
    const grid_valid = use_spherical_correction and input.pseudo_spherical_grid.isValidFor(input.layers.len);
    for (input.pseudo_spherical_grid.samples, 0..) |sample, global_sample_index| {
        if (sample.optical_depth <= 0.0 and sample.thickness_km <= 0.0) continue;
        const radius_weighted_optical_depth = sample.optical_depth * (rearth_km + sample.altitude_km);
        try rows.append(allocator, .{
            .nominal_wavelength_nm = nominal_wavelength_nm,
            .sample_index = sample_index,
            .sample_wavelength_nm = sample_wavelength_nm,
            .kernel_weight = kernel_weight,
            .global_sample_index = global_sample_index,
            .altitude_km = sample.altitude_km,
            .support_weight_km = sample.thickness_km,
            .optical_depth = sample.optical_depth,
            .radius_weighted_optical_depth = radius_weighted_optical_depth,
            .grid_valid = if (grid_valid) 1 else 0,
        });
    }
}

fn pseudoSphericalSumkextForLevel(
    pseudo_spherical_grid: TransportCommon.PseudoSphericalGrid,
    geo: *const Labos.Geometry,
    direction_index: usize,
    level: usize,
) f64 {
    const rearth_km = 6371.0;
    const top_level = pseudo_spherical_grid.level_sample_starts.len - 1;
    if (level >= top_level) return 0.0;

    const u = std.math.clamp(geo.u[direction_index], -1.0, 1.0);
    const sin2theta = @max(1.0 - u * u, 0.0);
    const level_radius = rearth_km + pseudoSphericalLevelAltitude(pseudo_spherical_grid, level);
    const sqrx_sin2theta = sin2theta * level_radius * level_radius;
    var sumkext: f64 = 0.0;
    for (pseudo_spherical_grid.level_sample_starts[level]..pseudo_spherical_grid.samples.len) |sample_index| {
        const sample = pseudo_spherical_grid.samples[sample_index];
        if (sample.optical_depth <= 0.0) continue;
        const sample_radius = rearth_km + sample.altitude_km;
        const denominator = @sqrt(@abs(sample_radius * sample_radius - sqrx_sin2theta));
        sumkext += (sample.optical_depth * sample_radius) / @max(denominator, 1.0e-12);
    }
    return sumkext;
}

fn pseudoSphericalLevelAltitude(
    pseudo_spherical_grid: TransportCommon.PseudoSphericalGrid,
    level: usize,
) f64 {
    if (pseudo_spherical_grid.level_altitudes_km.len != 0) {
        return pseudo_spherical_grid.level_altitudes_km[level];
    }
    if (level == 0) {
        const first = pseudo_spherical_grid.samples[0];
        return @max(first.altitude_km - 0.5 * first.thickness_km, 0.0);
    }

    const start_index = pseudo_spherical_grid.level_sample_starts[level];
    if (start_index >= pseudo_spherical_grid.samples.len) {
        const last = pseudo_spherical_grid.samples[pseudo_spherical_grid.samples.len - 1];
        return @max(last.altitude_km + 0.5 * last.thickness_km, 0.0);
    }

    const sample = pseudo_spherical_grid.samples[start_index];
    return @max(sample.altitude_km - 0.5 * sample.thickness_km, 0.0);
}

fn appendOrderSurfaceRowsForFourier(
    allocator: std.mem.Allocator,
    rows: *std.ArrayList(OrderSurfaceRow),
    start_level: usize,
    end_level: usize,
    geo: *const Labos.Geometry,
    atten: *const Labos.DynamicAttenArray,
    rt: []const Labos.LayerRT,
    controls: TransportCommon.RtmControls,
    num_orders_max: usize,
    nominal_wavelength_nm: f64,
    sample_index: usize,
    sample_wavelength_nm: f64,
    kernel_weight: f64,
) !void {
    const nlevel = end_level + 1;
    var workspace = try Labos.OrdersWorkspace.init(allocator, nlevel);
    defer workspace.deinit();
    const ud = workspace.ud[0..nlevel];
    const ud_sum_local = workspace.ud_sum_local[0..nlevel];
    const ud_orde = workspace.ud_orde[0..nlevel];
    const ud_local = workspace.ud_local[0..nlevel];
    initializeTraceOrderBuffers(ud, ud_sum_local, ud_orde, ud_local, geo.nmutot);

    for (start_level..end_level + 1) |ilevel| {
        for (0..geo.nmutot) |imu| {
            const att = atten.get(imu, end_level, ilevel);
            ud_orde[ilevel].E.set(imu, att);
            ud[ilevel].E.set(imu, att);
        }
    }

    for (start_level..end_level) |ilevel| {
        for (0..2) |imu0| {
            const col_idx = geo.n_gauss + imu0;
            const att = atten.get(col_idx, end_level, ilevel + 1);
            for (0..geo.nmutot) |imu| {
                ud_local[ilevel].D.col[imu0].set(imu, rt[ilevel + 1].T.get(imu, col_idx) * att);
            }
        }
    }
    ud_local[end_level].D = Labos.Vec2.zero(geo.nmutot);

    for (start_level..end_level + 1) |ilevel| {
        for (0..2) |imu0| {
            const col_idx = geo.n_gauss + imu0;
            const att = atten.get(col_idx, end_level, ilevel);
            for (0..geo.nmutot) |imu| {
                ud_local[ilevel].U.col[imu0].set(imu, rt[ilevel].R.get(imu, col_idx) * att);
            }
        }
    }

    for (start_level..end_level + 1) |ilevel| {
        ud_sum_local[ilevel].U = ud_local[ilevel].U;
        ud_sum_local[ilevel].D = ud_local[ilevel].D;
    }

    transportTraceOrderToOtherLevels(start_level, end_level, geo.nmutot, atten, ud_local, ud_orde);
    for (start_level..end_level + 1) |ilevel| {
        ud[ilevel].U = ud_orde[ilevel].U;
        ud[ilevel].D = ud_orde[ilevel].D;
    }

    var max_value = orderMaxValue(ud_orde, end_level, geo);
    if (controls.scattering != .multiple or max_value < controls.threshold_conv_first) {
        try appendOrderSurfaceRow(
            allocator,
            rows,
            "first_converged",
            1,
            max_value,
            ud,
            ud_orde,
            geo,
            nominal_wavelength_nm,
            sample_index,
            sample_wavelength_nm,
            kernel_weight,
        );
        return;
    }
    try appendOrderSurfaceRow(allocator, rows, "accumulated", 1, max_value, ud, ud_orde, geo, nominal_wavelength_nm, sample_index, sample_wavelength_nm, kernel_weight);

    var num_orders: usize = 1;
    while (true) {
        num_orders += 1;

        for (start_level..end_level) |ilevel| {
            for (0..2) |imu0| {
                for (0..geo.nmutot) |imu| {
                    const rst_dot_u = Labos.dotGauss(&rt[ilevel + 1].R, imu, &ud_orde[ilevel].U.col[imu0], geo.n_gauss);
                    const t_dot_d = Labos.dotGauss(&rt[ilevel + 1].T, imu, &ud_orde[ilevel + 1].D.col[imu0], geo.n_gauss);
                    ud_local[ilevel].D.col[imu0].set(imu, rst_dot_u + t_dot_d);
                }
            }
        }
        ud_local[end_level].D = Labos.Vec2.zero(geo.nmutot);

        for (0..2) |imu0| {
            for (0..geo.nmutot) |imu| {
                const r_dot_d = Labos.dotGauss(&rt[start_level].R, imu, &ud_orde[start_level].D.col[imu0], geo.n_gauss);
                ud_local[start_level].U.col[imu0].set(imu, r_dot_d);
            }
        }

        for (start_level + 1..end_level + 1) |ilevel| {
            for (0..2) |imu0| {
                for (0..geo.nmutot) |imu| {
                    const r_dot_d = Labos.dotGauss(&rt[ilevel].R, imu, &ud_orde[ilevel].D.col[imu0], geo.n_gauss);
                    const tst_dot_u = Labos.dotGauss(&rt[ilevel].T, imu, &ud_orde[ilevel - 1].U.col[imu0], geo.n_gauss);
                    ud_local[ilevel].U.col[imu0].set(imu, r_dot_d + tst_dot_u);
                }
            }
        }

        transportTraceOrderToOtherLevels(start_level, end_level, geo.nmutot, atten, ud_local, ud_orde);
        max_value = orderMaxValue(ud_orde, end_level, geo);
        if (max_value < controls.threshold_conv_mult or num_orders >= num_orders_max) {
            try appendOrderSurfaceRow(
                allocator,
                rows,
                if (num_orders >= num_orders_max) "max_orders" else "multiple_converged",
                num_orders,
                max_value,
                ud,
                ud_orde,
                geo,
                nominal_wavelength_nm,
                sample_index,
                sample_wavelength_nm,
                kernel_weight,
            );
            break;
        }

        accumulateTraceOrderContribution(ud, ud_sum_local, ud_orde, ud_local, start_level, end_level, geo.nmutot);
        try appendOrderSurfaceRow(allocator, rows, "accumulated", num_orders, max_value, ud, ud_orde, geo, nominal_wavelength_nm, sample_index, sample_wavelength_nm, kernel_weight);
    }
}

fn initializeTraceOrderBuffers(
    ud: []Labos.UDField,
    ud_sum_local: []Labos.UDLocal,
    ud_orde: []Labos.UDField,
    ud_local: []Labos.UDLocal,
    nmutot: usize,
) void {
    for (ud, ud_sum_local, ud_orde, ud_local) |*field, *sum_local, *orde, *local| {
        field.* = .{ .E = Labos.Vec.zero(nmutot), .U = Labos.Vec2.zero(nmutot), .D = Labos.Vec2.zero(nmutot) };
        sum_local.* = .{ .U = Labos.Vec2.zero(nmutot), .D = Labos.Vec2.zero(nmutot) };
        orde.* = .{ .E = Labos.Vec.zero(nmutot), .U = Labos.Vec2.zero(nmutot), .D = Labos.Vec2.zero(nmutot) };
        local.* = .{ .U = Labos.Vec2.zero(nmutot), .D = Labos.Vec2.zero(nmutot) };
    }
}

fn transportTraceOrderToOtherLevels(
    start_level: usize,
    end_level: usize,
    nmutot: usize,
    atten: *const Labos.DynamicAttenArray,
    ud_local: []const Labos.UDLocal,
    ud_orde: []Labos.UDField,
) void {
    ud_orde[start_level].U = ud_local[start_level].U;
    for (start_level + 1..end_level + 1) |ilevel| {
        for (0..2) |imu0| {
            for (0..nmutot) |imu| {
                const local_val = ud_local[ilevel].U.col[imu0].get(imu);
                const prev_val = ud_orde[ilevel - 1].U.col[imu0].get(imu);
                ud_orde[ilevel].U.col[imu0].set(imu, local_val + atten.get(imu, ilevel - 1, ilevel) * prev_val);
            }
        }
    }

    ud_orde[end_level].D = Labos.Vec2.zero(nmutot);
    var ilevel = end_level;
    while (ilevel > start_level) {
        ilevel -= 1;
        for (0..2) |imu0| {
            for (0..nmutot) |imu| {
                const local_val = ud_local[ilevel].D.col[imu0].get(imu);
                const prev_val = ud_orde[ilevel + 1].D.col[imu0].get(imu);
                ud_orde[ilevel].D.col[imu0].set(imu, local_val + atten.get(imu, ilevel + 1, ilevel) * prev_val);
            }
        }
    }
}

fn accumulateTraceOrderContribution(
    ud: []Labos.UDField,
    ud_sum_local: []Labos.UDLocal,
    ud_orde: []const Labos.UDField,
    ud_local: []const Labos.UDLocal,
    start_level: usize,
    end_level: usize,
    nmutot: usize,
) void {
    for (start_level..end_level + 1) |ilevel| {
        for (0..2) |imu0| {
            for (0..nmutot) |imu| {
                ud[ilevel].U.col[imu0].set(imu, ud[ilevel].U.col[imu0].get(imu) + ud_orde[ilevel].U.col[imu0].get(imu));
                ud[ilevel].D.col[imu0].set(imu, ud[ilevel].D.col[imu0].get(imu) + ud_orde[ilevel].D.col[imu0].get(imu));
                ud_sum_local[ilevel].U.col[imu0].set(imu, ud_sum_local[ilevel].U.col[imu0].get(imu) + ud_local[ilevel].U.col[imu0].get(imu));
                ud_sum_local[ilevel].D.col[imu0].set(imu, ud_sum_local[ilevel].D.col[imu0].get(imu) + ud_local[ilevel].D.col[imu0].get(imu));
            }
        }
    }
}

fn orderMaxValue(ud_orde: []const Labos.UDField, end_level: usize, geo: *const Labos.Geometry) f64 {
    var max_value: f64 = 0.0;
    for (0..2) |imu0| {
        for (geo.n_gauss..geo.nmutot) |imu| {
            max_value = @max(max_value, @abs(ud_orde[end_level].U.col[imu0].get(imu)));
        }
    }
    return max_value;
}

fn appendOrderSurfaceRow(
    allocator: std.mem.Allocator,
    rows: *std.ArrayList(OrderSurfaceRow),
    stop_reason: []const u8,
    order_index: usize,
    max_value: f64,
    ud: []const Labos.UDField,
    ud_orde: []const Labos.UDField,
    geo: *const Labos.Geometry,
    nominal_wavelength_nm: f64,
    sample_index: usize,
    sample_wavelength_nm: f64,
    kernel_weight: f64,
) !void {
    const solar_col: usize = 1;
    const view_idx = geo.viewIdx();
    try rows.append(allocator, .{
        .nominal_wavelength_nm = nominal_wavelength_nm,
        .sample_index = sample_index,
        .sample_wavelength_nm = sample_wavelength_nm,
        .kernel_weight = kernel_weight,
        .fourier_index = 0,
        .order_index = order_index,
        .stop_reason = stop_reason,
        .max_value = max_value,
        .surface_u_order = ud_orde[0].U.col[solar_col].get(view_idx),
        .surface_u_accumulated = ud[0].U.col[solar_col].get(view_idx),
        .surface_d_order = ud_orde[0].D.col[solar_col].get(view_idx),
        .surface_e_view = ud[0].E.get(view_idx),
    });
}

fn appendSourceTermRowsForFourier(
    allocator: std.mem.Allocator,
    rows: *std.ArrayList(SourceTermRow),
    angle_rows: *std.ArrayList(SourceAngleComponentRow),
    input: TransportCommon.ForwardInput,
    ud: []const Labos.UDField,
    i_fourier: usize,
    geo: *const Labos.Geometry,
    plm_basis: *const Labos.FourierPlmBasis,
    layer_phase_kernel_cache: ?[]const Labos.PhaseKernel,
    layer_phase_kernel_valid: ?[]const bool,
    nominal_wavelength_nm: f64,
    sample_index: usize,
    sample_wavelength_nm: f64,
    kernel_weight: f64,
) !void {
    const solar_col: usize = 1;
    const view_idx = geo.viewIdx();
    const solar_idx = geo.n_gauss + 1;
    const view_mu = @max(geo.u[view_idx], 1.0e-12);
    const use_rtm_quadrature = input.rtm_quadrature.isValidFor(input.layers.len);

    for (0..input.layers.len + 1) |ilevel| {
        const source_interface = if (use_rtm_quadrature)
            TransportCommon.SourceInterfaceInput{}
        else
            sourceInterfaceAtLevel(input.layers, input.source_interfaces, ilevel);
        const source_rtm_weight = if (use_rtm_quadrature)
            input.rtm_quadrature.levels[ilevel].weight
        else if (source_interface.rtm_weight > 0.0 and source_interface.ksca_above > 0.0)
            source_interface.rtm_weight
        else
            source_interface.source_weight;
        const source_ksca = if (use_rtm_quadrature)
            input.rtm_quadrature.levels[ilevel].ksca
        else if (source_interface.rtm_weight > 0.0 and source_interface.ksca_above > 0.0)
            source_interface.ksca_above
        else
            1.0;
        if (source_rtm_weight <= 0.0 or source_ksca <= 0.0) continue;

        const phase_coefficients = if (use_rtm_quadrature)
            input.rtm_quadrature.levels[ilevel].phase_coefficients
        else
            source_interface.phase_coefficients_above;
        const source_max_phase_index = if (use_rtm_quadrature)
            adjacentLayerPhaseCoefficientIndex(input.layers, ilevel)
        else if (input.layers.len != 0)
            adjacentLayerPhaseCoefficientIndex(input.layers, ilevel)
        else
            maxInterfacePhaseCoefficientIndex(input.layers, input.source_interfaces, ilevel);
        if (i_fourier > source_max_phase_index) continue;

        const z = blk: {
            if (!use_rtm_quadrature) {
                if (reuseLayerKernelIndex(input.layers, source_interface, ilevel)) |above_index| {
                    if (layer_phase_kernel_cache) |cache| {
                        if (layer_phase_kernel_valid) |valid| {
                            const cache_index = above_index + 1;
                            if (cache_index < cache.len and cache_index < valid.len and valid[cache_index]) {
                                break :blk cache[cache_index];
                            }
                        }
                    }
                }
            }
            break :blk fillZplusZminFromBasisLimited(
                i_fourier,
                phase_coefficients,
                source_max_phase_index,
                geo,
                plm_basis,
            );
        };

        var pmin_ed: f64 = 0.0;
        for (0..geo.n_gauss) |imu| {
            const mu = @max(geo.u[imu], 1.0e-12);
            const pmin = 0.25 * z.Zmin.get(view_idx, imu) / (view_mu * mu);
            const field_value = ud[ilevel].D.col[solar_col].get(imu);
            const angle_contribution = pmin * field_value;
            pmin_ed += angle_contribution;
            if (i_fourier == 0) {
                try appendSourceAngleRow(
                    allocator,
                    angle_rows,
                    "pmin_diffuse",
                    imu,
                    pmin,
                    field_value,
                    angle_contribution,
                    ud[ilevel].E.get(view_idx),
                    source_ksca,
                    source_rtm_weight,
                    i_fourier,
                    ilevel,
                    nominal_wavelength_nm,
                    sample_index,
                    sample_wavelength_nm,
                    kernel_weight,
                );
            }
        }

        const solar_mu = @max(geo.u[solar_idx], 1.0e-12);
        const pmin_direct = 0.25 * z.Zmin.get(view_idx, solar_idx) / (view_mu * solar_mu);
        const direct_field_value = ud[ilevel].E.get(solar_idx);
        const direct_angle_contribution = pmin_direct * direct_field_value;
        pmin_ed += direct_angle_contribution;
        if (i_fourier == 0) {
            try appendSourceAngleRow(
                allocator,
                angle_rows,
                "pmin_direct",
                solar_idx,
                pmin_direct,
                direct_field_value,
                direct_angle_contribution,
                ud[ilevel].E.get(view_idx),
                source_ksca,
                source_rtm_weight,
                i_fourier,
                ilevel,
                nominal_wavelength_nm,
                sample_index,
                sample_wavelength_nm,
                kernel_weight,
            );
        }

        var pplusst_u: f64 = 0.0;
        for (0..geo.n_gauss) |imu| {
            const mu = @max(geo.u[imu], 1.0e-12);
            const pplusst = 0.25 * z.Zplus.get(view_idx, imu) / (view_mu * mu);
            const field_value = ud[ilevel].U.col[solar_col].get(imu);
            const angle_contribution = pplusst * field_value;
            pplusst_u += angle_contribution;
            if (i_fourier == 0) {
                try appendSourceAngleRow(
                    allocator,
                    angle_rows,
                    "pplusst_up",
                    imu,
                    pplusst,
                    field_value,
                    angle_contribution,
                    ud[ilevel].E.get(view_idx),
                    source_ksca,
                    source_rtm_weight,
                    i_fourier,
                    ilevel,
                    nominal_wavelength_nm,
                    sample_index,
                    sample_wavelength_nm,
                    kernel_weight,
                );
            }
        }

        const contribution = ud[ilevel].E.get(view_idx) *
            source_ksca *
            (pmin_ed + pplusst_u);
        try rows.append(allocator, .{
            .nominal_wavelength_nm = nominal_wavelength_nm,
            .sample_index = sample_index,
            .sample_wavelength_nm = sample_wavelength_nm,
            .kernel_weight = kernel_weight,
            .fourier_index = i_fourier,
            .level_index = ilevel,
            .rtm_weight = source_rtm_weight,
            .ksca = source_ksca,
            .source_contribution = contribution,
            .weighted_source_contribution = source_rtm_weight * contribution,
        });
    }
}

fn appendSourceAngleRow(
    allocator: std.mem.Allocator,
    rows: *std.ArrayList(SourceAngleComponentRow),
    component_kind: []const u8,
    angle_index: usize,
    phase_value: f64,
    field_value: f64,
    angle_contribution: f64,
    e_view: f64,
    ksca: f64,
    rtm_weight: f64,
    fourier_index: usize,
    level_index: usize,
    nominal_wavelength_nm: f64,
    sample_index: usize,
    sample_wavelength_nm: f64,
    kernel_weight: f64,
) !void {
    const source_contribution = e_view * ksca * angle_contribution;
    try rows.append(allocator, .{
        .nominal_wavelength_nm = nominal_wavelength_nm,
        .sample_index = sample_index,
        .sample_wavelength_nm = sample_wavelength_nm,
        .kernel_weight = kernel_weight,
        .fourier_index = fourier_index,
        .level_index = level_index,
        .component_kind = component_kind,
        .angle_index = angle_index,
        .phase_value = phase_value,
        .field_value = field_value,
        .angle_contribution = angle_contribution,
        .weighted_angle_contribution = rtm_weight * source_contribution,
    });
}

fn sourceInterfaceAtLevel(
    layers: []const TransportCommon.LayerInput,
    source_interfaces: []const TransportCommon.SourceInterfaceInput,
    ilevel: usize,
) TransportCommon.SourceInterfaceInput {
    if (source_interfaces.len == layers.len + 1 and ilevel < source_interfaces.len) {
        return source_interfaces[ilevel];
    }
    return TransportCommon.sourceInterfaceFromLayers(layers, ilevel);
}

fn maxPhaseCoefficientIndex(phase_coefficients: [TransportCommon.phase_coefficient_count]f64) usize {
    var max_index: usize = 0;
    for (1..TransportCommon.phase_coefficient_count) |idx| {
        if (@abs(phase_coefficients[idx]) > 1.0e-12) {
            max_index = idx;
        }
    }
    return max_index;
}

fn maxInterfacePhaseCoefficientIndex(
    layers: []const TransportCommon.LayerInput,
    source_interfaces: []const TransportCommon.SourceInterfaceInput,
    ilevel: usize,
) usize {
    const source_interface = sourceInterfaceAtLevel(layers, source_interfaces, ilevel);
    const above_max = maxPhaseCoefficientIndex(source_interface.phase_coefficients_above);
    const below_max = maxPhaseCoefficientIndex(source_interface.phase_coefficients_below);
    if (layers.len == 0 or ilevel == 0 or ilevel > layers.len - 1) return @max(above_max, below_max);
    return @max(above_max, below_max);
}

fn adjacentLayerPhaseCoefficientIndex(
    layers: []const TransportCommon.LayerInput,
    ilevel: usize,
) usize {
    if (layers.len == 0) return 0;
    if (ilevel == 0) return maxPhaseCoefficientIndex(layers[0].phase_coefficients);
    if (ilevel >= layers.len) return maxPhaseCoefficientIndex(layers[layers.len - 1].phase_coefficients);
    return @max(
        maxPhaseCoefficientIndex(layers[ilevel - 1].phase_coefficients),
        maxPhaseCoefficientIndex(layers[ilevel].phase_coefficients),
    );
}

fn reuseLayerKernelIndex(
    layers: []const TransportCommon.LayerInput,
    source_interface: TransportCommon.SourceInterfaceInput,
    ilevel: usize,
) ?usize {
    if (layers.len == 0) return null;
    const above_index = @min(ilevel, layers.len - 1);
    if (!std.mem.eql(
        f64,
        source_interface.phase_coefficients_above[0..],
        layers[above_index].phase_coefficients[0..],
    )) {
        return null;
    }
    return above_index;
}

fn fillZplusZminFromBasisLimited(
    i_fourier: usize,
    phase_coefficients: [TransportCommon.phase_coefficient_count]f64,
    max_phase_index: usize,
    geo: *const Labos.Geometry,
    plm_basis: *const Labos.FourierPlmBasis,
) Labos.PhaseKernel {
    const n = geo.nmutot;
    var zplus = Labos.Mat.zero(n);
    var zmin = Labos.Mat.zero(n);
    const bounded_max_phase_index = @min(max_phase_index, maxPhaseCoefficientIndex(phase_coefficients));
    if (i_fourier > bounded_max_phase_index) return .{ .Zplus = zplus, .Zmin = zmin };

    for (i_fourier..bounded_max_phase_index + 1) |l| {
        const alpha1 = phase_coefficients[l];
        for (0..n) |j| {
            const pj = plm_basis.plus[l][j];
            for (0..n) |i| {
                zplus.addTo(i, j, alpha1 * plm_basis.plus[l][i] * pj);
                zmin.addTo(i, j, alpha1 * plm_basis.minus[l][i] * pj);
            }
        }
    }
    return .{ .Zplus = zplus, .Zmin = zmin };
}

fn usesVendorStrongLinePartition(line_list: ReferenceData.SpectroscopyLineList) bool {
    if (!line_list.hasStrongLineSidecars()) return false;
    if (line_list.runtime_controls.gas_index) |gas_index| {
        if (gas_index != 7) return false;
    }
    if (line_list.runtime_controls.active_isotopes.len == 0) return true;
    for (line_list.runtime_controls.active_isotopes) |isotope| {
        if (isotope == 1) return true;
    }
    return false;
}

fn isVendorStrongCandidate(line: ReferenceData.SpectroscopyLine) bool {
    return line.gas_index == 7 and
        line.isotope_number == 1 and
        line.branch_ic1 != null and
        line.branch_ic1.? == 5 and
        line.branch_ic2 != null and
        line.branch_ic2.? == 1 and
        line.rotational_nf != null and
        line.rotational_nf.? <= 35;
}

fn isVendorStrongCandidateFromSource(line: ReferenceData.SpectroscopyLine) bool {
    return line.vendor_filter_metadata_from_source and isVendorStrongCandidate(line);
}

fn wavelengthToWavenumberCm1(wavelength_nm: f64) f64 {
    return 1.0e7 / @max(wavelength_nm, 1.0e-12);
}

fn lineWithinSupportWindow(
    line: ReferenceData.SpectroscopyLine,
    cutoff_cm1: ?f64,
    support_start_nm: f64,
    support_end_nm: f64,
) bool {
    const line_wavenumber_cm1 = wavelengthToWavenumberCm1(line.center_wavelength_nm);
    const window_start_cm1 = wavelengthToWavenumberCm1(support_end_nm);
    const window_end_cm1 = wavelengthToWavenumberCm1(support_start_nm);
    const cutoff = cutoff_cm1 orelse 0.0;
    return line_wavenumber_cm1 >= window_start_cm1 - cutoff and
        line_wavenumber_cm1 <= window_end_cm1 + cutoff;
}

fn optionalU8ToF64(value: ?u8) f64 {
    return if (value) |unwrapped|
        @floatFromInt(unwrapped)
    else
        std.math.nan(f64);
}

fn optionalUsizeToF64(value: ?usize) f64 {
    return if (value) |unwrapped|
        @floatFromInt(unwrapped + 1)
    else
        std.math.nan(f64);
}

fn lessThanLineCatalogRow(_: void, lhs: LineCatalogRow, rhs: LineCatalogRow) bool {
    if (lhs.center_wavelength_nm != rhs.center_wavelength_nm) return lhs.center_wavelength_nm < rhs.center_wavelength_nm;
    if (lhs.isotope_number != rhs.isotope_number) return lhs.isotope_number < rhs.isotope_number;
    if (sortNanLast(lhs.branch_ic1, rhs.branch_ic1)) |result| return result;
    if (sortNanLast(lhs.branch_ic2, rhs.branch_ic2)) |result| return result;
    if (sortNanLast(lhs.rotational_nf, rhs.rotational_nf)) |result| return result;
    return lhs.source_row_index < rhs.source_row_index;
}

fn lessThanStrongStateRow(_: void, lhs: StrongStateRow, rhs: StrongStateRow) bool {
    if (lhs.pressure_hpa != rhs.pressure_hpa) return lhs.pressure_hpa < rhs.pressure_hpa;
    if (lhs.temperature_k != rhs.temperature_k) return lhs.temperature_k < rhs.temperature_k;
    return lhs.strong_index < rhs.strong_index;
}

fn lessThanSpectroscopySummaryRow(_: void, lhs: SpectroscopySummaryRow, rhs: SpectroscopySummaryRow) bool {
    if (lhs.pressure_hpa != rhs.pressure_hpa) return lhs.pressure_hpa < rhs.pressure_hpa;
    if (lhs.temperature_k != rhs.temperature_k) return lhs.temperature_k < rhs.temperature_k;
    return lhs.wavelength_nm < rhs.wavelength_nm;
}

fn lessThanSublayerOpticsRow(_: void, lhs: SublayerOpticsRow, rhs: SublayerOpticsRow) bool {
    if (lhs.wavelength_nm != rhs.wavelength_nm) return lhs.wavelength_nm < rhs.wavelength_nm;
    if (lhs.global_sublayer_index != rhs.global_sublayer_index) return lhs.global_sublayer_index < rhs.global_sublayer_index;
    return lhs.interval_index_1based < rhs.interval_index_1based;
}

fn lessThanIntervalBoundRow(_: void, lhs: IntervalBoundRow, rhs: IntervalBoundRow) bool {
    if (lhs.nominal_wavelength_nm != rhs.nominal_wavelength_nm) return lhs.nominal_wavelength_nm < rhs.nominal_wavelength_nm;
    return lhs.boundary_index_0based < rhs.boundary_index_0based;
}

fn lessThanWeakLineContributorRow(_: void, lhs: WeakLineContributorRow, rhs: WeakLineContributorRow) bool {
    if (lhs.wavelength_nm != rhs.wavelength_nm) return lhs.wavelength_nm < rhs.wavelength_nm;
    if (lhs.pressure_hpa != rhs.pressure_hpa) return lhs.pressure_hpa < rhs.pressure_hpa;
    if (lhs.temperature_k != rhs.temperature_k) return lhs.temperature_k < rhs.temperature_k;
    if (lhs.center_wavenumber_cm1 != rhs.center_wavenumber_cm1) return lhs.center_wavenumber_cm1 < rhs.center_wavenumber_cm1;
    if (lhs.line_strength_cm2_per_molecule != rhs.line_strength_cm2_per_molecule) return lhs.line_strength_cm2_per_molecule < rhs.line_strength_cm2_per_molecule;
    return lhs.source_row_index < rhs.source_row_index;
}

fn lessThanAdaptiveGridRow(_: void, lhs: AdaptiveGridRow, rhs: AdaptiveGridRow) bool {
    if (lhs.nominal_wavelength_nm != rhs.nominal_wavelength_nm) return lhs.nominal_wavelength_nm < rhs.nominal_wavelength_nm;
    if (lhs.interval_start_nm != rhs.interval_start_nm) return lhs.interval_start_nm < rhs.interval_start_nm;
    return lhs.interval_end_nm < rhs.interval_end_nm;
}

fn lessThanKernelSampleRow(_: void, lhs: KernelSampleRow, rhs: KernelSampleRow) bool {
    if (lhs.nominal_wavelength_nm != rhs.nominal_wavelength_nm) return lhs.nominal_wavelength_nm < rhs.nominal_wavelength_nm;
    return lhs.sample_index < rhs.sample_index;
}

fn lessThanTransportSampleRow(_: void, lhs: TransportSampleRow, rhs: TransportSampleRow) bool {
    if (lhs.nominal_wavelength_nm != rhs.nominal_wavelength_nm) return lhs.nominal_wavelength_nm < rhs.nominal_wavelength_nm;
    return lhs.sample_index < rhs.sample_index;
}

fn lessThanTransportSummaryRow(_: void, lhs: TransportSummaryRow, rhs: TransportSummaryRow) bool {
    return lhs.nominal_wavelength_nm < rhs.nominal_wavelength_nm;
}

fn lessThanFourierTermRow(_: void, lhs: FourierTermRow, rhs: FourierTermRow) bool {
    if (lhs.nominal_wavelength_nm != rhs.nominal_wavelength_nm) return lhs.nominal_wavelength_nm < rhs.nominal_wavelength_nm;
    if (lhs.sample_index != rhs.sample_index) return lhs.sample_index < rhs.sample_index;
    return lhs.fourier_index < rhs.fourier_index;
}

fn lessThanTransportLayerRow(_: void, lhs: TransportLayerRow, rhs: TransportLayerRow) bool {
    if (lhs.nominal_wavelength_nm != rhs.nominal_wavelength_nm) return lhs.nominal_wavelength_nm < rhs.nominal_wavelength_nm;
    if (lhs.sample_index != rhs.sample_index) return lhs.sample_index < rhs.sample_index;
    return lhs.layer_index < rhs.layer_index;
}

fn lessThanSourceTermRow(_: void, lhs: SourceTermRow, rhs: SourceTermRow) bool {
    if (lhs.nominal_wavelength_nm != rhs.nominal_wavelength_nm) return lhs.nominal_wavelength_nm < rhs.nominal_wavelength_nm;
    if (lhs.sample_index != rhs.sample_index) return lhs.sample_index < rhs.sample_index;
    if (lhs.fourier_index != rhs.fourier_index) return lhs.fourier_index < rhs.fourier_index;
    return lhs.level_index < rhs.level_index;
}

fn lessThanOrderSurfaceRow(_: void, lhs: OrderSurfaceRow, rhs: OrderSurfaceRow) bool {
    if (lhs.nominal_wavelength_nm != rhs.nominal_wavelength_nm) return lhs.nominal_wavelength_nm < rhs.nominal_wavelength_nm;
    if (lhs.sample_index != rhs.sample_index) return lhs.sample_index < rhs.sample_index;
    if (lhs.fourier_index != rhs.fourier_index) return lhs.fourier_index < rhs.fourier_index;
    return lhs.order_index < rhs.order_index;
}

fn lessThanSourceAngleComponentRow(_: void, lhs: SourceAngleComponentRow, rhs: SourceAngleComponentRow) bool {
    if (lhs.nominal_wavelength_nm != rhs.nominal_wavelength_nm) return lhs.nominal_wavelength_nm < rhs.nominal_wavelength_nm;
    if (lhs.sample_index != rhs.sample_index) return lhs.sample_index < rhs.sample_index;
    if (lhs.fourier_index != rhs.fourier_index) return lhs.fourier_index < rhs.fourier_index;
    if (lhs.level_index != rhs.level_index) return lhs.level_index < rhs.level_index;
    const component_order = std.mem.order(u8, lhs.component_kind, rhs.component_kind);
    if (component_order != .eq) return component_order == .lt;
    return lhs.angle_index < rhs.angle_index;
}

fn lessThanAttenuationTermRow(_: void, lhs: AttenuationTermRow, rhs: AttenuationTermRow) bool {
    if (lhs.nominal_wavelength_nm != rhs.nominal_wavelength_nm) return lhs.nominal_wavelength_nm < rhs.nominal_wavelength_nm;
    if (lhs.sample_index != rhs.sample_index) return lhs.sample_index < rhs.sample_index;
    const direction_order = std.mem.order(u8, lhs.direction_kind, rhs.direction_kind);
    if (direction_order != .eq) return direction_order == .lt;
    return lhs.level_index < rhs.level_index;
}

fn lessThanPseudoSphericalSampleRow(_: void, lhs: PseudoSphericalSampleRow, rhs: PseudoSphericalSampleRow) bool {
    if (lhs.nominal_wavelength_nm != rhs.nominal_wavelength_nm) return lhs.nominal_wavelength_nm < rhs.nominal_wavelength_nm;
    if (lhs.sample_index != rhs.sample_index) return lhs.sample_index < rhs.sample_index;
    return lhs.global_sample_index < rhs.global_sample_index;
}

fn sortNanLast(lhs: f64, rhs: f64) ?bool {
    const lhs_nan = std.math.isNan(lhs);
    const rhs_nan = std.math.isNan(rhs);
    if (lhs_nan and rhs_nan) return null;
    if (lhs_nan != rhs_nan) return !lhs_nan;
    if (lhs != rhs) return lhs < rhs;
    return null;
}

fn loadComparisonThermodynamicStates(
    allocator: std.mem.Allocator,
    trace_root: []const u8,
) ![]ThermodynamicState {
    const path = try std.fs.path.join(
        allocator,
        &.{ trace_root, "vendor", "spectroscopy_summary.csv" },
    );
    defer allocator.free(path);

    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(contents);

    var states = std.ArrayList(ThermodynamicState).empty;
    defer states.deinit(allocator);

    var lines = std.mem.splitScalar(u8, contents, '\n');
    _ = lines.next();
    var previous_state: ?ThermodynamicState = null;
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        const state = try parseThermodynamicStateFromSpectroscopySummaryLine(trimmed);
        if (previous_state) |previous| {
            if (sameThermodynamicState(previous, state)) continue;
        }
        try states.append(allocator, state);
        previous_state = state;
    }

    return states.toOwnedSlice(allocator);
}

fn parseThermodynamicStateFromSpectroscopySummaryLine(line: []const u8) !ThermodynamicState {
    var columns = std.mem.splitScalar(u8, line, ',');
    const pressure_text = columns.next() orelse return error.InvalidFortranSpectroscopySummary;
    const temperature_text = columns.next() orelse return error.InvalidFortranSpectroscopySummary;
    return .{
        .pressure_hpa = try std.fmt.parseFloat(f64, std.mem.trim(u8, pressure_text, " \t\r")),
        .temperature_k = try std.fmt.parseFloat(f64, std.mem.trim(u8, temperature_text, " \t\r")),
    };
}

fn sameThermodynamicState(lhs: ThermodynamicState, rhs: ThermodynamicState) bool {
    return @abs(lhs.pressure_hpa - rhs.pressure_hpa) <= 1.0e-12 and
        @abs(lhs.temperature_k - rhs.temperature_k) <= 1.0e-12;
}
