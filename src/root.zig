const std = @import("std");

const controls = @import("rtm/controls.zig");
const hashing = @import("common/hashing.zig");
const defaults = @import("input/defaults.zig");
const input_json = @import("input/json.zig");
const input_validate = @import("input/validate.zig");
const jacobian_states = @import("rtm/jacobian_states.zig");
const o2_case = @import("input/o2_case.zig");
const o2_session_memory = @import("cache/o2_session_memory.zig");
const atmospheric_budget = @import("output/atmospheric_budget.zig");
const instrument_response = @import("output/instrument_response.zig");
const instrument_tables = @import("setup/instrument_tables.zig");
const o2_line_contributions = @import("output/o2_line_contributions.zig");
const o2_o2_cia = @import("output/o2_o2_cia.zig");
const o2_spectrum = @import("output/spectrum.zig");
const retrieval = @import("retrieval/root.zig");
const retrieval_algebra = @import("retrieval/algebra.zig");
const radiance_results = @import("spectrum/radiance_results.zig");
const radiance_wavelengths = @import("spectrum/radiance_wavelengths.zig");
const aerosol_tables = @import("setup/aerosol_tables.zig");
const atmosphere_layers = @import("setup/atmosphere_layers.zig");
const cia_table = @import("setup/cia_table.zig");
const phase_table = @import("setup/phase_table.zig");
const setup_tables = @import("setup/o2_run_tables.zig");
const line_tables = @import("setup/line_tables.zig");
const solar_table = @import("setup/solar_table.zig");
const profile_lines = @import("cache/profile_line_memory.zig");
const sampling_table = @import("spectrum/sampling_table.zig");
const solve = @import("rtm/solve.zig");
const spectrum_run = @import("spectrum/spectrum_run.zig");

const Allocator = std.mem.Allocator;

// root.zig ---------------------------------------------------------------------------------------------------|
// Public explicit row surface for the O2 A forward model.                                                     |
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
pub const optimal_estimation = retrieval;
pub const RetrievalStateSpec = retrieval.StateSpec;
pub const RetrievalPressureAltitudeProfile = retrieval.PressureAltitudeProfile;
pub const RetrievalResult = retrieval.Result;
pub const RetrievalBatchResult = retrieval.BatchResult;
pub const RetrievalFastmodeBatchResult = retrieval.FastmodeBatchResult;
pub const SolveConfig = controls.SolveConfig;
pub const TransportControls = controls.TransportControls;
pub const JacobianState = jacobian_states.State;
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
// size: 2728 B (2.664 KiB), align: 8                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [   0.. 703] case  : O2Case                                                                                 |
// [ 704..2727] tables: O2RunTables                                                                            |
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
    const prepared_solve_config = try controls.prepareSolveConfig(solve_config);
    _ = try prepareSessionRows(allocator, session, prepared, prepared_solve_config);
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
    //   Root-level orchestration follows the integrated transport route in                                    |
    //   `tests/unit/spectrum/spectrum_run_test.zig`                                                           |
    // --------------------------------------------------------------------------------------------------------|
    const prepared_solve_config = try controls.prepareSolveConfig(solve_config);
    const prepared_rows = try prepareSessionRows(allocator, session, prepared, prepared_solve_config);
    const table = prepared_rows.table;
    const wavelengths = session.radiance.wavelengthList();
    const product_count = table.rows.len;
    const worker_count = prepared_rows.worker_count;
    const worker_pool = session.worker_pool.poolForWorkerCount(allocator, worker_count);
    const transport_workers = session.transport_workers.workers[0..worker_count];

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

    // runO2A sampling policy ---------------------------------------------------------------------------------|
    // Canonical expected values owned by this repository.                                                     |
    // product row using integrated radiance and integrated irradiance sampling. O2 A                          |
    // `evidence/python-reference-case-native.json` exposes no Python-native key for calibration arrays, slit  |
    // kernels, or per-channel integration overrides. Keep this policy fixed here;                             |
    // user-configurable controls enter through O2Case JSON and `o2aSolveConfig`.                              |
    // --------------------------------------------------------------------------------------------------------|
    const sampling_policy = spectrum_run.O2ASamplingPolicy{};
    const summary = try spectrum_run.runO2ASpectrum(
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
        prepared_solve_config,
        sampling_policy,
        !prepared_rows.dense_radiance_results_match,
        worker_pool,
        worker_count,
        .{
            .dense_radiance = session.radiance.resultRows(),
            .wavelengths_nm = result.spectrum.wavelength_nm,
            .raw_radiance = raw_radiance,
            .raw_irradiance = raw_irradiance,
            .radiance = product_radiance,
            .irradiance = result.spectrum.irradiance,
            .reflectance = result.spectrum.reflectance,
            .jacobian = result.spectrum.jacobian,
        },
        transport_workers,
        &session.solar_irradiance,
    );
    if (!prepared_rows.dense_radiance_results_match) {
        session.radiance.markResultsValid(prepared_rows.dense_radiance_result_stamp);
    }

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

pub fn runO2AOptimalEstimation(
    allocator: Allocator,
    session: *O2SessionMemory,
    prepared: *const PreparedO2A,
    measurement_wavelength_nm: []const f64,
    measurement_reflectance: []const f64,
    measurement_variance: []const f64,
    state_specs: []const retrieval.StateSpec,
    retrieval_controls: retrieval.Controls,
) !retrieval.Result {
    // runO2AOptimalEstimation --------------------------------------------------------------------------------|
    // Run one full-physics O2 A optimal-estimation solve through the explicit forward path.                   |
    //                                                                                                         |
    // steps                                                                                                   |
    //   1. copy measurement rows into dense retrieval SoA storage                                             |
    //   2. initialize the fixed two-state Rodgers vectors from StateSpec rows                                 |
    //   3. per iteration: apply scalar retrieval state to an O2Case, refresh layer/aerosol rows, run          |
    //      spectrum plus reflectance Jacobians, stream the normal system, and solve the transformed update    |
    //   4. write history, posterior covariance, and averaging kernel into the retained Result owner           |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : one product-grid forward/Jacobian evaluation per iteration                                 |
    //   memory   : session caches retain wavelength, radiance, solar, and RTM worker storage across           |
    //              iterations; retrieval math uses fixed stack vectors                                        |
    //                                                                                                         |
    // performance note                                                                                        |
    //   Pressure-state changes rebuild the LayerGrid only. Public spectrum runs cache spectroscopy-profile    |
    //   support rows and sample them onto the refreshed support grid inside spectrum_run; they do not cache   |
    //   pressure-dependent diagnostic layer rows.                                                             |
    //                                                                                                         |
    //   explicit row forward facade.                                                                          |
    // --------------------------------------------------------------------------------------------------------|
    try validateRetrievalControls(retrieval_controls);

    var measurement = try retrieval.MeasuredReflectanceRows.init(
        allocator,
        measurement_wavelength_nm,
        measurement_reflectance,
        measurement_variance,
    );
    defer measurement.deinit(allocator);

    var result = try retrieval.Result.init(allocator, state_specs.len, retrieval_controls.max_iterations);
    errdefer result.deinit(allocator);

    const state_space = try retrieval.initializeStateSpace(state_specs, &result);
    const state_count = state_specs.len;
    const has_pressure_state = retrievalStateActive(state_specs, .aerosol_layer_mid_pressure_hpa);
    if (has_pressure_state and prepared.case.atmosphere.intervals.len == 0) return error.InvalidStateSpec;

    const mutable_interval_count = if (has_pressure_state) prepared.case.atmosphere.intervals.len else 0;
    const mutable_intervals = try allocator.alloc(o2_case.VerticalInterval, mutable_interval_count);
    defer allocator.free(mutable_intervals);

    var retrieval_layers = try atmosphere_layers.buildFromPreparedProfiles(
        allocator,
        prepared.case,
        prepared.tables.layers.source_profile.rows,
        prepared.tables.layers.spectroscopy_profile.rows,
        prepared.tables.quadrature,
    );
    defer retrieval_layers.deinit(allocator);

    var state = state_space.state;
    var scratch: retrieval.RetrievalIterationScratch = .{};
    try retrieval.preparePriorScales(state_space, state_count, &scratch);

    var final_posterior_precision: retrieval.StateMatrix =
        .{.{0.0} ** retrieval.max_state_count} ** retrieval.max_state_count;
    var converged = false;
    var iteration_count: usize = 0;

    for (0..retrieval_controls.max_iterations) |iteration_offset| {
        const previous = state;
        var forward = try evaluateRetrievalState(
            allocator,
            session,
            prepared,
            state_specs,
            previous,
            state_space.derivative_state_mask,
            mutable_intervals,
            &retrieval_layers,
        );
        defer forward.deinit(allocator);

        const accumulation = try retrieval.accumulateNormalSystem(
            measurement,
            .{
                .wavelength_nm = forward.spectrum.wavelength_nm,
                .reflectance = forward.spectrum.reflectance,
                .jacobian = forward.spectrum.jacobian,
            },
            state_specs,
            previous,
            state_space.prior,
            scratch.sqrt_sa,
            &scratch,
        );

        const step = try retrieval.solveStep(
            state_count,
            scratch.g,
            scratch.b,
            state_space.prior,
            scratch.sqrt_sa,
            scratch.sqrt_inv_sa,
            retrieval_controls.max_change_transformed_state,
            &scratch,
        );
        state = step.state;
        for (0..state_count) |index| {
            state[index] = @min(state_space.upper[index], @max(state_space.lower[index], state[index]));
        }

        var dx_iter = retrieval_algebra.zeroVector();
        for (0..state_count) |index| dx_iter[index] = state[index] - previous[index];

        var chi2_state: f64 = 0.0;
        for (0..state_count) |index| {
            chi2_state += dx_iter[index] * dx_iter[index] / state_space.variance[index];
        }
        const state_conv = retrieval.quadraticForm(step.posterior_precision, dx_iter, state_count) /
            @as(f64, @floatFromInt(state_count));
        converged = state_conv < retrieval_controls.state_vector_convergence_threshold and step.snr_normal;

        const history_offset = iteration_offset * state_count;
        for (0..state_count) |index| result.history_state[history_offset + index] = state[index];
        result.history_chi2[iteration_offset] = accumulation.chi2_reflectance + chi2_state;
        result.history_chi2_reflectance[iteration_offset] = accumulation.chi2_reflectance;
        result.history_chi2_state_vector[iteration_offset] = chi2_state;
        result.history_state_vector_convergence[iteration_offset] = state_conv;
        result.history_snr_normal[iteration_offset] = if (step.snr_normal) 1 else 0;
        final_posterior_precision = step.posterior_precision;
        scratch.jt_invse_j = accumulation.jt_invse_j;

        iteration_count = iteration_offset + 1;
        if (converged) break;
    }

    const posterior_covariance = try retrieval_algebra.invertSymmetric(final_posterior_precision, state_count);
    const averaging_kernel = retrieval_algebra.multiply(posterior_covariance, scratch.jt_invse_j, state_count);
    result.iteration_count = @intCast(iteration_count);
    result.converged = converged;
    for (0..state_count) |row| {
        result.state[row] = state[row];
        for (0..state_count) |col| {
            result.posterior_covariance[row * state_count + col] = posterior_covariance[row][col];
            result.averaging_kernel[row * state_count + col] = averaging_kernel[row][col];
        }
    }
    return result;
}

pub fn runO2AOptimalEstimationCorrection(
    allocator: Allocator,
    session: *O2SessionMemory,
    prepared: *const PreparedO2A,
    measurement_wavelength_nm: []const f64,
    measurement_reflectance: []const f64,
    measurement_variance: []const f64,
    state_specs: []const retrieval.StateSpec,
    retrieval_controls: retrieval.Controls,
) !retrieval.Result {
    // runO2AOptimalEstimationCorrection --------------------------------------------------------------------- |
    // Apply one full-physics O2 A correction step to a prepared case already written at the fast-stage state. |
    //                                                                                                         |
    // contract                                                                                                |
    //   The correction path returns exactly one Rodgers update. Controls still validate solver thresholds,    |
    //   but max_iterations does not widen the correction history.                                             |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : one product-grid forward/Jacobian evaluation on the sparse correction wavelength axis      |
    //   memory   : result history capacity is 1; the caller's session caches retain RTM/profile rows          |
    //                                                                                                         |
    //   reuses evaluateRetrievalState for the same state-space normal-system math.                            |
    // --------------------------------------------------------------------------------------------------------|
    try validateRetrievalControls(retrieval_controls);

    var measurement = try retrieval.MeasuredReflectanceRows.init(
        allocator,
        measurement_wavelength_nm,
        measurement_reflectance,
        measurement_variance,
    );
    defer measurement.deinit(allocator);

    var result = try retrieval.Result.init(allocator, state_specs.len, 1);
    errdefer result.deinit(allocator);

    const state_space = try retrieval.initializeStateSpace(state_specs, &result);
    const state_count = state_specs.len;
    const has_pressure_state = retrievalStateActive(state_specs, .aerosol_layer_mid_pressure_hpa);
    if (has_pressure_state and prepared.case.atmosphere.intervals.len == 0) return error.InvalidStateSpec;

    const mutable_interval_count = if (has_pressure_state) prepared.case.atmosphere.intervals.len else 0;
    const mutable_intervals = try allocator.alloc(o2_case.VerticalInterval, mutable_interval_count);
    defer allocator.free(mutable_intervals);

    var retrieval_layers = try atmosphere_layers.buildFromPreparedProfiles(
        allocator,
        prepared.case,
        prepared.tables.layers.source_profile.rows,
        prepared.tables.layers.spectroscopy_profile.rows,
        prepared.tables.quadrature,
    );
    defer retrieval_layers.deinit(allocator);

    var scratch: retrieval.RetrievalIterationScratch = .{};
    try retrieval.preparePriorScales(state_space, state_count, &scratch);

    var forward = try evaluateRetrievalState(
        allocator,
        session,
        prepared,
        state_specs,
        state_space.state,
        state_space.derivative_state_mask,
        mutable_intervals,
        &retrieval_layers,
    );
    defer forward.deinit(allocator);

    const accumulation = try retrieval.accumulateNormalSystem(
        measurement,
        .{
            .wavelength_nm = forward.spectrum.wavelength_nm,
            .reflectance = forward.spectrum.reflectance,
            .jacobian = forward.spectrum.jacobian,
        },
        state_specs,
        state_space.state,
        state_space.prior,
        scratch.sqrt_sa,
        &scratch,
    );

    const step = try retrieval.solveStep(
        state_count,
        scratch.g,
        scratch.b,
        state_space.prior,
        scratch.sqrt_sa,
        scratch.sqrt_inv_sa,
        retrieval_controls.max_change_transformed_state,
        &scratch,
    );

    var state = step.state;
    for (0..state_count) |index| {
        state[index] = @min(state_space.upper[index], @max(state_space.lower[index], state[index]));
    }

    var dx_iter = retrieval_algebra.zeroVector();
    for (0..state_count) |index| dx_iter[index] = state[index] - state_space.state[index];

    var chi2_state: f64 = 0.0;
    for (0..state_count) |index| {
        chi2_state += dx_iter[index] * dx_iter[index] / state_space.variance[index];
    }
    const state_conv = retrieval.quadraticForm(step.posterior_precision, dx_iter, state_count) /
        @as(f64, @floatFromInt(state_count));
    const converged = state_conv < retrieval_controls.state_vector_convergence_threshold and step.snr_normal;

    for (0..state_count) |index| result.history_state[index] = state[index];
    result.history_chi2[0] = accumulation.chi2_reflectance + chi2_state;
    result.history_chi2_reflectance[0] = accumulation.chi2_reflectance;
    result.history_chi2_state_vector[0] = chi2_state;
    result.history_state_vector_convergence[0] = state_conv;
    result.history_snr_normal[0] = if (step.snr_normal) 1 else 0;

    const posterior_covariance = try retrieval_algebra.invertSymmetric(step.posterior_precision, state_count);
    const averaging_kernel = retrieval_algebra.multiply(posterior_covariance, accumulation.jt_invse_j, state_count);
    result.iteration_count = 1;
    result.converged = converged;
    for (0..state_count) |row| {
        result.state[row] = state[row];
        for (0..state_count) |col| {
            result.posterior_covariance[row * state_count + col] = posterior_covariance[row][col];
            result.averaging_kernel[row * state_count + col] = averaging_kernel[row][col];
        }
    }
    return result;
}

pub fn runO2AOptimalEstimationBatch(
    allocator: Allocator,
    session: *O2SessionMemory,
    prepared: *const PreparedO2A,
    measurement_wavelength_nm: []const f64,
    measurement_reflectance: []const f64,
    measurement_variance: []const f64,
    state_template: []const retrieval.StateSpec,
    initial_states: []const f64,
    prior_states: []const f64,
    retrieval_controls: retrieval.Controls,
) !retrieval.BatchResult {
    // runO2AOptimalEstimationBatch -------------------------------------------------------------------------- |
    // Run a correctness-first full-physics OE batch over caller-provided start/prior rows.                    |
    //                                                                                                         |
    // boundary                                                                                                |
    //   This is the single-worker O2 A batch slice. Each start reuses the same public measurement rows and    |
    //   prepared case, then copies compact result rows into the run-major BatchResult owner.                  |
    //                                                                                                         |
    // failure model                                                                                           |
    //   OutOfMemory aborts the whole batch. Numerical or control failures mark only that start as failed,     |
    // --------------------------------------------------------------------------------------------------------|
    try validateRetrievalControls(retrieval_controls);

    if (state_template.len == 0 or state_template.len > retrieval.max_state_count) return error.InvalidStateCount;

    if (initial_states.len != prior_states.len) return error.InvalidStateSpec;

    if (initial_states.len % state_template.len != 0) return error.InvalidStateSpec;

    const run_count = initial_states.len / state_template.len;
    if (run_count == 0) return error.InvalidStateSpec;

    var result = try retrieval.BatchResult.init(
        allocator,
        run_count,
        state_template.len,
        retrieval_controls.max_iterations,
    );
    errdefer result.deinit(allocator);

    for (0..run_count) |run_index| {
        const state_offset = run_index * state_template.len;
        var run_specs_buffer: [retrieval.max_state_count]retrieval.StateSpec = undefined;
        for (state_template, 0..) |template, state_index| {
            var spec = template;
            spec.initial = initial_states[state_offset + state_index];
            spec.prior = prior_states[state_offset + state_index];
            run_specs_buffer[state_index] = spec;
        }

        var run = runO2AOptimalEstimation(
            allocator,
            session,
            prepared,
            measurement_wavelength_nm,
            measurement_reflectance,
            measurement_variance,
            run_specs_buffer[0..state_template.len],
            retrieval_controls,
        ) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => {
                result.status[run_index] = @intFromEnum(retrieval.BatchRunStatus.failed);
                continue;
            },
        };
        defer run.deinit(allocator);

        result.iteration_count[run_index] = run.iteration_count;
        result.converged[run_index] = if (run.converged) 1 else 0;
        result.status[run_index] = @intFromEnum(retrieval.BatchRunStatus.ok);
        for (0..state_template.len) |state_index| {
            result.state[state_offset + state_index] = run.state[state_index];
        }

        const history_offset = run_index * result.history_capacity * state_template.len;
        const history_len = @as(usize, run.iteration_count) * state_template.len;
        @memcpy(
            result.history_state[history_offset .. history_offset + history_len],
            run.history_state[0..history_len],
        );
    }

    return result;
}

pub fn runO2AFastmodeOptimalEstimationBatch(
    allocator: Allocator,
    fast_session: *O2SessionMemory,
    correction_session: *O2SessionMemory,
    fast_prepared: *const PreparedO2A,
    fast_measurement_wavelength_nm: []const f64,
    fast_measurement_reflectance: []const f64,
    fast_measurement_variance: []const f64,
    fast_state_template: []const retrieval.StateSpec,
    initial_states: []const f64,
    prior_states: []const f64,
    fast_controls: retrieval.Controls,
    correction_prepared: *const PreparedO2A,
    correction_measurement_wavelength_nm: []const f64,
    correction_measurement_reflectance: []const f64,
    correction_measurement_variance: []const f64,
    correction_state_template: []const retrieval.StateSpec,
    correction_prior_states: []const f64,
    correction_controls: retrieval.Controls,
) !retrieval.FastmodeBatchResult {
    // runO2AFastmodeOptimalEstimationBatch ------------------------------------------------------------------ |
    // Run fast-stage starts, then run a full-physics correction batch seeded from the fast-stage states.      |
    //                                                                                                         |
    // boundary                                                                                                |
    //   Python owns the fast and correction case construction. Zig receives two prepared O2 A cases, two      |
    //   measurement grids, and config-driven controls; no wavelength counts are hardcoded here.               |
    //                                                                                                         |
    //   converged flags keep fast-stage convergence when the correction stage returns ok.                     |
    // --------------------------------------------------------------------------------------------------------|
    if (fast_state_template.len != correction_state_template.len) return error.InvalidStateSpec;

    if (initial_states.len != prior_states.len) return error.InvalidStateSpec;

    if (correction_prior_states.len != prior_states.len) return error.InvalidStateSpec;

    var fast = try runO2AOptimalEstimationBatch(
        allocator,
        fast_session,
        fast_prepared,
        fast_measurement_wavelength_nm,
        fast_measurement_reflectance,
        fast_measurement_variance,
        fast_state_template,
        initial_states,
        prior_states,
        fast_controls,
    );
    defer fast.deinit(allocator);

    var correction = try runO2AOptimalEstimationBatch(
        allocator,
        correction_session,
        correction_prepared,
        correction_measurement_wavelength_nm,
        correction_measurement_reflectance,
        correction_measurement_variance,
        correction_state_template,
        fast.state,
        correction_prior_states,
        correction_controls,
    );
    defer correction.deinit(allocator);

    const total_history_capacity = fast.history_capacity + correction.history_capacity;
    var result = try retrieval.FastmodeBatchResult.init(
        allocator,
        fast.run_count,
        fast.state_count,
        total_history_capacity,
    );
    errdefer result.deinit(allocator);

    const state_count = fast.state_count;
    const ok_status = @intFromEnum(retrieval.BatchRunStatus.ok);
    const failed_status = @intFromEnum(retrieval.BatchRunStatus.failed);
    const CorrectionStage = struct {
        iteration_count: usize,
        converged: u8,
        ok: bool,
    };

    for (0..fast.run_count) |run_index| {
        const fast_ok = fast.status[run_index] == ok_status;
        var correction_stage = CorrectionStage{
            .iteration_count = 0,
            .converged = 0,
            .ok = false,
        };
        if (fast_ok) {
            correction_stage = .{
                .iteration_count = correction.iteration_count[run_index],
                .converged = correction.converged[run_index],
                .ok = correction.status[run_index] == ok_status,
            };
        }
        const result_ok = fast_ok and correction_stage.ok;

        result.fast_stage_iteration_count[run_index] = fast.iteration_count[run_index];
        result.fast_stage_converged[run_index] = fast.converged[run_index];
        result.full_correction_iteration_count[run_index] = correction_stage.iteration_count;
        result.full_correction_converged[run_index] = correction_stage.converged;

        result.status[run_index] = failed_status;

        result.iteration_count[run_index] =
            fast.iteration_count[run_index] + correction_stage.iteration_count;
        result.converged[run_index] = 0;

        const state_offset = run_index * state_count;
        var final_state = fast.state;
        if (result_ok) {
            result.status[run_index] = ok_status;
            result.converged[run_index] = fast.converged[run_index];
            final_state = correction.state;
        }
        @memcpy(
            result.state[state_offset .. state_offset + state_count],
            final_state[state_offset .. state_offset + state_count],
        );

        const result_history_offset = run_index * total_history_capacity * state_count;
        const fast_history_offset = run_index * fast.history_capacity * state_count;
        const correction_history_offset = run_index * correction.history_capacity * state_count;
        const fast_history_len = fast.iteration_count[run_index] * state_count;
        const correction_history_len = correction_stage.iteration_count * state_count;
        const correction_result_offset = result_history_offset + fast.history_capacity * state_count;
        const correction_result_end = correction_result_offset + correction_history_len;
        @memcpy(
            result.history_state[result_history_offset .. result_history_offset + fast_history_len],
            fast.history_state[fast_history_offset .. fast_history_offset + fast_history_len],
        );
        @memcpy(
            result.history_state[correction_result_offset..correction_result_end],
            correction.history_state[correction_history_offset .. correction_history_offset + correction_history_len],
        );

        if (correction_history_len != 0 and fast.iteration_count[run_index] < fast.history_capacity) {
            const compact_target_offset =
                result_history_offset + fast.iteration_count[run_index] * state_count;
            const compact_target_end = compact_target_offset + correction_history_len;
            std.mem.copyForwards(
                f64,
                result.history_state[compact_target_offset..compact_target_end],
                result.history_state[correction_result_offset..correction_result_end],
            );
        }
    }

    return result;
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
    // Build the exercised O2 A transport controls used by integrated transport evidence.                      |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .derivative_mode = .semi_analytical,
        .derivative_state_mask = jacobian_states.stateMask(.aerosol_optical_depth) |
            jacobian_states.stateMask(.aerosol_layer_mid_pressure_hpa),
        .controls = .{
            .scattering = .multiple,
            .n_streams = @intCast(case.rtm.stream_count),
            .performance_thresholds = case.rtm.performance_thresholds,
            .use_spherical_correction = case.geometry.pseudo_spherical,
            .integrate_source_function = true,
            .renorm_phase_function = true,
        },
    };
}

fn validateRetrievalControls(retrieval_controls: retrieval.Controls) !void {
    // validateRetrievalControls ----------------------------------------------------------------------------- |
    // Reject impossible OE controls before the iteration loop uses them as divisors or damping limits.        |
    // --------------------------------------------------------------------------------------------------------|
    if (retrieval_controls.max_iterations == 0 or
        retrieval_controls.max_iterations > retrieval.max_iteration_count)
    {
        return error.InvalidStateSpec;
    }
    if (retrieval_controls.state_vector_convergence_threshold <= 0.0 or
        retrieval_controls.max_change_transformed_state <= 0.0 or
        !std.math.isFinite(retrieval_controls.state_vector_convergence_threshold) or
        !std.math.isFinite(retrieval_controls.max_change_transformed_state))
    {
        return error.InvalidStateSpec;
    }
}

fn evaluateRetrievalState(
    allocator: Allocator,
    session: *O2SessionMemory,
    prepared: *const PreparedO2A,
    state_specs: []const retrieval.StateSpec,
    state: retrieval.StateVector,
    derivative_state_mask: jacobian_states.StateMask,
    mutable_intervals: []o2_case.VerticalInterval,
    retrieval_layers: *atmosphere_layers.LayerGrid,
) !O2SpectrumRunResult {
    // evaluateRetrievalState -------------------------------------------------------------------------------- |
    // Apply one retrieval state vector, refresh state-dependent setup rows, and run spectrum reflectance.     |
    //                                                                                                         |
    // boundary                                                                                                |
    //   The retrieval driver owns one retained LayerGrid. This function refills its computed rows for the     |
    //   current state while borrowing line, CIA, phase, instrument, and solar tables from the prepared case.  |
    //                                                                                                         |
    // refresh                                                                                                 |
    //   aerosol optical depth : rebuild inline AerosolLayerTable                                              |
    //   pressure placement    : rebuild LayerGrid and inline AerosolLayerTable                                |
    //   profile-line cache    : reused when exact wavelengths and mode bits match; support-profile values     |
    //                           are sampled onto the refreshed support grid at solve time                     |
    //                                                                                                         |
    //   state-dependent scene/optical rows while invariant spectroscopy and instrument setup stay retained.   |
    // --------------------------------------------------------------------------------------------------------|
    var case = prepared.case;
    if (mutable_intervals.len != 0) {
        @memcpy(mutable_intervals, prepared.case.atmosphere.intervals);
        case.atmosphere.intervals = mutable_intervals;
    }
    try writeRetrievalStateToCase(&case, mutable_intervals, state_specs, state);
    try input_validate.o2Case(case);

    try atmosphere_layers.refillFromPreparedProfiles(retrieval_layers, case, prepared.tables.quadrature);

    var evaluation_prepared = PreparedO2A{
        .case = case,
        .tables = prepared.tables,
    };
    evaluation_prepared.tables.layers = retrieval_layers.*;
    evaluation_prepared.tables.aerosol = aerosol_tables.build(case);

    var solve_config = o2aSolveConfig(case);
    solve_config.derivative_mode = .semi_analytical;
    solve_config.derivative_state_mask = derivative_state_mask;

    return runO2AWithSessionMemory(allocator, session, &evaluation_prepared, solve_config);
}

fn writeRetrievalStateToCase(
    case: *O2Case,
    mutable_intervals: []o2_case.VerticalInterval,
    state_specs: []const retrieval.StateSpec,
    state: retrieval.StateVector,
) !void {
    // writeRetrievalStateToCase ----------------------------------------------------------------------------- |
    // Write active OE scalar values into the case copy used for this iteration.                               |
    //                                                                                                         |
    // pressure placement                                                                                      |
    //   target interval takes the new aerosol top/bottom pressures, the adjacent interval boundaries move     |
    //   with it, and no other interval is changed.                                                            |
    // --------------------------------------------------------------------------------------------------------|
    for (state_specs, 0..) |spec, index| {
        const value = state[index];
        switch (spec.state) {
            .aerosol_optical_depth => case.aerosol.optical_depth = value,
            .aerosol_layer_mid_pressure_hpa => {
                if (mutable_intervals.len == 0) return error.InvalidStateSpec;

                const fit_interval_index = @as(usize, spec.interval_index_1based);
                const half_thickness = 0.5 * spec.thickness_hpa;
                const top_pressure = value - half_thickness;
                const bottom_pressure = value + half_thickness;

                case.aerosol.interval_index_1based = fit_interval_index;
                case.aerosol.top_pressure_hpa = top_pressure;
                case.aerosol.bottom_pressure_hpa = bottom_pressure;

                var updated = false;
                for (mutable_intervals) |*interval| {
                    const interval_index = interval.index_1based;

                    if (interval_index == fit_interval_index) {
                        interval.top_pressure_hpa = top_pressure;
                        interval.bottom_pressure_hpa = bottom_pressure;
                        updated = true;
                        continue;
                    }

                    if (interval_index + 1 == fit_interval_index) {
                        interval.bottom_pressure_hpa = top_pressure;
                        continue;
                    }

                    if (interval_index == fit_interval_index + 1) {
                        interval.top_pressure_hpa = bottom_pressure;
                    }
                }

                if (!updated) return error.InvalidStateSpec;
            },
        }
    }
}

fn retrievalStateActive(state_specs: []const retrieval.StateSpec, state: jacobian_states.State) bool {
    // retrievalStateActive ---------------------------------------------------------------------------------- |
    // Test whether one fixed Jacobian state appears in the current OE state vector.                           |
    // --------------------------------------------------------------------------------------------------------|
    for (state_specs) |spec| {
        if (spec.state == state) return true;
    }
    return false;
}

const PreparedSessionRows = struct {
    table: sampling_table.SpectrumSamplingTable,
    worker_count: usize,
    dense_radiance_results_match: bool,
    dense_radiance_result_stamp: hashing.ReuseStamp,
};

fn prepareSessionRows(
    allocator: Allocator,
    session: *O2SessionMemory,
    prepared: *const PreparedO2A,
    prepared_solve_config: SolveConfig,
) !PreparedSessionRows {
    // prepareSessionRows -------------------------------------------------------------------------------------|
    // Rebuild shape rows and retain expensive profile-line values for one already-validated solve route.      |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Root prepares SolveConfig once before this boundary. Wavelength workers receive the same sanitized    |
    //   mask and validated stream/threshold controls, matching the prepared LABOS execution route.            |
    // --------------------------------------------------------------------------------------------------------|
    const sampling_stamp = samplingTableReuseStamp(prepared);
    const table = resolve_sampling_table: {
        if (session.spectrum.hasTable(sampling_stamp)) {
            break :resolve_sampling_table try session.spectrum.table(
                session.spectrum.rows.len,
                session.spectrum.kernel_offsets_nm.len,
            );
        }

        var owned_sampling = try sampling_table.buildO2SpectrumSamplingTable(
            allocator,
            prepared.case,
            prepared.tables.instrument,
            prepared.tables.lines,
        );
        defer owned_sampling.deinit(allocator);
        const row_count = owned_sampling.rows.len;
        const side_sample_count = owned_sampling.kernel_offsets_nm.len;
        session.spectrum.takeTable(allocator, &owned_sampling, sampling_stamp);
        break :resolve_sampling_table try session.spectrum.table(row_count, side_sample_count);
    };

    var owned_wavelengths = try radiance_wavelengths.buildRadianceWavelengthList(allocator, table);
    defer owned_wavelengths.deinit(allocator);
    const wavelength_list_stamp = radianceWavelengthListReuseStamp(owned_wavelengths.view());
    const dense_count = owned_wavelengths.wavelengths.len;
    const exact_wavelengths = try allocator.alloc(f64, dense_count);
    defer allocator.free(exact_wavelengths);
    for (owned_wavelengths.wavelengths, exact_wavelengths) |row, *wavelength_nm| {
        wavelength_nm.* = row.wavelength_nm;
    }
    const worker_count = spectrum_run.preferredRadianceWorkerCount(dense_count);
    const worker_pool = session.worker_pool.poolForWorkerCount(allocator, worker_count);

    // Public O2 A spectrum runs read support-profile sigma rows through optics interpolation. They do not read
    // diagnostic layer-node rows or profile-line d_sigma/dT rows for the current surface/aerosol Jacobian set.
    // Both mode bits remain in the reuse stamp so future diagnostic or temperature-profile paths split caches.
    const build_layer_values = false;
    const needs_temperature_derivatives = false;
    const profile_stamp = profile_lines.profileLineReuseStamp(
        prepared.case.id,
        exact_wavelengths,
        build_layer_values,
        needs_temperature_derivatives,
    );

    const wavelength_list_matches = session.radiance.hasWavelengthList(
        wavelength_list_stamp,
        owned_wavelengths.rows.len,
        owned_wavelengths.sample_indices.len,
        owned_wavelengths.wavelengths.len,
    );
    if (!wavelength_list_matches) {
        session.radiance.takeWavelengthList(allocator, &owned_wavelengths, wavelength_list_stamp);
    }
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
                build_layer_values,
                needs_temperature_derivatives,
                worker_pool,
                worker_count,
            );
    }
    const dense_radiance_result_stamp = radianceResultReuseStamp(
        prepared,
        exact_wavelengths,
        prepared_solve_config,
        profile_stamp,
    );
    const dense_radiance_results_match = session.radiance.resultsValid(dense_radiance_result_stamp);

    const layer_count = prepared.tables.layers.layer_pressures_hpa.len;
    const support_count = prepared.tables.layers.support_mid_altitudes_km.len;
    const phase_max_index = @max(prepared.tables.phase.aerosol_phase_max_index, @as(usize, 2));
    const fourier_max_index = prepared_solve_config.controls.performance_thresholds.cappedFourierMax(phase_max_index);
    try session.transport_workers.ensureWorkerCount(allocator, worker_count);
    for (session.transport_workers.workers[0..worker_count]) |*worker_memory| {
        try worker_memory.ensureOpticsCapacity(allocator, support_count, layer_count);
        try worker_memory.ensureCapacity(
            allocator,
            layer_count + 1,
            prepared_solve_config.controls.n_streams,
            @min(phase_max_index, fourier_max_index) + 1,
            fourier_max_index + 1,
            true,
        );
    }
    return .{
        .table = table,
        .worker_count = worker_count,
        .dense_radiance_results_match = dense_radiance_results_match,
        .dense_radiance_result_stamp = dense_radiance_result_stamp,
    };
}

fn radianceWavelengthListReuseStamp(wavelengths: radiance_wavelengths.RadianceWavelengthList) hashing.ReuseStamp {
    // radianceWavelengthListReuseStamp ---------------------------------------------------------------------- |
    // Identify the exact forward-miss row/index/wavelength plan that dense radiance results are indexed by.   |
    // --------------------------------------------------------------------------------------------------------|
    var hasher = std.hash.Wyhash.init(0);
    radiance_wavelengths.hashAll(&hasher, wavelengths);
    return .{ .value = hasher.final() };
}

fn samplingTableReuseStamp(prepared: *const PreparedO2A) hashing.ReuseStamp {
    // samplingTableReuseStamp ------------------------------------------------------------------------------- |
    // Identify the retained wavelength-sampling table before root decides whether to rebuild instrument       |
    // kernels.                                                                                                |
    //                                                                                                         |
    //   `wavelengthPlanKey`. The explicit route hashes only inputs consumed by                                |
    //   `spectrum/sampling_table.zig`: product grid, explicit measured wavelengths, instrument sampling       |
    //   knobs, and the O2 line centers/strengths that split adaptive intervals.                               |
    // --------------------------------------------------------------------------------------------------------|
    var hasher = std.hash.Wyhash.init(0x4f32_4132_7761_7665);
    hasher.update(prepared.case.id);
    hashSpectralGrid(&hasher, prepared.case.spectral_grid);
    hasher.update(std.mem.sliceAsBytes(prepared.case.observation.measured_wavelengths_nm));
    hashInstrumentSamplingInputs(&hasher, prepared.tables.instrument);
    hashAdaptiveLineInputs(&hasher, prepared.tables.lines);
    return .{ .value = hasher.final() };
}

fn hashSpectralGrid(hasher: *std.hash.Wyhash, grid: o2_case.SpectralGrid) void {
    // hashSpectralGrid -------------------------------------------------------------------------------------- |
    // Hash the endpoint-inclusive product grid used by adaptive support-window construction.                  |
    // --------------------------------------------------------------------------------------------------------|
    hashing.updateValue(hasher, grid.start_nm);
    hashing.updateValue(hasher, grid.end_nm);
    hashing.updateValue(hasher, grid.sample_count);
}

fn hashInstrumentSamplingInputs(hasher: *std.hash.Wyhash, instrument: instrument_tables.InstrumentTable) void {
    // hashInstrumentSamplingInputs -------------------------------------------------------------------------- |
    // Hash instrument controls that change adaptive interval boundaries, Gauss orders, or line-shape weights. |
    // --------------------------------------------------------------------------------------------------------|
    hasher.update(instrument.name);
    hashing.updateValue(hasher, instrument.line_fwhm_nm);
    hashing.updateValue(hasher, instrument.high_resolution_step_nm);
    hashing.updateValue(hasher, instrument.high_resolution_half_span_nm);
    hashing.updateValue(hasher, instrument.adaptive_points_per_fwhm);
    hashing.updateValue(hasher, instrument.strong_line_min_divisions);
    hashing.updateValue(hasher, instrument.strong_line_max_divisions);
}

fn hashAdaptiveLineInputs(hasher: *std.hash.Wyhash, lines: line_tables.O2LineTable) void {
    // hashAdaptiveLineInputs -------------------------------------------------------------------------------- |
    // Hash the line-table fields read by `collectAdaptiveStrongLineCenters`.                                  |
    //                                                                                                         |
    // math                                                                                                    |
    //   threshold = max(line_strength) * threshold_line_sim                                                   |
    //   active centers are line centers inside the global support span with strength >= threshold             |
    // --------------------------------------------------------------------------------------------------------|
    hashing.updateValue(hasher, lines.threshold_line_sim);
    hashing.updateValue(hasher, lines.rows.len);
    for (lines.rows) |row| {
        hashing.updateValue(hasher, row.center_wavelength_nm);
        hashing.updateValue(hasher, row.line_strength_cm2_per_molecule);
    }
}

fn radianceResultReuseStamp(
    prepared: *const PreparedO2A,
    wavelengths_nm: []const f64,
    solve_config: SolveConfig,
    profile_stamp: hashing.ReuseStamp,
) hashing.ReuseStamp {
    // radianceResultReuseStamp ------------------------------------------------------------------------------ |
    // Identify dense radiance rows for one route without letting the stamp enter transport math.              |
    //                                                                                                         |
    // boundary                                                                                                |
    //   The stamp covers exact wavelengths, active solve controls, view/surface scalars, profile-line cache   |
    //   identity, and numeric setup rows used by `radianceAtWavelength`. A match permits skipping dense       |
    //   prefetch; product gather and reflectance assembly still run.                                          |
    // --------------------------------------------------------------------------------------------------------|
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(prepared.case.id);
    hasher.update(std.mem.sliceAsBytes(wavelengths_nm));
    hashing.updateValue(&hasher, profile_stamp.value);

    const angles = viewAngles(prepared.case);
    for ([_]f64{
        angles.solar_mu,
        angles.view_mu,
        angles.relative_azimuth_rad,
        prepared.case.surface_albedo,
    }) |value| hashing.updateValue(&hasher, value);
    for ([_]usize{
        @intFromEnum(solve_config.derivative_mode),
        solve_config.derivative_state_mask,
        @intFromEnum(solve_config.controls.scattering),
        solve_config.controls.n_streams,
    }) |value| hashing.updateValue(&hasher, value);
    hashing.updateBool(&hasher, solve_config.controls.use_spherical_correction);
    hashing.updateBool(&hasher, solve_config.controls.integrate_source_function);
    hashing.updateBool(&hasher, solve_config.controls.renorm_phase_function);
    updateHashThresholds(&hasher, solve_config.controls.performance_thresholds);

    atmosphere_layers.hashAll(&hasher, prepared.tables.layers);
    aerosol_tables.hashAll(&hasher, prepared.tables.aerosol);
    cia_table.hashAll(&hasher, prepared.tables.cia);
    phase_table.hashAll(&hasher, prepared.tables.phase);
    solar_table.hashAll(&hasher, prepared.tables.solar);

    return .{ .value = hasher.final() };
}

fn updateHashThresholds(hasher: *std.hash.Wyhash, thresholds: controls.PerformanceThresholds) void {
    // updateHashThresholds ---------------------------------------------------------------------------------- |
    // Hash scalar RTM thresholds field-by-field so padding bytes never affect cache validity.                 |
    // --------------------------------------------------------------------------------------------------------|
    for ([_]u16{
        thresholds.num_orders_max,
        thresholds.fourier_floor_scalar,
    }) |value| hashing.updateValue(hasher, value);
    hashing.updateOptionalU16(hasher, thresholds.fourier_order_cap);
    hashing.updateOptionalU16(hasher, thresholds.aerosol_tangent_order_cap);
    for ([_]f64{
        thresholds.fourier_tail_reflectance_epsilon,
        thresholds.threshold_conv_first,
        thresholds.threshold_conv_mult,
        thresholds.threshold_doubl,
        thresholds.threshold_mul,
        thresholds.phase_function_truncation_threshold,
    }) |value| hashing.updateValue(hasher, value);
}

fn viewAngles(case: O2Case) solve.ViewAngles {
    // viewAngles ---------------------------------------------------------------------------------------------|
    // Convert public geometry degrees into the forward-layer transport angle convention.                      |
    // --------------------------------------------------------------------------------------------------------|
    const solar_sin = @sin(std.math.degreesToRadians(case.geometry.solar_zenith_deg));
    const view_sin = @sin(std.math.degreesToRadians(case.geometry.viewing_zenith_deg));
    return .{
        .solar_mu = @sqrt(@max(1.0 - solar_sin * solar_sin, 0.0)),
        .view_mu = @sqrt(@max(1.0 - view_sin * view_sin, 0.0)),

        .relative_azimuth_rad = std.math.degreesToRadians(@mod(180.0 - case.geometry.relative_azimuth_deg, 360.0)),
    };
}
