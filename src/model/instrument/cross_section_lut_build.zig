const Allocator = @import("std").mem.Allocator;
const LutControls = @import("../../core/lut_controls.zig");
const ReferenceData = @import("../ReferenceData.zig");
const gauss_legendre = @import("../../kernels/quadrature/gauss_legendre.zig");
const constants = @import("constants.zig");
const basis = @import("cross_section_lut_basis.zig");

const max_operational_refspec_temperature_coefficients = constants.max_operational_refspec_temperature_coefficients;
const max_operational_refspec_pressure_coefficients = constants.max_operational_refspec_pressure_coefficients;

pub const GenerationSource = union(enum) {
    line_list: *const ReferenceData.SpectroscopyLineList,
    cross_section_table: *const ReferenceData.CrossSectionTable,
    cia_table: *const ReferenceData.CollisionInducedAbsorptionTable,
};

pub fn buildFromSource(
    comptime LutType: type,
    allocator: Allocator,
    wavelengths_nm: []const f64,
    source: GenerationSource,
    controls: LutControls.XsecControls,
) !LutType {
    try controls.validate();
    if (controls.mode == .direct or controls.mode == .consume or wavelengths_nm.len == 0) {
        return @import("../../core/errors.zig").Error.InvalidRequest;
    }
    if (controls.temperature_coefficient_count > max_operational_refspec_temperature_coefficients or
        controls.pressure_coefficient_count > max_operational_refspec_pressure_coefficients)
    {
        return @import("../../core/errors.zig").Error.InvalidRequest;
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
        basis.fillLegendreValues(
            legendre_lnT[temperature_index * temperature_coefficient_count ..][0..temperature_coefficient_count],
            scaled_lnT[temperature_index],
        );
    }
    for (0..pressure_grid_count) |pressure_index| {
        basis.fillLegendreValues(
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
