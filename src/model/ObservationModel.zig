//! Purpose:
//!   Define the typed observation-model contract attached to a canonical scene.
//!
//! Physics:
//!   Captures instrument regime, calibration offsets, line-shape/reference carriers, solar
//!   spectra, operational LUTs, and optional measured-channel supporting data.
//!
//! Vendor:
//!   `observation-model and instrument-support contract`
//!
//! Design:
//!   Keep instrument/observation configuration typed and self-contained so adapters can hydrate
//!   operational metadata without leaking file-format policy into kernels.
//!
//! Invariants:
//!   Calibration fields must be finite, optional measured channels must be strictly increasing,
//!   and noise/support arrays must stay shape-consistent with their associated wavelengths.
//!
//! Validation:
//!   Observation-model validation tests in this file and the execution tests that hydrate
//!   measured-channel and operational observation metadata.

const std = @import("std");
const errors = @import("../core/errors.zig");
const Binding = @import("Binding.zig").Binding;
const Instrument = @import("Instrument.zig").Instrument;
const InstrumentId = @import("Instrument.zig").Id;
const BuiltinLineShapeKind = @import("Instrument.zig").BuiltinLineShapeKind;
const AdaptiveReferenceGrid = @import("Instrument.zig").AdaptiveReferenceGrid;
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

/// Purpose:
///   Store per-band cross-section fitting controls shared by simulation and retrieval scenes.
pub const CrossSectionFitControls = struct {
    use_effective_cross_section_oe: bool = false,
    use_polynomial_expansion: bool = false,
    xsec_strong_absorption_bands: []const bool = &.{},
    polynomial_degree_bands: []const u32 = &.{},

    /// Purpose:
    ///   Validate the owned slices and reject obviously inconsistent control payloads.
    pub fn validate(self: CrossSectionFitControls) errors.Error!void {
        for (self.polynomial_degree_bands) |degree| {
            if (degree > 16) return errors.Error.InvalidRequest;
        }
    }

    /// Purpose:
    ///   Ensure any configured per-band vectors match the resolved scene band count.
    pub fn validateForBandCount(self: CrossSectionFitControls, band_count: usize) errors.Error!void {
        try self.validate();
        if (self.xsec_strong_absorption_bands.len != 0 and self.xsec_strong_absorption_bands.len != band_count) {
            return errors.Error.InvalidRequest;
        }
        if (self.polynomial_degree_bands.len != 0 and self.polynomial_degree_bands.len != band_count) {
            return errors.Error.InvalidRequest;
        }
    }

    /// Purpose:
    ///   Deep-clone the per-band control vectors into owned storage.
    pub fn clone(self: CrossSectionFitControls, allocator: Allocator) !CrossSectionFitControls {
        return .{
            .use_effective_cross_section_oe = self.use_effective_cross_section_oe,
            .use_polynomial_expansion = self.use_polynomial_expansion,
            .xsec_strong_absorption_bands = if (self.xsec_strong_absorption_bands.len != 0)
                try allocator.dupe(bool, self.xsec_strong_absorption_bands)
            else
                &.{},
            .polynomial_degree_bands = if (self.polynomial_degree_bands.len != 0)
                try allocator.dupe(u32, self.polynomial_degree_bands)
            else
                &.{},
        };
    }

    /// Purpose:
    ///   Release any owned per-band control storage.
    pub fn deinitOwned(self: *CrossSectionFitControls, allocator: Allocator) void {
        if (self.xsec_strong_absorption_bands.len != 0) allocator.free(self.xsec_strong_absorption_bands);
        if (self.polynomial_degree_bands.len != 0) allocator.free(self.polynomial_degree_bands);
        self.* = .{};
    }

    /// Purpose:
    ///   Report whether a band is flagged as a strong-absorption interval.
    pub fn strongAbsorptionForBand(self: CrossSectionFitControls, band_index: usize) bool {
        if (band_index >= self.xsec_strong_absorption_bands.len) return false;
        return self.xsec_strong_absorption_bands[band_index];
    }

    /// Purpose:
    ///   Return the configured polynomial degree for a band, or zero when absent.
    pub fn polynomialOrderForBand(self: CrossSectionFitControls, band_index: usize) u32 {
        if (band_index >= self.polynomial_degree_bands.len) return 0;
        return self.polynomial_degree_bands[band_index];
    }
};

/// Purpose:
///   Store the observation-side configuration and supporting data required to evaluate a scene.
pub const ObservationModel = struct {
    instrument: InstrumentId = .generic,
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
    adaptive_reference_grid: AdaptiveReferenceGrid = .{},
    solar_spectrum_source: Binding = .none,
    weighted_reference_grid_source: Binding = .none,
    instrument_line_shape: InstrumentLineShape = .{},
    instrument_line_shape_table: InstrumentLineShapeTable = .{},
    operational_refspec_grid: OperationalReferenceGrid = .{},
    operational_solar_spectrum: OperationalSolarSpectrum = .{},
    o2_operational_lut: OperationalCrossSectionLut = .{},
    o2o2_operational_lut: OperationalCrossSectionLut = .{},
    cross_section_fit: CrossSectionFitControls = .{},
    measured_wavelengths_nm: []const f64 = &.{},
    owns_measured_wavelengths: bool = false,
    reference_radiance: []const f64 = &.{},
    owns_reference_radiance: bool = false,
    ingested_noise_sigma: []const f64 = &.{},

    /// Purpose:
    ///   Validate calibration, measured-channel, and operational-support metadata.
    pub fn validate(self: *const ObservationModel) errors.Error!void {
        try self.solar_spectrum_source.validate();
        try self.weighted_reference_grid_source.validate();
        try self.instrument.validate();
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
                // INVARIANT:
                //   Input-driven noise models require an explicit sigma vector so transport and
                //   retrieval code can treat the noise contract as already materialized.
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
            // GOTCHA:
            //   High-resolution sampling is an all-or-nothing contract. A single nonzero field
            //   would under-specify the convolution support grid.
            return errors.Error.InvalidRequest;
        }
        try self.adaptive_reference_grid.validate();
        try self.instrument_line_shape.validate();
        try self.instrument_line_shape_table.validate();
        try self.operational_refspec_grid.validate();
        try self.operational_solar_spectrum.validate();
        try self.o2_operational_lut.validate();
        try self.o2o2_operational_lut.validate();
        try self.cross_section_fit.validate();
    }

    /// Purpose:
    ///   Release any owned line-shape, grid, solar-spectrum, LUT, and measured-channel storage.
    pub fn deinitOwned(self: *ObservationModel, allocator: Allocator) void {
        self.instrument_line_shape.deinitOwned(allocator);
        self.instrument_line_shape_table.deinitOwned(allocator);
        self.operational_refspec_grid.deinitOwned(allocator);
        self.operational_solar_spectrum.deinitOwned(allocator);
        self.o2_operational_lut.deinitOwned(allocator);
        self.o2o2_operational_lut.deinitOwned(allocator);
        self.cross_section_fit.deinitOwned(allocator);
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
        .instrument = .tropomi,
        .solar_spectrum_source = .bundle_default,
        .weighted_reference_grid_source = .{ .ingest = .{
            .full_name = "refspec_demo.grid",
            .ingest_name = "refspec_demo",
            .output_name = "grid",
        } },
        .sampling = .operational,
        .noise_model = .shot_noise,
        .multiplicative_offset = 1.002,
        .stray_light = 0.0007,
        .adaptive_reference_grid = .{
            .points_per_fwhm = 5,
            .strong_line_min_divisions = 3,
            .strong_line_max_divisions = 8,
        },
    };

    try std.testing.expectEqual(Instrument.SamplingMode.operational, model.sampling);
    try std.testing.expectEqual(Instrument.NoiseModelKind.shot_noise, model.noise_model);
    try model.validate();
}

test "observation model carries explicit measured-channel wavelengths" {
    const measured_wavelengths = [_]f64{ 760.8, 761.02, 761.31 };
    const model: ObservationModel = .{
        .instrument = .tropomi,
        .sampling = .measured_channels,
        .noise_model = .snr_from_input,
        .measured_wavelengths_nm = &measured_wavelengths,
        .reference_radiance = &.{ 1.2, 1.1, 1.0 },
        .ingested_noise_sigma = &.{ 0.02, 0.03, 0.025 },
    };

    try model.validate();
    try std.testing.expectEqual(@as(f64, 761.02), model.measured_wavelengths_nm[1]);
}

test "cross-section fit controls validate band-scoped settings" {
    const valid: CrossSectionFitControls = .{
        .use_effective_cross_section_oe = true,
        .use_polynomial_expansion = true,
        .xsec_strong_absorption_bands = &.{ true, false },
        .polynomial_degree_bands = &.{ 5, 3 },
    };

    try valid.validateForBandCount(2);
    try std.testing.expect(valid.strongAbsorptionForBand(0));
    try std.testing.expectEqual(@as(u32, 3), valid.polynomialOrderForBand(1));
    try std.testing.expectEqual(@as(u32, 0), valid.polynomialOrderForBand(3));

    try std.testing.expectError(
        errors.Error.InvalidRequest,
        (CrossSectionFitControls{
            .polynomial_degree_bands = &.{ 4, 2 },
        }).validateForBandCount(1),
    );
}
