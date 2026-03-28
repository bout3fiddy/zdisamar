//! Purpose:
//!   Store operational solar spectrum controls and interpolation helpers.
//!
//! Physics:
//!   Represents wavelength-aligned irradiance samples and supports interpolation onto target grids.
//!
//! Vendor:
//!   `solar spectrum controls`
//!
//! Design:
//!   The spectrum stays as explicit owned slices so callers can clone, correct, and free it deterministically.
//!
//! Invariants:
//!   Wavelengths are strictly increasing, irradiance is non-negative, and empty spectra disable the helper.
//!
//! Validation:
//!   Tests cover interpolation and measured-spectrum correction.

const std = @import("std");
const errors = @import("../../core/errors.zig");
const Allocator = std.mem.Allocator;

/// Purpose:
///   Store an operational solar spectrum with wavelengths and irradiance.
pub const OperationalSolarSpectrum = struct {
    wavelengths_nm: []const f64 = &[_]f64{},
    irradiance: []const f64 = &[_]f64{},

    /// Purpose:
    ///   Report whether the solar spectrum is active.
    pub fn enabled(self: *const OperationalSolarSpectrum) bool {
        return self.wavelengths_nm.len > 0;
    }

    /// Purpose:
    ///   Validate the solar spectrum.
    ///
    /// Physics:
    ///   Requires monotonic wavelengths and non-negative irradiance samples.
    pub fn validate(self: *const OperationalSolarSpectrum) errors.Error!void {
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

    /// Purpose:
    ///   Clone the spectrum into owned storage.
    pub fn clone(self: OperationalSolarSpectrum, allocator: Allocator) !OperationalSolarSpectrum {
        var cloned: OperationalSolarSpectrum = .{};
        cloned.wavelengths_nm = try allocator.dupe(f64, self.wavelengths_nm);
        errdefer allocator.free(cloned.wavelengths_nm);
        cloned.irradiance = try allocator.dupe(f64, self.irradiance);
        return cloned;
    }

    /// Purpose:
    ///   Release owned spectrum storage.
    pub fn deinitOwned(self: *OperationalSolarSpectrum, allocator: Allocator) void {
        allocator.free(self.wavelengths_nm);
        allocator.free(self.irradiance);
        self.* = .{};
    }

    /// Purpose:
    ///   Interpolate irradiance at a wavelength.
    ///
    /// Physics:
    ///   Uses linear interpolation between adjacent monotonic samples.
    pub fn interpolateIrradiance(self: *const OperationalSolarSpectrum, wavelength_nm: f64) f64 {
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

    /// Purpose:
    ///   Interpolate the solar spectrum onto a target wavelength grid.
    pub fn interpolateOnto(
        self: *const OperationalSolarSpectrum,
        allocator: Allocator,
        wavelengths_nm: []const f64,
    ) ![]f64 {
        const irradiance = try allocator.alloc(f64, wavelengths_nm.len);
        errdefer allocator.free(irradiance);

        for (wavelengths_nm, irradiance) |wavelength_nm, *slot| {
            slot.* = self.interpolateIrradiance(wavelength_nm);
        }
        return irradiance;
    }

    /// Purpose:
    ///   Correct measured values onto a target grid using the solar spectrum ratio.
    ///
    /// Physics:
    ///   Scales measured radiance by target-to-source solar irradiance.
    pub fn correctMeasuredSpectrumOnto(
        self: *const OperationalSolarSpectrum,
        allocator: Allocator,
        source_wavelengths_nm: []const f64,
        measured_values: []const f64,
        target_wavelengths_nm: []const f64,
    ) ![]f64 {
        if (source_wavelengths_nm.len != measured_values.len or measured_values.len != target_wavelengths_nm.len) {
            return errors.Error.InvalidRequest;
        }

        const corrected = try allocator.alloc(f64, target_wavelengths_nm.len);
        errdefer allocator.free(corrected);
        const source_solar = try self.interpolateOnto(allocator, source_wavelengths_nm);
        defer allocator.free(source_solar);
        const target_solar = try self.interpolateOnto(allocator, target_wavelengths_nm);
        defer allocator.free(target_solar);

        for (measured_values, source_solar, target_solar, corrected) |measured_value, source_irradiance, target_irradiance, *slot| {
            if (!std.math.isFinite(measured_value)) return errors.Error.InvalidRequest;
            slot.* = measured_value * target_irradiance / @max(source_irradiance, 1.0e-12);
        }
        return corrected;
    }
};

test "operational solar spectrum interpolates onto measured wavelengths" {
    const spectrum: OperationalSolarSpectrum = .{
        .wavelengths_nm = &.{ 760.8, 761.0, 761.2 },
        .irradiance = &.{ 2.7e14, 2.8e14, 2.9e14 },
    };

    const aligned = try spectrum.interpolateOnto(std.testing.allocator, &.{ 760.8, 760.9, 761.15 });
    defer std.testing.allocator.free(aligned);

    try std.testing.expectApproxEqAbs(@as(f64, 2.7e14), aligned[0], 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 2.75e14), aligned[1], 1.0e10);
    try std.testing.expectApproxEqAbs(@as(f64, 2.875e14), aligned[2], 1.0e10);
}

test "operational solar spectrum corrects measured irradiance onto a shifted radiance grid" {
    const source_solar: OperationalSolarSpectrum = .{
        .wavelengths_nm = &.{ 760.8, 761.0, 761.2, 761.4 },
        .irradiance = &.{ 3.00e14, 2.90e14, 2.80e14, 2.70e14 },
    };

    const corrected = try source_solar.correctMeasuredSpectrumOnto(
        std.testing.allocator,
        &.{ 760.8, 761.0, 761.2 },
        &.{ 2.70e14, 2.68e14, 2.66e14 },
        &.{ 760.81, 761.01, 761.21 },
    );
    defer std.testing.allocator.free(corrected);

    try std.testing.expect(corrected[0] < 2.70e14);
    try std.testing.expect(corrected[1] < 2.68e14);
    try std.testing.expect(corrected[2] < 2.66e14);
}
