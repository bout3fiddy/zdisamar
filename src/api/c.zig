//! Purpose:
//!   Expose a minimal C ABI around the retained O2A forward workflow.
//!
//! Physics:
//!   Runs complete prepared O2A spectra through the native Zig engine; callers
//!   receive bulk arrays rather than scalar per-wavelength entrypoints.
//!
//! Design:
//!   The ABI is handle-based. Zig owns contexts and result arrays until the
//!   matching destroy/free call is made.

const std = @import("std");
const zdisamar = @import("zdisamar");

const allocator = std.heap.page_allocator;

pub const ZdsStatus = enum(c_int) {
    ok = 0,
    failure = 1,
};

pub const ZdsSpectrum = extern struct {
    len: usize = 0,
    wavelength_nm: [*]const f64 = undefined,
    radiance: [*]const f64 = undefined,
    irradiance: [*]const f64 = undefined,
    reflectance: [*]const f64 = undefined,
};

const Context = struct {
    prepared: ?zdisamar.Prepared = null,
    result: ?zdisamar.Result = null,
    last_error: [256:0]u8 = [_:0]u8{0} ** 256,

    fn clearResult(self: *Context) void {
        if (self.result) |*result| result.deinit(allocator);
        self.result = null;
    }

    fn clearPrepared(self: *Context) void {
        if (self.prepared) |*prepared| prepared.deinit(allocator);
        self.prepared = null;
    }

    fn setError(self: *Context, message: []const u8) void {
        @memset(self.last_error[0..], 0);
        const n = @min(message.len, self.last_error.len - 1);
        @memcpy(self.last_error[0..n], message[0..n]);
    }
};

fn defaultO2ACase() zdisamar.Case {
    return .{
        .id = "c-api-default-o2a",
        .spectral_grid = .{
            .start_nm = 758.0,
            .end_nm = 771.0,
            .sample_count = 121,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .instrument_line_fwhm_nm = 0.38,
        },
        .surface = .{
            .albedo = 0.05,
        },
    };
}

export fn zds_context_create() ?*Context {
    const ctx = allocator.create(Context) catch return null;
    ctx.* = .{};
    return ctx;
}

export fn zds_context_destroy(ctx: ?*Context) void {
    const resolved = ctx orelse return;
    resolved.clearResult();
    resolved.clearPrepared();
    allocator.destroy(resolved);
}

export fn zds_prepare_default_o2a(ctx: ?*Context) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    resolved.clearResult();
    resolved.clearPrepared();
    var case = defaultO2ACase();
    resolved.prepared = zdisamar.prepare(allocator, &case) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_run_spectrum(ctx: ?*Context, out: ?*ZdsSpectrum) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const output = out orelse return @intFromEnum(ZdsStatus.failure);
    if (resolved.prepared == null) {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    }
    const prepared = &resolved.prepared.?;
    resolved.clearResult();
    resolved.result = zdisamar.run(
        allocator,
        prepared,
        .exact,
        .{},
        null,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    const result = &(resolved.result.?);
    output.* = .{
        .len = result.wavelengths.len,
        .wavelength_nm = result.wavelengths.ptr,
        .radiance = result.radiance.ptr,
        .irradiance = result.irradiance.ptr,
        .reflectance = result.reflectance.ptr,
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_spectrum_free(ctx: ?*Context, out: ?*ZdsSpectrum) void {
    const resolved = ctx orelse return;
    resolved.clearResult();
    if (out) |output| output.* = .{};
}

export fn zds_last_error(ctx: ?*Context) [*:0]const u8 {
    const resolved = ctx orelse return "null context";
    return @ptrCast(&resolved.last_error);
}
