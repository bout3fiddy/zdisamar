const std = @import("std");
const internal = @import("internal");
const o2a_scene = @import("o2a_scene");
const zdisamar = internal.public;

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    var scene = o2a_scene.reference();
    scene.spectral_grid = .{
        .start_nm = 758.0,
        .end_nm = 759.0,
        .sample_count = 2,
    };

    var prepared = try zdisamar.prepare(allocator, scene);
    defer prepared.deinit(allocator);

    const solve_config = zdisamar.solveConfig(scene);

    var result = try zdisamar.runForward(allocator, &prepared, solve_config);
    defer result.deinit(allocator);

    std.debug.print("cost_timing_forward_analysis samples={}\n", .{result.spectrum.sampleCount()});
}
