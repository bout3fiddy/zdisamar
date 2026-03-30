const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");
const vendor_support = @import("vendor_o2a_trace_support");

const Measurement = internal.kernels.transport.measurement;
const TransportCommon = internal.kernels.transport.common;
const Calibration = internal.kernels.spectra.calibration;
const ReferenceData = internal.reference_data;
const InstrumentProviders = internal.plugin_internal.providers.Instrument;
const OpticsPrepare = internal.kernels.optics.preparation;

const default_wavelengths_nm = [_]f64{ 762.29, 765.0, 755.0 };

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

const CliConfig = struct {
    trace_root: []const u8,
    wavelengths_nm: []f64,
};

const TraceFiles = struct {
    line_catalog: std.fs.File,
    strong_state: std.fs.File,
    spectroscopy_summary: std.fs.File,
    adaptive_grid: std.fs.File,
    kernel_samples: std.fs.File,
    transport_samples: std.fs.File,
    transport_summary: std.fs.File,

    fn init(allocator: std.mem.Allocator, trace_root: []const u8) !TraceFiles {
        const zig_root = try std.fs.path.join(allocator, &.{ trace_root, "zig" });
        defer allocator.free(zig_root);
        try std.fs.cwd().makePath(zig_root);

        return .{
            .line_catalog = try createCsvFile(allocator, zig_root, "line_catalog.csv", "source_row_index,gas_index,isotope_number,center_wavelength_nm,center_wavenumber_cm1,line_strength_cm2_per_molecule,air_half_width_nm,temperature_exponent,lower_state_energy_cm1,pressure_shift_nm,line_mixing_coefficient,branch_ic1,branch_ic2,rotational_nf\n"),
            .strong_state = try createCsvFile(allocator, zig_root, "strong_state.csv", "pressure_hpa,temperature_k,strong_index,center_wavelength_nm,center_wavenumber_cm1,sig_moy_cm1,population_t,dipole_t,mod_sig_cm1,half_width_cm1_at_t,line_mixing_coefficient\n"),
            .spectroscopy_summary = try createCsvFile(allocator, zig_root, "spectroscopy_summary.csv", "pressure_hpa,temperature_k,wavelength_nm,weak_sigma_cm2_per_molecule,strong_sigma_cm2_per_molecule,line_mixing_sigma_cm2_per_molecule,total_sigma_cm2_per_molecule\n"),
            .adaptive_grid = try createCsvFile(allocator, zig_root, "adaptive_grid.csv", "nominal_wavelength_nm,interval_kind,source_center_wavelength_nm,interval_start_nm,interval_end_nm,division_count\n"),
            .kernel_samples = try createCsvFile(allocator, zig_root, "kernel_samples.csv", "nominal_wavelength_nm,sample_index,sample_wavelength_nm,weight\n"),
            .transport_samples = try createCsvFile(allocator, zig_root, "transport_samples.csv", "nominal_wavelength_nm,sample_index,sample_wavelength_nm,radiance,irradiance,weight\n"),
            .transport_summary = try createCsvFile(allocator, zig_root, "transport_summary.csv", "nominal_wavelength_nm,final_radiance,final_irradiance,final_reflectance\n"),
        };
    }

    fn deinit(self: *TraceFiles) void {
        self.line_catalog.close();
        self.strong_state.close();
        self.spectroscopy_summary.close();
        self.adaptive_grid.close();
        self.kernel_samples.close();
        self.transport_samples.close();
        self.transport_summary.close();
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
        scene: *const zdisamar.Scene,
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

    var prepared_case = try vendor_support.prepareVendorO2ATraceCase(allocator);
    defer prepared_case.deinit(allocator);

    var files = try TraceFiles.init(allocator, config.trace_root);
    defer files.deinit();

    var line_list = try prepared_case.prepared.spectroscopy_lines.?.clone(allocator);
    defer line_list.deinit(allocator);
    try line_list.buildStrongLineMatchIndex(allocator);

    try emitLineCatalog(
        &files.line_catalog,
        line_list,
        prepared_case.scene.spectral_grid.start_nm,
        prepared_case.scene.spectral_grid.end_nm,
    );
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
        config.wavelengths_nm,
    );

    var transport_buffers = try TransportBuffers.init(
        allocator,
        &prepared_case.scene,
        prepared_case.plan.transport_route,
        &prepared_case.prepared,
    );
    defer transport_buffers.deinit(allocator);

    try emitTransportTraces(
        allocator,
        &files,
        &prepared_case.scene,
        prepared_case.plan.transport_route,
        &prepared_case.prepared,
        .{
            .transport = prepared_case.plan.providers.transport,
            .surface = prepared_case.plan.providers.surface,
            .instrument = prepared_case.plan.providers.instrument,
            .noise = prepared_case.plan.providers.noise,
        },
        &transport_buffers,
        config.wavelengths_nm,
    );
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
        if (vendor_partition and isVendorStrongCandidate(line)) continue;
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
    wavelengths_nm: []const f64,
) !void {
    var rows = std.ArrayList(SpectroscopySummaryRow).empty;
    defer rows.deinit(std.heap.page_allocator);

    for (states, 0..) |state, state_index| {
        const sublayer = sublayers[state_index];
        for (wavelengths_nm) |wavelength_nm| {
            const evaluation = line_list.evaluateAtPrepared(
                wavelength_nm,
                sublayer.temperature_k,
                sublayer.pressure_hpa,
                &state,
            );
            try rows.append(std.heap.page_allocator, .{
                .pressure_hpa = sublayer.pressure_hpa,
                .temperature_k = sublayer.temperature_k,
                .wavelength_nm = wavelength_nm,
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

fn emitTransportTraces(
    allocator: std.mem.Allocator,
    files: *TraceFiles,
    scene: *const zdisamar.Scene,
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

    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const safe_span = if (span_nm <= 0.0) 1.0 else span_nm;
    const transport_layer_count = Measurement.workspace.resolvedTransportLayerCount(route, prepared);
    const radiance_calibration = providers.instrument.calibrationForScene(scene, .radiance);
    const irradiance_support = scene.observation_model.primaryOperationalBandSupport().operational_solar_spectrum;
    const solar_cosine = scene.geometry.solarCosineAtAltitude(0.0);

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
        var integration: InstrumentProviders.IntegrationKernel = undefined;
        providers.instrument.integrationForWavelength(
            scene,
            prepared,
            .radiance,
            nominal_wavelength_nm,
            &integration,
        );
        if (!integration.enabled) {
            integration = .{
                .enabled = true,
                .sample_count = 1,
                .offsets_nm = [_]f64{0.0} ++ [_]f64{0.0} ** (InstrumentProviders.max_integration_sample_count - 1),
                .weights = [_]f64{1.0} ++ [_]f64{0.0} ** (InstrumentProviders.max_integration_sample_count - 1),
            };
        }

        for (0..integration.sample_count) |sample_index| {
            const sample_wavelength_nm = evaluation_wavelength_nm + integration.offsets_nm[sample_index];
            const weight = integration.weights[sample_index];
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
            &integration,
        );
        const integrated_irradiance = try Measurement.spectral_eval.integrateIrradianceAtNominal(
            scene,
            prepared,
            evaluation_wavelength_nm,
            safe_span,
            &buffers.evaluation_cache,
            &integration,
        );
        try summary_rows.append(allocator, .{
            .nominal_wavelength_nm = nominal_wavelength_nm,
            .final_radiance = integrated_radiance.radiance,
            .final_irradiance = integrated_irradiance,
            .final_reflectance = (integrated_radiance.radiance * std.math.pi) /
                @max(integrated_irradiance * solar_cosine, 1.0e-12),
        });
    }

    std.sort.block(AdaptiveGridRow, adaptive_rows.items, {}, lessThanAdaptiveGridRow);
    std.sort.block(KernelSampleRow, kernel_rows.items, {}, lessThanKernelSampleRow);
    std.sort.block(TransportSampleRow, transport_rows.items, {}, lessThanTransportSampleRow);
    std.sort.block(TransportSummaryRow, summary_rows.items, {}, lessThanTransportSummaryRow);

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

fn sortNanLast(lhs: f64, rhs: f64) ?bool {
    const lhs_nan = std.math.isNan(lhs);
    const rhs_nan = std.math.isNan(rhs);
    if (lhs_nan and rhs_nan) return null;
    if (lhs_nan != rhs_nan) return !lhs_nan;
    if (lhs != rhs) return lhs < rhs;
    return null;
}
