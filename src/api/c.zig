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
    result_handle: ?*anyopaque = null,
};

const Context = struct {
    prepared: ?zdisamar.Prepared = null,
    results: std.ArrayList(*zdisamar.Result) = .empty,
    last_error: [256:0]u8 = [_:0]u8{0} ** 256,

    fn clearResults(self: *Context) void {
        for (self.results.items) |result| {
            result.deinit(allocator);
            allocator.destroy(result);
        }
        self.results.clearAndFree(allocator);
    }

    fn removeResult(self: *Context, result: *zdisamar.Result) bool {
        for (self.results.items, 0..) |stored, index| {
            if (stored == result) {
                _ = self.results.swapRemove(index);
                return true;
            }
        }
        return false;
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
    resolved.clearResults();
    resolved.clearPrepared();
    allocator.destroy(resolved);
}

export fn zds_prepare_default_o2a(ctx: ?*Context) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
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
    const result = allocator.create(zdisamar.Result) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    result.* = zdisamar.run(
        allocator,
        prepared,
        .exact,
        .{},
    ) catch |err| {
        allocator.destroy(result);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.results.append(allocator, result) catch |err| {
        result.deinit(allocator);
        allocator.destroy(result);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    output.* = .{
        .len = result.wavelengths.len,
        .wavelength_nm = result.wavelengths.ptr,
        .radiance = result.radiance.ptr,
        .irradiance = result.irradiance.ptr,
        .reflectance = result.reflectance.ptr,
        .result_handle = @ptrCast(result),
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_spectrum_free(ctx: ?*Context, out: ?*ZdsSpectrum) void {
    const resolved = ctx orelse return;
    const output = out orelse return;
    if (output.result_handle) |handle| {
        const result: *zdisamar.Result = @ptrCast(@alignCast(handle));
        if (resolved.removeResult(result)) {
            result.deinit(allocator);
            allocator.destroy(result);
        }
    }
    output.* = .{};
}

export fn zds_last_error(ctx: ?*Context) [*:0]const u8 {
    const resolved = ctx orelse return "null context";
    return @ptrCast(&resolved.last_error);
}
