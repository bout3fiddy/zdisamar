const std = @import("std");
const harness = @import("harness.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const output_path = if (args.len > 1) args[1] else "out/ci/bench/summary.json";
    const matrix = try harness.loadMatrix(allocator, "validation/perf/perf_matrix.json");
    defer matrix.deinit();

    var report = try harness.measureMatrix(allocator, matrix.value);
    defer report.deinit(allocator);

    try harness.writeReportFile(report, output_path);
    std.debug.print(
        "wrote {d} bench scenarios to {s} ({d} ms total)\n",
        .{ report.scenario_count, output_path, report.total_elapsed_ms },
    );
}
