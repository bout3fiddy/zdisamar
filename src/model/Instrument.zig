const std = @import("std");
const errors = @import("../core/errors.zig");
const Allocator = std.mem.Allocator;
const constants = @import("instrument/constants.zig");

pub const max_line_shape_samples = constants.max_line_shape_samples;
pub const max_line_shape_nominals = constants.max_line_shape_nominals;
pub const max_operational_refspec_temperature_coefficients = constants.max_operational_refspec_temperature_coefficients;
pub const max_operational_refspec_pressure_coefficients = constants.max_operational_refspec_pressure_coefficients;

pub const OperationalReferenceGrid = @import("instrument/reference_grid.zig").OperationalReferenceGrid;
pub const AdaptiveReferenceGrid = @import("instrument/reference_grid.zig").AdaptiveReferenceGrid;
pub const OperationalSolarSpectrum = @import("instrument/solar_spectrum.zig").OperationalSolarSpectrum;
pub const OperationalCrossSectionLut = @import("instrument/cross_section_lut.zig").OperationalCrossSectionLut;
pub const InstrumentLineShape = @import("instrument/line_shape.zig").InstrumentLineShape;
pub const InstrumentLineShapeTable = @import("instrument/line_shape.zig").InstrumentLineShapeTable;
pub const BuiltinLineShapeKind = @import("instrument/line_shape.zig").BuiltinLineShapeKind;

pub const Id = union(enum) {
    unset,
    generic,
    tropomi,
    synthetic,
    custom: []const u8,

    pub fn parse(value: []const u8) Id {
        if (value.len == 0) return .unset;
        if (std.mem.eql(u8, value, "generic")) return .generic;
        if (std.mem.eql(u8, value, "tropomi")) return .tropomi;
        if (std.mem.eql(u8, value, "synthetic")) return .synthetic;
        return .{ .custom = value };
    }

    pub fn label(self: Id) []const u8 {
        return switch (self) {
            .unset => "",
            .generic => "generic",
            .tropomi => "tropomi",
            .synthetic => "synthetic",
            .custom => |value| value,
        };
    }

    pub fn validate(self: Id) errors.Error!void {
        switch (self) {
            .unset => return errors.Error.MissingObservationInstrument,
            .custom => |value| if (value.len == 0) return errors.Error.MissingObservationInstrument,
            .generic, .tropomi, .synthetic => {},
        }
    }
};

pub const Instrument = struct {
    pub const SamplingMode = enum {
        native,
        operational,
        measured_channels,
        synthetic,

        pub fn parse(value: []const u8) errors.Error!SamplingMode {
            if (std.mem.eql(u8, value, "native")) return .native;
            if (std.mem.eql(u8, value, "operational")) return .operational;
            if (std.mem.eql(u8, value, "measured_channels")) return .measured_channels;
            if (std.mem.eql(u8, value, "synthetic")) return .synthetic;
            return errors.Error.InvalidRequest;
        }

        pub fn label(self: SamplingMode) []const u8 {
            return @tagName(self);
        }
    };

    pub const NoiseModelKind = enum {
        none,
        shot_noise,
        s5p_operational,
        snr_from_input,

        pub fn parse(value: []const u8) errors.Error!NoiseModelKind {
            if (std.mem.eql(u8, value, "none")) return .none;
            if (std.mem.eql(u8, value, "shot_noise")) return .shot_noise;
            if (std.mem.eql(u8, value, "s5p_operational")) return .s5p_operational;
            if (std.mem.eql(u8, value, "snr_from_input")) return .snr_from_input;
            return errors.Error.InvalidRequest;
        }

        pub fn label(self: NoiseModelKind) []const u8 {
            return @tagName(self);
        }
    };

    id: Id = .generic,
    sampling: SamplingMode = .native,
    noise_model: NoiseModelKind = .none,
    wavelength_shift_nm: f64 = 0.0,
    instrument_line_fwhm_nm: f64 = 0.0,
    builtin_line_shape: BuiltinLineShapeKind = .gaussian,
    high_resolution_step_nm: f64 = 0.0,
    high_resolution_half_span_nm: f64 = 0.0,
    instrument_line_shape: InstrumentLineShape = .{},
    instrument_line_shape_table: InstrumentLineShapeTable = .{},
    operational_refspec_grid: OperationalReferenceGrid = .{},
    operational_solar_spectrum: OperationalSolarSpectrum = .{},
    o2_operational_lut: OperationalCrossSectionLut = .{},
    o2o2_operational_lut: OperationalCrossSectionLut = .{},

    pub fn validate(self: *const Instrument) errors.Error!void {
        try self.id.validate();
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
        self.instrument_line_shape.deinitOwned(allocator);
        self.instrument_line_shape_table.deinitOwned(allocator);
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
    try std.testing.expectError(errors.Error.InvalidRequest, Instrument.SamplingMode.parse("mystery_mode"));
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

    try std.testing.expectError(errors.Error.InvalidRequest, invalid.validate());
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
    try std.testing.expectError(errors.Error.InvalidRequest, invalid_grid.validate());

    const invalid_solar: Instrument = .{
        .id = .tropomi,
        .sampling = .operational,
        .noise_model = .s5p_operational,
        .operational_solar_spectrum = .{
            .wavelengths_nm = &[_]f64{ 760.8, 760.8 },
            .irradiance = &[_]f64{ 2.7e14, 2.8e14 },
        },
    };
    try std.testing.expectError(errors.Error.InvalidRequest, invalid_solar.validate());

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
    try std.testing.expectError(errors.Error.InvalidRequest, invalid_lut.validate());
}
