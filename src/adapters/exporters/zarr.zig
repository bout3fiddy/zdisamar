const std = @import("std");
const Spec = @import("spec.zig");
const io = @import("io.zig");

pub const Error = error{
    UnsupportedFormat,
    PathTooLong,
    ValueOutOfRange,
} || io.Error || std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.WriteError || std.fs.Dir.MakeError || std.fmt.BufPrintError;

pub const ExportReport = struct {
    artifact: Spec.ExportArtifact,
    files_written: u32,
    bytes_written: usize,
};

pub fn write(request: Spec.ExportRequest, view: Spec.ExportView, allocator: std.mem.Allocator) Error!ExportReport {
    if (request.format != .zarr) return Error.UnsupportedFormat;
    const artifact = Spec.buildArtifact(request);
    const store_path = try io.filePathFromUri(request.destination_uri);

    try std.fs.cwd().makePath(store_path);

    var files_written: u32 = 0;
    var bytes_written: usize = 0;

    const root_group_payload = "{\n  \"zarr_format\": 2\n}\n";
    bytes_written += try writeStoreTextFile(store_path, ".zgroup", root_group_payload, &files_written);

    const root_attrs_payload = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"conventions\": \"CF-1.10\",\n  \"source\": \"zdisamar\",\n  \"dataset_name\": \"{s}\",\n  \"scene_id\": \"{s}\",\n  \"workspace_label\": \"{s}\",\n  \"plan_id\": {d},\n  \"solver_route\": \"{s}\",\n  \"model_family\": \"{s}\",\n  \"transport_family\": \"{s}\",\n  \"derivative_mode\": \"{s}\",\n  \"numerical_mode\": \"{s}\",\n  \"status\": \"{s}\",\n  \"plugin_count\": {d},\n  \"dataset_hash_count\": {d},\n  \"native_capability_count\": {d},\n  \"native_entry_symbol_count\": {d},\n  \"native_library_path_count\": {d}\n}}\n",
        .{
            artifact.dataset_name,
            view.scene_id,
            view.workspace_label,
            view.plan_id,
            view.provenance.solver_route,
            view.provenance.model_family,
            view.provenance.transport_family,
            view.provenance.derivative_mode,
            view.provenance.numerical_mode,
            @tagName(view.status),
            view.provenance.pluginVersionCount(),
            view.provenance.dataset_hashes.len,
            view.provenance.native_capability_slots.len,
            view.provenance.native_entry_symbols.len,
            view.provenance.native_library_paths.len,
        },
    );
    defer allocator.free(root_attrs_payload);
    bytes_written += try writeStoreTextFile(store_path, ".zattrs", root_attrs_payload, &files_written);

    const root_group_names = [_][]const u8{
        "metadata",
        "provenance",
        "diagnostics",
        "measurement_space",
        "retrieval",
    };
    for (root_group_names) |group_name| {
        bytes_written += try writeSubgroup(allocator, store_path, group_name, &files_written);
    }

    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "metadata/dataset_name",
        "metadata",
        &[_][]const u8{artifact.dataset_name},
        &files_written,
    );
    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "metadata/scene_id",
        "metadata",
        &[_][]const u8{view.scene_id},
        &files_written,
    );
    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "metadata/workspace_label",
        "metadata",
        &[_][]const u8{view.workspace_label},
        &files_written,
    );
    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "metadata/status",
        "metadata",
        &[_][]const u8{@tagName(view.status)},
        &files_written,
    );
    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "metadata/engine_version",
        "metadata",
        &[_][]const u8{view.provenance.engine_version},
        &files_written,
    );

    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "provenance/model_family",
        "provenance",
        &[_][]const u8{view.provenance.model_family},
        &files_written,
    );
    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "provenance/solver_route",
        "provenance",
        &[_][]const u8{view.provenance.solver_route},
        &files_written,
    );
    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "provenance/transport_family",
        "provenance",
        &[_][]const u8{view.provenance.transport_family},
        &files_written,
    );
    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "provenance/derivative_mode",
        "provenance",
        &[_][]const u8{view.provenance.derivative_mode},
        &files_written,
    );
    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "provenance/numerical_mode",
        "provenance",
        &[_][]const u8{view.provenance.numerical_mode},
        &files_written,
    );

    const plugin_versions = view.provenance.pluginVersions();
    if (plugin_versions.len > 0) {
        bytes_written += try writeStringArray(
            allocator,
            store_path,
            "provenance/plugin_versions",
            "provenance",
            plugin_versions,
            &files_written,
        );
    }
    if (view.provenance.dataset_hashes.len > 0) {
        bytes_written += try writeStringArray(
            allocator,
            store_path,
            "provenance/dataset_hashes",
            "provenance",
            view.provenance.dataset_hashes,
            &files_written,
        );
    }
    if (view.provenance.native_capability_slots.len > 0) {
        bytes_written += try writeStringArray(
            allocator,
            store_path,
            "provenance/native_capability_slots",
            "provenance",
            view.provenance.native_capability_slots,
            &files_written,
        );
    }
    if (view.provenance.native_entry_symbols.len > 0) {
        bytes_written += try writeStringArray(
            allocator,
            store_path,
            "provenance/native_entry_symbols",
            "provenance",
            view.provenance.native_entry_symbols,
            &files_written,
        );
    }
    if (view.provenance.native_library_paths.len > 0) {
        bytes_written += try writeStringArray(
            allocator,
            store_path,
            "provenance/native_library_paths",
            "provenance",
            view.provenance.native_library_paths,
            &files_written,
        );
    }

    const provenance_counts = [_]i32{
        try toI32(plugin_versions.len),
        try toI32(view.provenance.dataset_hashes.len),
        try toI32(view.provenance.native_capability_slots.len),
        try toI32(view.provenance.native_entry_symbols.len),
        try toI32(view.provenance.native_library_paths.len),
    };
    bytes_written += try writeInt32Array(
        allocator,
        store_path,
        "provenance/counts",
        "provenance",
        &provenance_counts,
        &files_written,
    );

    bytes_written += try writeStringArray(
        allocator,
        store_path,
        "diagnostics/summary",
        "diagnostics",
        &[_][]const u8{view.diagnostics.summary},
        &files_written,
    );
    const diagnostic_flags = [_]i32{
        @intFromBool(view.diagnostics.emitted_provenance),
        @intFromBool(view.diagnostics.emitted_jacobians),
    };
    bytes_written += try writeInt32Array(
        allocator,
        store_path,
        "diagnostics/flags",
        "diagnostics",
        &diagnostic_flags,
        &files_written,
    );

    if (view.measurement_space_product) |product| {
        bytes_written += try writeFloat64Array(allocator, store_path, "measurement_space/wavelength_nm", "measurement_space", product.wavelengths, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "measurement_space/toa_radiance", "measurement_space", product.radiance, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "measurement_space/solar_irradiance", "measurement_space", product.irradiance, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "measurement_space/reflectance", "measurement_space", product.reflectance, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "measurement_space/noise_sigma", "measurement_space", product.noise_sigma, &files_written);
        if (product.jacobian) |jacobian| {
            bytes_written += try writeFloat64Array(allocator, store_path, "measurement_space/jacobian", "measurement_space", jacobian, &files_written);
        }

        const effective_air_mass_factor = [_]f64{product.effective_air_mass_factor};
        const effective_single_scatter_albedo = [_]f64{product.effective_single_scatter_albedo};
        const effective_temperature_k = [_]f64{product.effective_temperature_k};
        const effective_pressure_hpa = [_]f64{product.effective_pressure_hpa};
        const gas_optical_depth = [_]f64{product.gas_optical_depth};
        const cia_optical_depth = [_]f64{product.cia_optical_depth};
        const aerosol_optical_depth = [_]f64{product.aerosol_optical_depth};
        const cloud_optical_depth = [_]f64{product.cloud_optical_depth};
        const total_optical_depth = [_]f64{product.total_optical_depth};
        const depolarization_factor = [_]f64{product.depolarization_factor};
        const d_optical_depth_d_temperature = [_]f64{product.d_optical_depth_d_temperature};

        bytes_written += try writeFloat64Array(allocator, store_path, "measurement_space/effective_air_mass_factor", "measurement_space", &effective_air_mass_factor, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "measurement_space/effective_single_scatter_albedo", "measurement_space", &effective_single_scatter_albedo, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "measurement_space/effective_temperature_k", "measurement_space", &effective_temperature_k, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "measurement_space/effective_pressure_hpa", "measurement_space", &effective_pressure_hpa, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "measurement_space/gas_optical_depth", "measurement_space", &gas_optical_depth, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "measurement_space/cia_optical_depth", "measurement_space", &cia_optical_depth, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "measurement_space/aerosol_optical_depth", "measurement_space", &aerosol_optical_depth, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "measurement_space/cloud_optical_depth", "measurement_space", &cloud_optical_depth, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "measurement_space/total_optical_depth", "measurement_space", &total_optical_depth, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "measurement_space/depolarization_factor", "measurement_space", &depolarization_factor, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "measurement_space/d_optical_depth_d_temperature", "measurement_space", &d_optical_depth_d_temperature, &files_written);
    }

    if (view.retrieval) |retrieval| {
        bytes_written += try writeStringArray(
            allocator,
            store_path,
            "retrieval/method",
            "retrieval",
            &[_][]const u8{@tagName(retrieval.method)},
            &files_written,
        );
        bytes_written += try writeStringArray(
            allocator,
            store_path,
            "retrieval/inverse_problem_id",
            "retrieval",
            &[_][]const u8{retrieval.inverse_problem_id},
            &files_written,
        );
        bytes_written += try writeFloat64Array(
            allocator,
            store_path,
            "retrieval/metrics",
            "retrieval",
            &[_]f64{
                @as(f64, @floatFromInt(retrieval.iterations)),
                retrieval.cost,
                retrieval.dfs,
                retrieval.residual_norm,
                retrieval.step_norm,
            },
            &files_written,
        );
    }

    if (view.retrieval_state_vector) |product| {
        bytes_written += try writeStringArray(
            allocator,
            store_path,
            "retrieval/state_vector/parameter_names",
            "retrieval/state_vector",
            product.parameter_names,
            &files_written,
        );
        bytes_written += try writeFloat64Array(
            allocator,
            store_path,
            "retrieval/state_vector/values",
            "retrieval/state_vector",
            product.values,
            &files_written,
        );
    }

    if (view.retrieval_fitted_measurement) |product| {
        bytes_written += try writeFloat64Array(allocator, store_path, "retrieval/fitted_measurement/wavelength_nm", "retrieval/fitted_measurement", product.wavelengths, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "retrieval/fitted_measurement/toa_radiance", "retrieval/fitted_measurement", product.radiance, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "retrieval/fitted_measurement/solar_irradiance", "retrieval/fitted_measurement", product.irradiance, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "retrieval/fitted_measurement/reflectance", "retrieval/fitted_measurement", product.reflectance, &files_written);
        bytes_written += try writeFloat64Array(allocator, store_path, "retrieval/fitted_measurement/noise_sigma", "retrieval/fitted_measurement", product.noise_sigma, &files_written);
    }

    if (view.retrieval_averaging_kernel) |product| {
        bytes_written += try writeStringArray(
            allocator,
            store_path,
            "retrieval/averaging_kernel/parameter_names",
            "retrieval/averaging_kernel",
            product.parameter_names,
            &files_written,
        );
        bytes_written += try writeFloat64Matrix(
            allocator,
            store_path,
            "retrieval/averaging_kernel/values",
            "retrieval/averaging_kernel",
            product.row_count,
            product.column_count,
            product.values,
            &files_written,
        );
    }

    if (view.retrieval_jacobian) |product| {
        bytes_written += try writeStringArray(
            allocator,
            store_path,
            "retrieval/jacobian/parameter_names",
            "retrieval/jacobian",
            product.parameter_names,
            &files_written,
        );
        bytes_written += try writeFloat64Matrix(
            allocator,
            store_path,
            "retrieval/jacobian/values",
            "retrieval/jacobian",
            product.row_count,
            product.column_count,
            product.values,
            &files_written,
        );
    }

    return .{
        .artifact = artifact,
        .files_written = files_written,
        .bytes_written = bytes_written,
    };
}

fn writeSubgroup(
    allocator: std.mem.Allocator,
    store_path: []const u8,
    relative_group_path: []const u8,
    files_written: *u32,
) !usize {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const group_path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ store_path, relative_group_path });
    try std.fs.cwd().makePath(group_path);

    var bytes_written: usize = 0;
    bytes_written += try writeStoreTextFile(group_path, ".zgroup", "{\n  \"zarr_format\": 2\n}\n", files_written);

    const attrs_payload = try std.fmt.allocPrint(allocator, "{{\n  \"group_role\": \"{s}\"\n}}\n", .{relative_group_path});
    defer allocator.free(attrs_payload);
    bytes_written += try writeStoreTextFile(group_path, ".zattrs", attrs_payload, files_written);
    return bytes_written;
}

fn writeStringArray(
    allocator: std.mem.Allocator,
    store_path: []const u8,
    relative_array_path: []const u8,
    group_role: []const u8,
    values: []const []const u8,
    files_written: *u32,
) !usize {
    const width = maxStringLen(values);
    const chunk_payload = try encodeStringChunk(allocator, values, width);
    defer allocator.free(chunk_payload);

    const zarray_payload = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"chunks\": [{d}],\n  \"compressor\": null,\n  \"dtype\": \"|S{d}\",\n  \"fill_value\": null,\n  \"filters\": null,\n  \"order\": \"C\",\n  \"shape\": [{d}],\n  \"zarr_format\": 2\n}}\n",
        .{ values.len, width, values.len },
    );
    defer allocator.free(zarray_payload);

    const zattrs_payload = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"_ARRAY_DIMENSIONS\": [\"item\"],\n  \"content_type\": \"fixed_ascii_string\",\n  \"group_role\": \"{s}\"\n}}\n",
        .{group_role},
    );
    defer allocator.free(zattrs_payload);

    var bytes_written: usize = 0;
    bytes_written += try writeArrayDirectory(store_path, relative_array_path);

    var zarray_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const zarray_relative = try std.fmt.bufPrint(&zarray_rel_path, "{s}/.zarray", .{relative_array_path});
    bytes_written += try writeStoreTextFile(store_path, zarray_relative, zarray_payload, files_written);

    var zattrs_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const zattrs_relative = try std.fmt.bufPrint(&zattrs_rel_path, "{s}/.zattrs", .{relative_array_path});
    bytes_written += try writeStoreTextFile(store_path, zattrs_relative, zattrs_payload, files_written);

    var chunk_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const chunk_relative = try std.fmt.bufPrint(&chunk_rel_path, "{s}/0", .{relative_array_path});
    bytes_written += try writeStoreBinaryFile(store_path, chunk_relative, chunk_payload, files_written);
    return bytes_written;
}

fn writeInt32Array(
    allocator: std.mem.Allocator,
    store_path: []const u8,
    relative_array_path: []const u8,
    group_role: []const u8,
    values: []const i32,
    files_written: *u32,
) !usize {
    const chunk_payload = try encodeInt32Chunk(allocator, values);
    defer allocator.free(chunk_payload);

    const zarray_payload = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"chunks\": [{d}],\n  \"compressor\": null,\n  \"dtype\": \"<i4\",\n  \"fill_value\": 0,\n  \"filters\": null,\n  \"order\": \"C\",\n  \"shape\": [{d}],\n  \"zarr_format\": 2\n}}\n",
        .{ values.len, values.len },
    );
    defer allocator.free(zarray_payload);

    const zattrs_payload = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"_ARRAY_DIMENSIONS\": [\"item\"],\n  \"content_type\": \"int32\",\n  \"group_role\": \"{s}\"\n}}\n",
        .{group_role},
    );
    defer allocator.free(zattrs_payload);

    var bytes_written: usize = 0;
    bytes_written += try writeArrayDirectory(store_path, relative_array_path);

    var zarray_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const zarray_relative = try std.fmt.bufPrint(&zarray_rel_path, "{s}/.zarray", .{relative_array_path});
    bytes_written += try writeStoreTextFile(store_path, zarray_relative, zarray_payload, files_written);

    var zattrs_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const zattrs_relative = try std.fmt.bufPrint(&zattrs_rel_path, "{s}/.zattrs", .{relative_array_path});
    bytes_written += try writeStoreTextFile(store_path, zattrs_relative, zattrs_payload, files_written);

    var chunk_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const chunk_relative = try std.fmt.bufPrint(&chunk_rel_path, "{s}/0", .{relative_array_path});
    bytes_written += try writeStoreBinaryFile(store_path, chunk_relative, chunk_payload, files_written);
    return bytes_written;
}

fn writeFloat64Array(
    allocator: std.mem.Allocator,
    store_path: []const u8,
    relative_array_path: []const u8,
    group_role: []const u8,
    values: []const f64,
    files_written: *u32,
) !usize {
    const chunk_payload = try encodeFloat64Chunk(allocator, values);
    defer allocator.free(chunk_payload);

    const zarray_payload = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"chunks\": [{d}],\n  \"compressor\": null,\n  \"dtype\": \"<f8\",\n  \"fill_value\": 0.0,\n  \"filters\": null,\n  \"order\": \"C\",\n  \"shape\": [{d}],\n  \"zarr_format\": 2\n}}\n",
        .{ values.len, values.len },
    );
    defer allocator.free(zarray_payload);

    const zattrs_payload = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"_ARRAY_DIMENSIONS\": [\"item\"],\n  \"content_type\": \"float64\",\n  \"group_role\": \"{s}\"\n}}\n",
        .{group_role},
    );
    defer allocator.free(zattrs_payload);

    var bytes_written: usize = 0;
    bytes_written += try writeArrayDirectory(store_path, relative_array_path);

    var zarray_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const zarray_relative = try std.fmt.bufPrint(&zarray_rel_path, "{s}/.zarray", .{relative_array_path});
    bytes_written += try writeStoreTextFile(store_path, zarray_relative, zarray_payload, files_written);

    var zattrs_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const zattrs_relative = try std.fmt.bufPrint(&zattrs_rel_path, "{s}/.zattrs", .{relative_array_path});
    bytes_written += try writeStoreTextFile(store_path, zattrs_relative, zattrs_payload, files_written);

    var chunk_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const chunk_relative = try std.fmt.bufPrint(&chunk_rel_path, "{s}/0", .{relative_array_path});
    bytes_written += try writeStoreBinaryFile(store_path, chunk_relative, chunk_payload, files_written);
    return bytes_written;
}

fn writeFloat64Matrix(
    allocator: std.mem.Allocator,
    store_path: []const u8,
    relative_array_path: []const u8,
    group_role: []const u8,
    row_count: u32,
    column_count: u32,
    values: []const f64,
    files_written: *u32,
) !usize {
    if (values.len != @as(usize, row_count) * @as(usize, column_count)) return Error.ValueOutOfRange;

    const chunk_payload = try encodeFloat64Chunk(allocator, values);
    defer allocator.free(chunk_payload);

    const zarray_payload = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"chunks\": [{d}, {d}],\n  \"compressor\": null,\n  \"dtype\": \"<f8\",\n  \"fill_value\": 0.0,\n  \"filters\": null,\n  \"order\": \"C\",\n  \"shape\": [{d}, {d}],\n  \"zarr_format\": 2\n}}\n",
        .{ row_count, column_count, row_count, column_count },
    );
    defer allocator.free(zarray_payload);

    const zattrs_payload = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"_ARRAY_DIMENSIONS\": [\"row\", \"column\"],\n  \"content_type\": \"float64\",\n  \"group_role\": \"{s}\"\n}}\n",
        .{group_role},
    );
    defer allocator.free(zattrs_payload);

    var bytes_written: usize = 0;
    bytes_written += try writeArrayDirectory(store_path, relative_array_path);

    var zarray_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const zarray_relative = try std.fmt.bufPrint(&zarray_rel_path, "{s}/.zarray", .{relative_array_path});
    bytes_written += try writeStoreTextFile(store_path, zarray_relative, zarray_payload, files_written);

    var zattrs_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const zattrs_relative = try std.fmt.bufPrint(&zattrs_rel_path, "{s}/.zattrs", .{relative_array_path});
    bytes_written += try writeStoreTextFile(store_path, zattrs_relative, zattrs_payload, files_written);

    var chunk_rel_path: [std.fs.max_path_bytes]u8 = undefined;
    const chunk_relative = try std.fmt.bufPrint(&chunk_rel_path, "{s}/0.0", .{relative_array_path});
    bytes_written += try writeStoreBinaryFile(store_path, chunk_relative, chunk_payload, files_written);
    return bytes_written;
}

fn writeArrayDirectory(store_path: []const u8, relative_array_path: []const u8) !usize {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const array_path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ store_path, relative_array_path });
    try std.fs.cwd().makePath(array_path);
    return 0;
}

fn writeStoreTextFile(store_path: []const u8, relative_path: []const u8, payload: []const u8, files_written: *u32) !usize {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ store_path, relative_path });
    files_written.* += 1;
    return io.writeTextFile(full_path, payload);
}

fn writeStoreBinaryFile(store_path: []const u8, relative_path: []const u8, payload: []const u8, files_written: *u32) !usize {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ store_path, relative_path });
    files_written.* += 1;
    return io.writeBinaryFile(full_path, payload);
}

fn encodeStringChunk(allocator: std.mem.Allocator, values: []const []const u8, width: usize) ![]u8 {
    const payload = try allocator.alloc(u8, values.len * width);
    @memset(payload, 0);
    for (values, 0..) |value, index| {
        const row = payload[index * width ..][0..width];
        std.mem.copyForwards(u8, row[0..value.len], value);
    }
    return payload;
}

fn encodeInt32Chunk(allocator: std.mem.Allocator, values: []const i32) ![]u8 {
    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);
    for (values) |value| try writer.writeInt(i32, value, .little);
    return buffer.toOwnedSlice(allocator);
}

fn encodeFloat64Chunk(allocator: std.mem.Allocator, values: []const f64) ![]u8 {
    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);
    for (values) |value| try writer.writeInt(u64, @as(u64, @bitCast(value)), .little);
    return buffer.toOwnedSlice(allocator);
}

fn maxStringLen(values: []const []const u8) usize {
    var max_len: usize = 1;
    for (values) |value| max_len = @max(max_len, value.len);
    return max_len;
}

fn toI32(value: usize) Error!i32 {
    return std.math.cast(i32, value) orelse Error.ValueOutOfRange;
}

test "zarr exporter emits group metadata and array stores" {
    const dataset_hashes = [_][]const u8{"sha256:test-zarr"};
    var provenance: @import("../../core/provenance.zig").Provenance = .{
        .plan_id = 9,
        .workspace_label = "ws-zarr",
        .scene_id = "scene-zarr",
        .dataset_hashes = &dataset_hashes,
    };
    provenance.setPluginVersions(&[_][]const u8{"builtin.zarr@0.1.0"});
    var result = @import("../../core/Result.zig").Result.init(9, "ws-zarr", "scene-zarr", provenance);
    defer result.deinit(std.testing.allocator);

    const jacobian = try std.testing.allocator.dupe(f64, &.{ 0.21, 0.18, 0.16 });
    errdefer std.testing.allocator.free(jacobian);
    result.attachMeasurementSpaceProduct(.{
        .summary = .{
            .sample_count = 3,
            .wavelength_start_nm = 405.0,
            .wavelength_end_nm = 465.0,
            .mean_radiance = 0.42,
            .mean_irradiance = 1.17,
            .mean_reflectance = 0.36,
            .mean_noise_sigma = 0.01,
            .mean_jacobian = 0.18333333333333335,
        },
        .wavelengths = try std.testing.allocator.dupe(f64, &.{ 405.0, 435.0, 465.0 }),
        .radiance = try std.testing.allocator.dupe(f64, &.{ 0.35, 0.42, 0.49 }),
        .irradiance = try std.testing.allocator.dupe(f64, &.{ 1.12, 1.17, 1.22 }),
        .reflectance = try std.testing.allocator.dupe(f64, &.{ 0.3125, 0.3589743589, 0.4016393443 }),
        .noise_sigma = try std.testing.allocator.dupe(f64, &.{ 0.01, 0.011, 0.012 }),
        .jacobian = jacobian,
        .effective_air_mass_factor = 1.25,
        .effective_single_scatter_albedo = 0.92,
        .effective_temperature_k = 266.0,
        .effective_pressure_hpa = 550.0,
        .gas_optical_depth = 0.19,
        .cia_optical_depth = 0.03,
        .aerosol_optical_depth = 0.07,
        .cloud_optical_depth = 0.04,
        .total_optical_depth = 0.30,
        .depolarization_factor = 0.025,
        .d_optical_depth_d_temperature = -1.5e-4,
    });

    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = try std.fmt.bufPrint(&root_buffer, "zig-cache/zarr-backend-test-{d}", .{@as(u64, @intCast(@abs(std.time.nanoTimestamp())))});
    defer std.fs.cwd().deleteTree(root) catch {};

    const destination_uri = try std.fmt.allocPrint(std.testing.allocator, "file://{s}/scene.zarr", .{root});
    defer std.testing.allocator.free(destination_uri);

    const report = try write(.{
        .plugin_id = "builtin.zarr",
        .format = .zarr,
        .destination_uri = destination_uri,
        .dataset_name = "scene-zarr",
    }, Spec.ExportView.fromResult(&result), std.testing.allocator);

    try std.testing.expect(report.files_written >= 40);

    const zgroup_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/scene.zarr/.zgroup", .{root});
    defer std.testing.allocator.free(zgroup_path);
    const plugin_array_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/scene.zarr/provenance/plugin_versions/.zarray", .{root});
    defer std.testing.allocator.free(plugin_array_path);
    const plugin_chunk_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/scene.zarr/provenance/plugin_versions/0", .{root});
    defer std.testing.allocator.free(plugin_chunk_path);
    const wavelength_array_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/scene.zarr/measurement_space/wavelength_nm/.zarray", .{root});
    defer std.testing.allocator.free(wavelength_array_path);
    const wavelength_chunk_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/scene.zarr/measurement_space/wavelength_nm/0", .{root});
    defer std.testing.allocator.free(wavelength_chunk_path);

    const zgroup_payload = try std.fs.cwd().readFileAlloc(std.testing.allocator, zgroup_path, 8 * 1024);
    defer std.testing.allocator.free(zgroup_payload);
    const zarray_payload = try std.fs.cwd().readFileAlloc(std.testing.allocator, plugin_array_path, 8 * 1024);
    defer std.testing.allocator.free(zarray_payload);
    const chunk_payload = try std.fs.cwd().readFileAlloc(std.testing.allocator, plugin_chunk_path, 8 * 1024);
    defer std.testing.allocator.free(chunk_payload);
    const wavelength_zarray = try std.fs.cwd().readFileAlloc(std.testing.allocator, wavelength_array_path, 8 * 1024);
    defer std.testing.allocator.free(wavelength_zarray);
    const wavelength_chunk = try std.fs.cwd().readFileAlloc(std.testing.allocator, wavelength_chunk_path, 8 * 1024);
    defer std.testing.allocator.free(wavelength_chunk);

    try std.testing.expect(std.mem.containsAtLeast(u8, zgroup_payload, 1, "\"zarr_format\": 2"));
    try std.testing.expect(std.mem.containsAtLeast(u8, zarray_payload, 1, "\"dtype\": \"|S"));
    try std.testing.expect(std.mem.containsAtLeast(u8, chunk_payload, 1, "builtin.zarr@0.1.0"));
    try std.testing.expect(std.mem.containsAtLeast(u8, wavelength_zarray, 1, "\"dtype\": \"<f8\""));
    try std.testing.expectEqual(@as(usize, 24), wavelength_chunk.len);
}
