//! Purpose:
//!   Emit a fresh full-band O2A comparison CSV for the current worktree
//!   against the stored DISAMAR vendor reference.

const std = @import("std");
const internal = @import("zdisamar_internal");
const support = @import("o2a_vendor_support");

const output_dir_default = "out/analysis/o2a/fresh_vendor_plot";
const reference_csv_path = "validation/reference/o2a_with_cia_disamar_reference.csv";
const output_csv_name = "vendor_o2a_comparison.csv";
const summary_name = "summary.txt";

const FullReferenceSample = struct {
    wavelength_nm: f64,
    irradiance: f64,
    radiance: f64,
    reflectance: f64,
};

const CliConfig = struct {
    output_dir: []u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const config = try parseArgs(allocator, args);
    defer allocator.free(config.output_dir);

    var vendor_case = try support.runVendorO2AReflectanceCase(allocator);
    defer vendor_case.deinit(allocator);

    const reference = try loadFullReferenceSamples(allocator, reference_csv_path);
    defer allocator.free(reference);

    try std.fs.cwd().makePath(config.output_dir);

    const output_csv_path = try std.fs.path.join(allocator, &.{ config.output_dir, output_csv_name });
    defer allocator.free(output_csv_path);
    try writeComparisonCsv(output_csv_path, reference, &vendor_case.product);

    const summary_path = try std.fs.path.join(allocator, &.{ config.output_dir, summary_name });
    defer allocator.free(summary_path);
    const metrics = support.computeComparisonMetrics(&vendor_case.product, vendor_case.reference, 1.0e-12);
    try writeSummary(summary_path, output_csv_path, metrics);

    std.debug.print("wrote {s}\n", .{output_csv_path});
    std.debug.print("wrote {s}\n", .{summary_path});
}

fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !CliConfig {
    var output_dir = try allocator.dupe(u8, output_dir_default);
    errdefer allocator.free(output_dir);

    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--output-dir")) {
            index += 1;
            if (index >= args.len) return error.MissingOutputDir;
            allocator.free(output_dir);
            output_dir = try allocator.dupe(u8, args[index]);
            continue;
        }
        return error.InvalidArguments;
    }

    return .{
        .output_dir = output_dir,
    };
}

fn loadFullReferenceSamples(
    allocator: std.mem.Allocator,
    path: []const u8,
) ![]FullReferenceSample {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(bytes);

    var samples = std.ArrayList(FullReferenceSample).empty;
    defer samples.deinit(allocator);

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    _ = lines.next();
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, "\r \t");
        if (trimmed.len == 0) continue;

        var columns = std.mem.splitScalar(u8, trimmed, ',');
        const wavelength_text = columns.next() orelse return error.InvalidData;
        const irradiance_text = columns.next() orelse return error.InvalidData;
        const radiance_text = columns.next() orelse return error.InvalidData;
        const reflectance_text = columns.next() orelse return error.InvalidData;

        try samples.append(allocator, .{
            .wavelength_nm = try std.fmt.parseFloat(f64, std.mem.trim(u8, wavelength_text, " \t")),
            .irradiance = try std.fmt.parseFloat(f64, std.mem.trim(u8, irradiance_text, " \t")),
            .radiance = try std.fmt.parseFloat(f64, std.mem.trim(u8, radiance_text, " \t")),
            .reflectance = try std.fmt.parseFloat(f64, std.mem.trim(u8, reflectance_text, " \t")),
        });
    }

    return try samples.toOwnedSlice(allocator);
}

fn writeComparisonCsv(
    output_csv_path: []const u8,
    reference: []const FullReferenceSample,
    product: *const internal.kernels.transport.measurement.MeasurementSpaceProduct,
) !void {
    var file = try std.fs.cwd().createFile(output_csv_path, .{ .truncate = true });
    defer file.close();

    var writer = file.writer(&.{});
    defer writer.interface.flush() catch {};

    try writer.interface.writeAll(
        "wavelength_nm,fortran_irradiance,fortran_radiance,fortran_reflectance,zdisamar_irradiance,zdisamar_radiance,zdisamar_reflectance,irradiance_residual,radiance_residual,reflectance_residual,reflectance_ratio\n",
    );

    for (reference) |sample| {
        const z_irradiance = support.interpolateVector(
            product.wavelengths,
            product.irradiance,
            sample.wavelength_nm,
        );
        const z_radiance = support.interpolateVector(
            product.wavelengths,
            product.radiance,
            sample.wavelength_nm,
        );
        const z_reflectance = support.interpolateVector(
            product.wavelengths,
            product.reflectance,
            sample.wavelength_nm,
        );
        const reflectance_ratio = if (@abs(sample.reflectance) > 1.0e-30)
            z_reflectance / sample.reflectance
        else
            0.0;

        try writer.interface.print(
            "{d:.8},{e:.12},{e:.12},{e:.12},{e:.12},{e:.12},{e:.12},{e:.12},{e:.12},{e:.12},{d:.12}\n",
            .{
                sample.wavelength_nm,
                sample.irradiance,
                sample.radiance,
                sample.reflectance,
                z_irradiance,
                z_radiance,
                z_reflectance,
                z_irradiance - sample.irradiance,
                z_radiance - sample.radiance,
                z_reflectance - sample.reflectance,
                reflectance_ratio,
            },
        );
    }
}

fn writeSummary(
    summary_path: []const u8,
    output_csv_path: []const u8,
    metrics: support.ComparisonMetrics,
) !void {
    var file = try std.fs.cwd().createFile(summary_path, .{ .truncate = true });
    defer file.close();

    var writer = file.writer(&.{});
    defer writer.interface.flush() catch {};

    try writer.interface.print(
        \\csv: {s}
        \\sample_count: {d}
        \\mean_abs_difference: {d:.12}
        \\root_mean_square_difference: {d:.12}
        \\max_abs_difference: {d:.12}
        \\max_abs_difference_wavelength_nm: {d:.8}
        \\correlation: {d:.12}
        \\blue_wing_mean_difference: {d:.12}
        \\trough_wavelength_difference_nm: {d:.12}
        \\trough_value_difference: {d:.12}
        \\rebound_peak_difference: {d:.12}
        \\mid_band_mean_difference: {d:.12}
        \\red_wing_mean_difference: {d:.12}
        \\
    ,
        .{
            output_csv_path,
            metrics.sample_count,
            metrics.mean_abs_difference,
            metrics.root_mean_square_difference,
            metrics.max_abs_difference,
            metrics.max_abs_difference_wavelength_nm,
            metrics.correlation,
            metrics.blue_wing_mean_difference,
            metrics.trough_wavelength_difference_nm,
            metrics.trough_value_difference,
            metrics.rebound_peak_difference,
            metrics.mid_band_mean_difference,
            metrics.red_wing_mean_difference,
        },
    );
}
