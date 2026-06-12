const std = @import("std");

const Allocator = std.mem.Allocator;

// memory.zig -------------------------------------------------------------------------------------------------|
// Shared allocation helpers for retained explicit-dataflow memory owners.                                     |
//                                                                                                             |
// ownership boundary                                                                                          |
//   Helpers in this file resize caller-owned storage only. They do not store allocator state, active counts,  |
//   physics inputs, cache stamps, or validity flags.                                                          |
// ------------------------------------------------------------------------------------------------------------|

pub fn ensureSliceCapacity(
    comptime T: type,
    allocator: Allocator,
    slice: *[]T,
    required_len: usize,
) Allocator.Error!bool {
    // ensureSliceCapacity ----------------------------------------------------------------------------------- |
    // Replace backing storage when the retained slice is too small; old values are intentionally discarded.   |
    //                                                                                                         |
    // result                                                                                                  |
    //   false : existing allocation was large enough                                                          |
    //   true  : backing slice was replaced, so callers must invalidate any parallel validity/cache rows       |
    // --------------------------------------------------------------------------------------------------------|
    if (slice.len >= required_len) return false;

    const new_slice = try allocator.alloc(T, required_len);
    allocator.free(slice.*);
    slice.* = new_slice;
    return true;
}
