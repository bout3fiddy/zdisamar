const std = @import("std");

// hashing.zig ------------------------------------------------------------------------------------------------|
// Reuse stamps for setup/cache owners.                                                                        |
// ------------------------------------------------------------------------------------------------------------|

// ReuseStamp -------------------------------------------------------------------------------------------------|
// Compact identity stamp for retained setup/cache rows.                                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 8 B (0.008 KiB), align: 8 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
// [0..7] value : u64                                                                                          |
pub const ReuseStamp = struct {
    value: u64 = 0,

    pub fn eql(self: ReuseStamp, other: ReuseStamp) bool {
        // ReuseStamp.eql -------------------------------------------------------------------------------------|
        // Compare two retained setup/cache stamps.                                                            |
        // ----------------------------------------------------------------------------------------------------|
        return self.value == other.value;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn updateValue(hasher: *std.hash.Wyhash, value: anytype) void {
    // updateValue ------------------------------------------------------------------------------------------- |
    // Hash one scalar value after the caller has reduced enums/options to padding-free storage.               |
    // --------------------------------------------------------------------------------------------------------|
    const stored = value;
    hasher.update(std.mem.asBytes(&stored));
}

pub fn updateBool(hasher: *std.hash.Wyhash, value: bool) void {
    // updateBool -------------------------------------------------------------------------------------------- |
    // Hash one bool as a stable byte instead of compiler-specific bool storage.                               |
    // --------------------------------------------------------------------------------------------------------|
    const byte = [_]u8{if (value) 1 else 0};
    hasher.update(&byte);
}

pub fn updateOptionalU16(hasher: *std.hash.Wyhash, value: ?u16) void {
    // updateOptionalU16 ------------------------------------------------------------------------------------- |
    // Hash optional u16 caps with an explicit presence byte.                                                  |
    // --------------------------------------------------------------------------------------------------------|
    updateBool(hasher, value != null);
    if (value) |resolved| updateValue(hasher, resolved);
}
// ------------------------------------------------------------------------------------------------------------|
