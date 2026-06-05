const std = @import("std");

const c = @cImport({
    @cInclude("zlib.h");
});

// instrumentation: telemetry storage
// captures: fixed flat columns
// why: write compact Parquet directly without CSV staging.
pub const Compression = enum {
    uncompressed,
    gzip,

    fn parquetCodec(self: Compression) i32 {
        return switch (self) {
            .uncompressed => 0,
            .gzip => 2,
        };
    }
};

pub const ColumnKind = enum {
    int32,
    int64,
    double,
    byte_array,

    fn parquetType(self: ColumnKind) i32 {
        return switch (self) {
            .int32 => 1,
            .int64 => 2,
            .double => 5,
            .byte_array => 6,
        };
    }

    fn fixedWidth(self: ColumnKind) ?usize {
        return switch (self) {
            .int32 => 4,
            .int64 => 8,
            .double => 8,
            .byte_array => null,
        };
    }
};

pub const ColumnDef = struct {
    name: []const u8,
    kind: ColumnKind,
    utf8: bool = false,
};

pub const Options = struct {
    row_group_rows: usize = 65_536,
    compression: Compression = .gzip,
    created_by: []const u8 = "zdisamar parquet_lite",
};

const parquet_magic = "PAR1";
const encoding_plain = 0;
const encoding_rle = 3;

// instrumentation: telemetry storage
// captures: row-grouped typed values
// why: keep capture output columnar and bounded by flush size.
pub const TableWriter = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    file: std.Io.File,
    columns: []const ColumnDef,
    buffers: []ColumnBuffer,
    row_groups: std.ArrayList(RowGroupMeta) = .empty,
    chunks: std.ArrayList(ChunkMeta) = .empty,
    footer_buffer: std.ArrayList(u8) = .empty,
    page_header_buffer: std.ArrayList(u8) = .empty,
    compressed_buffer: std.ArrayList(u8) = .empty,
    options: Options,
    current_rows: usize = 0,
    total_rows: u64 = 0,
    current_offset: u64 = parquet_magic.len,
    closed: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        file: std.Io.File,
        columns: []const ColumnDef,
        options: Options,
    ) !TableWriter {
        if (columns.len == 0) return error.EmptySchema;
        if (options.row_group_rows == 0) return error.InvalidRowGroupSize;

        var file_open = true;
        errdefer if (file_open) file.close(io);

        const buffers = try allocator.alloc(ColumnBuffer, columns.len);
        errdefer allocator.free(buffers);

        for (columns, buffers) |column_def, *buffer| {
            buffer.* = .{ .kind = column_def.kind };
            if (column_def.kind.fixedWidth()) |width| {
                const capacity = options.row_group_rows * width;
                try buffer.bytes.ensureTotalCapacityPrecise(allocator, capacity);
            }
        }

        var table = TableWriter{
            .allocator = allocator,
            .io = io,
            .file = file,
            .columns = columns,
            .buffers = buffers,
            .options = options,
        };
        file_open = false;
        errdefer table.deinit();
        try table.writeAll(parquet_magic);
        return table;
    }

    pub fn deinit(self: *TableWriter) void {
        for (self.buffers) |*buffer| {
            buffer.deinit(self.allocator);
        }
        self.allocator.free(self.buffers);
        self.row_groups.deinit(self.allocator);
        self.chunks.deinit(self.allocator);
        self.footer_buffer.deinit(self.allocator);
        self.page_header_buffer.deinit(self.allocator);
        self.compressed_buffer.deinit(self.allocator);
        self.file.close(self.io);
        self.* = undefined;
    }

    pub fn appendInt32(self: *TableWriter, column_index: usize, value: i32) !void {
        try self.column(column_index, .int32).appendInt32(self.allocator, value);
    }

    pub fn appendInt64(self: *TableWriter, column_index: usize, value: i64) !void {
        try self.column(column_index, .int64).appendInt64(self.allocator, value);
    }

    pub fn appendDouble(self: *TableWriter, column_index: usize, value: f64) !void {
        try self.column(column_index, .double).appendDouble(self.allocator, value);
    }

    pub fn appendBytes(self: *TableWriter, column_index: usize, value: []const u8) !void {
        try self.column(column_index, .byte_array).appendBytes(self.allocator, value);
    }

    pub fn finishRow(self: *TableWriter) !void {
        self.current_rows += 1;
        self.total_rows += 1;
        if (self.current_rows >= self.options.row_group_rows) {
            try self.flushRowGroup();
        }
    }

    pub fn close(self: *TableWriter) !void {
        if (self.closed) return;
        try self.flushRowGroup();
        try self.writeFooter();
        self.closed = true;
    }

    fn column(self: *TableWriter, column_index: usize, expected: ColumnKind) *ColumnBuffer {
        std.debug.assert(column_index < self.buffers.len);
        std.debug.assert(self.columns[column_index].kind == expected);
        return &self.buffers[column_index];
    }

    fn flushRowGroup(self: *TableWriter) !void {
        if (self.current_rows == 0) return;

        const first_chunk = self.chunks.items.len;
        var total_byte_size: u64 = 0;
        for (self.columns, self.buffers) |column_def, *buffer| {
            const data_page_offset = self.current_offset;
            self.page_header_buffer.clearRetainingCapacity();
            const page_data = try self.pagePayload(buffer.bytes.items);
            try writePageHeader(
                self.allocator,
                &self.page_header_buffer,
                try castI32(self.current_rows),
                try castI32(buffer.bytes.items.len),
                try castI32(page_data.len),
            );

            try self.writeAll(self.page_header_buffer.items);
            try self.writeAll(page_data);

            const total_uncompressed = self.page_header_buffer.items.len + buffer.bytes.items.len;
            const total_compressed = self.page_header_buffer.items.len + page_data.len;
            try self.chunks.append(self.allocator, .{
                .physical_type = column_def.kind.parquetType(),
                .codec = self.options.compression.parquetCodec(),
                .num_values = try castI64(self.current_rows),
                .data_page_offset = try castI64(data_page_offset),
                .file_offset = try castI64(data_page_offset),
                .total_uncompressed_size = try castI64(total_uncompressed),
                .total_compressed_size = try castI64(total_compressed),
            });
            total_byte_size += total_compressed;
            buffer.clear();
        }

        try self.row_groups.append(self.allocator, .{
            .first_chunk = first_chunk,
            .num_rows = try castI64(self.current_rows),
            .total_byte_size = try castI64(total_byte_size),
        });
        self.current_rows = 0;
    }

    fn pagePayload(self: *TableWriter, page_data: []const u8) ![]const u8 {
        switch (self.options.compression) {
            .uncompressed => return page_data,
            .gzip => return self.gzipCompress(page_data),
        }
    }

    fn gzipCompress(self: *TableWriter, page_data: []const u8) ![]const u8 {
        if (page_data.len > std.math.maxInt(c_ulong)) return error.ValueTooLarge;

        var stream: c.z_stream = std.mem.zeroes(c.z_stream);
        const init_result = c.deflateInit2_(
            &stream,
            c.Z_BEST_SPEED,
            c.Z_DEFLATED,
            15 + 16,
            8,
            c.Z_DEFAULT_STRATEGY,
            c.ZLIB_VERSION,
            @sizeOf(c.z_stream),
        );
        if (init_result != c.Z_OK) return error.CompressionFailed;
        defer _ = c.deflateEnd(&stream);

        const bound = c.deflateBound(&stream, @intCast(page_data.len));
        try self.compressed_buffer.ensureTotalCapacityPrecise(self.allocator, bound);
        self.compressed_buffer.items.len = bound;

        stream.next_in = @ptrCast(@constCast(page_data.ptr));
        stream.avail_in = @intCast(page_data.len);
        stream.next_out = @ptrCast(self.compressed_buffer.items.ptr);
        stream.avail_out = @intCast(self.compressed_buffer.items.len);

        const deflate_result = c.deflate(&stream, c.Z_FINISH);
        if (deflate_result != c.Z_STREAM_END) return error.CompressionFailed;
        self.compressed_buffer.items.len = @intCast(stream.total_out);
        return self.compressed_buffer.items;
    }

    fn writeAll(self: *TableWriter, bytes: []const u8) !void {
        var buffer: [4096]u8 = undefined;
        var writer = self.file.writer(self.io, &buffer);
        try writer.interface.writeAll(bytes);
        try writer.interface.flush();
        self.current_offset += bytes.len;
    }

    fn writeFooter(self: *TableWriter) !void {
        self.footer_buffer.clearRetainingCapacity();
        var writer = CompactWriter{ .buffer = &self.footer_buffer, .allocator = self.allocator };
        try writeFileMetadata(&writer, self);
        try self.writeAll(self.footer_buffer.items);

        const footer_len = try castU32(self.footer_buffer.items.len);
        var len_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &len_bytes, footer_len, .little);
        try self.writeAll(&len_bytes);
        try self.writeAll(parquet_magic);
    }
};

const ColumnBuffer = struct {
    kind: ColumnKind,
    bytes: std.ArrayList(u8) = .empty,

    fn deinit(self: *ColumnBuffer, allocator: std.mem.Allocator) void {
        self.bytes.deinit(allocator);
    }

    fn clear(self: *ColumnBuffer) void {
        self.bytes.clearRetainingCapacity();
    }

    fn appendInt32(self: *ColumnBuffer, allocator: std.mem.Allocator, value: i32) !void {
        std.debug.assert(self.kind == .int32);
        const dest = try self.addFixed(allocator, 4);
        std.mem.writeInt(i32, dest[0..4], value, .little);
    }

    fn appendInt64(self: *ColumnBuffer, allocator: std.mem.Allocator, value: i64) !void {
        std.debug.assert(self.kind == .int64);
        const dest = try self.addFixed(allocator, 8);
        std.mem.writeInt(i64, dest[0..8], value, .little);
    }

    fn appendDouble(self: *ColumnBuffer, allocator: std.mem.Allocator, value: f64) !void {
        std.debug.assert(self.kind == .double);
        const dest = try self.addFixed(allocator, 8);
        std.mem.writeInt(u64, dest[0..8], @bitCast(value), .little);
    }

    fn appendBytes(self: *ColumnBuffer, allocator: std.mem.Allocator, value: []const u8) !void {
        std.debug.assert(self.kind == .byte_array);
        if (value.len > std.math.maxInt(u32)) return error.ValueTooLarge;
        try self.bytes.ensureUnusedCapacity(allocator, 4 + value.len);
        const len_dest = self.bytes.addManyAsSliceAssumeCapacity(4);
        std.mem.writeInt(u32, len_dest[0..4], @intCast(value.len), .little);
        self.bytes.appendSliceAssumeCapacity(value);
    }

    fn addFixed(self: *ColumnBuffer, allocator: std.mem.Allocator, width: usize) ![]u8 {
        try self.bytes.ensureUnusedCapacity(allocator, width);
        return self.bytes.addManyAsSliceAssumeCapacity(width);
    }
};

const RowGroupMeta = struct {
    first_chunk: usize,
    num_rows: i64,
    total_byte_size: i64,
};

const ChunkMeta = struct {
    physical_type: i32,
    codec: i32,
    num_values: i64,
    data_page_offset: i64,
    file_offset: i64,
    total_uncompressed_size: i64,
    total_compressed_size: i64,
};

const CompactType = enum(u8) {
    stop = 0,
    bool_true = 1,
    bool_false = 2,
    byte = 3,
    i16 = 4,
    i32 = 5,
    i64 = 6,
    double = 7,
    binary = 8,
    list = 9,
    set = 10,
    map = 11,
    struct_ = 12,
};

const CompactWriter = struct {
    buffer: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    last_field_id: i16 = 0,

    fn resetFieldTracking(self: *CompactWriter) void {
        self.last_field_id = 0;
    }

    fn saveFieldId(self: *const CompactWriter) i16 {
        return self.last_field_id;
    }

    fn restoreFieldId(self: *CompactWriter, field_id: i16) void {
        self.last_field_id = field_id;
    }

    fn writeByte(self: *CompactWriter, value: u8) !void {
        try self.buffer.append(self.allocator, value);
    }

    fn writeBytes(self: *CompactWriter, bytes: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, bytes);
    }

    fn writeVarInt(self: *CompactWriter, value: u64) !void {
        var remaining = value;
        while (remaining >= 0x80) {
            try self.writeByte(@as(u8, @truncate(remaining)) | 0x80);
            remaining >>= 7;
        }
        try self.writeByte(@truncate(remaining));
    }

    fn writeI32(self: *CompactWriter, value: i32) !void {
        try self.writeVarInt(zigzag(value));
    }

    fn writeI64(self: *CompactWriter, value: i64) !void {
        try self.writeVarInt(zigzag(value));
    }

    fn writeString(self: *CompactWriter, value: []const u8) !void {
        try self.writeVarInt(value.len);
        try self.writeBytes(value);
    }

    fn writeFieldHeader(self: *CompactWriter, field_id: i16, field_type: CompactType) !void {
        const delta = field_id - self.last_field_id;
        if (delta > 0 and delta <= 15) {
            try self.writeByte((@as(u8, @intCast(delta)) << 4) | @intFromEnum(field_type));
        } else {
            try self.writeByte(@intFromEnum(field_type));
            try self.writeI16(field_id);
        }
        self.last_field_id = field_id;
    }

    fn writeI16(self: *CompactWriter, value: i16) !void {
        try self.writeVarInt(zigzag(value));
    }

    fn writeListHeader(self: *CompactWriter, element_type: CompactType, size: usize) !void {
        if (size < 15) {
            try self.writeByte((@as(u8, @intCast(size)) << 4) | @intFromEnum(element_type));
        } else {
            try self.writeByte(0xf0 | @intFromEnum(element_type));
            try self.writeVarInt(size);
        }
    }

    fn writeStructEnd(self: *CompactWriter) !void {
        try self.writeByte(@intFromEnum(CompactType.stop));
    }
};

fn writePageHeader(
    allocator: std.mem.Allocator,
    buffer: *std.ArrayList(u8),
    num_values: i32,
    uncompressed_page_size: i32,
    compressed_page_size: i32,
) !void {
    var writer = CompactWriter{ .buffer = buffer, .allocator = allocator };
    writer.resetFieldTracking();
    try writer.writeFieldHeader(1, .i32);
    try writer.writeI32(0);
    try writer.writeFieldHeader(2, .i32);
    try writer.writeI32(uncompressed_page_size);
    try writer.writeFieldHeader(3, .i32);
    try writer.writeI32(compressed_page_size);
    try writer.writeFieldHeader(5, .struct_);

    const saved = writer.saveFieldId();
    writer.resetFieldTracking();
    try writer.writeFieldHeader(1, .i32);
    try writer.writeI32(num_values);
    try writer.writeFieldHeader(2, .i32);
    try writer.writeI32(encoding_plain);
    try writer.writeFieldHeader(3, .i32);
    try writer.writeI32(encoding_rle);
    try writer.writeFieldHeader(4, .i32);
    try writer.writeI32(encoding_rle);
    try writer.writeStructEnd();
    writer.restoreFieldId(saved);

    try writer.writeStructEnd();
}

fn writeFileMetadata(writer: *CompactWriter, table: *const TableWriter) !void {
    writer.resetFieldTracking();
    try writer.writeFieldHeader(1, .i32);
    try writer.writeI32(1);

    try writer.writeFieldHeader(2, .list);
    try writer.writeListHeader(.struct_, table.columns.len + 1);
    try writeRootSchemaElement(writer, table.columns.len);
    for (table.columns) |column| {
        try writeColumnSchemaElement(writer, column);
    }

    try writer.writeFieldHeader(3, .i64);
    try writer.writeI64(try castI64(table.total_rows));

    try writer.writeFieldHeader(4, .list);
    try writer.writeListHeader(.struct_, table.row_groups.items.len);
    for (table.row_groups.items) |row_group| {
        try writeRowGroup(writer, table, row_group);
    }

    try writer.writeFieldHeader(6, .binary);
    try writer.writeString(table.options.created_by);
    try writer.writeStructEnd();
}

fn writeRootSchemaElement(writer: *CompactWriter, column_count: usize) !void {
    const saved = writer.saveFieldId();
    writer.resetFieldTracking();
    try writer.writeFieldHeader(4, .binary);
    try writer.writeString("schema");
    try writer.writeFieldHeader(5, .i32);
    try writer.writeI32(try castI32(column_count));
    try writer.writeStructEnd();
    writer.restoreFieldId(saved);
}

fn writeColumnSchemaElement(writer: *CompactWriter, column: ColumnDef) !void {
    const saved = writer.saveFieldId();
    writer.resetFieldTracking();
    try writer.writeFieldHeader(1, .i32);
    try writer.writeI32(column.kind.parquetType());
    try writer.writeFieldHeader(3, .i32);
    try writer.writeI32(0);
    try writer.writeFieldHeader(4, .binary);
    try writer.writeString(column.name);
    if (column.utf8) {
        try writer.writeFieldHeader(6, .i32);
        try writer.writeI32(0);
    }
    try writer.writeStructEnd();
    writer.restoreFieldId(saved);
}

fn writeRowGroup(writer: *CompactWriter, table: *const TableWriter, row_group: RowGroupMeta) !void {
    const saved = writer.saveFieldId();
    writer.resetFieldTracking();
    try writer.writeFieldHeader(1, .list);
    try writer.writeListHeader(.struct_, table.columns.len);
    const chunks = table.chunks.items[row_group.first_chunk..][0..table.columns.len];
    for (table.columns, chunks) |column, chunk| {
        try writeColumnChunk(writer, column, chunk);
    }
    try writer.writeFieldHeader(2, .i64);
    try writer.writeI64(row_group.total_byte_size);
    try writer.writeFieldHeader(3, .i64);
    try writer.writeI64(row_group.num_rows);
    try writer.writeStructEnd();
    writer.restoreFieldId(saved);
}

fn writeColumnChunk(writer: *CompactWriter, column: ColumnDef, chunk: ChunkMeta) !void {
    const saved = writer.saveFieldId();
    writer.resetFieldTracking();
    try writer.writeFieldHeader(2, .i64);
    try writer.writeI64(chunk.file_offset);
    try writer.writeFieldHeader(3, .struct_);
    try writeColumnMetadata(writer, column, chunk);
    try writer.writeStructEnd();
    writer.restoreFieldId(saved);
}

fn writeColumnMetadata(writer: *CompactWriter, column: ColumnDef, chunk: ChunkMeta) !void {
    const saved = writer.saveFieldId();
    writer.resetFieldTracking();
    try writer.writeFieldHeader(1, .i32);
    try writer.writeI32(chunk.physical_type);
    try writer.writeFieldHeader(2, .list);
    try writer.writeListHeader(.i32, 2);
    try writer.writeI32(encoding_plain);
    try writer.writeI32(encoding_rle);
    try writer.writeFieldHeader(3, .list);
    try writer.writeListHeader(.binary, 1);
    try writer.writeString(column.name);
    try writer.writeFieldHeader(4, .i32);
    try writer.writeI32(chunk.codec);
    try writer.writeFieldHeader(5, .i64);
    try writer.writeI64(chunk.num_values);
    try writer.writeFieldHeader(6, .i64);
    try writer.writeI64(chunk.total_uncompressed_size);
    try writer.writeFieldHeader(7, .i64);
    try writer.writeI64(chunk.total_compressed_size);
    try writer.writeFieldHeader(9, .i64);
    try writer.writeI64(chunk.data_page_offset);
    try writer.writeStructEnd();
    writer.restoreFieldId(saved);
}

fn zigzag(value: anytype) u64 {
    const signed = @as(i64, value);
    return (@as(u64, @bitCast(signed)) << 1) ^ @as(u64, @bitCast(signed >> 63));
}

fn castI32(value: anytype) !i32 {
    return std.math.cast(i32, value) orelse error.IntegerOverflow;
}

fn castI64(value: anytype) !i64 {
    return std.math.cast(i64, value) orelse error.IntegerOverflow;
}

fn castU32(value: anytype) !u32 {
    return std.math.cast(u32, value) orelse error.IntegerOverflow;
}
