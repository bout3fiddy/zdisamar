//! Purpose:
//!   Store operational cross-section lookup tables for wavelength, temperature, and pressure.
//!
//! Physics:
//!   Evaluates wavelength-indexed Legendre coefficient tables over scaled logarithmic temperature and pressure coordinates.
//!
//! Vendor:
//!   `operational cross-section LUT`
//!
//! Design:
//!   The coefficient layout is explicit so the flattened indexing and polynomial basis remain easy to audit.
//!
//! Invariants:
//!   Wavelengths are monotonic, coefficient counts stay within the fixed caps, and the coefficient tensor shape matches the table metadata.
//!
//! Validation:
//!   Tests cover interpolation and temperature/pressure dependence through the LUT evaluator.

const std = @import("std");
const errors = @import("../../core/errors.zig");
const LutControls = @import("../../core/lut_controls.zig");
const ReferenceData = @import("../ReferenceData.zig");
const build_helpers = @import("cross_section_lut_build.zig");
const eval_helpers = @import("cross_section_lut_eval.zig");
const constants = @import("constants.zig");

const Allocator = std.mem.Allocator;
const max_operational_refspec_temperature_coefficients = constants.max_operational_refspec_temperature_coefficients;
const max_operational_refspec_pressure_coefficients = constants.max_operational_refspec_pressure_coefficients;

pub const GenerationSource = build_helpers.GenerationSource;

/// Purpose:
///   Store an operational cross-section lookup table.
///
/// Physics:
///   Evaluates wavelength-indexed coefficients over scaled temperature and pressure coordinates.
pub const OperationalCrossSectionLut = struct {
    wavelengths_nm: []const f64 = &[_]f64{},
    coefficients: []const f64 = &[_]f64{},
    temperature_coefficient_count: u8 = 0,
    pressure_coefficient_count: u8 = 0,
    min_temperature_k: f64 = 0.0,
    max_temperature_k: f64 = 0.0,
    min_pressure_hpa: f64 = 0.0,
    max_pressure_hpa: f64 = 0.0,

    /// Purpose:
    ///   Report whether the LUT is active.
    pub fn enabled(self: *const OperationalCrossSectionLut) bool {
        return self.wavelengths_nm.len > 0;
    }

    /// Purpose:
    ///   Validate the operational cross-section LUT.
    ///
    /// Physics:
    ///   Ensures monotonic wavelengths, finite coefficient values, and compatible temperature/pressure ranges.
    pub fn validate(self: *const OperationalCrossSectionLut) errors.Error!void {
        if (!self.enabled()) {
            if (self.coefficients.len != 0 or
                self.temperature_coefficient_count != 0 or
                self.pressure_coefficient_count != 0)
            {
                return errors.Error.InvalidRequest;
            }
            return;
        }

        if (self.temperature_coefficient_count == 0 or
            self.temperature_coefficient_count > max_operational_refspec_temperature_coefficients or
            self.pressure_coefficient_count == 0 or
            self.pressure_coefficient_count > max_operational_refspec_pressure_coefficients)
        {
            return errors.Error.InvalidRequest;
        }

        if (!std.math.isFinite(self.min_temperature_k) or
            !std.math.isFinite(self.max_temperature_k) or
            !std.math.isFinite(self.min_pressure_hpa) or
            !std.math.isFinite(self.max_pressure_hpa) or
            self.min_temperature_k <= 0.0 or
            self.max_temperature_k <= self.min_temperature_k or
            self.min_pressure_hpa <= 0.0 or
            self.max_pressure_hpa <= self.min_pressure_hpa)
        {
            return errors.Error.InvalidRequest;
        }

        var previous_wavelength: ?f64 = null;
        for (self.wavelengths_nm) |wavelength_nm| {
            if (!std.math.isFinite(wavelength_nm)) return errors.Error.InvalidRequest;
            if (previous_wavelength) |previous| {
                if (wavelength_nm <= previous) return errors.Error.InvalidRequest;
            }
            previous_wavelength = wavelength_nm;
        }

        const expected_coefficient_count =
            self.wavelengths_nm.len *
            @as(usize, self.temperature_coefficient_count) *
            @as(usize, self.pressure_coefficient_count);
        if (self.coefficients.len != expected_coefficient_count) {
            return errors.Error.InvalidRequest;
        }

        for (self.coefficients) |coefficient| {
            if (!std.math.isFinite(coefficient)) return errors.Error.InvalidRequest;
        }
    }

    /// Purpose:
    ///   Clone the LUT into owned storage.
    pub fn clone(self: OperationalCrossSectionLut, allocator: Allocator) !OperationalCrossSectionLut {
        var cloned: OperationalCrossSectionLut = .{
            .temperature_coefficient_count = self.temperature_coefficient_count,
            .pressure_coefficient_count = self.pressure_coefficient_count,
            .min_temperature_k = self.min_temperature_k,
            .max_temperature_k = self.max_temperature_k,
            .min_pressure_hpa = self.min_pressure_hpa,
            .max_pressure_hpa = self.max_pressure_hpa,
        };
        cloned.wavelengths_nm = try allocator.dupe(f64, self.wavelengths_nm);
        errdefer allocator.free(cloned.wavelengths_nm);
        cloned.coefficients = try allocator.dupe(f64, self.coefficients);
        return cloned;
    }

    /// Purpose:
    ///   Build an operational LUT by fitting direct absorption evaluations onto the Legendre basis.
    ///
    /// Physics:
    ///   Mirrors the vendor XsecLUT workflow by evaluating sigma on Gauss-Legendre nodes in
    ///   scaled `ln(T)` and `ln(p)` coordinates, then projecting onto the orthogonal basis.
    pub fn buildFromSource(
        allocator: Allocator,
        wavelengths_nm: []const f64,
        source: GenerationSource,
        controls: LutControls.XsecControls,
    ) !OperationalCrossSectionLut {
        return build_helpers.buildFromSource(
            OperationalCrossSectionLut,
            allocator,
            wavelengths_nm,
            source,
            controls,
        );
    }

    /// Purpose:
    ///   Release owned LUT storage.
    pub fn deinitOwned(self: *OperationalCrossSectionLut, allocator: Allocator) void {
        allocator.free(self.wavelengths_nm);
        allocator.free(self.coefficients);
        self.* = .{};
    }

    /// Purpose:
    ///   Evaluate the LUT sigma at a wavelength, temperature, and pressure.
    ///
    /// Physics:
    ///   Interpolates wavelength samples after evaluating the Legendre basis in scaled log coordinates.
    pub fn sigmaAt(
        self: *const OperationalCrossSectionLut,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) f64 {
        return eval_helpers.evaluate(@This(), self, wavelength_nm, temperature_k, pressure_hpa).sigma;
    }

    /// Purpose:
    ///   Evaluate the LUT temperature derivative at a wavelength, temperature, and pressure.
    pub fn dSigmaDTemperatureAt(
        self: *const OperationalCrossSectionLut,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) f64 {
        return eval_helpers.evaluate(@This(), self, wavelength_nm, temperature_k, pressure_hpa).d_sigma_d_temperature;
    }
};

test "generated cross-section LUT reproduces direct table values" {
    const wavelengths = [_]f64{ 430.0, 431.0, 432.0 };
    const points = [_]ReferenceData.CrossSectionPoint{
        .{ .wavelength_nm = 430.0, .sigma_cm2_per_molecule = 2.0e-19 },
        .{ .wavelength_nm = 431.0, .sigma_cm2_per_molecule = 3.0e-19 },
        .{ .wavelength_nm = 432.0, .sigma_cm2_per_molecule = 4.0e-19 },
    };
    const table: ReferenceData.CrossSectionTable = .{ .points = @constCast(points[0..]) };
    const lut = try OperationalCrossSectionLut.buildFromSource(
        std.testing.allocator,
        wavelengths[0..],
        .{ .cross_section_table = &table },
        .{
            .mode = .generate,
            .min_temperature_k = 180.0,
            .max_temperature_k = 325.0,
            .min_pressure_hpa = 0.03,
            .max_pressure_hpa = 1050.0,
            .temperature_grid_count = 6,
            .pressure_grid_count = 8,
            .temperature_coefficient_count = 3,
            .pressure_coefficient_count = 4,
        },
    );
    defer {
        var owned = lut;
        owned.deinitOwned(std.testing.allocator);
    }

    try std.testing.expectApproxEqRel(@as(f64, 3.0e-19), lut.sigmaAt(431.0, 250.0, 600.0), 1.0e-10);
    try std.testing.expectApproxEqRel(@as(f64, 0.0), lut.dSigmaDTemperatureAt(431.0, 250.0, 600.0), 1.0e-10);
}

test "generated cross-section LUT rejects consume-mode source builds" {
    const wavelengths = [_]f64{430.0};
    const points = [_]ReferenceData.CrossSectionPoint{
        .{ .wavelength_nm = 430.0, .sigma_cm2_per_molecule = 2.0e-19 },
    };
    const table: ReferenceData.CrossSectionTable = .{ .points = @constCast(points[0..]) };

    try std.testing.expectError(errors.Error.InvalidRequest, OperationalCrossSectionLut.buildFromSource(
        std.testing.allocator,
        wavelengths[0..],
        .{ .cross_section_table = &table },
        .{ .mode = .consume },
    ));
}

test "cross-section LUT extrapolates scaled log coordinates outside configured temperature range" {
    const lut: OperationalCrossSectionLut = .{
        .wavelengths_nm = &[_]f64{431.0},
        .coefficients = &[_]f64{
            0.0,
            1.0,
        },
        .temperature_coefficient_count = 2,
        .pressure_coefficient_count = 1,
        .min_temperature_k = 100.0,
        .max_temperature_k = 200.0,
        .min_pressure_hpa = 10.0,
        .max_pressure_hpa = 1000.0,
    };
    try lut.validate();

    const ln_span = @log(lut.max_temperature_k) - @log(lut.min_temperature_k);
    const expected_scaled_lnT =
        -((@log(lut.max_temperature_k) + @log(lut.min_temperature_k)) / ln_span) +
        (2.0 * @log(@as(f64, 50.0)) / ln_span);
    const expected_derivative = 2.0 / (ln_span * 50.0);

    try std.testing.expect(expected_scaled_lnT < -1.0);
    try std.testing.expectApproxEqRel(expected_scaled_lnT, lut.sigmaAt(431.0, 50.0, 100.0), 1.0e-12);
    try std.testing.expectApproxEqRel(expected_derivative, lut.dSigmaDTemperatureAt(431.0, 50.0, 100.0), 1.0e-12);
}

test "cross-section LUT keeps non-positive temperature and pressure inputs finite" {
    const lut: OperationalCrossSectionLut = .{
        .wavelengths_nm = &[_]f64{431.0},
        .coefficients = &[_]f64{
            0.0,
            1.0,
        },
        .temperature_coefficient_count = 2,
        .pressure_coefficient_count = 1,
        .min_temperature_k = 100.0,
        .max_temperature_k = 200.0,
        .min_pressure_hpa = 10.0,
        .max_pressure_hpa = 1000.0,
    };
    try lut.validate();

    const sigma = lut.sigmaAt(431.0, 0.0, 0.0);
    const derivative = lut.dSigmaDTemperatureAt(431.0, 0.0, 0.0);

    try std.testing.expect(std.math.isFinite(sigma));
    try std.testing.expect(std.math.isFinite(derivative));
    try std.testing.expectApproxEqRel(
        lut.sigmaAt(431.0, lut.min_temperature_k, lut.min_pressure_hpa),
        sigma,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), derivative, 1.0e-12);
}
