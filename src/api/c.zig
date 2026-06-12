const std = @import("std");
const zdisamar = @import("zdisamar");

const allocator = std.heap.smp_allocator;

// c.zig ------------------------------------------------------------------------------------------------------|
// C ABI boundary for Python bindings and external callers.                                                    |
//                                                                                                             |
// called from                                                                                                 |
//   build.zig builds this file as the `zdisamar_c` dynamic-library root.                                      |
//   python/zdisamar/bindings/signatures.py binds the exported `zds_*` symbols with ctypes.                    |
//                                                                                                             |
// boundary                                                                                                    |
//   Context owns prepared setup tables, reusable O2 session memory, returned spectrum handles, and error      |
//   text. Compute receives only the public root inputs: PreparedO2A, O2SessionMemory, and SolveConfig.        |
//   JSON parsing, diagnostic tables, retrieval, and fastmode return typed failures until their WP4/WP5        |
//   ports land; no parsed control is silently ignored.                                                        |
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
// [24..31] rows           : ?[*]const O2LineContributionRow                                                   |
pub const ZdsO2LineContributions = extern struct {
    len: usize = 0,
    total_row_count: usize = 0,
    truncated: u8 = 0,
    rows: ?[*]const zdisamar.O2LineContributionRow = null,
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
// [8..15] rows: ?[*]const O2O2CIARow                                                                          |
pub const ZdsO2O2CIADiagnostics = extern struct {
    len: usize = 0,
    rows: ?[*]const zdisamar.O2O2CIARow = null,
};
// ------------------------------------------------------------------------------------------------------------|

// CResult ----------------------------------------------------------------------------------------------------|
// Context-owned native spectrum plus optional compact C-facing Jacobian rows.                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 184 B (0.180 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..159] native          : O2SpectrumRunResult                                                            |
// [160..175] compact_jacobian: []f64                                                                          |
// [176..183] state_count     : usize                                                                          |
const CResult = struct {
    native: zdisamar.O2SpectrumRunResult = .{},
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
// size: 7952 B (7.766 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..1655] parsed    : ?ParsedO2CaseJson                                                                  |
// [1656..4191] prepared  : ?PreparedO2A                                                                       |
// [4192..7663] session   : O2SessionMemory                                                                    |
// [7664..7687] results   : ArrayList(*CResult)                                                                |
// [7688..7943] last_error: [256:0]u8                                                                          |
// [7944..7951] trailing padding: 8 B                                                                          |
//                                                                                                             |
// referenced storage                                                                                          |
//   parsed owns JSON arena storage borrowed by prepared.case for zds_prepare_o2a_json.                        |
const Context = struct {
    parsed: ?zdisamar.ParsedO2CaseJson = null,
    prepared: ?zdisamar.PreparedO2A = null,
    session: zdisamar.O2SessionMemory,
    results: std.ArrayList(*CResult) = .empty,
    last_error: [256:0]u8 = [_:0]u8{0} ** 256,

    fn init() Context {
        // Context.init ---------------------------------------------------------------------------------------|
        // Create an empty API context with initialized session memory.                                        |
        // ----------------------------------------------------------------------------------------------------|
        return .{ .session = zdisamar.initO2SessionMemory(allocator) };
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

export fn zds_context_create() ?*Context {
    // zds_context_create -------------------------------------------------------------------------------------|
    // Allocate one opaque C context for Python or external callers.                                           |
    // --------------------------------------------------------------------------------------------------------|
    const ctx = allocator.create(Context) catch return null;
    ctx.* = Context.init();
    return ctx;
}

export fn zds_context_destroy(ctx: ?*Context) void {
    // zds_context_destroy ------------------------------------------------------------------------------------|
    // Release a context and every result handle still retained by it.                                         |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return;
    resolved.deinit();
    allocator.destroy(resolved);
}

export fn zds_prepare_default_o2a(ctx: ?*Context) c_int {
    // zds_prepare_default_o2a --------------------------------------------------------------------------------|
    // Prepare the built-in default O2 A product case.                                                         |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);

    resolved.clearPrepared();

    resolved.prepared = zdisamar.prepareO2A(allocator, zdisamar.defaultO2Case()) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_prepare_o2a_json(ctx: ?*Context, json_ptr: ?[*]const u8, json_len: usize) c_int {
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
    var parsed = zdisamar.parseO2CaseJson(allocator, payload) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer parsed.deinit();

    var prepared = zdisamar.prepareO2A(allocator, parsed.case) catch |err| {
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
    // Build retained session rows for the prepared default O2 A case.                                         |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);

    const prepared = &(resolved.prepared orelse {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    });

    zdisamar.warmO2ASessionMemory(
        allocator,
        &resolved.session,
        prepared,
        zdisamar.o2aSolveConfig(prepared.case),
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_warm_o2a_optimal_estimation(ctx: ?*Context, _: ?[*]const u8, _: usize) c_int {
    // zds_warm_o2a_optimal_estimation ------------------------------------------------------------------------|
    // Return a typed failure until retrieval/OE cache warming is ported.                                      |
    // --------------------------------------------------------------------------------------------------------|
    return unsupported(ctx, "UnsupportedOptimalEstimation");
}

export fn zds_default_o2a_input_json(ctx: ?*Context, out: ?[*]u8, buffer_len: usize, out_len: ?*usize) c_int {
    // zds_default_o2a_input_json -----------------------------------------------------------------------------|
    // Render the built-in O2 A case as Python-native JSON, using the two-call ctypes buffer pattern.          |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const slot = out_len orelse {
        resolved.setError("null output length");
        return @intFromEnum(ZdsStatus.failure);
    };

    const rendered = zdisamar.renderDefaultO2CaseJson(allocator) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    defer allocator.free(rendered);

    slot.* = rendered.len;
    const buffer = out orelse {
        resolved.setError("");
        return @intFromEnum(ZdsStatus.ok);
    };

    if (buffer_len <= rendered.len) {
        resolved.setError("output buffer too small");
        return @intFromEnum(ZdsStatus.failure);
    }

    @memcpy(buffer[0..rendered.len], rendered);
    buffer[rendered.len] = 0;
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_run_spectrum(ctx: ?*Context, out: ?*ZdsSpectrum) c_int {
    // zds_run_spectrum ---------------------------------------------------------------------------------------|
    // Run the prepared case without returning Jacobian columns.                                               |
    // --------------------------------------------------------------------------------------------------------|
    return runSpectrum(ctx, out, null, 0, false);
}

export fn zds_run_spectrum_jacobian(ctx: ?*Context, out: ?*ZdsSpectrum) c_int {
    // zds_run_spectrum_jacobian ------------------------------------------------------------------------------|
    // Run the prepared case with all fixed Jacobian columns in public order.                                  |
    // --------------------------------------------------------------------------------------------------------|
    return runSpectrum(ctx, out, null, 0, true);
}

export fn zds_run_spectrum_jacobian_for_states(
    ctx: ?*Context,
    out: ?*ZdsSpectrum,
    state_ids: ?[*]const u8,
    state_count: usize,
) c_int {
    // zds_run_spectrum_jacobian_for_states -------------------------------------------------------------------|
    // Run the prepared case with a caller-selected compact Jacobian column order.                             |
    // --------------------------------------------------------------------------------------------------------|
    return runSpectrum(ctx, out, state_ids, state_count, true);
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

    const output = out orelse {
        resolved.setError("null atmospheric budget output");
        return @intFromEnum(ZdsStatus.failure);
    };
    output.* = .{};

    var budget = zdisamar.buildAtmosphericBudget(
        allocator,
        prepared,
        wavelengths_ptr[0..wavelength_count],
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer budget.deinit(allocator);

    output.* = .{
        .len = budget.rows.len,
        .rows = if (budget.rows.len == 0) null else budget.rows.ptr,
    };
    budget.rows = &.{};
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
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
    if (max_rows == 0) {
        resolved.setError("invalid O2 line contribution row limit");
        return @intFromEnum(ZdsStatus.failure);
    }

    const output = out orelse {
        resolved.setError("null O2 line contribution output");
        return @intFromEnum(ZdsStatus.failure);
    };
    output.* = .{};

    var contributions = zdisamar.buildO2LineContributions(
        allocator,
        prepared,
        wavelengths_ptr[0..wavelength_count],
        max_rows,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer contributions.deinit(allocator);

    output.* = .{
        .len = contributions.rows.len,
        .total_row_count = contributions.total_row_count,
        .truncated = @intFromBool(contributions.truncated),
        .rows = if (contributions.rows.len == 0) null else contributions.rows.ptr,
    };
    contributions.rows = &.{};
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
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

    const output = out orelse {
        resolved.setError("null instrument response output");
        return @intFromEnum(ZdsStatus.failure);
    };
    output.* = .{};

    var response = zdisamar.buildInstrumentResponse(
        allocator,
        prepared,
        wavelengths_ptr[0..wavelength_count],
        channel_mask,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer response.deinit(allocator);

    output.* = .{
        .len = response.rows.len,
        .rows = if (response.rows.len == 0) null else response.rows.ptr,
    };
    response.rows = &.{};
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
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

    const output = out orelse {
        resolved.setError("null O2-O2 CIA output");
        return @intFromEnum(ZdsStatus.failure);
    };
    output.* = .{};

    var diagnostics = zdisamar.buildO2O2CIADiagnostics(
        allocator,
        prepared,
        wavelengths_ptr[0..wavelength_count],
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer diagnostics.deinit(allocator);

    output.* = .{
        .len = diagnostics.rows.len,
        .rows = if (diagnostics.rows.len == 0) null else diagnostics.rows.ptr,
    };
    diagnostics.rows = &.{};
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_run_o2a_optimal_estimation(ctx: ?*Context, _: ?*const anyopaque, _: ?*anyopaque) c_int {
    // zds_run_o2a_optimal_estimation -------------------------------------------------------------------------|
    // Return a typed failure until package 5 ports optimal estimation.                                        |
    // --------------------------------------------------------------------------------------------------------|
    return unsupported(ctx, "UnsupportedOptimalEstimation");
}

export fn zds_run_o2a_optimal_estimation_correction(ctx: ?*Context, _: ?*const anyopaque, _: ?*anyopaque) c_int {
    // zds_run_o2a_optimal_estimation_correction --------------------------------------------------------------|
    // Return a typed failure until package 5 ports correction runs.                                           |
    // --------------------------------------------------------------------------------------------------------|
    return unsupported(ctx, "UnsupportedOptimalEstimationCorrection");
}

export fn zds_run_o2a_optimal_estimation_batch(ctx: ?*Context, _: ?*const anyopaque, _: ?*anyopaque) c_int {
    // zds_run_o2a_optimal_estimation_batch -------------------------------------------------------------------|
    // Return a typed failure until package 5 ports batch retrieval.                                           |
    // --------------------------------------------------------------------------------------------------------|
    return unsupported(ctx, "UnsupportedOptimalEstimationBatch");
}

export fn zds_run_o2a_fastmode_optimal_estimation_batch(
    ctx: ?*Context,
    _: ?*anyopaque,
    _: ?*const anyopaque,
    _: ?*const anyopaque,
    _: ?*anyopaque,
) c_int {
    // zds_run_o2a_fastmode_optimal_estimation_batch ----------------------------------------------------------|
    // Return a typed failure until package 5 ports fastmode batch retrieval.                                  |
    // --------------------------------------------------------------------------------------------------------|
    return unsupported(ctx, "UnsupportedFastmodeOptimalEstimationBatch");
}

export fn zds_spectrum_free(ctx: ?*Context, out: ?*ZdsSpectrum) void {
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

export fn zds_optimal_estimation_result_free(_: ?*Context, _: ?*anyopaque) void {
    // zds_optimal_estimation_result_free ---------------------------------------------------------------------|
    // Placeholder free hook for the unimplemented optimal-estimation result route.                            |
    // --------------------------------------------------------------------------------------------------------|
}

export fn zds_optimal_estimation_batch_result_free(_: ?*Context, _: ?*anyopaque) void {
    // zds_optimal_estimation_batch_result_free ---------------------------------------------------------------|
    // Placeholder free hook for the unimplemented batch optimal-estimation result route.                      |
    // --------------------------------------------------------------------------------------------------------|
}

export fn zds_optimal_estimation_fastmode_batch_result_free(_: ?*Context, _: ?*anyopaque) void {
    // zds_optimal_estimation_fastmode_batch_result_free ------------------------------------------------------|
    // Placeholder free hook for the unimplemented fastmode batch result route.                                |
    // --------------------------------------------------------------------------------------------------------|
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

export fn zds_last_error(ctx: ?*Context) [*:0]const u8 {
    // zds_last_error -----------------------------------------------------------------------------------------|
    // Return the context's last bounded nul-terminated error string.                                          |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return "null context";
    return @ptrCast(&resolved.last_error);
}

fn runSpectrum(
    ctx: ?*Context,
    out: ?*ZdsSpectrum,
    state_ids: ?[*]const u8,
    requested_state_count: usize,
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

    const selection = jacobianSelection(state_ids, requested_state_count, wants_jacobian) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    var solve_config = zdisamar.o2aSolveConfig(prepared.case);
    solve_config.derivative_state_mask = selection.mask;
    solve_config.derivative_mode = if (wants_jacobian) .semi_analytical else .none;

    const result = allocator.create(CResult) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    result.* = .{};
    errdefer allocator.destroy(result);
    result.native = zdisamar.runO2AWithSessionMemory(allocator, &resolved.session, prepared, solve_config) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer result.native.deinit(allocator);

    if (selection.state_count != 0) {
        const selected_ids = selection.ids[0..selection.state_count];
        result.compact_jacobian = compactJacobian(result.native.spectrum.jacobian, selected_ids) catch |err| {
            resolved.setError(@errorName(err));
            return @intFromEnum(ZdsStatus.failure);
        };
        result.state_count = selection.state_count;
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

const JacobianSelection = struct {
    ids: [zdisamar.jacobian_state_count]u8 = .{0} ** zdisamar.jacobian_state_count,
    state_count: usize = 0,
    mask: u8 = 0,
};

fn jacobianSelection(
    state_ids: ?[*]const u8,
    requested_state_count: usize,
    wants_jacobian: bool,
) !JacobianSelection {
    // jacobianSelection --------------------------------------------------------------------------------------|
    // Validate Python state ids and build the fixed root SolveConfig mask plus compact output order.          |
    // --------------------------------------------------------------------------------------------------------|
    if (!wants_jacobian) return .{};
    if (requested_state_count > zdisamar.jacobian_state_count) return error.UnsupportedJacobianState;

    var selection = JacobianSelection{};
    if (requested_state_count == 0) {
        for (0..zdisamar.jacobian_state_count) |index| {
            selection.ids[index] = @intCast(index);
            selection.mask |= @as(u8, 1) << @intCast(index);
        }
        selection.state_count = zdisamar.jacobian_state_count;
        return selection;
    }

    const ids = state_ids orelse return error.UnsupportedJacobianState;

    for (ids[0..requested_state_count]) |id| {
        if (id >= zdisamar.jacobian_state_count) return error.UnsupportedJacobianState;

        const bit = @as(u8, 1) << @intCast(id);
        if ((selection.mask & bit) != 0) return error.UnsupportedJacobianState;

        selection.ids[selection.state_count] = id;
        selection.state_count += 1;
        selection.mask |= bit;
    }

    return selection;
}

fn compactJacobian(jacobian: []const zdisamar.JacobianVector, state_ids: []const u8) ![]f64 {
    // compactJacobian ----------------------------------------------------------------------------------------|
    // Copy fixed native Jacobian vectors into Python's compact row-major active-state table.                  |
    // --------------------------------------------------------------------------------------------------------|
    const state_count = state_ids.len;
    const compact = try allocator.alloc(f64, jacobian.len * state_count);
    for (jacobian, 0..) |row, sample_index| {
        for (state_ids, 0..) |state_id, compact_index| {
            compact[sample_index * state_count + compact_index] = row[state_id];
        }
    }
    return compact;
}

fn spectrumReport(spectrum: zdisamar.O2Spectrum) ZdsDiagnosticReport {
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
    // Return a typed API-boundary failure for routes that are not ported in this package slice.               |
    // --------------------------------------------------------------------------------------------------------|
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    resolved.setError(message);
    return @intFromEnum(ZdsStatus.failure);
}

comptime {
    std.debug.assert(@sizeOf(ZdsSpectrum) == 64);
    std.debug.assert(@sizeOf(ZdsDiagnosticReport) == 48);
    std.debug.assert(@sizeOf(ZdsAtmosphericBudget) == 16);
    std.debug.assert(@sizeOf(ZdsO2LineContributions) == 32);
    std.debug.assert(@sizeOf(ZdsInstrumentResponse) == 16);
    std.debug.assert(@sizeOf(ZdsO2O2CIADiagnostics) == 16);
    std.debug.assert(@sizeOf(CResult) == 184);
}
