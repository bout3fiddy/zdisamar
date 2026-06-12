const std = @import("std");

const controls = @import("transport/controls.zig");
const hashing = @import("common/hashing.zig");
const defaults = @import("input/defaults.zig");
const input_json = @import("input/json.zig");
const jacobian_states = @import("transport/jacobian_states.zig");
const layer_depths = @import("optics/layer_depths.zig");
const o2_case = @import("input/o2_case.zig");
const o2_session_memory = @import("cache/o2_session_memory.zig");
const atmospheric_budget = @import("output/atmospheric_budget.zig");
const instrument_response = @import("output/instrument_response.zig");
const o2_line_contributions = @import("output/o2_line_contributions.zig");
const o2_o2_cia = @import("output/o2_o2_cia.zig");
const o2_spectrum = @import("output/spectrum.zig");
const radiance_results = @import("spectrum/radiance_results.zig");
const radiance_wavelengths = @import("spectrum/radiance_wavelengths.zig");
const setup_tables = @import("setup/o2_run_tables.zig");
const profile_lines = @import("cache/profile_line_memory.zig");
const sampling_table = @import("spectrum/sampling_table.zig");
const solve = @import("transport/solve.zig");
const source_levels = @import("optics/source_levels.zig");
const spectrum_run = @import("spectrum/spectrum_run.zig");
const curved_sun_path = @import("optics/curved_sun_path.zig");

const Allocator = std.mem.Allocator;

// root.zig ---------------------------------------------------------------------------------------------------|
// Public explicit-dataflow surface for the O2 A forward model.                                                |
//                                                                                                             |
// public flow                                                                                                 |
//   defaultO2Case -> prepareO2A -> warmO2ASessionMemory -> runO2AWithSessionMemory                            |
//                                                                                                             |
// boundary                                                                                                    |
//   The root facade owns preparation/run composition only. Setup tables, session caches, spectrum workers,    |
//   and output rows still live in named modules with explicit inputs. C/Python will call this file through    |
//   `src/api/c.zig`; compute code receives typed rows and never sees a C context.                             |
// ------------------------------------------------------------------------------------------------------------|

pub const O2Case = o2_case.O2Case;
pub const O2RunTables = setup_tables.O2RunTables;
pub const ProfileLineValues = profile_lines.ProfileLineValues;
pub const O2SessionMemory = o2_session_memory.O2SessionMemory;
pub const AtmosphericBudget = atmospheric_budget.AtmosphericBudget;
pub const AtmosphericBudgetRow = atmospheric_budget.AtmosphericBudgetRow;
pub const InstrumentResponse = instrument_response.InstrumentResponse;
pub const InstrumentResponseRow = instrument_response.InstrumentResponseRow;
pub const O2LineContributions = o2_line_contributions.O2LineContributions;
pub const O2LineContributionRow = o2_line_contributions.O2LineContributionRow;
pub const O2O2CIADiagnostics = o2_o2_cia.O2O2CIADiagnostics;
pub const O2O2CIARow = o2_o2_cia.O2O2CIARow;
pub const O2Spectrum = o2_spectrum.O2Spectrum;
pub const O2SpectrumRunResult = o2_spectrum.O2SpectrumRunResult;
pub const O2SpectrumRunSummary = o2_spectrum.O2SpectrumRunSummary;
pub const SolveConfig = controls.SolveConfig;
pub const TransportControls = controls.TransportControls;
pub const JacobianVector = jacobian_states.Vector;
pub const ParsedO2CaseJson = input_json.ParsedO2CaseJson;
pub const jacobian_state_count = jacobian_states.state_count;

pub const defaultO2Case = defaults.referenceCase;
pub const parseO2CaseJson = input_json.parseO2CaseJson;
pub const renderDefaultO2CaseJson = input_json.renderDefaultO2CaseJson;
pub const buildO2RunTables = setup_tables.buildO2RunTables;
pub const buildO2ProfileLineValues = profile_lines.buildO2ProfileLineValues;

// PreparedO2A ------------------------------------------------------------------------------------------------|
// Public owner for parsed/default O2 A controls and setup tables.                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 2560 B (2.500 KiB), align: 8                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [   0.. 623] case  : O2Case                                                                                 |
// [ 624..2559] tables: O2RunTables                                                                            |
//                                                                                                             |
// referenced storage                                                                                          |
//   case borrows control strings/slices. tables owns loaded physical setup arrays and scalar tables.          |
pub const PreparedO2A = struct {
    case: O2Case,
    tables: O2RunTables,

    pub fn deinit(self: *PreparedO2A, allocator: Allocator) void {
        // PreparedO2A.deinit ---------------------------------------------------------------------------------|
        // Release setup tables; case strings and static/default slices are borrowed.                          |
        // ----------------------------------------------------------------------------------------------------|
        self.tables.deinit(allocator);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn deinitO2RunTables(allocator: Allocator, tables: *O2RunTables) void {
    // deinitO2RunTables --------------------------------------------------------------------------------------|
    // Public teardown wrapper for callers that own O2 A setup tables.                                         |
    // --------------------------------------------------------------------------------------------------------|
    tables.deinit(allocator);
}

pub fn initO2SessionMemory(allocator: Allocator) O2SessionMemory {
    // initO2SessionMemory ------------------------------------------------------------------------------------|
    // Create an empty reusable O2 A session cache.                                                            |
    // --------------------------------------------------------------------------------------------------------|
    return O2SessionMemory.init(allocator);
}

pub fn prepareO2A(allocator: Allocator, case: O2Case) !PreparedO2A {
    // prepareO2A ---------------------------------------------------------------------------------------------|
    // Build the O2 A setup tables retained across forward runs.                                               |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .case = case,
        .tables = try buildO2RunTables(allocator, case),
    };
}

pub fn warmO2ASessionMemory(
    allocator: Allocator,
    session: *O2SessionMemory,
    prepared: *const PreparedO2A,
    solve_config: SolveConfig,
) !void {
    // warmO2ASessionMemory -----------------------------------------------------------------------------------|
    // Materialize reusable spectrum, radiance, profile-line, solar, and transport memory for one case.        |
    // --------------------------------------------------------------------------------------------------------|
    _ = try prepareSessionRows(allocator, session, prepared, solve_config);
}

pub fn runO2AWithSessionMemory(
    allocator: Allocator,
    session: *O2SessionMemory,
    prepared: *const PreparedO2A,
    solve_config: SolveConfig,
) !O2SpectrumRunResult {
    // runO2AWithSessionMemory --------------------------------------------------------------------------------|
    // Run the O2 A product-grid spectrum through caller-retained session memory and return owned arrays.      |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Root-level orchestration follows the Stage 3 parity route in                                          |
    //   `tests/unit/spectrum/spectrum_run_test.zig`                                                           |
    //   and ports main:`src/root.zig` `runO2AWithSessionStorage` as a narrow facade over explicit owners.     |
    // --------------------------------------------------------------------------------------------------------|
    const prepared_rows = try prepareSessionRows(allocator, session, prepared, solve_config);
    const table = prepared_rows.table;
    const wavelengths = session.radiance.wavelengthList();
    const product_count = table.rows.len;
    const support_count = prepared.tables.layers.support_mid_altitudes_km.len;
    const layer_count = prepared.tables.layers.layer_pressures_hpa.len;

    var result = O2SpectrumRunResult{
        .spectrum = .{
            .wavelength_nm = try allocator.alloc(f64, product_count),
            .radiance = &.{},
            .irradiance = &.{},
            .reflectance = &.{},
            .jacobian = &.{},
        },
    };
    errdefer result.deinit(allocator);
    result.spectrum.radiance = try allocator.alloc(f64, product_count);
    result.spectrum.irradiance = try allocator.alloc(f64, product_count);
    result.spectrum.reflectance = try allocator.alloc(f64, product_count);
    result.spectrum.jacobian = try allocator.alloc(jacobian_states.Vector, product_count);

    const raw_radiance = try allocator.alloc(radiance_results.RadianceResult, product_count);
    defer allocator.free(raw_radiance);
    const raw_irradiance = try allocator.alloc(f64, product_count);
    defer allocator.free(raw_irradiance);
    const product_radiance = try allocator.alloc(radiance_results.RadianceResult, product_count);
    defer allocator.free(product_radiance);
    const line_sigma = try allocator.alloc(f64, support_count);
    defer allocator.free(line_sigma);
    const support = try allocator.alloc(layer_depths.SupportOptics, support_count);
    defer allocator.free(support);
    const layers = try allocator.alloc(layer_depths.LayerOptics, layer_count);
    defer allocator.free(layers);
    const source_rows = try allocator.alloc(source_levels.SourceLevel, layer_count + 1);
    defer allocator.free(source_rows);
    const curved_samples = try allocator.alloc(curved_sun_path.CurvedSunPathSample, support_count);
    defer allocator.free(curved_samples);
    const curved_level_starts = try allocator.alloc(usize, layer_count + 1);
    defer allocator.free(curved_level_starts);
    const curved_level_altitudes = try allocator.alloc(f64, layer_count + 1);
    defer allocator.free(curved_level_altitudes);

    const summary = try spectrum_run.runO2ASpectrumSingleWorker(
        table,
        wavelengths,
        viewAngles(prepared.case),
        prepared.case.surface_albedo,
        prepared.tables.layers,
        session.profile_lines,
        prepared.tables.cia,
        prepared.tables.aerosol,
        prepared.tables.phase,
        prepared.tables.solar,
        solve_config,
        true,
        true,
        .{},
        .{},
        &.{},
        &.{},
        session.radiance.resultRows(),
        result.spectrum.wavelength_nm,
        raw_radiance,
        raw_irradiance,
        product_radiance,
        result.spectrum.irradiance,
        result.spectrum.reflectance,
        result.spectrum.jacobian,
        line_sigma,
        support,
        layers,
        source_rows,
        curved_samples,
        curved_level_starts,
        curved_level_altitudes,
        &session.transport_workers,
        &session.solar_irradiance,
    );

    for (product_radiance, result.spectrum.radiance) |row, *radiance| {
        radiance.* = row.radiance;
    }
    result.summary.reflectance_assembly = summary;
    return result;
}

pub fn runO2A(allocator: Allocator, prepared: *const PreparedO2A, solve_config: SolveConfig) !O2SpectrumRunResult {
    // runO2A -------------------------------------------------------------------------------------------------|
    // Run one O2 A spectrum with a short-lived session memory owner.                                          |
    // --------------------------------------------------------------------------------------------------------|
    var session = initO2SessionMemory(allocator);
    defer session.deinit(allocator);
    return runO2AWithSessionMemory(allocator, &session, prepared, solve_config);
}

pub fn buildAtmosphericBudget(
    allocator: Allocator,
    prepared: *const PreparedO2A,
    wavelengths_nm: []const f64,
) !AtmosphericBudget {
    // buildAtmosphericBudget ---------------------------------------------------------------------------------|
    // Build public atmospheric support-row diagnostic rows for the prepared O2 A case.                        |
    // --------------------------------------------------------------------------------------------------------|
    return atmospheric_budget.build(allocator, prepared.case, &prepared.tables, wavelengths_nm);
}

pub fn buildO2O2CIADiagnostics(
    allocator: Allocator,
    prepared: *const PreparedO2A,
    wavelengths_nm: []const f64,
) !O2O2CIADiagnostics {
    // buildO2O2CIADiagnostics --------------------------------------------------------------------------------|
    // Build public O2-O2 CIA diagnostic rows from atmospheric-budget support rows.                            |
    // --------------------------------------------------------------------------------------------------------|
    var budget = try buildAtmosphericBudget(allocator, prepared, wavelengths_nm);
    defer budget.deinit(allocator);
    return o2_o2_cia.build(allocator, budget);
}

pub fn buildO2LineContributions(
    allocator: Allocator,
    prepared: *const PreparedO2A,
    wavelengths_nm: []const f64,
    max_rows: usize,
) !O2LineContributions {
    // buildO2LineContributions -------------------------------------------------------------------------------|
    // Build public O2 line-by-line diagnostic rows for caller-selected wavelengths.                           |
    // --------------------------------------------------------------------------------------------------------|
    return o2_line_contributions.build(allocator, &prepared.tables, wavelengths_nm, max_rows);
}

pub fn buildInstrumentResponse(
    allocator: Allocator,
    prepared: *const PreparedO2A,
    wavelengths_nm: []const f64,
    channel_mask: u32,
) !InstrumentResponse {
    // buildInstrumentResponse --------------------------------------------------------------------------------|
    // Build public instrument-response support rows for caller-selected wavelengths and channels.             |
    // --------------------------------------------------------------------------------------------------------|
    return instrument_response.build(
        allocator,
        prepared.case,
        &prepared.tables,
        wavelengths_nm,
        channel_mask,
    );
}

pub fn o2aSolveConfig(case: O2Case) SolveConfig {
    // o2aSolveConfig -----------------------------------------------------------------------------------------|
    // Build the exercised O2 A transport controls used by Stage 2/3 parity evidence.                          |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .derivative_mode = .semi_analytical,
        .derivative_state_mask = jacobian_states.stateMask(.aerosol_optical_depth) |
            jacobian_states.stateMask(.aerosol_layer_mid_pressure_hpa),
        .controls = .{
            .scattering = .multiple,
            .n_streams = @intCast(case.rtm.stream_count),
            .performance_thresholds = controls.PerformanceThresholds.o2a_default,
            .use_spherical_correction = case.geometry.pseudo_spherical,
            .integrate_source_function = true,
            .renorm_phase_function = true,
        },
    };
}

const PreparedSessionRows = struct {
    table: sampling_table.SpectrumSamplingTable,
};

fn prepareSessionRows(
    allocator: Allocator,
    session: *O2SessionMemory,
    prepared: *const PreparedO2A,
    solve_config: SolveConfig,
) !PreparedSessionRows {
    // prepareSessionRows -------------------------------------------------------------------------------------|
    // Rebuild shape rows and retain expensive profile-line values when the exact wavelength stamp matches.    |
    // --------------------------------------------------------------------------------------------------------|
    var owned_sampling = try sampling_table.buildO2SpectrumSamplingTable(
        allocator,
        prepared.case,
        prepared.tables.instrument,
        prepared.tables.lines,
    );
    defer owned_sampling.deinit(allocator);
    const row_count = owned_sampling.rows.len;
    const side_sample_count = owned_sampling.kernel_offsets_nm.len;
    session.spectrum.takeTable(allocator, &owned_sampling);
    const table = try session.spectrum.table(row_count, side_sample_count);

    var owned_wavelengths = try radiance_wavelengths.buildRadianceWavelengthList(allocator, table);
    defer owned_wavelengths.deinit(allocator);
    const dense_count = owned_wavelengths.wavelengths.len;
    const exact_wavelengths = try allocator.alloc(f64, dense_count);
    defer allocator.free(exact_wavelengths);
    for (owned_wavelengths.wavelengths, exact_wavelengths) |row, *wavelength_nm| {
        wavelength_nm.* = row.wavelength_nm;
    }
    const profile_stamp = profileLineReuseStamp(prepared.case.id, exact_wavelengths);

    session.radiance.takeWavelengthList(allocator, &owned_wavelengths);
    try session.radiance.ensureResultCapacity(allocator, dense_count);

    const cache_matches = session.profile_lines.reuse_stamp.eql(profile_stamp) and
        session.profile_lines.wavelength_count == dense_count;
    if (!cache_matches) {
        session.profile_lines.deinit(allocator);
        session.profile_lines =
            try profile_lines.buildO2ProfileLineValuesForWavelengthsWithCutoffGrid(
                allocator,
                prepared.case,
                exact_wavelengths,
                exact_wavelengths,
            );
    }

    const layer_count = prepared.tables.layers.layer_pressures_hpa.len;
    const phase_max_index = @max(prepared.tables.phase.aerosol_phase_max_index, @as(usize, 2));
    const fourier_max_index = solve_config.controls.performance_thresholds.cappedFourierMax(phase_max_index);
    try session.transport_workers.ensureCapacity(
        allocator,
        layer_count + 1,
        solve_config.controls.n_streams,
        @min(phase_max_index, fourier_max_index) + 1,
        fourier_max_index + 1,
        true,
    );
    return .{ .table = table };
}

fn profileLineReuseStamp(case_id: []const u8, wavelengths_nm: []const f64) hashing.ReuseStamp {
    // profileLineReuseStamp ----------------------------------------------------------------------------------|
    // Match the profile-line builder's retained-cache identity for one exact radiance wavelength list.        |
    // --------------------------------------------------------------------------------------------------------|
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(case_id);
    hasher.update(std.mem.sliceAsBytes(wavelengths_nm));
    return .{ .value = hasher.final() };
}

fn viewAngles(case: O2Case) solve.ViewAngles {
    // viewAngles ---------------------------------------------------------------------------------------------|
    // Convert public geometry degrees into the old forward-layer transport angle convention.                  |
    // --------------------------------------------------------------------------------------------------------|
    const solar_sin = @sin(std.math.degreesToRadians(case.geometry.solar_zenith_deg));
    const view_sin = @sin(std.math.degreesToRadians(case.geometry.viewing_zenith_deg));
    return .{
        .solar_mu = @sqrt(@max(1.0 - solar_sin * solar_sin, 0.0)),
        .view_mu = @sqrt(@max(1.0 - view_sin * view_sin, 0.0)),

        // main:`forward_model/optical_properties/state_build/forward_layers.zig` transport_dphi_rad.
        .relative_azimuth_rad = std.math.degreesToRadians(@mod(180.0 - case.geometry.relative_azimuth_deg, 360.0)),
    };
}
