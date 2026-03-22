const std = @import("std");
const SolverMode = @import("../../core/Plan.zig").SolverMode;
const GeometryModel = @import("../../model/Geometry.zig").Model;
const SpectroscopyMode = @import("../../model/Absorber.zig").SpectroscopyMode;
const Instrument = @import("../../model/Instrument.zig").Instrument;
const InstrumentId = @import("../../model/Instrument.zig").Id;
const ObservationRegime = @import("../../model/ObservationModel.zig").ObservationRegime;
const SurfaceKind = @import("../../model/Surface.zig").Surface.Kind;
const DerivativeMode = @import("../../model/InverseProblem.zig").DerivativeMode;
const StateTransform = @import("../../model/StateVector.zig").Transform;
const ExportFormat = @import("../exporters/format.zig").ExportFormat;

pub const AssetKind = enum {
    file,
};

pub const IngestAdapter = enum {
    spectral_ascii,
};

pub const ProductKind = enum {
    measurement_space,
    state_vector,
    fitted_measurement,
    averaging_kernel,
    jacobian,
    posterior_covariance,
    result,
    diagnostics,
};

// --- Vendor-key identity layer ---
// These enums mirror the vendor (DISAMAR) config file structure and give each
// vendor concept a stable, typed identity inside the Zig codebase. They are the
// single source of truth for vendor method codes and scatterer classifications
// so that adapters and tests never rely on raw strings or magic integers.

/// Every vendor top-level config section. Used for inventory tracking and
/// coverage assertions in the vendor config surface matrix.
pub const VendorSection = enum {
    general,
    instrument,
    mul_offset,
    stray_light,
    rrs_ring,
    reference_data,
    geometry,
    pressure_temperature,
    absorbing_gas,
    surface,
    atmospheric_intervals,
    cloud_aerosol_fraction,
    cloud,
    aerosol,
    subcolumns,
    retrieval,
    radiative_transfer,
    additional_output,
};

/// Fidelity status of a vendor config key in the Zig parity matrix.
/// Used by the config surface matrix JSON and by execution-time validation.
pub const VendorCompatStatus = enum {
    /// Vendor control is expressible in canonical YAML, honored by runtime,
    /// and validated against one or more vendor cases.
    exact,
    /// Same scientific intent is represented, but runtime differs in a
    /// declared and bounded way; provenance and validation say so.
    approximate,
    /// Canonical YAML may expose a placeholder or reject the field explicitly,
    /// but the runtime does not pretend to honor it.
    unsupported,
    /// Parsed from config but NOT consumed by any runtime code path.
    /// This status is forbidden by the end of WP-01.
    parsed_but_not_honored,
};

/// Every vendor config subsection. These appear as the second level within a
/// vendor section (e.g. GENERAL/overall, INSTRUMENT/wavelength_range). The
/// canonical set is derived from the vendor config surface matrix.
pub const VendorSubsection = enum {
    // GENERAL subsections
    overall,
    fileNames,
    method,
    createLUT,
    createXsecLUT,
    specifications_DOAS_DISMAS,
    specifyFitting,
    external_data,

    // INSTRUMENT subsections
    wavelength_range,
    slit_index,
    slit_parameters,
    polScrambler,
    wavelShift,
    addGaussianNoise,
    SNR_irradiance,
    SNR_radiance,
    calibrationErrorRefl,
    simpleOffsets,
    sinusoidal_features,
    smear,

    // Sim/Retr split subsections (shared across multiple sections)
    simulation,
    retrieval,

    // REFERENCE_DATA subsections
    solarIrradiance,

    // GEOMETRY subsections
    geometry,

    // PRESSURE_TEMPERATURE subsections
    climatology,
    PT_sim,
    PT_retr,
    temperature_offset,
    specificationsT,
    filenames,

    // ABSORBING_GAS subsections
    profile,
    column,
    scaling,
    errorCovariancesSpecs,
    HITRAN,

    // SURFACE subsections
    surfaceType,
    wavelIndepSim,
    wavelIndepRetr,
    wavelDependentSim,
    wavelDependentRetr,
    pressure,

    // ATMOSPHERIC_INTERVALS subsections
    interval_top_pressures,

    // CLOUD_AEROSOL_FRACTION subsections
    fraction,
    thresholdVarSurfCldAlbedo,
    fractionType,
    wavelIndependentSim,
    wavelIndependentRetr,

    // CLOUD / AEROSOL subsections
    cloudType,
    aerosolType,
    LambWavelIndepSim,
    LambWavelIndepRetr,
    LambertianSim,
    LambertianRetr,
    HGscatteringSim,
    HGscatteringRetr,
    MieScatteringSim,
    MieScatteringRetr,

    // SUBCOLUMNS subsections
    subcolumns,

    // RETRIEVAL subsections
    retrieval_specs,

    // RADIATIVE_TRANSFER subsections
    numDivPointsWavel,
    numDivPointsWavelLineAbs,
    numDivPointsAlt,
    RTM_Sim_Retr,
    RTM,

    // ADDITIONAL_OUTPUT subsections
    additional,
};

/// Composite identifier for a vendor config control: section + subsection + key.
/// Used in coverage assertions and the support-status matrix so that tests can
/// enumerate the full vendor surface without scattering raw strings.
pub const VendorKeyId = struct {
    section: VendorSection,
    subsection: VendorSubsection,
    key: []const u8,
};

/// Section-level default fidelity classification derived from the vendor config
/// surface matrix. Individual keys may override this with a finer status, but
/// this gives the dominant picture per section.
pub fn sectionDefaultStatus(section: VendorSection) VendorCompatStatus {
    return switch (section) {
        // Sections with majority exact support
        .geometry => .exact,
        .radiative_transfer => .exact,
        .additional_output => .exact,
        .rrs_ring => .exact,
        // Sections with majority approximate support
        .surface => .approximate,
        .retrieval => .approximate,
        // Sections that are mostly or entirely unsupported
        .general => .unsupported,
        .instrument => .unsupported,
        .mul_offset => .unsupported,
        .stray_light => .unsupported,
        .reference_data => .unsupported,
        .pressure_temperature => .unsupported,
        .absorbing_gas => .unsupported,
        .atmospheric_intervals => .unsupported,
        .cloud_aerosol_fraction => .unsupported,
        .cloud => .unsupported,
        .aerosol => .unsupported,
        .subcolumns => .unsupported,
    };
}

/// Parse a vendor section name string (case-sensitive, underscore-delimited)
/// into the typed enum. Accepts both the Zig enum field name and the vendor
/// UPPER_CASE form used in the matrix JSON.
pub fn parseVendorSection(value: []const u8) Error!VendorSection {
    // Zig-style lowercase names
    const fields = @typeInfo(VendorSection).@"enum".fields;
    inline for (fields) |f| {
        if (std.mem.eql(u8, value, f.name)) return @enumFromInt(f.value);
    }
    // Vendor UPPER_CASE aliases from the matrix JSON
    const aliases = .{
        .{ "GENERAL", VendorSection.general },
        .{ "INSTRUMENT", VendorSection.instrument },
        .{ "MUL_OFFSET", VendorSection.mul_offset },
        .{ "STRAY_LIGHT", VendorSection.stray_light },
        .{ "RRS_RING", VendorSection.rrs_ring },
        .{ "REFERENCE_DATA", VendorSection.reference_data },
        .{ "GEOMETRY", VendorSection.geometry },
        .{ "PRESSURE_TEMPERATURE", VendorSection.pressure_temperature },
        .{ "ABSORBING_GAS", VendorSection.absorbing_gas },
        .{ "SURFACE", VendorSection.surface },
        .{ "ATMOSPHERIC_INTERVALS", VendorSection.atmospheric_intervals },
        .{ "CLOUD_AEROSOL_FRACTION", VendorSection.cloud_aerosol_fraction },
        .{ "CLOUD", VendorSection.cloud },
        .{ "AEROSOL", VendorSection.aerosol },
        .{ "SUBCOLUMNS", VendorSection.subcolumns },
        .{ "RETRIEVAL", VendorSection.retrieval },
        .{ "RADIATIVE_TRANSFER", VendorSection.radiative_transfer },
        .{ "ADDITIONAL_OUTPUT", VendorSection.additional_output },
    };
    inline for (aliases) |entry| {
        if (std.mem.eql(u8, value, entry[0])) return entry[1];
    }
    return error.InvalidValue;
}

/// Parse a vendor subsection name string into the typed enum.
pub fn parseVendorSubsection(value: []const u8) Error!VendorSubsection {
    const fields = @typeInfo(VendorSubsection).@"enum".fields;
    inline for (fields) |f| {
        if (std.mem.eql(u8, value, f.name)) return @enumFromInt(f.value);
    }
    return error.InvalidValue;
}

/// Vendor retrieval-method codes (maps to integer method IDs in the vendor file).
pub const RetrievalMethod = enum {
    oe, // 0 -- optimal estimation
    dismas, // 1
    doas, // 2
    classic_doas, // 3
    domino_no2, // 4
};

/// Vendor simulation-method codes.
pub const SimulationMethod = enum {
    oe_lbl, // 0 -- line-by-line OE
    dismas, // 1
};

/// Scattering order encoded in a 2-bit field matching vendor integer codes.
pub const ScatteringMode = enum(u2) {
    none = 0,
    single = 1,
    multiple = 2,
};

/// Cloud scatterer classification in the vendor config.
pub const CloudType = enum {
    none,
    lamb_wavel_indep,
    lambertian,
    mie_scattering,
    hg_scattering,
};

/// Aerosol scatterer classification (same variants as CloudType).
pub const AerosolType = enum {
    none,
    lamb_wavel_indep,
    lambertian,
    mie_scattering,
    hg_scattering,
};

/// Surface albedo wavelength dependence.
pub const SurfaceType = enum {
    wavel_independent,
    wavel_dependent,
};

/// Cloud/aerosol fraction wavelength dependence.
pub const FractionType = enum {
    wavel_independent,
    wavel_dependent,
};

/// All absorber species recognised in vendor config files.
pub const AbsorberSpecies = enum {
    o3,
    trop_o3,
    strat_o3,
    no2,
    trop_no2,
    strat_no2,
    so2,
    hcho,
    bro,
    chocho,
    o2_o2,
    o2,
    h2o,
    co2,
    ch4,
    co,
    nh3,

    /// Line-absorbing species use HITRAN line-by-line spectroscopy.
    pub fn isLineAbsorbing(self: AbsorberSpecies) bool {
        return switch (self) {
            .o2, .h2o, .co2, .ch4, .co, .nh3 => true,
            else => false,
        };
    }

    /// Cross-section species use tabulated absorption cross-sections.
    pub fn isCrossSection(self: AbsorberSpecies) bool {
        return switch (self) {
            .o3, .trop_o3, .strat_o3, .no2, .trop_no2, .strat_no2, .so2, .hcho, .bro, .chocho, .o2_o2 => true,
            else => false,
        };
    }

    /// Whether a total-column fit is meaningful for this species.
    pub fn isColumnFittable(self: AbsorberSpecies) bool {
        return switch (self) {
            .o2, .o2_o2 => false,
            else => true,
        };
    }

    /// Profile fitting eligibility follows column fitting eligibility.
    pub fn isProfileFittable(self: AbsorberSpecies) bool {
        return self.isColumnFittable();
    }

    /// HITRAN molecule index, or null for species without a HITRAN entry.
    pub fn hitranIndex(self: AbsorberSpecies) ?u8 {
        return switch (self) {
            .h2o => 1,
            .co2 => 2,
            .o3, .trop_o3, .strat_o3 => 3,
            .co => 5,
            .ch4 => 6,
            .o2 => 7,
            .so2 => 9,
            .no2, .trop_no2, .strat_no2 => 10,
            .nh3 => 11,
            else => null,
        };
    }

    /// Map a vendor config gas name string to the typed enum.
    pub fn fromVendorName(name: []const u8) ?AbsorberSpecies {
        const map = .{
            .{ "O3", .o3 },
            .{ "trop_O3", .trop_o3 },
            .{ "strat_O3", .strat_o3 },
            .{ "NO2", .no2 },
            .{ "trop_NO2", .trop_no2 },
            .{ "strat_NO2", .strat_no2 },
            .{ "SO2", .so2 },
            .{ "HCHO", .hcho },
            .{ "BrO", .bro },
            .{ "CHOCHO", .chocho },
            .{ "O2-O2", .o2_o2 },
            .{ "O2", .o2 },
            .{ "H2O", .h2o },
            .{ "CO2", .co2 },
            .{ "CH4", .ch4 },
            .{ "CO", .co },
            .{ "NH3", .nh3 },
        };
        inline for (map) |entry| {
            if (std.mem.eql(u8, name, entry[0])) return entry[1];
        }
        return null;
    }
};

/// Cloud scatterer classification in the vendor config.
/// Aerosol scatterer classification (same variants as CloudType).
/// Surface albedo wavelength dependence.
/// All absorber species recognised in vendor config files.
pub const Error = error{
    InvalidValue,
    UnsupportedIngestAdapter,
};

pub fn parseAssetKind(kind: []const u8) Error!AssetKind {
    if (std.mem.eql(u8, kind, "file")) return .file;
    return error.InvalidValue;
}

pub fn parseIngestAdapter(adapter: []const u8) Error!IngestAdapter {
    if (std.mem.eql(u8, adapter, "spectral_ascii")) return .spectral_ascii;
    return error.UnsupportedIngestAdapter;
}

pub fn parseSolverMode(value: []const u8) Error!SolverMode {
    if (std.mem.eql(u8, value, "scalar")) return .scalar;
    if (std.mem.eql(u8, value, "polarized")) return .polarized;
    if (std.mem.eql(u8, value, "derivative_enabled")) return .derivative_enabled;
    return error.InvalidValue;
}

pub fn parseDerivativeMode(value: []const u8) Error!DerivativeMode {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "semi_analytical")) return .semi_analytical;
    if (std.mem.eql(u8, value, "analytical_plugin")) return .analytical_plugin;
    if (std.mem.eql(u8, value, "numerical")) return .numerical;
    return error.InvalidValue;
}

pub fn parseGeometryModel(value: []const u8) Error!GeometryModel {
    if (std.mem.eql(u8, value, "plane_parallel")) return .plane_parallel;
    if (std.mem.eql(u8, value, "pseudo_spherical")) return .pseudo_spherical;
    if (std.mem.eql(u8, value, "spherical")) return .spherical;
    return error.InvalidValue;
}

pub fn parseObservationRegime(value: []const u8) Error!ObservationRegime {
    if (std.mem.eql(u8, value, "nadir")) return .nadir;
    if (std.mem.eql(u8, value, "limb")) return .limb;
    if (std.mem.eql(u8, value, "occultation")) return .occultation;
    return error.InvalidValue;
}

pub fn parseSamplingMode(value: []const u8) Error!Instrument.SamplingMode {
    return Instrument.SamplingMode.parse(value) catch error.InvalidValue;
}

pub fn parseNoiseModelKind(value: []const u8) Error!Instrument.NoiseModelKind {
    return Instrument.NoiseModelKind.parse(value) catch error.InvalidValue;
}

pub fn parseSurfaceKind(value: []const u8) Error!SurfaceKind {
    return SurfaceKind.parse(value) catch error.InvalidValue;
}

pub fn parseSpectroscopyMode(value: []const u8) Error!SpectroscopyMode {
    if (std.mem.eql(u8, value, "line_by_line")) return .line_by_line;
    if (std.mem.eql(u8, value, "cia")) return .cia;
    if (std.mem.eql(u8, value, "cross_sections")) return .cross_sections;
    return error.InvalidValue;
}

pub fn parseStateTransform(value: []const u8) Error!StateTransform {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "log")) return .log;
    if (std.mem.eql(u8, value, "logit")) return .logit;
    return error.InvalidValue;
}

pub fn parseProductKind(value: []const u8) Error!ProductKind {
    if (std.mem.eql(u8, value, "measurement_space")) return .measurement_space;
    if (std.mem.eql(u8, value, "state_vector")) return .state_vector;
    if (std.mem.eql(u8, value, "fitted_measurement")) return .fitted_measurement;
    if (std.mem.eql(u8, value, "averaging_kernel")) return .averaging_kernel;
    if (std.mem.eql(u8, value, "jacobian")) return .jacobian;
    if (std.mem.eql(u8, value, "posterior_covariance")) return .posterior_covariance;
    if (std.mem.eql(u8, value, "result")) return .result;
    if (std.mem.eql(u8, value, "diagnostics")) return .diagnostics;
    return error.InvalidValue;
}

pub fn parseExportFormat(value: []const u8) Error!ExportFormat {
    if (std.mem.eql(u8, value, "netcdf_cf")) return .netcdf_cf;
    if (std.mem.eql(u8, value, "zarr")) return .zarr;
    return error.InvalidValue;
}

pub fn normalizeTransportProvider(solver: []const u8, provider: []const u8) []const u8 {
    if (provider.len != 0) {
        if (std.mem.eql(u8, provider, "builtin.transport_dispatcher") or std.mem.eql(u8, provider, "builtin.dispatcher")) {
            return "builtin.dispatcher";
        }
        return provider;
    }
    if (std.mem.eql(u8, solver, "dispatcher") or std.mem.eql(u8, solver, "builtin.dispatcher") or std.mem.eql(u8, solver, "builtin.transport_dispatcher")) {
        return "builtin.dispatcher";
    }
    return "builtin.dispatcher";
}

pub fn normalizeRetrievalProvider(name: []const u8, explicit_provider: ?[]const u8) ?[]const u8 {
    if (explicit_provider) |provider| return provider;
    if (std.mem.eql(u8, name, "oe")) return "builtin.oe_solver";
    if (std.mem.eql(u8, name, "doas")) return "builtin.doas_solver";
    if (std.mem.eql(u8, name, "classic_doas")) return "builtin.doas_solver";
    if (std.mem.eql(u8, name, "dismas")) return "builtin.dismas_solver";
    if (std.mem.eql(u8, name, "domino_no2") or std.mem.eql(u8, name, "domino")) return "builtin.domino_solver";
    if (name.len == 0) return null;
    return name;
}

pub fn normalizeSurfaceProvider(explicit_provider: []const u8, model: SurfaceKind) []const u8 {
    if (explicit_provider.len != 0) return explicit_provider;
    return switch (model) {
        .lambertian => "builtin.lambertian_surface",
        .wavel_dependent => "builtin.wavel_dependent_surface",
    };
}

pub fn parseCloudType(value: []const u8) Error!CloudType {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "lamb_wavel_indep")) return .lamb_wavel_indep;
    if (std.mem.eql(u8, value, "lambertian") or std.mem.eql(u8, value, "legacy_binary_cloud")) return .lambertian;
    if (std.mem.eql(u8, value, "mie_scattering") or std.mem.eql(u8, value, "mie")) return .mie_scattering;
    if (std.mem.eql(u8, value, "hg_scattering") or std.mem.eql(u8, value, "hg") or std.mem.eql(u8, value, "hg_layer")) return .hg_scattering;
    return error.InvalidValue;
}

pub fn parseAerosolType(value: []const u8) Error!AerosolType {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "lamb_wavel_indep")) return .lamb_wavel_indep;
    if (std.mem.eql(u8, value, "lambertian") or std.mem.eql(u8, value, "legacy_binary_aerosol")) return .lambertian;
    if (std.mem.eql(u8, value, "mie_scattering") or std.mem.eql(u8, value, "mie")) return .mie_scattering;
    if (std.mem.eql(u8, value, "hg_scattering") or std.mem.eql(u8, value, "hg") or std.mem.eql(u8, value, "hg_layer")) return .hg_scattering;
    return error.InvalidValue;
}

pub fn parseSurfaceType(value: []const u8) Error!SurfaceType {
    if (std.mem.eql(u8, value, "wavel_independent")) return .wavel_independent;
    if (std.mem.eql(u8, value, "wavel_dependent")) return .wavel_dependent;
    return error.InvalidValue;
}

pub fn parseAbsorberSpecies(value: []const u8) Error!AbsorberSpecies {
    return AbsorberSpecies.fromVendorName(value) orelse
        std.meta.stringToEnum(AbsorberSpecies, value) orelse
        error.InvalidValue;
}

pub fn normalizeInstrumentProvider(explicit_provider: []const u8, instrument_id: InstrumentId) []const u8 {
    if (explicit_provider.len != 0) return explicit_provider;
    _ = instrument_id;
    return "builtin.generic_response";
}

// --- Parse functions for vendor identity enums ---

pub fn parseRetrievalMethod(value: []const u8) Error!RetrievalMethod {
    if (std.mem.eql(u8, value, "oe")) return .oe;
    if (std.mem.eql(u8, value, "dismas")) return .dismas;
    if (std.mem.eql(u8, value, "doas")) return .doas;
    if (std.mem.eql(u8, value, "classic_doas")) return .classic_doas;
    if (std.mem.eql(u8, value, "domino_no2") or std.mem.eql(u8, value, "domino")) return .domino_no2;
    return error.InvalidValue;
}

pub fn parseSimulationMethod(value: []const u8) Error!SimulationMethod {
    if (std.mem.eql(u8, value, "oe_lbl")) return .oe_lbl;
    if (std.mem.eql(u8, value, "dismas")) return .dismas;
    return error.InvalidValue;
}

pub fn parseScatteringMode(value: []const u8) Error!ScatteringMode {
    if (std.mem.eql(u8, value, "none") or std.mem.eql(u8, value, "0")) return .none;
    if (std.mem.eql(u8, value, "single") or std.mem.eql(u8, value, "1")) return .single;
    if (std.mem.eql(u8, value, "multiple") or std.mem.eql(u8, value, "2")) return .multiple;
    return error.InvalidValue;
}

pub fn parseFractionType(value: []const u8) Error!FractionType {
    if (std.mem.eql(u8, value, "wavel_independent")) return .wavel_independent;
    if (std.mem.eql(u8, value, "wavel_dependent")) return .wavel_dependent;
    return error.InvalidValue;
}

// --- Tests ---

test "parseRetrievalMethod covers all vendor methods" {
    try std.testing.expectEqual(RetrievalMethod.oe, try parseRetrievalMethod("oe"));
    try std.testing.expectEqual(RetrievalMethod.dismas, try parseRetrievalMethod("dismas"));
    try std.testing.expectEqual(RetrievalMethod.doas, try parseRetrievalMethod("doas"));
    try std.testing.expectEqual(RetrievalMethod.classic_doas, try parseRetrievalMethod("classic_doas"));
    try std.testing.expectEqual(RetrievalMethod.domino_no2, try parseRetrievalMethod("domino_no2"));
    try std.testing.expectEqual(RetrievalMethod.domino_no2, try parseRetrievalMethod("domino"));
}

test "parseRetrievalMethod rejects unknown method" {
    try std.testing.expectError(error.InvalidValue, parseRetrievalMethod("unknown"));
}

test "parseSimulationMethod covers all variants" {
    try std.testing.expectEqual(SimulationMethod.oe_lbl, try parseSimulationMethod("oe_lbl"));
    try std.testing.expectEqual(SimulationMethod.dismas, try parseSimulationMethod("dismas"));
    try std.testing.expectError(error.InvalidValue, parseSimulationMethod("bogus"));
}

test "parseScatteringMode accepts names and integer strings" {
    try std.testing.expectEqual(ScatteringMode.none, try parseScatteringMode("none"));
    try std.testing.expectEqual(ScatteringMode.none, try parseScatteringMode("0"));
    try std.testing.expectEqual(ScatteringMode.single, try parseScatteringMode("single"));
    try std.testing.expectEqual(ScatteringMode.single, try parseScatteringMode("1"));
    try std.testing.expectEqual(ScatteringMode.multiple, try parseScatteringMode("multiple"));
    try std.testing.expectEqual(ScatteringMode.multiple, try parseScatteringMode("2"));
}

test "ScatteringMode backing integer values" {
    try std.testing.expectEqual(@as(u2, 0), @intFromEnum(ScatteringMode.none));
    try std.testing.expectEqual(@as(u2, 1), @intFromEnum(ScatteringMode.single));
    try std.testing.expectEqual(@as(u2, 2), @intFromEnum(ScatteringMode.multiple));
}

test "parseCloudType and parseAerosolType accept shared variants" {
    const shared = .{ "none", "lamb_wavel_indep", "lambertian", "mie_scattering", "hg_scattering" };
    inline for (shared) |name| {
        _ = try parseCloudType(name);
        _ = try parseAerosolType(name);
    }
    // Short aliases
    try std.testing.expectEqual(CloudType.mie_scattering, try parseCloudType("mie"));
    try std.testing.expectEqual(AerosolType.hg_scattering, try parseAerosolType("hg"));
    // Legacy alias
    try std.testing.expectEqual(CloudType.hg_scattering, try parseCloudType("hg_layer"));
    try std.testing.expectEqual(AerosolType.hg_scattering, try parseAerosolType("hg_layer"));
}

test "parseSurfaceType and parseFractionType" {
    try std.testing.expectEqual(SurfaceType.wavel_independent, try parseSurfaceType("wavel_independent"));
    try std.testing.expectEqual(SurfaceType.wavel_dependent, try parseSurfaceType("wavel_dependent"));
    try std.testing.expectEqual(FractionType.wavel_independent, try parseFractionType("wavel_independent"));
    try std.testing.expectEqual(FractionType.wavel_dependent, try parseFractionType("wavel_dependent"));
}

test "AbsorberSpecies.fromVendorName round-trips all species" {
    const testing = std.testing;
    try testing.expectEqual(AbsorberSpecies.o3, AbsorberSpecies.fromVendorName("O3").?);
    try testing.expectEqual(AbsorberSpecies.trop_o3, AbsorberSpecies.fromVendorName("trop_O3").?);
    try testing.expectEqual(AbsorberSpecies.strat_o3, AbsorberSpecies.fromVendorName("strat_O3").?);
    try testing.expectEqual(AbsorberSpecies.no2, AbsorberSpecies.fromVendorName("NO2").?);
    try testing.expectEqual(AbsorberSpecies.trop_no2, AbsorberSpecies.fromVendorName("trop_NO2").?);
    try testing.expectEqual(AbsorberSpecies.strat_no2, AbsorberSpecies.fromVendorName("strat_NO2").?);
    try testing.expectEqual(AbsorberSpecies.so2, AbsorberSpecies.fromVendorName("SO2").?);
    try testing.expectEqual(AbsorberSpecies.hcho, AbsorberSpecies.fromVendorName("HCHO").?);
    try testing.expectEqual(AbsorberSpecies.bro, AbsorberSpecies.fromVendorName("BrO").?);
    try testing.expectEqual(AbsorberSpecies.chocho, AbsorberSpecies.fromVendorName("CHOCHO").?);
    try testing.expectEqual(AbsorberSpecies.o2_o2, AbsorberSpecies.fromVendorName("O2-O2").?);
    try testing.expectEqual(AbsorberSpecies.o2, AbsorberSpecies.fromVendorName("O2").?);
    try testing.expectEqual(AbsorberSpecies.h2o, AbsorberSpecies.fromVendorName("H2O").?);
    try testing.expectEqual(AbsorberSpecies.co2, AbsorberSpecies.fromVendorName("CO2").?);
    try testing.expectEqual(AbsorberSpecies.ch4, AbsorberSpecies.fromVendorName("CH4").?);
    try testing.expectEqual(AbsorberSpecies.co, AbsorberSpecies.fromVendorName("CO").?);
    try testing.expectEqual(AbsorberSpecies.nh3, AbsorberSpecies.fromVendorName("NH3").?);
    try testing.expect(AbsorberSpecies.fromVendorName("UNKNOWN") == null);
}

test "AbsorberSpecies classification methods are consistent" {
    // Every species must be exactly one of line-absorbing or cross-section.
    const all = std.enums.values(AbsorberSpecies);
    for (all) |species| {
        const is_line = species.isLineAbsorbing();
        const is_xs = species.isCrossSection();
        try std.testing.expect(is_line != is_xs);
    }
}

test "AbsorberSpecies.hitranIndex returns non-null for line-absorbing species" {
    const line_species = [_]AbsorberSpecies{ .o2, .h2o, .co2, .ch4, .co, .nh3 };
    for (line_species) |species| {
        try std.testing.expect(species.hitranIndex() != null);
    }
}

// --- Vendor identity layer tests ---

test "parseVendorSection accepts Zig field names" {
    try std.testing.expectEqual(VendorSection.general, try parseVendorSection("general"));
    try std.testing.expectEqual(VendorSection.instrument, try parseVendorSection("instrument"));
    try std.testing.expectEqual(VendorSection.radiative_transfer, try parseVendorSection("radiative_transfer"));
    try std.testing.expectEqual(VendorSection.additional_output, try parseVendorSection("additional_output"));
}

test "parseVendorSection accepts vendor UPPER_CASE names" {
    try std.testing.expectEqual(VendorSection.general, try parseVendorSection("GENERAL"));
    try std.testing.expectEqual(VendorSection.rrs_ring, try parseVendorSection("RRS_RING"));
    try std.testing.expectEqual(VendorSection.cloud_aerosol_fraction, try parseVendorSection("CLOUD_AEROSOL_FRACTION"));
    try std.testing.expectEqual(VendorSection.additional_output, try parseVendorSection("ADDITIONAL_OUTPUT"));
}

test "parseVendorSection rejects unknown section" {
    try std.testing.expectError(error.InvalidValue, parseVendorSection("NONEXISTENT"));
}

test "parseVendorSubsection covers representative subsections" {
    try std.testing.expectEqual(VendorSubsection.overall, try parseVendorSubsection("overall"));
    try std.testing.expectEqual(VendorSubsection.fileNames, try parseVendorSubsection("fileNames"));
    try std.testing.expectEqual(VendorSubsection.method, try parseVendorSubsection("method"));
    try std.testing.expectEqual(VendorSubsection.wavelength_range, try parseVendorSubsection("wavelength_range"));
    try std.testing.expectEqual(VendorSubsection.slit_parameters, try parseVendorSubsection("slit_parameters"));
    try std.testing.expectEqual(VendorSubsection.RTM_Sim_Retr, try parseVendorSubsection("RTM_Sim_Retr"));
    try std.testing.expectEqual(VendorSubsection.additional, try parseVendorSubsection("additional"));
    try std.testing.expectEqual(VendorSubsection.simulation, try parseVendorSubsection("simulation"));
    try std.testing.expectEqual(VendorSubsection.retrieval, try parseVendorSubsection("retrieval"));
    try std.testing.expectEqual(VendorSubsection.cloudType, try parseVendorSubsection("cloudType"));
    try std.testing.expectEqual(VendorSubsection.aerosolType, try parseVendorSubsection("aerosolType"));
}

test "parseVendorSubsection rejects unknown subsection" {
    try std.testing.expectError(error.InvalidValue, parseVendorSubsection("bogus_subsection"));
}

test "sectionDefaultStatus returns exact for geometry" {
    try std.testing.expectEqual(VendorCompatStatus.exact, sectionDefaultStatus(.geometry));
    try std.testing.expectEqual(VendorCompatStatus.exact, sectionDefaultStatus(.radiative_transfer));
    try std.testing.expectEqual(VendorCompatStatus.exact, sectionDefaultStatus(.additional_output));
    try std.testing.expectEqual(VendorCompatStatus.exact, sectionDefaultStatus(.rrs_ring));
}

test "sectionDefaultStatus returns approximate for surface and retrieval" {
    try std.testing.expectEqual(VendorCompatStatus.approximate, sectionDefaultStatus(.surface));
    try std.testing.expectEqual(VendorCompatStatus.approximate, sectionDefaultStatus(.retrieval));
}

test "sectionDefaultStatus returns unsupported for non-parity sections" {
    const unsupported_sections = [_]VendorSection{
        .general,       .instrument,            .mul_offset,
        .stray_light,   .reference_data,        .pressure_temperature,
        .absorbing_gas, .atmospheric_intervals, .cloud_aerosol_fraction,
        .cloud,         .aerosol,               .subcolumns,
    };
    for (unsupported_sections) |section| {
        try std.testing.expectEqual(VendorCompatStatus.unsupported, sectionDefaultStatus(section));
    }
}

test "sectionDefaultStatus is exhaustive over VendorSection" {
    // Ensures every VendorSection variant is handled (compile-time guarantee
    // from the switch, but this test documents the intent for coverage).
    const all = std.enums.values(VendorSection);
    for (all) |section| {
        const status = sectionDefaultStatus(section);
        try std.testing.expect(status == .exact or status == .approximate or status == .unsupported);
    }
}

test "VendorKeyId can represent a section/subsection/key triple" {
    const key_id = VendorKeyId{
        .section = .geometry,
        .subsection = .geometry,
        .key = "SolarZenithAngle_Sim",
    };
    try std.testing.expectEqual(VendorSection.geometry, key_id.section);
    try std.testing.expectEqual(VendorSubsection.geometry, key_id.subsection);
    try std.testing.expect(std.mem.eql(u8, "SolarZenithAngle_Sim", key_id.key));
}

test "normalizeRetrievalProvider handles classic_doas and domino" {
    // classic_doas maps to the DOAS solver
    const classic = normalizeRetrievalProvider("classic_doas", null);
    try std.testing.expect(classic != null);
    try std.testing.expect(std.mem.eql(u8, "builtin.doas_solver", classic.?));

    // domino_no2 maps to the DOMINO solver
    const domino = normalizeRetrievalProvider("domino_no2", null);
    try std.testing.expect(domino != null);
    try std.testing.expect(std.mem.eql(u8, "builtin.domino_solver", domino.?));

    // Short alias "domino" also maps to DOMINO solver
    const domino_short = normalizeRetrievalProvider("domino", null);
    try std.testing.expect(domino_short != null);
    try std.testing.expect(std.mem.eql(u8, "builtin.domino_solver", domino_short.?));
}
