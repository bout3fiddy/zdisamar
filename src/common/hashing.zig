const std = @import("std");

// hashing.zig ------------------------------------------------------------------------------------------------|
// Shared exact-bit hash helpers for cache and plan keys. These helpers only append bytes to a caller-owned    |
// Wyhash; seed choice and domain-specific fields stay local to each key builder.                              |
// ------------------------------------------------------------------------------------------------------------|

pub fn updateOptionalInt(hash: *std.hash.Wyhash, value: anytype) void {
    updateInt(hash, value != null);
    if (value) |resolved| updateInt(hash, resolved);
}

pub fn updateOptionalIntSlice(hash: *std.hash.Wyhash, value: anytype) void {
    updateInt(hash, value != null);
    if (value) |resolved| {
        updateInt(hash, resolved.len);
        for (resolved) |item| updateOptionalInt(hash, item);
    }
}

pub fn updateOptionalFloat(hash: *std.hash.Wyhash, value: ?f64) void {
    updateInt(hash, value != null);
    if (value) |resolved| updateFloat(hash, resolved);
}

pub fn updateFloatSlice(hash: *std.hash.Wyhash, values: []const f64) void {
    updateInt(hash, values.len);
    hash.update(std.mem.sliceAsBytes(values));
}

pub fn updateFloat(hash: *std.hash.Wyhash, value: f64) void {
    var bits = @as(u64, @bitCast(value));
    hash.update(std.mem.asBytes(&bits));
}

pub fn updateInt(hash: *std.hash.Wyhash, value: anytype) void {
    var bits = value;
    hash.update(std.mem.asBytes(&bits));
}
