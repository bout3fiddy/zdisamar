const std = @import("std");
const MeasurementSpace = @import("../forward_model/instrument_grid/root.zig");

pub const spectrum_name = "generated_spectrum.csv";

pub const SummaryReport = struct {
    sample_count: u32,
    wavelength_start_nm: f64,
    wavelength_end_nm: f64,
    mean_radiance: f64,
    mean_irradiance: f64,
    mean_reflectance: f64,
};

pub fn writeSummaryReport(
    summary_path: []const u8,
    report: SummaryReport,
) !void {
    var file = try std.fs.cwd().createFile(summary_path, .{ .truncate = true });
    defer file.close();

    var writer = file.writer(&.{});
    try std.json.Stringify.value(report, .{ .whitespace = .indent_2 }, &writer.interface);
    try writer.interface.flush();
}

pub fn summaryReportFromProduct(product: *const MeasurementSpace.MeasurementSpaceProduct) SummaryReport {
    return .{
        .sample_count = product.summary.sample_count,
        .wavelength_start_nm = product.summary.wavelength_start_nm,
        .wavelength_end_nm = product.summary.wavelength_end_nm,
        .mean_radiance = product.summary.mean_radiance,
        .mean_irradiance = product.summary.mean_irradiance,
        .mean_reflectance = product.summary.mean_reflectance,
    };
}

pub fn writeGeneratedSpectrumCsv(
    output_path: []const u8,
    product: *const MeasurementSpace.MeasurementSpaceProduct,
) !void {
    var file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer file.close();

    var writer = file.writer(&.{});
    defer writer.interface.flush() catch {};
    try writer.interface.writeAll(
        "wavelength_nm,irradiance,radiance,reflectance\n",
    );

    for (product.wavelengths, product.irradiance, product.radiance, product.reflectance) |wavelength_nm, irradiance, radiance, reflectance| {
        try writer.interface.print(
            "{d:.8},{e:.17},{e:.17},{e:.17}\n",
            .{ wavelength_nm, irradiance, radiance, reflectance },
        );
    }
}
