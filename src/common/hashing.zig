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

    pub fn fromBytes(bytes: []const u8) ReuseStamp {
        // ReuseStamp.fromBytes -------------------------------------------------------------------------------|
        // Hash stable setup identity bytes into the compact reuse stamp.                                      |
        // ----------------------------------------------------------------------------------------------------|
        return .{ .value = std.hash.Wyhash.hash(0, bytes) };
    }

    pub fn eql(self: ReuseStamp, other: ReuseStamp) bool {
        // ReuseStamp.eql -------------------------------------------------------------------------------------|
        // Compare two retained setup/cache stamps.                                                            |
        // ----------------------------------------------------------------------------------------------------|
        return self.value == other.value;
    }
};
// ------------------------------------------------------------------------------------------------------------|
