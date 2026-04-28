const std = @import("std");
const AbsorberModel = @import("../../input/Absorber.zig");
const AtmosphereModel = @import("../../input/Atmosphere.zig");
const InstrumentModel = @import("../../input/Instrument.zig");
const Instrument = InstrumentModel.Instrument;
const MeasurementSpace = @import("../../forward_model/instrument_grid/root.zig");
const OpticsPrepare = @import("../../forward_model/optical_properties/root.zig");
const ObservationModel = @import("../../input/ObservationModel.zig");
const ReferenceDataModel = @import("../../input/ReferenceData.zig");
const Scene = @import("../../input/Scene.zig").Scene;
const SpectralGrid = @import("../../input/Spectrum.zig").SpectralGrid;
const bundled_optics = @import("../../input/reference_data/bundled/assets.zig");
const providers = @import("../../forward_model/builtins/root.zig");
const reference_assets = @import("../../input/reference_data/ingest/reference_assets.zig");
const transport_common = @import("../../forward_model/radiative_transfer/root.zig");
const parity_types = @import("types.zig");
const adaptive_plan = @import("../../forward_model/builtins/instrument/adaptive_plan.zig");
const instrument_types = @import("../../forward_model/builtins/instrument/types.zig");

const Allocator = std.mem.Allocator;
pub const AbsorberSpecies = parity_types.AbsorberSpecies;
pub const Route = parity_types.Route;
pub const RadiativeTransferControls = parity_types.RadiativeTransferControls;
pub const ReferenceSample = parity_types.ReferenceSample;
pub const ExternalAsset = parity_types.ExternalAsset;
pub const OutputKind = parity_types.OutputKind;
pub const OutputRequest = parity_types.OutputRequest;
pub const ValidationPolicy = parity_types.ValidationPolicy;
pub const PlanSpec = parity_types.PlanSpec;
pub const Metadata = parity_types.Metadata;
pub const GeometrySpec = parity_types.GeometrySpec;
pub const AerosolSpec = parity_types.AerosolSpec;
pub const ObservationSpec = parity_types.ObservationSpec;
pub const LineGasSpec = parity_types.LineGasSpec;
pub const CiaSpec = parity_types.CiaSpec;
pub const InputsSpec = parity_types.InputsSpec;
pub const ResolvedVendorO2ACase = parity_types.ResolvedVendorO2ACase;
pub const LoadedVendorO2AInputs = parity_types.LoadedVendorO2AInputs;
pub const SolarSpectrumSample = parity_types.SolarSpectrumSample;

pub fn loadReferenceSamples(allocator: Allocator, path: []const u8) ![]ReferenceSample {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(bytes);

    var samples = std.ArrayList(ReferenceSample).empty;
    errdefer samples.deinit(allocator);

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    _ = lines.next();
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, "\r \t");
        if (trimmed.len == 0) continue;

        var columns = std.mem.splitScalar(u8, trimmed, ',');
        const wavelength_text = columns.next() orelse return error.InvalidData;
        const irradiance_text = columns.next() orelse return error.InvalidData;
        _ = columns.next() orelse return error.InvalidData;
        const reflectance_text = columns.next() orelse return error.InvalidData;

        try samples.append(allocator, .{
            .wavelength_nm = try std.fmt.parseFloat(f64, std.mem.trim(u8, wavelength_text, " \t")),
            .irradiance = try std.fmt.parseFloat(f64, std.mem.trim(u8, irradiance_text, " \t")),
            .reflectance = try std.fmt.parseFloat(f64, std.mem.trim(u8, reflectance_text, " \t")),
        });
    }

    return try samples.toOwnedSlice(allocator);
}

pub fn loadSolarSpectrumSamples(
    allocator: Allocator,
    asset: ExternalAsset,
) ![]SolarSpectrumSample {
    if (!std.mem.eql(u8, asset.format, "solar_reference_csv")) return error.UnsupportedSolarReferenceAssetFormat;

    const file = try std.fs.cwd().openFile(asset.path, .{});
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(bytes);

    var samples = std.ArrayList(SolarSpectrumSample).empty;
    errdefer samples.deinit(allocator);

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    _ = lines.next();
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, "\r \t");
        if (trimmed.len == 0) continue;

        var columns = std.mem.splitScalar(u8, trimmed, ',');
        const wavelength_text = columns.next() orelse return error.InvalidData;
        const irradiance_text = columns.next() orelse return error.InvalidData;

        try samples.append(allocator, .{
            .wavelength_nm = try std.fmt.parseFloat(f64, std.mem.trim(u8, wavelength_text, " \t")),
            .irradiance = try std.fmt.parseFloat(f64, std.mem.trim(u8, irradiance_text, " \t")),
        });
    }

    return try samples.toOwnedSlice(allocator);
}

pub fn loadResolvedVendorO2AInputs(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
) !LoadedVendorO2AInputs {
    var profile_asset = try reference_assets.loadExternalAsset(
        allocator,
        .climatology_profile,
        resolved.inputs.atmosphere_profile.id,
        resolved.inputs.atmosphere_profile.path,
        resolved.inputs.atmosphere_profile.format,
    );
    defer profile_asset.deinit(allocator);
    var profile = try profile_asset.toClimatologyProfile(allocator);
    errdefer profile.deinit(allocator);
    var dense_profile = try profile.densifyVendorPressureGrid(allocator, resolved.surface_pressure_hpa);
    errdefer dense_profile.deinit(allocator);
    var spectroscopy_profile = try buildVendorTraceGasSpectroscopyProfile(
        allocator,
        profile,
        dense_profile,
    );
    errdefer spectroscopy_profile.deinit(allocator);
    profile.deinit(allocator);
    profile = dense_profile;
    dense_profile = .{ .rows = &.{} };

    var cross_sections = try bundled_optics.zeroContinuumTable(allocator, 758.0, 771.0);
    errdefer cross_sections.deinit(allocator);

    var line_list = try loadResolvedVendorO2ALineList(allocator, resolved.o2);
    errdefer line_list.deinit(allocator);

    var cia_table: ?ReferenceDataModel.CollisionInducedAbsorptionTable = null;
    errdefer if (cia_table) |*table| table.deinit(allocator);
    if (resolved.o2o2.enabled) {
        const cia_asset = resolved.o2o2.cia_asset orelse return error.MissingCollisionInducedAbsorptionAsset;
        var loaded_cia = try reference_assets.loadExternalAsset(
            allocator,
            .collision_induced_absorption_table,
            cia_asset.id,
            cia_asset.path,
            cia_asset.format,
        );
        defer loaded_cia.deinit(allocator);
        cia_table = try loaded_cia.toCollisionInducedAbsorptionTable(allocator);
    }

    var lut_asset = try reference_assets.loadExternalAsset(
        allocator,
        .lookup_table,
        resolved.inputs.airmass_factor_lut.id,
        resolved.inputs.airmass_factor_lut.path,
        resolved.inputs.airmass_factor_lut.format,
    );
    defer lut_asset.deinit(allocator);
    var lut = try lut_asset.toAirmassFactorLut(allocator);
    errdefer lut.deinit(allocator);

    const reference = try loadReferenceSamples(allocator, resolved.inputs.vendor_reference_csv.path);
    errdefer allocator.free(reference);
    const raw_solar_spectrum = try loadSolarSpectrumSamples(allocator, resolved.inputs.raw_solar_reference);
    errdefer allocator.free(raw_solar_spectrum);

    return .{
        .profile = profile,
        .spectroscopy_profile = spectroscopy_profile,
        .cross_sections = cross_sections,
        .line_list = line_list,
        .cia_table = cia_table,
        .lut = lut,
        .reference = reference,
        .raw_solar_spectrum = raw_solar_spectrum,
    };
}

pub fn loadResolvedVendorO2AAtmosphereProfile(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
) !ReferenceDataModel.ClimatologyProfile {
    var profile_asset = try reference_assets.loadExternalAsset(
        allocator,
        .climatology_profile,
        resolved.inputs.atmosphere_profile.id,
        resolved.inputs.atmosphere_profile.path,
        resolved.inputs.atmosphere_profile.format,
    );
    defer profile_asset.deinit(allocator);
    return profile_asset.toClimatologyProfile(allocator);
}

fn buildVendorTraceGasSpectroscopyProfile(
    allocator: Allocator,
    source_profile: ReferenceDataModel.ClimatologyProfile,
    dense_profile: ReferenceDataModel.ClimatologyProfile,
) !ReferenceDataModel.ClimatologyProfile {
    const rows = try allocator.alloc(ReferenceDataModel.ClimatologyPoint, source_profile.rows.len);
    errdefer allocator.free(rows);

    for (source_profile.rows, rows) |source_row, *target_row| {
        const pressure_hpa = source_row.pressure_hpa;
        const temperature_k = source_row.temperature_k;
        target_row.* = .{
            .altitude_km = dense_profile.interpolateAltitudeForPressureSpline(pressure_hpa),
            .pressure_hpa = pressure_hpa,
            .temperature_k = temperature_k,
            .air_number_density_cm3 = pressure_hpa / @max(temperature_k, 1.0e-9) / 1.380658e-19,
        };
    }

    return .{ .rows = rows };
}

pub fn buildResolvedVendorO2AScene(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
    raw_solar_spectrum: []const SolarSpectrumSample,
) !Scene {
    const solar_support_start_nm = resolved.spectral_grid.start_nm - (2.0 * resolved.observation.instrument_line_fwhm_nm);
    const solar_support_end_nm = resolved.spectral_grid.end_nm + (2.0 * resolved.observation.instrument_line_fwhm_nm);
    var retained_solar_count: usize = 0;
    for (raw_solar_spectrum) |sample| {
        if (sample.wavelength_nm <= solar_support_start_nm) continue;
        if (sample.wavelength_nm >= solar_support_end_nm) continue;
        retained_solar_count += 1;
    }
    if (retained_solar_count < 3) return error.InvalidData;

    const solar_wavelengths = try allocator.alloc(f64, retained_solar_count);
    var solar_wavelengths_owned = true;
    errdefer if (solar_wavelengths_owned) allocator.free(solar_wavelengths);
    const solar_irradiance = try allocator.alloc(f64, retained_solar_count);
    var solar_irradiance_owned = true;
    errdefer if (solar_irradiance_owned) allocator.free(solar_irradiance);
    var solar_index: usize = 0;
    for (raw_solar_spectrum) |sample| {
        if (sample.wavelength_nm <= solar_support_start_nm) continue;
        if (sample.wavelength_nm >= solar_support_end_nm) continue;
        solar_wavelengths[solar_index] = sample.wavelength_nm;
        solar_irradiance[solar_index] = sample.irradiance;
        solar_index += 1;
    }

    const absorber_items = try allocator.alloc(AbsorberModel.Absorber, 1);
    var absorber_items_owned = true;
    errdefer if (absorber_items_owned) allocator.free(absorber_items);
    const absorber_id = try allocator.dupe(u8, "o2");
    var absorber_id_owned = true;
    errdefer if (absorber_id_owned) allocator.free(absorber_id);
    const absorber_species = try allocator.dupe(u8, "o2");
    var absorber_species_owned = true;
    errdefer if (absorber_species_owned) allocator.free(absorber_species);
    const isotopes_sim = if (resolved.o2.isotopes_sim.len != 0)
        try allocator.dupe(u8, resolved.o2.isotopes_sim)
    else
        &.{};
    var isotopes_sim_owned = isotopes_sim.len != 0;
    errdefer if (isotopes_sim_owned) allocator.free(isotopes_sim);

    absorber_items[0] = .{
        .id = absorber_id,
        .species = absorber_species,
        .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "o2").?,
        .profile_source = .atmosphere,
        .spectroscopy = .{
            .mode = .line_by_line,
            .line_gas_controls = .{
                .factor_lm_sim = resolved.o2.line_mixing_factor,
                .isotopes_sim = isotopes_sim,
                .threshold_line_sim = resolved.o2.threshold_line_sim,
                .cutoff_sim_cm1 = resolved.o2.cutoff_sim_cm1,
                .active_stage = .simulation,
            },
        },
    };

    const parity_response: Instrument.SpectralResponse = .{
        .explicit = true,
        .slit_index = switch (resolved.observation.builtin_line_shape) {
            .gaussian => .gaussian_modulated,
            .flat_top_n4 => .flat_top_n4,
            .triple_flat_top_n4 => .triple_flat_top_n4,
        },
        .fwhm_nm = resolved.observation.instrument_line_fwhm_nm,
        .builtin_line_shape = resolved.observation.builtin_line_shape,
        .integration_mode = .disamar_hr_grid,
        .high_resolution_step_nm = resolved.observation.high_resolution_step_nm,
        .high_resolution_half_span_nm = resolved.observation.high_resolution_half_span_nm,
    };

    var scene: Scene = .{
        .id = resolved.scene_id,
        .surface = .{
            .albedo = resolved.surface_albedo,
            .pressure_hpa = resolved.surface_pressure_hpa,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = resolved.aerosol.optical_depth,
            .single_scatter_albedo = resolved.aerosol.single_scatter_albedo,
            .asymmetry_factor = resolved.aerosol.asymmetry_factor,
            .angstrom_exponent = resolved.aerosol.angstrom_exponent,
            .reference_wavelength_nm = resolved.aerosol.reference_wavelength_nm,
            .layer_center_km = resolved.aerosol.layer_center_km,
            .layer_width_km = resolved.aerosol.layer_width_km,
            .placement = resolved.aerosol.placement,
        },
        .geometry = .{
            .model = resolved.geometry.model,
            .solar_zenith_deg = resolved.geometry.solar_zenith_deg,
            .viewing_zenith_deg = resolved.geometry.viewing_zenith_deg,
            .relative_azimuth_deg = resolved.geometry.relative_azimuth_deg,
        },
        .atmosphere = .{
            .layer_count = resolved.layer_count,
            .sublayer_divisions = resolved.sublayer_divisions,
            .surface_pressure_hpa = resolved.surface_pressure_hpa,
            .has_aerosols = true,
        },
        .spectral_grid = resolved.spectral_grid,
        .absorbers = .{
            .items = absorber_items,
        },
        .observation_model = .{
            .instrument = .{ .custom = resolved.observation.instrument_name },
            .regime = resolved.observation.regime,
            .sampling = resolved.observation.sampling,
            .noise_model = resolved.observation.noise_model,
            .instrument_line_fwhm_nm = resolved.observation.instrument_line_fwhm_nm,
            .builtin_line_shape = resolved.observation.builtin_line_shape,
            .high_resolution_step_nm = resolved.observation.high_resolution_step_nm,
            .high_resolution_half_span_nm = resolved.observation.high_resolution_half_span_nm,
            .adaptive_reference_grid = resolved.observation.adaptive_reference_grid,
            .operational_solar_spectrum = .{
                .wavelengths_nm = solar_wavelengths,
                .irradiance = solar_irradiance,
            },
            .measurement_pipeline = .{
                .radiance = .{
                    .explicit = true,
                    .response = parity_response,
                },
                .irradiance = .{
                    .explicit = true,
                    .response = parity_response,
                },
            },
        },
    };
    solar_wavelengths_owned = false;
    solar_irradiance_owned = false;
    absorber_items_owned = false;
    absorber_id_owned = false;
    absorber_species_owned = false;
    isotopes_sim_owned = false;
    errdefer scene.deinitOwned(allocator);

    if (resolved.intervals.len != 0) {
        scene.atmosphere.interval_grid = .{
            .semantics = .explicit_pressure_bounds,
            .fit_interval_index_1based = resolved.fit_interval_index_1based,
            .intervals = resolved.intervals,
        };
    }
    try scene.observation_model.operational_solar_spectrum.prepareInterpolation(allocator);
    return scene;
}

pub fn prepareResolvedVendorO2ARoute(
    scene: *const Scene,
    rtm_controls: RadiativeTransferControls,
) !Route {
    return transport_common.prepareRoute(.{
        .regime = scene.observation_model.regime,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = rtm_controls,
    });
}

pub fn runResolvedVendorO2AReflectanceCase(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
) !struct {
    reference: []ReferenceSample,
    scene: Scene,
    route: Route,
    prepared: OpticsPrepare.PreparedOpticalState,
    product: MeasurementSpace.MeasurementSpaceProduct,
} {
    var prepared_case = try prepareResolvedVendorO2ACase(allocator, resolved);
    errdefer {
        prepared_case.prepared.deinit(allocator);
        prepared_case.scene.deinitOwned(allocator);
        allocator.free(prepared_case.reference);
    }

    var product = try MeasurementSpace.simulateProduct(
        allocator,
        &prepared_case.scene,
        prepared_case.route,
        &prepared_case.prepared,
        providers.exact(),
    );
    errdefer product.deinit(allocator);

    return .{
        .reference = prepared_case.reference,
        .scene = prepared_case.scene,
        .route = prepared_case.route,
        .prepared = prepared_case.prepared,
        .product = product,
    };
}

pub fn prepareResolvedVendorO2ACase(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
) !struct {
    reference: []ReferenceSample,
    scene: Scene,
    route: Route,
    prepared: OpticsPrepare.PreparedOpticalState,
} {
    var inputs = try loadResolvedVendorO2AInputs(allocator, resolved);
    defer inputs.deinit(allocator);

    var scene = try buildResolvedVendorO2AScene(allocator, resolved, inputs.raw_solar_spectrum);
    errdefer scene.deinitOwned(allocator);

    const reference = inputs.reference;
    inputs.reference = inputs.reference[0..0];
    errdefer allocator.free(reference);

    var prepared = try OpticsPrepare.prepare(allocator, &scene, .{
        .profile = &inputs.profile,
        .spectroscopy_profile = &inputs.spectroscopy_profile,
        .cross_sections = &inputs.cross_sections,
        .collision_induced_absorption = if (inputs.cia_table) |*table| table else null,
        .spectroscopy_lines = &inputs.line_list,
        .lut = &inputs.lut,
    });
    errdefer prepared.deinit(allocator);

    try installVendorWeakCutoffGrid(allocator, &scene, &prepared);
    try rewindowParitySolarSupportToMeasurementKernel(allocator, &scene, &prepared);

    const route = try prepareResolvedVendorO2ARoute(&scene, resolved.rtm_controls);

    return .{
        .reference = reference,
        .scene = scene,
        .route = route,
        .prepared = prepared,
    };
}

fn installVendorWeakCutoffGrid(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *OpticsPrepare.PreparedOpticalState,
) !void {
    const response = scene.observation_model.resolvedChannelControls(.radiance).response;
    var has_cutoff_line_list = false;
    if (prepared.spectroscopy_lines) |line_list| {
        has_cutoff_line_list = line_list.runtime_controls.cutoff_cm1 != null;
    }
    for (prepared.line_absorbers) |line_absorber| {
        has_cutoff_line_list = has_cutoff_line_list or line_absorber.line_list.runtime_controls.cutoff_cm1 != null;
    }
    if (!has_cutoff_line_list) return;

    const support = try adaptive_plan.buildAdaptiveSupportWavelengths(
        allocator,
        scene,
        prepared,
        response,
    ) orelse {
        return error.DisamarKernelRealizationFailed;
    };
    defer allocator.free(support);
    if (support.len < 2) return error.DisamarKernelRealizationFailed;

    if (prepared.spectroscopy_lines) |*line_list| {
        try installCutoffGridOnLineList(allocator, line_list, support);
    }
    for (prepared.line_absorbers) |*line_absorber| {
        try installCutoffGridOnLineList(allocator, &line_absorber.line_list, support);
    }
}

fn installCutoffGridOnLineList(
    allocator: Allocator,
    line_list: *ReferenceDataModel.SpectroscopyLineList,
    support_wavelengths_nm: []const f64,
) !void {
    if (line_list.runtime_controls.cutoff_cm1 == null) return;
    const owned_support = try allocator.dupe(f64, support_wavelengths_nm);
    if (line_list.runtime_controls.cutoff_grid_wavelengths_nm.len != 0) {
        allocator.free(line_list.runtime_controls.cutoff_grid_wavelengths_nm);
    }
    line_list.runtime_controls.cutoff_grid_wavelengths_nm = owned_support;
}

fn rewindowParitySolarSupportToMeasurementKernel(
    allocator: Allocator,
    scene: *Scene,
    prepared: *const OpticsPrepare.PreparedOpticalState,
) !void {
    if (!scene.observation_model.operational_solar_spectrum.enabled()) return;

    const support = try sharedParityMeasurementSupport(scene, prepared) orelse return;
    const support_start_nm = support.start_nm;
    const support_end_nm = support.end_nm;
    if (!(support_end_nm > support_start_nm)) return;

    const current = scene.observation_model.operational_solar_spectrum;
    var retained_count: usize = 0;
    for (current.wavelengths_nm) |wavelength_nm| {
        if (wavelength_nm < support_start_nm) continue;
        if (wavelength_nm > support_end_nm) continue;
        retained_count += 1;
    }
    if (retained_count < 3) return error.InvalidData;

    const retained_wavelengths_nm = try allocator.alloc(f64, retained_count);
    var retained_wavelengths_owned = true;
    errdefer if (retained_wavelengths_owned) allocator.free(retained_wavelengths_nm);
    const retained_irradiance = try allocator.alloc(f64, retained_count);
    var retained_irradiance_owned = true;
    errdefer if (retained_irradiance_owned) allocator.free(retained_irradiance);

    var retained_index: usize = 0;
    for (current.wavelengths_nm, current.irradiance) |wavelength_nm, irradiance| {
        if (wavelength_nm < support_start_nm) continue;
        if (wavelength_nm > support_end_nm) continue;
        retained_wavelengths_nm[retained_index] = wavelength_nm;
        retained_irradiance[retained_index] = irradiance;
        retained_index += 1;
    }

    scene.observation_model.operational_solar_spectrum.deinitOwned(allocator);
    scene.observation_model.operational_solar_spectrum = .{
        .wavelengths_nm = retained_wavelengths_nm,
        .irradiance = retained_irradiance,
    };
    retained_wavelengths_owned = false;
    retained_irradiance_owned = false;
    try scene.observation_model.operational_solar_spectrum.prepareInterpolation(allocator);
}

fn sharedParityMeasurementSupport(
    scene: *const Scene,
    prepared: *const OpticsPrepare.PreparedOpticalState,
) !?struct { start_nm: f64, end_nm: f64 } {
    var radiance_start: instrument_types.IntegrationKernel = undefined;
    var radiance_end: instrument_types.IntegrationKernel = undefined;
    var irradiance_start: instrument_types.IntegrationKernel = undefined;
    var irradiance_end: instrument_types.IntegrationKernel = undefined;

    try @import("../../forward_model/builtins/instrument/integration.zig").integrationForWavelengthChecked(
        scene,
        prepared,
        .radiance,
        scene.spectral_grid.start_nm,
        &radiance_start,
    );
    try @import("../../forward_model/builtins/instrument/integration.zig").integrationForWavelengthChecked(
        scene,
        prepared,
        .radiance,
        scene.spectral_grid.end_nm,
        &radiance_end,
    );
    try @import("../../forward_model/builtins/instrument/integration.zig").integrationForWavelengthChecked(
        scene,
        prepared,
        .irradiance,
        scene.spectral_grid.start_nm,
        &irradiance_start,
    );
    try @import("../../forward_model/builtins/instrument/integration.zig").integrationForWavelengthChecked(
        scene,
        prepared,
        .irradiance,
        scene.spectral_grid.end_nm,
        &irradiance_end,
    );

    if (!radiance_start.enabled or !radiance_end.enabled or
        !irradiance_start.enabled or !irradiance_end.enabled or
        radiance_start.sample_count == 0 or radiance_end.sample_count == 0 or
        irradiance_start.sample_count == 0 or irradiance_end.sample_count == 0)
    {
        return null;
    }

    try expectParityKernelBoundsMatch(radiance_start, irradiance_start);
    try expectParityKernelBoundsMatch(radiance_end, irradiance_end);

    return .{
        .start_nm = scene.spectral_grid.start_nm + radiance_start.offsets_nm[0],
        .end_nm = scene.spectral_grid.end_nm + radiance_end.offsets_nm[radiance_end.sample_count - 1],
    };
}

fn expectParityKernelBoundsMatch(
    lhs: instrument_types.IntegrationKernel,
    rhs: instrument_types.IntegrationKernel,
) !void {
    if (lhs.sample_count != rhs.sample_count) return error.InvalidRequest;
    if (@abs(lhs.offsets_nm[0] - rhs.offsets_nm[0]) > 1.0e-12) return error.InvalidRequest;
    if (@abs(lhs.offsets_nm[lhs.sample_count - 1] - rhs.offsets_nm[rhs.sample_count - 1]) > 1.0e-12) {
        return error.InvalidRequest;
    }
}

pub fn loadResolvedVendorO2ALineList(
    allocator: Allocator,
    spec: LineGasSpec,
) !ReferenceDataModel.SpectroscopyLineList {
    var asset = try reference_assets.loadExternalAsset(
        allocator,
        .spectroscopy_line_list,
        spec.line_list_asset.id,
        spec.line_list_asset.path,
        spec.line_list_asset.format,
    );
    defer asset.deinit(allocator);

    var line_list = try asset.toSpectroscopyLineList(allocator);
    errdefer line_list.deinit(allocator);

    var strong_lines_asset = try reference_assets.loadExternalAsset(
        allocator,
        .spectroscopy_strong_line_set,
        spec.strong_lines_asset.id,
        spec.strong_lines_asset.path,
        spec.strong_lines_asset.format,
    );
    defer strong_lines_asset.deinit(allocator);

    var strong_lines = try strong_lines_asset.toSpectroscopyStrongLineSet(allocator);
    defer strong_lines.deinit(allocator);

    var relaxation_asset = try reference_assets.loadExternalAsset(
        allocator,
        .spectroscopy_relaxation_matrix,
        spec.line_mixing_asset.id,
        spec.line_mixing_asset.path,
        spec.line_mixing_asset.format,
    );
    defer relaxation_asset.deinit(allocator);

    var relaxation_matrix = try relaxation_asset.toSpectroscopyRelaxationMatrix(allocator);
    defer relaxation_matrix.deinit(allocator);

    try line_list.attachStrongLineSidecars(allocator, strong_lines, relaxation_matrix);
    return line_list;
}
