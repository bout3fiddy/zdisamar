const std = @import("std");

const internal = @import("internal");

const memory = internal.common.memory;

test "ensureSliceCapacity reports reuse or replacement" {
    var values: []f64 = &.{};
    defer std.testing.allocator.free(values);

    try std.testing.expect(try memory.ensureSliceCapacity(f64, std.testing.allocator, &values, 2));
    try std.testing.expectEqual(@as(usize, 2), values.len);

    values[0] = 1.0;
    values[1] = 2.0;
    try std.testing.expect(!try memory.ensureSliceCapacity(f64, std.testing.allocator, &values, 2));
    try std.testing.expectApproxEqAbs(1.0, values[0], 0.0);

    try std.testing.expect(try memory.ensureSliceCapacity(f64, std.testing.allocator, &values, 3));
    try std.testing.expectEqual(@as(usize, 3), values.len);
}
