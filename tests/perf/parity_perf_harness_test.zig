const std = @import("std");
const harness = @import("harness.zig");

test "performance harness executes perf matrix scenarios with bounded runtime" {
    const matrix = try harness.loadMatrix(std.testing.allocator, "validation/perf/perf_matrix.json");
    defer matrix.deinit();

    try std.testing.expectEqual(@as(u32, 1), matrix.value.version);
    try std.testing.expect(matrix.value.scenarios.len > 0);

    var report = try harness.measureMatrixWithOptions(std.testing.allocator, matrix.value, .{
        .max_iterations = 64,
    });
    defer report.deinit(std.testing.allocator);

    try harness.assertExecutionSanity(report);
}
