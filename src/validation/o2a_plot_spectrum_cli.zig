const std = @import("std");
const zdisamar = @import("zdisamar");

const report = zdisamar.report;

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: output_dir=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: output_dir carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total also includes referenced storage above
const Config = struct {
    output_dir: []const u8 = "out/analysis/o2a/plot_bundle_tmp",
};

pub fn main(init: std.process.Init) !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const config = try parseArgs(args);
    try std.Io.Dir.cwd().createDirPath(init.io, config.output_dir);

    const input = zdisamar.defaultO2AInput();
    var reflectance_case = try zdisamar.o2a.runResolvedVendorO2AReflectanceCase(allocator, &input);
    defer reflectance_case.deinit(allocator);

    const spectrum_path = try std.fs.path.join(allocator, &.{ config.output_dir, report.spectrum_name });
    defer allocator.free(spectrum_path);
    try report.writeGeneratedSpectrumCsv(spectrum_path, &reflectance_case.product);
    std.debug.print("wrote {s}\n", .{spectrum_path});
}

fn parseArgs(args: []const [:0]const u8) !Config {
    var config: Config = .{};
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--output-dir")) {
            index += 1;
            if (index >= args.len) return error.MissingOutputDir;
            config.output_dir = args[index];
        } else {
            return error.UnsupportedArgument;
        }
    }
    return config;
}
