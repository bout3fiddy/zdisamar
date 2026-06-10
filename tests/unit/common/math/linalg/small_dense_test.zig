const std = @import("std");
const internal = @import("internal");

const small_dense = internal.common.math.linalg.small_dense;
const index = small_dense.index;

test "small dense index maps row-major matrix cells" {
    try std.testing.expectEqual(@as(usize, 0), index(0, 0, 3));
    try std.testing.expectEqual(@as(usize, 1), index(0, 1, 3));
    try std.testing.expectEqual(@as(usize, 3), index(1, 0, 3));
    try std.testing.expectEqual(@as(usize, 8), index(2, 2, 3));
}
