const std = @import("std");
const Result = @import("../../core/Result.zig").Result;
const Spec = @import("spec.zig");
const NetcdfCf = @import("netcdf_cf.zig");
const Zarr = @import("zarr.zig");
const Diagnostic = @import("diagnostic.zig");

pub const Error =
    NetcdfCf.Error ||
    Zarr.Error ||
    Diagnostic.Error;

pub const ExportReport = struct {
    artifact: Spec.ExportArtifact,
    files_written: u32,
    bytes_written: usize,
};

pub const DiagnosticReport = Diagnostic.DiagnosticReport;
pub const DiagnosticFormat = Diagnostic.DiagnosticFormat;

pub fn write(
    allocator: std.mem.Allocator,
    request: Spec.ExportRequest,
    result: Result,
) Error!ExportReport {
    return switch (request.format) {
        .netcdf_cf => {
            const report = try NetcdfCf.write(request, result, allocator);
            return .{
                .artifact = report.artifact,
                .files_written = report.files_written,
                .bytes_written = report.bytes_written,
            };
        },
        .zarr => {
            const report = try Zarr.write(request, result, allocator);
            return .{
                .artifact = report.artifact,
                .files_written = report.files_written,
                .bytes_written = report.bytes_written,
            };
        },
    };
}

pub fn exportDiagnostic(
    allocator: std.mem.Allocator,
    destination_uri: []const u8,
    format: DiagnosticFormat,
    result: Result,
) Error!DiagnosticReport {
    return try Diagnostic.write(destination_uri, format, result, allocator);
}

test "writer dispatches based on export format metadata" {
    const request: Spec.ExportRequest = .{
        .format = .netcdf_cf,
        .destination_uri = "file://out/dispatch.nc",
    };
    const artifact = Spec.buildArtifact(request);
    try std.testing.expectEqualStrings("builtin.netcdf_cf", artifact.plugin_id);
}
