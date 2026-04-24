//! Purpose:
//!   Run the stock O2A vendor-parity forward case with coarse timing splits
//!   and emit a profiling summary without any comparison metrics or plotting.

const std = @import("std");
const zdisamar = @import("zdisamar");
const profile_support = zdisamar.profile;

pub const output_dir_default = profile_support.output_dir_default;
pub const summary_name = profile_support.summary_name;
pub const spectrum_name = profile_support.spectrum_name;
pub const CliConfig = profile_support.CliConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const config = try parseArgs(allocator, args);
    defer allocator.free(config.output_dir);

    try profile_support.runProfileWorkflow(allocator, config);
    const summary_path = try std.fs.path.join(allocator, &.{ config.output_dir, summary_name });
    defer allocator.free(summary_path);
    std.debug.print("wrote {s}\n", .{summary_path});
    if (config.write_spectrum) {
        const spectrum_path = try std.fs.path.join(allocator, &.{ config.output_dir, spectrum_name });
        defer allocator.free(spectrum_path);
        std.debug.print("wrote {s}\n", .{spectrum_path});
    }
}

fn parseArgs(
    allocator: std.mem.Allocator,
    args: []const []const u8,
) !CliConfig {
    var config: CliConfig = .{
        .output_dir = try allocator.dupe(u8, output_dir_default),
    };
    errdefer allocator.free(config.output_dir);

    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--output-dir")) {
            index += 1;
            if (index >= args.len) return error.MissingOutputDir;
            allocator.free(config.output_dir);
            config.output_dir = try allocator.dupe(u8, args[index]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--case-yaml")) {
            index += 1;
            if (index >= args.len) return error.MissingCaseYaml;
            config.case_yaml_path = args[index];
            continue;
        }
        if (std.mem.eql(u8, arg, "--repeat")) {
            index += 1;
            if (index >= args.len) return error.MissingRepeatCount;
            config.repeat_count = try std.fmt.parseInt(u32, args[index], 10);
            continue;
        }
        if (std.mem.eql(u8, arg, "--write-spectrum")) {
            config.write_spectrum = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--quick")) {
            config.preset = .quick;
            continue;
        }
        if (std.mem.eql(u8, arg, "--plot-bundle-grid")) {
            config.preset = .plot_bundle;
            continue;
        }
        return error.InvalidArguments;
    }

    if (config.repeat_count == 0) return error.InvalidRepeatCount;
    return config;
}
