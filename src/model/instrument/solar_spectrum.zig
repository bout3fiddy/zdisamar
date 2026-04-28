const std = @import("std");
const errors = @import("../../core/errors.zig");
const Allocator = std.mem.Allocator;

pub const OperationalSolarSpectrum = struct {
    wavelengths_nm: []const f64 = &[_]f64{},
    irradiance: []const f64 = &[_]f64{},
    spline_second_derivatives: []const f64 = &[_]f64{},
    owns_spline_state: bool = false,

    pub fn enabled(self: *const OperationalSolarSpectrum) bool {
        return self.wavelengths_nm.len > 0;
    }

    pub fn validate(self: *const OperationalSolarSpectrum) errors.Error!void {
        if (!self.enabled()) {
            if (self.irradiance.len != 0 or self.spline_second_derivatives.len != 0) {
                return errors.Error.InvalidRequest;
            }
            return;
        }
        if (self.irradiance.len != self.wavelengths_nm.len) return errors.Error.InvalidRequest;
        if (self.spline_second_derivatives.len != 0 and
            self.spline_second_derivatives.len != self.wavelengths_nm.len)
        {
            return errors.Error.InvalidRequest;
        }

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
        for (self.spline_second_derivatives) |second_derivative| {
            if (!std.math.isFinite(second_derivative)) return errors.Error.InvalidRequest;
        }
    }

    pub fn prepareInterpolation(
        self: *OperationalSolarSpectrum,
        allocator: Allocator,
    ) errors.Error!void {
        try self.validate();
        if (!self.enabled() or self.wavelengths_nm.len < 3) {
            self.clearSplineState(allocator);
            return;
        }

        const second_derivatives = try allocator.alloc(f64, self.wavelengths_nm.len);
        errdefer allocator.free(second_derivatives);
        const slopes = try allocator.alloc(f64, self.wavelengths_nm.len);
        defer allocator.free(slopes);
        const c3 = try allocator.alloc(f64, self.wavelengths_nm.len);
        defer allocator.free(c3);
        const c4 = try allocator.alloc(f64, self.wavelengths_nm.len);
        defer allocator.free(c4);

        @memset(slopes, 0.0);
        @memset(c3, 0.0);
        @memset(c4, 0.0);

        const first_span_nm = self.wavelengths_nm[1] - self.wavelengths_nm[0];
        const last_span_nm = self.wavelengths_nm[self.wavelengths_nm.len - 1] -
            self.wavelengths_nm[self.wavelengths_nm.len - 2];
        if (first_span_nm <= 0.0 or last_span_nm <= 0.0) return errors.Error.InvalidRequest;

        slopes[0] = (self.irradiance[1] - self.irradiance[0]) / first_span_nm;
        slopes[self.wavelengths_nm.len - 1] = (self.irradiance[self.irradiance.len - 1] -
            self.irradiance[self.irradiance.len - 2]) / last_span_nm;

        var index: usize = 1;
        while (index < self.wavelengths_nm.len) : (index += 1) {
            c3[index] = self.wavelengths_nm[index] - self.wavelengths_nm[index - 1];
            if (c3[index] <= 0.0) return errors.Error.InvalidRequest;
            c4[index] = (self.irradiance[index] - self.irradiance[index - 1]) / c3[index];
        }

        // PARITY:
        //   Match DISAMAR's `mathTools::spline` wrapper in the only mode used
        //   for the O2A solar source: first derivatives specified at both ends.
        c4[0] = 1.0;
        c3[0] = 0.0;

        if (self.wavelengths_nm.len > 2) {
            index = 1;
            while (index + 1 < self.wavelengths_nm.len) : (index += 1) {
                const g = -c3[index + 1] / c4[index - 1];
                slopes[index] = g * slopes[index - 1] + 3.0 * (c3[index] * c4[index + 1] + c3[index + 1] * c4[index]);
                c4[index] = g * c3[index - 1] + 2.0 * (c3[index] + c3[index + 1]);
            }
        }

        index = self.wavelengths_nm.len - 1;
        while (index > 0) : (index -= 1) {
            slopes[index - 1] = (slopes[index - 1] - c3[index - 1] * slopes[index]) / c4[index - 1];
        }

        index = 1;
        while (index < self.wavelengths_nm.len) : (index += 1) {
            const dtau_nm = c3[index];
            const first_divided_difference = (self.irradiance[index] - self.irradiance[index - 1]) / dtau_nm;
            const third_divided_difference = slopes[index - 1] + slopes[index] - (2.0 * first_divided_difference);
            c3[index - 1] = 2.0 * (first_divided_difference - slopes[index - 1] - third_divided_difference) / dtau_nm;
            c4[index - 1] = 6.0 * third_divided_difference / (dtau_nm * dtau_nm);
        }

        second_derivatives[0] = -0.5 * c3[1];
        for (1..self.wavelengths_nm.len - 1) |interior_index| {
            second_derivatives[interior_index] = c3[interior_index];
        }
        second_derivatives[self.wavelengths_nm.len - 1] = -0.5 * c3[self.wavelengths_nm.len - 2];

        self.clearSplineState(allocator);
        self.spline_second_derivatives = second_derivatives;
        self.owns_spline_state = true;
    }

    pub fn clone(self: OperationalSolarSpectrum, allocator: Allocator) !OperationalSolarSpectrum {
        var cloned: OperationalSolarSpectrum = .{};
        cloned.wavelengths_nm = try allocator.dupe(f64, self.wavelengths_nm);
        errdefer allocator.free(cloned.wavelengths_nm);
        cloned.irradiance = try allocator.dupe(f64, self.irradiance);
        errdefer allocator.free(cloned.irradiance);
        if (self.spline_second_derivatives.len != 0) {
            cloned.spline_second_derivatives = try allocator.dupe(f64, self.spline_second_derivatives);
            cloned.owns_spline_state = true;
        } else {
            try cloned.prepareInterpolation(allocator);
        }
        return cloned;
    }

    pub fn deinitOwned(self: *OperationalSolarSpectrum, allocator: Allocator) void {
        self.clearSplineState(allocator);
        allocator.free(self.wavelengths_nm);
        allocator.free(self.irradiance);
        self.* = .{};
    }

    pub fn interpolateIrradiance(self: *const OperationalSolarSpectrum, wavelength_nm: f64) f64 {
        return self.interpolateIrradianceWithinBounds(wavelength_nm) orelse {
            if (!self.enabled()) return 0.0;
            if (wavelength_nm <= self.wavelengths_nm[0]) return self.irradiance[0];
            return self.irradiance[self.irradiance.len - 1];
        };
    }

    pub fn interpolateIrradianceLinear(self: *const OperationalSolarSpectrum, wavelength_nm: f64) f64 {
        return self.interpolateIrradianceLinearWithinBounds(wavelength_nm) orelse {
            if (!self.enabled()) return 0.0;
            if (wavelength_nm <= self.wavelengths_nm[0]) return self.irradiance[0];
            return self.irradiance[self.irradiance.len - 1];
        };
    }

    pub fn coversRange(
        self: *const OperationalSolarSpectrum,
        lower_wavelength_nm: f64,
        upper_wavelength_nm: f64,
    ) bool {
        if (!self.enabled()) return false;
        return lower_wavelength_nm >= self.wavelengths_nm[0] and
            upper_wavelength_nm <= self.wavelengths_nm[self.wavelengths_nm.len - 1];
    }

    pub fn interpolateIrradianceWithinBounds(
        self: *const OperationalSolarSpectrum,
        wavelength_nm: f64,
    ) ?f64 {
        if (!self.enabled()) return null;
        if (wavelength_nm < self.wavelengths_nm[0]) return null;
        if (wavelength_nm > self.wavelengths_nm[self.wavelengths_nm.len - 1]) return null;
        if (self.splineReady()) {
            return self.interpolatePreparedSplineWithinBounds(wavelength_nm);
        }
        return self.interpolateIrradianceLinearWithinBounds(wavelength_nm);
    }

    pub fn interpolateIrradianceLinearWithinBounds(
        self: *const OperationalSolarSpectrum,
        wavelength_nm: f64,
    ) ?f64 {
        if (!self.enabled()) return null;
        if (wavelength_nm < self.wavelengths_nm[0]) return null;
        if (wavelength_nm == self.wavelengths_nm[0]) return self.irradiance[0];
        for (self.wavelengths_nm[0 .. self.wavelengths_nm.len - 1], self.wavelengths_nm[1..], self.irradiance[0 .. self.irradiance.len - 1], self.irradiance[1..]) |left_nm, right_nm, left_irradiance, right_irradiance| {
            if (wavelength_nm <= right_nm) {
                const span = right_nm - left_nm;
                if (span == 0.0) return right_irradiance;
                const weight = (wavelength_nm - left_nm) / span;
                return left_irradiance + weight * (right_irradiance - left_irradiance);
            }
        }
        if (wavelength_nm == self.wavelengths_nm[self.wavelengths_nm.len - 1]) {
            return self.irradiance[self.irradiance.len - 1];
        }
        return null;
    }

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

    fn splineReady(self: *const OperationalSolarSpectrum) bool {
        return self.spline_second_derivatives.len == self.wavelengths_nm.len and
            self.wavelengths_nm.len >= 3;
    }

    fn clearSplineState(self: *OperationalSolarSpectrum, allocator: Allocator) void {
        if (self.owns_spline_state and self.spline_second_derivatives.len != 0) {
            allocator.free(@constCast(self.spline_second_derivatives));
        }
        self.spline_second_derivatives = &[_]f64{};
        self.owns_spline_state = false;
    }

    fn interpolatePreparedSplineWithinBounds(
        self: *const OperationalSolarSpectrum,
        wavelength_nm: f64,
    ) ?f64 {
        if (wavelength_nm == self.wavelengths_nm[0]) return self.irradiance[0];
        if (wavelength_nm == self.wavelengths_nm[self.wavelengths_nm.len - 1]) {
            return self.irradiance[self.irradiance.len - 1];
        }

        var lower_index: usize = 0;
        var upper_index: usize = self.wavelengths_nm.len - 1;
        while (upper_index - lower_index > 1) {
            const middle_index = (upper_index + lower_index) / 2;
            if (self.wavelengths_nm[middle_index] > wavelength_nm) {
                upper_index = middle_index;
            } else {
                lower_index = middle_index;
            }
        }

        const span_nm = self.wavelengths_nm[upper_index] - self.wavelengths_nm[lower_index];
        if (span_nm == 0.0) return self.irradiance[upper_index];

        const dx_nm = wavelength_nm - self.wavelengths_nm[lower_index];
        // PARITY:
        //   DISAMAR `mathTools::splint` evaluates prepared spline second
        //   derivatives in Horner form. Keep the O2 A solar source on the
        //   same reduction path; the symmetric cubic only differs in the last
        //   bits, but irradiance is large enough for those bits to be visible.
        const b = (self.irradiance[upper_index] - self.irradiance[lower_index]) / span_nm -
            (2.0 * self.spline_second_derivatives[lower_index] +
                self.spline_second_derivatives[upper_index]) * span_nm / 6.0;
        const d = (self.spline_second_derivatives[upper_index] -
            self.spline_second_derivatives[lower_index]) / (6.0 * span_nm);
        return self.irradiance[lower_index] +
            dx_nm * (b + dx_nm * (self.spline_second_derivatives[lower_index] / 2.0 + dx_nm * d));
    }
};
