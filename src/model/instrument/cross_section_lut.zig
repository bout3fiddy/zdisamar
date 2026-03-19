const std = @import("std");
const errors = @import("../../core/errors.zig");
const constants = @import("constants.zig");
const max_operational_refspec_temperature_coefficients = constants.max_operational_refspec_temperature_coefficients;
const max_operational_refspec_pressure_coefficients = constants.max_operational_refspec_pressure_coefficients;
const Allocator = std.mem.Allocator;

pub const OperationalCrossSectionLut = struct {
    wavelengths_nm: []const f64 = &[_]f64{},
    coefficients: []const f64 = &[_]f64{},
    temperature_coefficient_count: u8 = 0,
    pressure_coefficient_count: u8 = 0,
    min_temperature_k: f64 = 0.0,
    max_temperature_k: f64 = 0.0,
    min_pressure_hpa: f64 = 0.0,
    max_pressure_hpa: f64 = 0.0,

    pub fn enabled(self: *const OperationalCrossSectionLut) bool {
        return self.wavelengths_nm.len > 0;
    }

    pub fn validate(self: *const OperationalCrossSectionLut) errors.Error!void {
        if (!self.enabled()) {
            if (self.coefficients.len != 0 or
                self.temperature_coefficient_count != 0 or
                self.pressure_coefficient_count != 0)
            {
                return errors.Error.InvalidRequest;
            }
            return;
        }

        if (self.temperature_coefficient_count == 0 or
            self.temperature_coefficient_count > max_operational_refspec_temperature_coefficients or
            self.pressure_coefficient_count == 0 or
            self.pressure_coefficient_count > max_operational_refspec_pressure_coefficients)
        {
            return errors.Error.InvalidRequest;
        }

        if (!std.math.isFinite(self.min_temperature_k) or
            !std.math.isFinite(self.max_temperature_k) or
            !std.math.isFinite(self.min_pressure_hpa) or
            !std.math.isFinite(self.max_pressure_hpa) or
            self.min_temperature_k <= 0.0 or
            self.max_temperature_k <= self.min_temperature_k or
            self.min_pressure_hpa <= 0.0 or
            self.max_pressure_hpa <= self.min_pressure_hpa)
        {
            return errors.Error.InvalidRequest;
        }

        var previous_wavelength: ?f64 = null;
        for (self.wavelengths_nm) |wavelength_nm| {
            if (!std.math.isFinite(wavelength_nm)) return errors.Error.InvalidRequest;
            if (previous_wavelength) |previous| {
                if (wavelength_nm <= previous) return errors.Error.InvalidRequest;
            }
            previous_wavelength = wavelength_nm;
        }

        const expected_coefficient_count =
            self.wavelengths_nm.len *
            @as(usize, self.temperature_coefficient_count) *
            @as(usize, self.pressure_coefficient_count);
        if (self.coefficients.len != expected_coefficient_count) {
            return errors.Error.InvalidRequest;
        }

        for (self.coefficients) |coefficient| {
            if (!std.math.isFinite(coefficient)) return errors.Error.InvalidRequest;
        }
    }

    pub fn clone(self: OperationalCrossSectionLut, allocator: Allocator) !OperationalCrossSectionLut {
        return .{
            .wavelengths_nm = try allocator.dupe(f64, self.wavelengths_nm),
            .coefficients = try allocator.dupe(f64, self.coefficients),
            .temperature_coefficient_count = self.temperature_coefficient_count,
            .pressure_coefficient_count = self.pressure_coefficient_count,
            .min_temperature_k = self.min_temperature_k,
            .max_temperature_k = self.max_temperature_k,
            .min_pressure_hpa = self.min_pressure_hpa,
            .max_pressure_hpa = self.max_pressure_hpa,
        };
    }

    pub fn deinitOwned(self: *OperationalCrossSectionLut, allocator: Allocator) void {
        allocator.free(self.wavelengths_nm);
        allocator.free(self.coefficients);
        self.* = .{};
    }

    pub fn sigmaAt(
        self: *const OperationalCrossSectionLut,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) f64 {
        return self.evaluate(wavelength_nm, temperature_k, pressure_hpa).sigma;
    }

    pub fn dSigmaDTemperatureAt(
        self: *const OperationalCrossSectionLut,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) f64 {
        return self.evaluate(wavelength_nm, temperature_k, pressure_hpa).d_sigma_d_temperature;
    }

    fn evaluate(
        self: *const OperationalCrossSectionLut,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) struct { sigma: f64, d_sigma_d_temperature: f64 } {
        if (!self.enabled()) {
            return .{
                .sigma = 0.0,
                .d_sigma_d_temperature = 0.0,
            };
        }

        var legendre_lnT = [_]f64{0.0} ** max_operational_refspec_temperature_coefficients;
        var legendre_lnp = [_]f64{0.0} ** max_operational_refspec_pressure_coefficients;
        var derivative_legendre_lnT = [_]f64{0.0} ** max_operational_refspec_temperature_coefficients;

        const scaled_lnT = self.scaledLogCoordinate(
            temperature_k,
            self.min_temperature_k,
            self.max_temperature_k,
        );
        const scaled_lnp = self.scaledLogCoordinate(
            pressure_hpa,
            self.min_pressure_hpa,
            self.max_pressure_hpa,
        );

        fillLegendreValues(legendre_lnT[0..@as(usize, self.temperature_coefficient_count)], scaled_lnT);
        fillLegendreValues(legendre_lnp[0..@as(usize, self.pressure_coefficient_count)], scaled_lnp);
        fillLegendreTemperatureDerivative(
            derivative_legendre_lnT[0..@as(usize, self.temperature_coefficient_count)],
            legendre_lnT[0..@as(usize, self.temperature_coefficient_count)],
            scaled_lnT,
            temperature_k,
            self.min_temperature_k,
            self.max_temperature_k,
        );

        const bracket = self.wavelengthBracket(wavelength_nm);
        const left_sigma = self.evaluateAtIndex(
            bracket.left_index,
            legendre_lnT[0..@as(usize, self.temperature_coefficient_count)],
            legendre_lnp[0..@as(usize, self.pressure_coefficient_count)],
        );
        const right_sigma = if (bracket.left_index == bracket.right_index)
            left_sigma
        else
            self.evaluateAtIndex(
                bracket.right_index,
                legendre_lnT[0..@as(usize, self.temperature_coefficient_count)],
                legendre_lnp[0..@as(usize, self.pressure_coefficient_count)],
            );
        const left_derivative = self.evaluateAtIndex(
            bracket.left_index,
            derivative_legendre_lnT[0..@as(usize, self.temperature_coefficient_count)],
            legendre_lnp[0..@as(usize, self.pressure_coefficient_count)],
        );
        const right_derivative = if (bracket.left_index == bracket.right_index)
            left_derivative
        else
            self.evaluateAtIndex(
                bracket.right_index,
                derivative_legendre_lnT[0..@as(usize, self.temperature_coefficient_count)],
                legendre_lnp[0..@as(usize, self.pressure_coefficient_count)],
            );

        return .{
            .sigma = @max(
                left_sigma + bracket.weight * (right_sigma - left_sigma),
                0.0,
            ),
            .d_sigma_d_temperature = left_derivative + bracket.weight * (right_derivative - left_derivative),
        };
    }

    fn evaluateAtIndex(
        self: OperationalCrossSectionLut,
        wavelength_index: usize,
        legendre_lnT: []const f64,
        legendre_lnp: []const f64,
    ) f64 {
        var sigma: f64 = 0.0;
        for (0..self.pressure_coefficient_count) |pressure_index| {
            for (0..self.temperature_coefficient_count) |temperature_index| {
                sigma += self.coefficientAt(temperature_index, pressure_index, wavelength_index) *
                    legendre_lnT[temperature_index] *
                    legendre_lnp[pressure_index];
            }
        }
        return sigma;
    }

    fn coefficientAt(
        self: OperationalCrossSectionLut,
        temperature_index: usize,
        pressure_index: usize,
        wavelength_index: usize,
    ) f64 {
        const wavelength_stride =
            @as(usize, self.temperature_coefficient_count) *
            @as(usize, self.pressure_coefficient_count);
        const offset = wavelength_index * wavelength_stride +
            pressure_index * @as(usize, self.temperature_coefficient_count) +
            temperature_index;
        return self.coefficients[offset];
    }

    fn scaledLogCoordinate(
        self: OperationalCrossSectionLut,
        value: f64,
        minimum: f64,
        maximum: f64,
    ) f64 {
        _ = self;
        const clamped = std.math.clamp(value, minimum, maximum);
        const ln_max = @log(maximum);
        const ln_min = @log(minimum);
        const scale = ln_max - ln_min;
        if (scale == 0.0) return 0.0;
        return -((ln_max + ln_min) / scale) + (2.0 * @log(clamped) / scale);
    }

    fn wavelengthBracket(
        self: OperationalCrossSectionLut,
        wavelength_nm: f64,
    ) struct { left_index: usize, right_index: usize, weight: f64 } {
        if (self.wavelengths_nm.len == 0) {
            return .{
                .left_index = 0,
                .right_index = 0,
                .weight = 0.0,
            };
        }
        if (wavelength_nm <= self.wavelengths_nm[0]) {
            return .{
                .left_index = 0,
                .right_index = 0,
                .weight = 0.0,
            };
        }

        for (self.wavelengths_nm[0 .. self.wavelengths_nm.len - 1], self.wavelengths_nm[1..], 0..) |left_nm, right_nm, index| {
            if (wavelength_nm <= right_nm) {
                const span = right_nm - left_nm;
                return .{
                    .left_index = index,
                    .right_index = index + 1,
                    .weight = if (span == 0.0) 0.0 else (wavelength_nm - left_nm) / span,
                };
            }
        }

        const last_index = self.wavelengths_nm.len - 1;
        return .{
            .left_index = last_index,
            .right_index = last_index,
            .weight = 0.0,
        };
    }
};

fn fillLegendreValues(values: []f64, scaled_coordinate: f64) void {
    if (values.len == 0) return;
    values[0] = 1.0;
    if (values.len == 1) return;
    values[1] = scaled_coordinate;
    if (values.len == 2) return;

    for (2..values.len) |index| {
        const order = @as(f64, @floatFromInt(index - 1));
        values[index] =
            (((2.0 * order) + 1.0) * scaled_coordinate * values[index - 1] - order * values[index - 2]) /
            (order + 1.0);
    }
}

fn fillLegendreTemperatureDerivative(
    derivative_values: []f64,
    legendre_values: []const f64,
    scaled_coordinate: f64,
    temperature_k: f64,
    minimum_temperature_k: f64,
    maximum_temperature_k: f64,
) void {
    @memset(derivative_values, 0.0);
    if (derivative_values.len <= 1) return;

    const ln_max = @log(maximum_temperature_k);
    const ln_min = @log(minimum_temperature_k);
    const scale = ln_max - ln_min;
    if (scale == 0.0 or temperature_k <= 0.0) return;

    const d_scaled_d_temperature = 2.0 / (scale * std.math.clamp(temperature_k, minimum_temperature_k, maximum_temperature_k));
    derivative_values[1] = 1.0;
    for (2..derivative_values.len) |index| {
        derivative_values[index] =
            (scaled_coordinate * derivative_values[index - 1]) +
            (@as(f64, @floatFromInt(index)) * legendre_values[index - 1]);
    }
    for (1..derivative_values.len) |index| {
        derivative_values[index] *= d_scaled_d_temperature;
    }
}
