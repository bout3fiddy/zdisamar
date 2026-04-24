//! Purpose:
//!   Store and evaluate collision-induced absorption tables.
//!
//! Physics:
//!   Interpolates wavelength-dependent coefficients and evaluates temperature-dependent absorption cross sections.
//!
//! Vendor:
//!   `collision-induced absorption`
//!
//! Design:
//!   The coefficients are kept explicit so the temperature polynomial and wavelength interpolation remain visible.
//!
//! Invariants:
//!   Wavelength tables are monotonic, temperature values are finite, and the scale factor is in cm^5 / molecule^2.
//!
//! Validation:
//!   Tests cover projection of sigma onto the differential-fit space.

const std = @import("std");
const cross_sections = @import("cross_sections.zig");
const spline = @import("../../kernels/interpolation/spline.zig");
const Allocator = std.mem.Allocator;

const max_spline_window_points: usize = 256;

pub const CollisionInducedAbsorptionPoint = struct {
    wavelength_nm: f64,
    a0: f64,
    a1: f64,
    a2: f64,
};

/// Purpose:
///   Own a collision-induced absorption table.
pub const CollisionInducedAbsorptionTable = struct {
    scale_factor_cm5_per_molecule2: f64,
    points: []const CollisionInducedAbsorptionPoint,

    /// Purpose:
    ///   Release the owned CIA points.
    pub fn deinit(self: *CollisionInducedAbsorptionTable, allocator: Allocator) void {
        allocator.free(self.points);
        self.* = undefined;
    }

    /// Purpose:
    ///   Clone the table into new owned storage.
    pub fn clone(self: CollisionInducedAbsorptionTable, allocator: Allocator) !CollisionInducedAbsorptionTable {
        return .{
            .scale_factor_cm5_per_molecule2 = self.scale_factor_cm5_per_molecule2,
            .points = try allocator.dupe(CollisionInducedAbsorptionPoint, self.points),
        };
    }

    /// Purpose:
    ///   Evaluate the CIA cross section at a wavelength and temperature.
    ///
    /// Physics:
    ///   Uses a quadratic temperature polynomial in degrees Celsius and clamps negative absorption to zero.
    ///
    /// Units:
    ///   `scale_factor_cm5_per_molecule2` is a scale factor in cm^5 / molecule^2.
    pub fn sigmaAt(self: CollisionInducedAbsorptionTable, wavelength_nm: f64, temperature_k: f64) f64 {
        const coefficients = self.interpolateCoefficients(wavelength_nm);
        const temperature_c = temperature_k - 273.15;
        const raw_sigma = coefficients.a0 +
            coefficients.a1 * temperature_c +
            coefficients.a2 * temperature_c * temperature_c;
        return self.scale_factor_cm5_per_molecule2 * @max(raw_sigma, 0.0);
    }

    /// Purpose:
    ///   Evaluate the temperature derivative of the CIA cross section.
    pub fn dSigmaDTemperatureAt(self: CollisionInducedAbsorptionTable, wavelength_nm: f64, temperature_k: f64) f64 {
        const coefficients = self.interpolateCoefficients(wavelength_nm);
        const temperature_c = temperature_k - 273.15;
        const raw_sigma = coefficients.a0 +
            coefficients.a1 * temperature_c +
            coefficients.a2 * temperature_c * temperature_c;
        if (raw_sigma <= 0.0) return 0.0;
        return self.scale_factor_cm5_per_molecule2 *
            (coefficients.a1 + 2.0 * coefficients.a2 * temperature_c);
    }

    /// Purpose:
    ///   Compute a mean CIA cross section across a wavelength window.
    pub fn meanSigmaInRange(
        self: CollisionInducedAbsorptionTable,
        start_nm: f64,
        end_nm: f64,
        temperature_k: f64,
    ) f64 {
        var total: f64 = 0.0;
        var count: usize = 0;
        for (self.points) |point| {
            if (point.wavelength_nm < start_nm or point.wavelength_nm > end_nm) continue;
            total += self.sigmaAt(point.wavelength_nm, temperature_k);
            count += 1;
        }

        if (count > 0) return total / @as(f64, @floatFromInt(count));
        return self.sigmaAt((start_nm + end_nm) * 0.5, temperature_k);
    }

    /// Purpose:
    ///   Interpolate CIA coefficients at a wavelength.
    fn interpolateCoefficients(self: CollisionInducedAbsorptionTable, wavelength_nm: f64) CollisionInducedAbsorptionPoint {
        if (self.points.len == 0) {
            return .{
                .wavelength_nm = wavelength_nm,
                .a0 = 0.0,
                .a1 = 0.0,
                .a2 = 0.0,
            };
        }
        if (wavelength_nm <= self.points[0].wavelength_nm) return self.points[0];
        if (wavelength_nm >= self.points[self.points.len - 1].wavelength_nm) return self.points[self.points.len - 1];

        const right_index = lowerBoundPointIndex(self.points, wavelength_nm);
        const window = splineWindow(self.points.len, right_index);
        if (window.count >= 3) {
            const points = self.points[window.start .. window.start + window.count];
            return .{
                .wavelength_nm = wavelength_nm,
                .a0 = sampleCoefficientSpline(points, wavelength_nm, .a0),
                .a1 = sampleCoefficientSpline(points, wavelength_nm, .a1),
                .a2 = sampleCoefficientSpline(points, wavelength_nm, .a2),
            };
        }
        return interpolateCoefficientsLinear(self.points[right_index - 1], self.points[right_index], wavelength_nm);
    }
};

const CoefficientKind = enum { a0, a1, a2 };

const SplineWindow = struct {
    start: usize,
    count: usize,
};

fn splineWindow(point_count: usize, right_index: usize) SplineWindow {
    const count = @min(point_count, max_spline_window_points);
    if (point_count <= max_spline_window_points) return .{ .start = 0, .count = count };

    const half_window = max_spline_window_points / 2;
    var start: usize = if (right_index > half_window) right_index - half_window else 0;
    if (start + count > point_count) start = point_count - count;
    return .{ .start = start, .count = count };
}

fn sampleCoefficientSpline(
    points: []const CollisionInducedAbsorptionPoint,
    wavelength_nm: f64,
    coefficient_kind: CoefficientKind,
) f64 {
    var x: [max_spline_window_points]f64 = undefined;
    var y: [max_spline_window_points]f64 = undefined;
    for (points, 0..) |point, index| {
        x[index] = point.wavelength_nm;
        y[index] = switch (coefficient_kind) {
            .a0 => point.a0,
            .a1 => point.a1,
            .a2 => point.a2,
        };
    }
    return spline.sampleEndpointSecant(x[0..points.len], y[0..points.len], wavelength_nm) catch unreachable;
}

fn interpolateCoefficientsLinear(
    left: CollisionInducedAbsorptionPoint,
    right: CollisionInducedAbsorptionPoint,
    wavelength_nm: f64,
) CollisionInducedAbsorptionPoint {
    const span = right.wavelength_nm - left.wavelength_nm;
    if (span == 0.0) return right;
    const weight = (wavelength_nm - left.wavelength_nm) / span;
    return .{
        .wavelength_nm = wavelength_nm,
        .a0 = left.a0 + weight * (right.a0 - left.a0),
        .a1 = left.a1 + weight * (right.a1 - left.a1),
        .a2 = left.a2 + weight * (right.a2 - left.a2),
    };
}

/// Purpose:
///   Find the first CIA sample whose wavelength is not less than the target.
fn lowerBoundPointIndex(points: []const CollisionInducedAbsorptionPoint, wavelength_nm: f64) usize {
    var low: usize = 0;
    var high: usize = points.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (points[middle].wavelength_nm < wavelength_nm) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    return low;
}

/// Purpose:
///   Project CIA sigma samples into the same differential-fit space as cross sections.
///
/// Physics:
///   Evaluates CIA at the given wavelengths and removes the weighted polynomial baseline.
pub fn effectiveSigmaAtSamples(
    allocator: Allocator,
    table: CollisionInducedAbsorptionTable,
    wavelengths_nm: []const f64,
    temperature_k: f64,
    weights: []const f64,
    polynomial_order: u32,
) ![]f64 {
    if (wavelengths_nm.len != weights.len) return error.ShapeMismatch;

    const sigma = try allocator.alloc(f64, wavelengths_nm.len);
    defer allocator.free(sigma);
    for (sigma, wavelengths_nm) |*slot, wavelength_nm| {
        slot.* = table.sigmaAt(wavelength_nm, temperature_k);
    }
    return cross_sections.differentialVector(allocator, wavelengths_nm, sigma, weights, polynomial_order);
}

test "cia helpers project sigma onto the same differential fit space" {
    const table: CollisionInducedAbsorptionTable = .{
        .scale_factor_cm5_per_molecule2 = 1.0,
        .points = &[_]CollisionInducedAbsorptionPoint{
            .{ .wavelength_nm = 759.0, .a0 = 1.0, .a1 = 0.0, .a2 = 0.0 },
            .{ .wavelength_nm = 762.0, .a0 = 2.0, .a1 = 0.0, .a2 = 0.0 },
        },
    };
    const wavelengths = [_]f64{ 759.0, 760.0, 761.0, 762.0 };
    const weights = [_]f64{ 1.0, 1.0, 1.0, 1.0 };
    const sigma = try effectiveSigmaAtSamples(std.testing.allocator, table, &wavelengths, 273.15, &weights, 1);
    defer std.testing.allocator.free(sigma);

    try std.testing.expectApproxEqAbs(@as(f64, 0.0), cross_sections.weightedMeanSamples(sigma, &weights), 1.0e-9);
}

test "cia coefficient interpolation follows vendor endpoint-secant spline" {
    const points = [_]CollisionInducedAbsorptionPoint{
        .{ .wavelength_nm = 760.0, .a0 = 4.90, .a1 = 0.10, .a2 = 0.01 },
        .{ .wavelength_nm = 760.5, .a0 = 4.90, .a1 = 0.12, .a2 = 0.02 },
        .{ .wavelength_nm = 761.0, .a0 = 4.91, .a1 = 0.14, .a2 = 0.03 },
        .{ .wavelength_nm = 761.5, .a0 = 4.91, .a1 = 0.16, .a2 = 0.04 },
        .{ .wavelength_nm = 762.0, .a0 = 4.93, .a1 = 0.18, .a2 = 0.05 },
    };
    const table: CollisionInducedAbsorptionTable = .{
        .scale_factor_cm5_per_molecule2 = 1.0,
        .points = &points,
    };

    const target_nm = 761.25;
    const coefficients = table.interpolateCoefficients(target_nm);
    const wavelengths = [_]f64{ 760.0, 760.5, 761.0, 761.5, 762.0 };
    const a0 = [_]f64{ 4.90, 4.90, 4.91, 4.91, 4.93 };
    const expected_a0 = try spline.sampleEndpointSecant(&wavelengths, &a0, target_nm);

    try std.testing.expectApproxEqAbs(expected_a0, coefficients.a0, 1.0e-15);
}
