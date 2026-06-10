const std = @import("std");
const InstrumentGrid = @import("../forward_model/instrument_grid/root.zig");

pub const spectrum_name = "generated_spectrum.csv";

// json.zig ---------------------------------------------------------------------------------------------------|
// File-output helpers for product summaries and generated spectra. This module is an output boundary, so it   |
// owns JSON/CSV formatting that must stay out of RTM and optical-property compute routines.                   |
//                                                                                                             |
// called by                                                                                                   |
//   root.writeReport writes a SummaryReport to a caller-selected path. api/c.zig uses summaryReportFromProduct|
//   to fill ZdsDiagnosticReport without file I/O. validation/o2a_plot_spectrum_cli.zig writes                 |
//   generated_spectrum.csv for local plotting.                                                                |
//                                                                                                             |
// main paths                                                                                                  |
//   summaryReportFromProduct  -> copy scalar InstrumentGridProduct summary fields into SummaryReport          |
//   writeSummaryReport        -> stream indented JSON for one SummaryReport                                   |
//   writeGeneratedSpectrumCsv -> stream wavelength, irradiance, radiance, and reflectance columns             |
//                                                                                                             |
// boundary                                                                                                    |
//   SummaryReport is the small scalar report value shared by file output and the C diagnostic-report API.     |
//   The generated-spectrum CSV is a validation/plotting artifact, not an internal transport format.           |
//                                                                                                             |
// memory                                                                                                      |
//   SummaryReport is a compact value. File writers stream rows directly to std.fs.File writers and do not     |
//   retain additional row buffers.                                                                            |
// ------------------------------------------------------------------------------------------------------------|

// SummaryReport ----------------------------------------------------------------------------------------------|
// Stores the scalar spectrum summary written to JSON.                                                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_start_nm : f64                                                                          |
// [ 8..15] wavelength_end_nm   : f64                                                                          |
// [16..23] mean_radiance       : f64                                                                          |
// [24..31] mean_irradiance     : f64                                                                          |
// [32..39] mean_reflectance    : f64                                                                          |
// [40..43] sample_count        : u32                                                                          |
// [44..47] trailing padding                                                                                   |
//                                                                                                             |
// unused bits: 32 padding + 0 bool-storage slack = 32 bits                                                    |
// footprint: per instance = 48 B (0.047 KiB); total = per instance * live instance count                      |
pub const SummaryReport = struct {
    sample_count: u32,
    wavelength_start_nm: f64,
    wavelength_end_nm: f64,
    mean_radiance: f64,
    mean_irradiance: f64,
    mean_reflectance: f64,
};
// ------------------------------------------------------------------------------------------------------------|

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

pub fn summaryReportFromProduct(product: *const InstrumentGrid.InstrumentGridProduct) SummaryReport {
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
    product: *const InstrumentGrid.InstrumentGridProduct,
) !void {
    var file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer file.close();

    var writer = file.writer(&.{});
    defer writer.interface.flush() catch {};
    try writer.interface.writeAll(
        "wavelength_nm,irradiance,radiance,reflectance\n",
    );

    for (
        product.wavelengths,
        product.irradiance,
        product.radiance,
        product.reflectance,
    ) |wavelength_nm, irradiance, radiance, reflectance| {
        try writer.interface.print(
            "{d:.8},{e:.17},{e:.17},{e:.17}\n",
            .{ wavelength_nm, irradiance, radiance, reflectance },
        );
    }
}
