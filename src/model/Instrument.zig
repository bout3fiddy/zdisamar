//! Purpose:
//!   Define the typed instrument contract and re-export the instrument-carrier modules.
//!
//! Physics:
//!   Captures sampling mode, noise model, calibration/high-resolution controls, and the
//!   operational/reference carriers needed by instrument-response handling.
//!
//! Vendor:
//!   `instrument contract`
//!
//! Design:
//!   Keep the scene-facing instrument surface lightweight while line shapes, reference grids,
//!   solar spectra, and operational LUTs live in dedicated carrier modules under
//!   `src/model/instrument/`.
//!
//! Invariants:
//!   Instrument ids must validate, high-resolution controls are configured as pairs, and owned
//!   carrier storage is released only through `deinitOwned`.
//!
//! Validation:
//!   Instrument validation tests in this file plus the instrument-carrier unit tests and
//!   operational sampling paths exercised by transport/retrieval integration tests.

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
pub const SpectralChannel = enum {
    radiance,
    irradiance,
};

/// Purpose:
///   Identify the instrument family associated with an observation model.
pub const Id = union(enum) {
    unset,
    generic,
    tropomi,
    synthetic,
    custom: []const u8,

    /// Purpose:
    ///   Parse a public-facing instrument id into the typed instrument enum.
    pub fn parse(value: []const u8) Id {
        if (value.len == 0) return .unset;
        if (std.mem.eql(u8, value, "generic")) return .generic;
        if (std.mem.eql(u8, value, "tropomi")) return .tropomi;
        if (std.mem.eql(u8, value, "synthetic")) return .synthetic;
        return .{ .custom = value };
    }

    /// Purpose:
    ///   Return the stable label used for public-facing instrument ids.
    pub fn label(self: Id) []const u8 {
        return switch (self) {
            .unset => "",
            .generic => "generic",
            .tropomi => "tropomi",
            .synthetic => "synthetic",
            .custom => |value| value,
        };
    }

    /// Purpose:
    ///   Reject unset or malformed instrument ids.
    pub fn validate(self: Id) errors.Error!void {
        switch (self) {
            .unset => return errors.Error.MissingObservationInstrument,
            .custom => |value| if (value.len == 0) return errors.Error.MissingObservationInstrument,
            .generic, .tropomi, .synthetic => {},
        }
    }
};

/// Purpose:
///   Store typed instrument settings and carrier data for a canonical observation model.
pub const Instrument = struct {
    pub const SamplingMode = enum {
        native,
        operational,
        measured_channels,
        synthetic,

        /// Purpose:
        ///   Parse a public-facing sampling mode label into the typed enum.
        pub fn parse(value: []const u8) errors.Error!SamplingMode {
            if (std.mem.eql(u8, value, "native")) return .native;
            if (std.mem.eql(u8, value, "operational")) return .operational;
            if (std.mem.eql(u8, value, "measured_channels")) return .measured_channels;
            if (std.mem.eql(u8, value, "synthetic")) return .synthetic;
            return errors.Error.InvalidRequest;
        }

        /// Purpose:
        ///   Return the stable label used for the sampling mode.
        pub fn label(self: SamplingMode) []const u8 {
            return @tagName(self);
        }
    };

    pub const NoiseModelKind = enum {
        none,
        shot_noise,
        s5p_operational,
        lab_operational,
        snr_from_input,

        /// Purpose:
        ///   Parse a public-facing noise-model label into the typed enum.
        pub fn parse(value: []const u8) errors.Error!NoiseModelKind {
            if (std.mem.eql(u8, value, "none")) return .none;
            if (std.mem.eql(u8, value, "shot_noise")) return .shot_noise;
            if (std.mem.eql(u8, value, "s5p_operational")) return .s5p_operational;
            if (std.mem.eql(u8, value, "lab_operational")) return .lab_operational;
            if (std.mem.eql(u8, value, "snr_from_input")) return .snr_from_input;
            return errors.Error.InvalidRequest;
        }

        /// Purpose:
        ///   Return the stable label used for the noise model.
        pub fn label(self: NoiseModelKind) []const u8 {
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

    pub const NodalCorrection = struct {
        wavelengths_nm: []const f64 = &.{},
        values: []const f64 = &.{},
        variances: []const f64 = &.{},
        use_linear_interpolation: bool = false,
        use_reference_spectrum: bool = false,
        use_characteristic_bias: bool = false,
        characteristic_bias: []const f64 = &.{},
        owns_memory: bool = false,

        pub fn enabled(self: NodalCorrection) bool {
            return self.wavelengths_nm.len != 0 or self.values.len != 0;
        }

        pub fn validate(self: *const NodalCorrection) errors.Error!void {
            if (self.wavelengths_nm.len == 0 and
                self.values.len == 0 and
                self.variances.len == 0 and
                self.characteristic_bias.len == 0)
            {
                return;
            }
            if (self.wavelengths_nm.len == 0 or self.values.len == 0 or self.wavelengths_nm.len != self.values.len) {
                return errors.Error.InvalidRequest;
            }
            if (self.variances.len != 0 and self.variances.len != self.values.len) {
                return errors.Error.InvalidRequest;
            }
            if (self.characteristic_bias.len != 0 and self.characteristic_bias.len != self.values.len) {
                return errors.Error.InvalidRequest;
            }

            var previous_wavelength: ?f64 = null;
            for (self.wavelengths_nm, self.values, 0..) |wavelength_nm, value, index| {
                if (!std.math.isFinite(wavelength_nm) or !std.math.isFinite(value)) {
                    return errors.Error.InvalidRequest;
                }
                if (previous_wavelength) |previous| {
                    if (wavelength_nm <= previous) return errors.Error.InvalidRequest;
                }
                previous_wavelength = wavelength_nm;
                if (index < self.variances.len) {
                    const variance = self.variances[index];
                    if (!std.math.isFinite(variance) or variance < 0.0) return errors.Error.InvalidRequest;
                }
                if (index < self.characteristic_bias.len) {
                    if (!std.math.isFinite(self.characteristic_bias[index])) return errors.Error.InvalidRequest;
                }
            }
        }

        pub fn deinitOwned(self: *NodalCorrection, allocator: Allocator) void {
            if (self.owns_memory) {
                if (self.wavelengths_nm.len != 0) allocator.free(@constCast(self.wavelengths_nm));
                if (self.values.len != 0) allocator.free(@constCast(self.values));
                if (self.variances.len != 0) allocator.free(@constCast(self.variances));
                if (self.characteristic_bias.len != 0) allocator.free(@constCast(self.characteristic_bias));
            }
            self.* = .{};
        }
    };

    pub const SpectralResponse = struct {
        explicit: bool = false,
        slit_index: SlitIndex = .gaussian_modulated,
        fwhm_nm: f64 = 0.0,
        amplitude: f64 = 0.0,
        scale: f64 = 1.0,
        phase_deg: f64 = 0.0,
        builtin_line_shape: BuiltinLineShapeKind = .gaussian,
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

    pub const SimpleOffsets = struct {
        multiplicative_percent: f64 = 0.0,
        additive_percent_of_first: f64 = 0.0,

        pub fn enabled(self: SimpleOffsets) bool {
            return self.multiplicative_percent != 0.0 or self.additive_percent_of_first != 0.0;
        }

        pub fn validate(self: SimpleOffsets) errors.Error!void {
            if (!std.math.isFinite(self.multiplicative_percent) or !std.math.isFinite(self.additive_percent_of_first)) {
                return errors.Error.InvalidRequest;
            }
        }
    };

    pub const SinusoidalFeatures = struct {
        additive_amplitude_percent: f64 = 0.0,
        additive_period_nm: f64 = 0.0,
        additive_phase_deg: f64 = 0.0,
        multiplicative_amplitude_percent: f64 = 0.0,
        multiplicative_period_nm: f64 = 0.0,
        multiplicative_phase_deg: f64 = 0.0,

        pub fn enabled(self: SinusoidalFeatures) bool {
            return self.additive_amplitude_percent != 0.0 or self.multiplicative_amplitude_percent != 0.0;
        }

        pub fn validate(self: SinusoidalFeatures) errors.Error!void {
            if (!std.math.isFinite(self.additive_amplitude_percent) or
                !std.math.isFinite(self.additive_period_nm) or
                !std.math.isFinite(self.additive_phase_deg) or
                !std.math.isFinite(self.multiplicative_amplitude_percent) or
                !std.math.isFinite(self.multiplicative_period_nm) or
                !std.math.isFinite(self.multiplicative_phase_deg))
            {
                return errors.Error.InvalidRequest;
            }
            if (self.additive_amplitude_percent != 0.0 and self.additive_period_nm <= 0.0) return errors.Error.InvalidRequest;
            if (self.multiplicative_amplitude_percent != 0.0 and self.multiplicative_period_nm <= 0.0) return errors.Error.InvalidRequest;
        }
    };

    pub const NoiseControls = struct {
        explicit: bool = false,
        enabled: bool = false,
        model: NoiseModelKind = .none,
        electrons_per_count: f64 = 2.0,
        reference_bin_width_nm: f64 = 0.0,
        snr_max: f64 = std.math.inf(f64),
        lab_a: f64 = 0.0,
        lab_b: f64 = 0.0,
        snr_wavelengths_nm: []const f64 = &.{},
        snr_values: []const f64 = &.{},
        reference_signal: []const f64 = &.{},
        reference_sigma: []const f64 = &.{},
        owns_snr_memory: bool = false,
        owns_reference_memory: bool = false,

        pub fn validate(self: *const NoiseControls) errors.Error!void {
            if (!std.math.isFinite(self.electrons_per_count) or self.electrons_per_count <= 0.0) {
                return errors.Error.InvalidRequest;
            }
            if (!std.math.isFinite(self.reference_bin_width_nm) or self.reference_bin_width_nm < 0.0) {
                return errors.Error.InvalidRequest;
            }
            if (std.math.isNan(self.snr_max) or self.snr_max <= 0.0) return errors.Error.InvalidRequest;
            if (!std.math.isFinite(self.lab_a) or self.lab_a < 0.0 or !std.math.isFinite(self.lab_b) or self.lab_b < 0.0) {
                return errors.Error.InvalidRequest;
            }
            if (self.enabled and self.model == .lab_operational and self.lab_a <= 0.0) {
                return errors.Error.InvalidRequest;
            }
            if (self.snr_wavelengths_nm.len != self.snr_values.len) {
                return errors.Error.InvalidRequest;
            }
            if (self.reference_signal.len != self.reference_sigma.len) {
                return errors.Error.InvalidRequest;
            }
            var previous_wavelength: ?f64 = null;
            for (self.snr_wavelengths_nm, self.snr_values) |wavelength_nm, snr_value| {
                if (!std.math.isFinite(wavelength_nm) or !std.math.isFinite(snr_value) or snr_value <= 0.0) {
                    return errors.Error.InvalidRequest;
                }
                if (previous_wavelength) |previous| {
                    if (wavelength_nm <= previous) return errors.Error.InvalidRequest;
                }
                previous_wavelength = wavelength_nm;
            }
            for (self.reference_signal, self.reference_sigma) |signal, sigma| {
                if (!std.math.isFinite(signal) or signal <= 0.0 or !std.math.isFinite(sigma) or sigma <= 0.0) {
                    return errors.Error.InvalidRequest;
                }
            }
        }

        pub fn deinitOwned(self: *NoiseControls, allocator: Allocator) void {
            if (self.owns_snr_memory) {
                if (self.snr_wavelengths_nm.len != 0) allocator.free(@constCast(self.snr_wavelengths_nm));
                if (self.snr_values.len != 0) allocator.free(@constCast(self.snr_values));
            }
            if (self.owns_reference_memory) {
                if (self.reference_signal.len != 0) allocator.free(@constCast(self.reference_signal));
                if (self.reference_sigma.len != 0) allocator.free(@constCast(self.reference_sigma));
            }
            self.* = .{};
        }
    };

    pub const SpectralChannelControls = struct {
        explicit: bool = false,
        response: SpectralResponse = .{},
        wavelength_shift_nm: f64 = 0.0,
        multiplicative_offset: f64 = 1.0,
        additive_offset: f64 = 0.0,
        stray_light: f64 = 0.0,
        simple_offsets: SimpleOffsets = .{},
        spectral_features: SinusoidalFeatures = .{},
        smear_percent: f64 = 0.0,
        multiplicative_nodes: NodalCorrection = .{},
        stray_light_nodes: NodalCorrection = .{},
        noise: NoiseControls = .{},
        use_polarization_scrambler: bool = true,

        pub fn validate(self: *const SpectralChannelControls) errors.Error!void {
            if (!std.math.isFinite(self.wavelength_shift_nm) or
                !std.math.isFinite(self.multiplicative_offset) or
                self.multiplicative_offset <= 0.0 or
                !std.math.isFinite(self.additive_offset) or
                !std.math.isFinite(self.stray_light) or
                !std.math.isFinite(self.smear_percent))
            {
                return errors.Error.InvalidRequest;
            }
            try self.response.validate();
            try self.simple_offsets.validate();
            try self.spectral_features.validate();
            try self.multiplicative_nodes.validate();
            try self.stray_light_nodes.validate();
            try self.noise.validate();
        }

        pub fn deinitOwned(self: *SpectralChannelControls, allocator: Allocator) void {
            self.response.deinitOwned(allocator);
            self.multiplicative_nodes.deinitOwned(allocator);
            self.stray_light_nodes.deinitOwned(allocator);
            self.noise.deinitOwned(allocator);
            self.* = .{};
        }
    };

    pub const RingControls = struct {
        explicit: bool = false,
        enabled: bool = false,
        differential: bool = false,
        coefficient: f64 = 0.0,
        approximate_rrs: bool = false,
        fraction_raman_lines: f64 = 1.0,
        use_cabannes: bool = false,
        degree_poly: u32 = 0,
        include_absorption: bool = false,
        spectrum: []const f64 = &.{},
        owns_memory: bool = false,

        pub fn validate(self: *const RingControls) errors.Error!void {
            if (!std.math.isFinite(self.coefficient) or
                !std.math.isFinite(self.fraction_raman_lines) or
                self.fraction_raman_lines < 0.0 or
                self.degree_poly > 7)
            {
                return errors.Error.InvalidRequest;
            }
            for (self.spectrum) |value| {
                if (!std.math.isFinite(value)) return errors.Error.InvalidRequest;
            }
        }

        pub fn deinitOwned(self: *RingControls, allocator: Allocator) void {
            if (self.owns_memory and self.spectrum.len != 0) allocator.free(@constCast(self.spectrum));
            self.* = .{};
        }
    };

    pub const ReflectanceCalibration = struct {
        multiplicative_error: NodalCorrection = .{},
        additive_error: NodalCorrection = .{},

        pub fn validate(self: *const ReflectanceCalibration) errors.Error!void {
            try self.multiplicative_error.validate();
            try self.additive_error.validate();
        }

        pub fn deinitOwned(self: *ReflectanceCalibration, allocator: Allocator) void {
            self.multiplicative_error.deinitOwned(allocator);
            self.additive_error.deinitOwned(allocator);
            self.* = .{};
        }
    };

    pub const MeasurementPipeline = struct {
        radiance: SpectralChannelControls = .{},
        irradiance: SpectralChannelControls = .{},
        ring: RingControls = .{},
        reflectance_calibration: ReflectanceCalibration = .{},

        pub fn validate(self: *const MeasurementPipeline) errors.Error!void {
            try self.radiance.validate();
            try self.irradiance.validate();
            try self.ring.validate();
            try self.reflectance_calibration.validate();
        }

        pub fn deinitOwned(self: *MeasurementPipeline, allocator: Allocator) void {
            self.radiance.deinitOwned(allocator);
            self.irradiance.deinitOwned(allocator);
            self.ring.deinitOwned(allocator);
            self.reflectance_calibration.deinitOwned(allocator);
            self.* = .{};
        }
    };

    /// Purpose:
    ///   Carry explicit operational replacements scoped to one prepared spectral band.
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
            if (!self.enabled()) {
                if (self.id.len == 0) return;
                return;
            }
            if (self.id.len == 0) return errors.Error.InvalidRequest;
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
            const solar_spectrum = try self.operational_solar_spectrum.clone(allocator);
            errdefer {
                var cleanup = solar_spectrum;
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
                .operational_solar_spectrum = solar_spectrum,
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

    /// Purpose:
    ///   Validate instrument id, high-resolution controls, and any attached operational carriers.
    pub fn validate(self: *const Instrument) errors.Error!void {
        try self.id.validate();
        if (self.instrument_line_fwhm_nm < 0.0) {
            return errors.Error.InvalidRequest;
        }
        if (self.high_resolution_step_nm < 0.0 or self.high_resolution_half_span_nm < 0.0) {
            return errors.Error.InvalidRequest;
        }
        if ((self.high_resolution_step_nm == 0.0) != (self.high_resolution_half_span_nm == 0.0)) {
            // GOTCHA:
            //   The high-resolution support grid is defined by both its spacing and half-span, so
            //   partial configuration would under-specify the convolution domain.
            return errors.Error.InvalidRequest;
        }
        try self.instrument_line_shape.validate();
        try self.instrument_line_shape_table.validate();
        try self.operational_refspec_grid.validate();
        try self.operational_solar_spectrum.validate();
        try self.o2_operational_lut.validate();
        try self.o2o2_operational_lut.validate();
    }

    /// Purpose:
    ///   Release any owned line-shape, grid, solar-spectrum, and LUT storage.
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

test "noise controls validation rejects one-sided tables" {
    const snr_missing_wavelengths: Instrument.NoiseControls = .{
        .enabled = true,
        .model = .snr_from_input,
        .snr_values = &[_]f64{100.0},
    };
    try std.testing.expectError(errors.Error.InvalidRequest, snr_missing_wavelengths.validate());

    const reference_missing_signal: Instrument.NoiseControls = .{
        .enabled = true,
        .model = .s5p_operational,
        .reference_sigma = &[_]f64{1.0},
    };
    try std.testing.expectError(errors.Error.InvalidRequest, reference_missing_signal.validate());
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
