const std = @import("std");
const errors = @import("../core/errors.zig");
const Binding = @import("Binding.zig").Binding;
const Instrument = @import("Instrument.zig").Instrument;
const BuiltinLineShapeKind = @import("Instrument.zig").BuiltinLineShapeKind;
const InstrumentLineShape = @import("Instrument.zig").InstrumentLineShape;
const InstrumentLineShapeTable = @import("Instrument.zig").InstrumentLineShapeTable;
const OperationalReferenceGrid = @import("Instrument.zig").OperationalReferenceGrid;
const OperationalSolarSpectrum = @import("Instrument.zig").OperationalSolarSpectrum;
const OperationalCrossSectionLut = @import("Instrument.zig").OperationalCrossSectionLut;
const Allocator = std.mem.Allocator;

pub const ObservationRegime = enum {
    nadir,
    limb,
    occultation,
};

pub const ObservationModel = struct {
    instrument: []const u8 = "generic",
    response_provider: []const u8 = "",
    regime: ObservationRegime = .nadir,
    sampling: []const u8 = "native",
    noise_model: []const u8 = "none",
    wavelength_shift_nm: f64 = 0.0,
    multiplicative_offset: f64 = 1.0,
    stray_light: f64 = 0.0,
    instrument_line_fwhm_nm: f64 = 0.0,
    builtin_line_shape: BuiltinLineShapeKind = .gaussian,
    high_resolution_step_nm: f64 = 0.0,
    high_resolution_half_span_nm: f64 = 0.0,
    solar_spectrum_source: Binding = .{},
    weighted_reference_grid_source: Binding = .{},
    instrument_line_shape: InstrumentLineShape = .{},
    instrument_line_shape_table: InstrumentLineShapeTable = .{},
    operational_refspec_grid: OperationalReferenceGrid = .{},
    operational_solar_spectrum: OperationalSolarSpectrum = .{},
    o2_operational_lut: OperationalCrossSectionLut = .{},
    o2o2_operational_lut: OperationalCrossSectionLut = .{},
    ingested_noise_sigma: []const f64 = &.{},

    pub fn resolvedSampling(self: *const ObservationModel) errors.Error!Instrument.SamplingMode {
        if (std.mem.eql(u8, self.sampling, "native")) return .native;
        if (std.mem.eql(u8, self.sampling, "operational")) return .operational;
        if (std.mem.eql(u8, self.sampling, "measured_channels")) return .measured_channels;
        if (std.mem.eql(u8, self.sampling, "synthetic")) return .synthetic;
        return errors.Error.InvalidRequest;
    }

    pub fn resolvedNoiseModel(self: *const ObservationModel) errors.Error!Instrument.NoiseModelKind {
        if (std.mem.eql(u8, self.noise_model, "none")) return .none;
        if (std.mem.eql(u8, self.noise_model, "shot_noise")) return .shot_noise;
        if (std.mem.eql(u8, self.noise_model, "s5p_operational")) return .s5p_operational;
        if (std.mem.eql(u8, self.noise_model, "snr_from_input")) return .snr_from_input;
        return errors.Error.InvalidRequest;
    }

    pub fn validate(self: *const ObservationModel) errors.Error!void {
        try self.solar_spectrum_source.validate();
        try self.weighted_reference_grid_source.validate();
        if (self.instrument.len == 0) {
            return errors.Error.MissingObservationInstrument;
        }
        if (self.sampling.len == 0 or self.noise_model.len == 0) {
            return errors.Error.InvalidRequest;
        }
        if (!std.math.isFinite(self.multiplicative_offset) or self.multiplicative_offset <= 0.0) {
            return errors.Error.InvalidRequest;
        }
        if (!std.math.isFinite(self.stray_light)) {
            return errors.Error.InvalidRequest;
        }
        for (self.ingested_noise_sigma) |value| {
            if (!std.math.isFinite(value) or value <= 0.0) {
                return errors.Error.InvalidRequest;
            }
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

    pub fn deinitOwned(self: *ObservationModel, allocator: Allocator) void {
        self.instrument_line_shape.deinitOwned(allocator);
        self.instrument_line_shape_table.deinitOwned(allocator);
        self.operational_refspec_grid.deinitOwned(allocator);
        self.operational_solar_spectrum.deinitOwned(allocator);
        self.o2_operational_lut.deinitOwned(allocator);
        self.o2o2_operational_lut.deinitOwned(allocator);
        if (self.ingested_noise_sigma.len != 0) allocator.free(self.ingested_noise_sigma);
        self.ingested_noise_sigma = &.{};
    }
};

test "observation model carries calibration and supporting-data bindings" {
    const model: ObservationModel = .{
        .instrument = "tropomi",
        .response_provider = "builtin.generic_response",
        .solar_spectrum_source = .{ .kind = .bundle_default },
        .weighted_reference_grid_source = .{ .kind = .ingest, .name = "refspec_demo.grid" },
        .sampling = "operational",
        .noise_model = "shot_noise",
        .multiplicative_offset = 1.002,
        .stray_light = 0.0007,
    };

    try std.testing.expectEqual(Instrument.SamplingMode.operational, try model.resolvedSampling());
    try std.testing.expectEqual(Instrument.NoiseModelKind.shot_noise, try model.resolvedNoiseModel());
    try model.validate();

    try std.testing.expectError(errors.Error.InvalidRequest, (ObservationModel{
        .instrument = "tropomi",
        .sampling = "unexpected_sampling",
        .noise_model = "none",
    }).validate());
}
