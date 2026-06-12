const std = @import("std");

const defaults = @import("defaults.zig");
const errors = @import("../common/errors.zig");
const o2_case = @import("o2_case.zig");
const validate = @import("validate.zig");

const Allocator = std.mem.Allocator;
const default_output_isotopes = [_]usize{ 1, 2, 3 };

// json.zig ---------------------------------------------------------------------------------------------------|
// Python-native O2 A JSON bridge.                                                                             |
//                                                                                                             |
// boundary                                                                                                    |
//   Python emits O2AInput.to_native_json_bytes() with resolved asset paths and a few Python bookkeeping       |
//   fields. This parser turns that API shape into O2Case, validates controls that are intentionally inert     |
//   for this WP4 forward-only route, and rejects unsupported route changes before compute sees the case.      |
//                                                                                                             |
// compatibility                                                                                               |
//   Python's json encoder emits bare NaN for optional altitude placeholders. Zig's JSON scanner is strict,    |
//   so the input boundary rewrites bare NaN tokens to null before typed parsing. Those fields are not model   |
//   controls on this route; pressure bounds are the consumed vertical coordinates.                            |
// ------------------------------------------------------------------------------------------------------------|

// ParsedReferenceCaseJson ------------------------------------------------------------------------------------|
// Owns parser arena storage backing one borrowed O2Case.                                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 1648 B (1.609 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..1039] parsed: std.json.Parsed(NativeReferenceCaseJson)                                               |
// [1040..1647] case  : O2Case                                                                                 |
//                                                                                                             |
// referenced storage                                                                                          |
//   case slices and strings point into parsed.arena and stay valid until deinit.                              |
pub const ParsedReferenceCaseJson = struct {
    parsed: std.json.Parsed(NativeReferenceCaseJson),
    case: o2_case.O2Case,

    pub fn deinit(self: *ParsedReferenceCaseJson) void {
        // ParsedReferenceCaseJson.deinit ---------------------------------------------------------------------|
        // Release the JSON parser arena that backs all borrowed case strings and slices.                      |
        // ----------------------------------------------------------------------------------------------------|
        self.parsed.deinit();
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn parseReferenceCaseJson(allocator: Allocator, raw_json: []const u8) !ParsedReferenceCaseJson {
    // parseReferenceCaseJson ---------------------------------------------------------------------------------|
    // Parse Python's native O2 A JSON shape and return a typed case borrowing parser-owned rows.              |
    // --------------------------------------------------------------------------------------------------------|
    const normalized = try normalizePythonJson(allocator, raw_json);
    defer normalized.deinit(allocator);

    var parsed = try std.json.parseFromSlice(
        NativeReferenceCaseJson,
        allocator,
        normalized.bytes,
        .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
    );
    errdefer parsed.deinit();

    const case = try buildCase(parsed.value);
    try validate.referenceCase(case);

    return .{ .parsed = parsed, .case = case };
}

pub fn renderDefaultReferenceCaseJson(allocator: Allocator) ![]u8 {
    // renderDefaultReferenceCaseJson -------------------------------------------------------------------------|
    // Render the built-in O2 A case in the Python native JSON shape consumed by O2AInput.from_json.           |
    // --------------------------------------------------------------------------------------------------------|
    const case = defaults.referenceCase();
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    try std.json.Stringify.value(outputReferenceCase(case), .{}, &out.writer);
    return out.toOwnedSlice();
}

fn buildCase(native: NativeReferenceCaseJson) !o2_case.O2Case {
    // buildCase ----------------------------------------------------------------------------------------------|
    // Convert API JSON rows into O2Case while rejecting unsupported controls at the parser boundary.          |
    // --------------------------------------------------------------------------------------------------------|
    try validateMetadata(native.metadata);
    try validatePlan(native.plan);
    try validateReferenceAssets(native.inputs);
    try validateObservation(native.observation, native.inputs.raw_solar_reference.id);
    try validateRtm(native.rtm_controls, native.geometry.model);
    try validateAerosol(native.aerosol);

    const line_mixing_factor = native.o2.line_mixing_factor orelse return errors.Error.UnsupportedJsonInput;
    const threshold_line_sim = native.o2.threshold_line_sim orelse return errors.Error.UnsupportedJsonInput;
    const cutoff_sim_cm1 = native.o2.cutoff_sim_cm1 orelse return errors.Error.UnsupportedJsonInput;
    const cia_asset = native.o2o2.cia_asset orelse return errors.Error.UnsupportedJsonInput;
    const rtm_defaults = defaults.referenceCase().rtm;

    return .{
        .id = native.scene_id,
        .spectral_grid = native.spectral_grid,
        .surface_albedo = native.surface_albedo,

        .atmosphere = .{
            .profile = native.inputs.atmosphere_profile,
            .surface_pressure_hpa = native.surface_pressure_hpa,
            .layer_count = native.layer_count,
            .sublayer_divisions = native.sublayer_divisions,
            .fit_interval_index_1based = native.fit_interval_index_1based,
            .intervals = native.intervals,
        },

        .geometry = .{
            .solar_zenith_deg = native.geometry.solar_zenith_deg,
            .viewing_zenith_deg = native.geometry.viewing_zenith_deg,
            .relative_azimuth_deg = native.geometry.relative_azimuth_deg,
            .pseudo_spherical = std.mem.eql(u8, native.geometry.model, "pseudo_spherical"),
        },

        .aerosol = .{
            .optical_depth = native.aerosol.optical_depth,
            .single_scatter_albedo = native.aerosol.single_scatter_albedo,
            .asymmetry_factor = native.aerosol.asymmetry_factor,
            .angstrom_exponent = native.aerosol.angstrom_exponent,
            .reference_wavelength_nm = native.aerosol.reference_wavelength_nm,
            .interval_index_1based = native.aerosol.placement.interval_index_1based,
            .top_pressure_hpa = native.aerosol.placement.top_pressure_hpa,
            .bottom_pressure_hpa = native.aerosol.placement.bottom_pressure_hpa,
        },

        .observation = .{
            .instrument_name = native.observation.instrument_name,
            .instrument_line_fwhm_nm = native.observation.instrument_line_fwhm_nm,
            .high_resolution_step_nm = native.observation.high_resolution_step_nm,
            .high_resolution_half_span_nm = native.observation.high_resolution_half_span_nm,
            .adaptive_points_per_fwhm = native.observation.adaptive_reference_grid.points_per_fwhm,
            .strong_line_min_divisions = native.observation.adaptive_reference_grid.strong_line_min_divisions,
            .strong_line_max_divisions = native.observation.adaptive_reference_grid.strong_line_max_divisions,
            .solar_reference = native.inputs.raw_solar_reference,
        },

        .line_gas = .{
            .line_list = native.o2.line_list_asset,
            .line_mixing = native.o2.line_mixing_asset,
            .strong_lines = native.o2.strong_lines_asset,
            .line_mixing_factor = line_mixing_factor,
            .isotopes_sim = native.o2.isotopes_sim,
            .threshold_line_sim = threshold_line_sim,
            .cutoff_sim_cm1 = cutoff_sim_cm1,
        },

        .cia = .{
            .enabled = native.o2o2.enabled,
            .table = cia_asset,
        },

        .rtm = .{
            .stream_count = native.rtm_controls.n_streams,
            .fourier_term_limit = rtm_defaults.fourier_term_limit,
        },
    };
}

fn validateMetadata(metadata: MetadataJson) !void {
    // validateMetadata ---------------------------------------------------------------------------------------|
    // Require Python bookkeeping fields to be present and non-empty so missing payload families fail early.   |
    // --------------------------------------------------------------------------------------------------------|
    if (metadata.id.len == 0) return errors.Error.InvalidControl;
    if (metadata.storage.len == 0) return errors.Error.InvalidControl;
}

fn validatePlan(plan: PlanJson) !void {
    // validatePlan -------------------------------------------------------------------------------------------|
    // The C run entry point selects Jacobian mode; JSON plan metadata may not request another compute route.  |
    // --------------------------------------------------------------------------------------------------------|
    if (!std.mem.eql(u8, plan.derivative_mode, "none")) return errors.Error.UnsupportedJsonInput;
}

fn validateReferenceAssets(inputs: ReferenceInputsJson) !void {
    // validateReferenceAssets --------------------------------------------------------------------------------|
    // Consume Python's reference asset map by validating ids/formats used for RTM and Python roundtrips.      |
    // --------------------------------------------------------------------------------------------------------|
    try expectAsset(inputs.atmosphere_profile, "atmosphere_profile", "profile_csv");
    try expectAsset(inputs.raw_solar_reference, "raw_solar_reference", "solar_reference_csv");
    try expectAsset(inputs.vendor_reference_csv, "vendor_reference_csv", "disamar_o2a_reference_csv");
    try expectAsset(inputs.airmass_factor_lut, "airmass_factor_lut", "csv");
}

fn validateObservation(observation: ObservationJson, solar_reference_asset_id: []const u8) !void {
    // validateObservation ------------------------------------------------------------------------------------|
    // Accept the current O2 A instrument route and reject explicit measurement axes until sampling ports it.  |
    // --------------------------------------------------------------------------------------------------------|
    if (!std.mem.eql(u8, observation.regime, "nadir")) return errors.Error.UnsupportedJsonInput;
    if (!std.mem.eql(u8, observation.sampling, "native")) return errors.Error.UnsupportedJsonInput;
    if (!std.mem.eql(u8, observation.builtin_line_shape, "flat_top_n4")) return errors.Error.UnsupportedJsonInput;
    if (!std.mem.eql(u8, observation.solar_reference_asset_id, solar_reference_asset_id)) {
        return errors.Error.UnsupportedJsonInput;
    }
    if (observation.measured_wavelengths_nm.len != 0) return errors.Error.UnsupportedJsonInput;
}

fn validateRtm(rtm: RtmControlsJson, geometry_model: []const u8) !void {
    // validateRtm --------------------------------------------------------------------------------------------|
    // Keep WP4 on the proven Stage 2/3 route: multiple scattering, integrated source, default thresholds.     |
    // --------------------------------------------------------------------------------------------------------|
    if (!std.mem.eql(u8, rtm.scattering, "multiple")) return errors.Error.UnsupportedJsonInput;
    if (rtm.n_streams != defaults.referenceCase().rtm.stream_count) return errors.Error.UnsupportedJsonInput;
    if (!rtm.integrate_source_function) return errors.Error.UnsupportedJsonInput;
    if (!rtm.renorm_phase_function) return errors.Error.UnsupportedJsonInput;

    const pseudo_spherical = std.mem.eql(u8, geometry_model, "pseudo_spherical");
    const plane_parallel = std.mem.eql(u8, geometry_model, "plane_parallel");
    if (!pseudo_spherical and !plane_parallel) return errors.Error.UnsupportedJsonInput;
    if (rtm.use_spherical_correction != pseudo_spherical) return errors.Error.UnsupportedJsonInput;

    try expectDefaultThresholds(rtm.performance_thresholds);
}

fn validateAerosol(aerosol: AerosolJson) !void {
    // validateAerosol ----------------------------------------------------------------------------------------|
    // Accept the scalar explicit-pressure aerosol layer; reject multi-layer profile payloads for WP5.         |
    // --------------------------------------------------------------------------------------------------------|
    if (!std.mem.eql(u8, aerosol.placement.semantics, "explicit_interval_bounds")) {
        return errors.Error.UnsupportedJsonInput;
    }
    if (aerosol.profile.len != 0) return errors.Error.UnsupportedJsonInput;
}

fn expectDefaultThresholds(thresholds: PerformanceThresholdsJson) !void {
    // expectDefaultThresholds --------------------------------------------------------------------------------|
    // Validate every Python threshold field because this WP4 slice still builds SolveConfig from defaults.    |
    // --------------------------------------------------------------------------------------------------------|
    const default_order_shape =
        thresholds.num_orders_max == 0 and
        thresholds.fourier_floor_scalar == 2 and
        thresholds.fourier_order_cap == null and
        thresholds.aerosol_tangent_order_cap == null;

    const default_fourier_and_doubling =
        thresholds.fourier_tail_reflectance_epsilon == 3.0e-14 and
        thresholds.threshold_doubl == 1.0e-6 and
        thresholds.phase_function_truncation_threshold == 1.0e-8;

    const default_scattering_convergence =
        thresholds.threshold_conv_first == 1.5e-7 and
        thresholds.threshold_conv_mult == 1.5e-9 and
        thresholds.threshold_mul == 1.0e-8;

    if (!default_order_shape) return errors.Error.UnsupportedJsonInput;
    if (!default_fourier_and_doubling) return errors.Error.UnsupportedJsonInput;
    if (!default_scattering_convergence) return errors.Error.UnsupportedJsonInput;
}

fn expectAsset(asset: o2_case.Asset, id: []const u8, format: []const u8) !void {
    // expectAsset --------------------------------------------------------------------------------------------|
    // Check asset identity while allowing Python to resolve relative paths to absolute package paths.         |
    // --------------------------------------------------------------------------------------------------------|
    if (!std.mem.eql(u8, asset.id, id)) return errors.Error.UnsupportedJsonInput;
    if (!std.mem.eql(u8, asset.format, format)) return errors.Error.UnsupportedJsonInput;
    if (asset.path.len == 0) return errors.Error.InvalidControl;
}

fn outputReferenceCase(case: o2_case.O2Case) OutputReferenceCaseJson {
    // outputReferenceCase ------------------------------------------------------------------------------------|
    // Build the Python-native JSON view for the built-in reference case.                                      |
    // --------------------------------------------------------------------------------------------------------|
    const geometry_model = if (case.geometry.pseudo_spherical) "pseudo_spherical" else "plane_parallel";

    return .{
        .metadata = .{
            .id = "disamar_reference_o2a",
            .storage = "disamar-reference-o2a",
            .description = "DISAMAR O2 A reference case for Python and validation.",
        },
        .plan = .{ .derivative_mode = "none" },

        .inputs = .{
            .atmosphere_profile = case.atmosphere.profile,
            .vendor_reference_csv = o2_case.asset(
                "vendor_reference_csv",
                "data/reference_data/validation/o2a_with_cia_disamar_reference.csv",
                "disamar_o2a_reference_csv",
            ),
            .raw_solar_reference = case.observation.solar_reference,
            .airmass_factor_lut = o2_case.asset(
                "airmass_factor_lut",
                "data/reference_data/luts/airmass_factor_nadir_demo.csv",
                "csv",
            ),
        },

        .scene_id = case.id,
        .spectral_grid = case.spectral_grid,
        .layer_count = case.atmosphere.layer_count,
        .sublayer_divisions = case.atmosphere.sublayer_divisions,
        .surface_pressure_hpa = case.atmosphere.surface_pressure_hpa,
        .fit_interval_index_1based = case.atmosphere.fit_interval_index_1based,
        .intervals = case.atmosphere.intervals,
        .surface_albedo = case.surface_albedo,

        .geometry = .{
            .model = geometry_model,
            .solar_zenith_deg = case.geometry.solar_zenith_deg,
            .viewing_zenith_deg = case.geometry.viewing_zenith_deg,
            .relative_azimuth_deg = case.geometry.relative_azimuth_deg,
        },

        .aerosol = .{
            .optical_depth = case.aerosol.optical_depth,
            .single_scatter_albedo = case.aerosol.single_scatter_albedo,
            .asymmetry_factor = case.aerosol.asymmetry_factor,
            .angstrom_exponent = case.aerosol.angstrom_exponent,
            .reference_wavelength_nm = case.aerosol.reference_wavelength_nm,
            .placement = .{
                .semantics = "explicit_interval_bounds",
                .interval_index_1based = case.aerosol.interval_index_1based,
                .top_pressure_hpa = case.aerosol.top_pressure_hpa,
                .bottom_pressure_hpa = case.aerosol.bottom_pressure_hpa,
            },
        },

        .observation = .{
            .instrument_name = case.observation.instrument_name,
            .regime = "nadir",
            .sampling = "native",
            .instrument_line_fwhm_nm = case.observation.instrument_line_fwhm_nm,
            .builtin_line_shape = "flat_top_n4",
            .high_resolution_step_nm = case.observation.high_resolution_step_nm,
            .high_resolution_half_span_nm = case.observation.high_resolution_half_span_nm,
            .adaptive_reference_grid = .{
                .points_per_fwhm = case.observation.adaptive_points_per_fwhm,
                .strong_line_min_divisions = case.observation.strong_line_min_divisions,
                .strong_line_max_divisions = case.observation.strong_line_max_divisions,
            },
            .solar_reference_asset_id = case.observation.solar_reference.id,
        },

        .o2 = .{
            .line_list_asset = case.line_gas.line_list,
            .line_mixing_asset = case.line_gas.line_mixing,
            .strong_lines_asset = case.line_gas.strong_lines,
            .line_mixing_factor = case.line_gas.line_mixing_factor,
            .isotopes_sim = default_output_isotopes[0..],
            .threshold_line_sim = case.line_gas.threshold_line_sim,
            .cutoff_sim_cm1 = case.line_gas.cutoff_sim_cm1,
        },

        .o2o2 = .{
            .enabled = case.cia.enabled,
            .cia_asset = case.cia.table,
        },

        .rtm_controls = .{
            .scattering = "multiple",
            .n_streams = case.rtm.stream_count,
            .performance_thresholds = .{},
            .use_spherical_correction = case.geometry.pseudo_spherical,
            .integrate_source_function = true,
            .renorm_phase_function = true,
        },
    };
}

const NormalizedJson = struct {
    bytes: []const u8,
    owned: bool,

    fn deinit(self: NormalizedJson, allocator: Allocator) void {
        // NormalizedJson.deinit ------------------------------------------------------------------------------|
        // Free the compatibility copy only when bare NaN replacement allocated one.                           |
        // ----------------------------------------------------------------------------------------------------|
        if (self.owned) allocator.free(self.bytes);
    }
};

fn normalizePythonJson(allocator: Allocator, raw_json: []const u8) !NormalizedJson {
    // normalizePythonJson ------------------------------------------------------------------------------------|
    // Replace bare NaN tokens outside strings with null so std.json can scan Python's placeholder fields.     |
    // --------------------------------------------------------------------------------------------------------|
    if (std.mem.indexOf(u8, raw_json, "NaN") == null) return .{ .bytes = raw_json, .owned = false };

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var index: usize = 0;
    var in_string = false;
    var escaped = false;
    var changed = false;
    while (index < raw_json.len) {
        const byte = raw_json[index];
        if (in_string) {
            try out.append(allocator, byte);

            if (escaped) {
                escaped = false;
            } else if (byte == '\\') {
                escaped = true;
            } else if (byte == '"') {
                in_string = false;
            }

            index += 1;
            continue;
        }

        if (byte == '"') {
            in_string = true;
            try out.append(allocator, byte);
            index += 1;
            continue;
        }

        if (isBareNaN(raw_json, index)) {
            try out.appendSlice(allocator, "null");
            index += 3;
            changed = true;
            continue;
        }

        try out.append(allocator, byte);
        index += 1;
    }

    if (!changed) {
        out.deinit(allocator);
        return .{ .bytes = raw_json, .owned = false };
    }

    return .{ .bytes = try out.toOwnedSlice(allocator), .owned = true };
}

fn isBareNaN(bytes: []const u8, index: usize) bool {
    // isBareNaN ----------------------------------------------------------------------------------------------|
    // Detect Python's unquoted NaN token without touching string content or longer identifier-like words.     |
    // --------------------------------------------------------------------------------------------------------|
    if (index + 3 > bytes.len) return false;
    if (!std.mem.eql(u8, bytes[index..][0..3], "NaN")) return false;

    const before_ok = index == 0 or !isNameByte(bytes[index - 1]);
    const after_ok = index + 3 == bytes.len or !isNameByte(bytes[index + 3]);
    return before_ok and after_ok;
}

fn isNameByte(byte: u8) bool {
    // isNameByte ---------------------------------------------------------------------------------------------|
    // JSON identifiers are invalid here; this guard keeps the NaN rewrite scoped to the exact bare token.     |
    // --------------------------------------------------------------------------------------------------------|
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

const MetadataJson = struct {
    id: []const u8,
    storage: []const u8,
    description: []const u8 = "",
};

const PlanJson = struct {
    derivative_mode: []const u8,
};

const ReferenceInputsJson = struct {
    atmosphere_profile: o2_case.Asset,
    vendor_reference_csv: o2_case.Asset,
    raw_solar_reference: o2_case.Asset,
    airmass_factor_lut: o2_case.Asset,
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
};

const AerosolProfileLayerJson = struct {
    top_pressure_hpa: f64,
    bottom_pressure_hpa: f64,
    optical_depth: f64,
    single_scatter_albedo: f64 = 0.93,
    asymmetry_factor: f64 = 0.65,
    angstrom_exponent: f64 = 1.3,
    reference_wavelength_nm: f64 = 550.0,
};

const AerosolJson = struct {
    optical_depth: f64,
    single_scatter_albedo: f64,
    asymmetry_factor: f64,
    angstrom_exponent: f64,
    reference_wavelength_nm: f64,
    placement: AerosolPlacementJson,
    profile: []const AerosolProfileLayerJson = &.{},
};

const AdaptiveReferenceGridJson = struct {
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
    adaptive_reference_grid: AdaptiveReferenceGridJson,
    solar_reference_asset_id: []const u8,
    measured_wavelengths_nm: []const f64 = &.{},
};

const O2Json = struct {
    line_list_asset: o2_case.Asset,
    line_mixing_asset: o2_case.Asset,
    strong_lines_asset: o2_case.Asset,
    line_mixing_factor: ?f64,
    isotopes_sim: []const u8,
    threshold_line_sim: ?f64,
    cutoff_sim_cm1: ?f64,
};

const O2O2Json = struct {
    enabled: bool,
    cia_asset: ?o2_case.Asset,
};

const OutputO2Json = struct {
    line_list_asset: o2_case.Asset,
    line_mixing_asset: o2_case.Asset,
    strong_lines_asset: o2_case.Asset,
    line_mixing_factor: f64,
    isotopes_sim: []const usize,
    threshold_line_sim: f64,
    cutoff_sim_cm1: f64,
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

const NativeReferenceCaseJson = struct {
    metadata: MetadataJson,
    plan: PlanJson,
    inputs: ReferenceInputsJson,
    scene_id: []const u8,
    spectral_grid: o2_case.SpectralGrid,
    layer_count: usize,
    sublayer_divisions: usize,
    surface_pressure_hpa: f64,
    fit_interval_index_1based: usize,
    intervals: []const o2_case.VerticalInterval,
    surface_albedo: f64,
    geometry: GeometryJson,
    aerosol: AerosolJson,
    observation: ObservationJson,
    o2: O2Json,
    o2o2: O2O2Json,
    rtm_controls: RtmControlsJson,
};

const OutputReferenceCaseJson = struct {
    metadata: MetadataJson,
    plan: PlanJson,
    inputs: ReferenceInputsJson,
    scene_id: []const u8,
    spectral_grid: o2_case.SpectralGrid,
    layer_count: usize,
    sublayer_divisions: usize,
    surface_pressure_hpa: f64,
    fit_interval_index_1based: usize,
    intervals: []const o2_case.VerticalInterval,
    surface_albedo: f64,
    geometry: GeometryJson,
    aerosol: AerosolJson,
    observation: ObservationJson,
    o2: OutputO2Json,
    o2o2: O2O2Json,
    rtm_controls: RtmControlsJson,
};
