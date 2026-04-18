//! Purpose:
//!   Define the top-level typed instrument contract after splitting the
//!   measurement-pipeline controls into their own module.

const std = @import("std");
const errors = @import("../../core/errors.zig");
const Allocator = std.mem.Allocator;
const constants = @import("constants.zig");
const id_mod = @import("id.zig");
const reference_grid = @import("reference_grid.zig");
const solar_spectrum = @import("solar_spectrum.zig");
const cross_section_lut = @import("cross_section_lut.zig");
const pipeline = @import("pipeline.zig");

pub const max_line_shape_samples = constants.max_line_shape_samples;
pub const max_line_shape_nominals = constants.max_line_shape_nominals;
pub const max_operational_refspec_temperature_coefficients = constants.max_operational_refspec_temperature_coefficients;
pub const max_operational_refspec_pressure_coefficients = constants.max_operational_refspec_pressure_coefficients;

pub const Id = id_mod.Id;
pub const OperationalReferenceGrid = reference_grid.OperationalReferenceGrid;
pub const AdaptiveReferenceGrid = reference_grid.AdaptiveReferenceGrid;
pub const OperationalSolarSpectrum = solar_spectrum.OperationalSolarSpectrum;
pub const OperationalCrossSectionLut = cross_section_lut.OperationalCrossSectionLut;
pub const SpectralChannel = pipeline.SpectralChannel;
pub const BuiltinLineShapeKind = pipeline.BuiltinLineShapeKind;
pub const InstrumentLineShape = pipeline.InstrumentLineShape;
pub const InstrumentLineShapeTable = pipeline.InstrumentLineShapeTable;

pub const Instrument = struct {
    pub const SamplingMode = pipeline.SamplingMode;
    pub const NoiseModelKind = pipeline.NoiseModelKind;
    pub const SlitIndex = pipeline.SlitIndex;
    pub const NodalCorrection = pipeline.NodalCorrection;
    pub const SpectralResponse = pipeline.SpectralResponse;
    pub const SimpleOffsets = pipeline.SimpleOffsets;
    pub const SinusoidalFeatures = pipeline.SinusoidalFeatures;
    pub const NoiseControls = pipeline.NoiseControls;
    pub const SpectralChannelControls = pipeline.SpectralChannelControls;
    pub const RingControls = pipeline.RingControls;
    pub const ReflectanceCalibration = pipeline.ReflectanceCalibration;
    pub const MeasurementPipeline = pipeline.MeasurementPipeline;

    pub const OperationalBandSupport = struct {
        id: []const u8 = "",
        owns_id: bool = false,
        high_resolution_step_nm: f64 = 0.0,
        high_resolution_half_span_nm: f64 = 0.0,
        instrument_line_shape: InstrumentLineShape = .{},
        instrument_line_shape_table: InstrumentLineShapeTable = .{},
        operational_refspec_grid: OperationalReferenceGrid = .{},
        operational_solar_spectrum: OperationalSolarSpectrum = .{},
        o2_operational_lut: OperationalCrossSectionLut = .{},
        o2o2_operational_lut: OperationalCrossSectionLut = .{},

        pub fn enabled(self: *const OperationalBandSupport) bool {
            return self.high_resolution_step_nm > 0.0 or
                self.high_resolution_half_span_nm > 0.0 or
                self.instrument_line_shape.sample_count > 0 or
                self.instrument_line_shape_table.nominal_count > 0 or
                self.operational_refspec_grid.enabled() or
                self.operational_solar_spectrum.enabled() or
                self.o2_operational_lut.enabled() or
                self.o2o2_operational_lut.enabled();
        }

        pub fn validate(self: *const OperationalBandSupport) errors.Error!void {
            if (self.high_resolution_step_nm < 0.0 or self.high_resolution_half_span_nm < 0.0) {
                return errors.Error.InvalidRequest;
            }
            if ((self.high_resolution_step_nm == 0.0) != (self.high_resolution_half_span_nm == 0.0)) {
                return errors.Error.InvalidRequest;
            }
            if (!self.enabled()) return;
            if (self.id.len == 0) return errors.Error.InvalidRequest;
            try self.instrument_line_shape.validate();
            try self.instrument_line_shape_table.validate();
            try self.operational_refspec_grid.validate();
            try self.operational_solar_spectrum.validate();
            try self.o2_operational_lut.validate();
            try self.o2o2_operational_lut.validate();
        }

        pub fn clone(self: OperationalBandSupport, allocator: Allocator) !OperationalBandSupport {
            const owned_id = if (self.id.len != 0)
                try allocator.dupe(u8, self.id)
            else
                "";
            errdefer if (owned_id.len != 0) allocator.free(owned_id);

            const line_shape = try self.instrument_line_shape.clone(allocator);
            errdefer {
                var cleanup = line_shape;
                cleanup.deinitOwned(allocator);
            }
            const line_shape_table = try self.instrument_line_shape_table.clone(allocator);
            errdefer {
                var cleanup = line_shape_table;
                cleanup.deinitOwned(allocator);
            }
            const refspec_grid = try self.operational_refspec_grid.clone(allocator);
            errdefer {
                var cleanup = refspec_grid;
                cleanup.deinitOwned(allocator);
            }
            const resolved_solar_spectrum = try self.operational_solar_spectrum.clone(allocator);
            errdefer {
                var cleanup = resolved_solar_spectrum;
                cleanup.deinitOwned(allocator);
            }
            const o2_lut = try self.o2_operational_lut.clone(allocator);
            errdefer {
                var cleanup = o2_lut;
                cleanup.deinitOwned(allocator);
            }
            const o2o2_lut = try self.o2o2_operational_lut.clone(allocator);
            errdefer {
                var cleanup = o2o2_lut;
                cleanup.deinitOwned(allocator);
            }

            return .{
                .id = owned_id,
                .owns_id = owned_id.len != 0,
                .high_resolution_step_nm = self.high_resolution_step_nm,
                .high_resolution_half_span_nm = self.high_resolution_half_span_nm,
                .instrument_line_shape = line_shape,
                .instrument_line_shape_table = line_shape_table,
                .operational_refspec_grid = refspec_grid,
                .operational_solar_spectrum = resolved_solar_spectrum,
                .o2_operational_lut = o2_lut,
                .o2o2_operational_lut = o2o2_lut,
            };
        }

        pub fn deinitOwned(self: *OperationalBandSupport, allocator: Allocator) void {
            if (self.owns_id and self.id.len != 0) allocator.free(self.id);
            self.instrument_line_shape.deinitOwned(allocator);
            self.instrument_line_shape_table.deinitOwned(allocator);
            self.operational_refspec_grid.deinitOwned(allocator);
            self.operational_solar_spectrum.deinitOwned(allocator);
            self.o2_operational_lut.deinitOwned(allocator);
            self.o2o2_operational_lut.deinitOwned(allocator);
            self.* = .{};
        }
    };

    id: Id = .generic,
    sampling: pipeline.SamplingMode = .native,
    noise_model: pipeline.NoiseModelKind = .none,
    wavelength_shift_nm: f64 = 0.0,
    instrument_line_fwhm_nm: f64 = 0.0,
    builtin_line_shape: pipeline.BuiltinLineShapeKind = .gaussian,
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
