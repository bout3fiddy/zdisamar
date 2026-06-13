const std = @import("std");
const zdisamar = @import("zdisamar");

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    var case = zdisamar.defaultO2Case();
    case.spectral_grid = .{
        .start_nm = 758.0,
        .end_nm = 759.0,
        .sample_count = 2,
    };

    var prepared = try zdisamar.prepareO2A(allocator, case);
    defer prepared.deinit(allocator);

    const solve_config = zdisamar.SolveConfig{
        .derivative_mode = .none,
        .derivative_state_mask = 0,
        .controls = .{
            .scattering = .multiple,
            .n_streams = @intCast(case.rtm.stream_count),
            .integrate_source_function = false,
        },
    };

    var result = try zdisamar.runO2A(allocator, &prepared, solve_config);
    defer result.deinit(allocator);

    std.debug.print("cost_timing_forward_smoke samples={}\n", .{result.spectrum.sampleCount()});
}
