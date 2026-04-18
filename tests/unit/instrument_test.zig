const std = @import("std");
const internal = @import("internal");
const InstrumentModel = internal.instrument;

const Instrument = InstrumentModel.Instrument;
const OperationalCrossSectionLut = InstrumentModel.OperationalCrossSectionLut;

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
        .id = .synthetic,
        .sampling = .measured_channels,
        .noise_model = .snr_from_input,
        .high_resolution_step_nm = 0.08,
        .high_resolution_half_span_nm = 0.32,
    };

    try std.testing.expectEqual(Instrument.SamplingMode.measured_channels, instrument.sampling);
    try std.testing.expectEqual(Instrument.NoiseModelKind.snr_from_input, instrument.noise_model);
    try instrument.validate();

    try std.testing.expectEqual(Instrument.SamplingMode.synthetic, try Instrument.SamplingMode.parse("synthetic"));
    try std.testing.expectEqual(Instrument.NoiseModelKind.none, try Instrument.NoiseModelKind.parse("none"));
    try std.testing.expectError(error.InvalidRequest, Instrument.SamplingMode.parse("mystery_mode"));
}

test "instrument validation rejects malformed operational lut surfaces" {
    const invalid: Instrument = .{
        .id = .{ .custom = "test" },
        .sampling = .operational,
        .noise_model = .s5p_operational,
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

    try std.testing.expectError(error.InvalidRequest, invalid.validate());
}

test "operational band support rejects malformed inert hr-grid controls" {
    const negative_step: Instrument.OperationalBandSupport = .{
        .high_resolution_step_nm = -0.08,
        .high_resolution_half_span_nm = -0.32,
    };
    try std.testing.expectError(error.InvalidRequest, negative_step.validate());

    const one_sided_grid: Instrument.OperationalBandSupport = .{
        .high_resolution_step_nm = 0.08,
        .high_resolution_half_span_nm = 0.0,
    };
    try std.testing.expectError(error.InvalidRequest, one_sided_grid.validate());
}

test "noise controls validation rejects one-sided tables" {
    const snr_missing_wavelengths: Instrument.NoiseControls = .{
        .enabled = true,
        .model = .snr_from_input,
        .snr_values = &[_]f64{100.0},
    };
    try std.testing.expectError(error.InvalidRequest, snr_missing_wavelengths.validate());

    const reference_missing_signal: Instrument.NoiseControls = .{
        .enabled = true,
        .model = .s5p_operational,
        .reference_sigma = &[_]f64{1.0},
    };
    try std.testing.expectError(error.InvalidRequest, reference_missing_signal.validate());
}

test "operational reference grid and solar spectrum validate typed external inputs" {
    const instrument: Instrument = .{
        .id = .tropomi,
        .sampling = .operational,
        .noise_model = .s5p_operational,
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
        .id = .tropomi,
        .sampling = .operational,
        .noise_model = .s5p_operational,
        .operational_refspec_grid = .{
            .wavelengths_nm = &[_]f64{ 760.8, 760.8 },
            .weights = &[_]f64{ 0.5, 0.5 },
        },
    };
    try std.testing.expectError(error.InvalidRequest, invalid_grid.validate());

    const invalid_solar: Instrument = .{
        .id = .tropomi,
        .sampling = .operational,
        .noise_model = .s5p_operational,
        .operational_solar_spectrum = .{
            .wavelengths_nm = &[_]f64{ 760.8, 760.8 },
            .irradiance = &[_]f64{ 2.7e14, 2.8e14 },
        },
    };
    try std.testing.expectError(error.InvalidRequest, invalid_solar.validate());

    const invalid_lut: Instrument = .{
        .id = .tropomi,
        .sampling = .operational,
        .noise_model = .s5p_operational,
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
    try std.testing.expectError(error.InvalidRequest, invalid_lut.validate());
}
