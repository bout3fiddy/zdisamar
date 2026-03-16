const std = @import("std");
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

        for (self.points[0 .. self.points.len - 1], self.points[1..]) |left, right| {
            if (wavelength_nm <= right.wavelength_nm) {
                const span = right.wavelength_nm - left.wavelength_nm;
                if (span == 0.0) return right.sigma_cm2_per_molecule;
                const weight = (wavelength_nm - left.wavelength_nm) / span;
                return left.sigma_cm2_per_molecule + weight * (right.sigma_cm2_per_molecule - left.sigma_cm2_per_molecule);
            }
        }
        return self.points[self.points.len - 1].sigma_cm2_per_molecule;
    }
};
