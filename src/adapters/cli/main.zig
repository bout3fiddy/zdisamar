const std = @import("std");
const zdisamar = @import("zdisamar");

pub fn main() !void {
    var engine = zdisamar.Engine.init(std.heap.page_allocator, .{});
    defer engine.deinit();

    try engine.bootstrapBuiltinCatalog();

    const plan = try engine.preparePlan(.{});
    var workspace = engine.createWorkspace("cli");
    const request = zdisamar.Request.init(.{ .id = "demo-scene" });
    const result = try engine.execute(&plan, &workspace, request);

    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        "zdisamar scaffold: model={s} plan_id={d} status={s}\n",
        .{ plan.template.model_family, result.plan_id, @tagName(result.status) },
    );
}
