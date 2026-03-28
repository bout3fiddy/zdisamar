//! Purpose:
//!   Define typed LUT execution controls and compatibility keys shared by config, planning, caches,
//!   and provenance.
//!
//! Physics:
//!   Captures whether reflectance/correction and spectroscopy paths run directly, generate LUTs,
//!   or consume precomputed LUTs, together with the scientific inputs that make a LUT reusable.
//!
//! Vendor:
//!   `createLUT`, `createXsecLUT`
//!
//! Design:
//!   Keep LUT workflow state typed and explicit so prepared plans, requests, and caches can reject
//!   incompatible reuse instead of relying on implicit runtime assumptions.
//!
//! Invariants:
//!   Non-direct LUT modes must provide finite ranges and counts, and compatibility keys must
//!   capture the scene and instrument inputs that define reuse safety.

const std = @import("std");
const errors = @import("errors.zig");

pub const Mode = enum {
    direct,
    generate,
    consume,

    pub fn label(self: Mode) []const u8 {
        return @tagName(self);
    }

    pub fn parse(value: []const u8) ?Mode {
        return std.meta.stringToEnum(Mode, value);
    }
};

pub const ReflectanceControls = struct {
    reflectance_mode: Mode = .direct,
    correction_mode: Mode = .direct,
    use_chandra_formula: bool = false,
    surface_albedo: f64 = 0.0,

    pub fn enabled(self: ReflectanceControls) bool {
        return self.reflectance_mode != .direct or self.correction_mode != .direct;
    }

    pub fn validate(self: ReflectanceControls) errors.Error!void {
        if (!std.math.isFinite(self.surface_albedo) or self.surface_albedo < 0.0) {
            return errors.Error.InvalidRequest;
        }
    }

    pub fn matches(self: ReflectanceControls, other: ReflectanceControls) bool {
        return self.reflectance_mode == other.reflectance_mode and
            self.correction_mode == other.correction_mode and
            self.use_chandra_formula == other.use_chandra_formula and
            approxEqCompatibleF64(self.surface_albedo, other.surface_albedo);
    }
};

pub const XsecControls = struct {
    mode: Mode = .direct,
    min_temperature_k: f64 = 0.0,
    max_temperature_k: f64 = 0.0,
    min_pressure_hpa: f64 = 0.0,
    max_pressure_hpa: f64 = 0.0,
    temperature_grid_count: u8 = 0,
    pressure_grid_count: u8 = 0,
    temperature_coefficient_count: u8 = 0,
    pressure_coefficient_count: u8 = 0,

    pub fn enabled(self: XsecControls) bool {
        return self.mode != .direct;
    }

    pub fn coefficientCount(self: XsecControls) u32 {
        return @as(u32, self.temperature_coefficient_count) *
            @as(u32, self.pressure_coefficient_count);
    }

    pub fn validate(self: XsecControls) errors.Error!void {
        if (self.mode == .direct) {
            return;
        }

        if (!std.math.isFinite(self.min_temperature_k) or
            !std.math.isFinite(self.max_temperature_k) or
            !std.math.isFinite(self.min_pressure_hpa) or
            !std.math.isFinite(self.max_pressure_hpa))
        {
            return errors.Error.InvalidRequest;
        }
        if (self.min_temperature_k <= 0.0 or self.max_temperature_k <= self.min_temperature_k) {
            return errors.Error.InvalidRequest;
        }
        if (self.min_pressure_hpa <= 0.0 or self.max_pressure_hpa <= self.min_pressure_hpa) {
            return errors.Error.InvalidRequest;
        }
        if (self.temperature_grid_count == 0 or
            self.pressure_grid_count == 0 or
            self.temperature_coefficient_count == 0 or
            self.pressure_coefficient_count == 0)
        {
            return errors.Error.InvalidRequest;
        }
        if (self.temperature_coefficient_count > self.temperature_grid_count or
            self.pressure_coefficient_count > self.pressure_grid_count)
        {
            return errors.Error.InvalidRequest;
        }
    }

    pub fn matches(self: XsecControls, other: XsecControls) bool {
        return self.mode == other.mode and
            approxEqCompatibleF64(self.min_temperature_k, other.min_temperature_k) and
            approxEqCompatibleF64(self.max_temperature_k, other.max_temperature_k) and
            approxEqCompatibleF64(self.min_pressure_hpa, other.min_pressure_hpa) and
            approxEqCompatibleF64(self.max_pressure_hpa, other.max_pressure_hpa) and
            self.temperature_grid_count == other.temperature_grid_count and
            self.pressure_grid_count == other.pressure_grid_count and
            self.temperature_coefficient_count == other.temperature_coefficient_count and
            self.pressure_coefficient_count == other.pressure_coefficient_count;
    }
};

pub const Controls = struct {
    reflectance: ReflectanceControls = .{},
    xsec: XsecControls = .{},

    pub fn enabled(self: Controls) bool {
        return self.reflectance.enabled() or self.xsec.enabled();
    }

    pub fn validate(self: Controls) errors.Error!void {
        try self.reflectance.validate();
        try self.xsec.validate();
    }

    pub fn matches(self: Controls, other: Controls) bool {
        return self.reflectance.matches(other.reflectance) and self.xsec.matches(other.xsec);
    }
};

pub const CompatibilityKey = struct {
    controls: Controls = .{},
    spectral_start_nm: f64 = 0.0,
    spectral_end_nm: f64 = 0.0,
    nominal_sample_count: u32 = 0,
    nominal_wavelength_hash: u64 = 0,
    solar_zenith_deg: f64 = 0.0,
    viewing_zenith_deg: f64 = 0.0,
    relative_azimuth_deg: f64 = 0.0,
    surface_albedo: f64 = 0.0,
    instrument_line_fwhm_nm: f64 = 0.0,
    high_resolution_step_nm: f64 = 0.0,
    high_resolution_half_span_nm: f64 = 0.0,
    lut_sampling_half_span_nm: f64 = 0.0,

    pub fn enabled(self: CompatibilityKey) bool {
        return self.controls.enabled();
    }

    pub fn validate(self: CompatibilityKey) errors.Error!void {
        try self.controls.validate();
        if (!self.enabled()) return;

        if (!std.math.isFinite(self.spectral_start_nm) or
            !std.math.isFinite(self.spectral_end_nm) or
            !std.math.isFinite(self.solar_zenith_deg) or
            !std.math.isFinite(self.viewing_zenith_deg) or
            !std.math.isFinite(self.relative_azimuth_deg) or
            !std.math.isFinite(self.surface_albedo) or
            !std.math.isFinite(self.instrument_line_fwhm_nm) or
            !std.math.isFinite(self.high_resolution_step_nm) or
            !std.math.isFinite(self.high_resolution_half_span_nm) or
            !std.math.isFinite(self.lut_sampling_half_span_nm))
        {
            return errors.Error.InvalidRequest;
        }
        if (self.spectral_end_nm <= self.spectral_start_nm) return errors.Error.InvalidRequest;
        if (self.surface_albedo < 0.0) return errors.Error.InvalidRequest;
        if (self.instrument_line_fwhm_nm < 0.0) return errors.Error.InvalidRequest;
        if (self.high_resolution_step_nm < 0.0 or self.high_resolution_half_span_nm < 0.0) {
            return errors.Error.InvalidRequest;
        }
        if (self.lut_sampling_half_span_nm < 0.0) return errors.Error.InvalidRequest;
        if ((self.high_resolution_step_nm == 0.0) != (self.high_resolution_half_span_nm == 0.0)) {
            return errors.Error.InvalidRequest;
        }
        if (self.high_resolution_step_nm > 0.0) {
            if (self.nominal_sample_count != 0 or self.nominal_wavelength_hash != 0) {
                return errors.Error.InvalidRequest;
            }
        } else if (self.nominal_sample_count == 0) {
            return errors.Error.InvalidRequest;
        }
    }

    pub fn matches(self: CompatibilityKey, other: CompatibilityKey) bool {
        return self.controls.matches(other.controls) and
            approxEqCompatibleF64(self.spectral_start_nm, other.spectral_start_nm) and
            approxEqCompatibleF64(self.spectral_end_nm, other.spectral_end_nm) and
            self.nominal_sample_count == other.nominal_sample_count and
            self.nominal_wavelength_hash == other.nominal_wavelength_hash and
            approxEqCompatibleF64(self.solar_zenith_deg, other.solar_zenith_deg) and
            approxEqCompatibleF64(self.viewing_zenith_deg, other.viewing_zenith_deg) and
            approxEqCompatibleF64(self.relative_azimuth_deg, other.relative_azimuth_deg) and
            approxEqCompatibleF64(self.surface_albedo, other.surface_albedo) and
            approxEqCompatibleF64(self.instrument_line_fwhm_nm, other.instrument_line_fwhm_nm) and
            approxEqCompatibleF64(self.high_resolution_step_nm, other.high_resolution_step_nm) and
            approxEqCompatibleF64(self.high_resolution_half_span_nm, other.high_resolution_half_span_nm) and
            approxEqCompatibleF64(self.lut_sampling_half_span_nm, other.lut_sampling_half_span_nm);
    }
};

fn approxEqCompatibleF64(lhs: f64, rhs: f64) bool {
    return lhs == rhs or
        std.math.approxEqAbs(f64, lhs, rhs, 1.0e-12) or
        std.math.approxEqRel(f64, lhs, rhs, 1.0e-12);
}

test "lut controls reject incomplete non-direct xsec settings" {
    try std.testing.expectError(errors.Error.InvalidRequest, (Controls{
        .xsec = .{ .mode = .generate },
    }).validate());
    try std.testing.expectError(errors.Error.InvalidRequest, (Controls{
        .xsec = .{ .mode = .consume },
    }).validate());
}

test "lut compatibility keys compare all scientific inputs explicitly" {
    const lhs: CompatibilityKey = .{
        .controls = .{
            .reflectance = .{ .reflectance_mode = .generate, .surface_albedo = 0.1 },
            .xsec = .{
                .mode = .consume,
                .min_temperature_k = 180.0,
                .max_temperature_k = 325.0,
                .min_pressure_hpa = 0.03,
                .max_pressure_hpa = 1050.0,
                .temperature_grid_count = 10,
                .pressure_grid_count = 20,
                .temperature_coefficient_count = 5,
                .pressure_coefficient_count = 10,
            },
        },
        .spectral_start_nm = 758.0,
        .spectral_end_nm = 770.0,
        .solar_zenith_deg = 60.0,
        .viewing_zenith_deg = 30.0,
        .relative_azimuth_deg = 120.0,
        .surface_albedo = 0.1,
        .instrument_line_fwhm_nm = 0.38,
        .high_resolution_step_nm = 0.01,
        .high_resolution_half_span_nm = 1.14,
        .lut_sampling_half_span_nm = 1.14,
    };
    var rhs = lhs;

    try lhs.validate();
    try rhs.validate();
    try std.testing.expect(lhs.matches(rhs));

    rhs.lut_sampling_half_span_nm = 1.5;
    try std.testing.expect(!lhs.matches(rhs));
}

test "lut compatibility keys tolerate numerically equivalent float inputs" {
    const lhs: CompatibilityKey = .{
        .controls = .{
            .reflectance = .{ .reflectance_mode = .generate, .surface_albedo = 0.1 },
            .xsec = .{
                .mode = .consume,
                .min_temperature_k = 180.0,
                .max_temperature_k = 325.0,
                .min_pressure_hpa = 0.03,
                .max_pressure_hpa = 1050.0,
                .temperature_grid_count = 10,
                .pressure_grid_count = 20,
                .temperature_coefficient_count = 5,
                .pressure_coefficient_count = 10,
            },
        },
        .spectral_start_nm = 758.0,
        .spectral_end_nm = 770.0,
        .nominal_sample_count = 0,
        .solar_zenith_deg = 60.0,
        .viewing_zenith_deg = 30.0,
        .relative_azimuth_deg = 120.0,
        .surface_albedo = 0.1,
        .instrument_line_fwhm_nm = 0.38,
        .high_resolution_step_nm = 0.01,
        .high_resolution_half_span_nm = 1.14,
        .lut_sampling_half_span_nm = 1.14,
    };
    var rhs = lhs;

    rhs.controls.reflectance.surface_albedo += 5.0e-13;
    rhs.controls.xsec.max_temperature_k += 1.0e-10;
    rhs.spectral_start_nm += 5.0e-13;
    rhs.relative_azimuth_deg += 5.0e-13;
    rhs.high_resolution_half_span_nm += 5.0e-13;

    try lhs.validate();
    try rhs.validate();
    try std.testing.expect(lhs.matches(rhs));

    rhs.instrument_line_fwhm_nm += 1.0e-6;
    try std.testing.expect(!lhs.matches(rhs));
}
