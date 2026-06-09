const std = @import("std");
const errors = @import("../common/errors.zig");
const Allocator = std.mem.Allocator;
const constants = @import("instrument/constants.zig");
const reference_grid = @import("instrument/reference_grid.zig");
const solar_spectrum = @import("instrument/solar_spectrum.zig");
const cross_section_lut = @import("instrument/cross_section_lut.zig");
const pipeline = @import("instrument/pipeline.zig");

// Instrument.zig ---------------------------------------------------------------------------------------------|
// Public instrument input model and re-export surface for instrument support data.                            |
//                                                                                                             |
// data                                                                                                        |
//   Instrument stores native sampling controls plus optional operational grids, solar spectra, line-shape     |
//   tables, and generated O2/O2-O2 cross-section LUT headers. OperationalBandSupport is the band-local owner  |
//   used when the same support data is carried beside a resolved O2 A band.                                   |
//                                                                                                             |
// ownership                                                                                                   |
//   Nested support structs own their referenced arrays after clone or preparation. OperationalBandSupport     |
//   also owns its id string when owns_id is true. deinitOwned walks the same nested support tree.             |
// ------------------------------------------------------------------------------------------------------------|

pub const max_line_shape_samples = constants.max_line_shape_samples;
pub const max_line_shape_nominals = constants.max_line_shape_nominals;
pub const max_operational_refspec_temperature_coefficients = constants.max_operational_refspec_temperature_coefficients;
pub const max_operational_refspec_pressure_coefficients = constants.max_operational_refspec_pressure_coefficients;

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

pub const OperationalReferenceGrid = reference_grid.OperationalReferenceGrid;
pub const AdaptiveReferenceGrid = reference_grid.AdaptiveReferenceGrid;
pub const OperationalSolarSpectrum = solar_spectrum.OperationalSolarSpectrum;
pub const OperationalCrossSectionLut = cross_section_lut.OperationalCrossSectionLut;
pub const SpectralChannel = pipeline.SpectralChannel;
pub const BuiltinLineShapeKind = pipeline.BuiltinLineShapeKind;
pub const InstrumentLineShape = pipeline.InstrumentLineShape;
pub const InstrumentLineShapeTable = pipeline.InstrumentLineShapeTable;

// Instrument -------------------------------------------------------------------------------------------------|
// Scene-level instrument controls and optional operational support headers.                                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 392 B (0.383 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 23] id                              : Id                                                             |
// [ 24.. 31] wavelength_shift_nm             : f64                                                            |
// [ 32.. 39] instrument_line_fwhm_nm         : f64                                                            |
// [ 40.. 47] high_resolution_step_nm         : f64                                                            |
// [ 48.. 55] high_resolution_half_span_nm    : f64                                                            |
// [ 56.. 95] instrument_line_shape           : InstrumentLineShape                                            |
// [ 96..151] instrument_line_shape_table     : InstrumentLineShapeTable                                       |
// [152..183] operational_refspec_grid        : OperationalReferenceGrid                                       |
// [184..239] operational_solar_spectrum      : OperationalSolarSpectrum                                       |
// [240..311] o2_operational_lut              : OperationalCrossSectionLut                                     |
// [312..383] o2o2_operational_lut            : OperationalCrossSectionLut                                     |
// [384..384] sampling                        : SamplingMode                                                   |
// [385..385] builtin_line_shape              : BuiltinLineShapeKind                                           |
// [386..391] trailing padding                : 6 B                                                            |
//                                                                                                             |
// referenced storage                                                                                          |
//   id may carry a custom borrowed string. Nested support headers carry their own referenced arrays.          |
//                                                                                                             |
// unused bits: 48 padding + 12 enum-storage slack = 60 bits                                                   |
// cache span: 7 cache lines at 64 B per line                                                                  |
// footprint: per instance = 392 B (0.383 KiB); total also includes nested support storage                     |
pub const Instrument = struct {
    pub const SamplingMode = pipeline.SamplingMode;
    pub const SlitIndex = pipeline.SlitIndex;
    pub const SpectralResponse = pipeline.SpectralResponse;
    pub const SpectralChannelControls = pipeline.SpectralChannelControls;

    // OperationalBandSupport ---------------------------------------------------------------------------------|
    // Band-local operational support bundle retained beside a resolved band.                                  |
    //                                                                                                         |
    // layout(64-bit)                                                                                          |
    // size: 368 B (0.359 KiB), align: 8 B                                                                     |
    //                                                                                                         |
    // memory                                                                                                  |
    // [  0.. 15] id                           : []const u8                                                    |
    // [ 16.. 23] high_resolution_step_nm      : f64                                                           |
    // [ 24.. 31] high_resolution_half_span_nm : f64                                                           |
    // [ 32.. 71] instrument_line_shape        : InstrumentLineShape                                           |
    // [ 72..127] instrument_line_shape_table  : InstrumentLineShapeTable                                      |
    // [128..159] operational_refspec_grid     : OperationalReferenceGrid                                      |
    // [160..215] operational_solar_spectrum   : OperationalSolarSpectrum                                      |
    // [216..287] o2_operational_lut           : OperationalCrossSectionLut                                    |
    // [288..359] o2o2_operational_lut         : OperationalCrossSectionLut                                    |
    // [360..360] owns_id                      : bool                                                          |
    // [361..367] trailing padding             : 7 B                                                           |
    //                                                                                                         |
    // referenced storage                                                                                      |
    //   id is owned only when owns_id is true. Nested support headers carry their own referenced arrays.      |
    //                                                                                                         |
    // unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                |
    // cache span: 6 cache lines at 64 B per line                                                              |
    // footprint: per instance = 368 B (0.359 KiB); total also includes nested support storage                 |
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
    // --------------------------------------------------------------------------------------------------------|

    id: Id = .generic,
    sampling: pipeline.SamplingMode = .native,
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
// ------------------------------------------------------------------------------------------------------------|
