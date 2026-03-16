const std = @import("std");
const errors = @import("../core/errors.zig");
const Binding = @import("Binding.zig").Binding;
const Instrument = @import("Instrument.zig").Instrument;
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

    pub fn instrumentSpec(self: ObservationModel) Instrument {
        return .{
            .name = self.instrument,
            .sampling = self.sampling,
            .noise_model = self.noise_model,
            .wavelength_shift_nm = self.wavelength_shift_nm,
            .instrument_line_fwhm_nm = self.instrument_line_fwhm_nm,
            .high_resolution_step_nm = self.high_resolution_step_nm,
            .high_resolution_half_span_nm = self.high_resolution_half_span_nm,
            .instrument_line_shape = self.instrument_line_shape,
            .instrument_line_shape_table = self.instrument_line_shape_table,
            .operational_refspec_grid = self.operational_refspec_grid,
            .operational_solar_spectrum = self.operational_solar_spectrum,
            .o2_operational_lut = self.o2_operational_lut,
            .o2o2_operational_lut = self.o2o2_operational_lut,
        };
    }

    pub fn resolvedSampling(self: ObservationModel) errors.Error!Instrument.SamplingMode {
        return self.instrumentSpec().resolvedSampling();
    }

    pub fn resolvedNoiseModel(self: ObservationModel) errors.Error!Instrument.NoiseModelKind {
        return self.instrumentSpec().resolvedNoiseModel();
    }

    pub fn validate(self: ObservationModel) errors.Error!void {
        try self.solar_spectrum_source.validate();
        try self.weighted_reference_grid_source.validate();
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
        try self.instrumentSpec().validate();
    }

    pub fn deinitOwned(self: *ObservationModel, allocator: Allocator) void {
        var instrument = self.instrumentSpec();
        instrument.deinitOwned(allocator);
        self.operational_refspec_grid = instrument.operational_refspec_grid;
        self.operational_solar_spectrum = instrument.operational_solar_spectrum;
        self.o2_operational_lut = instrument.o2_operational_lut;
        self.o2o2_operational_lut = instrument.o2o2_operational_lut;
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
