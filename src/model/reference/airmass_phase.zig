const std = @import("std");
const Allocator = std.mem.Allocator;

// Helper interpolation tables used by optics preparation and transport support.
// This module does not claim full AMF or scattering-solver capability on its own.

pub const AirmassFactorPoint = struct {
    solar_zenith_deg: f64,
    view_zenith_deg: f64,
    relative_azimuth_deg: f64,
    airmass_factor: f64,
};

pub const MiePhasePoint = struct {
    wavelength_nm: f64,
    extinction_scale: f64,
    single_scatter_albedo: f64,
    phase_coefficients: [4]f64,
};

pub const MiePhaseTable = struct {
    points: []MiePhasePoint,

    pub fn deinit(self: *MiePhaseTable, allocator: Allocator) void {
        allocator.free(self.points);
        self.* = undefined;
    }

    pub fn interpolate(self: MiePhaseTable, wavelength_nm: f64) MiePhasePoint {
        if (self.points.len == 0) {
            return .{
                .wavelength_nm = wavelength_nm,
                .extinction_scale = 1.0,
                .single_scatter_albedo = 1.0,
                .phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
            };
        }
        if (wavelength_nm <= self.points[0].wavelength_nm) return self.points[0];

        for (self.points[0 .. self.points.len - 1], self.points[1..]) |left, right| {
            if (wavelength_nm <= right.wavelength_nm) {
                const span = right.wavelength_nm - left.wavelength_nm;
                if (span == 0.0) return right;
                const weight = (wavelength_nm - left.wavelength_nm) / span;

                var phase_coefficients: [4]f64 = undefined;
                for (&phase_coefficients, 0..) |*slot, index| {
                    slot.* = left.phase_coefficients[index] +
                        weight * (right.phase_coefficients[index] - left.phase_coefficients[index]);
                }
                phase_coefficients[0] = 1.0;
                return .{
                    .wavelength_nm = wavelength_nm,
                    .extinction_scale = left.extinction_scale + weight * (right.extinction_scale - left.extinction_scale),
                    .single_scatter_albedo = left.single_scatter_albedo + weight * (right.single_scatter_albedo - left.single_scatter_albedo),
                    .phase_coefficients = phase_coefficients,
                };
            }
        }
        return self.points[self.points.len - 1];
    }
};

pub const AirmassFactorLut = struct {
    points: []AirmassFactorPoint,

    pub fn deinit(self: *AirmassFactorLut, allocator: Allocator) void {
        allocator.free(self.points);
        self.* = undefined;
    }

    pub fn nearest(self: AirmassFactorLut, solar_zenith_deg: f64, view_zenith_deg: f64, relative_azimuth_deg: f64) f64 {
        if (self.points.len == 0) return 1.0;

        var best_distance = std.math.inf(f64);
        var best_value = self.points[0].airmass_factor;
        for (self.points) |point| {
            const delta_sza = point.solar_zenith_deg - solar_zenith_deg;
            const delta_vza = point.view_zenith_deg - view_zenith_deg;
            const delta_raa = point.relative_azimuth_deg - relative_azimuth_deg;
            const distance = delta_sza * delta_sza + delta_vza * delta_vza + delta_raa * delta_raa;
            if (distance < best_distance) {
                best_distance = distance;
                best_value = point.airmass_factor;
            }
        }
        return best_value;
    }

    pub fn providesSupportOnly(_: AirmassFactorLut) bool {
        return true;
    }
};
