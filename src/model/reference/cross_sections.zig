const std = @import("std");
const cholesky = @import("../../kernels/linalg/cholesky.zig");
const dense = @import("../../kernels/linalg/small_dense.zig");
const Allocator = std.mem.Allocator;

pub const CrossSectionPoint = struct {
    wavelength_nm: f64,
    sigma_cm2_per_molecule: f64,
};

pub const CrossSectionTable = struct {
    points: []CrossSectionPoint,

    pub fn deinit(self: *CrossSectionTable, allocator: Allocator) void {
        allocator.free(self.points);
        self.* = undefined;
    }

    pub fn meanSigmaInRange(self: CrossSectionTable, start_nm: f64, end_nm: f64) f64 {
        var total: f64 = 0.0;
        var count: usize = 0;
        for (self.points) |point| {
            if (point.wavelength_nm < start_nm or point.wavelength_nm > end_nm) continue;
            total += point.sigma_cm2_per_molecule;
            count += 1;
        }

        if (count > 0) return total / @as(f64, @floatFromInt(count));
        return self.interpolateSigma((start_nm + end_nm) * 0.5);
    }

    pub fn interpolateSigma(self: CrossSectionTable, wavelength_nm: f64) f64 {
        if (self.points.len == 0) return 0.0;
        if (wavelength_nm <= self.points[0].wavelength_nm) return self.points[0].sigma_cm2_per_molecule;
        if (wavelength_nm >= self.points[self.points.len - 1].wavelength_nm) return self.points[self.points.len - 1].sigma_cm2_per_molecule;

        const bracket = self.bracketForWavelength(wavelength_nm) orelse return self.points[self.points.len - 1].sigma_cm2_per_molecule;
        const left = self.points[bracket.left_index];
        const right = self.points[bracket.right_index];
        const span = right.wavelength_nm - left.wavelength_nm;
        if (span == 0.0) return right.sigma_cm2_per_molecule;
        const weight = (wavelength_nm - left.wavelength_nm) / span;
        return left.sigma_cm2_per_molecule + weight * (right.sigma_cm2_per_molecule - left.sigma_cm2_per_molecule);
    }

    pub fn sigmaAtHighResolution(self: CrossSectionTable, wavelength_nm: f64) f64 {
        return self.interpolateSigma(wavelength_nm);
    }

    pub fn bracketForWavelength(
        self: CrossSectionTable,
        wavelength_nm: f64,
    ) ?struct { left_index: usize, right_index: usize } {
        if (self.points.len < 2) return null;

        var low: usize = 0;
        var high: usize = self.points.len - 1;
        while (low + 1 < high) {
            const middle = low + (high - low) / 2;
            if (self.points[middle].wavelength_nm <= wavelength_nm) {
                low = middle;
            } else {
                high = middle;
            }
        }
        return .{
            .left_index = low,
            .right_index = high,
        };
    }
};

pub fn weightedMeanSamples(samples: []const f64, weights: []const f64) f64 {
    if (samples.len == 0 or samples.len != weights.len) return 0.0;

    var numerator: f64 = 0.0;
    var denominator: f64 = 0.0;
    for (samples, weights) |sample, weight| {
        numerator += sample * weight;
        denominator += weight;
    }
    return numerator / @max(denominator, 1.0e-12);
}

pub fn differentialVector(
    allocator: Allocator,
    wavelengths_nm: []const f64,
    values: []const f64,
    weights: []const f64,
    polynomial_order: u32,
) ![]f64 {
    if (wavelengths_nm.len != values.len or values.len != weights.len) return error.ShapeMismatch;
    if (polynomial_order > 7) return error.InvalidPolynomialOrder;

    const result = try allocator.dupe(f64, values);
    errdefer allocator.free(result);
    if (values.len == 0 or polynomial_order == 0) {
        const mean = weightedMeanSamples(values, weights);
        for (result) |*value| value.* -= mean;
        return result;
    }

    const term_count: usize = @intCast(polynomial_order + 1);
    const normal = try allocator.alloc(f64, term_count * term_count);
    defer allocator.free(normal);
    @memset(normal, 0.0);
    const rhs = try allocator.alloc(f64, term_count);
    defer allocator.free(rhs);
    @memset(rhs, 0.0);
    const coeffs = try allocator.alloc(f64, term_count);
    defer allocator.free(coeffs);

    const midpoint_nm = 0.5 * (wavelengths_nm[0] + wavelengths_nm[wavelengths_nm.len - 1]);
    const half_span_nm = @max(0.5 * (wavelengths_nm[wavelengths_nm.len - 1] - wavelengths_nm[0]), 1.0e-9);
    // VENDOR:
    //   Normalize wavelength into a compact polynomial basis before assembling the dense fit system.
    for (wavelengths_nm, values, weights) |wavelength_nm, value, weight| {
        const x = (wavelength_nm - midpoint_nm) / half_span_nm;
        var powers: [8]f64 = undefined;
        powers[0] = 1.0;
        var power_index: usize = 1;
        while (power_index < term_count) : (power_index += 1) {
            powers[power_index] = powers[power_index - 1] * x;
        }

        for (0..term_count) |row| {
            rhs[row] += weight * powers[row] * value;
            for (0..term_count) |column| {
                normal[dense.index(row, column, term_count)] += weight * powers[row] * powers[column];
            }
        }
    }

    const factor = try allocator.dupe(f64, normal);
    defer allocator.free(factor);
    if (cholesky.factorInPlace(factor, term_count)) |_| {
        cholesky.solveWithFactor(factor, term_count, rhs, coeffs) catch return error.SingularSystem;
    } else |_| {
        return error.SingularSystem;
    }

    for (wavelengths_nm, 0..) |wavelength_nm, index| {
        const x = (wavelength_nm - midpoint_nm) / half_span_nm;
        var baseline: f64 = 0.0;
        var x_power: f64 = 1.0;
        for (coeffs) |coefficient| {
            baseline += coefficient * x_power;
            x_power *= x;
        }
        result[index] -= baseline;
    }
    return result;
}

pub fn effectiveCrossSectionFromSensitivity(
    allocator: Allocator,
    wavelengths_nm: []const f64,
    sensitivity: []const f64,
    air_mass_factors: []const f64,
    polynomial_order: u32,
) ![]f64 {
    if (wavelengths_nm.len != sensitivity.len or sensitivity.len != air_mass_factors.len) {
        return error.ShapeMismatch;
    }

    const normalized = try allocator.alloc(f64, sensitivity.len);
    defer allocator.free(normalized);
    const weights = try allocator.alloc(f64, sensitivity.len);
    defer allocator.free(weights);
    for (normalized, weights, sensitivity, air_mass_factors) |*slot, *weight_slot, sample, amf| {
        const safe_amf = @max(@abs(amf), 1.0e-9);
        slot.* = sample / safe_amf;
        weight_slot.* = safe_amf;
    }
    return differentialVector(allocator, wavelengths_nm, normalized, weights, polynomial_order);
}

test "cross-section helpers remove weighted polynomial baselines" {
    const wavelengths = [_]f64{ 759.0, 760.0, 761.0, 762.0 };
    const values = [_]f64{ 1.0, 1.4, 1.8, 2.2 };
    const weights = [_]f64{ 1.0, 1.0, 1.0, 1.0 };
    const differential = try differentialVector(std.testing.allocator, &wavelengths, &values, &weights, 1);
    defer std.testing.allocator.free(differential);

    try std.testing.expectApproxEqAbs(@as(f64, 0.0), weightedMeanSamples(differential, &weights), 1.0e-9);
}
