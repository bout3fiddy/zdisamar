const std = @import("std");
const errors = @import("../../common/errors.zig");
const LutControls = @import("../../common/lut_controls.zig");
const ReferenceData = @import("../ReferenceData.zig");
const gauss_legendre = @import("../../common/math/quadrature/gauss_legendre.zig");
const constants = @import("constants.zig");

const Allocator = std.mem.Allocator;
const max_operational_refspec_temperature_coefficients = constants.max_operational_refspec_temperature_coefficients;
const max_operational_refspec_pressure_coefficients = constants.max_operational_refspec_pressure_coefficients;

// cross_section_lut.zig --------------------------------------------------------------------------------------|
// Operational pressure/temperature cross-section LUT preparation and evaluation.                              |
//                                                                                                             |
// data                                                                                                        |
//   OperationalCrossSectionLut is a header over wavelength planes and Legendre coefficient storage.           |
//   buildLutFromSource samples a source line list, cross-section table, or CIA table into coefficient planes. |
//   evaluateLut rebuilds the pressure/temperature basis for one support row and interpolates between          |
//   wavelength planes.                                                                                        |
//                                                                                                             |
// hot reads                                                                                                   |
//   Support-row optical-property evaluation repeatedly calls sigmaAt and dSigmaDTemperatureAt. The small      |
//   basis arrays stay on the stack; coefficient and wavelength data stay out-of-line behind this header.      |
//                                                                                                             |
// ownership                                                                                                   |
//   clone and buildFromSource allocate wavelength and coefficient arrays. deinitOwned releases those arrays.  |
// ------------------------------------------------------------------------------------------------------------|

// OperationalCrossSectionLut ---------------------------------------------------------------------------------|
// Header for one operational cross-section lookup table.                                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 72 B (0.070 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] wavelengths_nm                : []const f64                                                        |
// [16..31] coefficients                  : []const f64                                                        |
// [32..39] min_temperature_k             : f64                                                                |
// [40..47] max_temperature_k             : f64                                                                |
// [48..55] min_pressure_hpa              : f64                                                                |
// [56..63] max_pressure_hpa              : f64                                                                |
// [64..64] temperature_coefficient_count : u8                                                                 |
// [65..65] pressure_coefficient_count    : u8                                                                 |
// [66..71] trailing padding              : 6 B                                                                |
//                                                                                                             |
// referenced storage                                                                                          |
//   wavelengths_nm and coefficients point at borrowed parser slices or arrays owned by clone/buildFromSource. |
//                                                                                                             |
// unused bits: 48 padding + 0 bool-storage slack = 48 bits                                                    |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 72 B (0.070 KiB); referenced wavelength/coefficient arrays are out-of-line.       |
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

    pub fn buildFromSource(
        allocator: Allocator,
        wavelengths_nm: []const f64,
        source: GenerationSource,
        controls: LutControls.XsecControls,
    ) !OperationalCrossSectionLut {
        return buildLutFromSource(
            OperationalCrossSectionLut,
            allocator,
            wavelengths_nm,
            source,
            controls,
        );
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
        // OperationalCrossSectionLut.sigmaAt -----------------------------------------------------------------|
        // Returns sigma from the shared LUT evaluator for one support row.                                    |
        //                                                                                                     |
        // hot path                                                                                            |
        //   repeated : support-row cross-section evaluation                                                   |
        //   reads    : coefficient storage, wavelength, temperature, pressure                                 |
        //   output   : sigma                                                                                  |
        // ----------------------------------------------------------------------------------------------------|

        return evaluateLut(@This(), self, wavelength_nm, temperature_k, pressure_hpa).sigma;
    }

    pub fn dSigmaDTemperatureAt(
        self: *const OperationalCrossSectionLut,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) f64 {
        // OperationalCrossSectionLut.dSigmaDTemperatureAt ----------------------------------------------------|
        // Returns dSigma/dT from the shared LUT evaluator for one support row.                                |
        //                                                                                                     |
        // hot path                                                                                            |
        //   repeated : support-row cross-section derivative evaluation                                        |
        //   reads    : coefficient storage, wavelength, temperature, pressure                                 |
        //   output   : dSigma/dT                                                                              |
        // ----------------------------------------------------------------------------------------------------|

        return evaluateLut(@This(), self, wavelength_nm, temperature_k, pressure_hpa).d_sigma_d_temperature;
    }
};
// ------------------------------------------------------------------------------------------------------------|

fn fillLegendreValues(values: []f64, scaled_coordinate: f64) void {
    // fillLegendreValues -------------------------------------------------------------------------------------|
    // Fills Legendre recurrence values for one scaled coordinate.                                             |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : each pressure/temperature basis build during LUT evaluation                                |
    //   writes   : caller-owned basis output slice                                                            |
    //   reads    : scaled coordinate                                                                          |
    // --------------------------------------------------------------------------------------------------------|

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
    // fillLegendreTemperatureDerivative ----------------------------------------------------------------------|
    // Fills derivative basis values for the temperature coordinate.                                           |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : each dSigma/dT LUT evaluation                                                              |
    //   reads    : Legendre values, scaled coordinate, temperature bounds                                     |
    //   writes   : caller-owned derivative basis slice                                                        |
    // --------------------------------------------------------------------------------------------------------|

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

pub const GenerationSource = union(enum) {
    line_list: *const ReferenceData.SpectroscopyLineList,
    cross_section_table: *const ReferenceData.CrossSectionTable,
    cia_table: *const ReferenceData.CollisionInducedAbsorptionTable,
};

fn buildLutFromSource(
    comptime LutType: type,
    allocator: Allocator,
    wavelengths_nm: []const f64,
    source: GenerationSource,
    controls: LutControls.XsecControls,
) !LutType {
    try controls.validate();
    if (controls.mode == .direct or controls.mode == .consume or wavelengths_nm.len == 0) {
        return @import("../../common/errors.zig").Error.InvalidRequest;
    }
    if (controls.temperature_coefficient_count > max_operational_refspec_temperature_coefficients or
        controls.pressure_coefficient_count > max_operational_refspec_pressure_coefficients)
    {
        return @import("../../common/errors.zig").Error.InvalidRequest;
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
    const coefficients = try allocator.alloc(
        f64,
        wavelengths_nm.len * temperature_coefficient_count * pressure_coefficient_count,
    );
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

            const prepared_state = if (prepared_line_state) |*state| state else null;

            for (wavelengths_nm, 0..) |wavelength_nm, wavelength_index| {
                const sample_offset = sampleIndex(
                    temperature_index,
                    pressure_index,
                    wavelength_index,
                    pressure_grid_count,
                    wavelengths_nm.len,
                );

                samples[sample_offset] = sampleSigmaAtSource(
                    source,
                    wavelength_nm,
                    temperatures_k[temperature_index],
                    pressures_hpa[pressure_index],
                    prepared_state,
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

    const lut: LutType = .{
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

// Evaluation -------------------------------------------------------------------------------------------------|
// One LUT evaluation result.                                                                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] sigma                 : f64                                                                        |
// [ 8..15] d_sigma_d_temperature : f64                                                                        |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); stack or return value                                           |
const Evaluation = struct {
    sigma: f64,
    d_sigma_d_temperature: f64,
};
// ------------------------------------------------------------------------------------------------------------|

fn evaluateLut(
    comptime LutType: type,
    self: *const LutType,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) Evaluation {
    // evaluateLut --------------------------------------------------------------------------------------------|
    // Evaluates one operational cross-section LUT at wavelength, temperature, and pressure.                   |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : support-row carrier evaluation                                                             |
    //   reads    : coefficient storage, wavelength grid, temperature/pressure bounds                          |
    //   stack    : bounded Legendre basis arrays                                                              |
    //   calls    : wavelengthBracket, evaluateAtIndex                                                         |
    // --------------------------------------------------------------------------------------------------------|

    if (!self.enabled()) {
        return .{
            .sigma = 0.0,
            .d_sigma_d_temperature = 0.0,
        };
    }

    var legendre_lnT = [_]f64{0.0} ** max_operational_refspec_temperature_coefficients;
    var legendre_lnp = [_]f64{0.0} ** max_operational_refspec_pressure_coefficients;
    var derivative_legendre_lnT = [_]f64{0.0} ** max_operational_refspec_temperature_coefficients;

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

    const bracket = wavelengthBracket(LutType, self, wavelength_nm);
    const temperature_basis = legendre_lnT[0..@as(usize, self.temperature_coefficient_count)];
    const pressure_basis = legendre_lnp[0..@as(usize, self.pressure_coefficient_count)];
    const derivative_temperature_basis =
        derivative_legendre_lnT[0..@as(usize, self.temperature_coefficient_count)];

    const left_sigma = evaluateAtIndex(
        LutType,
        self,
        bracket.left_index,
        temperature_basis,
        pressure_basis,
    );

    const right_sigma = choose_right_sigma: {
        if (bracket.left_index == bracket.right_index) break :choose_right_sigma left_sigma;

        break :choose_right_sigma evaluateAtIndex(
            LutType,
            self,
            bracket.right_index,
            temperature_basis,
            pressure_basis,
        );
    };

    const left_derivative = evaluateAtIndex(
        LutType,
        self,
        bracket.left_index,
        derivative_temperature_basis,
        pressure_basis,
    );

    const right_derivative = choose_right_derivative: {
        if (bracket.left_index == bracket.right_index) break :choose_right_derivative left_derivative;

        break :choose_right_derivative evaluateAtIndex(
            LutType,
            self,
            bracket.right_index,
            derivative_temperature_basis,
            pressure_basis,
        );
    };

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
    // evaluateAtIndex ----------------------------------------------------------------------------------------|
    // Reduces pressure and temperature coefficient products into one sigma value.                             |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : left and right wavelength bracket samples                                                  |
    //   reads    : flattened coefficient grid and Legendre basis slices                                       |
    //   math     : sum coefficient[wavelength, pressure, temperature] * T_basis * p_basis                     |
    // --------------------------------------------------------------------------------------------------------|

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
    const has_valid_bounds = minimum > 0.0 and maximum > 0.0;
    if (!has_valid_bounds) return 0.0;

    const ln_max = @log(maximum);
    const ln_min = @log(minimum);
    const scale = ln_max - ln_min;

    if (scale == 0.0) return 0.0;

    const safe_value = choose_safe_value: {
        if (value > 0.0) break :choose_safe_value value;
        break :choose_safe_value minimum;
    };

    return -((ln_max + ln_min) / scale) + (2.0 * @log(safe_value) / scale);
}

fn wavelengthBracket(
    comptime LutType: type,
    self: *const LutType,
    wavelength_nm: f64,
) struct { left_index: usize, right_index: usize, weight: f64 } {
    // wavelengthBracket --------------------------------------------------------------------------------------|
    // Finds adjacent coefficient planes and the interpolation weight for one wavelength.                      |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : each LUT evaluation                                                                        |
    //   reads    : wavelength grid and target wavelength                                                      |
    //   output   : bracket indexes and interpolation weight                                                   |
    //                                                                                                         |
    // layout(64-bit)                                                                                          |
    // anonymous return struct: size 24 B (0.023 KiB), align: 8 B                                              |
    // [ 0.. 7] left_index  : usize                                                                            |
    // [ 8..15] right_index : usize                                                                            |
    // [16..23] weight      : f64                                                                              |
    // --------------------------------------------------------------------------------------------------------|

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

    for (
        self.wavelengths_nm[0 .. self.wavelengths_nm.len - 1],
        self.wavelengths_nm[1..],
        0..,
    ) |left_nm, right_nm, index| {
        if (wavelength_nm <= right_nm) {
            const span = right_nm - left_nm;
            const weight = if (span == 0.0) 0.0 else (wavelength_nm - left_nm) / span;

            return .{
                .left_index = index,
                .right_index = index + 1,
                .weight = weight,
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
