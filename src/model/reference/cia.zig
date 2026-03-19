const std = @import("std");
const cross_sections = @import("cross_sections.zig");
const Allocator = std.mem.Allocator;

pub const CollisionInducedAbsorptionPoint = struct {
    wavelength_nm: f64,
    a0: f64,
    a1: f64,
    a2: f64,
};

pub const CollisionInducedAbsorptionTable = struct {
    scale_factor_cm5_per_molecule2: f64,
    points: []const CollisionInducedAbsorptionPoint,

    pub fn deinit(self: *CollisionInducedAbsorptionTable, allocator: Allocator) void {
        allocator.free(self.points);
        self.* = undefined;
    }

    pub fn clone(self: CollisionInducedAbsorptionTable, allocator: Allocator) !CollisionInducedAbsorptionTable {
        return .{
            .scale_factor_cm5_per_molecule2 = self.scale_factor_cm5_per_molecule2,
            .points = try allocator.dupe(CollisionInducedAbsorptionPoint, self.points),
        };
    }

    pub fn sigmaAt(self: CollisionInducedAbsorptionTable, wavelength_nm: f64, temperature_k: f64) f64 {
        const coefficients = self.interpolateCoefficients(wavelength_nm);
        const temperature_c = temperature_k - 273.15;
        const raw_sigma = coefficients.a0 +
            coefficients.a1 * temperature_c +
            coefficients.a2 * temperature_c * temperature_c;
        return self.scale_factor_cm5_per_molecule2 * @max(raw_sigma, 0.0);
    }

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
        const left = self.points[right_index - 1];
        const right = self.points[right_index];
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
};

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
