const std = @import("std");
const AerosolModel = @import("../Aerosol.zig");
const AtmosphereModel = @import("../Atmosphere.zig");
const InstrumentGrid = @import("../../forward_model/instrument_grid/root.zig");
const OpticsPrepare = @import("../../forward_model/optical_properties/root.zig");
const Scene = @import("../Scene.zig").Scene;
const implementations = @import("../../forward_model/implementations/root.zig");
const Jacobian = @import("../../forward_model/jacobian/root.zig");
const metrics = @import("metrics.zig");
const reference_types = @import("types.zig");
const runtime = @import("run.zig");

const Allocator = std.mem.Allocator;

pub const ReferenceData = metrics.ReferenceData;
pub const ReferenceSample = metrics.ReferenceSample;
pub const O2AInput = reference_types.ResolvedVendorO2ACase;
pub const PreparedO2A = metrics.VendorO2APreparedCase;
pub const SessionStorage = InstrumentGrid.ProductStorage;
pub const Output = InstrumentGrid.InstrumentGridProduct;
pub const AerosolProfileLayer = AerosolModel.ProfileLayer;
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

const default_isotopes = [_]u8{ 1, 2, 3 };

const ProfilePreparationSession = struct {
    borrowed: OpticsPrepare.BorrowedProfilePreparation = .{},
    captured: bool = false,

    fn borrowedPreparation(self: *const ProfilePreparationSession) ?*const OpticsPrepare.BorrowedProfilePreparation {
        if (!self.captured) return null;
        return &self.borrowed;
    }

    fn captureFromPrepared(self: *ProfilePreparationSession, prepared: *OpticsPrepare.PreparedOpticalState) void {
        if (self.captured or prepared.spectroscopy_profile_altitudes_km.len == 0) return;
        if (!prepared.owns_spectroscopy_profile_arrays) return;

        self.borrowed.altitudes_km = prepared.spectroscopy_profile_altitudes_km;
        self.borrowed.pressures_hpa = prepared.spectroscopy_profile_pressures_hpa;
        self.borrowed.temperatures_k = prepared.spectroscopy_profile_temperatures_k;
        prepared.spectroscopy_profile_altitudes_km = &.{};
        prepared.spectroscopy_profile_pressures_hpa = &.{};
        prepared.spectroscopy_profile_temperatures_k = &.{};
        prepared.owns_spectroscopy_profile_arrays = false;

        if (prepared.owns_spectroscopy_profile_strong_line_states) {
            self.borrowed.strong_line_states = prepared.spectroscopy_profile_strong_line_states;
            prepared.spectroscopy_profile_strong_line_states = null;
            prepared.owns_spectroscopy_profile_strong_line_states = false;
        }
        if (prepared.owns_spectroscopy_profile_weak_line_states) {
            self.borrowed.weak_line_states = prepared.spectroscopy_profile_weak_line_states;
            prepared.spectroscopy_profile_weak_line_states = null;
            prepared.owns_spectroscopy_profile_weak_line_states = false;
        }
        self.borrowed.spectroscopy_plan_key = prepared.spectroscopy_plan_key;
        self.borrowed.spectroscopy_profile_cache_inputs_key = prepared.spectroscopy_profile_cache_inputs_key;
        self.captured = true;
    }

    fn deinit(self: *ProfilePreparationSession, allocator: Allocator) void {
        if (self.borrowed.strong_line_states) |states| {
            for (states) |*state| state.deinit(allocator);
            allocator.free(states);
        }
        if (self.borrowed.weak_line_states) |states| {
            for (states) |*state| state.deinit(allocator);
            allocator.free(states);
        }
        if (self.borrowed.altitudes_km.len != 0) allocator.free(self.borrowed.altitudes_km);
        if (self.borrowed.pressures_hpa.len != 0) allocator.free(self.borrowed.pressures_hpa);
        if (self.borrowed.temperatures_k.len != 0) allocator.free(self.borrowed.temperatures_k);
        self.* = .{};
    }
};

pub const AerosolProfileSpectrumSession = struct {
    loaded_inputs: runtime.LoadedVendorO2AInputs,
    scene: Scene,
    route: reference_types.Route,
    weak_cutoff_grid: runtime.WeakCutoffGridCache = .{},
    solar_rewindowed: bool = false,
    profile_preparation: ProfilePreparationSession = .{},
    cached_profile_layers: []AerosolProfileLayer = &.{},
    cached_prepared: ?OpticsPrepare.PreparedOpticalState = null,

    pub fn init(allocator: Allocator, input: *const O2AInput) !AerosolProfileSpectrumSession {
        var loaded_inputs = try runtime.loadResolvedVendorO2AInputs(allocator, input);
        errdefer loaded_inputs.deinit(allocator);

        var scene = try runtime.buildResolvedVendorO2AScene(
            allocator,
            input,
            loaded_inputs.raw_solar_spectrum,
        );
        errdefer scene.deinitOwned(allocator);

        return .{
            .loaded_inputs = loaded_inputs,
            .scene = scene,
            .route = try runtime.prepareResolvedVendorO2ARouteFromResolved(input),
        };
    }

    pub fn deinit(self: *AerosolProfileSpectrumSession, allocator: Allocator) void {
        if (self.cached_prepared) |*prepared| prepared.deinit(allocator);
        if (self.cached_profile_layers.len != 0) allocator.free(self.cached_profile_layers);
        self.profile_preparation.deinit(allocator);
        self.weak_cutoff_grid.deinit(allocator);
        self.scene.deinitOwned(allocator);
        self.loaded_inputs.deinit(allocator);
        self.* = undefined;
    }

    pub fn run(
        self: *AerosolProfileSpectrumSession,
        allocator: Allocator,
        storage: *SessionStorage,
        profile_layers: []const AerosolProfileLayer,
    ) !Output {
        if (!profileLayersEqual(self.cached_profile_layers, profile_layers)) {
            if (self.cached_prepared) |*prepared| {
                self.profile_preparation.captureFromPrepared(prepared);
                prepared.deinit(allocator);
                self.cached_prepared = null;
            }
            if (self.cached_profile_layers.len != 0) {
                allocator.free(self.cached_profile_layers);
                self.cached_profile_layers = &.{};
            }
            const copied_layers = try allocator.dupe(AerosolProfileLayer, profile_layers);
            errdefer allocator.free(copied_layers);
            var prepared = try runtime.prepareResolvedVendorO2AOpticalStateWithSceneSessionCachesAndAerosolProfile(
                allocator,
                &self.scene,
                &self.loaded_inputs,
                &self.weak_cutoff_grid,
                &self.solar_rewindowed,
                self.profile_preparation.borrowedPreparation(),
                copied_layers,
            );
            errdefer prepared.deinit(allocator);
            self.cached_profile_layers = copied_layers;
            self.cached_prepared = prepared;
        }

        const prepared = &self.cached_prepared.?;

        const view = try InstrumentGrid.simulateProductWithWorkspace(
            allocator,
            storage,
            &self.scene,
            self.route,
            prepared,
            implementations.exact(),
        );
        return view.toOwned(allocator);
    }
};

fn profileLayersEqual(left: []const AerosolProfileLayer, right: []const AerosolProfileLayer) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| {
        if (a.top_pressure_hpa != b.top_pressure_hpa or
            a.bottom_pressure_hpa != b.bottom_pressure_hpa or
            a.optical_depth != b.optical_depth or
            a.single_scatter_albedo != b.single_scatter_albedo or
            a.asymmetry_factor != b.asymmetry_factor or
            a.angstrom_exponent != b.angstrom_exponent or
            a.reference_wavelength_nm != b.reference_wavelength_nm)
        {
            return false;
        }
    }
    return true;
}

pub fn defaultInput() O2AInput {
    return .{
        .metadata = .{
            .id = "disamar_reference_o2a",
            .storage = "disamar-reference-o2a",
            .description = "DISAMAR O2 A reference case for Python and validation.",
        },
        .plan = .{
            .model_family = "disamar_standard",
            .transport_solver = "dispatcher",
            .execution_derivative_mode = "none",
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
            .regime = .nadir,
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
        .outputs = &.{},
        .validation = .{
            .strict_unknown_fields = true,
            .require_resolved_assets = true,
            .require_resolved_stage_references = true,
        },
    };
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
        .outputs = input.outputs,
        .validation = input.validation,
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
        prepared.route,
        &prepared.prepared,
        implementations.exact(),
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
        prepared.route,
        &prepared.prepared,
        implementations.exact(),
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
        prepared.route,
        &prepared.prepared,
        implementations.exact(),
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
        prepared.route,
        &prepared.prepared,
        implementations.exact(),
    );
}

pub fn validateInput(input: *const O2AInput) !void {
    if (input.spectral_grid.sample_count < 2) return error.InvalidSpectralGrid;
    if (!(input.spectral_grid.end_nm > input.spectral_grid.start_nm)) return error.InvalidSpectralGrid;
    if (input.layer_count == 0 or input.sublayer_divisions == 0) return error.InvalidAtmosphere;
    if (input.intervals.len == 0) return error.InvalidAtmosphere;
    for (input.intervals) |interval| try interval.validate();
    try input.aerosol.placement.validate();
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
