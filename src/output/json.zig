const std = @import("std");
const InstrumentGrid = @import("../forward_model/instrument_grid/root.zig");
const runtime_io = @import("../common/runtime_io.zig");

pub const spectrum_name = "generated_spectrum.csv";

// layout(64-bit):
//   size: 48 B, align: 8 B
//   field storage: 44 B across 6 fields; largest fields are the three f64 summary values
//   padding: 4 B (32 bits)
//   unused bits: 32 padding + 0 bool-storage slack = 32 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 48 B (0.047 KiB); total = per instance * live instance count
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
    var runtime = runtime_io.RuntimeIo.init(std.heap.smp_allocator);
    defer runtime.deinit();
    const io = runtime.io();
    var file = try std.Io.Dir.cwd().createFile(io, summary_path, .{ .truncate = true });
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);
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
    var runtime = runtime_io.RuntimeIo.init(std.heap.smp_allocator);
    defer runtime.deinit();
    const io = runtime.io();
    var file = try std.Io.Dir.cwd().createFile(io, output_path, .{ .truncate = true });
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);
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
