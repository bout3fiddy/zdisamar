const std = @import("std");
const errors = @import("../../common/errors.zig");
const Allocator = std.mem.Allocator;
const line_shape = @import("line_shape.zig");

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
        if (std.mem.eql(u8, value, "0") or std.mem.eql(u8, value, "gaussian") or std.mem.eql(u8, value, "gaussian_modulated")) {
            return .gaussian_modulated;
        }
        if (std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "flat_top") or std.mem.eql(u8, value, "flat_top_n4")) {
            return .flat_top_n4;
        }
        if (std.mem.eql(u8, value, "2") or std.mem.eql(u8, value, "triple_flat_top") or std.mem.eql(u8, value, "triple_flat_top_n4")) {
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

// layout(64-bit):
//   size: 152 B, align: 8 B
//   field storage: 148 B across 12 fields; largest: instrument_line_shape_table=56 B, instrument_line_shape=40 B, fwhm_nm=8 B; padding: 4 B (32 bits)
//   unused bits: 32 padding + 7 bool-storage slack = 39 bits
//   cache span: 3 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 152 B (0.148 KiB); total = per instance * live instance count
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
        if (!std.math.isFinite(self.amplitude) or !std.math.isFinite(self.scale) or self.scale <= 0.0 or !std.math.isFinite(self.phase_deg)) {
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

// layout(64-bit):
//   size: 192 B, align: 8 B
//   field storage: 185 B across 6 fields; largest: response=152 B, wavelength_shift_nm=8 B, multiplicative_offset=8 B; padding: 7 B (56 bits)
//   unused bits: 56 padding + 7 bool-storage slack = 63 bits
//   cache span: 3 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 192 B (0.188 KiB); total = per instance * live instance count
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
