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
    sampling: Instrument.SamplingMode = .native,
    noise_model: Instrument.NoiseModelKind = .none,
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
    measured_wavelengths_nm: []const f64 = &.{},
    owns_measured_wavelengths: bool = false,
    reference_radiance: []const f64 = &.{},
    owns_reference_radiance: bool = false,
    ingested_noise_sigma: []const f64 = &.{},

    pub fn validate(self: *const ObservationModel) errors.Error!void {
        try self.solar_spectrum_source.validate();
        try self.weighted_reference_grid_source.validate();
        if (self.instrument.len == 0) {
            return errors.Error.MissingObservationInstrument;
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
        for (self.reference_radiance) |value| {
            if (!std.math.isFinite(value) or value < 0.0) {
                return errors.Error.InvalidRequest;
            }
        }
        switch (self.noise_model) {
            .snr_from_input, .s5p_operational => {
                if (self.ingested_noise_sigma.len == 0) return errors.Error.InvalidRequest;
            },
            .none, .shot_noise => {},
        }
        if (self.noise_model == .s5p_operational and self.reference_radiance.len != self.ingested_noise_sigma.len) {
            return errors.Error.InvalidRequest;
        }
        if (self.measured_wavelengths_nm.len != 0) {
            var previous_wavelength: ?f64 = null;
            for (self.measured_wavelengths_nm) |wavelength_nm| {
                if (!std.math.isFinite(wavelength_nm)) return errors.Error.InvalidRequest;
                if (previous_wavelength) |previous| {
                    if (wavelength_nm <= previous) return errors.Error.InvalidRequest;
                }
                previous_wavelength = wavelength_nm;
            }
            if (self.ingested_noise_sigma.len != 0 and self.ingested_noise_sigma.len != self.measured_wavelengths_nm.len) {
                return errors.Error.InvalidRequest;
            }
        }
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
        if (self.owns_measured_wavelengths and self.measured_wavelengths_nm.len != 0) allocator.free(self.measured_wavelengths_nm);
        self.measured_wavelengths_nm = &.{};
        self.owns_measured_wavelengths = false;
        if (self.owns_reference_radiance and self.reference_radiance.len != 0) allocator.free(self.reference_radiance);
        self.reference_radiance = &.{};
        self.owns_reference_radiance = false;
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
        .sampling = .operational,
        .noise_model = .shot_noise,
        .multiplicative_offset = 1.002,
        .stray_light = 0.0007,
    };

    try std.testing.expectEqual(Instrument.SamplingMode.operational, model.sampling);
    try std.testing.expectEqual(Instrument.NoiseModelKind.shot_noise, model.noise_model);
    try model.validate();
}

test "observation model carries explicit measured-channel wavelengths" {
    const measured_wavelengths = [_]f64{ 760.8, 761.02, 761.31 };
    const model: ObservationModel = .{
        .instrument = "tropomi",
        .sampling = .measured_channels,
        .noise_model = .snr_from_input,
        .measured_wavelengths_nm = &measured_wavelengths,
        .reference_radiance = &.{ 1.2, 1.1, 1.0 },
        .ingested_noise_sigma = &.{ 0.02, 0.03, 0.025 },
    };

    try model.validate();
    try std.testing.expectEqual(@as(f64, 761.02), model.measured_wavelengths_nm[1]);
}
