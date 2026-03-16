const std = @import("std");
const errors = @import("../core/errors.zig");
const Allocator = std.mem.Allocator;

pub const max_line_shape_samples: usize = 9;
pub const max_line_shape_nominals: usize = 256;
pub const max_operational_refspec_temperature_coefficients: usize = 8;
pub const max_operational_refspec_pressure_coefficients: usize = 12;

pub const OperationalReferenceGrid = struct {
    wavelengths_nm: []const f64 = &[_]f64{},
    weights: []const f64 = &[_]f64{},

    pub fn enabled(self: OperationalReferenceGrid) bool {
        return self.wavelengths_nm.len > 0;
    }

    pub fn validate(self: OperationalReferenceGrid) errors.Error!void {
        if (!self.enabled()) {
            if (self.weights.len != 0) return errors.Error.InvalidRequest;
            return;
        }
        if (self.weights.len != self.wavelengths_nm.len) return errors.Error.InvalidRequest;

        var previous_wavelength: ?f64 = null;
        var weight_sum: f64 = 0.0;
        for (self.wavelengths_nm, self.weights) |wavelength_nm, weight| {
            if (!std.math.isFinite(wavelength_nm) or !std.math.isFinite(weight) or weight < 0.0) {
                return errors.Error.InvalidRequest;
            }
            if (previous_wavelength) |previous| {
                if (wavelength_nm <= previous) return errors.Error.InvalidRequest;
            }
            previous_wavelength = wavelength_nm;
            weight_sum += weight;
        }
        if (weight_sum <= 0.0 or !std.math.isFinite(weight_sum)) return errors.Error.InvalidRequest;
    }

    pub fn clone(self: OperationalReferenceGrid, allocator: Allocator) !OperationalReferenceGrid {
        return .{
            .wavelengths_nm = try allocator.dupe(f64, self.wavelengths_nm),
            .weights = try allocator.dupe(f64, self.weights),
        };
    }

    pub fn deinitOwned(self: *OperationalReferenceGrid, allocator: Allocator) void {
        allocator.free(self.wavelengths_nm);
        allocator.free(self.weights);
        self.* = .{};
    }
};

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

pub const OperationalCrossSectionLut = struct {
    wavelengths_nm: []const f64 = &[_]f64{},
    coefficients: []const f64 = &[_]f64{},
    temperature_coefficient_count: u8 = 0,
    pressure_coefficient_count: u8 = 0,
    min_temperature_k: f64 = 0.0,
    max_temperature_k: f64 = 0.0,
    min_pressure_hpa: f64 = 0.0,
    max_pressure_hpa: f64 = 0.0,

    pub fn enabled(self: OperationalCrossSectionLut) bool {
        return self.wavelengths_nm.len > 0;
    }

    pub fn validate(self: OperationalCrossSectionLut) errors.Error!void {
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
        self: OperationalCrossSectionLut,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) f64 {
        return self.evaluate(wavelength_nm, temperature_k, pressure_hpa).sigma;
    }

    pub fn dSigmaDTemperatureAt(
        self: OperationalCrossSectionLut,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) f64 {
        return self.evaluate(wavelength_nm, temperature_k, pressure_hpa).d_sigma_d_temperature;
    }

    fn evaluate(
        self: OperationalCrossSectionLut,
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

pub const InstrumentLineShape = struct {
    sample_count: u8 = 0,
    offsets_nm: [max_line_shape_samples]f64 = [_]f64{0.0} ** max_line_shape_samples,
    weights: [max_line_shape_samples]f64 = [_]f64{0.0} ** max_line_shape_samples,

    pub fn validate(self: InstrumentLineShape) errors.Error!void {
        if (self.sample_count > max_line_shape_samples) {
            return errors.Error.InvalidRequest;
        }
        if (self.sample_count == 0) return;

        var weight_sum: f64 = 0.0;
        for (0..self.sample_count) |index| {
            if (self.weights[index] < 0.0) return errors.Error.InvalidRequest;
            weight_sum += self.weights[index];
        }
        if (!std.math.isFinite(weight_sum) or weight_sum <= 0.0) {
            return errors.Error.InvalidRequest;
        }
    }
};

pub const InstrumentLineShapeTable = struct {
    nominal_count: u16 = 0,
    sample_count: u8 = 0,
    nominal_wavelengths_nm: [max_line_shape_nominals]f64 = [_]f64{0.0} ** max_line_shape_nominals,
    offsets_nm: [max_line_shape_samples]f64 = [_]f64{0.0} ** max_line_shape_samples,
    weights: [max_line_shape_nominals * max_line_shape_samples]f64 = [_]f64{0.0} ** (max_line_shape_nominals * max_line_shape_samples),

    pub fn validate(self: InstrumentLineShapeTable) errors.Error!void {
        if (self.nominal_count > max_line_shape_nominals or self.sample_count > max_line_shape_samples) {
            return errors.Error.InvalidRequest;
        }
        if (self.nominal_count == 0 and self.sample_count == 0) return;
        if (self.nominal_count == 0 or self.sample_count == 0) {
            return errors.Error.InvalidRequest;
        }

        var previous_nominal: ?f64 = null;
        for (0..self.nominal_count) |nominal_index| {
            const nominal = self.nominal_wavelengths_nm[nominal_index];
            if (!std.math.isFinite(nominal)) return errors.Error.InvalidRequest;
            if (previous_nominal) |previous| {
                if (nominal < previous) return errors.Error.InvalidRequest;
            }
            previous_nominal = nominal;

            var row_sum: f64 = 0.0;
            for (0..self.sample_count) |sample_index| {
                const weight = self.weightAt(nominal_index, sample_index);
                if (weight < 0.0 or !std.math.isFinite(weight)) return errors.Error.InvalidRequest;
                row_sum += weight;
            }
            if (row_sum <= 0.0 or !std.math.isFinite(row_sum)) return errors.Error.InvalidRequest;
        }
    }

    pub fn weightAt(self: InstrumentLineShapeTable, nominal_index: usize, sample_index: usize) f64 {
        return self.weights[nominal_index * max_line_shape_samples + sample_index];
    }

    pub fn setWeight(self: *InstrumentLineShapeTable, nominal_index: usize, sample_index: usize, value: f64) void {
        self.weights[nominal_index * max_line_shape_samples + sample_index] = value;
    }

    pub fn nearestNominalIndex(self: InstrumentLineShapeTable, wavelength_nm: f64) ?usize {
        if (self.nominal_count == 0) return null;

        var best_index: usize = 0;
        var best_delta = std.math.inf(f64);
        for (0..self.nominal_count) |index| {
            const delta = @abs(self.nominal_wavelengths_nm[index] - wavelength_nm);
            if (delta < best_delta) {
                best_delta = delta;
                best_index = index;
            }
        }
        return best_index;
    }
};

pub const Instrument = struct {
    pub const SamplingMode = enum {
        native,
        operational,
        measured_channels,
        synthetic,
    };

    pub const NoiseModelKind = enum {
        none,
        shot_noise,
        s5p_operational,
        snr_from_input,
    };

    name: []const u8 = "generic",
    sampling: []const u8 = "native",
    noise_model: []const u8 = "none",
    wavelength_shift_nm: f64 = 0.0,
    instrument_line_fwhm_nm: f64 = 0.0,
    high_resolution_step_nm: f64 = 0.0,
    high_resolution_half_span_nm: f64 = 0.0,
    instrument_line_shape: InstrumentLineShape = .{},
    instrument_line_shape_table: InstrumentLineShapeTable = .{},
    operational_refspec_grid: OperationalReferenceGrid = .{},
    operational_solar_spectrum: OperationalSolarSpectrum = .{},
    o2_operational_lut: OperationalCrossSectionLut = .{},
    o2o2_operational_lut: OperationalCrossSectionLut = .{},

    pub fn resolvedSampling(self: Instrument) errors.Error!SamplingMode {
        if (std.mem.eql(u8, self.sampling, "native")) return .native;
        if (std.mem.eql(u8, self.sampling, "operational")) return .operational;
        if (std.mem.eql(u8, self.sampling, "measured_channels")) return .measured_channels;
        if (std.mem.eql(u8, self.sampling, "synthetic")) return .synthetic;
        return errors.Error.InvalidRequest;
    }

    pub fn resolvedNoiseModel(self: Instrument) errors.Error!NoiseModelKind {
        if (std.mem.eql(u8, self.noise_model, "none")) return .none;
        if (std.mem.eql(u8, self.noise_model, "shot_noise")) return .shot_noise;
        if (std.mem.eql(u8, self.noise_model, "s5p_operational")) return .s5p_operational;
        if (std.mem.eql(u8, self.noise_model, "snr_from_input")) return .snr_from_input;
        return errors.Error.InvalidRequest;
    }

    pub fn validate(self: Instrument) errors.Error!void {
        if (self.name.len == 0) {
            return errors.Error.MissingObservationInstrument;
        }
        if (self.sampling.len == 0 or self.noise_model.len == 0) {
            return errors.Error.InvalidRequest;
        }
        _ = try self.resolvedSampling();
        _ = try self.resolvedNoiseModel();
        if (self.instrument_line_fwhm_nm < 0.0) {
            return errors.Error.InvalidRequest;
        }
        if (self.high_resolution_step_nm < 0.0 or self.high_resolution_half_span_nm < 0.0) {
            return errors.Error.InvalidRequest;
        }
        if ((self.high_resolution_step_nm == 0.0) != (self.high_resolution_half_span_nm == 0.0)) {
            return errors.Error.InvalidRequest;
        }
        try self.instrument_line_shape.validate();
        try self.instrument_line_shape_table.validate();
        try self.operational_refspec_grid.validate();
        try self.operational_solar_spectrum.validate();
        try self.o2_operational_lut.validate();
        try self.o2o2_operational_lut.validate();
    }

    pub fn deinitOwned(self: *Instrument, allocator: Allocator) void {
        self.operational_refspec_grid.deinitOwned(allocator);
        self.operational_solar_spectrum.deinitOwned(allocator);
        self.o2_operational_lut.deinitOwned(allocator);
        self.o2o2_operational_lut.deinitOwned(allocator);
    }
};

test "operational cross-section lut evaluates vendor-style scaled log legendre expansions" {
    const lut: OperationalCrossSectionLut = .{
        .wavelengths_nm = &[_]f64{ 760.8, 761.2 },
        .coefficients = &[_]f64{
            2.0e-24, 0.5e-24, 0.3e-24, 0.1e-24,
            3.0e-24, 0.6e-24, 0.4e-24, 0.2e-24,
        },
        .temperature_coefficient_count = 2,
        .pressure_coefficient_count = 2,
        .min_temperature_k = 220.0,
        .max_temperature_k = 320.0,
        .min_pressure_hpa = 150.0,
        .max_pressure_hpa = 1000.0,
    };

    try lut.validate();
    const sigma = lut.sigmaAt(761.0, 260.0, 700.0);
    const warmer_sigma = lut.sigmaAt(761.0, 300.0, 700.0);
    const derivative = lut.dSigmaDTemperatureAt(761.0, 260.0, 700.0);

    try std.testing.expect(sigma > 0.0);
    try std.testing.expect(warmer_sigma > sigma);
    try std.testing.expect(derivative > 0.0);
    try std.testing.expect(lut.sigmaAt(761.2, 260.0, 700.0) > lut.sigmaAt(760.8, 260.0, 700.0));
}

test "instrument resolves typed sampling and noise selectors" {
    const instrument: Instrument = .{
        .name = "synthetic",
        .sampling = "measured_channels",
        .noise_model = "snr_from_input",
        .high_resolution_step_nm = 0.08,
        .high_resolution_half_span_nm = 0.32,
    };

    try std.testing.expectEqual(Instrument.SamplingMode.measured_channels, try instrument.resolvedSampling());
    try std.testing.expectEqual(Instrument.NoiseModelKind.snr_from_input, try instrument.resolvedNoiseModel());
    try instrument.validate();

    try std.testing.expectError(errors.Error.InvalidRequest, (Instrument{
        .name = "synthetic",
        .sampling = "mystery_mode",
        .noise_model = "none",
    }).validate());
}

test "instrument validation rejects malformed operational lut surfaces" {
    const invalid: Instrument = .{
        .name = "test",
        .sampling = "operational",
        .noise_model = "s5p_operational",
        .o2_operational_lut = .{
            .wavelengths_nm = &[_]f64{760.8},
            .coefficients = &[_]f64{},
            .temperature_coefficient_count = 1,
            .pressure_coefficient_count = 1,
            .min_temperature_k = 220.0,
            .max_temperature_k = 320.0,
            .min_pressure_hpa = 150.0,
            .max_pressure_hpa = 1000.0,
        },
    };

    try std.testing.expectError(errors.Error.InvalidRequest, invalid.validate());
}

test "operational reference grid and solar spectrum validate typed external inputs" {
    const instrument: Instrument = .{
        .name = "tropomi",
        .sampling = "operational",
        .noise_model = "s5p_operational",
        .operational_refspec_grid = .{
            .wavelengths_nm = &[_]f64{ 760.8, 761.0, 761.2 },
            .weights = &[_]f64{ 0.25, 0.5, 0.25 },
        },
        .operational_solar_spectrum = .{
            .wavelengths_nm = &[_]f64{ 760.8, 761.0, 761.2 },
            .irradiance = &[_]f64{ 2.7e14, 2.8e14, 2.75e14 },
        },
    };

    try instrument.validate();
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.75e14),
        instrument.operational_solar_spectrum.interpolateIrradiance(760.9),
        1.0e10,
    );
}

test "operational typed carriers reject duplicate wavelengths" {
    const invalid_grid: Instrument = .{
        .name = "tropomi",
        .sampling = "operational",
        .noise_model = "s5p_operational",
        .operational_refspec_grid = .{
            .wavelengths_nm = &[_]f64{ 760.8, 760.8 },
            .weights = &[_]f64{ 0.5, 0.5 },
        },
    };
    try std.testing.expectError(errors.Error.InvalidRequest, invalid_grid.validate());

    const invalid_solar: Instrument = .{
        .name = "tropomi",
        .sampling = "operational",
        .noise_model = "s5p_operational",
        .operational_solar_spectrum = .{
            .wavelengths_nm = &[_]f64{ 760.8, 760.8 },
            .irradiance = &[_]f64{ 2.7e14, 2.8e14 },
        },
    };
    try std.testing.expectError(errors.Error.InvalidRequest, invalid_solar.validate());

    const invalid_lut: Instrument = .{
        .name = "tropomi",
        .sampling = "operational",
        .noise_model = "s5p_operational",
        .o2_operational_lut = .{
            .wavelengths_nm = &[_]f64{ 760.8, 760.8 },
            .coefficients = &[_]f64{ 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0 },
            .temperature_coefficient_count = 2,
            .pressure_coefficient_count = 2,
            .min_temperature_k = 220.0,
            .max_temperature_k = 320.0,
            .min_pressure_hpa = 150.0,
            .max_pressure_hpa = 1000.0,
        },
    };
    try std.testing.expectError(errors.Error.InvalidRequest, invalid_lut.validate());
}
