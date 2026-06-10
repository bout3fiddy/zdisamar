const std = @import("std");
const errors = @import("../../common/errors.zig");
const constants = @import("constants.zig");
const max_line_shape_samples = constants.max_line_shape_samples;
const max_line_shape_nominals = constants.max_line_shape_nominals;

// line_shape.zig ---------------------------------------------------------------------------------------------|
// Instrument line-shape payloads used before spectral convolution writes integration kernels.                 |
//                                                                                                             |
// called from                                                                                                 |
//   Instrument and ObservationModel retain these rows inside operational band support.                        |
//   ObservationModel.spectralResponse borrows the active explicit kernel/table into SpectralResponse.         |
//   integrationForWavelengthWithAdaptiveCacheChecked chooses the table-backed or fixed explicit kernel route  |
//   before falling back to adaptive or built-in line-shape integration.                                       |
//   instrument-grid cache hashing records the retained kernel values so changed ISRF data invalidates cached  |
//   forward-model products.                                                                                   |
//                                                                                                             |
// main paths                                                                                                  |
//   BuiltinLineShapeKind.parse maps input/vendor names onto the built-in slit family.                         |
//   validate checks bounded counts, backing slice lengths, sorted nominal wavelengths, and positive weights.  |
//   ensureOwnedStorage expands borrowed parser slices into fixed-capacity arrays used by mutable loaders.     |
//   writeNormalizedKernel and writeNormalizedKernelForNominal copy one bounded kernel into caller-owned       |
//   scratch slices and normalize weights before convolution.                                                  |
//                                                                                                             |
// hot reads                                                                                                   |
//   Instrument integration repeats the selected kernel write for nominal channel samples. Table lookup scans  |
//   nominal_wavelengths_nm for the closest row, then streams offset/weight samples from flattened storage.    |
//                                                                                                             |
// ownership                                                                                                   |
//   InstrumentLineShape and InstrumentLineShapeTable are slice headers over borrowed or owned arrays. clone   |
//   and ensureOwnedStorage allocate support arrays and set owns_memory. deinitOwned frees only when that flag |
//   is true, so borrowed parser slices are not released here.                                                 |
// ------------------------------------------------------------------------------------------------------------|

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

// InstrumentLineShape ----------------------------------------------------------------------------------------|
// One line-shape kernel header.                                                                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] offsets_nm  : []const f64                                                                          |
// [16..31] weights     : []const f64                                                                          |
// [32..32] sample_count: u8                                                                                   |
// [33..33] owns_memory : bool                                                                                 |
// [34..39] trailing padding : 6 B                                                                             |
//                                                                                                             |
// referenced storage                                                                                          |
//   offsets_nm and weights point at borrowed input slices or owned arrays when owns_memory is true.           |
//                                                                                                             |
// unused bits: 48 padding + 7 bool-storage slack = 55 bits                                                    |
// footprint: per instance = 40 B (0.039 KiB); total also includes referenced kernel arrays                    |
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
        // InstrumentLineShape.writeNormalizedKernel ----------------------------------------------------------|
        // Copies the explicit kernel into caller-owned scratch slices and normalizes the weights.             |
        //                                                                                                     |
        // hot path                                                                                            |
        //   repeated : one nominal channel sample during instrument integration                               |
        //   reads    : offsets_nm, weights, sample_count                                                      |
        //   writes   : caller-owned kernel slices                                                             |
        //   caller   : integrationForWavelengthWithAdaptiveCacheChecked                                       |
        // ----------------------------------------------------------------------------------------------------|

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
// ------------------------------------------------------------------------------------------------------------|

// InstrumentLineShapeTable -----------------------------------------------------------------------------------|
// Several line-shape kernels keyed by nominal wavelength.                                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 56 B (0.055 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] nominal_wavelengths_nm : []const f64                                                               |
// [16..31] offsets_nm             : []const f64                                                               |
// [32..47] weights                : []const f64                                                               |
// [48..49] nominal_count          : u16                                                                       |
// [50..50] sample_count           : u8                                                                        |
// [51..51] owns_memory            : bool                                                                      |
// [52..55] trailing padding       : 4 B                                                                       |
//                                                                                                             |
// referenced storage                                                                                          |
//   nominal_wavelengths_nm, offsets_nm, and weights point at borrowed input or owned arrays.                  |
//                                                                                                             |
// unused bits: 32 padding + 7 bool-storage slack = 39 bits                                                    |
// footprint: per instance = 56 B (0.055 KiB); total also includes referenced table arrays                     |
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

        const has_empty_table = self.nominal_count == 0 and self.sample_count == 0;
        if (has_empty_table) return;

        const has_partial_table = self.nominal_count == 0 or self.sample_count == 0;
        if (has_partial_table) {
            return errors.Error.InvalidRequest;
        }

        const required_weight_count = @as(usize, self.nominal_count) * @as(usize, self.sample_count);
        if (self.nominal_wavelengths_nm.len < self.nominal_count or
            self.offsets_nm.len < self.sample_count or
            self.weights.len < required_weight_count)
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

        if (self.nominal_wavelengths_nm.len != 0) {
            @memcpy(
                nominals[0..self.nominal_wavelengths_nm.len],
                self.nominal_wavelengths_nm,
            );
        }
        if (self.offsets_nm.len != 0) {
            @memcpy(offsets[0..self.offsets_nm.len], self.offsets_nm);
        }
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
        // InstrumentLineShapeTable.nearestNominalIndex -------------------------------------------------------|
        // Finds the closest nominal kernel row for one wavelength.                                            |
        //                                                                                                     |
        // hot path                                                                                            |
        //   repeated : each table-backed line-shape integration point                                         |
        //   reads    : nominal_wavelengths_nm                                                                 |
        //   output   : closest row index, or null for an empty table                                          |
        // ----------------------------------------------------------------------------------------------------|

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
        // InstrumentLineShapeTable.writeNormalizedKernelForNominal -------------------------------------------|
        // Selects a nominal row, copies that kernel into caller-owned slices, and normalizes the weights.     |
        //                                                                                                     |
        // hot path                                                                                            |
        //   repeated : table-backed instrument integration point                                              |
        //   reads    : nominal_wavelengths_nm, offsets_nm, weights                                            |
        //   writes   : caller-owned kernel slices                                                             |
        // ----------------------------------------------------------------------------------------------------|

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
// ------------------------------------------------------------------------------------------------------------|
