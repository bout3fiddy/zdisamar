//! Purpose:
//!   Store operational and adaptive reference-grid controls for instrument processing.
//!
//! Physics:
//!   Describes wavelength support grids and strong-line refinement settings used during spectroscopy preparation.
//!
//! Vendor:
//!   `reference grid controls`
//!
//! Design:
//!   The grid state is explicit and cloneable so prepare-time ownership stays clear.
//!
//! Invariants:
//!   Wavelengths are strictly increasing, weights are non-negative, and adaptive strong-line divisions are ordered.
//!
//! Validation:
//!   Tests cover weighted spacing and strong-line division validation.

const std = @import("std");
const errors = @import("../../core/errors.zig");
const Allocator = std.mem.Allocator;

/// Purpose:
///   Store an operational reference grid with wavelengths and weights.
pub const OperationalReferenceGrid = struct {
    wavelengths_nm: []const f64 = &[_]f64{},
    weights: []const f64 = &[_]f64{},

    /// Purpose:
    ///   Report whether the operational grid is active.
    pub fn enabled(self: *const OperationalReferenceGrid) bool {
        return self.wavelengths_nm.len > 0;
    }

    /// Purpose:
    ///   Validate the operational reference grid.
    ///
    /// Physics:
    ///   Ensures the wavelength list is monotonic and the weights sum to a positive value.
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

    /// Purpose:
    ///   Clone the grid into owned storage.
    pub fn clone(self: OperationalReferenceGrid, allocator: Allocator) !OperationalReferenceGrid {
        return .{
            .wavelengths_nm = try allocator.dupe(f64, self.wavelengths_nm),
            .weights = try allocator.dupe(f64, self.weights),
        };
    }

    /// Purpose:
    ///   Compute the weighted effective spacing of the reference grid.
    ///
    /// Physics:
    ///   Returns the weighted mean spacing between adjacent wavelengths.
    pub fn effectiveSpacingNm(self: *const OperationalReferenceGrid) f64 {
        if (self.wavelengths_nm.len < 2) return 1.0;

        var weighted_spacing_sum: f64 = 0.0;
        var pair_weight_sum: f64 = 0.0;
        for (self.wavelengths_nm[0 .. self.wavelengths_nm.len - 1], self.wavelengths_nm[1..], self.weights[0 .. self.weights.len - 1], self.weights[1..]) |left_nm, right_nm, left_weight, right_weight| {
            const pair_weight = 0.5 * (left_weight + right_weight);
            weighted_spacing_sum += pair_weight * (right_nm - left_nm);
            pair_weight_sum += pair_weight;
        }

        if (pair_weight_sum <= 0.0 or !std.math.isFinite(pair_weight_sum)) return 1.0;
        return weighted_spacing_sum / pair_weight_sum;
    }

    /// Purpose:
    ///   Release owned grid storage.
    pub fn deinitOwned(self: *OperationalReferenceGrid, allocator: Allocator) void {
        allocator.free(self.wavelengths_nm);
        allocator.free(self.weights);
        self.* = .{};
    }
};

/// Purpose:
///   Store adaptive reference-grid controls for strong-line refinement.
pub const AdaptiveReferenceGrid = struct {
    points_per_fwhm: u16 = 0,
    strong_line_min_divisions: u16 = 0,
    strong_line_max_divisions: u16 = 0,

    /// Purpose:
    ///   Report whether the adaptive grid settings are active.
    pub fn enabled(self: AdaptiveReferenceGrid) bool {
        return self.points_per_fwhm != 0 or
            self.strong_line_min_divisions != 0 or
            self.strong_line_max_divisions != 0;
    }

    /// Purpose:
    ///   Validate adaptive strong-line grid settings.
    ///
    /// Physics:
    ///   Enforces positive refinement settings with the maximum not smaller than the minimum.
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

test "operational reference grid reports a weighted effective spacing" {
    const grid: OperationalReferenceGrid = .{
        .wavelengths_nm = &.{ 760.8, 761.0, 761.3 },
        .weights = &.{ 0.2, 0.6, 0.2 },
    };

    try std.testing.expectApproxEqAbs(@as(f64, 0.25), grid.effectiveSpacingNm(), 1.0e-12);
}

test "adaptive reference grid validates vendor-like strong-line division ranges" {
    try (AdaptiveReferenceGrid{
        .points_per_fwhm = 5,
        .strong_line_min_divisions = 3,
        .strong_line_max_divisions = 8,
    }).validate();

    try std.testing.expectError(
        errors.Error.InvalidRequest,
        (AdaptiveReferenceGrid{
            .points_per_fwhm = 5,
            .strong_line_min_divisions = 8,
            .strong_line_max_divisions = 3,
        }).validate(),
    );
}
