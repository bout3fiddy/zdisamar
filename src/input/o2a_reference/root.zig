const std = @import("std");
const AerosolModel = @import("../Aerosol.zig");
const AtmosphereModel = @import("../Atmosphere.zig");
const InstrumentGrid = @import("../../forward_model/instrument_grid/root.zig");
const Jacobian = @import("../../forward_model/jacobian/root.zig");
const metrics = @import("metrics.zig");
const reference_types = @import("types.zig");
const runtime = @import("run.zig");

const Allocator = std.mem.Allocator;

// root.zig ---------------------------------------------------------------------------------------------------|
// Public O2 A reference-case facade used by Zig tests, C/Python bindings, and research harnesses.             |
//                                                                                                             |
// called by                                                                                                   |
//   src/root.zig exposes this namespace as zdisamar.o2a and forwards public O2 A helpers                      |
//   src/api/c.zig validates inputs, prepares handles, runs spectra/Jacobians, and gates retrieval support     |
//   optimal_estimation/retrieval.zig consumes prepared O2 A cases for retrieval paths                         |
//   trace, telemetry, and perturbation CLIs use the default and benchmark validation cases                    |
//                                                                                                             |
// main paths                                                                                                  |
//   defaultInput / benchmarkJacobianInput build deterministic DISAMAR-reference O2 A cases                    |
//   parseInputJson / renderInputJson validate and preserve the public JSON shape                              |
//   prepareO2A converts the resolved case into scene, reference data, RTM config, and prepared optics         |
//   runO2A* executes the instrument-grid product with optional caller-owned session storage and Jacobian rows |
//                                                                                                             |
// boundary shape                                                                                              |
//   This file is a facade over metrics.zig, run.zig, and instrument-grid execution. It owns validation and    |
//   stable defaults; detailed asset loading, scene construction, and metric comparison stay in child modules. |
//                                                                                                             |
// memory                                                                                                      |
//   Functions return owned prepared cases or output products through the caller allocator. This module owns   |
//   no retained cache; fixed-asset caching lives in fixed_asset_cache.zig.                                    |
// ------------------------------------------------------------------------------------------------------------|

pub const ReferenceData = metrics.ReferenceData;
pub const ReferenceSample = metrics.ReferenceSample;
pub const O2AInput = reference_types.ResolvedVendorO2ACase;
pub const PreparedO2A = metrics.VendorO2APreparedCase;
pub const SessionStorage = InstrumentGrid.ProductStorage;
pub const Output = InstrumentGrid.InstrumentGridProduct;
pub const AerosolProfileLayer = AerosolModel.ProfileLayer;
pub const max_aerosol_profile_layers = AerosolModel.max_profile_layers;
pub const ReflectanceCase = metrics.VendorO2AReflectanceCase;
pub const ComparisonMetrics = metrics.ComparisonMetrics;
pub const TrendTolerances = metrics.TrendTolerances;
pub const TrendState = metrics.TrendState;
pub const AssessmentVerdict = metrics.AssessmentVerdict;
pub const AssessmentOutcome = metrics.AssessmentOutcome;
pub const RangeExtremum = metrics.RangeExtremum;

pub const runResolvedVendorO2AReflectanceCase = metrics.runResolvedVendorO2AReflectanceCase;
pub const prepareResolvedVendorO2ACase = metrics.prepareResolvedVendorO2ACase;
pub const meanVectorInRange = metrics.meanVectorInRange;
pub const minVectorInRange = metrics.minVectorInRange;
pub const maxVectorInRange = metrics.maxVectorInRange;
pub const meanReferenceInRange = metrics.meanReferenceInRange;
pub const minReferenceInRange = metrics.minReferenceInRange;
pub const maxReferenceInRange = metrics.maxReferenceInRange;
pub const interpolateVector = metrics.interpolateVector;
pub const compareLowerIsBetter = metrics.compareLowerIsBetter;
pub const compareHigherIsBetter = metrics.compareHigherIsBetter;
pub const compareAbsoluteCeiling = metrics.compareAbsoluteCeiling;
pub const computeComparisonMetrics = metrics.computeComparisonMetrics;
pub const assessAgainstBaseline = metrics.assessAgainstBaseline;
pub const loadResolvedO2ASpectroscopyLineList = metrics.loadResolvedO2ASpectroscopyLineList;

const default_intervals = [_]AtmosphereModel.VerticalInterval{
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

const benchmark_jacobian_intervals = [_]AtmosphereModel.VerticalInterval{
    .{
        .index_1based = 1,
        .top_pressure_hpa = 0.3,
        .bottom_pressure_hpa = 875.0,
        .altitude_divisions = 16,
    },
    .{
        .index_1based = 2,
        .top_pressure_hpa = 875.0,
        .bottom_pressure_hpa = 925.0,
        .altitude_divisions = 4,
    },
    .{
        .index_1based = 3,
        .top_pressure_hpa = 925.0,
        .bottom_pressure_hpa = 1013.25,
        .altitude_divisions = 6,
    },
};

const default_isotopes = [_]u8{ 1, 2, 3 };

pub fn defaultInput() O2AInput {
    return .{
        .metadata = .{
            .id = "disamar_reference_o2a",
            .storage = "disamar-reference-o2a",
            .description = "DISAMAR O2 A reference case for Python and validation.",
        },
        .plan = .{
            .derivative_mode = .none,
        },
        .inputs = .{
            .atmosphere_profile = asset(
                "atmosphere_profile",
                "data/reference_data/climatologies/vendor_config_o2a_profile.csv",
                "profile_csv",
            ),
            .vendor_reference_csv = asset(
                "vendor_reference_csv",
                "data/reference_data/validation/o2a_with_cia_disamar_reference.csv",
                "disamar_o2a_reference_csv",
            ),
            .raw_solar_reference = asset(
                "raw_solar_reference",
                "data/reference_data/solar/o2a_solar_reference_753_778.csv",
                "solar_reference_csv",
            ),
            .airmass_factor_lut = asset(
                "airmass_factor_lut",
                "data/reference_data/luts/airmass_factor_nadir_demo.csv",
                "csv",
            ),
        },
        .scene_id = "o2a_disamar_reference_python",
        .spectral_grid = .{
            .start_nm = 755.0,
            .end_nm = 776.0,
            .sample_count = 701,
        },
        .layer_count = 3,
        .sublayer_divisions = 4,
        .surface_pressure_hpa = 1013.25,
        .fit_interval_index_1based = 2,
        .intervals = default_intervals[0..],
        .surface_albedo = 0.2,
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 30.0,
            .relative_azimuth_deg = 120.0,
        },
        .aerosol = .{
            .optical_depth = 0.3,
            .single_scatter_albedo = 1.0,
            .asymmetry_factor = 0.7,
            .angstrom_exponent = 0.0,
            .reference_wavelength_nm = 550.0,
            .placement = .{
                .semantics = .explicit_interval_bounds,
                .interval_index_1based = 2,
                .top_pressure_hpa = 500.0,
                .bottom_pressure_hpa = 520.0,
            },
        },
        .observation = .{
            .instrument_name = "disamar-o2a-compare",
            .sampling = .native,
            .instrument_line_fwhm_nm = 0.38,
            .builtin_line_shape = .flat_top_n4,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
            .adaptive_reference_grid = .{
                .points_per_fwhm = 20,
                .strong_line_min_divisions = 8,
                .strong_line_max_divisions = 40,
            },
            .solar_reference_asset_id = "raw_solar_reference",
        },
        .o2 = .{
            .line_list_asset = asset(
                "o2_hitran",
                "data/reference_data/cross_sections/o2a_hitran_07_hit08_tropomi.par",
                "hitran_par_o2a",
            ),
            .line_mixing_asset = asset(
                "o2_line_mixing",
                "data/reference_data/cross_sections/o2a_lisa_rmf.dat",
                "lisa_rmf",
            ),
            .strong_lines_asset = asset(
                "o2_strong_lines",
                "data/reference_data/cross_sections/o2a_lisa_sdf.dat",
                "lisa_sdf",
            ),
            .line_mixing_factor = 1.0,
            .isotopes_sim = default_isotopes[0..],
            .threshold_line_sim = 3.0e-5,
            .cutoff_sim_cm1 = 200.0,
        },
        .o2o2 = .{
            .enabled = true,
            .cia_asset = asset(
                "o2o2_cia",
                "data/reference_data/cross_sections/o2o2_bira_o2a.dat",
                "bira_cia",
            ),
        },
        .rtm_controls = .{
            .scattering = .multiple,
            .n_streams = 20,
            .performance_thresholds = reference_types.RadiativeTransferPerformanceThresholds.o2a_default,
            .use_spherical_correction = true,
            .integrate_source_function = true,
            .renorm_phase_function = true,
        },
    };
}

pub fn benchmarkJacobianInput() O2AInput {
    var input = defaultInput();
    input.metadata = .{
        .id = "disamar_reference_o2a_jacobian_validation",
        .storage = "disamar-reference-o2a-jacobian-validation",
        .description = "Hardcoded DISAMAR O2 A Jacobian validation case.",
    };
    input.inputs.raw_solar_reference = asset(
        "raw_solar_reference",
        "data/reference_data/solar/o2a_solar_reference_chance_kurucz_2010_753_778.csv",
        "solar_reference_csv",
    );
    input.scene_id = "o2a_disamar_reference_jacobian_validation";
    input.spectral_grid = .{
        .start_nm = 758.0,
        .end_nm = 770.0,
        .sample_count = 301,
    };
    input.intervals = benchmark_jacobian_intervals[0..];
    input.geometry.viewing_zenith_deg = 0.0;
    input.geometry.relative_azimuth_deg = 0.0;
    input.aerosol.placement.top_pressure_hpa = 875.0;
    input.aerosol.placement.bottom_pressure_hpa = 925.0;
    input.observation.instrument_name = "disamar-o2a-jacobian-validation";
    input.observation.instrument_line_fwhm_nm = 0.12;
    input.observation.high_resolution_half_span_nm = 0.36;
    input.observation.adaptive_reference_grid.points_per_fwhm = 30;
    input.observation.adaptive_reference_grid.strong_line_min_divisions = 6;
    input.observation.adaptive_reference_grid.strong_line_max_divisions = 30;
    input.rtm_controls.performance_thresholds.phase_function_truncation_threshold = 1.0e-6;
    return input;
}

pub fn parseInputJson(allocator: Allocator, json: []const u8) !std.json.Parsed(O2AInput) {
    var parsed = try std.json.parseFromSlice(O2AInput, allocator, json, .{
        .ignore_unknown_fields = false,
    });
    errdefer parsed.deinit();
    try validateInput(&parsed.value);
    return parsed;
}

pub fn renderInputJson(allocator: Allocator, input: *const O2AInput) ![]u8 {
    const isotopes_u32 = try allocator.alloc(u32, input.o2.isotopes_sim.len);
    defer allocator.free(isotopes_u32);
    for (input.o2.isotopes_sim, 0..) |value, index| isotopes_u32[index] = value;

    const view = .{
        .metadata = input.metadata,
        .plan = input.plan,
        .inputs = input.inputs,
        .scene_id = input.scene_id,
        .spectral_grid = input.spectral_grid,
        .layer_count = input.layer_count,
        .sublayer_divisions = input.sublayer_divisions,
        .surface_pressure_hpa = input.surface_pressure_hpa,
        .fit_interval_index_1based = input.fit_interval_index_1based,
        .intervals = input.intervals,
        .surface_albedo = input.surface_albedo,
        .geometry = input.geometry,
        .aerosol = input.aerosol,
        .observation = input.observation,
        .o2 = .{
            .line_list_asset = input.o2.line_list_asset,
            .line_mixing_asset = input.o2.line_mixing_asset,
            .strong_lines_asset = input.o2.strong_lines_asset,
            .line_mixing_factor = input.o2.line_mixing_factor,
            .isotopes_sim = isotopes_u32,
            .threshold_line_sim = input.o2.threshold_line_sim,
            .cutoff_sim_cm1 = input.o2.cutoff_sim_cm1,
        },
        .o2o2 = input.o2o2,
        .rtm_controls = input.rtm_controls,
    };
    return std.fmt.allocPrint(
        allocator,
        "{f}\n",
        .{std.json.fmt(view, .{ .whitespace = .indent_2 })},
    );
}

pub fn renderDefaultInputJson(allocator: Allocator) ![]u8 {
    const input = defaultInput();
    return renderInputJson(allocator, &input);
}

pub fn prepareO2A(allocator: Allocator, input: *const O2AInput) !PreparedO2A {
    try validateInput(input);
    return metrics.prepareResolvedVendorO2ACase(allocator, input);
}

pub fn runO2A(allocator: Allocator, prepared: *const PreparedO2A) !Output {
    return InstrumentGrid.simulateProduct(
        allocator,
        &prepared.scene,
        prepared.rtm_config,
        &prepared.prepared,
    );
}

pub fn runO2AWithSessionStorage(
    allocator: Allocator,
    storage: *SessionStorage,
    prepared: *const PreparedO2A,
) !Output {
    const view = try InstrumentGrid.simulateProductWithWorkspace(
        allocator,
        storage,
        &prepared.scene,
        prepared.rtm_config,
        &prepared.prepared,
    );
    return view.toOwned(allocator);
}

pub fn runO2AWithSessionStorageJacobianStates(
    allocator: Allocator,
    storage: *SessionStorage,
    prepared: *const PreparedO2A,
    output_states: []const Jacobian.State,
) !Output {
    const view = try InstrumentGrid.simulateProductWithWorkspace(
        allocator,
        storage,
        &prepared.scene,
        prepared.rtm_config,
        &prepared.prepared,
    );
    return view.toOwnedWithJacobianStates(allocator, output_states);
}

pub fn warmO2ASessionStorage(
    allocator: Allocator,
    storage: *SessionStorage,
    prepared: *const PreparedO2A,
) !void {
    return InstrumentGrid.warmProductWorkspace(
        allocator,
        storage,
        &prepared.scene,
        prepared.rtm_config,
        &prepared.prepared,
    );
}

pub fn validateInput(input: *const O2AInput) !void {
    if (input.spectral_grid.sample_count < 2) return error.InvalidSpectralGrid;
    if (!(input.spectral_grid.end_nm > input.spectral_grid.start_nm)) return error.InvalidSpectralGrid;

    if (input.observation.measured_wavelengths_nm.len != 0) {
        if (input.observation.measured_wavelengths_nm.len != input.spectral_grid.sample_count) {
            return error.InvalidSpectralGrid;
        }

        var previous: ?f64 = null;
        for (input.observation.measured_wavelengths_nm) |wavelength_nm| {
            if (!std.math.isFinite(wavelength_nm)) return error.InvalidSpectralGrid;

            if (previous) |earlier| {
                if (wavelength_nm <= earlier) return error.InvalidSpectralGrid;
            }
            previous = wavelength_nm;
        }
    }
    if (input.layer_count == 0 or input.sublayer_divisions == 0) return error.InvalidAtmosphere;
    if (input.intervals.len == 0) return error.InvalidAtmosphere;

    for (input.intervals) |interval| try interval.validate();
    try validateAerosol(input);
    try input.plan.validate();
    try input.rtm_controls.validate();

    try requireAsset(input.inputs.atmosphere_profile);
    try requireAsset(input.inputs.vendor_reference_csv);
    try requireAsset(input.inputs.raw_solar_reference);
    try requireAsset(input.inputs.airmass_factor_lut);

    try requireAsset(input.o2.line_list_asset);
    try requireAsset(input.o2.line_mixing_asset);
    try requireAsset(input.o2.strong_lines_asset);
    if (input.o2o2.enabled) {
        try requireAsset(input.o2o2.cia_asset orelse return error.MissingCollisionInducedAbsorptionAsset);
    }
}

pub fn hasMultiLayerAerosolProfile(input: *const O2AInput) bool {
    return input.aerosol.profile.len > 1;
}

pub fn requireRetrievalCompatibleAerosol(input: *const O2AInput) !void {
    if (hasMultiLayerAerosolProfile(input)) return error.MultiLayerAerosolProfileUnsupportedForRetrieval;
}

fn validateAerosol(input: *const O2AInput) !void {
    try input.aerosol.placement.validate();
    if (input.aerosol.profile.len > max_aerosol_profile_layers) return error.InvalidAerosolProfile;
    for (input.aerosol.profile) |layer| try layer.validate();
}

fn requireAsset(value: reference_types.ExternalAsset) !void {
    if (value.id.len == 0 or value.path.len == 0 or value.format.len == 0) return error.InvalidReferenceAsset;
}

fn asset(id: []const u8, path: []const u8, format: []const u8) reference_types.ExternalAsset {
    return .{
        .id = id,
        .path = path,
        .format = format,
    };
}
