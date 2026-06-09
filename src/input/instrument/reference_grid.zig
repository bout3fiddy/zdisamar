const std = @import("std");
const errors = @import("../../common/errors.zig");
const Allocator = std.mem.Allocator;

// reference_grid.zig -----------------------------------------------------------------------------------------|
// Operational and adaptive wavelength-grid controls for instrument sampling.                                  |
//                                                                                                             |
// data                                                                                                        |
//   OperationalReferenceGrid is a small header over weighted wavelength samples. AdaptiveReferenceGrid stores |
//   integer controls used by the adaptive instrument-grid builder.                                            |
//                                                                                                             |
// ownership                                                                                                   |
//   OperationalReferenceGrid.clone duplicates wavelength and weight arrays; deinitOwned releases those owned  |
//   arrays. AdaptiveReferenceGrid is an inline value with no referenced storage.                              |
// ------------------------------------------------------------------------------------------------------------|

// OperationalReferenceGrid -----------------------------------------------------------------------------------|
// Weighted support wavelength grid.                                                                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] wavelengths_nm : []const f64                                                                       |
// [16..31] weights        : []const f64                                                                       |
//                                                                                                             |
// referenced storage                                                                                          |
//   wavelengths_nm and weights point at borrowed parser slices or arrays owned by clone.                      |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 32 B (0.031 KiB); total also includes referenced wavelength and weight arrays     |
pub const OperationalReferenceGrid = struct {
    wavelengths_nm: []const f64 = &[_]f64{},
    weights: []const f64 = &[_]f64{},

    pub fn enabled(self: *const OperationalReferenceGrid) bool {
        return self.wavelengths_nm.len > 0;
    }

    pub fn validate(self: *const OperationalReferenceGrid) errors.Error!void {
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
        var cloned: OperationalReferenceGrid = .{};
        cloned.wavelengths_nm = try allocator.dupe(f64, self.wavelengths_nm);
        errdefer allocator.free(cloned.wavelengths_nm);
        cloned.weights = try allocator.dupe(f64, self.weights);
        return cloned;
    }

    pub fn effectiveSpacingNm(self: *const OperationalReferenceGrid) f64 {
        if (self.wavelengths_nm.len < 2) return 1.0;

        var weighted_spacing_sum: f64 = 0.0;
        var pair_weight_sum: f64 = 0.0;

        for (
            self.wavelengths_nm[0 .. self.wavelengths_nm.len - 1],
            self.wavelengths_nm[1..],
            self.weights[0 .. self.weights.len - 1],
            self.weights[1..],
        ) |left_nm, right_nm, left_weight, right_weight| {
            const pair_weight = 0.5 * (left_weight + right_weight);
            weighted_spacing_sum += pair_weight * (right_nm - left_nm);
            pair_weight_sum += pair_weight;
        }

        if (pair_weight_sum <= 0.0 or !std.math.isFinite(pair_weight_sum)) return 1.0;
        return weighted_spacing_sum / pair_weight_sum;
    }

    pub fn deinitOwned(self: *OperationalReferenceGrid, allocator: Allocator) void {
        allocator.free(self.wavelengths_nm);
        allocator.free(self.weights);
        self.* = .{};
    }
};
// ------------------------------------------------------------------------------------------------------------|

// AdaptiveReferenceGrid --------------------------------------------------------------------------------------|
// Adaptive high-resolution grid controls used around strong lines.                                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 6 B (0.006 KiB), align: 2 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
// [0..1] points_per_fwhm           : u16                                                                      |
// [2..3] strong_line_min_divisions : u16                                                                      |
// [4..5] strong_line_max_divisions : u16                                                                      |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 6 B (0.006 KiB); total = per instance * live instance count                       |
pub const AdaptiveReferenceGrid = struct {
    points_per_fwhm: u16 = 0,
    strong_line_min_divisions: u16 = 0,
    strong_line_max_divisions: u16 = 0,

    pub fn enabled(self: AdaptiveReferenceGrid) bool {
        return self.points_per_fwhm != 0 or
            self.strong_line_min_divisions != 0 or
            self.strong_line_max_divisions != 0;
    }

    pub fn validate(self: AdaptiveReferenceGrid) errors.Error!void {
        if (!self.enabled()) return;
        if (self.points_per_fwhm == 0 or
            self.strong_line_min_divisions == 0 or
            self.strong_line_max_divisions == 0 or
            self.strong_line_max_divisions < self.strong_line_min_divisions)
        {
            return errors.Error.InvalidRequest;
        }
    }
};
// ------------------------------------------------------------------------------------------------------------|
