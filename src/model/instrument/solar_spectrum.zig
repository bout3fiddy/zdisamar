const std = @import("std");
const errors = @import("../../core/errors.zig");
const Allocator = std.mem.Allocator;

pub const OperationalSolarSpectrum = struct {
    wavelengths_nm: []const f64 = &[_]f64{},
    irradiance: []const f64 = &[_]f64{},

    pub fn enabled(self: OperationalSolarSpectrum) bool {
        return self.wavelengths_nm.len > 0;
    }

    pub fn validate(self: OperationalSolarSpectrum) errors.Error!void {
        if (!self.enabled()) {
            if (self.irradiance.len != 0) return errors.Error.InvalidRequest;
            return;
        }
        if (self.irradiance.len != self.wavelengths_nm.len) return errors.Error.InvalidRequest;

        var previous_wavelength: ?f64 = null;
        for (self.wavelengths_nm, self.irradiance) |wavelength_nm, irradiance| {
            if (!std.math.isFinite(wavelength_nm) or !std.math.isFinite(irradiance) or irradiance < 0.0) {
                return errors.Error.InvalidRequest;
            }
            if (previous_wavelength) |previous| {
                if (wavelength_nm <= previous) return errors.Error.InvalidRequest;
            }
            previous_wavelength = wavelength_nm;
        }
    }

    pub fn clone(self: OperationalSolarSpectrum, allocator: Allocator) !OperationalSolarSpectrum {
        return .{
            .wavelengths_nm = try allocator.dupe(f64, self.wavelengths_nm),
            .irradiance = try allocator.dupe(f64, self.irradiance),
        };
    }

    pub fn deinitOwned(self: *OperationalSolarSpectrum, allocator: Allocator) void {
        allocator.free(self.wavelengths_nm);
        allocator.free(self.irradiance);
        self.* = .{};
    }

    pub fn interpolateIrradiance(self: OperationalSolarSpectrum, wavelength_nm: f64) f64 {
        if (!self.enabled()) return 0.0;
        if (wavelength_nm <= self.wavelengths_nm[0]) return self.irradiance[0];
        for (self.wavelengths_nm[0 .. self.wavelengths_nm.len - 1], self.wavelengths_nm[1..], self.irradiance[0 .. self.irradiance.len - 1], self.irradiance[1..]) |left_nm, right_nm, left_irradiance, right_irradiance| {
            if (wavelength_nm <= right_nm) {
                const span = right_nm - left_nm;
                if (span == 0.0) return right_irradiance;
                const weight = (wavelength_nm - left_nm) / span;
                return left_irradiance + weight * (right_irradiance - left_irradiance);
            }
        }
        return self.irradiance[self.irradiance.len - 1];
    }
};
