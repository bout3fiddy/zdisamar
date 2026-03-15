const std = @import("std");
const zdisamar = @import("zdisamar");

test "perf smoke executes repeated prepared plans without failure" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{ .max_prepared_plans = 512 });
    defer engine.deinit();

    try engine.bootstrapBuiltinCatalog();
    var workspace = engine.createWorkspace("perf-suite");

    var checksum: u64 = 0;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        if (i != 0) {
            workspace.reset();
        }

        var plan = try engine.preparePlan(.{});
        defer plan.deinit();
        const request = zdisamar.Request.init(.{
            .id = "scene-perf",
            .spectral_grid = .{ .sample_count = 16 },
        });
        var result = try engine.execute(&plan, &workspace, request);
        defer result.deinit(std.testing.allocator);

        try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
        checksum +%= result.plan_id;
    }

    try std.testing.expect(checksum > 0);
}
