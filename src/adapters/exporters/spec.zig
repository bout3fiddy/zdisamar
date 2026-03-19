const std = @import("std");
const ExportFormat = @import("format.zig").ExportFormat;
const Result = @import("../../core/Result.zig").Result;
const Provenance = @import("../../core/provenance.zig").Provenance;
const Diagnostics = @import("../../core/diagnostics.zig").Diagnostics;
const MeasurementSpaceProduct = @import("../../kernels/transport/measurement_space.zig").MeasurementSpaceProduct;
const RetrievalOutcome = @import("../../retrieval/common/contracts.zig").SolverOutcome;

pub const Compression = struct {
    codec: Codec = .none,
    level: ?u8 = null,

    pub const Codec = enum {
        none,
        zstd,
        gzip,
    };
};

pub const Chunking = struct {
    spectra: u32,
    layers: u32,
};

pub const ExportRequest = struct {
    plugin_id: []const u8,
    format: ExportFormat,
    destination_uri: []const u8,
    dataset_name: []const u8 = "result",
    include_provenance: bool = true,
    compression: Compression = .{},
    chunking: ?Chunking = null,
};

pub const ExportView = struct {
    status: Result.Status,
    plan_id: u64,
    workspace_label: []const u8,
    scene_id: []const u8,
    provenance: Provenance,
    diagnostics: Diagnostics,
    retrieval: ?RetrievalOutcome = null,
    measurement_space_product: ?*const MeasurementSpaceProduct = null,
    retrieval_state_vector: ?*const Result.RetrievalStateVectorProduct = null,
    retrieval_fitted_measurement: ?*const MeasurementSpaceProduct = null,
    retrieval_averaging_kernel: ?*const Result.RetrievalMatrixProduct = null,
    retrieval_jacobian: ?*const Result.RetrievalMatrixProduct = null,
    retrieval_posterior_covariance: ?*const Result.RetrievalMatrixProduct = null,

    pub fn fromResult(result: *const Result) ExportView {
        return .{
            .status = result.status,
            .plan_id = result.plan_id,
            .workspace_label = result.workspace_label,
            .scene_id = result.scene_id,
            .provenance = result.provenance,
            .diagnostics = result.diagnostics,
            .retrieval = result.retrieval,
            .measurement_space_product = if (result.measurement_space_product) |*product| product else null,
            .retrieval_state_vector = if (result.retrieval_products.state_vector) |*product| product else null,
            .retrieval_fitted_measurement = if (result.retrieval_products.fitted_measurement) |*product| product else null,
            .retrieval_averaging_kernel = if (result.retrieval_products.averaging_kernel) |*product| product else null,
            .retrieval_jacobian = if (result.retrieval_products.jacobian) |*product| product else null,
            .retrieval_posterior_covariance = if (result.retrieval_products.posterior_covariance) |*product| product else null,
        };
    }
};

pub const ExportArtifact = struct {
    format: ExportFormat,
    destination_uri: []const u8,
    dataset_name: []const u8,
    plugin_id: []const u8,
    media_type: []const u8,
    extension: []const u8,
    includes_provenance: bool,
};

pub fn buildArtifact(request: ExportRequest) ExportArtifact {
    return .{
        .format = request.format,
        .destination_uri = request.destination_uri,
        .dataset_name = request.dataset_name,
        .plugin_id = request.plugin_id,
        .media_type = request.format.mediaType(),
        .extension = request.format.extension(),
        .includes_provenance = request.include_provenance,
    };
}

test "adapter maps export request to stable artifact metadata" {
    const netcdf = buildArtifact(.{
        .plugin_id = "builtin.netcdf_cf",
        .format = .netcdf_cf,
        .destination_uri = "file://out/scene.nc",
    });
    try std.testing.expectEqualStrings("builtin.netcdf_cf", netcdf.plugin_id);
    try std.testing.expectEqualStrings("application/x-netcdf", netcdf.media_type);
    try std.testing.expectEqualStrings(".nc", netcdf.extension);

    const zarr = buildArtifact(.{
        .plugin_id = "builtin.zarr",
        .format = .zarr,
        .destination_uri = "file://out/scene.zarr",
        .dataset_name = "slant_column",
        .include_provenance = false,
        .compression = .{ .codec = .zstd, .level = 3 },
        .chunking = .{ .spectra = 256, .layers = 64 },
    });
    try std.testing.expectEqualStrings("builtin.zarr", zarr.plugin_id);
    try std.testing.expectEqualStrings("application/vnd+zarr", zarr.media_type);
    try std.testing.expectEqualStrings(".zarr", zarr.extension);
    try std.testing.expectEqual(false, zarr.includes_provenance);
}
