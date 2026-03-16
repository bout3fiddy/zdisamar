const std = @import("std");
const errors = @import("../../core/errors.zig");
const constants = @import("constants.zig");
const max_line_shape_samples = constants.max_line_shape_samples;
const max_line_shape_nominals = constants.max_line_shape_nominals;

pub const InstrumentLineShape = struct {
    sample_count: u8 = 0,
    offsets_nm: [max_line_shape_samples]f64 = [_]f64{0.0} ** max_line_shape_samples,
    weights: [max_line_shape_samples]f64 = [_]f64{0.0} ** max_line_shape_samples,

    pub fn validate(self: InstrumentLineShape) errors.Error!void {
        if (self.sample_count > max_line_shape_samples) {
            return errors.Error.InvalidRequest;
        }
        if (self.sample_count == 0) return;

        var weight_sum: f64 = 0.0;
        for (0..self.sample_count) |index| {
            if (self.weights[index] < 0.0) return errors.Error.InvalidRequest;
            weight_sum += self.weights[index];
        }
        if (!std.math.isFinite(weight_sum) or weight_sum <= 0.0) {
            return errors.Error.InvalidRequest;
        }
    }
};

pub const InstrumentLineShapeTable = struct {
    nominal_count: u16 = 0,
    sample_count: u8 = 0,
    nominal_wavelengths_nm: [max_line_shape_nominals]f64 = [_]f64{0.0} ** max_line_shape_nominals,
    offsets_nm: [max_line_shape_samples]f64 = [_]f64{0.0} ** max_line_shape_samples,
    weights: [max_line_shape_nominals * max_line_shape_samples]f64 = [_]f64{0.0} ** (max_line_shape_nominals * max_line_shape_samples),

    pub fn validate(self: InstrumentLineShapeTable) errors.Error!void {
        if (self.nominal_count > max_line_shape_nominals or self.sample_count > max_line_shape_samples) {
            return errors.Error.InvalidRequest;
        }
        if (self.nominal_count == 0 and self.sample_count == 0) return;
        if (self.nominal_count == 0 or self.sample_count == 0) {
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

    pub fn weightAt(self: InstrumentLineShapeTable, nominal_index: usize, sample_index: usize) f64 {
        return self.weights[nominal_index * max_line_shape_samples + sample_index];
    }

    pub fn setWeight(self: *InstrumentLineShapeTable, nominal_index: usize, sample_index: usize, value: f64) void {
        self.weights[nominal_index * max_line_shape_samples + sample_index] = value;
    }

    pub fn nearestNominalIndex(self: InstrumentLineShapeTable, wavelength_nm: f64) ?usize {
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
};
