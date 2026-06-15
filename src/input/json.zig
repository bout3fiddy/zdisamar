const std = @import("std");

const errors = @import("../common/errors.zig");
const scene_input = @import("scene.zig");
const transport_controls = @import("../rtm/controls.zig");
const validate = @import("validate.zig");

const Allocator = std.mem.Allocator;
pub const supported_stream_count: usize = 20;
pub const route_fourier_term_limit: usize = 20;

// json.zig ---------------------------------------------------------------------------------------------------|
// Python-native O2 A JSON bridge.                                                                             |
//                                                                                                             |
// boundary                                                                                                    |
//   Python emits Scene.to_native_json_bytes() with resolved asset paths and a few Python bookkeeping          |
//   fields. This parser turns that API shape into Scene, validates controls that are intentionally inert      |
//   for this O2 A forward-only route, and rejects unsupported route changes before compute sees the scene.    |
//                                                                                                             |
// JSON input normalization                                                                                    |
//   Python's json encoder emits bare NaN for optional altitude placeholders. Zig's JSON scanner is strict,    |
//   so the input boundary rewrites bare NaN tokens to null before typed parsing. Those fields are not model   |
//   controls on this route; pressure bounds are the consumed vertical coordinates.                            |
// ------------------------------------------------------------------------------------------------------------|

// ParsedSceneJson --------------------------------------------------------------------------------------------|
// Owns parser arena storage backing one borrowed Scene.                                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 1744 B (1.703 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..1039] parsed: std.json.Parsed(NativeSceneJson)                                                       |
// [1040..1743] scene : Scene                                                                                  |
//                                                                                                             |
// referenced storage                                                                                          |
//   scene slices and strings point into parsed.arena and stay valid until deinit.                             |
pub const ParsedSceneJson = struct {
    parsed: std.json.Parsed(NativeSceneJson),
    scene: scene_input.Scene,

    pub fn deinit(self: *ParsedSceneJson) void {
        // ParsedSceneJson.deinit -----------------------------------------------------------------------------|
        // Release the JSON parser arena that backs all borrowed scene strings and slices.                     |
        // ----------------------------------------------------------------------------------------------------|
        self.parsed.deinit();
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn parseSceneJson(allocator: Allocator, raw_json: []const u8) !ParsedSceneJson {
    // parseSceneJson -----------------------------------------------------------------------------------------|
    // Parse Python's native O2 A JSON shape and return a typed scene borrowing parser-owned rows.             |
    // --------------------------------------------------------------------------------------------------------|
    const normalized = try normalizePythonJson(allocator, raw_json);
    defer normalized.deinit(allocator);

    var parsed = try std.json.parseFromSlice(
        NativeSceneJson,
        allocator,
        normalized.bytes,
        .{ .allocate = .alloc_always },
    );
    errdefer parsed.deinit();

    const scene = try buildScene(parsed.arena.allocator(), parsed.value);
    try validate.sceneControls(scene);

    return .{ .parsed = parsed, .scene = scene };
}

fn buildScene(allocator: Allocator, native: NativeSceneJson) !scene_input.Scene {
    // buildScene ---------------------------------------------------------------------------------------------|
    // Convert API JSON rows into Scene while rejecting unsupported controls at the parser boundary.           |
    // --------------------------------------------------------------------------------------------------------|
    try validateMetadata(native.metadata);
    try validatePlan(native.plan);
    try validateAssets(native.inputs);
    try validateObservation(native.observation, native.inputs.raw_solar_reference.id);
    const performance_thresholds = try performanceThresholdsFromJson(native.rtm_controls.performance_thresholds);
    try validateRtm(native.rtm_controls, native.geometry.model, performance_thresholds);
    try validateAerosol(native.aerosol);
    const intervals = try verticalIntervalsFromJson(allocator, native.intervals);
    const aerosol_profile = try aerosolProfileRowsFromJson(allocator, native.aerosol.profile);

    const line_mixing_factor = native.o2.line_mixing_factor orelse return errors.Error.UnsupportedJsonInput;
    const threshold_line_sim = native.o2.threshold_line_sim orelse return errors.Error.UnsupportedJsonInput;
    const cutoff_sim_cm1 = native.o2.cutoff_sim_cm1 orelse return errors.Error.UnsupportedJsonInput;
    const cia_asset = native.o2o2.cia_asset orelse return errors.Error.UnsupportedJsonInput;

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
            .intervals = intervals,
        },

        .geometry = .{
            .solar_zenith_deg = native.geometry.solar_zenith_deg,
            .viewing_zenith_deg = native.geometry.viewing_zenith_deg,
            .relative_azimuth_deg = native.geometry.relative_azimuth_deg,
            .pseudo_spherical = std.mem.eql(u8, native.geometry.model, "pseudo_spherical"),
        },

        .aerosol = .{
            .optical_depth = aerosolScalarOpticalDepth(native.aerosol),
            .single_scatter_albedo = aerosolScalarSingleScatterAlbedo(native.aerosol),
            .asymmetry_factor = aerosolScalarAsymmetryFactor(native.aerosol),
            .angstrom_exponent = aerosolScalarAngstromExponent(native.aerosol),
            .reference_wavelength_nm = aerosolScalarReferenceWavelengthNm(native.aerosol),
            .interval_index_1based = native.aerosol.placement.interval_index_1based,
            .top_pressure_hpa = aerosolScalarTopPressureHpa(native.aerosol),
            .bottom_pressure_hpa = aerosolScalarBottomPressureHpa(native.aerosol),
            .profile = aerosol_profile,
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
            .measured_wavelengths_nm = native.observation.measured_wavelengths_nm,
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
            .fourier_term_limit = route_fourier_term_limit,
            .performance_thresholds = performance_thresholds,
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

fn validateAssets(inputs: InputsJson) !void {
    // validateAssets -----------------------------------------------------------------------------------------|
    // Consume Python's reference asset map by validating ids/formats used for RTM and Python roundtrips.      |
    // --------------------------------------------------------------------------------------------------------|
    try expectAsset(inputs.atmosphere_profile, "atmosphere_profile", "profile_csv");
    try expectAsset(inputs.raw_solar_reference, "raw_solar_reference", "solar_reference_csv");
    try expectAsset(inputs.vendor_reference_csv, "vendor_reference_csv", "disamar_o2a_reference_csv");
    try expectAsset(inputs.airmass_factor_lut, "airmass_factor_lut", "csv");
}

fn validateObservation(observation: ObservationJson, solar_reference_asset_id: []const u8) !void {
    // validateObservation ------------------------------------------------------------------------------------|
    // Accept the current O2 A instrument route and pass explicit sparse product axes to Scene validation.     |
    // --------------------------------------------------------------------------------------------------------|
    if (!std.mem.eql(u8, observation.regime, "nadir")) return errors.Error.UnsupportedJsonInput;
    if (!std.mem.eql(u8, observation.sampling, "native")) return errors.Error.UnsupportedJsonInput;
    if (!std.mem.eql(u8, observation.builtin_line_shape, "flat_top_n4")) return errors.Error.UnsupportedJsonInput;
    if (!std.mem.eql(u8, observation.solar_reference_asset_id, solar_reference_asset_id)) {
        return errors.Error.UnsupportedJsonInput;
    }
}

fn validateRtm(
    rtm: RtmControlsJson,
    geometry_model: []const u8,
    performance_thresholds: transport_controls.PerformanceThresholds,
) !void {
    // validateRtm --------------------------------------------------------------------------------------------|
    // Keep O2 A on the supported integrated-source route while consuming scene-owned LABOS threshold controls.|
    // --------------------------------------------------------------------------------------------------------|
    if (!std.mem.eql(u8, rtm.scattering, "multiple")) return errors.Error.UnsupportedJsonInput;
    if (rtm.n_streams != supported_stream_count) return errors.Error.UnsupportedJsonInput;
    if (!rtm.integrate_source_function) return errors.Error.UnsupportedJsonInput;
    if (!rtm.renorm_phase_function) return errors.Error.UnsupportedJsonInput;

    const pseudo_spherical = std.mem.eql(u8, geometry_model, "pseudo_spherical");
    const plane_parallel = std.mem.eql(u8, geometry_model, "plane_parallel");
    if (!pseudo_spherical and !plane_parallel) return errors.Error.UnsupportedJsonInput;
    if (rtm.use_spherical_correction != pseudo_spherical) return errors.Error.UnsupportedJsonInput;

    try performance_thresholds.validate();
}

fn validateAerosol(aerosol: AerosolJson) !void {
    // validateAerosol ----------------------------------------------------------------------------------------|
    // Accept scalar placement and explicit multi-layer profile payloads on the proven O2 A route.             |
    // --------------------------------------------------------------------------------------------------------|
    if (!std.mem.eql(u8, aerosol.placement.semantics, "explicit_interval_bounds")) {
        return errors.Error.UnsupportedJsonInput;
    }
    try validateInertAltitudePlaceholder(aerosol.placement.top_altitude_km);
    try validateInertAltitudePlaceholder(aerosol.placement.bottom_altitude_km);
}

fn verticalIntervalsFromJson(
    allocator: Allocator,
    rows: []const VerticalIntervalJson,
) ![]const scene_input.VerticalInterval {
    // verticalIntervalsFromJson ------------------------------------------------------------------------------|
    // Convert native interval JSON while accepting only null altitude placeholders as inert metadata.         |
    // --------------------------------------------------------------------------------------------------------|
    const intervals = try allocator.alloc(scene_input.VerticalInterval, rows.len);
    errdefer allocator.free(intervals);

    for (rows, intervals) |row, *interval| {
        try validateInertAltitudePlaceholder(row.top_altitude_km);
        try validateInertAltitudePlaceholder(row.bottom_altitude_km);
        try validateInertPressureVariance(row.top_pressure_variance_hpa2);
        try validateInertPressureVariance(row.bottom_pressure_variance_hpa2);
        interval.* = .{
            .index_1based = row.index_1based,
            .top_pressure_hpa = row.top_pressure_hpa,
            .bottom_pressure_hpa = row.bottom_pressure_hpa,
            .altitude_divisions = row.altitude_divisions,
        };
    }

    return intervals;
}

fn aerosolProfileRowsFromJson(
    allocator: Allocator,
    rows: []const AerosolProfileLayerJson,
) ![]const scene_input.AerosolProfileLayer {
    // aerosolProfileRowsFromJson -----------------------------------------------------------------------------|
    // Convert public aerosol profile rows while rejecting non-null altitude placeholders on this pressure route.
    // --------------------------------------------------------------------------------------------------------|
    for (rows) |row| {
        try validateInertAltitudePlaceholder(row.top_altitude_km);
        try validateInertAltitudePlaceholder(row.bottom_altitude_km);
    }
    if (rows.len <= 1) return &.{};

    const profile = try allocator.alloc(scene_input.AerosolProfileLayer, rows.len);
    errdefer allocator.free(profile);
    for (rows, profile) |row, *layer| {
        layer.* = aerosolProfileLayerFromJson(row);
    }
    return profile;
}

fn aerosolProfileLayerFromJson(row: AerosolProfileLayerJson) scene_input.AerosolProfileLayer {
    // aerosolProfileLayerFromJson ----------------------------------------------------------------------------|
    // Strip known inert altitude placeholders after they have been validated as null.                         |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .top_pressure_hpa = row.top_pressure_hpa,
        .bottom_pressure_hpa = row.bottom_pressure_hpa,
        .optical_depth = row.optical_depth,
        .single_scatter_albedo = row.single_scatter_albedo,
        .asymmetry_factor = row.asymmetry_factor,
        .angstrom_exponent = row.angstrom_exponent,
        .reference_wavelength_nm = row.reference_wavelength_nm,
    };
}

fn validateInertAltitudePlaceholder(value: ?f64) !void {
    // validateInertAltitudePlaceholder -----------------------------------------------------------------------|
    // Native O2 A uses pressure bounds; finite altitude bounds would be silently inert on this route.         |
    // --------------------------------------------------------------------------------------------------------|
    if (value) |resolved| {
        if (!std.math.isNan(resolved)) return errors.Error.UnsupportedJsonInput;
    }
}

fn validateInertPressureVariance(value: f64) !void {
    // validateInertPressureVariance --------------------------------------------------------------------------|
    // Native O2 A consumes deterministic pressure bounds; non-zero pressure variances would be inert here.    |
    // --------------------------------------------------------------------------------------------------------|
    if (!std.math.isFinite(value) or value != 0.0) return errors.Error.UnsupportedJsonInput;
}

fn aerosolScalarOpticalDepth(aerosol: AerosolJson) f64 {
    // aerosolScalarOpticalDepth ------------------------------------------------------------------------------|
    // Preserve single-profile-layer behavior by folding one layer into the scalar aerosol controls.           |
    // --------------------------------------------------------------------------------------------------------|
    return if (aerosol.profile.len == 1) aerosol.profile[0].optical_depth else aerosol.optical_depth;
}

fn aerosolScalarSingleScatterAlbedo(aerosol: AerosolJson) f64 {
    // aerosolScalarSingleScatterAlbedo -----------------------------------------------------------------------|
    // Preserve single-profile-layer behavior by folding one layer into the scalar aerosol controls.           |
    // --------------------------------------------------------------------------------------------------------|
    return if (aerosol.profile.len == 1)
        aerosol.profile[0].single_scatter_albedo
    else
        aerosol.single_scatter_albedo;
}

fn aerosolScalarAsymmetryFactor(aerosol: AerosolJson) f64 {
    // aerosolScalarAsymmetryFactor ---------------------------------------------------------------------------|
    // Preserve single-profile-layer behavior by folding one layer into the scalar aerosol controls.           |
    // --------------------------------------------------------------------------------------------------------|
    return if (aerosol.profile.len == 1) aerosol.profile[0].asymmetry_factor else aerosol.asymmetry_factor;
}

fn aerosolScalarAngstromExponent(aerosol: AerosolJson) f64 {
    // aerosolScalarAngstromExponent --------------------------------------------------------------------------|
    // Preserve single-profile-layer behavior by folding one layer into the scalar aerosol controls.           |
    // --------------------------------------------------------------------------------------------------------|
    return if (aerosol.profile.len == 1)
        aerosol.profile[0].angstrom_exponent
    else
        aerosol.angstrom_exponent;
}

fn aerosolScalarReferenceWavelengthNm(aerosol: AerosolJson) f64 {
    // aerosolScalarReferenceWavelengthNm ---------------------------------------------------------------------|
    // Preserve single-profile-layer behavior by folding one layer into the scalar aerosol controls.           |
    // --------------------------------------------------------------------------------------------------------|
    return if (aerosol.profile.len == 1)
        aerosol.profile[0].reference_wavelength_nm
    else
        aerosol.reference_wavelength_nm;
}

fn aerosolScalarTopPressureHpa(aerosol: AerosolJson) f64 {
    // aerosolScalarTopPressureHpa ----------------------------------------------------------------------------|
    // Preserve single-profile-layer behavior by folding one layer into explicit pressure placement.           |
    // --------------------------------------------------------------------------------------------------------|
    return if (aerosol.profile.len == 1)
        aerosol.profile[0].top_pressure_hpa
    else
        aerosol.placement.top_pressure_hpa;
}

fn aerosolScalarBottomPressureHpa(aerosol: AerosolJson) f64 {
    // aerosolScalarBottomPressureHpa -------------------------------------------------------------------------|
    // Preserve single-profile-layer behavior by folding one layer into explicit pressure placement.           |
    // --------------------------------------------------------------------------------------------------------|
    return if (aerosol.profile.len == 1)
        aerosol.profile[0].bottom_pressure_hpa
    else
        aerosol.placement.bottom_pressure_hpa;
}

fn performanceThresholdsFromJson(thresholds: PerformanceThresholdsJson) !transport_controls.PerformanceThresholds {
    // performanceThresholdsFromJson --------------------------------------------------------------------------|
    // Convert Python-native LABOS threshold controls into the transport row consumed by root solve config.    |
    //                                                                                                         |
    // boundary                                                                                                |
    //   Python `with_rtm_optimisation_applied()` writes fastmode RTM thresholds into the native scene before  |
    //   crossing the C ABI. The parser must consume those values; accepting them and then using defaults      |
    //   would silently ignore a public forward control.                                                       |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .num_orders_max = try u16FromJson(thresholds.num_orders_max),
        .fourier_floor_scalar = try u16FromJson(thresholds.fourier_floor_scalar),
        .fourier_order_cap = try optionalU16FromJson(thresholds.fourier_order_cap),
        .aerosol_tangent_order_cap = try optionalU16FromJson(thresholds.aerosol_tangent_order_cap),
        .fourier_tail_reflectance_epsilon = thresholds.fourier_tail_reflectance_epsilon,
        .threshold_conv_first = thresholds.threshold_conv_first,
        .threshold_conv_mult = thresholds.threshold_conv_mult,
        .threshold_doubl = thresholds.threshold_doubl,
        .threshold_mul = thresholds.threshold_mul,
        .phase_function_truncation_threshold = thresholds.phase_function_truncation_threshold,
    };
}

fn optionalU16FromJson(value: ?usize) !?u16 {
    // optionalU16FromJson ------------------------------------------------------------------------------------|
    // Narrow optional JSON caps to the transport row width and reject overflow before setup is retained.      |
    // --------------------------------------------------------------------------------------------------------|
    if (value) |some| return try u16FromJson(some);
    return null;
}

fn u16FromJson(value: usize) !u16 {
    // u16FromJson --------------------------------------------------------------------------------------------|
    // Narrow JSON counters to the LABOS control width used by the current route.                              |
    // --------------------------------------------------------------------------------------------------------|
    return std.math.cast(u16, value) orelse errors.Error.UnsupportedJsonInput;
}

fn expectAsset(asset: scene_input.Asset, id: []const u8, format: []const u8) !void {
    // expectAsset --------------------------------------------------------------------------------------------|
    // Check asset identity while allowing Python to resolve relative paths to absolute package paths.         |
    // --------------------------------------------------------------------------------------------------------|
    if (!std.mem.eql(u8, asset.id, id)) return errors.Error.UnsupportedJsonInput;
    if (!std.mem.eql(u8, asset.format, format)) return errors.Error.UnsupportedJsonInput;
    if (asset.path.len == 0) return errors.Error.InvalidControl;
}

const NormalizedJson = struct {
    bytes: []const u8,
    owned: bool,

    fn deinit(self: NormalizedJson, allocator: Allocator) void {
        // NormalizedJson.deinit ------------------------------------------------------------------------------|
        // Free the normalization copy only when bare NaN replacement allocated one.                           |
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

const VerticalIntervalJson = struct {
    index_1based: usize,
    top_pressure_hpa: f64,
    bottom_pressure_hpa: f64,
    top_altitude_km: ?f64 = null,
    bottom_altitude_km: ?f64 = null,
    top_pressure_variance_hpa2: f64 = 0.0,
    bottom_pressure_variance_hpa2: f64 = 0.0,
    altitude_divisions: usize,
};

const AerosolPlacementJson = struct {
    semantics: []const u8,
    interval_index_1based: usize,
    top_pressure_hpa: f64,
    bottom_pressure_hpa: f64,
    top_altitude_km: ?f64 = null,
    bottom_altitude_km: ?f64 = null,
};

const AerosolProfileLayerJson = struct {
    top_pressure_hpa: f64,
    bottom_pressure_hpa: f64,
    top_altitude_km: ?f64 = null,
    bottom_altitude_km: ?f64 = null,
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

const LineGasJson = struct {
    line_list_asset: scene_input.Asset,
    line_mixing_asset: scene_input.Asset,
    strong_lines_asset: scene_input.Asset,
    line_mixing_factor: ?f64,
    isotopes_sim: []const u8,
    threshold_line_sim: ?f64,
    cutoff_sim_cm1: ?f64,
};

const CiaJson = struct {
    enabled: bool,
    cia_asset: ?scene_input.Asset,
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
    intervals: []const VerticalIntervalJson,
    surface_albedo: f64,
    geometry: GeometryJson,
    aerosol: AerosolJson,
    observation: ObservationJson,
    o2: LineGasJson,
    o2o2: CiaJson,
    rtm_controls: RtmControlsJson,
};
