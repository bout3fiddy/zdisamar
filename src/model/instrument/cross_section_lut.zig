//! Purpose:
//!   Store operational cross-section lookup tables for wavelength, temperature, and pressure.
//!
//! Physics:
//!   Evaluates wavelength-indexed Legendre coefficient tables over scaled logarithmic temperature and pressure coordinates.
//!
//! Vendor:
//!   `operational cross-section LUT`
//!
//! Design:
//!   The coefficient layout is explicit so the flattened indexing and polynomial basis remain easy to audit.
//!
//! Invariants:
//!   Wavelengths are monotonic, coefficient counts stay within the fixed caps, and the coefficient tensor shape matches the table metadata.
//!
//! Validation:
//!   Tests cover interpolation and temperature/pressure dependence through the LUT evaluator.

const std = @import("std");
const errors = @import("../../core/errors.zig");
const LutControls = @import("../../core/lut_controls.zig");
const ReferenceData = @import("../ReferenceData.zig");
const gauss_legendre = @import("../../kernels/quadrature/gauss_legendre.zig");
const constants = @import("constants.zig");
const max_operational_refspec_temperature_coefficients = constants.max_operational_refspec_temperature_coefficients;
const max_operational_refspec_pressure_coefficients = constants.max_operational_refspec_pressure_coefficients;
const Allocator = std.mem.Allocator;

pub const GenerationSource = union(enum) {
    line_list: *const ReferenceData.SpectroscopyLineList,
    cross_section_table: *const ReferenceData.CrossSectionTable,
    cia_table: *const ReferenceData.CollisionInducedAbsorptionTable,
};

/// Purpose:
///   Store an operational cross-section lookup table.
///
/// Physics:
///   Evaluates wavelength-indexed coefficients over scaled temperature and pressure coordinates.
pub const OperationalCrossSectionLut = struct {
    wavelengths_nm: []const f64 = &[_]f64{},
    coefficients: []const f64 = &[_]f64{},
    temperature_coefficient_count: u8 = 0,
    pressure_coefficient_count: u8 = 0,
    min_temperature_k: f64 = 0.0,
    max_temperature_k: f64 = 0.0,
    min_pressure_hpa: f64 = 0.0,
    max_pressure_hpa: f64 = 0.0,

    /// Purpose:
    ///   Report whether the LUT is active.
    pub fn enabled(self: *const OperationalCrossSectionLut) bool {
        return self.wavelengths_nm.len > 0;
    }

    /// Purpose:
    ///   Validate the operational cross-section LUT.
    ///
    /// Physics:
    ///   Ensures monotonic wavelengths, finite coefficient values, and compatible temperature/pressure ranges.
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

    /// Purpose:
    ///   Clone the LUT into owned storage.
    pub fn clone(self: OperationalCrossSectionLut, allocator: Allocator) !OperationalCrossSectionLut {
        var cloned: OperationalCrossSectionLut = .{
            .temperature_coefficient_count = self.temperature_coefficient_count,
            .pressure_coefficient_count = self.pressure_coefficient_count,
            .min_temperature_k = self.min_temperature_k,
            .max_temperature_k = self.max_temperature_k,
            .min_pressure_hpa = self.min_pressure_hpa,
            .max_pressure_hpa = self.max_pressure_hpa,
        };
        cloned.wavelengths_nm = try allocator.dupe(f64, self.wavelengths_nm);
        errdefer allocator.free(cloned.wavelengths_nm);
        cloned.coefficients = try allocator.dupe(f64, self.coefficients);
        return cloned;
    }

    /// Purpose:
    ///   Build an operational LUT by fitting direct absorption evaluations onto the Legendre basis.
    ///
    /// Physics:
    ///   Mirrors the vendor XsecLUT workflow by evaluating sigma on Gauss-Legendre nodes in
    ///   scaled `ln(T)` and `ln(p)` coordinates, then projecting onto the orthogonal basis.
    pub fn buildFromSource(
        allocator: Allocator,
        wavelengths_nm: []const f64,
        source: GenerationSource,
        controls: LutControls.XsecControls,
    ) !OperationalCrossSectionLut {
        try controls.validate();
        if (controls.mode == .direct or controls.mode == .consume or wavelengths_nm.len == 0) {
            return errors.Error.InvalidRequest;
        }
        if (controls.temperature_coefficient_count > max_operational_refspec_temperature_coefficients or
            controls.pressure_coefficient_count > max_operational_refspec_pressure_coefficients)
        {
            return errors.Error.InvalidRequest;
        }

        const temperature_grid_count: usize = controls.temperature_grid_count;
        const pressure_grid_count: usize = controls.pressure_grid_count;
        const temperature_coefficient_count: usize = controls.temperature_coefficient_count;
        const pressure_coefficient_count: usize = controls.pressure_coefficient_count;

        const scaled_lnT = try allocator.alloc(f64, temperature_grid_count);
        defer allocator.free(scaled_lnT);
        const scaled_lnp = try allocator.alloc(f64, pressure_grid_count);
        defer allocator.free(scaled_lnp);
        const weight_scaled_lnT = try allocator.alloc(f64, temperature_grid_count);
        defer allocator.free(weight_scaled_lnT);
        const weight_scaled_lnp = try allocator.alloc(f64, pressure_grid_count);
        defer allocator.free(weight_scaled_lnp);
        const temperatures_k = try allocator.alloc(f64, temperature_grid_count);
        defer allocator.free(temperatures_k);
        const pressures_hpa = try allocator.alloc(f64, pressure_grid_count);
        defer allocator.free(pressures_hpa);
        const legendre_lnT = try allocator.alloc(f64, temperature_coefficient_count * temperature_grid_count);
        defer allocator.free(legendre_lnT);
        const legendre_lnp = try allocator.alloc(f64, pressure_coefficient_count * pressure_grid_count);
        defer allocator.free(legendre_lnp);
        const samples = try allocator.alloc(f64, wavelengths_nm.len * temperature_grid_count * pressure_grid_count);
        defer allocator.free(samples);
        const coefficients = try allocator.alloc(f64, wavelengths_nm.len * temperature_coefficient_count * pressure_coefficient_count);
        errdefer allocator.free(coefficients);

        try gauss_legendre.fillNodesAndWeights(
            controls.temperature_grid_count,
            scaled_lnT,
            weight_scaled_lnT,
        );
        try gauss_legendre.fillNodesAndWeights(
            controls.pressure_grid_count,
            scaled_lnp,
            weight_scaled_lnp,
        );

        fillPhysicalGrid(
            scaled_lnT,
            temperatures_k,
            controls.min_temperature_k,
            controls.max_temperature_k,
        );
        fillPhysicalGrid(
            scaled_lnp,
            pressures_hpa,
            controls.min_pressure_hpa,
            controls.max_pressure_hpa,
        );

        for (0..temperature_grid_count) |temperature_index| {
            fillLegendreValues(
                legendre_lnT[temperature_index * temperature_coefficient_count ..][0..temperature_coefficient_count],
                scaled_lnT[temperature_index],
            );
        }
        for (0..pressure_grid_count) |pressure_index| {
            fillLegendreValues(
                legendre_lnp[pressure_index * pressure_coefficient_count ..][0..pressure_coefficient_count],
                scaled_lnp[pressure_index],
            );
        }

        for (0..temperature_grid_count) |temperature_index| {
            for (0..pressure_grid_count) |pressure_index| {
                var prepared_line_state: ?ReferenceData.StrongLinePreparedState = null;
                defer if (prepared_line_state) |*state| state.deinit(allocator);
                if (source == .line_list) {
                    prepared_line_state = try source.line_list.prepareStrongLineState(
                        allocator,
                        temperatures_k[temperature_index],
                        pressures_hpa[pressure_index],
                    );
                }
                for (wavelengths_nm, 0..) |wavelength_nm, wavelength_index| {
                    samples[
                        sampleIndex(
                            temperature_index,
                            pressure_index,
                            wavelength_index,
                            pressure_grid_count,
                            wavelengths_nm.len,
                        )
                    ] = sampleSigmaAtSource(
                        source,
                        wavelength_nm,
                        temperatures_k[temperature_index],
                        pressures_hpa[pressure_index],
                        if (prepared_line_state) |*state| state else null,
                    );
                }
            }
        }

        for (wavelengths_nm, 0..) |_, wavelength_index| {
            for (0..pressure_coefficient_count) |pressure_coefficient_index| {
                for (0..temperature_coefficient_count) |temperature_coefficient_index| {
                    var coefficient: f64 = 0.0;
                    for (0..pressure_grid_count) |pressure_index| {
                        const pressure_legendre = legendre_lnp[
                            pressure_index * pressure_coefficient_count + pressure_coefficient_index
                        ];
                        for (0..temperature_grid_count) |temperature_index| {
                            const temperature_legendre = legendre_lnT[
                                temperature_index * temperature_coefficient_count + temperature_coefficient_index
                            ];
                            coefficient +=
                                weight_scaled_lnp[pressure_index] *
                                weight_scaled_lnT[temperature_index] *
                                pressure_legendre *
                                temperature_legendre *
                                samples[
                                    sampleIndex(
                                        temperature_index,
                                        pressure_index,
                                        wavelength_index,
                                        pressure_grid_count,
                                        wavelengths_nm.len,
                                    )
                                ];
                        }
                    }
                    coefficient *= (2.0 * @as(f64, @floatFromInt(pressure_coefficient_index)) + 1.0) / 2.0;
                    coefficient *= (2.0 * @as(f64, @floatFromInt(temperature_coefficient_index)) + 1.0) / 2.0;
                    coefficients[
                        coefficientIndex(
                            temperature_coefficient_index,
                            pressure_coefficient_index,
                            wavelength_index,
                            temperature_coefficient_count,
                            pressure_coefficient_count,
                        )
                    ] = coefficient;
                }
            }
        }

        const lut: OperationalCrossSectionLut = .{
            .wavelengths_nm = try allocator.dupe(f64, wavelengths_nm),
            .coefficients = coefficients,
            .temperature_coefficient_count = controls.temperature_coefficient_count,
            .pressure_coefficient_count = controls.pressure_coefficient_count,
            .min_temperature_k = controls.min_temperature_k,
            .max_temperature_k = controls.max_temperature_k,
            .min_pressure_hpa = controls.min_pressure_hpa,
            .max_pressure_hpa = controls.max_pressure_hpa,
        };
        errdefer allocator.free(lut.wavelengths_nm);
        try lut.validate();
        return lut;
    }

    /// Purpose:
    ///   Release owned LUT storage.
    pub fn deinitOwned(self: *OperationalCrossSectionLut, allocator: Allocator) void {
        allocator.free(self.wavelengths_nm);
        allocator.free(self.coefficients);
        self.* = .{};
    }

    /// Purpose:
    ///   Evaluate the LUT sigma at a wavelength, temperature, and pressure.
    ///
    /// Physics:
    ///   Interpolates wavelength samples after evaluating the Legendre basis in scaled log coordinates.
    pub fn sigmaAt(
        self: *const OperationalCrossSectionLut,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) f64 {
        return self.evaluate(wavelength_nm, temperature_k, pressure_hpa).sigma;
    }

    /// Purpose:
    ///   Evaluate the LUT temperature derivative at a wavelength, temperature, and pressure.
    pub fn dSigmaDTemperatureAt(
        self: *const OperationalCrossSectionLut,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) f64 {
        return self.evaluate(wavelength_nm, temperature_k, pressure_hpa).d_sigma_d_temperature;
    }

    /// Purpose:
    ///   Evaluate the LUT at a point and return sigma plus temperature derivative.
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

    /// Purpose:
    ///   Evaluate one wavelength slice of the coefficient table.
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

    /// Purpose:
    ///   Read a coefficient from the flattened wavelength/pressure/temperature tensor.
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

    /// Purpose:
    ///   Map a positive physical coordinate into scaled log space.
    ///
    /// Units:
    ///   `value`, `minimum`, and `maximum` are temperatures in kelvin or pressures in hPa depending on the caller.
    fn scaledLogCoordinate(
        self: OperationalCrossSectionLut,
        value: f64,
        minimum: f64,
        maximum: f64,
    ) f64 {
        _ = self;
        const ln_max = @log(maximum);
        const ln_min = @log(minimum);
        const scale = ln_max - ln_min;
        if (scale == 0.0) return 0.0;
        return -((ln_max + ln_min) / scale) + (2.0 * @log(value) / scale);
    }

    /// Purpose:
    ///   Find the wavelength bracket used for linear interpolation.
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

// VENDOR:
//   `Legendre basis expansion`
//   These helpers assemble the polynomial basis and its temperature derivative for the flattened coefficient tensor.
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

    const d_scaled_d_temperature = 2.0 / (scale * temperature_k);
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

fn fillPhysicalGrid(
    scaled_coordinates: []const f64,
    values: []f64,
    minimum: f64,
    maximum: f64,
) void {
    const a = (@log(maximum) + @log(minimum)) * 0.5;
    const b = (@log(maximum) - @log(minimum)) * 0.5;
    for (scaled_coordinates, values) |scaled_coordinate, *value| {
        value.* = @exp(a + (b * scaled_coordinate));
    }
}

fn sampleSigmaAtSource(
    source: GenerationSource,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    prepared_line_state: ?*const ReferenceData.StrongLinePreparedState,
) f64 {
    return switch (source) {
        .line_list => |line_list| line_list.evaluateAtPrepared(
            wavelength_nm,
            temperature_k,
            pressure_hpa,
            prepared_line_state,
        ).total_sigma_cm2_per_molecule,
        .cross_section_table => |table| table.interpolateSigma(wavelength_nm),
        .cia_table => |table| table.sigmaAt(wavelength_nm, temperature_k),
    };
}

fn sampleIndex(
    temperature_index: usize,
    pressure_index: usize,
    wavelength_index: usize,
    pressure_grid_count: usize,
    wavelength_count: usize,
) usize {
    return temperature_index * pressure_grid_count * wavelength_count +
        pressure_index * wavelength_count +
        wavelength_index;
}

fn coefficientIndex(
    temperature_coefficient_index: usize,
    pressure_coefficient_index: usize,
    wavelength_index: usize,
    temperature_coefficient_count: usize,
    pressure_coefficient_count: usize,
) usize {
    return wavelength_index * temperature_coefficient_count * pressure_coefficient_count +
        pressure_coefficient_index * temperature_coefficient_count +
        temperature_coefficient_index;
}

test "generated cross-section LUT reproduces direct table values" {
    const wavelengths = [_]f64{ 430.0, 431.0, 432.0 };
    const points = [_]ReferenceData.CrossSectionPoint{
        .{ .wavelength_nm = 430.0, .sigma_cm2_per_molecule = 2.0e-19 },
        .{ .wavelength_nm = 431.0, .sigma_cm2_per_molecule = 3.0e-19 },
        .{ .wavelength_nm = 432.0, .sigma_cm2_per_molecule = 4.0e-19 },
    };
    const table: ReferenceData.CrossSectionTable = .{ .points = @constCast(points[0..]) };
    const lut = try OperationalCrossSectionLut.buildFromSource(
        std.testing.allocator,
        wavelengths[0..],
        .{ .cross_section_table = &table },
        .{
            .mode = .generate,
            .min_temperature_k = 180.0,
            .max_temperature_k = 325.0,
            .min_pressure_hpa = 0.03,
            .max_pressure_hpa = 1050.0,
            .temperature_grid_count = 6,
            .pressure_grid_count = 8,
            .temperature_coefficient_count = 3,
            .pressure_coefficient_count = 4,
        },
    );
    defer {
        var owned = lut;
        owned.deinitOwned(std.testing.allocator);
    }

    try std.testing.expectApproxEqRel(@as(f64, 3.0e-19), lut.sigmaAt(431.0, 250.0, 600.0), 1.0e-10);
    try std.testing.expectApproxEqRel(@as(f64, 0.0), lut.dSigmaDTemperatureAt(431.0, 250.0, 600.0), 1.0e-10);
}

test "generated cross-section LUT rejects consume-mode source builds" {
    const wavelengths = [_]f64{430.0};
    const points = [_]ReferenceData.CrossSectionPoint{
        .{ .wavelength_nm = 430.0, .sigma_cm2_per_molecule = 2.0e-19 },
    };
    const table: ReferenceData.CrossSectionTable = .{ .points = @constCast(points[0..]) };

    try std.testing.expectError(errors.Error.InvalidRequest, OperationalCrossSectionLut.buildFromSource(
        std.testing.allocator,
        wavelengths[0..],
        .{ .cross_section_table = &table },
        .{ .mode = .consume },
    ));
}

test "cross-section LUT extrapolates scaled log coordinates outside configured temperature range" {
    const lut: OperationalCrossSectionLut = .{
        .wavelengths_nm = &[_]f64{431.0},
        .coefficients = &[_]f64{
            0.0,
            1.0,
        },
        .temperature_coefficient_count = 2,
        .pressure_coefficient_count = 1,
        .min_temperature_k = 100.0,
        .max_temperature_k = 200.0,
        .min_pressure_hpa = 10.0,
        .max_pressure_hpa = 1000.0,
    };
    try lut.validate();

    const ln_span = @log(lut.max_temperature_k) - @log(lut.min_temperature_k);
    const expected_scaled_lnT =
        -((@log(lut.max_temperature_k) + @log(lut.min_temperature_k)) / ln_span) +
        (2.0 * @log(@as(f64, 50.0)) / ln_span);
    const expected_derivative = 2.0 / (ln_span * 50.0);

    try std.testing.expect(expected_scaled_lnT < -1.0);
    try std.testing.expectApproxEqRel(expected_scaled_lnT, lut.sigmaAt(431.0, 50.0, 100.0), 1.0e-12);
    try std.testing.expectApproxEqRel(expected_derivative, lut.dSigmaDTemperatureAt(431.0, 50.0, 100.0), 1.0e-12);
}
