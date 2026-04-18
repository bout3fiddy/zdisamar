const basis = @import("cross_section_lut_basis.zig");

pub const Evaluation = struct {
    sigma: f64,
    d_sigma_d_temperature: f64,
};

pub fn evaluate(
    comptime LutType: type,
    self: *const LutType,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) Evaluation {
    if (!self.enabled()) {
        return .{
            .sigma = 0.0,
            .d_sigma_d_temperature = 0.0,
        };
    }

    var legendre_lnT = [_]f64{0.0} ** @import("constants.zig").max_operational_refspec_temperature_coefficients;
    var legendre_lnp = [_]f64{0.0} ** @import("constants.zig").max_operational_refspec_pressure_coefficients;
    var derivative_legendre_lnT = [_]f64{0.0} ** @import("constants.zig").max_operational_refspec_temperature_coefficients;

    const scaled_lnT = scaledLogCoordinate(
        temperature_k,
        self.min_temperature_k,
        self.max_temperature_k,
    );
    const scaled_lnp = scaledLogCoordinate(
        pressure_hpa,
        self.min_pressure_hpa,
        self.max_pressure_hpa,
    );

    basis.fillLegendreValues(legendre_lnT[0..@as(usize, self.temperature_coefficient_count)], scaled_lnT);
    basis.fillLegendreValues(legendre_lnp[0..@as(usize, self.pressure_coefficient_count)], scaled_lnp);
    basis.fillLegendreTemperatureDerivative(
        derivative_legendre_lnT[0..@as(usize, self.temperature_coefficient_count)],
        legendre_lnT[0..@as(usize, self.temperature_coefficient_count)],
        scaled_lnT,
        temperature_k,
        self.min_temperature_k,
        self.max_temperature_k,
    );

    const bracket = wavelengthBracket(LutType, self, wavelength_nm);
    const left_sigma = evaluateAtIndex(
        LutType,
        self,
        bracket.left_index,
        legendre_lnT[0..@as(usize, self.temperature_coefficient_count)],
        legendre_lnp[0..@as(usize, self.pressure_coefficient_count)],
    );
    const right_sigma = if (bracket.left_index == bracket.right_index)
        left_sigma
    else
        evaluateAtIndex(
            LutType,
            self,
            bracket.right_index,
            legendre_lnT[0..@as(usize, self.temperature_coefficient_count)],
            legendre_lnp[0..@as(usize, self.pressure_coefficient_count)],
        );
    const left_derivative = evaluateAtIndex(
        LutType,
        self,
        bracket.left_index,
        derivative_legendre_lnT[0..@as(usize, self.temperature_coefficient_count)],
        legendre_lnp[0..@as(usize, self.pressure_coefficient_count)],
    );
    const right_derivative = if (bracket.left_index == bracket.right_index)
        left_derivative
    else
        evaluateAtIndex(
            LutType,
            self,
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
    comptime LutType: type,
    self: *const LutType,
    wavelength_index: usize,
    legendre_lnT: []const f64,
    legendre_lnp: []const f64,
) f64 {
    var sigma: f64 = 0.0;
    for (0..self.pressure_coefficient_count) |pressure_index| {
        for (0..self.temperature_coefficient_count) |temperature_index| {
            sigma += coefficientAt(
                LutType,
                self,
                temperature_index,
                pressure_index,
                wavelength_index,
            ) *
                legendre_lnT[temperature_index] *
                legendre_lnp[pressure_index];
        }
    }
    return sigma;
}

fn coefficientAt(
    comptime LutType: type,
    self: *const LutType,
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
    value: f64,
    minimum: f64,
    maximum: f64,
) f64 {
    if (!(minimum > 0.0) or !(maximum > 0.0)) return 0.0;
    const ln_max = @log(maximum);
    const ln_min = @log(minimum);
    const scale = ln_max - ln_min;
    if (scale == 0.0) return 0.0;
    const safe_value = if (value > 0.0) value else minimum;
    return -((ln_max + ln_min) / scale) + (2.0 * @log(safe_value) / scale);
}

fn wavelengthBracket(
    comptime LutType: type,
    self: *const LutType,
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
