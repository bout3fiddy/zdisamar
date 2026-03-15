const std = @import("std");
const Result = @import("../../core/Result.zig").Result;
const Spec = @import("spec.zig");
const io = @import("io.zig");

const NC_DIMENSION: u32 = 10;
const NC_VARIABLE: u32 = 11;
const NC_ATTRIBUTE: u32 = 12;

const NcType = enum(u32) {
    byte = 1,
    char = 2,
    short = 3,
    int = 4,
    float = 5,
    double = 6,
};

const zero_char = [_]u8{0};

const Dimension = struct {
    name: []const u8,
    len: u32,
};

const Attribute = struct {
    name: []const u8,
    value: Value,

    const Value = union(enum) {
        char: []const u8,
        int: i32,
        double: f64,
    };
};

const Variable = struct {
    name: []const u8,
    rank: u32 = 0,
    dim_ids: [2]u32 = .{ 0, 0 },
    data: Data,

    const Data = union(enum) {
        char: []const u8,
        double: []const f64,
    };

    fn dataLen(self: Variable) usize {
        return switch (self.data) {
            .char => |bytes| bytes.len,
            .double => |values| values.len * @sizeOf(f64),
        };
    }
};

pub const Error = error{
    UnsupportedFormat,
    FileTooLarge,
    ValueOutOfRange,
} || io.Error || std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.WriteError || std.fs.Dir.MakeError || std.fs.File.StatError;

pub const ExportReport = struct {
    artifact: Spec.ExportArtifact,
    files_written: u32,
    bytes_written: usize,
};

pub fn write(request: Spec.ExportRequest, result: Result, allocator: std.mem.Allocator) Error!ExportReport {
    if (request.format != .netcdf_cf) return Error.UnsupportedFormat;
    const artifact = Spec.buildArtifact(request);
    const file_path = try io.filePathFromUri(request.destination_uri);

    const payload = try renderNetcdfClassicPayload(allocator, artifact, result);
    defer allocator.free(payload);

    const bytes_written = try io.writeBinaryFile(file_path, payload);
    return .{
        .artifact = artifact,
        .files_written = 1,
        .bytes_written = bytes_written,
    };
}

fn renderNetcdfClassicPayload(
    allocator: std.mem.Allocator,
    artifact: Spec.ExportArtifact,
    result: Result,
) ![]u8 {
    var owned_buffers = std.ArrayList([]u8).empty;
    defer {
        for (owned_buffers.items) |buffer| allocator.free(buffer);
        owned_buffers.deinit(allocator);
    }

    const plan_id_text = try allocOwnedPrint(allocator, &owned_buffers, "{d}", .{result.plan_id});
    const generation_text = try allocOwnedPrint(allocator, &owned_buffers, "{d}", .{result.provenance.plugin_inventory_generation});

    var dimensions = std.ArrayList(Dimension).empty;
    defer dimensions.deinit(allocator);

    var global_attributes = std.ArrayList(Attribute).empty;
    defer global_attributes.deinit(allocator);

    var variables = std.ArrayList(Variable).empty;
    defer variables.deinit(allocator);

    try global_attributes.appendSlice(allocator, &.{
        .{ .name = "Conventions", .value = .{ .char = "CF-1.10" } },
        .{ .name = "title", .value = .{ .char = "zdisamar retrieval result" } },
        .{ .name = "source", .value = .{ .char = "zdisamar" } },
        .{ .name = "file_format", .value = .{ .char = "netCDF classic (CDF-1)" } },
        .{ .name = "adapter_format", .value = .{ .char = artifact.format.id() } },
        .{ .name = "plugin_id", .value = .{ .char = artifact.plugin_id } },
        .{ .name = "dataset_name", .value = .{ .char = artifact.dataset_name } },
        .{ .name = "scene_id", .value = .{ .char = result.scene_id } },
        .{ .name = "workspace_label", .value = .{ .char = result.workspace_label } },
        .{ .name = "model_family", .value = .{ .char = result.provenance.model_family } },
        .{ .name = "solver_route", .value = .{ .char = result.provenance.solver_route } },
        .{ .name = "transport_family", .value = .{ .char = result.provenance.transport_family } },
        .{ .name = "derivative_mode", .value = .{ .char = result.provenance.derivative_mode } },
        .{ .name = "numerical_mode", .value = .{ .char = result.provenance.numerical_mode } },
        .{ .name = "engine_version", .value = .{ .char = result.provenance.engine_version } },
        .{ .name = "status", .value = .{ .char = @tagName(result.status) } },
        .{ .name = "plan_id", .value = .{ .char = plan_id_text } },
        .{ .name = "plugin_inventory_generation", .value = .{ .char = generation_text } },
        .{ .name = "plugin_count", .value = .{ .int = try toI32(result.provenance.pluginVersionCount()) } },
        .{ .name = "dataset_hash_count", .value = .{ .int = try toI32(result.provenance.dataset_hashes.len) } },
        .{ .name = "native_capability_count", .value = .{ .int = try toI32(result.provenance.native_capability_slots.len) } },
        .{ .name = "native_entry_symbol_count", .value = .{ .int = try toI32(result.provenance.native_entry_symbols.len) } },
        .{ .name = "native_library_path_count", .value = .{ .int = try toI32(result.provenance.native_library_paths.len) } },
    });

    if (result.measurement_space_product) |product| {
        try global_attributes.appendSlice(allocator, &.{
            .{ .name = "effective_air_mass_factor", .value = .{ .double = product.effective_air_mass_factor } },
            .{ .name = "effective_single_scatter_albedo", .value = .{ .double = product.effective_single_scatter_albedo } },
            .{ .name = "effective_temperature_k", .value = .{ .double = product.effective_temperature_k } },
            .{ .name = "effective_pressure_hpa", .value = .{ .double = product.effective_pressure_hpa } },
            .{ .name = "gas_optical_depth", .value = .{ .double = product.gas_optical_depth } },
            .{ .name = "cia_optical_depth", .value = .{ .double = product.cia_optical_depth } },
            .{ .name = "aerosol_optical_depth", .value = .{ .double = product.aerosol_optical_depth } },
            .{ .name = "cloud_optical_depth", .value = .{ .double = product.cloud_optical_depth } },
            .{ .name = "total_optical_depth", .value = .{ .double = product.total_optical_depth } },
            .{ .name = "depolarization_factor", .value = .{ .double = product.depolarization_factor } },
            .{ .name = "d_optical_depth_d_temperature", .value = .{ .double = product.d_optical_depth_d_temperature } },
        });
    }

    try addStringVariable(allocator, &dimensions, &variables, "dataset_name_strlen", "dataset_name", artifact.dataset_name);
    try addStringVariable(allocator, &dimensions, &variables, "scene_id_strlen", "scene_id", result.scene_id);
    try addStringVariable(allocator, &dimensions, &variables, "workspace_label_strlen", "workspace_label", result.workspace_label);
    try addStringVariable(allocator, &dimensions, &variables, "model_family_strlen", "model_family", result.provenance.model_family);
    try addStringVariable(allocator, &dimensions, &variables, "solver_route_strlen", "solver_route", result.provenance.solver_route);
    try addStringVariable(allocator, &dimensions, &variables, "transport_family_strlen", "transport_family", result.provenance.transport_family);
    try addStringVariable(allocator, &dimensions, &variables, "derivative_mode_strlen", "derivative_mode", result.provenance.derivative_mode);
    try addStringVariable(allocator, &dimensions, &variables, "numerical_mode_strlen", "numerical_mode", result.provenance.numerical_mode);
    try addStringVariable(allocator, &dimensions, &variables, "engine_version_strlen", "engine_version", result.provenance.engine_version);
    try addStringVariable(allocator, &dimensions, &variables, "status_strlen", "status", @tagName(result.status));
    try addStringVariable(allocator, &dimensions, &variables, "diagnostics_summary_strlen", "diagnostics_summary", result.diagnostics.summary);

    try addStringListVariable(
        allocator,
        &owned_buffers,
        &dimensions,
        &variables,
        "plugin_count",
        "plugin_strlen",
        "plugin_versions",
        result.provenance.pluginVersions(),
    );
    try addStringListVariable(
        allocator,
        &owned_buffers,
        &dimensions,
        &variables,
        "dataset_hash_count",
        "dataset_hash_strlen",
        "dataset_hashes",
        result.provenance.dataset_hashes,
    );
    try addStringListVariable(
        allocator,
        &owned_buffers,
        &dimensions,
        &variables,
        "native_capability_count",
        "native_capability_strlen",
        "native_capability_slots",
        result.provenance.native_capability_slots,
    );
    try addStringListVariable(
        allocator,
        &owned_buffers,
        &dimensions,
        &variables,
        "native_entry_symbol_count",
        "native_entry_symbol_strlen",
        "native_entry_symbols",
        result.provenance.native_entry_symbols,
    );
    try addStringListVariable(
        allocator,
        &owned_buffers,
        &dimensions,
        &variables,
        "native_library_path_count",
        "native_library_path_strlen",
        "native_library_paths",
        result.provenance.native_library_paths,
    );

    if (result.measurement_space_product) |product| {
        try addDoubleVariable(allocator, &dimensions, &variables, "wavelength_sample_count", "wavelength_nm", product.wavelengths);
        try addDoubleVariable(allocator, &dimensions, &variables, "radiance_sample_count", "toa_radiance", product.radiance);
        try addDoubleVariable(allocator, &dimensions, &variables, "irradiance_sample_count", "solar_irradiance", product.irradiance);
        try addDoubleVariable(allocator, &dimensions, &variables, "reflectance_sample_count", "reflectance", product.reflectance);
        try addDoubleVariable(allocator, &dimensions, &variables, "noise_sample_count", "noise_sigma", product.noise_sigma);
        if (product.jacobian) |jacobian| {
            try addDoubleVariable(allocator, &dimensions, &variables, "jacobian_sample_count", "jacobian", jacobian);
        }
    }

    const header_size = try computeHeaderSize(dimensions.items, global_attributes.items, variables.items);
    var begins = try allocator.alloc(u32, variables.items.len);
    defer allocator.free(begins);

    var next_offset = header_size;
    for (variables.items, 0..) |variable, index| {
        begins[index] = try toU32(next_offset);
        next_offset += align4(variable.dataLen());
    }

    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(allocator);
    const writer = buffer.writer(allocator);

    try writer.writeAll("CDF\x01");
    try writer.writeInt(u32, 0, .big);
    try writeDimensionList(writer, dimensions.items);
    try writeAttributeList(writer, global_attributes.items);
    try writeVariableList(writer, variables.items, begins);

    for (variables.items) |variable| {
        try writeVariableData(writer, variable);
    }

    return buffer.toOwnedSlice(allocator);
}

fn addStringVariable(
    allocator: std.mem.Allocator,
    dimensions: *std.ArrayList(Dimension),
    variables: *std.ArrayList(Variable),
    dimension_name: []const u8,
    variable_name: []const u8,
    value: []const u8,
) !void {
    const dimension_id = try appendDimension(allocator, dimensions, dimension_name, fixedStringLen(value));
    try variables.append(allocator, .{
        .name = variable_name,
        .rank = 1,
        .dim_ids = .{ dimension_id, 0 },
        .data = .{ .char = if (value.len == 0) zero_char[0..] else value },
    });
}

fn addStringListVariable(
    allocator: std.mem.Allocator,
    owned_buffers: *std.ArrayList([]u8),
    dimensions: *std.ArrayList(Dimension),
    variables: *std.ArrayList(Variable),
    count_dimension_name: []const u8,
    width_dimension_name: []const u8,
    variable_name: []const u8,
    values: []const []const u8,
) !void {
    if (values.len == 0) return;

    const count_dimension_id = try appendDimension(allocator, dimensions, count_dimension_name, values.len);
    const width_dimension_id = try appendDimension(allocator, dimensions, width_dimension_name, maxStringLen(values));
    const payload = try encodeStringMatrix(allocator, owned_buffers, values, dimensions.items[@as(usize, width_dimension_id)].len);

    try variables.append(allocator, .{
        .name = variable_name,
        .rank = 2,
        .dim_ids = .{ count_dimension_id, width_dimension_id },
        .data = .{ .char = payload },
    });
}

fn addDoubleVariable(
    allocator: std.mem.Allocator,
    dimensions: *std.ArrayList(Dimension),
    variables: *std.ArrayList(Variable),
    dimension_name: []const u8,
    variable_name: []const u8,
    values: []const f64,
) !void {
    if (values.len == 0) return;

    const dimension_id = try appendDimension(allocator, dimensions, dimension_name, values.len);
    try variables.append(allocator, .{
        .name = variable_name,
        .rank = 1,
        .dim_ids = .{ dimension_id, 0 },
        .data = .{ .double = values },
    });
}

fn appendDimension(
    allocator: std.mem.Allocator,
    dimensions: *std.ArrayList(Dimension),
    name: []const u8,
    len: usize,
) !u32 {
    const dimension_id = try toU32(dimensions.items.len);
    try dimensions.append(allocator, .{
        .name = name,
        .len = try toU32(len),
    });
    return dimension_id;
}

fn allocOwnedPrint(
    allocator: std.mem.Allocator,
    owned_buffers: *std.ArrayList([]u8),
    comptime format: []const u8,
    args: anytype,
) ![]const u8 {
    const payload = try std.fmt.allocPrint(allocator, format, args);
    try owned_buffers.append(allocator, payload);
    return payload;
}

fn encodeStringMatrix(
    allocator: std.mem.Allocator,
    owned_buffers: *std.ArrayList([]u8),
    values: []const []const u8,
    width: u32,
) ![]const u8 {
    const width_usize = @as(usize, width);
    const payload = try allocator.alloc(u8, values.len * width_usize);
    @memset(payload, 0);
    for (values, 0..) |value, index| {
        const row = payload[index * width_usize ..][0..width_usize];
        std.mem.copyForwards(u8, row[0..value.len], value);
    }
    try owned_buffers.append(allocator, payload);
    return payload;
}

fn computeHeaderSize(
    dimensions: []const Dimension,
    global_attributes: []const Attribute,
    variables: []const Variable,
) !usize {
    var total: usize = 8;
    total += listSizeDimensions(dimensions);
    total += listSizeAttributes(global_attributes);
    total += listSizeVariables(variables);
    return total;
}

fn listSizeDimensions(dimensions: []const Dimension) usize {
    if (dimensions.len == 0) return 8;

    var total: usize = 8;
    for (dimensions) |dimension| {
        total += nameFieldSize(dimension.name);
        total += 4;
    }
    return total;
}

fn listSizeAttributes(attributes: []const Attribute) usize {
    if (attributes.len == 0) return 8;

    var total: usize = 8;
    for (attributes) |attribute| {
        total += nameFieldSize(attribute.name);
        total += 8;
        total += align4(attributeValueLen(attribute));
    }
    return total;
}

fn listSizeVariables(variables: []const Variable) usize {
    if (variables.len == 0) return 8;

    var total: usize = 8;
    for (variables) |variable| {
        total += nameFieldSize(variable.name);
        total += 4;
        total += 4 * @as(usize, variable.rank);
        total += 8;
        total += 12;
    }
    return total;
}

fn writeDimensionList(writer: anytype, dimensions: []const Dimension) !void {
    if (dimensions.len == 0) {
        try writeAbsentList(writer);
        return;
    }

    try writer.writeInt(u32, NC_DIMENSION, .big);
    try writer.writeInt(u32, try toU32(dimensions.len), .big);
    for (dimensions) |dimension| {
        try writeName(writer, dimension.name);
        try writer.writeInt(u32, dimension.len, .big);
    }
}

fn writeAttributeList(writer: anytype, attributes: []const Attribute) !void {
    if (attributes.len == 0) {
        try writeAbsentList(writer);
        return;
    }

    try writer.writeInt(u32, NC_ATTRIBUTE, .big);
    try writer.writeInt(u32, try toU32(attributes.len), .big);
    for (attributes) |attribute| {
        try writeName(writer, attribute.name);
        switch (attribute.value) {
            .char => |value| {
                try writer.writeInt(u32, @intFromEnum(NcType.char), .big);
                try writer.writeInt(u32, try toU32(value.len), .big);
                try writer.writeAll(value);
                try writePadding(writer, value.len);
            },
            .int => |value| {
                try writer.writeInt(u32, @intFromEnum(NcType.int), .big);
                try writer.writeInt(u32, 1, .big);
                try writer.writeInt(i32, value, .big);
            },
            .double => |value| {
                try writer.writeInt(u32, @intFromEnum(NcType.double), .big);
                try writer.writeInt(u32, 1, .big);
                try writer.writeInt(u64, @as(u64, @bitCast(value)), .big);
            },
        }
    }
}

fn writeVariableList(writer: anytype, variables: []const Variable, begins: []const u32) !void {
    if (variables.len == 0) {
        try writeAbsentList(writer);
        return;
    }

    try writer.writeInt(u32, NC_VARIABLE, .big);
    try writer.writeInt(u32, try toU32(variables.len), .big);
    for (variables, 0..) |variable, index| {
        try writeName(writer, variable.name);
        try writer.writeInt(u32, variable.rank, .big);
        for (0..@as(usize, variable.rank)) |dim_index| {
            try writer.writeInt(u32, variable.dim_ids[dim_index], .big);
        }
        try writeAbsentList(writer);
        try writer.writeInt(u32, @intFromEnum(variableNcType(variable)), .big);
        try writer.writeInt(u32, try toU32(align4(variable.dataLen())), .big);
        try writer.writeInt(u32, begins[index], .big);
    }
}

fn writeVariableData(writer: anytype, variable: Variable) !void {
    switch (variable.data) {
        .char => |value| {
            try writer.writeAll(value);
            try writePadding(writer, value.len);
        },
        .double => |values| {
            for (values) |value| {
                try writer.writeInt(u64, @as(u64, @bitCast(value)), .big);
            }
            try writePadding(writer, values.len * @sizeOf(f64));
        },
    }
}

fn variableNcType(variable: Variable) NcType {
    return switch (variable.data) {
        .char => .char,
        .double => .double,
    };
}

fn writeName(writer: anytype, name: []const u8) !void {
    try writer.writeInt(u32, try toU32(name.len), .big);
    try writer.writeAll(name);
    try writePadding(writer, name.len);
}

fn writeAbsentList(writer: anytype) !void {
    try writer.writeInt(u32, 0, .big);
    try writer.writeInt(u32, 0, .big);
}

fn writePadding(writer: anytype, len: usize) !void {
    const pad_len = align4(len) - len;
    for (0..pad_len) |_| try writer.writeByte(0);
}

fn nameFieldSize(name: []const u8) usize {
    return 4 + align4(name.len);
}

fn attributeValueLen(attribute: Attribute) usize {
    return switch (attribute.value) {
        .char => |value| value.len,
        .int => 4,
        .double => 8,
    };
}

fn fixedStringLen(value: []const u8) usize {
    return if (value.len == 0) 1 else value.len;
}

fn maxStringLen(values: []const []const u8) usize {
    var max_len: usize = 1;
    for (values) |value| {
        max_len = @max(max_len, value.len);
    }
    return max_len;
}

fn align4(len: usize) usize {
    return (len + 3) & ~@as(usize, 3);
}

fn toU32(value: usize) Error!u32 {
    return std.math.cast(u32, value) orelse Error.ValueOutOfRange;
}

fn toI32(value: usize) Error!i32 {
    return std.math.cast(i32, value) orelse Error.ValueOutOfRange;
}

test "netcdf/cf exporter renders a classic binary payload with named metadata tables" {
    const dataset_hashes = [_][]const u8{"sha256:test-dataset"};
    const native_capabilities = [_][]const u8{"exporter"};
    const native_symbols = [_][]const u8{"zdisamar_plugin_export"};
    const native_libraries = [_][]const u8{"plugins/libexporter.so"};

    var provenance: @import("../../core/provenance.zig").Provenance = .{
        .plan_id = 21,
        .workspace_label = "ws",
        .scene_id = "scene-a",
        .dataset_hashes = &dataset_hashes,
        .native_capability_slots = &native_capabilities,
        .native_entry_symbols = &native_symbols,
        .native_library_paths = &native_libraries,
    };
    provenance.setPluginVersions(&[_][]const u8{"builtin.netcdf_cf@0.1.0"});
    var result = Result.init(21, "ws", "scene-a", provenance);
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

    const payload = try renderNetcdfClassicPayload(std.testing.allocator, Spec.buildArtifact(.{
        .format = .netcdf_cf,
        .destination_uri = "file://out/scene-a.nc",
        .dataset_name = "scene-a",
    }), result);
    defer std.testing.allocator.free(payload);

    try std.testing.expect(std.mem.startsWith(u8, payload, "CDF\x01"));
    try std.testing.expect(std.mem.containsAtLeast(u8, payload, 1, "Conventions"));
    try std.testing.expect(std.mem.containsAtLeast(u8, payload, 1, "plugin_versions"));
    try std.testing.expect(std.mem.containsAtLeast(u8, payload, 1, "native_library_paths"));
    try std.testing.expect(std.mem.containsAtLeast(u8, payload, 1, "scene-a"));
    try std.testing.expect(std.mem.containsAtLeast(u8, payload, 1, "wavelength_nm"));
    try std.testing.expect(std.mem.containsAtLeast(u8, payload, 1, "toa_radiance"));
    try std.testing.expect(std.mem.containsAtLeast(u8, payload, 1, "effective_air_mass_factor"));
    try std.testing.expect(std.mem.containsAtLeast(u8, payload, 1, "cia_optical_depth"));
}
