const std = @import("std");
const errors = @import("../../common/errors.zig");
const Allocator = std.mem.Allocator;
const line_shape = @import("line_shape.zig");

// pipeline.zig -----------------------------------------------------------------------------------------------|
// Instrument spectral-response request types shared by scene input, observation-model resolution, and         |
// instrument-grid sampling. These rows describe what response to apply; compute code decides how to apply it. |
//                                                                                                             |
// called by                                                                                                   |
//   Instrument.zig re-exports these types for public input. ObservationModel.zig resolves scene defaults and  |
//   per-channel overrides into SpectralChannelControls. integration.zig turns SpectralResponse into sampling  |
//   kernels. implementations/instrument/calibration.zig turns channel controls into scalar calibration rows.  |
//                                                                                                             |
// main paths                                                                                                  |
//   SamplingMode        -> native, operational, measured-channel, or synthetic wavelength handling            |
//   SlitIndex           -> DISAMAR-compatible line-shape selector and builtin fallback kind                   |
//   SpectralResponse    -> FWHM, high-resolution grid, explicit line-shape kernels, and integration mode      |
//   SpectralChannelControls -> response plus wavelength shift, gain, offset, and stray-light controls         |
//                                                                                                             |
// validation boundary                                                                                         |
//   Validation rejects negative widths, half-configured high-resolution grids, invalid line-shape tables, and |
//   table slit requests with no explicit samples. It does not parse files or load support assets.             |
//                                                                                                             |
// ownership                                                                                                   |
//   Response structs own only nested line-shape storage. deinitOwned delegates to the nested line-shape       |
//   headers and then clears the response value.                                                               |
// ------------------------------------------------------------------------------------------------------------|

pub const BuiltinLineShapeKind = line_shape.BuiltinLineShapeKind;
pub const InstrumentLineShape = line_shape.InstrumentLineShape;
pub const InstrumentLineShapeTable = line_shape.InstrumentLineShapeTable;

pub const SpectralChannel = enum {
    radiance,
    irradiance,
};

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

pub const SlitIndex = enum(u8) {
    gaussian_modulated = 0,
    flat_top_n4 = 1,
    triple_flat_top_n4 = 2,
    table = 5,

    pub fn parse(value: []const u8) errors.Error!SlitIndex {
        if (std.mem.eql(u8, value, "0") or
            std.mem.eql(u8, value, "gaussian") or
            std.mem.eql(u8, value, "gaussian_modulated"))
        {
            return .gaussian_modulated;
        }

        if (std.mem.eql(u8, value, "1") or
            std.mem.eql(u8, value, "flat_top") or
            std.mem.eql(u8, value, "flat_top_n4"))
        {
            return .flat_top_n4;
        }

        if (std.mem.eql(u8, value, "2") or
            std.mem.eql(u8, value, "triple_flat_top") or
            std.mem.eql(u8, value, "triple_flat_top_n4"))
        {
            return .triple_flat_top_n4;
        }

        if (std.mem.eql(u8, value, "5") or std.mem.eql(u8, value, "table")) {
            return .table;
        }

        return errors.Error.InvalidRequest;
    }

    pub fn builtinKind(self: SlitIndex) BuiltinLineShapeKind {
        return switch (self) {
            .gaussian_modulated, .table => .gaussian,
            .flat_top_n4 => .flat_top_n4,
            .triple_flat_top_n4 => .triple_flat_top_n4,
        };
    }
};

// SpectralResponse -------------------------------------------------------------------------------------------|
// One spectral-response request plus optional explicit kernel/table data.                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 152 B (0.148 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] fwhm_nm                       : f64                                                              |
// [  8.. 15] amplitude                     : f64                                                              |
// [ 16.. 23] scale                         : f64                                                              |
// [ 24.. 31] phase_deg                     : f64                                                              |
// [ 32.. 39] high_resolution_step_nm       : f64                                                              |
// [ 40.. 47] high_resolution_half_span_nm  : f64                                                              |
// [ 48.. 87] instrument_line_shape         : InstrumentLineShape                                              |
// [ 88..143] instrument_line_shape_table   : InstrumentLineShapeTable                                         |
// [144..144] explicit                      : bool                                                             |
// [145..145] slit_index                    : SlitIndex                                                        |
// [146..146] builtin_line_shape            : BuiltinLineShapeKind                                             |
// [147..147] integration_mode              : IntegrationMode                                                  |
// [148..151] trailing padding              : 4 B                                                              |
//                                                                                                             |
// referenced storage                                                                                          |
//   explicit line-shape headers may own out-of-line kernel arrays.                                            |
//                                                                                                             |
// unused bits: 32 padding + 7 bool-storage slack + 18 enum-storage slack = 57 bits                            |
// cache span: 3 cache lines at 64 B per line                                                                  |
// footprint: per instance = 152 B (0.148 KiB); total also includes referenced line-shape storage              |
pub const SpectralResponse = struct {
    pub const RequestedIntegrationMode = enum {
        auto,
        default_kernel,
        explicit_hr_grid,
        disamar_hr_grid,
        adaptive,
    };
    pub const IntegrationMode = enum(u8) {
        default_kernel = 0,
        explicit_hr_grid = 1,
        disamar_hr_grid = 2,
        adaptive = 3,
    };

    explicit: bool = false,
    slit_index: SlitIndex = .gaussian_modulated,
    fwhm_nm: f64 = 0.0,
    amplitude: f64 = 0.0,
    scale: f64 = 1.0,
    phase_deg: f64 = 0.0,
    builtin_line_shape: BuiltinLineShapeKind = .gaussian,
    integration_mode: IntegrationMode = .default_kernel,
    high_resolution_step_nm: f64 = 0.0,
    high_resolution_half_span_nm: f64 = 0.0,
    instrument_line_shape: InstrumentLineShape = .{},
    instrument_line_shape_table: InstrumentLineShapeTable = .{},

    pub fn validate(self: *const SpectralResponse) errors.Error!void {
        if (self.fwhm_nm < 0.0 or !std.math.isFinite(self.fwhm_nm)) return errors.Error.InvalidRequest;

        if (!std.math.isFinite(self.amplitude) or
            !std.math.isFinite(self.scale) or
            self.scale <= 0.0 or
            !std.math.isFinite(self.phase_deg))
        {
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

        if (self.slit_index == .table and
            self.instrument_line_shape_table.nominal_count == 0 and
            self.instrument_line_shape.sample_count == 0)
        {
            return errors.Error.InvalidRequest;
        }
    }

    pub fn deinitOwned(self: *SpectralResponse, allocator: Allocator) void {
        self.instrument_line_shape.deinitOwned(allocator);
        self.instrument_line_shape_table.deinitOwned(allocator);
        self.* = .{};
    }
};
// ------------------------------------------------------------------------------------------------------------|

// SpectralChannelControls ------------------------------------------------------------------------------------|
// Per-channel response and scalar correction controls.                                                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 192 B (0.188 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..151] response              : SpectralResponse                                                         |
// [152..159] wavelength_shift_nm   : f64                                                                      |
// [160..167] multiplicative_offset : f64                                                                      |
// [168..175] additive_offset       : f64                                                                      |
// [176..183] stray_light           : f64                                                                      |
// [184..184] explicit              : bool                                                                     |
// [185..191] trailing padding      : 7 B                                                                      |
//                                                                                                             |
// referenced storage                                                                                          |
//   response may own nested line-shape arrays. Scalar correction controls are inline.                         |
//                                                                                                             |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                    |
// cache span: 3 cache lines at 64 B per line                                                                  |
// footprint: per instance = 192 B (0.188 KiB); total also includes nested response storage                    |
pub const SpectralChannelControls = struct {
    explicit: bool = false,
    response: SpectralResponse = .{},
    wavelength_shift_nm: f64 = 0.0,
    multiplicative_offset: f64 = 1.0,
    additive_offset: f64 = 0.0,
    stray_light: f64 = 0.0,

    pub fn validate(self: *const SpectralChannelControls) errors.Error!void {
        if (!std.math.isFinite(self.wavelength_shift_nm) or
            !std.math.isFinite(self.multiplicative_offset) or
            self.multiplicative_offset <= 0.0 or
            !std.math.isFinite(self.additive_offset) or
            !std.math.isFinite(self.stray_light))
        {
            return errors.Error.InvalidRequest;
        }
        try self.response.validate();
    }
};
// ------------------------------------------------------------------------------------------------------------|
