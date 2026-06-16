const std = @import("std");
const builtin = @import("builtin");
const zdisamar = @import("zdisamar");

const allocator = std.heap.smp_allocator;
pub const links_libc = builtin.link_libc;

// c.zig ------------------------------------------------------------------------------------------------------|
// C ABI boundary for Python bindings and external callers.                                                    |
//                                                                                                             |
// called from                                                                                                 |
//   build.zig builds this file as the `zdisamar_c` dynamic-library root.                                      |
//   python/zdisamar/bindings/signatures.py binds the exported `zds_*` symbols with ctypes.                    |
//                                                                                                             |
// boundary                                                                                                    |
//   Context owns prepared setup tables, reusable O2 session memory, returned spectrum handles, and error      |
//   text. Compute receives only the public root inputs: Prepared, SessionMemory, and SolveConfig.             |
//   JSON parsing, diagnostic tables, retrieval, and fastmode return typed failures until their O2 A/O2 A      |
// ------------------------------------------------------------------------------------------------------------|

pub const ZdsStatus = enum(c_int) {
    ok = 0,
    failure = 1,
};

// ZdsSpectrum ------------------------------------------------------------------------------------------------|
// Borrowed spectrum arrays returned by run calls. result_handle owns the backing CResult.                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 64 B (0.062 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] len                  : usize                                                                       |
// [ 8..15] wavelength_nm        : [*]const f64                                                                |
// [16..23] radiance             : [*]const f64                                                                |
// [24..31] irradiance           : [*]const f64                                                                |
// [32..39] reflectance          : [*]const f64                                                                |
// [40..47] jacobian             : ?[*]const f64                                                               |
// [48..55] jacobian_state_count : usize                                                                       |
// [56..63] result_handle        : ?*anyopaque                                                                 |
pub const ZdsSpectrum = extern struct {
    len: usize = 0,
    wavelength_nm: [*]const f64 = undefined,
    radiance: [*]const f64 = undefined,
    irradiance: [*]const f64 = undefined,
    reflectance: [*]const f64 = undefined,
    jacobian: ?[*]const f64 = null,
    jacobian_state_count: usize = 0,
    result_handle: ?*anyopaque = null,
};
// ------------------------------------------------------------------------------------------------------------|

// ZdsDiagnosticReport ----------------------------------------------------------------------------------------|
// Small scalar summary for one spectrum.                                                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 3] sample_count        : u32                                                                          |
// [ 4.. 7] padding             : 4 B                                                                          |
// [ 8..15] wavelength_start_nm : f64                                                                          |
// [16..23] wavelength_end_nm   : f64                                                                          |
// [24..31] mean_radiance       : f64                                                                          |
// [32..39] mean_irradiance     : f64                                                                          |
// [40..47] mean_reflectance    : f64                                                                          |
pub const ZdsDiagnosticReport = extern struct {
    sample_count: u32 = 0,
    wavelength_start_nm: f64 = 0.0,
    wavelength_end_nm: f64 = 0.0,
    mean_radiance: f64 = 0.0,
    mean_irradiance: f64 = 0.0,
    mean_reflectance: f64 = 0.0,
};
// ------------------------------------------------------------------------------------------------------------|

// ZdsOptimalEstimationScalarSpec -----------------------------------------------------------------------------|
// One C-facing scalar control field for a named fixed-state retrieval lane.                                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 0] has_lower : u8                                                                                     |
// [ 1.. 1] has_upper : u8                                                                                     |
// [ 2.. 7] padding   : 6 B                                                                                    |
// [ 8..15] initial   : f64                                                                                    |
// [16..23] prior     : f64                                                                                    |
// [24..31] variance  : f64                                                                                    |
// [32..39] lower     : f64                                                                                    |
// [40..47] upper     : f64                                                                                    |
pub const ZdsOptimalEstimationScalarSpec = extern struct {
    has_lower: u8 = 0,
    has_upper: u8 = 0,
    initial: f64 = 0.0,
    prior: f64 = 0.0,
    variance: f64 = 0.0,
    lower: f64 = 0.0,
    upper: f64 = 0.0,
};
// ------------------------------------------------------------------------------------------------------------|

// ZdsOptimalEstimationPressureSpec ---------------------------------------------------------------------------|
// C-facing pressure retrieval lane: scalar controls plus required layer-placement metadata.                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 88 B (0.086 KiB), align: 8 B                                                                          |
//                                                                                                             |
// referenced storage                                                                                          |
//   pressure-profile arrays are borrowed only while the request converts into the native fixed state.         |
pub const ZdsOptimalEstimationPressureSpec = extern struct {
    scalar: ZdsOptimalEstimationScalarSpec = .{},
    interval_index_1based: u32 = 0,
    thickness_hpa: f64 = 0.0,
    pressure_profile_count: usize = 0,
    pressure_profile_altitude_km: ?[*]const f64 = null,
    pressure_profile_pressure_hpa: ?[*]const f64 = null,
};
// ------------------------------------------------------------------------------------------------------------|

// ZdsOptimalEstimationControls -------------------------------------------------------------------------------|
// Iteration and convergence controls copied into the native retrieval request.                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] max_iterations                     : usize                                                         |
// [ 8..15] state_vector_convergence_threshold : f64                                                           |
// [16..23] max_change_transformed_state       : f64                                                           |
pub const ZdsOptimalEstimationControls = extern struct {
    max_iterations: usize = 10,
    state_vector_convergence_threshold: f64 = 1.0,
    max_change_transformed_state: f64 = 1.0,
};
// ------------------------------------------------------------------------------------------------------------|

// ZdsOptimalEstimationRequest --------------------------------------------------------------------------------|
// Single-run retrieval request with borrowed measurement arrays and named fixed-state fields.                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 192 B (0.188 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] sample_count           : usize                                                                   |
// [  8.. 15] wavelength_nm          : ?[*]const f64                                                           |
// [ 16.. 23] reflectance            : ?[*]const f64                                                           |
// [ 24.. 31] variance               : ?[*]const f64                                                           |
// [ 32.. 79] aerosol_optical_depth  : ZdsOptimalEstimationScalarSpec                                          |
// [ 80..167] aerosol_layer_pressure : ZdsOptimalEstimationPressureSpec                                        |
// [168..191] controls               : ZdsOptimalEstimationControls                                            |
//                                                                                                             |
// referenced storage                                                                                          |
//   measurement arrays and pressure-profile rows borrow caller buffers for the duration of the call.          |
pub const ZdsOptimalEstimationRequest = extern struct {
    sample_count: usize = 0,
    wavelength_nm: ?[*]const f64 = null,
    reflectance: ?[*]const f64 = null,
    variance: ?[*]const f64 = null,
    aerosol_optical_depth: ZdsOptimalEstimationScalarSpec = .{},
    aerosol_layer_pressure: ZdsOptimalEstimationPressureSpec = .{},
    controls: ZdsOptimalEstimationControls = .{},
};
// ------------------------------------------------------------------------------------------------------------|

// ZdsOptimalEstimationResult ---------------------------------------------------------------------------------|
// Borrowed single-run retrieval output. result_handle owns all pointed-to result arrays.                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 120 B (0.117 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] state_count                      : usize                                                         |
// [  8.. 15] iteration_count                  : usize                                                         |
// [ 16.. 16] converged                        : u8                                                            |
// [ 17.. 23] padding                          : 7 B                                                           |
// [ 24.. 31] state_ids                        : ?[*]const u8                                                  |
// [ 32.. 39] state                            : ?[*]const f64                                                 |
// [ 40.. 47] initial_state                    : ?[*]const f64                                                 |
// [ 48.. 55] posterior_covariance             : ?[*]const f64                                                 |
// [ 56.. 63] averaging_kernel                 : ?[*]const f64                                                 |
// [ 64.. 71] history_state                    : ?[*]const f64                                                 |
// [ 72.. 79] history_chi2                     : ?[*]const f64                                                 |
// [ 80.. 87] history_chi2_reflectance         : ?[*]const f64                                                 |
// [ 88.. 95] history_chi2_state_vector        : ?[*]const f64                                                 |
// [ 96..103] history_state_vector_convergence : ?[*]const f64                                                 |
// [104..111] history_snr_normal               : ?[*]const u8                                                  |
// [112..119] result_handle                    : ?*anyopaque                                                   |
//                                                                                                             |
// referenced storage                                                                                          |
//   all pointer fields borrow native result arrays until zds_optimal_estimation_result_free.                  |
pub const ZdsOptimalEstimationResult = extern struct {
    state_count: usize = 0,
    iteration_count: usize = 0,
    converged: u8 = 0,
    state_ids: ?[*]const u8 = null,
    state: ?[*]const f64 = null,
    initial_state: ?[*]const f64 = null,
    posterior_covariance: ?[*]const f64 = null,
    averaging_kernel: ?[*]const f64 = null,
    history_state: ?[*]const f64 = null,
    history_chi2: ?[*]const f64 = null,
    history_chi2_reflectance: ?[*]const f64 = null,
    history_chi2_state_vector: ?[*]const f64 = null,
    history_state_vector_convergence: ?[*]const f64 = null,
    history_snr_normal: ?[*]const u8 = null,
    result_handle: ?*anyopaque = null,
};
// ------------------------------------------------------------------------------------------------------------|

// ZdsOptimalEstimationBatchRequest ---------------------------------------------------------------------------|
// Multi-run retrieval request sharing one measurement grid and one fixed state template across run priors.    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 224 B (0.219 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] sample_count           : usize                                                                   |
// [  8.. 15] wavelength_nm          : ?[*]const f64                                                           |
// [ 16.. 23] reflectance            : ?[*]const f64                                                           |
// [ 24.. 31] variance               : ?[*]const f64                                                           |
// [ 32.. 79] aerosol_optical_depth  : ZdsOptimalEstimationScalarSpec                                          |
// [ 80..167] aerosol_layer_pressure : ZdsOptimalEstimationPressureSpec                                        |
// [168..175] run_count              : usize                                                                   |
// [176..183] initial                : ?[*]const f64                                                           |
// [184..191] prior                  : ?[*]const f64                                                           |
// [192..215] controls               : ZdsOptimalEstimationControls                                            |
// [216..223] batch_worker_count     : usize                                                                   |
//                                                                                                             |
// referenced storage                                                                                          |
//   measurement arrays, pressure-profile rows, and run initial/prior arrays borrow caller buffers.            |
pub const ZdsOptimalEstimationBatchRequest = extern struct {
    sample_count: usize = 0,
    wavelength_nm: ?[*]const f64 = null,
    reflectance: ?[*]const f64 = null,
    variance: ?[*]const f64 = null,
    aerosol_optical_depth: ZdsOptimalEstimationScalarSpec = .{},
    aerosol_layer_pressure: ZdsOptimalEstimationPressureSpec = .{},
    run_count: usize = 0,
    initial: ?[*]const f64 = null,
    prior: ?[*]const f64 = null,
    controls: ZdsOptimalEstimationControls = .{},
    batch_worker_count: usize = 1,
};
// ------------------------------------------------------------------------------------------------------------|

// ZdsOptimalEstimationBatchResult ----------------------------------------------------------------------------|
// Borrowed batch retrieval output backed by a native BatchResult handle.                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 72 B (0.070 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] run_count        : usize                                                                           |
// [ 8..15] state_count      : usize                                                                           |
// [16..23] history_capacity : usize                                                                           |
// [24..31] iteration_count  : ?[*]const usize                                                                 |
// [32..39] converged        : ?[*]const u8                                                                    |
// [40..47] status           : ?[*]const u8                                                                    |
// [48..55] state            : ?[*]const f64                                                                   |
// [56..63] history_state    : ?[*]const f64                                                                   |
// [64..71] result_handle    : ?*anyopaque                                                                     |
//                                                                                                             |
// referenced storage                                                                                          |
//   pointer fields borrow native batch result arrays until zds_optimal_estimation_batch_result_free.          |
pub const ZdsOptimalEstimationBatchResult = extern struct {
    run_count: usize = 0,
    state_count: usize = 0,
    history_capacity: usize = 0,
    iteration_count: ?[*]const usize = null,
    converged: ?[*]const u8 = null,
    status: ?[*]const u8 = null,
    state: ?[*]const f64 = null,
    history_state: ?[*]const f64 = null,
    result_handle: ?*anyopaque = null,
};
// ------------------------------------------------------------------------------------------------------------|

// ZdsOptimalEstimationFastmodeBatchResult --------------------------------------------------------------------|
// Borrowed fastmode batch output with per-stage iteration and convergence arrays.                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 104 B (0.102 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] run_count                       : usize                                                          |
// [  8.. 15] state_count                     : usize                                                          |
// [ 16.. 23] history_capacity                : usize                                                          |
// [ 24.. 31] iteration_count                 : ?[*]const usize                                                |
// [ 32.. 39] converged                       : ?[*]const u8                                                   |
// [ 40.. 47] status                          : ?[*]const u8                                                   |
// [ 48.. 55] state                           : ?[*]const f64                                                  |
// [ 56.. 63] history_state                   : ?[*]const f64                                                  |
// [ 64.. 71] fast_stage_iteration_count      : ?[*]const usize                                                |
// [ 72.. 79] fast_stage_converged            : ?[*]const u8                                                   |
// [ 80.. 87] full_correction_iteration_count : ?[*]const usize                                                |
// [ 88.. 95] full_correction_converged       : ?[*]const u8                                                   |
// [ 96..103] result_handle                   : ?*anyopaque                                                    |
//                                                                                                             |
// referenced storage                                                                                          |
//   pointer fields borrow native fastmode arrays until the matching fastmode result free call.                |
pub const ZdsOptimalEstimationFastmodeBatchResult = extern struct {
    run_count: usize = 0,
    state_count: usize = 0,
    history_capacity: usize = 0,
    iteration_count: ?[*]const usize = null,
    converged: ?[*]const u8 = null,
    status: ?[*]const u8 = null,
    state: ?[*]const f64 = null,
    history_state: ?[*]const f64 = null,
    fast_stage_iteration_count: ?[*]const usize = null,
    fast_stage_converged: ?[*]const u8 = null,
    full_correction_iteration_count: ?[*]const usize = null,
    full_correction_converged: ?[*]const u8 = null,
    result_handle: ?*anyopaque = null,
};
// ------------------------------------------------------------------------------------------------------------|

// ZdsAtmosphericBudget ---------------------------------------------------------------------------------------|
// Borrowed atmospheric-budget rows returned by zds_atmospheric_budget. rows owns a Context-free allocation.   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] len : usize                                                                                         |
// [8..15] rows: ?[*]const AtmosphericBudgetRow                                                                |
pub const ZdsAtmosphericBudget = extern struct {
    len: usize = 0,
    rows: ?[*]const zdisamar.AtmosphericBudgetRow = null,
};
// ------------------------------------------------------------------------------------------------------------|

// ZdsO2LineContributions -------------------------------------------------------------------------------------|
// Borrowed O2 line-contribution rows returned by zds_o2_line_contributions. rows owns a Context-free          |
// allocation.                                                                                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] len            : usize                                                                             |
// [ 8..15] total_row_count: usize                                                                             |
// [16..16] truncated      : u8                                                                                |
// [17..23] padding        : 7 B                                                                               |
// [24..31] rows           : ?[*]const LineContributionRow                                                     |
pub const ZdsO2LineContributions = extern struct {
    len: usize = 0,
    total_row_count: usize = 0,
    truncated: u8 = 0,
    rows: ?[*]const zdisamar.LineContributionRow = null,
};
// ------------------------------------------------------------------------------------------------------------|

// ZdsInstrumentResponse --------------------------------------------------------------------------------------|
// Borrowed instrument-response rows returned by zds_instrument_response_sampling. rows owns a Context-free    |
// allocation.                                                                                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] len : usize                                                                                         |
// [8..15] rows: ?[*]const InstrumentResponseRow                                                               |
pub const ZdsInstrumentResponse = extern struct {
    len: usize = 0,
    rows: ?[*]const zdisamar.InstrumentResponseRow = null,
};
// ------------------------------------------------------------------------------------------------------------|

// ZdsO2O2CIADiagnostics --------------------------------------------------------------------------------------|
// Borrowed O2-O2 CIA rows returned by zds_o2_o2_cia_diagnostics. rows owns a Context-free allocation.         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] len : usize                                                                                         |
// [8..15] rows: ?[*]const CiaRow                                                                              |
pub const ZdsO2O2CIADiagnostics = extern struct {
    len: usize = 0,
    rows: ?[*]const zdisamar.CiaRow = null,
};
// ------------------------------------------------------------------------------------------------------------|

// CResult ----------------------------------------------------------------------------------------------------|
// Context-owned native spectrum plus optional compact C-facing Jacobian rows.                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 176 B (0.172 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..151] native          : SpectrumRunResult                                                              |
// [152..167] compact_jacobian: []f64                                                                          |
// [168..175] state_count     : usize                                                                          |
const CResult = struct {
    native: zdisamar.SpectrumRunResult = .{},
    compact_jacobian: []f64 = &.{},
    state_count: usize = 0,

    fn deinit(self: *CResult) void {
        // CResult.deinit -------------------------------------------------------------------------------------|
        // Release the native spectrum and optional compact Jacobian copy.                                     |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.compact_jacobian);
        self.native.deinit(allocator);
        self.* = .{};
    }
};
// ------------------------------------------------------------------------------------------------------------|

// Context ----------------------------------------------------------------------------------------------------|
// Native owner behind the opaque C handle.                                                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// Debug build: size 8320 B (8.125 KiB), align 8                                                               |
// optimized  : size 8312 B (8.117 KiB), align 8                                                               |
//                                                                                                             |
// memory                                                                                                      |
// [   0..1751] parsed    : ?ParsedSceneJson                                                                   |
// [1752..4487] prepared  : ?Prepared                                                                          |
// [4488..7959] session   : SessionMemory in Debug                                                             |
// [4488..7951] session   : SessionMemory in optimized builds                                                  |
// [7960..7983] results   : ArrayList(*CResult) in Debug                                                       |
// [7952..7975] results   : ArrayList(*CResult) in optimized builds                                            |
// [7984..8007] oe_results: ArrayList(*RetrievalResult) in Debug                                               |
// [7976..7999] oe_results: ArrayList(*RetrievalResult) in optimized builds                                    |
// [8008..8031] oe_batch_results: ArrayList(*RetrievalBatchResult) in Debug                                    |
// [8000..8023] oe_batch_results: ArrayList(*RetrievalBatchResult) in optimized builds                         |
// [8032..8055] oe_fastmode_batch_results: ArrayList(*RetrievalFastmodeBatchResult) in Debug                   |
// [8024..8047] oe_fastmode_batch_results: ArrayList(*RetrievalFastmodeBatchResult) in optimized builds        |
// [8056..8311] last_error: [256:0]u8 in Debug                                                                 |
// [8048..8303] last_error: [256:0]u8 in optimized builds                                                      |
// [8312..8319] trailing padding: 8 B in Debug                                                                 |
// [8304..8311] trailing padding: 8 B in optimized builds                                                      |
//                                                                                                             |
// referenced storage                                                                                          |
//   parsed owns JSON arena storage borrowed by prepared.case for zds_prepare_o2a_json.                        |
pub const Context = struct {
    parsed: ?zdisamar.ParsedSceneJson = null,
    prepared: ?zdisamar.Prepared = null,
    session: zdisamar.SessionMemory,
    results: std.ArrayList(*CResult) = .empty,
    oe_results: std.ArrayList(*zdisamar.RetrievalResult) = .empty,
    oe_batch_results: std.ArrayList(*zdisamar.RetrievalBatchResult) = .empty,
    oe_fastmode_batch_results: std.ArrayList(*zdisamar.RetrievalFastmodeBatchResult) = .empty,
    last_error: [256:0]u8 = [_:0]u8{0} ** 256,

    fn init() Context {
        // Context.init ---------------------------------------------------------------------------------------|
        // Create an empty API context with initialized session memory.                                        |
        // ----------------------------------------------------------------------------------------------------|
        return .{ .session = zdisamar.initSessionMemory(allocator) };
    }

    fn deinit(self: *Context) void {
        // Context.deinit -------------------------------------------------------------------------------------|
        // Release prepared setup, retained session rows, and any live spectrum handles.                       |
        // ----------------------------------------------------------------------------------------------------|
        for (self.results.items) |result| {
            result.deinit();
            allocator.destroy(result);
        }
        self.results.deinit(allocator);
        clearStoredResults(zdisamar.RetrievalResult, &self.oe_results);
        clearStoredResults(zdisamar.RetrievalBatchResult, &self.oe_batch_results);
        clearStoredResults(zdisamar.RetrievalFastmodeBatchResult, &self.oe_fastmode_batch_results);
        self.clearPrepared();
        self.session.deinit(allocator);
        self.* = undefined;
    }

    fn clearPrepared(self: *Context) void {
        // Context.clearPrepared ------------------------------------------------------------------------------|
        // Release prepared tables before parsed JSON storage that may back prepared.case slices.              |
        // ----------------------------------------------------------------------------------------------------|
        if (self.prepared) |*prepared| prepared.deinit(allocator);
        self.prepared = null;
        if (self.parsed) |*parsed| parsed.deinit();
        self.parsed = null;
    }

    fn setError(self: *Context, message: []const u8) void {
        // Context.setError -----------------------------------------------------------------------------------|
        // Store a nul-terminated bounded error message for zds_last_error.                                    |
        // ----------------------------------------------------------------------------------------------------|
        @memset(self.last_error[0..], 0);
        const n = @min(message.len, self.last_error.len - 1);
        @memcpy(self.last_error[0..n], message[0..n]);
    }

    fn ownsResult(self: *const Context, result: *const CResult) bool {
        // Context.ownsResult ---------------------------------------------------------------------------------|
        // Check whether a CResult handle is still retained by this context.                                   |
        // ----------------------------------------------------------------------------------------------------|
        for (self.results.items) |stored| {
            if (stored == result) return true;
        }
        return false;
    }
};
// ------------------------------------------------------------------------------------------------------------|

fn clearStoredResults(comptime Item: type, list: *std.ArrayList(*Item)) void {
    // clearStoredResults -------------------------------------------------------------------------------------|
    // Release one Context-owned family of native result handles.                                              |
    // --------------------------------------------------------------------------------------------------------|
    for (list.items) |result| {
        result.deinit(allocator);
        allocator.destroy(result);
    }
    list.deinit(allocator);
    list.* = .empty;
}

fn destroyStoredResult(comptime Item: type, list: *std.ArrayList(*Item), result: *Item) void {
    // destroyStoredResult ------------------------------------------------------------------------------------|
    // Remove and free one retained handle when the matching C result free hook is called.                     |
    // --------------------------------------------------------------------------------------------------------|
    for (list.items, 0..) |stored, index| {
        if (stored == result) {
            _ = list.swapRemove(index);
            result.deinit(allocator);
            allocator.destroy(result);
            return;
        }
    }
}

pub export fn zds_context_create() ?*Context {
    // zds_context_create -------------------------------------------------------------------------------------|
    // Allocate one opaque C context for Python or external callers.                                           |
    // --------------------------------------------------------------------------------------------------------|
    const ctx = allocator.create(Context) catch return null;
    ctx.* = Context.init();
    return ctx;
}

pub export fn zds_context_destroy(ctx: ?*Context) void {
    // zds_context_destroy ------------------------------------------------------------------------------------|
    // Release a context and every result handle still retained by it.                                         |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return;
    resolved.deinit();
    allocator.destroy(resolved);
}

pub export fn zds_prepare_o2a_json(ctx: ?*Context, json_ptr: ?[*]const u8, json_len: usize) c_int {
    // zds_prepare_o2a_json -----------------------------------------------------------------------------------|
    // Parse Python's native O2 A JSON shape and prepare the resulting typed case.                             |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);

    if (json_ptr == null) {
        resolved.setError("null input JSON");
        return @intFromEnum(ZdsStatus.failure);
    }

    if (json_len == 0) {
        resolved.setError("empty input JSON");
        return @intFromEnum(ZdsStatus.failure);
    }

    const payload = json_ptr.?[0..json_len];
    var parsed = zdisamar.parseSceneJson(allocator, payload) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer parsed.deinit();

    var prepared = zdisamar.prepare(allocator, parsed.scene) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer prepared.deinit(allocator);

    resolved.clearPrepared();
    resolved.parsed = parsed;
    resolved.prepared = prepared;
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_warm_o2a_session(ctx: ?*Context) c_int {
    // zds_warm_o2a_session -----------------------------------------------------------------------------------|
    // Build retained session rows for the prepared O2 A case.                                                 |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);

    const prepared = &(resolved.prepared orelse {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    });

    var solve_config = zdisamar.solveConfig(prepared.scene);
    solve_config.derivative_mode = .none;
    solve_config.wants_jacobian = false;

    zdisamar.warmSessionMemory(
        allocator,
        &resolved.session,
        prepared,
        solve_config,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

pub export fn zds_warm_o2a_optimal_estimation(
    ctx: ?*Context,
) c_int {
    // zds_warm_o2a_optimal_estimation ------------------------------------------------------------------------|
    // Warm the session cache for the fixed two-lane semi-analytical Jacobian needed by OE.                    |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);

    const prepared = &(resolved.prepared orelse {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    });

    var solve_config = zdisamar.solveConfig(prepared.scene);
    solve_config.derivative_mode = .semi_analytical;
    solve_config.wants_jacobian = true;

    zdisamar.warmSessionMemory(
        allocator,
        &resolved.session,
        prepared,
        solve_config,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

pub export fn zds_run_spectrum(ctx: ?*Context, out: ?*ZdsSpectrum) c_int {
    // zds_run_spectrum ---------------------------------------------------------------------------------------|
    // Run the prepared case without returning Jacobian columns.                                               |
    // --------------------------------------------------------------------------------------------------------|
    return runSpectrum(ctx, out, false);
}

export fn zds_run_spectrum_jacobian(ctx: ?*Context, out: ?*ZdsSpectrum) c_int {
    // zds_run_spectrum_jacobian ------------------------------------------------------------------------------|
    // Run the prepared case with all fixed Jacobian columns in public order.                                  |
    // --------------------------------------------------------------------------------------------------------|
    return runSpectrum(ctx, out, true);
}

export fn zds_spectrum_report(ctx: ?*Context, spectrum: ?*const ZdsSpectrum, out: ?*ZdsDiagnosticReport) c_int {
    // zds_spectrum_report ------------------------------------------------------------------------------------|
    // Summarize one live spectrum handle into scalar means.                                                   |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);

    const raw = spectrum orelse {
        resolved.setError("null spectrum");
        return @intFromEnum(ZdsStatus.failure);
    };

    const report = out orelse {
        resolved.setError("null diagnostic report");
        return @intFromEnum(ZdsStatus.failure);
    };

    const handle = raw.result_handle orelse {
        resolved.setError("spectrum is closed");
        return @intFromEnum(ZdsStatus.failure);
    };

    const result: *CResult = @ptrCast(@alignCast(handle));
    if (!resolved.ownsResult(result)) {
        resolved.setError("unknown spectrum result");
        return @intFromEnum(ZdsStatus.failure);
    }

    report.* = spectrumReport(result.native.spectrum);
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_atmospheric_budget(
    ctx: ?*Context,
    wavelengths: ?[*]const f64,
    wavelength_count: usize,
    out: ?*ZdsAtmosphericBudget,
) c_int {
    // zds_atmospheric_budget ---------------------------------------------------------------------------------|
    // Build atmospheric support-row diagnostic records for caller-selected wavelengths.                       |
    // --------------------------------------------------------------------------------------------------------|
    return runWavelengthDiagnostic(.atmospheric_budget, ctx, wavelengths, wavelength_count, {}, out);
}

export fn zds_o2_line_contributions(
    ctx: ?*Context,
    wavelengths: ?[*]const f64,
    wavelength_count: usize,
    max_rows: usize,
    out: ?*ZdsO2LineContributions,
) c_int {
    // zds_o2_line_contributions ------------------------------------------------------------------------------|
    // Build O2 line-by-line diagnostic rows for caller-selected wavelengths.                                  |
    // --------------------------------------------------------------------------------------------------------|
    return runWavelengthDiagnostic(.line_contributions, ctx, wavelengths, wavelength_count, max_rows, out);
}

export fn zds_instrument_response_sampling(
    ctx: ?*Context,
    wavelengths: ?[*]const f64,
    wavelength_count: usize,
    channel_mask: u32,
    out: ?*ZdsInstrumentResponse,
) c_int {
    // zds_instrument_response_sampling -----------------------------------------------------------------------|
    // Build instrument-response support rows for caller-selected wavelengths and channel mask.                |
    // --------------------------------------------------------------------------------------------------------|
    return runWavelengthDiagnostic(.instrument_response, ctx, wavelengths, wavelength_count, channel_mask, out);
}

export fn zds_o2_o2_cia_diagnostics(
    ctx: ?*Context,
    wavelengths: ?[*]const f64,
    wavelength_count: usize,
    out: ?*ZdsO2O2CIADiagnostics,
) c_int {
    // zds_o2_o2_cia_diagnostics ------------------------------------------------------------------------------|
    // Build O2-O2 CIA diagnostic rows for caller-selected wavelengths.                                        |
    // --------------------------------------------------------------------------------------------------------|
    return runWavelengthDiagnostic(.cia_diagnostics, ctx, wavelengths, wavelength_count, {}, out);
}

// OptimalEstimationMeasurementSlices -------------------------------------------------------------------------|
// Checked view of caller-owned measurement arrays.                                                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] wavelength_nm : []const f64                                                                        |
// [16..31] reflectance   : []const f64                                                                        |
// [32..47] variance      : []const f64                                                                        |
//                                                                                                             |
// referenced storage                                                                                          |
//   All slices borrow caller-owned C buffers after null and length validation.                                |
const OptimalEstimationMeasurementSlices = struct {
    wavelength_nm: []const f64,
    reflectance: []const f64,
    variance: []const f64,
};
// ------------------------------------------------------------------------------------------------------------|

// OptimalEstimationFixedState --------------------------------------------------------------------------------|
// Request-scoped fixed native state plus pressure-profile spline scratch.                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 312 B (0.305 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..95] profiles: [2]PressureAltitudeProfile                                                               |
// [96..  ] state   : RetrievalState                                                                           |
//                                                                                                             |
// referenced storage                                                                                          |
//   Pressure-profile second-derivative arrays are owned until the C call returns and deinit frees them.       |
const OptimalEstimationFixedState = struct {
    profiles: [zdisamar.optimal_estimation.max_state_count]zdisamar.RetrievalPressureAltitudeProfile =
        [_]zdisamar.RetrievalPressureAltitudeProfile{.{}} ** zdisamar.optimal_estimation.max_state_count,
    state: zdisamar.RetrievalState = undefined,

    fn deinit(self: *OptimalEstimationFixedState) void {
        // OptimalEstimationFixedState.deinit -----------------------------------------------------------------|
        // Release request-scoped pressure-profile spline scratch.                                             |
        // ----------------------------------------------------------------------------------------------------|
        for (&self.profiles) |*profile| {
            if (profile.hasSamples()) {
                zdisamar.optimal_estimation.freePressureProfile(allocator, profile.*);
                profile.* = .{};
            }
        }
    }

    fn retrievalState(self: *const OptimalEstimationFixedState) zdisamar.RetrievalState {
        // OptimalEstimationFixedState.retrievalState ---------------------------------------------------------|
        // Return the fixed native state parsed from the named C request fields.                               |
        // ----------------------------------------------------------------------------------------------------|
        return self.state;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// OptimalEstimationRequestView -------------------------------------------------------------------------------|
// Normalized single-run request rows consumed by the native retrieval and correction solvers.                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 384 B (0.375 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 47] measurement: OptimalEstimationMeasurementSlices                                                  |
// [ 48.. 71] controls   : Controls                                                                            |
// [ 72..383] fixed_state: OptimalEstimationFixedState                                                         |
const OptimalEstimationRequestView = struct {
    measurement: OptimalEstimationMeasurementSlices,
    controls: zdisamar.optimal_estimation.Controls,
    fixed_state: OptimalEstimationFixedState,

    fn deinit(self: *OptimalEstimationRequestView) void {
        // OptimalEstimationRequestView.deinit ----------------------------------------------------------------|
        // Release request-scoped fixed-state side data.                                                       |
        // ----------------------------------------------------------------------------------------------------|
        self.fixed_state.deinit();
    }
};
// ------------------------------------------------------------------------------------------------------------|

// OptimalEstimationBatchRequestView --------------------------------------------------------------------------|
// Normalized batch request rows consumed by the native batch solver.                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 448 B (0.438 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 47] measurement        : OptimalEstimationMeasurementSlices                                          |
// [ 48.. 71] controls           : Controls                                                                    |
// [ 72..383] state_template     : OptimalEstimationFixedState                                                 |
// [384..399] initial            : []const f64                                                                 |
// [400..415] prior              : []const f64                                                                 |
// [416..423] run_count          : usize                                                                       |
// [424..431] state_count        : usize                                                                       |
// [432..439] total_state_count  : usize                                                                       |
// [440..447] batch_worker_count : usize                                                                       |
const OptimalEstimationBatchRequestView = struct {
    measurement: OptimalEstimationMeasurementSlices,
    controls: zdisamar.optimal_estimation.Controls,
    state_template: OptimalEstimationFixedState,
    initial: []const f64,
    prior: []const f64,
    run_count: usize,
    state_count: usize,
    total_state_count: usize,
    batch_worker_count: usize,

    fn deinit(self: *OptimalEstimationBatchRequestView) void {
        // OptimalEstimationBatchRequestView.deinit -----------------------------------------------------------|
        // Release request-scoped template side data.                                                          |
        // ----------------------------------------------------------------------------------------------------|
        self.state_template.deinit();
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub export fn zds_run_o2a_optimal_estimation(
    ctx: ?*Context,
    request: ?*const ZdsOptimalEstimationRequest,
    out: ?*ZdsOptimalEstimationResult,
) c_int {
    // zds_run_o2a_optimal_estimation -------------------------------------------------------------------------|
    // Run one full-physics OE solve and return a borrowed result view backed by a Context-owned handle.       |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);

    const output = out orelse {
        resolved.setError("null optimal-estimation result");
        return @intFromEnum(ZdsStatus.failure);
    };
    output.* = .{};

    const prepared = &(resolved.prepared orelse {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    });

    if (rejectMultiLayerAerosolProfileRetrieval(resolved)) |status| return status;

    var request_view = optimalEstimationRequestView(resolved, request) catch {
        return @intFromEnum(ZdsStatus.failure);
    };
    defer request_view.deinit();

    const result = allocator.create(zdisamar.RetrievalResult) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer allocator.destroy(result);
    result.* = zdisamar.runOptimalEstimation(
        allocator,
        &resolved.session,
        prepared,
        request_view.measurement.wavelength_nm,
        request_view.measurement.reflectance,
        request_view.measurement.variance,
        request_view.fixed_state.retrievalState(),
        request_view.controls,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer result.deinit(allocator);

    resolved.oe_results.append(allocator, result) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    output.* = optimalEstimationResultView(result);
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

pub export fn zds_run_o2a_optimal_estimation_correction(
    ctx: ?*Context,
    request: ?*const ZdsOptimalEstimationRequest,
    out: ?*ZdsOptimalEstimationResult,
) c_int {
    // zds_run_o2a_optimal_estimation_correction --------------------------------------------------------------|
    // Run one prepared-case full-physics correction step and return a Context-owned result handle.            |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);

    const output = out orelse {
        resolved.setError("null optimal-estimation result");
        return @intFromEnum(ZdsStatus.failure);
    };
    output.* = .{};

    const prepared = &(resolved.prepared orelse {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    });

    if (rejectMultiLayerAerosolProfileRetrieval(resolved)) |status| return status;

    var request_view = optimalEstimationRequestView(resolved, request) catch {
        return @intFromEnum(ZdsStatus.failure);
    };
    defer request_view.deinit();

    const result = allocator.create(zdisamar.RetrievalResult) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer allocator.destroy(result);
    result.* = zdisamar.runOptimalEstimationCorrection(
        allocator,
        &resolved.session,
        prepared,
        request_view.measurement.wavelength_nm,
        request_view.measurement.reflectance,
        request_view.measurement.variance,
        request_view.fixed_state.retrievalState(),
        request_view.controls,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer result.deinit(allocator);

    resolved.oe_results.append(allocator, result) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    output.* = optimalEstimationResultView(result);
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

pub export fn zds_run_o2a_optimal_estimation_batch(
    ctx: ?*Context,
    request: ?*const ZdsOptimalEstimationBatchRequest,
    out: ?*ZdsOptimalEstimationBatchResult,
) c_int {
    // zds_run_o2a_optimal_estimation_batch -------------------------------------------------------------------|
    // Run one full-physics single-worker batch and return a Context-owned result handle.                      |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);

    const output = out orelse {
        resolved.setError("null optimal-estimation batch result");
        return @intFromEnum(ZdsStatus.failure);
    };
    output.* = .{};

    const prepared = &(resolved.prepared orelse {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    });

    if (rejectMultiLayerAerosolProfileRetrieval(resolved)) |status| return status;

    var request_view = optimalEstimationBatchRequestView(resolved, request) catch {
        return @intFromEnum(ZdsStatus.failure);
    };
    defer request_view.deinit();

    const result = allocator.create(zdisamar.RetrievalBatchResult) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer allocator.destroy(result);
    result.* = zdisamar.runOptimalEstimationBatch(
        allocator,
        &resolved.session,
        prepared,
        request_view.measurement.wavelength_nm,
        request_view.measurement.reflectance,
        request_view.measurement.variance,
        request_view.state_template.retrievalState(),
        request_view.initial,
        request_view.prior,
        request_view.controls,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer result.deinit(allocator);

    resolved.oe_batch_results.append(allocator, result) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    output.* = optimalEstimationBatchResultView(result);
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

pub export fn zds_run_o2a_fastmode_optimal_estimation_batch(
    fast_ctx: ?*Context,
    correction_ctx: ?*Context,
    fast_request: ?*const ZdsOptimalEstimationBatchRequest,
    correction_request: ?*const ZdsOptimalEstimationBatchRequest,
    out: ?*ZdsOptimalEstimationFastmodeBatchResult,
) c_int {
    // zds_run_o2a_fastmode_optimal_estimation_batch ----------------------------------------------------------|
    // Run fast-stage and full-correction batches through paired prepared contexts.                            |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = fast_ctx orelse return @intFromEnum(ZdsStatus.failure);

    const correction = correction_ctx orelse {
        resolved.setError("null correction context");
        return @intFromEnum(ZdsStatus.failure);
    };

    const output = out orelse {
        resolved.setError("null optimal-estimation fastmode batch result");
        return @intFromEnum(ZdsStatus.failure);
    };
    output.* = .{};

    const fast_prepared = &(resolved.prepared orelse {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    });

    const correction_prepared = &(correction.prepared orelse {
        resolved.setError("correction context not prepared");
        return @intFromEnum(ZdsStatus.failure);
    });

    if (rejectMultiLayerAerosolProfileRetrieval(resolved)) |status| return status;

    if (rejectMultiLayerAerosolProfileRetrieval(correction)) |_| {
        resolved.setError("multi-layer aerosol profiles are forward-simulation only");
        return @intFromEnum(ZdsStatus.failure);
    }

    var fast_view = optimalEstimationBatchRequestView(resolved, fast_request) catch {
        return @intFromEnum(ZdsStatus.failure);
    };
    defer fast_view.deinit();

    var correction_view = optimalEstimationBatchRequestView(resolved, correction_request) catch {
        return @intFromEnum(ZdsStatus.failure);
    };
    defer correction_view.deinit();

    if (fast_view.run_count != correction_view.run_count) {
        resolved.setError("fastmode request shapes do not match");
        return @intFromEnum(ZdsStatus.failure);
    }

    const result = allocator.create(zdisamar.RetrievalFastmodeBatchResult) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer allocator.destroy(result);
    result.* = zdisamar.runFastmodeOptimalEstimationBatch(
        allocator,
        &resolved.session,
        &correction.session,
        fast_prepared,
        fast_view.measurement.wavelength_nm,
        fast_view.measurement.reflectance,
        fast_view.measurement.variance,
        fast_view.state_template.retrievalState(),
        fast_view.initial,
        fast_view.prior,
        fast_view.controls,
        correction_prepared,
        correction_view.measurement.wavelength_nm,
        correction_view.measurement.reflectance,
        correction_view.measurement.variance,
        correction_view.state_template.retrievalState(),
        correction_view.prior,
        correction_view.controls,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer result.deinit(allocator);

    resolved.oe_fastmode_batch_results.append(allocator, result) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    output.* = optimalEstimationFastmodeBatchResultView(result);
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

pub export fn zds_spectrum_free(ctx: ?*Context, out: ?*ZdsSpectrum) void {
    // zds_spectrum_free --------------------------------------------------------------------------------------|
    // Release one live spectrum handle returned by this context.                                              |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return;
    const raw = out orelse return;

    if (raw.result_handle) |handle| {
        const result: *CResult = @ptrCast(@alignCast(handle));
        destroyResult(resolved, result);
    }

    raw.* = .{};
}

pub export fn zds_optimal_estimation_result_free(ctx: ?*Context, out: ?*ZdsOptimalEstimationResult) void {
    // zds_optimal_estimation_result_free ---------------------------------------------------------------------|
    // Release one single-run optimal-estimation result handle returned by this context.                       |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return;
    const output = out orelse return;
    if (output.result_handle) |handle| {
        const result: *zdisamar.RetrievalResult = @ptrCast(@alignCast(handle));
        destroyStoredResult(zdisamar.RetrievalResult, &resolved.oe_results, result);
    }
    output.* = .{};
}

pub export fn zds_optimal_estimation_batch_result_free(ctx: ?*Context, out: ?*ZdsOptimalEstimationBatchResult) void {
    // zds_optimal_estimation_batch_result_free ---------------------------------------------------------------|
    // Release one batch optimal-estimation result handle returned by this context.                            |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return;
    const output = out orelse return;
    if (output.result_handle) |handle| {
        const result: *zdisamar.RetrievalBatchResult = @ptrCast(@alignCast(handle));
        destroyStoredResult(zdisamar.RetrievalBatchResult, &resolved.oe_batch_results, result);
    }
    output.* = .{};
}

pub export fn zds_optimal_estimation_fastmode_batch_result_free(
    ctx: ?*Context,
    out: ?*ZdsOptimalEstimationFastmodeBatchResult,
) void {
    // zds_optimal_estimation_fastmode_batch_result_free ------------------------------------------------------|
    // Release one fastmode batch result handle returned by this context.                                      |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return;
    const output = out orelse return;
    if (output.result_handle) |handle| {
        const result: *zdisamar.RetrievalFastmodeBatchResult = @ptrCast(@alignCast(handle));
        destroyStoredResult(
            zdisamar.RetrievalFastmodeBatchResult,
            &resolved.oe_fastmode_batch_results,
            result,
        );
    }
    output.* = .{};
}

export fn zds_atmospheric_budget_free(_: ?*Context, raw: ?*ZdsAtmosphericBudget) void {
    // zds_atmospheric_budget_free ----------------------------------------------------------------------------|
    // Release atmospheric-budget rows returned by zds_atmospheric_budget.                                     |
    // --------------------------------------------------------------------------------------------------------|
    const budget = raw orelse return;
    if (budget.rows) |rows| {
        allocator.free(rows[0..budget.len]);
    }
    budget.* = .{};
}

export fn zds_o2_line_contributions_free(_: ?*Context, raw: ?*ZdsO2LineContributions) void {
    // zds_o2_line_contributions_free -------------------------------------------------------------------------|
    // Release O2 line-contribution rows returned by zds_o2_line_contributions.                                |
    // --------------------------------------------------------------------------------------------------------|
    const contributions = raw orelse return;
    if (contributions.rows) |rows| {
        allocator.free(rows[0..contributions.len]);
    }
    contributions.* = .{};
}

export fn zds_instrument_response_free(_: ?*Context, raw: ?*ZdsInstrumentResponse) void {
    // zds_instrument_response_free ---------------------------------------------------------------------------|
    // Release instrument-response rows returned by zds_instrument_response_sampling.                          |
    // --------------------------------------------------------------------------------------------------------|
    const response = raw orelse return;
    if (response.rows) |rows| {
        allocator.free(rows[0..response.len]);
    }
    response.* = .{};
}

export fn zds_o2_o2_cia_diagnostics_free(_: ?*Context, raw: ?*ZdsO2O2CIADiagnostics) void {
    // zds_o2_o2_cia_diagnostics_free -------------------------------------------------------------------------|
    // Release O2-O2 CIA rows returned by zds_o2_o2_cia_diagnostics.                                           |
    // --------------------------------------------------------------------------------------------------------|
    const diagnostics = raw orelse return;
    if (diagnostics.rows) |rows| {
        allocator.free(rows[0..diagnostics.len]);
    }
    diagnostics.* = .{};
}

pub export fn zds_last_error(ctx: ?*Context) [*:0]const u8 {
    // zds_last_error -----------------------------------------------------------------------------------------|
    // Return the context's last bounded nul-terminated error string.                                          |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return "null context";
    return @ptrCast(&resolved.last_error);
}

fn optimalEstimationRequestView(
    resolved: *Context,
    request: ?*const ZdsOptimalEstimationRequest,
) !OptimalEstimationRequestView {
    // optimalEstimationRequestView ---------------------------------------------------------------------------|
    // Convert one public C OE request into native fixed-state rows, then run value-level request validation.  |
    //                                                                                                         |
    //   rejected because the refactor fixed the product state space to aerosol optical depth and pressure.    |
    // --------------------------------------------------------------------------------------------------------|
    const resolved_request = request orelse {
        resolved.setError("null optimal-estimation request");
        return error.InvalidRetrievalState;
    };

    const measurement = optimalEstimationMeasurementSlices(resolved, resolved_request) orelse {
        return error.InvalidMeasurement;
    };
    const controls = optimalEstimationControls(resolved, resolved_request) orelse {
        return error.InvalidRetrievalState;
    };
    var fixed_state = try optimalEstimationFixedState(resolved, resolved_request);
    errdefer fixed_state.deinit();

    zdisamar.optimal_estimation.validateRetrievalState(fixed_state.retrievalState()) catch |err| {
        resolved.setError(@errorName(err));
        return err;
    };

    return .{
        .measurement = measurement,
        .controls = controls,
        .fixed_state = fixed_state,
    };
}

fn optimalEstimationBatchRequestView(
    resolved: *Context,
    request: ?*const ZdsOptimalEstimationBatchRequest,
) !OptimalEstimationBatchRequestView {
    // optimalEstimationBatchRequestView ----------------------------------------------------------------------|
    // Convert one C batch request into shared measurement rows, a shared state template, and run state slices.|
    //                                                                                                         |
    // guard                                                                                                   |
    //   run_count, state_count, initial/prior rows, and worker count are validated before future worker setup.|
    // --------------------------------------------------------------------------------------------------------|
    const resolved_request = request orelse {
        resolved.setError("null optimal-estimation batch request");
        return error.InvalidRetrievalState;
    };

    const measurement = optimalEstimationMeasurementSlices(resolved, resolved_request) orelse {
        return error.InvalidMeasurement;
    };
    const controls = optimalEstimationControls(resolved, resolved_request) orelse {
        return error.InvalidRetrievalState;
    };

    const run_count = resolved_request.run_count;
    const state_count = zdisamar.optimal_estimation.max_state_count;
    if (run_count == 0) {
        resolved.setError("empty optimal-estimation batch");
        return error.InvalidRetrievalState;
    }

    const batch_worker_count = resolved_request.batch_worker_count;
    if (batch_worker_count != 1) {
        resolved.setError("invalid optimal-estimation batch_worker_count");
        return error.InvalidRetrievalState;
    }

    const total_state_count = std.math.mul(usize, run_count, state_count) catch {
        resolved.setError("optimal-estimation batch is too large");
        return error.InvalidRetrievalState;
    };

    const initial_ptr = resolved_request.initial orelse {
        resolved.setError("null batch initial states");
        return error.InvalidRetrievalState;
    };

    const prior_ptr = resolved_request.prior orelse {
        resolved.setError("null batch prior states");
        return error.InvalidRetrievalState;
    };

    var state_template = try optimalEstimationFixedStateFromRaw(resolved, resolved_request);
    errdefer state_template.deinit();

    zdisamar.optimal_estimation.validateRetrievalState(state_template.retrievalState()) catch |err| {
        resolved.setError(@errorName(err));
        return err;
    };

    return .{
        .measurement = measurement,
        .controls = controls,
        .state_template = state_template,
        .initial = initial_ptr[0..total_state_count],
        .prior = prior_ptr[0..total_state_count],
        .run_count = run_count,
        .state_count = state_count,
        .total_state_count = total_state_count,
        .batch_worker_count = batch_worker_count,
    };
}

fn optimalEstimationMeasurementSlices(
    resolved: *Context,
    request: anytype,
) ?OptimalEstimationMeasurementSlices {
    // optimalEstimationMeasurementSlices ---------------------------------------------------------------------|
    // Borrow caller measurement buffers after null and empty-shape checks.                                    |
    //                                                                                                         |
    // --------------------------------------------------------------------------------------------------------|
    const wavelengths_ptr = request.wavelength_nm orelse {
        resolved.setError("null measurement wavelengths");
        return null;
    };

    const reflectance_ptr = request.reflectance orelse {
        resolved.setError("null measurement reflectance");
        return null;
    };

    const variance_ptr = request.variance orelse {
        resolved.setError("null measurement variance");
        return null;
    };

    if (request.sample_count == 0) {
        resolved.setError("empty measurement");
        return null;
    }
    return .{
        .wavelength_nm = wavelengths_ptr[0..request.sample_count],
        .reflectance = reflectance_ptr[0..request.sample_count],
        .variance = variance_ptr[0..request.sample_count],
    };
}

fn optimalEstimationControls(
    resolved: *Context,
    request: anytype,
) ?zdisamar.optimal_estimation.Controls {
    // optimalEstimationControls ------------------------------------------------------------------------------|
    // Copy OE iteration controls and reject impossible iteration counts at the ABI boundary.                  |
    //                                                                                                         |
    // --------------------------------------------------------------------------------------------------------|
    if (request.controls.max_iterations == 0 or
        request.controls.max_iterations > zdisamar.optimal_estimation.max_iteration_count)
    {
        resolved.setError("invalid optimal-estimation max_iterations");
        return null;
    }
    return .{
        .max_iterations = request.controls.max_iterations,
        .state_vector_convergence_threshold = request.controls.state_vector_convergence_threshold,
        .max_change_transformed_state = request.controls.max_change_transformed_state,
    };
}

fn optimalEstimationFixedState(
    resolved: *Context,
    request: *const ZdsOptimalEstimationRequest,
) !OptimalEstimationFixedState {
    // optimalEstimationFixedState ----------------------------------------------------------------------------|
    // Convert the single-run fixed state fields into native fixed-state rows.                                 |
    // --------------------------------------------------------------------------------------------------------|
    return optimalEstimationFixedStateFromRaw(resolved, request);
}

fn optimalEstimationFixedStateFromRaw(
    resolved: *Context,
    request: anytype,
) !OptimalEstimationFixedState {
    // optimalEstimationFixedStateFromRaw ---------------------------------------------------------------------|
    // Convert named C fixed-state fields into native retrieval state plus pressure-profile curvature.         |
    //                                                                                                         |
    // --------------------------------------------------------------------------------------------------------|
    var parsed: OptimalEstimationFixedState = .{};
    errdefer parsed.deinit();

    parsed.profiles[1] = try optimalEstimationPressureProfile(resolved, request.aerosol_layer_pressure);
    parsed.state = .{
        .aerosol_optical_depth = try optimalEstimationScalarSpec(
            resolved,
            request.aerosol_optical_depth,
        ),
        .aerosol_layer_mid_pressure = .{
            .scalar = try optimalEstimationScalarSpec(
                resolved,
                request.aerosol_layer_pressure.scalar,
            ),
            .placement = .{
                .thickness_hpa = request.aerosol_layer_pressure.thickness_hpa,
                .interval_index_1based = request.aerosol_layer_pressure.interval_index_1based,
                .pressure_altitude_profile = parsed.profiles[1],
            },
        },
    };
    try zdisamar.optimal_estimation.validateRetrievalState(parsed.state);
    return parsed;
}

fn optimalEstimationScalarSpec(
    resolved: *Context,
    raw: ZdsOptimalEstimationScalarSpec,
) !zdisamar.RetrievalStateScalar {
    // optimalEstimationScalarSpec ----------------------------------------------------------------------------|
    // Convert one named C scalar field into the native fixed-lane scalar.                                     |
    // --------------------------------------------------------------------------------------------------------|
    if (raw.has_lower != 0 and !std.math.isFinite(raw.lower)) {
        resolved.setError("invalid optimal-estimation lower bound");
        return error.InvalidRetrievalState;
    }

    if (raw.has_upper != 0 and !std.math.isFinite(raw.upper)) {
        resolved.setError("invalid optimal-estimation upper bound");
        return error.InvalidRetrievalState;
    }

    const lower_bound = if (raw.has_lower != 0) raw.lower else zdisamar.optimal_estimation.no_lower_bound;
    const upper_bound = if (raw.has_upper != 0) raw.upper else zdisamar.optimal_estimation.no_upper_bound;

    return .{
        .initial = raw.initial,
        .prior = raw.prior,
        .variance = raw.variance,
        .lower_bound = lower_bound,
        .upper_bound = upper_bound,
    };
}

fn optimalEstimationPressureProfile(
    resolved: *Context,
    raw: ZdsOptimalEstimationPressureSpec,
) !zdisamar.RetrievalPressureAltitudeProfile {
    // optimalEstimationPressureProfile -----------------------------------------------------------------------|
    // Build the request-scoped pressure-profile spline for aerosol-layer pressure retrieval rows.             |
    //                                                                                                         |
    // guard                                                                                                   |
    //   Both altitude and pressure C buffers are required for the pressure-state derivative conversion.       |
    // --------------------------------------------------------------------------------------------------------|
    const altitude_ptr = raw.pressure_profile_altitude_km orelse {
        resolved.setError("missing pressure profile altitude");
        return error.InvalidPressureProfile;
    };

    const pressure_ptr = raw.pressure_profile_pressure_hpa orelse {
        resolved.setError("missing pressure profile pressure");
        return error.InvalidPressureProfile;
    };

    return zdisamar.optimal_estimation.buildPressureProfile(
        allocator,
        altitude_ptr[0..raw.pressure_profile_count],
        pressure_ptr[0..raw.pressure_profile_count],
    ) catch |err| {
        resolved.setError(@errorName(err));
        return err;
    };
}

const WavelengthDiagnostic = enum {
    atmospheric_budget,
    line_contributions,
    instrument_response,
    cia_diagnostics,
};

fn DiagnosticExtra(comptime diagnostic: WavelengthDiagnostic) type {
    // DiagnosticExtra --------------------------------------------------------------------------------------- |
    // Compile each wavelength-diagnostic ABI wrapper with only the extra scalar it actually accepts.          |
    // --------------------------------------------------------------------------------------------------------|
    return switch (diagnostic) {
        .atmospheric_budget, .cia_diagnostics => void,
        .line_contributions => usize,
        .instrument_response => u32,
    };
}

fn DiagnosticOutput(comptime diagnostic: WavelengthDiagnostic) type {
    // DiagnosticOutput -------------------------------------------------------------------------------------- |
    // Map one diagnostic kind to its stable extern output struct.                                             |
    // --------------------------------------------------------------------------------------------------------|
    return switch (diagnostic) {
        .atmospheric_budget => ZdsAtmosphericBudget,
        .line_contributions => ZdsO2LineContributions,
        .instrument_response => ZdsInstrumentResponse,
        .cia_diagnostics => ZdsO2O2CIADiagnostics,
    };
}

fn DiagnosticResult(comptime diagnostic: WavelengthDiagnostic) type {
    // DiagnosticResult -------------------------------------------------------------------------------------- |
    // Map one diagnostic kind to the native owned row collection returned by root.zig.                        |
    // --------------------------------------------------------------------------------------------------------|
    return switch (diagnostic) {
        .atmospheric_budget => zdisamar.AtmosphericBudget,
        .line_contributions => zdisamar.LineContributions,
        .instrument_response => zdisamar.InstrumentResponse,
        .cia_diagnostics => zdisamar.CiaDiagnostics,
    };
}

fn runWavelengthDiagnostic(
    comptime diagnostic: WavelengthDiagnostic,
    ctx: ?*Context,
    wavelengths: ?[*]const f64,
    wavelength_count: usize,
    extra: DiagnosticExtra(diagnostic),
    out: ?*DiagnosticOutput(diagnostic),
) c_int {
    // runWavelengthDiagnostic ------------------------------------------------------------------------------- |
    // Shared C-ABI body for row diagnostics that are selected by wavelength list.                             |
    //                                                                                                         |
    // boundary                                                                                                |
    //   The exported zds_* functions keep their exact C signatures. This helper specializes the native        |
    //   builder, output struct, and extra scalar at comptime so no runtime tag or type-erased row pointer     |
    //   crosses the ABI boundary.                                                                             |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const prepared = &(resolved.prepared orelse {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    });

    const wavelengths_ptr = wavelengths orelse {
        resolved.setError("null wavelength input");
        return @intFromEnum(ZdsStatus.failure);
    };
    if (wavelength_count == 0) {
        resolved.setError("empty wavelength input");
        return @intFromEnum(ZdsStatus.failure);
    }

    if (diagnostic == .line_contributions and extra == 0) {
        resolved.setError("invalid O2 line contribution row limit");
        return @intFromEnum(ZdsStatus.failure);
    }

    const output = out orelse {
        resolved.setError(nullDiagnosticOutputMessage(diagnostic));
        return @intFromEnum(ZdsStatus.failure);
    };
    output.* = .{};

    var result = buildWavelengthDiagnostic(
        diagnostic,
        prepared,
        wavelengths_ptr[0..wavelength_count],
        extra,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer result.deinit(allocator);

    marshalWavelengthDiagnostic(diagnostic, output, &result);
    result.rows = &.{};
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

fn nullDiagnosticOutputMessage(comptime diagnostic: WavelengthDiagnostic) []const u8 {
    // nullDiagnosticOutputMessage --------------------------------------------------------------------------- |
    // Keep the previous per-export null-output error strings while sharing the control flow.                  |
    // --------------------------------------------------------------------------------------------------------|
    return switch (diagnostic) {
        .atmospheric_budget => "null atmospheric budget output",
        .line_contributions => "null O2 line contribution output",
        .instrument_response => "null instrument response output",
        .cia_diagnostics => "null O2-O2 CIA output",
    };
}

fn buildWavelengthDiagnostic(
    comptime diagnostic: WavelengthDiagnostic,
    prepared: *const zdisamar.Prepared,
    wavelengths_nm: []const f64,
    extra: DiagnosticExtra(diagnostic),
) !DiagnosticResult(diagnostic) {
    // buildWavelengthDiagnostic ----------------------------------------------------------------------------- |
    // Dispatch to the native root builder selected by the exported ABI wrapper.                               |
    // --------------------------------------------------------------------------------------------------------|
    return switch (diagnostic) {
        .atmospheric_budget => zdisamar.buildAtmosphericBudget(allocator, prepared, wavelengths_nm),
        .line_contributions => zdisamar.buildLineContributions(allocator, prepared, wavelengths_nm, extra),
        .instrument_response => zdisamar.buildInstrumentResponse(allocator, prepared, wavelengths_nm, extra),
        .cia_diagnostics => zdisamar.buildCiaDiagnostics(allocator, prepared, wavelengths_nm),
    };
}

fn marshalWavelengthDiagnostic(
    comptime diagnostic: WavelengthDiagnostic,
    output: *DiagnosticOutput(diagnostic),
    result: *const DiagnosticResult(diagnostic),
) void {
    // marshalWavelengthDiagnostic --------------------------------------------------------------------------- |
    // Move native row ownership to the stable C-facing output struct without copying rows.                    |
    // --------------------------------------------------------------------------------------------------------|
    switch (diagnostic) {
        .atmospheric_budget => output.* = .{
            .len = result.rows.len,
            .rows = diagnosticRowsPointer(zdisamar.AtmosphericBudgetRow, result.rows),
        },
        .line_contributions => output.* = .{
            .len = result.rows.len,
            .total_row_count = result.total_row_count,
            .truncated = @intFromBool(result.truncated),
            .rows = diagnosticRowsPointer(zdisamar.LineContributionRow, result.rows),
        },
        .instrument_response => output.* = .{
            .len = result.rows.len,
            .rows = diagnosticRowsPointer(zdisamar.InstrumentResponseRow, result.rows),
        },
        .cia_diagnostics => output.* = .{
            .len = result.rows.len,
            .rows = diagnosticRowsPointer(zdisamar.CiaRow, result.rows),
        },
    }
}

fn diagnosticRowsPointer(comptime Row: type, rows: []const Row) ?[*]const Row {
    // diagnosticRowsPointer --------------------------------------------------------------------------------- |
    // Convert an owned native row slice to the nullable borrowed pointer used by the C ABI structs.           |
    // --------------------------------------------------------------------------------------------------------|
    if (rows.len == 0) return null;
    return rows.ptr;
}

fn runSpectrum(
    ctx: ?*Context,
    out: ?*ZdsSpectrum,
    wants_jacobian: bool,
) c_int {
    // runSpectrum --------------------------------------------------------------------------------------------|
    // Execute one forward spectrum and return a C view backed by a Context-owned result handle.               |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);

    const output = out orelse {
        resolved.setError("null spectrum output");
        return @intFromEnum(ZdsStatus.failure);
    };

    const prepared = &(resolved.prepared orelse {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    });

    var solve_config = zdisamar.solveConfig(prepared.scene);
    solve_config.derivative_mode = if (wants_jacobian) .semi_analytical else .none;
    solve_config.wants_jacobian = wants_jacobian;

    const result = allocator.create(CResult) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    result.* = .{};
    errdefer allocator.destroy(result);
    result.native = zdisamar.runForwardWithSessionMemory(
        allocator,
        &resolved.session,
        prepared,
        solve_config,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer result.native.deinit(allocator);

    if (wants_jacobian) {
        result.compact_jacobian = radianceJacobianRows(
            result.native.spectrum,
            solarMu0(prepared.scene),
        ) catch |err| {
            resolved.setError(@errorName(err));
            return @intFromEnum(ZdsStatus.failure);
        };
        result.state_count = zdisamar.jacobian_state_count;
    }
    errdefer allocator.free(result.compact_jacobian);

    resolved.results.append(allocator, result) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    output.* = .{
        .len = result.native.spectrum.sampleCount(),
        .wavelength_nm = result.native.spectrum.wavelength_nm.ptr,
        .radiance = result.native.spectrum.radiance.ptr,
        .irradiance = result.native.spectrum.irradiance.ptr,
        .reflectance = result.native.spectrum.reflectance.ptr,
        .jacobian = if (result.compact_jacobian.len == 0) null else result.compact_jacobian.ptr,
        .jacobian_state_count = result.state_count,
        .result_handle = @ptrCast(result),
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

fn radianceJacobianRows(
    spectrum: zdisamar.Spectrum,
    solar_mu0: f64,
) ![]f64 {
    // radianceJacobianRows -----------------------------------------------------------------------------------|
    // Convert native reflectance Jacobian rows into Python's fixed two-column radiance-Jacobian ABI table.    |
    //                                                                                                         |
    // boundary                                                                                                |
    //   Python `Spectrum.reflectance_jacobian()` treats the C `jacobian` pointer as dL/dx and divides by      |
    //   mu0 * irradiance / pi. Internal root output already stores dR/dx after reflectance assembly, so the   |
    //   C boundary inverts that scale exactly once before exposing the fixed ABI buffer.                      |
    // --------------------------------------------------------------------------------------------------------|
    const state_count = zdisamar.jacobian_state_count;
    if (spectrum.jacobian.len != spectrum.irradiance.len) return error.ShapeMismatch;

    const compact = try allocator.alloc(f64, spectrum.jacobian.len * state_count);
    for (spectrum.jacobian, spectrum.irradiance, 0..) |row, irradiance, sample_index| {
        const reflectance_to_radiance_scale = solar_mu0 * irradiance / std.math.pi;
        for (0..state_count) |state_index| {
            compact[sample_index * state_count + state_index] =
                row[state_index] * reflectance_to_radiance_scale;
        }
    }
    return compact;
}

fn solarMu0(scene: zdisamar.Scene) f64 {
    // solarMu0 -----------------------------------------------------------------------------------------------|
    // Return the transport solar direction cosine for Python radiance-Jacobian ABI conversion.                |
    // --------------------------------------------------------------------------------------------------------|
    return solarMu0FromZenithDegrees(scene.geometry.solar_zenith_deg);
}

pub fn solarMu0FromZenithDegrees(solar_zenith_deg: f64) f64 {
    // solarMu0FromZenithDegrees ------------------------------------------------------------------------------|
    // Match root transport's grazing-angle floor before converting reflectance Jacobians back to radiance.    |
    // --------------------------------------------------------------------------------------------------------|
    const solar_sin = @sin(std.math.degreesToRadians(solar_zenith_deg));
    return @max(
        @sqrt(@max(1.0 - solar_sin * solar_sin, 0.0)),
        zdisamar.geometry_direction_cosine_floor,
    );
}

fn spectrumReport(spectrum: zdisamar.Spectrum) ZdsDiagnosticReport {
    // spectrumReport -----------------------------------------------------------------------------------------|
    // Reduce copied spectrum arrays into the scalar report expected by the Python output object.              |
    // --------------------------------------------------------------------------------------------------------|
    var report = ZdsDiagnosticReport{ .sample_count = @intCast(spectrum.sampleCount()) };
    if (spectrum.sampleCount() == 0) return report;

    report.wavelength_start_nm = spectrum.wavelength_nm[0];
    report.wavelength_end_nm = spectrum.wavelength_nm[spectrum.wavelength_nm.len - 1];
    for (spectrum.radiance, spectrum.irradiance, spectrum.reflectance) |radiance, irradiance, reflectance| {
        report.mean_radiance += radiance;
        report.mean_irradiance += irradiance;
        report.mean_reflectance += reflectance;
    }
    const sample_count: f64 = @floatFromInt(spectrum.sampleCount());
    report.mean_radiance /= sample_count;
    report.mean_irradiance /= sample_count;
    report.mean_reflectance /= sample_count;
    return report;
}

fn optimalEstimationResultView(native: *zdisamar.RetrievalResult) ZdsOptimalEstimationResult {
    // optimalEstimationResultView ----------------------------------------------------------------------------|
    // Borrow one native single-run retrieval result through the stable C output row.                          |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .state_count = @intCast(native.state_count),
        .iteration_count = @intCast(native.iteration_count),
        .converged = @intFromBool(native.converged),
        .state_ids = @ptrCast(native.state_ids.ptr),
        .state = native.state.ptr,
        .initial_state = native.initial_state.ptr,
        .posterior_covariance = native.posterior_covariance.ptr,
        .averaging_kernel = native.averaging_kernel.ptr,
        .history_state = native.history_state.ptr,
        .history_chi2 = native.history_chi2.ptr,
        .history_chi2_reflectance = native.history_chi2_reflectance.ptr,
        .history_chi2_state_vector = native.history_chi2_state_vector.ptr,
        .history_state_vector_convergence = native.history_state_vector_convergence.ptr,
        .history_snr_normal = native.history_snr_normal.ptr,
        .result_handle = @ptrCast(native),
    };
}

fn optimalEstimationBatchResultView(native: *zdisamar.RetrievalBatchResult) ZdsOptimalEstimationBatchResult {
    // optimalEstimationBatchResultView -----------------------------------------------------------------------|
    // Borrow one native full-physics batch result through the stable C output row.                            |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .run_count = native.run_count,
        .state_count = native.state_count,
        .history_capacity = native.history_capacity,
        .iteration_count = native.iteration_count.ptr,
        .converged = native.converged.ptr,
        .status = native.status.ptr,
        .state = native.state.ptr,
        .history_state = native.history_state.ptr,
        .result_handle = @ptrCast(native),
    };
}

fn optimalEstimationFastmodeBatchResultView(
    native: *zdisamar.RetrievalFastmodeBatchResult,
) ZdsOptimalEstimationFastmodeBatchResult {
    // optimalEstimationFastmodeBatchResultView ---------------------------------------------------------------|
    // Borrow one native fastmode batch result through the stable C output row.                                |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .run_count = native.run_count,
        .state_count = native.state_count,
        .history_capacity = native.history_capacity,
        .iteration_count = native.iteration_count.ptr,
        .converged = native.converged.ptr,
        .status = native.status.ptr,
        .state = native.state.ptr,
        .history_state = native.history_state.ptr,
        .fast_stage_iteration_count = native.fast_stage_iteration_count.ptr,
        .fast_stage_converged = native.fast_stage_converged.ptr,
        .full_correction_iteration_count = native.full_correction_iteration_count.ptr,
        .full_correction_converged = native.full_correction_converged.ptr,
        .result_handle = @ptrCast(native),
    };
}

fn destroyResult(ctx: *Context, result: *CResult) void {
    // destroyResult ------------------------------------------------------------------------------------------|
    // Remove and free one retained result handle if it belongs to this context.                               |
    // --------------------------------------------------------------------------------------------------------|
    for (ctx.results.items, 0..) |stored, index| {
        if (stored == result) {
            _ = ctx.results.swapRemove(index);
            result.deinit();
            allocator.destroy(result);
            return;
        }
    }
}

fn unsupported(ctx: ?*Context, message: []const u8) c_int {
    // unsupported --------------------------------------------------------------------------------------------|
    // Return a typed API-boundary failure for routes that are not enabled in this API surface.                |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    resolved.setError(message);
    return @intFromEnum(ZdsStatus.failure);
}

fn rejectMultiLayerAerosolProfileRetrieval(ctx: ?*Context) ?c_int {
    // rejectMultiLayerAerosolProfileRetrieval --------------------------------------------------------------- |
    // Preserve the public Python contract that multi-layer aerosol profiles are forward-simulation only.      |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const prepared = &(resolved.prepared orelse return null);
    if (prepared.scene.aerosol.profile.len <= 1) return null;

    resolved.setError("multi-layer aerosol profiles are forward-simulation only");
    return @intFromEnum(ZdsStatus.failure);
}

comptime {
    std.debug.assert(@sizeOf(ZdsSpectrum) == 64);
    std.debug.assert(@sizeOf(ZdsDiagnosticReport) == 48);
    std.debug.assert(@sizeOf(ZdsAtmosphericBudget) == 16);
    std.debug.assert(@sizeOf(ZdsO2LineContributions) == 32);
    std.debug.assert(@sizeOf(ZdsInstrumentResponse) == 16);
    std.debug.assert(@sizeOf(ZdsO2O2CIADiagnostics) == 16);
    std.debug.assert(@sizeOf(CResult) == 176);
}
