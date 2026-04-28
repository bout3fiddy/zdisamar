const std = @import("std");
const zdisamar = @import("zdisamar");

const report = zdisamar.report;

const Config = struct {
    output_dir: []const u8 = "out/analysis/o2a/plot_bundle_tmp",
    case_yaml_path: []const u8 = zdisamar.disamar_reference.default_yaml_path,
};

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const config = try parseArgs(args);
    try std.fs.cwd().makePath(config.output_dir);

    var disamar_case = try zdisamar.disamar_reference.runReflectanceCaseFromFile(
        allocator,
        config.case_yaml_path,
        .{
            .spectral_grid = .{
                .start_nm = 755.0,
                .end_nm = 776.0,
                .sample_count = 701,
            },
            .adaptive_points_per_fwhm = 20,
            .adaptive_strong_line_min_divisions = 8,
            .adaptive_strong_line_max_divisions = 40,
            .line_mixing_factor = 1.0,
            .isotopes_sim = &.{ 1, 2, 3 },
            .threshold_line_sim = 3.0e-5,
            .cutoff_sim_cm1 = 200.0,
        },
    );
    defer disamar_case.deinit(allocator);

    const spectrum_path = try std.fs.path.join(allocator, &.{ config.output_dir, report.spectrum_name });
    defer allocator.free(spectrum_path);
    try report.writeGeneratedSpectrumCsv(spectrum_path, &disamar_case.product);
    std.debug.print("wrote {s}\n", .{spectrum_path});
}

fn parseArgs(args: []const []const u8) !Config {
    var config: Config = .{};
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--output-dir")) {
            index += 1;
            if (index >= args.len) return error.MissingOutputDir;
            config.output_dir = args[index];
        } else if (std.mem.eql(u8, arg, "--case")) {
            index += 1;
            if (index >= args.len) return error.MissingCasePath;
            config.case_yaml_path = args[index];
        } else {
            return error.UnsupportedArgument;
        }
    }
    return config;
}
