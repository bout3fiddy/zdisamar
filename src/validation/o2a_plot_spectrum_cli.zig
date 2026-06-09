const std = @import("std");
const zdisamar = @import("zdisamar");

const report = zdisamar.report;

// Config -----------------------------------------------------------------------------------------------------|
// Parsed command-line settings for the local O2 A spectrum-plot helper.                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] output_dir : []const u8                                                                            |
//                                                                                                             |
// referenced storage                                                                                          |
//   output_dir points at either the default string literal or the process-args buffer.                        |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); stack value during argument parsing                             |
const Config = struct {
    output_dir: []const u8 = "out/analysis/o2a/plot_bundle_tmp",
};
// ------------------------------------------------------------------------------------------------------------|

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const config = try parseArgs(args);
    try std.fs.cwd().makePath(config.output_dir);

    const input = zdisamar.defaultO2AInput();
    var reflectance_case = try zdisamar.o2a.runResolvedVendorO2AReflectanceCase(allocator, &input);
    defer reflectance_case.deinit(allocator);

    const spectrum_path = try std.fs.path.join(allocator, &.{ config.output_dir, report.spectrum_name });
    defer allocator.free(spectrum_path);
    try report.writeGeneratedSpectrumCsv(spectrum_path, &reflectance_case.product);
    std.debug.print("wrote {s}\n", .{spectrum_path});
}

fn parseArgs(args: []const []const u8) !Config {
    var config: Config = .{};
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        const is_output_dir = std.mem.eql(u8, arg, "--output-dir");

        if (!is_output_dir) return error.UnsupportedArgument;

        index += 1;
        if (index >= args.len) return error.MissingOutputDir;

        config.output_dir = args[index];
    }

    return config;
}
