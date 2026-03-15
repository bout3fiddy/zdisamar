const errors = @import("../core/errors.zig");
const Instrument = @import("Instrument.zig").Instrument;
const InstrumentLineShape = @import("Instrument.zig").InstrumentLineShape;
const InstrumentLineShapeTable = @import("Instrument.zig").InstrumentLineShapeTable;
const OperationalReferenceGrid = @import("Instrument.zig").OperationalReferenceGrid;
const OperationalSolarSpectrum = @import("Instrument.zig").OperationalSolarSpectrum;
const OperationalCrossSectionLut = @import("Instrument.zig").OperationalCrossSectionLut;
const Allocator = @import("std").mem.Allocator;

pub const ObservationRegime = enum {
    nadir,
    limb,
    occultation,
};

pub const ObservationModel = struct {
    instrument: []const u8 = "generic",
    regime: ObservationRegime = .nadir,
    sampling: []const u8 = "native",
    noise_model: []const u8 = "none",
    wavelength_shift_nm: f64 = 0.0,
    instrument_line_fwhm_nm: f64 = 0.0,
    high_resolution_step_nm: f64 = 0.0,
    high_resolution_half_span_nm: f64 = 0.0,
    instrument_line_shape: InstrumentLineShape = .{},
    instrument_line_shape_table: InstrumentLineShapeTable = .{},
    operational_refspec_grid: OperationalReferenceGrid = .{},
    operational_solar_spectrum: OperationalSolarSpectrum = .{},
    o2_operational_lut: OperationalCrossSectionLut = .{},
    o2o2_operational_lut: OperationalCrossSectionLut = .{},

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

    pub fn validate(self: ObservationModel) errors.Error!void {
        try self.instrumentSpec().validate();
    }

    pub fn deinitOwned(self: *ObservationModel, allocator: Allocator) void {
        var instrument = self.instrumentSpec();
        instrument.deinitOwned(allocator);
        self.operational_refspec_grid = instrument.operational_refspec_grid;
        self.operational_solar_spectrum = instrument.operational_solar_spectrum;
        self.o2_operational_lut = instrument.o2_operational_lut;
        self.o2o2_operational_lut = instrument.o2o2_operational_lut;
    }
};
