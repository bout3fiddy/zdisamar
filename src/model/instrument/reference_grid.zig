const std = @import("std");
const errors = @import("../../core/errors.zig");
const Allocator = std.mem.Allocator;

pub const OperationalReferenceGrid = struct {
    wavelengths_nm: []const f64 = &[_]f64{},
    weights: []const f64 = &[_]f64{},

    pub fn enabled(self: OperationalReferenceGrid) bool {
        return self.wavelengths_nm.len > 0;
    }

    pub fn validate(self: OperationalReferenceGrid) errors.Error!void {
        if (!self.enabled()) {
            if (self.weights.len != 0) return errors.Error.InvalidRequest;
            return;
        }
        if (self.weights.len != self.wavelengths_nm.len) return errors.Error.InvalidRequest;

        var previous_wavelength: ?f64 = null;
        var weight_sum: f64 = 0.0;
        for (self.wavelengths_nm, self.weights) |wavelength_nm, weight| {
            if (!std.math.isFinite(wavelength_nm) or !std.math.isFinite(weight) or weight < 0.0) {
                return errors.Error.InvalidRequest;
            }
            if (previous_wavelength) |previous| {
                if (wavelength_nm <= previous) return errors.Error.InvalidRequest;
            }
            previous_wavelength = wavelength_nm;
            weight_sum += weight;
        }
        if (weight_sum <= 0.0 or !std.math.isFinite(weight_sum)) return errors.Error.InvalidRequest;
    }

    pub fn clone(self: OperationalReferenceGrid, allocator: Allocator) !OperationalReferenceGrid {
        return .{
            .wavelengths_nm = try allocator.dupe(f64, self.wavelengths_nm),
            .weights = try allocator.dupe(f64, self.weights),
        };
    }

    pub fn deinitOwned(self: *OperationalReferenceGrid, allocator: Allocator) void {
        allocator.free(self.wavelengths_nm);
        allocator.free(self.weights);
        self.* = .{};
    }
};
