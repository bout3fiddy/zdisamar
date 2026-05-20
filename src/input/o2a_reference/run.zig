const std = @import("std");
const AbsorberModel = @import("../../input/Absorber.zig");
const AtmosphereModel = @import("../../input/Atmosphere.zig");
const InstrumentModel = @import("../../input/Instrument.zig");
const Instrument = InstrumentModel.Instrument;
const InstrumentGrid = @import("../../forward_model/instrument_grid/root.zig");
const OpticsPrepare = @import("../../forward_model/optical_properties/root.zig");
const ObservationModel = @import("../../input/ObservationModel.zig");
const ReferenceDataModel = @import("../../input/ReferenceData.zig");
const Scene = @import("../../input/Scene.zig").Scene;
const SpectralGrid = @import("../../input/Spectrum.zig").SpectralGrid;
const Trace = @import("../../forward_model/performance_trace.zig");
const bundled_optics = @import("../../input/reference_data/bundled/assets.zig");
const implementations = @import("../../forward_model/implementations/root.zig");
const reference_assets = @import("../../input/reference_data/ingest/reference_assets.zig");
const transport_common = @import("../../forward_model/radiative_transfer/root.zig");
const reference_types = @import("types.zig");
const adaptive_plan = @import("../../forward_model/implementations/instrument/adaptive_plan.zig");
const instrument_types = @import("../../forward_model/implementations/instrument/types.zig");
const fixed_asset_cache = @import("fixed_asset_cache.zig");

const Allocator = std.mem.Allocator;
pub const AbsorberSpecies = reference_types.AbsorberSpecies;
pub const Route = reference_types.Route;
pub const RadiativeTransferControls = reference_types.RadiativeTransferControls;
pub const ReferenceSample = reference_types.ReferenceSample;
pub const ExternalAsset = reference_types.ExternalAsset;
pub const OutputKind = reference_types.OutputKind;
pub const OutputRequest = reference_types.OutputRequest;
pub const ValidationPolicy = reference_types.ValidationPolicy;
pub const PlanSpec = reference_types.PlanSpec;
pub const Metadata = reference_types.Metadata;
pub const GeometrySpec = reference_types.GeometrySpec;
pub const AerosolSpec = reference_types.AerosolSpec;
pub const ObservationSpec = reference_types.ObservationSpec;
pub const LineGasSpec = reference_types.LineGasSpec;
pub const CiaSpec = reference_types.CiaSpec;
pub const InputsSpec = reference_types.InputsSpec;
pub const ResolvedVendorO2ACase = reference_types.ResolvedVendorO2ACase;
pub const LoadedVendorO2AInputs = reference_types.LoadedVendorO2AInputs;
pub const SolarSpectrumSample = reference_types.SolarSpectrumSample;

// layout(64-bit):
//   size: 3824 B, align: 8 B
//   field storage: reference=16 B, scene=2680 B, route=72 B, prepared=1056 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: reference carry references/descriptors; referenced storage is not included in size
//   cache span: 60 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 3824 B (3.734 KiB); total also includes referenced storage above
pub const PreparedRuntimeCase = struct {
    reference: []ReferenceSample,
    scene: Scene,
    route: Route,
    prepared: OpticsPrepare.PreparedOpticalState,
};

// Runtime-prepared O2 A case for repeated native retrieval evaluations.
// layout(64-bit):
//   size: 3808 B, align: 8 B
//   field storage: scene=2680 B, route=72 B, prepared=1056 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: scene and prepared carry owned buffers; referenced storage is not included in size
//   cache span: 60 cache line(s) at 64 B per line
//   count: one live value per native OE forward evaluation
//   footprint: per instance = 3808 B (3.719 KiB); total also includes referenced storage above
pub const PreparedRuntimeEvaluation = struct {
    scene: Scene,
    route: Route,
    prepared: OpticsPrepare.PreparedOpticalState,

    pub fn deinit(self: *PreparedRuntimeEvaluation, allocator: Allocator) void {
        self.prepared.deinit(allocator);
        self.scene.deinitOwned(allocator);
        self.* = undefined;
    }
};

pub const PreparedRuntimeOptics = struct {
    scene: Scene,
    prepared: OpticsPrepare.PreparedOpticalState,

    pub fn deinit(self: *PreparedRuntimeOptics, allocator: Allocator) void {
        self.prepared.deinit(allocator);
        self.scene.deinitOwned(allocator);
        self.* = undefined;
    }
};

// Retrieval-scoped weak-line cutoff support reused across state evaluations.
// layout(64-bit):
//   size: 32 B, align: 8 B
//   field storage: two slice descriptors at 16 B each; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: wavelength and wavenumber grids are owned dense f64 buffers
//   cache span: 1 cache line(s) at 64 B per line
//   count: one per O2 A retrieval case when vendor weak cutoff is active
//   footprint: per instance = 32 B (0.031 KiB); total also includes 2 * support_count * 8 B
pub const WeakCutoffGridCache = struct {
    wavelengths_nm: []f64 = &.{},
    wavenumbers_cm1: []f64 = &.{},

    pub fn deinit(self: *WeakCutoffGridCache, allocator: Allocator) void {
        allocator.free(self.wavelengths_nm);
        allocator.free(self.wavenumbers_cm1);
        self.* = .{};
    }

    fn valid(self: WeakCutoffGridCache) bool {
        return self.wavelengths_nm.len >= 2 and self.wavelengths_nm.len == self.wavenumbers_cm1.len;
    }

    fn replaceFromSupport(
        self: *WeakCutoffGridCache,
        allocator: Allocator,
        support_wavelengths_nm: []const f64,
    ) !void {
        const owned_wavelengths = try allocator.dupe(f64, support_wavelengths_nm);
        errdefer allocator.free(owned_wavelengths);
        const owned_wavenumbers = try allocator.alloc(f64, support_wavelengths_nm.len);
        errdefer allocator.free(owned_wavenumbers);
        for (support_wavelengths_nm, owned_wavenumbers) |wavelength_nm, *wavenumber_cm1| {
            wavenumber_cm1.* = 1.0e7 / @max(wavelength_nm, 1.0e-9);
        }

        self.deinit(allocator);
        self.wavelengths_nm = owned_wavelengths;
        self.wavenumbers_cm1 = owned_wavenumbers;
    }
};

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
    var profile = try loadFixedClimatologyProfile(allocator, resolved.inputs.atmosphere_profile);
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
        cia_table = try loadFixedCiaTable(allocator, cia_asset);
    }

    var lut = try loadFixedAirmassLut(allocator, resolved.inputs.airmass_factor_lut);
    errdefer lut.deinit(allocator);

    const reference = try loadFixedReferenceSamples(allocator, resolved.inputs.vendor_reference_csv);
    errdefer allocator.free(reference);
    const raw_solar_spectrum = try loadFixedSolarSpectrumSamples(allocator, resolved.inputs.raw_solar_reference);
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
    return loadFixedClimatologyProfile(allocator, resolved.inputs.atmosphere_profile);
}

fn loadFixedClimatologyProfile(
    allocator: Allocator,
    asset: ExternalAsset,
) !ReferenceDataModel.ClimatologyProfile {
    if (try fixed_asset_cache.loadProfile(allocator, asset)) |cached| return cached;

    var profile_asset = try reference_assets.loadExternalAsset(
        allocator,
        .climatology_profile,
        asset.id,
        asset.path,
        asset.format,
    );
    defer profile_asset.deinit(allocator);
    var profile = try profile_asset.toClimatologyProfile(allocator);
    errdefer profile.deinit(allocator);
    try fixed_asset_cache.storeProfile(asset, profile);
    return profile;
}

fn loadFixedCiaTable(
    allocator: Allocator,
    asset: ExternalAsset,
) !ReferenceDataModel.CollisionInducedAbsorptionTable {
    if (try fixed_asset_cache.loadCia(allocator, asset)) |cached| return cached;

    var loaded_cia = try reference_assets.loadExternalAsset(
        allocator,
        .collision_induced_absorption_table,
        asset.id,
        asset.path,
        asset.format,
    );
    defer loaded_cia.deinit(allocator);
    var table = try loaded_cia.toCollisionInducedAbsorptionTable(allocator);
    errdefer table.deinit(allocator);
    try fixed_asset_cache.storeCia(asset, table);
    return table;
}

fn loadFixedAirmassLut(
    allocator: Allocator,
    asset: ExternalAsset,
) !ReferenceDataModel.AirmassFactorLut {
    if (try fixed_asset_cache.loadAirmassLut(allocator, asset)) |cached| return cached;

    var lut_asset = try reference_assets.loadExternalAsset(
        allocator,
        .lookup_table,
        asset.id,
        asset.path,
        asset.format,
    );
    defer lut_asset.deinit(allocator);
    var lut = try lut_asset.toAirmassFactorLut(allocator);
    errdefer lut.deinit(allocator);
    try fixed_asset_cache.storeAirmassLut(asset, lut);
    return lut;
}

fn loadFixedReferenceSamples(
    allocator: Allocator,
    asset: ExternalAsset,
) ![]ReferenceSample {
    if (try fixed_asset_cache.loadReferenceSamples(allocator, asset)) |cached| return cached;

    const samples = try loadReferenceSamples(allocator, asset.path);
    errdefer allocator.free(samples);
    try fixed_asset_cache.storeReferenceSamples(asset, samples);
    return samples;
}

fn loadFixedSolarSpectrumSamples(
    allocator: Allocator,
    asset: ExternalAsset,
) ![]SolarSpectrumSample {
    if (try fixed_asset_cache.loadSolarSamples(allocator, asset)) |cached| return cached;

    const samples = try loadSolarSpectrumSamples(allocator, asset);
    errdefer allocator.free(samples);
    try fixed_asset_cache.storeSolarSamples(asset, samples);
    return samples;
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
    var solar_spectrum = try retainSolarSupport(allocator, resolved, raw_solar_spectrum);
    var solar_spectrum_owned = true;
    errdefer if (solar_spectrum_owned) solar_spectrum.deinitOwned(allocator);

    var absorber_set = try buildO2AbsorberSet(allocator, resolved);
    var absorber_set_owned = true;
    errdefer if (absorber_set_owned) absorber_set.deinitOwned(allocator);

    var scene = sceneFromResolvedO2A(
        resolved,
        absorber_set,
        solar_spectrum,
        referenceSpectralResponse(resolved),
    );
    solar_spectrum_owned = false;
    absorber_set_owned = false;
    errdefer scene.deinitOwned(allocator);

    attachResolvedIntervals(&scene, resolved);
    try scene.observation_model.operational_solar_spectrum.prepareInterpolation(allocator);
    return scene;
}

fn retainSolarSupport(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
    raw_solar_spectrum: []const SolarSpectrumSample,
) !InstrumentModel.OperationalSolarSpectrum {
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
    errdefer allocator.free(solar_wavelengths);
    const solar_irradiance = try allocator.alloc(f64, retained_solar_count);
    errdefer allocator.free(solar_irradiance);
    var solar_index: usize = 0;
    for (raw_solar_spectrum) |sample| {
        if (sample.wavelength_nm <= solar_support_start_nm) continue;
        if (sample.wavelength_nm >= solar_support_end_nm) continue;
        solar_wavelengths[solar_index] = sample.wavelength_nm;
        solar_irradiance[solar_index] = sample.irradiance;
        solar_index += 1;
    }

    return .{
        .wavelengths_nm = solar_wavelengths,
        .irradiance = solar_irradiance,
    };
}

fn buildO2AbsorberSet(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
) !AbsorberModel.AbsorberSet {
    const absorber_items = try allocator.alloc(AbsorberModel.Absorber, 1);
    errdefer allocator.free(absorber_items);
    const absorber_id = try allocator.dupe(u8, "o2");
    errdefer allocator.free(absorber_id);
    const absorber_species = try allocator.dupe(u8, "o2");
    errdefer allocator.free(absorber_species);
    const isotopes_sim = if (resolved.o2.isotopes_sim.len != 0)
        try allocator.dupe(u8, resolved.o2.isotopes_sim)
    else
        &.{};
    errdefer if (isotopes_sim.len != 0) allocator.free(isotopes_sim);

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

    return .{
        .items = absorber_items,
    };
}

fn referenceSpectralResponse(resolved: *const ResolvedVendorO2ACase) Instrument.SpectralResponse {
    return .{
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
}

fn sceneFromResolvedO2A(
    resolved: *const ResolvedVendorO2ACase,
    absorber_set: AbsorberModel.AbsorberSet,
    solar_spectrum: InstrumentModel.OperationalSolarSpectrum,
    reference_response: Instrument.SpectralResponse,
) Scene {
    return .{
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
        .absorbers = absorber_set,
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
            .operational_solar_spectrum = solar_spectrum,
            .measurement_pipeline = .{
                .radiance = .{
                    .explicit = true,
                    .response = reference_response,
                },
                .irradiance = .{
                    .explicit = true,
                    .response = reference_response,
                },
            },
        },
        .phase_function_truncation_threshold = resolved.rtm_controls.performance_thresholds.phase_function_truncation_threshold,
    };
}

fn attachResolvedIntervals(scene: *Scene, resolved: *const ResolvedVendorO2ACase) void {
    if (resolved.intervals.len != 0) {
        scene.atmosphere.interval_grid = .{
            .semantics = .explicit_pressure_bounds,
            .fit_interval_index_1based = resolved.fit_interval_index_1based,
            .intervals = resolved.intervals,
        };
    }
}

pub fn prepareResolvedVendorO2ARoute(
    scene: *const Scene,
    plan: PlanSpec,
    rtm_controls: RadiativeTransferControls,
) !Route {
    return transport_common.prepareRoute(.{
        .regime = scene.observation_model.regime,
        .execution_mode = try plan.executionMode(),
        .derivative_mode = try plan.derivativeMode(),
        .rtm_controls = rtm_controls,
    });
}

pub fn prepareResolvedVendorO2ARouteFromResolved(resolved: *const ResolvedVendorO2ACase) !Route {
    return transport_common.prepareRoute(.{
        .regime = resolved.observation.regime,
        .execution_mode = try resolved.plan.executionMode(),
        .derivative_mode = try resolved.plan.derivativeMode(),
        .rtm_controls = resolved.rtm_controls,
    });
}

pub fn runResolvedVendorO2AReflectanceCase(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
) !struct {
    // layout(64-bit):
    //   anonymous success payload: size 4144 B, align 8 B; padding is included in payload size
    //   footprint: per successful return payload = 4144 B (4.047 KiB)
    reference: []ReferenceSample,
    scene: Scene,
    route: Route,
    prepared: OpticsPrepare.PreparedOpticalState,
    product: InstrumentGrid.InstrumentGridProduct,
} {
    var prepared_case = try prepareResolvedVendorO2ACase(allocator, resolved);
    errdefer {
        prepared_case.prepared.deinit(allocator);
        prepared_case.scene.deinitOwned(allocator);
        allocator.free(prepared_case.reference);
    }

    var product = try InstrumentGrid.simulateProduct(
        allocator,
        &prepared_case.scene,
        prepared_case.route,
        &prepared_case.prepared,
        implementations.exact(),
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
) !PreparedRuntimeCase {
    var inputs = inputs: {
        const zone = Trace.staticZone(@src(), "prepare.load_inputs");
        defer zone.end();
        break :inputs try loadResolvedVendorO2AInputs(allocator, resolved);
    };
    defer inputs.deinit(allocator);

    var scene = scene: {
        const zone = Trace.staticZone(@src(), "prepare.build_scene");
        defer zone.end();
        break :scene try buildResolvedVendorO2AScene(allocator, resolved, inputs.raw_solar_spectrum);
    };
    errdefer scene.deinitOwned(allocator);

    const reference = inputs.reference;
    inputs.reference = inputs.reference[0..0];
    errdefer allocator.free(reference);

    var prepared = prepared: {
        const zone = Trace.staticZone(@src(), "prepare.optical");
        defer zone.end();
        break :prepared try OpticsPrepare.prepare(allocator, &scene, .{
            .profile = &inputs.profile,
            .spectroscopy_profile = &inputs.spectroscopy_profile,
            .cross_sections = &inputs.cross_sections,
            .collision_induced_absorption = if (inputs.cia_table) |*table| table else null,
            .spectroscopy_lines = &inputs.line_list,
            .lut = &inputs.lut,
        });
    };
    errdefer prepared.deinit(allocator);

    {
        const zone = Trace.staticZone(@src(), "prepare.weak_cutoff_grid");
        defer zone.end();
        try installVendorWeakCutoffGrid(allocator, &scene, &prepared, null);
    }

    {
        const zone = Trace.staticZone(@src(), "prepare.solar_rewindow");
        defer zone.end();
        try rewindowParitySolarSupportToMeasurementKernel(allocator, &scene, &prepared);
    }

    const route = route: {
        const zone = Trace.staticZone(@src(), "prepare.route");
        defer zone.end();
        break :route try prepareResolvedVendorO2ARoute(&scene, resolved.plan, resolved.rtm_controls);
    };

    return .{
        .reference = reference,
        .scene = scene,
        .route = route,
        .prepared = prepared,
    };
}

pub fn prepareResolvedVendorO2AEvaluationWithInputs(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
    inputs: *const LoadedVendorO2AInputs,
) !PreparedRuntimeEvaluation {
    var optics = try prepareResolvedVendorO2AOpticsWithInputs(allocator, resolved, inputs);
    errdefer optics.deinit(allocator);

    const route = route: {
        const zone = Trace.staticZone(@src(), "prepare.route");
        defer zone.end();
        break :route try prepareResolvedVendorO2ARoute(&optics.scene, resolved.plan, resolved.rtm_controls);
    };

    return .{
        .scene = optics.scene,
        .route = route,
        .prepared = optics.prepared,
    };
}

pub fn prepareResolvedVendorO2AOpticsWithInputs(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
    inputs: *const LoadedVendorO2AInputs,
) !PreparedRuntimeOptics {
    return prepareResolvedVendorO2AOpticsWithInputsInternal(
        allocator,
        resolved,
        inputs,
        null,
    );
}

pub fn prepareResolvedVendorO2AOpticsWithInputsAndWeakCutoffCache(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
    inputs: *const LoadedVendorO2AInputs,
    weak_cutoff_grid: *WeakCutoffGridCache,
) !PreparedRuntimeOptics {
    return prepareResolvedVendorO2AOpticsWithInputsInternal(
        allocator,
        resolved,
        inputs,
        weak_cutoff_grid,
    );
}

fn prepareResolvedVendorO2AOpticsWithInputsInternal(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
    inputs: *const LoadedVendorO2AInputs,
    weak_cutoff_grid: ?*WeakCutoffGridCache,
) !PreparedRuntimeOptics {
    var scene = scene: {
        const zone = Trace.staticZone(@src(), "prepare.build_scene");
        defer zone.end();
        break :scene try buildResolvedVendorO2AScene(allocator, resolved, inputs.raw_solar_spectrum);
    };
    errdefer scene.deinitOwned(allocator);

    var solar_rewindowed = false;
    var prepared = try prepareResolvedVendorO2AOpticalStateWithSceneInternal(
        allocator,
        &scene,
        inputs,
        weak_cutoff_grid,
        &solar_rewindowed,
        null,
    );
    errdefer prepared.deinit(allocator);

    return .{
        .scene = scene,
        .prepared = prepared,
    };
}

pub fn prepareResolvedVendorO2AOpticalStateWithSceneAndCaches(
    allocator: Allocator,
    scene: *Scene,
    inputs: *const LoadedVendorO2AInputs,
    weak_cutoff_grid: *WeakCutoffGridCache,
    solar_rewindowed: *bool,
) !OpticsPrepare.PreparedOpticalState {
    return prepareResolvedVendorO2AOpticalStateWithSceneInternal(
        allocator,
        scene,
        inputs,
        weak_cutoff_grid,
        solar_rewindowed,
        null,
    );
}

pub fn prepareResolvedVendorO2AOpticalStateWithSceneCachesAndProfilePreparation(
    allocator: Allocator,
    scene: *Scene,
    inputs: *const LoadedVendorO2AInputs,
    weak_cutoff_grid: *WeakCutoffGridCache,
    solar_rewindowed: *bool,
    borrowed_profile_preparation: *const OpticsPrepare.BorrowedProfilePreparation,
) !OpticsPrepare.PreparedOpticalState {
    return prepareResolvedVendorO2AOpticalStateWithSceneInternal(
        allocator,
        scene,
        inputs,
        weak_cutoff_grid,
        solar_rewindowed,
        borrowed_profile_preparation,
    );
}

fn prepareResolvedVendorO2AOpticalStateWithSceneInternal(
    allocator: Allocator,
    scene: *Scene,
    inputs: *const LoadedVendorO2AInputs,
    weak_cutoff_grid: ?*WeakCutoffGridCache,
    solar_rewindowed: *bool,
    borrowed_profile_preparation: ?*const OpticsPrepare.BorrowedProfilePreparation,
) !OpticsPrepare.PreparedOpticalState {
    var prepared = prepared: {
        const zone = Trace.staticZone(@src(), "prepare.optical");
        defer zone.end();
        break :prepared try OpticsPrepare.prepare(allocator, scene, .{
            .profile = &inputs.profile,
            .spectroscopy_profile = &inputs.spectroscopy_profile,
            .cross_sections = &inputs.cross_sections,
            .collision_induced_absorption = if (inputs.cia_table) |*table| table else null,
            .spectroscopy_lines = &inputs.line_list,
            .lut = &inputs.lut,
            .borrowed_profile_preparation = borrowed_profile_preparation,
        });
    };
    errdefer prepared.deinit(allocator);

    {
        const zone = Trace.staticZone(@src(), "prepare.weak_cutoff_grid");
        defer zone.end();
        try installVendorWeakCutoffGrid(allocator, scene, &prepared, weak_cutoff_grid);
    }

    if (!solar_rewindowed.*) {
        const zone = Trace.staticZone(@src(), "prepare.solar_rewindow");
        defer zone.end();
        try rewindowParitySolarSupportToMeasurementKernel(allocator, scene, &prepared);
        solar_rewindowed.* = true;
    }

    return prepared;
}

fn installVendorWeakCutoffGrid(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *OpticsPrepare.PreparedOpticalState,
    weak_cutoff_grid: ?*WeakCutoffGridCache,
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

    if (weak_cutoff_grid) |grid| {
        if (grid.valid()) {
            try installCutoffGridOnPreparedLineLists(allocator, prepared, grid.*);
            return;
        }
    }

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

    if (weak_cutoff_grid) |grid| {
        try grid.replaceFromSupport(allocator, support);
        try installCutoffGridOnPreparedLineLists(allocator, prepared, grid.*);
        return;
    }

    if (prepared.spectroscopy_lines) |*line_list| {
        try installCutoffGridOnLineList(allocator, line_list, support);
    }
    for (prepared.line_absorbers) |*line_absorber| {
        try installCutoffGridOnLineList(allocator, &line_absorber.line_list, support);
    }
}

fn installCutoffGridOnPreparedLineLists(
    allocator: Allocator,
    prepared: *OpticsPrepare.PreparedOpticalState,
    grid: WeakCutoffGridCache,
) !void {
    if (!grid.valid()) return error.DisamarKernelRealizationFailed;
    if (prepared.spectroscopy_lines) |*line_list| {
        try installCutoffGridOnLineListFromGrid(allocator, line_list, grid);
    }
    for (prepared.line_absorbers) |*line_absorber| {
        try installCutoffGridOnLineListFromGrid(allocator, &line_absorber.line_list, grid);
    }
}

fn installCutoffGridOnLineList(
    allocator: Allocator,
    line_list: *ReferenceDataModel.SpectroscopyLineList,
    support_wavelengths_nm: []const f64,
) !void {
    if (line_list.runtime_controls.cutoff_cm1 == null) return;
    const owned_support = try allocator.dupe(f64, support_wavelengths_nm);
    errdefer allocator.free(owned_support);
    const owned_support_wavenumbers = try allocator.alloc(f64, support_wavelengths_nm.len);
    errdefer allocator.free(owned_support_wavenumbers);
    for (support_wavelengths_nm, owned_support_wavenumbers) |wavelength_nm, *wavenumber_cm1| {
        wavenumber_cm1.* = 1.0e7 / @max(wavelength_nm, 1.0e-9);
    }
    if (line_list.runtime_controls.cutoff_grid_wavelengths_nm.len != 0) {
        allocator.free(line_list.runtime_controls.cutoff_grid_wavelengths_nm);
    }
    if (line_list.runtime_controls.cutoff_grid_wavenumbers_cm1.len != 0) {
        allocator.free(line_list.runtime_controls.cutoff_grid_wavenumbers_cm1);
    }
    line_list.runtime_controls.cutoff_grid_wavelengths_nm = owned_support;
    line_list.runtime_controls.cutoff_grid_wavenumbers_cm1 = owned_support_wavenumbers;
}

fn installCutoffGridOnLineListFromGrid(
    allocator: Allocator,
    line_list: *ReferenceDataModel.SpectroscopyLineList,
    grid: WeakCutoffGridCache,
) !void {
    if (line_list.runtime_controls.cutoff_cm1 == null) return;
    const owned_support = try allocator.dupe(f64, grid.wavelengths_nm);
    errdefer allocator.free(owned_support);
    const owned_support_wavenumbers = try allocator.dupe(f64, grid.wavenumbers_cm1);
    errdefer allocator.free(owned_support_wavenumbers);
    if (line_list.runtime_controls.cutoff_grid_wavelengths_nm.len != 0) {
        allocator.free(line_list.runtime_controls.cutoff_grid_wavelengths_nm);
    }
    if (line_list.runtime_controls.cutoff_grid_wavenumbers_cm1.len != 0) {
        allocator.free(line_list.runtime_controls.cutoff_grid_wavenumbers_cm1);
    }
    line_list.runtime_controls.cutoff_grid_wavelengths_nm = owned_support;
    line_list.runtime_controls.cutoff_grid_wavenumbers_cm1 = owned_support_wavenumbers;
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
    // layout(64-bit):
    //   anonymous optional payload: size 16 B, align 8 B; padding 0 B (0 bits)
    //   footprint: per present payload = 16 B (0.016 KiB)
    var radiance_start: instrument_types.IntegrationKernel = undefined;
    var radiance_end: instrument_types.IntegrationKernel = undefined;
    var irradiance_start: instrument_types.IntegrationKernel = undefined;
    var irradiance_end: instrument_types.IntegrationKernel = undefined;

    try @import("../../forward_model/implementations/instrument/integration.zig").integrationForWavelengthChecked(
        scene,
        prepared,
        .radiance,
        scene.spectral_grid.start_nm,
        &radiance_start,
    );
    try @import("../../forward_model/implementations/instrument/integration.zig").integrationForWavelengthChecked(
        scene,
        prepared,
        .radiance,
        scene.spectral_grid.end_nm,
        &radiance_end,
    );
    try @import("../../forward_model/implementations/instrument/integration.zig").integrationForWavelengthChecked(
        scene,
        prepared,
        .irradiance,
        scene.spectral_grid.start_nm,
        &irradiance_start,
    );
    try @import("../../forward_model/implementations/instrument/integration.zig").integrationForWavelengthChecked(
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
    if (try fixed_asset_cache.loadLineList(allocator, spec)) |cached| {
        return cached;
    }

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
    try fixed_asset_cache.storeLineList(spec, line_list);
    return line_list;
}
