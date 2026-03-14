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

        const plan = try engine.preparePlan(.{});
        const request = zdisamar.Request.init(.{
            .id = "scene-perf",
            .spectral_grid = .{ .sample_count = 16 },
        });
        const result = try engine.execute(&plan, &workspace, request);

        try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
        checksum +%= result.plan_id;
    }

    try std.testing.expect(checksum > 0);
}
