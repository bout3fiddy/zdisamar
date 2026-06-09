const std = @import("std");
const cholesky = @import("../../common/math/linalg/cholesky.zig");
const dense = @import("../../common/math/linalg/small_dense.zig");
const Allocator = std.mem.Allocator;

// cross_sections.zig -----------------------------------------------------------------------------------------|
// Table-backed cross-section sampling and differential baseline removal.                                      |
//                                                                                                             |
// data                                                                                                        |
//   CrossSectionPoint stores one wavelength/sigma pair. CrossSectionTable is a slice header over sorted       |
//   point storage owned by the table loader.                                                                  |
//                                                                                                             |
// hot path                                                                                                    |
//   interpolateSigma brackets one wavelength and linearly interpolates sigma. differentialVector builds a     |
//   small weighted polynomial fit and subtracts the baseline from spectral samples.                           |
//                                                                                                             |
// math                                                                                                        |
//   The differential fit uses a compact polynomial basis over wavelength normalized to roughly [-1, 1].       |
// ------------------------------------------------------------------------------------------------------------|

// CrossSectionPoint ------------------------------------------------------------------------------------------|
// One tabulated cross-section sample.                                                                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] wavelength_nm          : f64                                                                        |
// [8..15] sigma_cm2_per_molecule : f64                                                                        |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total = per instance * live point count                         |
pub const CrossSectionPoint = struct {
    wavelength_nm: f64,
    sigma_cm2_per_molecule: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// WavelengthBracket ------------------------------------------------------------------------------------------|
// Present optional payload returned by bracketForWavelength.                                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] left_index  : usize                                                                                 |
// [8..15] right_index : usize                                                                                 |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per present payload = 16 B (0.016 KiB)                                                           |
const WavelengthBracket = struct {
    left_index: usize,
    right_index: usize,
};
// ------------------------------------------------------------------------------------------------------------|

// CrossSectionTable ------------------------------------------------------------------------------------------|
// Owner/view header for sorted cross-section samples.                                                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0..15] points : []const CrossSectionPoint                                                                  |
//                                                                                                             |
// referenced storage                                                                                          |
//   points stores out-of-line CrossSectionPoint rows and is released by deinit.                               |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total also includes owned point rows                            |
pub const CrossSectionTable = struct {
    points: []const CrossSectionPoint,

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
        // CrossSectionTable.interpolateSigma -----------------------------------------------------------------|
        // Sample sigma at one wavelength from sorted table rows.                                              |
        //                                                                                                     |
        // hot path                                                                                            |
        //   repeated : carrier evaluation samples table-backed cross sections at each wavelength              |
        //   work     : bracket wavelength and linearly interpolate sigma                                      |
        //   memory   : binary search reads point wavelengths, final interpolation reads two compact rows      |
        // ----------------------------------------------------------------------------------------------------|

        if (self.points.len == 0) return 0.0;
        if (wavelength_nm <= self.points[0].wavelength_nm) return self.points[0].sigma_cm2_per_molecule;
        if (wavelength_nm >= self.points[self.points.len - 1].wavelength_nm) {
            return self.points[self.points.len - 1].sigma_cm2_per_molecule;
        }

        const bracket = self.bracketForWavelength(wavelength_nm) orelse
            return self.points[self.points.len - 1].sigma_cm2_per_molecule;
        const left = self.points[bracket.left_index];
        const right = self.points[bracket.right_index];
        const span = right.wavelength_nm - left.wavelength_nm;
        if (span == 0.0) return right.sigma_cm2_per_molecule;
        const weight = (wavelength_nm - left.wavelength_nm) / span;
        return left.sigma_cm2_per_molecule + weight * (right.sigma_cm2_per_molecule - left.sigma_cm2_per_molecule);
    }

    pub fn bracketForWavelength(
        self: CrossSectionTable,
        wavelength_nm: f64,
    ) ?WavelengthBracket {
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
// ------------------------------------------------------------------------------------------------------------|

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
    // differentialVector -------------------------------------------------------------------------------------|
    // Remove a weighted polynomial baseline from one spectral vector.                                         |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : effective cross-section or CIA output builds a differential spectrum                       |
    //   work     : assemble dense normal equations, Cholesky solve coefficients, subtract fitted baseline     |
    //   memory   : normal matrix is term_count^2 f64 values; coeff and rhs arrays are term_count f64 values   |
    //                                                                                                         |
    // math                                                                                                    |
    //   x = (wavelength_nm - midpoint_nm) / half_span_nm                                                      |
    //   baseline = sum coefficient[k] * x^k                                                                   |
    // --------------------------------------------------------------------------------------------------------|

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

    // Normalize wavelength into a compact polynomial basis before assembling the dense fit system.
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
