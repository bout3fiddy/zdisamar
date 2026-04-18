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
const spectroscopy_support = @import("../../model/reference/spectroscopy/support.zig");
const bundled_optics = @import("../../data/bundled/assets.zig");
const providers = @import("../providers/root.zig");
const reference_assets = @import("../../adapters/ingest/reference_assets.zig");
const transport_common = @import("../../kernels/transport/common.zig");
const parity_types = @import("vendor_parity_types.zig");

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

    return .{
        .profile = profile,
        .cross_sections = cross_sections,
        .line_list = line_list,
        .cia_table = cia_table,
        .lut = lut,
        .reference = reference,
    };
}

/// Purpose:
///   Materialize the resolved parity scene into the canonical typed `Scene`.
pub fn buildResolvedVendorO2AScene(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
    reference: []const ReferenceSample,
) !Scene {
    const reference_wavelengths = try allocator.alloc(f64, reference.len);
    errdefer allocator.free(reference_wavelengths);
    const reference_irradiance = try allocator.alloc(f64, reference.len);
    errdefer allocator.free(reference_irradiance);
    for (reference, 0..) |sample, index| {
        reference_wavelengths[index] = sample.wavelength_nm;
        reference_irradiance[index] = sample.irradiance;
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
                .wavelengths_nm = reference_wavelengths,
                .irradiance = reference_irradiance,
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

    var scene = try buildResolvedVendorO2AScene(allocator, resolved, inputs.reference);
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

    const route = try prepareResolvedVendorO2ARoute(&scene, resolved.rtm_controls);
    if (phase_profile_out) |profile| profile.plan_preparation_ns = if (timer) |*owned| owned.lap() else 0;

    return .{
        .reference = reference,
        .scene = scene,
        .route = route,
        .prepared = prepared,
    };
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

    try filterVendorStrongLineSidecars(
        allocator,
        &line_list,
        &strong_lines,
        &relaxation_matrix,
    );
    try line_list.attachStrongLineSidecars(allocator, strong_lines, relaxation_matrix);
    line_list.preserve_anchor_weak_lines = true;
    return line_list;
}

fn filterVendorStrongLineSidecars(
    allocator: Allocator,
    line_list: *const ReferenceDataModel.SpectroscopyLineList,
    strong_lines: *ReferenceDataModel.SpectroscopyStrongLineSet,
    relaxation_matrix: *ReferenceDataModel.RelaxationMatrix,
) !void {
    // DECISION:
    //   The retained vendor-parity assets keep the full vendor strong-line
    //   sidecar tables even when the bundled line list is a wavelength subset.
    //   Trim the sidecars to anchors present in the loaded line list before
    //   attaching them so the retained O2A helper preserves the committed
    //   subset semantics exercised by the vendor smoke tests.
    var matched_indices = std.ArrayList(usize).empty;
    defer matched_indices.deinit(allocator);

    for (strong_lines.lines, 0..) |strong_line, strong_index| {
        if (hasVendorStrongLineAnchor(line_list.*, strong_line)) {
            try matched_indices.append(allocator, strong_index);
        }
    }

    if (matched_indices.items.len == 0) return error.UnmatchedStrongLineSidecar;
    if (matched_indices.items.len == strong_lines.lines.len) return;

    const retained_count = matched_indices.items.len;
    const retained_lines = try allocator.alloc(ReferenceDataModel.SpectroscopyStrongLine, retained_count);
    errdefer allocator.free(retained_lines);
    const retained_wt0 = try allocator.alloc(f64, retained_count * retained_count);
    errdefer allocator.free(retained_wt0);
    const retained_bw = try allocator.alloc(f64, retained_count * retained_count);
    errdefer allocator.free(retained_bw);

    for (matched_indices.items, 0..) |old_row_index, new_row_index| {
        retained_lines[new_row_index] = strong_lines.lines[old_row_index];
        for (matched_indices.items, 0..) |old_col_index, new_col_index| {
            const flat_index = new_row_index * retained_count + new_col_index;
            retained_wt0[flat_index] = relaxation_matrix.weightAt(old_row_index, old_col_index);
            retained_bw[flat_index] = relaxation_matrix.temperatureExponentAt(old_row_index, old_col_index);
        }
    }

    strong_lines.deinit(allocator);
    strong_lines.* = .{ .lines = retained_lines };
    relaxation_matrix.deinit(allocator);
    relaxation_matrix.* = .{
        .line_count = retained_count,
        .wt0 = retained_wt0,
        .bw = retained_bw,
    };
}

fn hasVendorStrongLineAnchor(
    line_list: ReferenceDataModel.SpectroscopyLineList,
    strong_line: ReferenceDataModel.SpectroscopyStrongLine,
) bool {
    for (line_list.lines) |line| {
        if (!spectroscopy_support.isVendorO2AStrongCandidate(line)) continue;
        const tolerance_nm = @max(line_list.strong_line_tolerance_nm, strong_line.air_half_width_nm * 4.0);
        if (@abs(line.center_wavelength_nm - strong_line.center_wavelength_nm) <= tolerance_nm) {
            return true;
        }
    }
    return false;
}

test "vendor parity loader trims unmatched strong-line sidecars to the loaded subset" {
    var line_list = ReferenceDataModel.SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(ReferenceDataModel.SpectroscopyLine, &.{
            .{
                .gas_index = 7,
                .isotope_number = 1,
                .center_wavelength_nm = 771.3015,
                .line_strength_cm2_per_molecule = 1.0e-20,
                .air_half_width_nm = 0.0015,
                .temperature_exponent = 0.63,
                .lower_state_energy_cm1 = 1800.0,
                .pressure_shift_nm = 0.0,
                .line_mixing_coefficient = 0.0,
                .branch_ic1 = 5,
                .branch_ic2 = 1,
                .rotational_nf = 35,
            },
        }),
    };
    defer line_list.deinit(std.testing.allocator);

    var strong_lines = ReferenceDataModel.SpectroscopyStrongLineSet{
        .lines = try std.testing.allocator.dupe(ReferenceDataModel.SpectroscopyStrongLine, &.{
            .{
                .center_wavenumber_cm1 = 12965.1079,
                .center_wavelength_nm = 771.3015,
                .population_t0 = 5.10e-05,
                .dipole_ratio = 0.712,
                .dipole_t0 = 5.80e-04,
                .lower_state_energy_cm1 = 1804.8773,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -35,
            },
            .{
                .center_wavenumber_cm1 = 12966.8087,
                .center_wavelength_nm = 771.2004,
                .population_t0 = 4.99e-05,
                .dipole_ratio = -0.702,
                .dipole_t0 = -5.78e-04,
                .lower_state_energy_cm1 = 1803.1765,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -34,
            },
        }),
    };
    defer strong_lines.deinit(std.testing.allocator);

    var relaxation_matrix = ReferenceDataModel.RelaxationMatrix{
        .line_count = 2,
        .wt0 = try std.testing.allocator.dupe(f64, &.{
            0.02764486,
            0.0004338554,
            0.0004338554,
            0.02655312,
        }),
        .bw = try std.testing.allocator.dupe(f64, &.{
            0.629999646133,
            1.169364903905,
            1.169364903905,
            0.629999646133,
        }),
    };
    defer relaxation_matrix.deinit(std.testing.allocator);

    try filterVendorStrongLineSidecars(std.testing.allocator, &line_list, &strong_lines, &relaxation_matrix);
    try std.testing.expectEqual(@as(usize, 1), strong_lines.lines.len);
    try std.testing.expectApproxEqAbs(@as(f64, 771.3015), strong_lines.lines[0].center_wavelength_nm, 1.0e-9);
    try std.testing.expectEqual(@as(usize, 1), relaxation_matrix.line_count);
    try std.testing.expectApproxEqAbs(@as(f64, 0.02764486), relaxation_matrix.weightAt(0, 0), 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.629999646133), relaxation_matrix.temperatureExponentAt(0, 0), 1.0e-12);
}
