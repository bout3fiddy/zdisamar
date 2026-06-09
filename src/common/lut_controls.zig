const std = @import("std");
const errors = @import("errors.zig");

// lut_controls.zig -------------------------------------------------------------------------------------------|
// Shared LUT compatibility controls used by input preparation and cache-matching code.                        |
//                                                                                                             |
// public values                                                                                               |
//   Mode                : direct, generate, or consume behavior for a compatibility surface                   |
//   ReflectanceControls : reflectance and correction compatibility knobs                                      |
//   XsecControls        : cross-section LUT temperature/pressure grid knobs                                   |
//   Controls            : grouped reflectance and cross-section controls                                      |
//   CompatibilityKey    : full scene, instrument, spectroscopy, and LUT identity key                          |
//                                                                                                             |
// memory                                                                                                      |
//   CompatibilityKey is copied and compared as a compact value. It contains no owned heap storage.            |
// ------------------------------------------------------------------------------------------------------------|

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

// ReflectanceControls ----------------------------------------------------------------------------------------|
// Stores the reflectance compatibility knobs used when LUT behavior must match a prepared case.               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] surface_albedo      : f64                                                                          |
// [ 8.. 8] reflectance_mode    : Mode                                                                         |
// [ 9.. 9] correction_mode     : Mode                                                                         |
// [10..10] use_chandra_formula : bool                                                                         |
// [11..15] trailing padding                                                                                   |
//                                                                                                             |
// unused bits: 40 padding + 12 enum-storage slack + 7 bool-storage slack = 59 bits                            |
// footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count                      |
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
// ------------------------------------------------------------------------------------------------------------|

// XsecControls -----------------------------------------------------------------------------------------------|
// Stores the cross-section LUT grid controls used when generated or consumed cross sections must match.       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] min_temperature_k             : f64                                                                |
// [ 8..15] max_temperature_k             : f64                                                                |
// [16..23] min_pressure_hpa              : f64                                                                |
// [24..31] max_pressure_hpa              : f64                                                                |
// [32..32] mode                          : Mode                                                               |
// [33..33] temperature_grid_count        : u8                                                                 |
// [34..34] pressure_grid_count           : u8                                                                 |
// [35..35] temperature_coefficient_count : u8                                                                 |
// [36..36] pressure_coefficient_count    : u8                                                                 |
// [37..39] trailing padding                                                                                   |
//                                                                                                             |
// unused bits: 24 padding + 6 enum-storage slack + 0 bool-storage slack = 30 bits                             |
// footprint: per instance = 40 B (0.039 KiB); total = per instance * live instance count                      |
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
// ------------------------------------------------------------------------------------------------------------|

// Controls ---------------------------------------------------------------------------------------------------|
// Groups reflectance and cross-section LUT controls so callers can validate and compare both together.        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 56 B (0.055 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] reflectance : ReflectanceControls                                                                  |
// [16..55] xsec        : XsecControls                                                                         |
//                                                                                                             |
// unused bits: 0 top-level padding + nested control slack is documented by each nested layout                 |
// footprint: per instance = 56 B (0.055 KiB); total = per instance * live instance count                      |
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
// ------------------------------------------------------------------------------------------------------------|

// CompatibilityKey -------------------------------------------------------------------------------------------|
// Stores the full compatibility identity used to decide whether a LUT product can be reused.                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 160 B (0.156 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 55] controls                      : Controls                                                         |
// [ 56.. 63] spectral_start_nm             : f64                                                              |
// [ 64.. 71] spectral_end_nm               : f64                                                              |
// [ 72.. 79] nominal_wavelength_hash       : u64                                                              |
// [ 80.. 87] solar_zenith_deg              : f64                                                              |
// [ 88.. 95] viewing_zenith_deg            : f64                                                              |
// [ 96..103] relative_azimuth_deg          : f64                                                              |
// [104..111] surface_albedo                : f64                                                              |
// [112..119] instrument_line_fwhm_nm       : f64                                                              |
// [120..127] high_resolution_step_nm       : f64                                                              |
// [128..135] high_resolution_half_span_nm  : f64                                                              |
// [136..143] lut_sampling_half_span_nm     : f64                                                              |
// [144..151] spectroscopy_source_hash      : u64                                                              |
// [152..155] nominal_sample_count          : u32                                                              |
// [156..159] trailing padding                                                                                 |
//                                                                                                             |
// unused bits: 32 top-level padding bits; nested control slack is documented by Controls                      |
// footprint: per instance = 160 B (0.156 KiB); total = per instance * live instance count                     |
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
    spectroscopy_source_hash: u64 = 0,

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
            approxEqCompatibleF64(self.lut_sampling_half_span_nm, other.lut_sampling_half_span_nm) and
            self.spectroscopy_source_hash == other.spectroscopy_source_hash;
    }
};
// ------------------------------------------------------------------------------------------------------------|

fn approxEqCompatibleF64(lhs: f64, rhs: f64) bool {
    return lhs == rhs or
        std.math.approxEqAbs(f64, lhs, rhs, 1.0e-12) or
        std.math.approxEqRel(f64, lhs, rhs, 1.0e-12);
}
