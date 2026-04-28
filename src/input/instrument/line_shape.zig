const std = @import("std");
const errors = @import("../../common/errors.zig");
const constants = @import("constants.zig");
const max_line_shape_samples = constants.max_line_shape_samples;
const max_line_shape_nominals = constants.max_line_shape_nominals;

pub const BuiltinLineShapeKind = enum {
    gaussian,
    flat_top_n4,
    triple_flat_top_n4,

    pub fn parse(name: []const u8) errors.Error!BuiltinLineShapeKind {
        if (name.len == 0 or std.mem.eql(u8, name, "gaussian")) return .gaussian;
        if (std.mem.eql(u8, name, "flat_top") or
            std.mem.eql(u8, name, "flat_top_n4") or
            std.mem.eql(u8, name, "flat_topped") or
            std.mem.eql(u8, name, "vendor_flat_top"))
        {
            return .flat_top_n4;
        }
        if (std.mem.eql(u8, name, "triple_flat_top") or
            std.mem.eql(u8, name, "triple_flat_top_n4"))
        {
            return .triple_flat_top_n4;
        }
        if (std.mem.eql(u8, name, "table")) return .gaussian;
        return errors.Error.InvalidRequest;
    }
};

pub const InstrumentLineShape = struct {
    sample_count: u8 = 0,
    offsets_nm: []const f64 = &.{},
    weights: []const f64 = &.{},
    owns_memory: bool = false,

    pub fn validate(self: *const InstrumentLineShape) errors.Error!void {
        if (self.sample_count > max_line_shape_samples) {
            return errors.Error.InvalidRequest;
        }
        if (self.sample_count == 0) return;
        if (self.offsets_nm.len < self.sample_count or self.weights.len < self.sample_count) {
            return errors.Error.InvalidRequest;
        }

        var weight_sum: f64 = 0.0;
        for (0..self.sample_count) |index| {
            if (self.weights[index] < 0.0) return errors.Error.InvalidRequest;
            weight_sum += self.weights[index];
        }
        if (!std.math.isFinite(weight_sum) or weight_sum <= 0.0) {
            return errors.Error.InvalidRequest;
        }
    }

    pub fn ensureOwnedStorage(self: *InstrumentLineShape, allocator: std.mem.Allocator) !void {
        if (self.owns_memory) return;

        const offsets = try allocator.alloc(f64, max_line_shape_samples);
        errdefer allocator.free(offsets);
        const weights = try allocator.alloc(f64, max_line_shape_samples);
        errdefer allocator.free(weights);

        @memset(offsets, 0.0);
        @memset(weights, 0.0);
        if (self.offsets_nm.len != 0) @memcpy(offsets[0..self.offsets_nm.len], self.offsets_nm);
        if (self.weights.len != 0) @memcpy(weights[0..self.weights.len], self.weights);

        self.offsets_nm = offsets;
        self.weights = weights;
        self.owns_memory = true;
    }

    pub fn clone(self: InstrumentLineShape, allocator: std.mem.Allocator) !InstrumentLineShape {
        if (self.sample_count == 0) return .{};

        const offsets = try allocator.dupe(f64, self.offsets_nm[0..self.sample_count]);
        errdefer allocator.free(offsets);
        const weights = try allocator.dupe(f64, self.weights[0..self.sample_count]);

        return .{
            .sample_count = self.sample_count,
            .offsets_nm = offsets,
            .weights = weights,
            .owns_memory = true,
        };
    }

    pub fn deinitOwned(self: *InstrumentLineShape, allocator: std.mem.Allocator) void {
        if (self.owns_memory) {
            if (self.offsets_nm.len != 0) allocator.free(@constCast(self.offsets_nm));
            if (self.weights.len != 0) allocator.free(@constCast(self.weights));
        }
        self.* = .{};
    }

    pub fn writeNormalizedKernel(
        self: *const InstrumentLineShape,
        offsets_out: []f64,
        weights_out: []f64,
    ) usize {
        const sample_count = @min(@as(usize, self.sample_count), @min(offsets_out.len, weights_out.len));
        if (sample_count == 0) return 0;

        var weight_sum: f64 = 0.0;
        for (0..sample_count) |index| {
            offsets_out[index] = self.offsets_nm[index];
            weights_out[index] = self.weights[index];
            weight_sum += weights_out[index];
        }
        if (!std.math.isFinite(weight_sum) or weight_sum <= 0.0) return 0;
        for (0..sample_count) |index| weights_out[index] /= weight_sum;
        return sample_count;
    }
};

pub const InstrumentLineShapeTable = struct {
    nominal_count: u16 = 0,
    sample_count: u8 = 0,
    nominal_wavelengths_nm: []const f64 = &.{},
    offsets_nm: []const f64 = &.{},
    weights: []const f64 = &.{},
    owns_memory: bool = false,

    pub fn validate(self: *const InstrumentLineShapeTable) errors.Error!void {
        if (self.nominal_count > max_line_shape_nominals or self.sample_count > max_line_shape_samples) {
            return errors.Error.InvalidRequest;
        }
        if (self.nominal_count == 0 and self.sample_count == 0) return;
        if (self.nominal_count == 0 or self.sample_count == 0) {
            return errors.Error.InvalidRequest;
        }
        if (self.nominal_wavelengths_nm.len < self.nominal_count or
            self.offsets_nm.len < self.sample_count or
            self.weights.len < @as(usize, self.nominal_count) * @as(usize, self.sample_count))
        {
            return errors.Error.InvalidRequest;
        }

        var previous_nominal: ?f64 = null;
        for (0..self.nominal_count) |nominal_index| {
            const nominal = self.nominal_wavelengths_nm[nominal_index];
            if (!std.math.isFinite(nominal)) return errors.Error.InvalidRequest;
            if (previous_nominal) |previous| {
                if (nominal < previous) return errors.Error.InvalidRequest;
            }
            previous_nominal = nominal;

            var row_sum: f64 = 0.0;
            for (0..self.sample_count) |sample_index| {
                const weight = self.weightAt(nominal_index, sample_index);
                if (weight < 0.0 or !std.math.isFinite(weight)) return errors.Error.InvalidRequest;
                row_sum += weight;
            }
            if (row_sum <= 0.0 or !std.math.isFinite(row_sum)) return errors.Error.InvalidRequest;
        }
    }

    pub fn clone(self: InstrumentLineShapeTable, allocator: std.mem.Allocator) !InstrumentLineShapeTable {
        if (self.nominal_count == 0 or self.sample_count == 0) return .{};

        const nominal_count = @as(usize, self.nominal_count);
        const sample_count = @as(usize, self.sample_count);
        const nominal_wavelengths = try allocator.dupe(f64, self.nominal_wavelengths_nm[0..nominal_count]);
        errdefer allocator.free(nominal_wavelengths);
        const offsets = try allocator.dupe(f64, self.offsets_nm[0..sample_count]);
        errdefer allocator.free(offsets);
        const weights = try allocator.dupe(f64, self.weights[0 .. nominal_count * sample_count]);
        return .{
            .nominal_count = self.nominal_count,
            .sample_count = self.sample_count,
            .nominal_wavelengths_nm = nominal_wavelengths,
            .offsets_nm = offsets,
            .weights = weights,
            .owns_memory = true,
        };
    }

    pub fn ensureOwnedStorage(self: *InstrumentLineShapeTable, allocator: std.mem.Allocator) !void {
        if (self.owns_memory) return;

        const nominals = try allocator.alloc(f64, max_line_shape_nominals);
        errdefer allocator.free(nominals);
        const offsets = try allocator.alloc(f64, max_line_shape_samples);
        errdefer allocator.free(offsets);
        const weights = try allocator.alloc(f64, max_line_shape_nominals * max_line_shape_samples);
        errdefer allocator.free(weights);

        @memset(nominals, 0.0);
        @memset(offsets, 0.0);
        @memset(weights, 0.0);
        if (self.nominal_wavelengths_nm.len != 0) @memcpy(nominals[0..self.nominal_wavelengths_nm.len], self.nominal_wavelengths_nm);
        if (self.offsets_nm.len != 0) @memcpy(offsets[0..self.offsets_nm.len], self.offsets_nm);
        if (self.weights.len != 0) @memcpy(weights[0..self.weights.len], self.weights);

        self.nominal_wavelengths_nm = nominals;
        self.offsets_nm = offsets;
        self.weights = weights;
        self.owns_memory = true;
    }

    pub fn weightAt(self: *const InstrumentLineShapeTable, nominal_index: usize, sample_index: usize) f64 {
        return self.weights[nominal_index * @as(usize, self.sample_count) + sample_index];
    }

    pub fn setWeight(self: *InstrumentLineShapeTable, nominal_index: usize, sample_index: usize, value: f64) void {
        @constCast(self.weights)[nominal_index * @as(usize, self.sample_count) + sample_index] = value;
    }

    pub fn nearestNominalIndex(self: *const InstrumentLineShapeTable, wavelength_nm: f64) ?usize {
        if (self.nominal_count == 0) return null;

        var best_index: usize = 0;
        var best_delta = std.math.inf(f64);
        for (0..self.nominal_count) |index| {
            const delta = @abs(self.nominal_wavelengths_nm[index] - wavelength_nm);
            if (delta < best_delta) {
                best_delta = delta;
                best_index = index;
            }
        }
        return best_index;
    }

    pub fn writeNormalizedKernelForNominal(
        self: *const InstrumentLineShapeTable,
        nominal_wavelength_nm: f64,
        offsets_out: []f64,
        weights_out: []f64,
    ) usize {
        const nominal_index = self.nearestNominalIndex(nominal_wavelength_nm) orelse return 0;
        const sample_count = @min(@as(usize, self.sample_count), @min(offsets_out.len, weights_out.len));
        if (sample_count == 0) return 0;

        var weight_sum: f64 = 0.0;
        for (0..sample_count) |index| {
            offsets_out[index] = self.offsets_nm[index];
            weights_out[index] = self.weightAt(nominal_index, index);
            weight_sum += weights_out[index];
        }
        if (!std.math.isFinite(weight_sum) or weight_sum <= 0.0) return 0;
        for (0..sample_count) |index| weights_out[index] /= weight_sum;
        return sample_count;
    }

    pub fn deinitOwned(self: *InstrumentLineShapeTable, allocator: std.mem.Allocator) void {
        if (self.owns_memory) {
            if (self.nominal_wavelengths_nm.len != 0) allocator.free(@constCast(self.nominal_wavelengths_nm));
            if (self.offsets_nm.len != 0) allocator.free(@constCast(self.offsets_nm));
            if (self.weights.len != 0) allocator.free(@constCast(self.weights));
        }
        self.* = .{};
    }
};
