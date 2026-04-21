//! Purpose:
//!   Own the resolved O2A vendor-parity runtime contract shared by YAML-driven
//!   execution and the retained parity support helpers.
//!
//! Physics:
//!   This file hydrates the retained O2 A-band forcing case: climatology,
//!   line-by-line O2, optional O2-O2 CIA, aerosol placement, instrument
//!   sampling, and the scalar multiple-scattering RTM controls used for the
//!   current parity lane.
//!
//! Vendor:
//!   `readConfigFileModule::INSTRUMENT/O2/O2-O2/SURFACE/ATMOSPHERIC_INTERVALS/AEROSOL`
//!   and `verifyConfigFileModule::interval-grid and fit-interval checks`
//!
//! Design:
//!   The resolved case stays typed and explicit. Adapters compile YAML or other
//!   external control surfaces into this struct, and runtime code materializes
//!   the actual `Scene` and reference assets from that typed contract.
//!
//! Invariants:
//!   All referenced assets must exist and match the declared format, explicit
//!   interval grids must tile the active atmosphere, and no enabled parity
//!   feature may be silently dropped.
//!
//! Validation:
//!   The YAML adapter tests exercise the resolved-contract mapping, while the
//!   vendor assessment and oracle tests execute the resulting `Scene` through
//!   the retained O2A reflectance path.

const std = @import("std");
const AbsorberModel = @import("../../model/Absorber.zig");
const AtmosphereModel = @import("../../model/Atmosphere.zig");
const InstrumentModel = @import("../../model/Instrument.zig");
const Instrument = InstrumentModel.Instrument;
const MeasurementSpace = @import("../../kernels/transport/measurement.zig");
const OpticsPrepare = @import("../../kernels/optics/preparation.zig");
const ObservationModel = @import("../../model/ObservationModel.zig");
const ReferenceDataModel = @import("../../model/ReferenceData.zig");
const Scene = @import("../../model/Scene.zig").Scene;
const SpectralGrid = @import("../../model/Spectrum.zig").SpectralGrid;
const bundled_optics = @import("../../data/bundled/assets.zig");
const providers = @import("../providers/root.zig");
const reference_assets = @import("../../adapters/ingest/reference_assets.zig");
const transport_common = @import("../../kernels/transport/common.zig");
const parity_types = @import("vendor_parity_types.zig");
const instrument_types = @import("../providers/instrument/types.zig");

const Allocator = std.mem.Allocator;
pub const AbsorberSpecies = parity_types.AbsorberSpecies;
pub const Route = parity_types.Route;
pub const RtmControls = parity_types.RtmControls;
pub const PreparationPhaseProfile = parity_types.PreparationPhaseProfile;
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

/// Purpose:
///   Load the resolved external assets required by the retained vendor-parity case.
///
/// Decisions:
///   The loader stays asset-oriented even for the narrow first YAML cut so the
///   config references data files rather than embedding scientific payloads.
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
        .cross_sections = cross_sections,
        .line_list = line_list,
        .cia_table = cia_table,
        .lut = lut,
        .reference = reference,
        .raw_solar_spectrum = raw_solar_spectrum,
    };
}

/// Purpose:
///   Materialize the resolved parity scene into the canonical typed `Scene`.
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
    rtm_controls: RtmControls,
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
    var prepared_case = try prepareResolvedVendorO2ATraceCase(allocator, resolved, null);
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

pub fn prepareResolvedVendorO2ATraceCase(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
    phase_profile_out: ?*PreparationPhaseProfile,
) !struct {
    reference: []ReferenceSample,
    scene: Scene,
    route: Route,
    prepared: OpticsPrepare.PreparedOpticalState,
} {
    if (phase_profile_out) |profile| profile.* = .{
        .input_loading_ns = 0,
        .scene_assembly_ns = 0,
        .optics_preparation_ns = 0,
        .plan_preparation_ns = 0,
    };
    var timer = if (phase_profile_out != null)
        std.time.Timer.start() catch unreachable
    else
        null;

    var inputs = try loadResolvedVendorO2AInputs(allocator, resolved);
    defer inputs.deinit(allocator);
    if (phase_profile_out) |profile| profile.input_loading_ns = if (timer) |*owned| owned.lap() else 0;

    var scene = try buildResolvedVendorO2AScene(allocator, resolved, inputs.raw_solar_spectrum);
    errdefer scene.deinitOwned(allocator);
    if (phase_profile_out) |profile| profile.scene_assembly_ns = if (timer) |*owned| owned.lap() else 0;

    const reference = inputs.reference;
    inputs.reference = inputs.reference[0..0];
    errdefer allocator.free(reference);

    var prepared = try OpticsPrepare.prepare(allocator, &scene, .{
        .profile = &inputs.profile,
        .cross_sections = &inputs.cross_sections,
        .collision_induced_absorption = if (inputs.cia_table) |*table| table else null,
        .spectroscopy_lines = &inputs.line_list,
        .lut = &inputs.lut,
    });
    errdefer prepared.deinit(allocator);
    if (phase_profile_out) |profile| profile.optics_preparation_ns = if (timer) |*owned| owned.lap() else 0;

    try rewindowParitySolarSupportToMeasurementKernel(allocator, &scene, &prepared);

    const route = try prepareResolvedVendorO2ARoute(&scene, resolved.rtm_controls);
    if (phase_profile_out) |profile| profile.plan_preparation_ns = if (timer) |*owned| owned.lap() else 0;

    return .{
        .reference = reference,
        .scene = scene,
        .route = route,
        .prepared = prepared,
    };
}

/// Purpose:
///   Re-window the raw solar carrier to the shared measurement HR support used
///   by the vendor-faithful parity lane before spline interpolation is prepared.
///
/// Physics:
///   DISAMAR crops the raw solar file to the active `wavelHRSimS` span and
///   then builds the spline on that cropped support. Keeping extra file rows
///   outside the active HR band perturbs the cubic spline very slightly, which
///   is enough to leave `1e4-1e5` irradiance residuals after convolution.
///
/// Vendor:
///   `readModule::getHRSolarIrradiance`
///
/// Decisions:
///   The Zig runtime derives the vendor HR span from the realized radiance and
///   irradiance kernels at the first and last nominal wavelengths of the active
///   spectral grid, requires those parity kernels to agree, and then rebuilds
///   the owned solar carrier on just that inclusive range.
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
    errdefer allocator.free(retained_wavelengths_nm);
    const retained_irradiance = try allocator.alloc(f64, retained_count);
    errdefer allocator.free(retained_irradiance);

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
    try scene.observation_model.operational_solar_spectrum.prepareInterpolation(allocator);
}

fn sharedParityMeasurementSupport(
    scene: *const Scene,
    prepared: *const OpticsPrepare.PreparedOpticalState,
) !?struct { start_nm: f64, end_nm: f64 } {
    const bindings = providers.exact();
    var radiance_start: instrument_types.IntegrationKernel = undefined;
    var radiance_end: instrument_types.IntegrationKernel = undefined;
    var irradiance_start: instrument_types.IntegrationKernel = undefined;
    var irradiance_end: instrument_types.IntegrationKernel = undefined;

    bindings.instrument.integrationForWavelength(scene, prepared, .radiance, scene.spectral_grid.start_nm, &radiance_start);
    bindings.instrument.integrationForWavelength(scene, prepared, .radiance, scene.spectral_grid.end_nm, &radiance_end);
    bindings.instrument.integrationForWavelength(scene, prepared, .irradiance, scene.spectral_grid.start_nm, &irradiance_start);
    bindings.instrument.integrationForWavelength(scene, prepared, .irradiance, scene.spectral_grid.end_nm, &irradiance_end);

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
