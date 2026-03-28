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
const OperationalBandSupport = @import("Instrument.zig").Instrument.OperationalBandSupport;
const OperationalReferenceGrid = @import("Instrument.zig").OperationalReferenceGrid;
const OperationalSolarSpectrum = @import("Instrument.zig").OperationalSolarSpectrum;
const OperationalCrossSectionLut = @import("Instrument.zig").OperationalCrossSectionLut;
const SpectralChannel = @import("Instrument.zig").SpectralChannel;
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
            if (degree > 7) return errors.Error.InvalidRequest;
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
        const strong_absorption_bands = if (self.xsec_strong_absorption_bands.len != 0)
            try allocator.dupe(bool, self.xsec_strong_absorption_bands)
        else
            &.{};
        errdefer if (strong_absorption_bands.len != 0) allocator.free(strong_absorption_bands);

        const polynomial_degree_bands = if (self.polynomial_degree_bands.len != 0)
            try allocator.dupe(u32, self.polynomial_degree_bands)
        else
            &.{};
        errdefer if (polynomial_degree_bands.len != 0) allocator.free(polynomial_degree_bands);

        return .{
            .use_effective_cross_section_oe = self.use_effective_cross_section_oe,
            .use_polynomial_expansion = self.use_polynomial_expansion,
            .xsec_strong_absorption_bands = strong_absorption_bands,
            .polynomial_degree_bands = polynomial_degree_bands,
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

    /// Purpose:
    ///   Return the highest configured polynomial degree across all bands.
    pub fn maximumPolynomialOrder(self: CrossSectionFitControls) u32 {
        var maximum: u32 = 0;
        for (self.polynomial_degree_bands) |degree| {
            maximum = @max(maximum, degree);
        }
        return maximum;
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
    operational_band_support: []const OperationalBandSupport = &.{},
    owns_operational_band_support: bool = false,
    measurement_pipeline: Instrument.MeasurementPipeline = .{},
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
            .lab_operational => {
                const radiance_noise = self.resolvedChannelControls(.radiance).noise;
                const irradiance_noise = self.resolvedChannelControls(.irradiance).noise;
                if (radiance_noise.model != .lab_operational or irradiance_noise.model != .lab_operational) {
                    return errors.Error.InvalidRequest;
                }
                try radiance_noise.validate();
                try irradiance_noise.validate();
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
        if (self.operational_band_support.len > 1) {
            // GOTCHA:
            //   Runtime consumers still resolve one operational support record per scene. Reject
            //   multi-band support until optics/measurement prep becomes truly band-indexed rather
            //   than silently dropping enabled replacements for bands > 0.
            return errors.Error.InvalidRequest;
        }
        for (self.operational_band_support, 0..) |*support, index| {
            try support.validate();
            for (self.operational_band_support[index + 1 ..]) |other| {
                if (std.mem.eql(u8, support.id, other.id)) return errors.Error.InvalidRequest;
            }
        }
        try self.measurement_pipeline.validate();
        try self.cross_section_fit.validate();
    }

    /// Purpose:
    ///   Resolve the effective per-channel measurement controls, preserving legacy defaults
    ///   until callers opt into the explicit channel pipeline.
    pub fn resolvedChannelControls(self: *const ObservationModel, channel: SpectralChannel) Instrument.SpectralChannelControls {
        return switch (channel) {
            .radiance => if (self.measurement_pipeline.radiance.explicit)
                self.measurement_pipeline.radiance
            else
                self.legacyChannelControls(.radiance),
            .irradiance => if (self.measurement_pipeline.irradiance.explicit)
                self.measurement_pipeline.irradiance
            else
                self.legacyChannelControls(.irradiance),
        };
    }

    /// Purpose:
    ///   Return the explicit Ring controls, or a disabled record when absent.
    pub fn resolvedRingControls(self: *const ObservationModel) Instrument.RingControls {
        return self.measurement_pipeline.ring;
    }

    /// Purpose:
    ///   Return how many explicit operational band replacements are attached to the model.
    pub fn operationalBandCount(self: *const ObservationModel) usize {
        if (self.operational_band_support.len != 0) return self.operational_band_support.len;
        return if (legacyOperationalBandSupport(self).enabled()) 1 else 0;
    }

    /// Purpose:
    ///   Resolve the primary operational replacement set, falling back to the legacy singleton fields.
    pub fn primaryOperationalBandSupport(self: *const ObservationModel) OperationalBandSupport {
        return self.resolvedOperationalBandSupport(0) orelse .{};
    }

    /// Purpose:
    ///   Return the explicit support record for a band, or the legacy singleton view for band zero.
    pub fn resolvedOperationalBandSupport(
        self: *const ObservationModel,
        band_index: usize,
    ) ?OperationalBandSupport {
        if (band_index < self.operational_band_support.len) {
            return self.operational_band_support[band_index];
        }
        if (band_index == 0) {
            const legacy = legacyOperationalBandSupport(self);
            if (legacy.enabled()) return legacy;
        }
        return null;
    }

    /// Purpose:
    ///   Materialize stable provenance labels for each active operational replacement band.
    pub fn operationalReplacementLabelsOwned(
        self: *const ObservationModel,
        allocator: Allocator,
    ) ![]const []const u8 {
        const band_count = self.operationalBandCount();
        if (band_count == 0) return &.{};

        const labels = try allocator.alloc([]const u8, band_count);
        errdefer allocator.free(labels);

        var built: usize = 0;
        errdefer {
            for (labels[0..built]) |label| allocator.free(label);
        }

        for (0..band_count) |band_index| {
            const support = self.resolvedOperationalBandSupport(band_index).?;
            labels[band_index] = try supportReplacementLabelOwned(allocator, support, band_index);
            built = band_index + 1;
        }
        return labels;
    }

    /// Purpose:
    ///   Return reflectance calibration-error controls for sigma propagation.
    pub fn resolvedReflectanceCalibration(self: *const ObservationModel) Instrument.ReflectanceCalibration {
        return self.measurement_pipeline.reflectance_calibration;
    }

    fn legacyChannelControls(self: *const ObservationModel, channel: SpectralChannel) Instrument.SpectralChannelControls {
        var controls: Instrument.SpectralChannelControls = .{
            .response = legacySpectralResponse(self),
            .wavelength_shift_nm = self.wavelength_shift_nm,
            .noise = .{
                .enabled = legacyNoiseEnabled(self.noise_model, channel),
                .model = legacyNoiseModel(self.noise_model, channel),
                .reference_signal = if (channel == .radiance) self.reference_radiance else &.{},
                .reference_sigma = if (channel == .radiance) self.ingested_noise_sigma else &.{},
            },
        };
        if (channel == .radiance) {
            controls.multiplicative_offset = self.multiplicative_offset;
            controls.stray_light = self.stray_light;
            controls.use_polarization_scrambler = true;
        }
        return controls;
    }

    fn legacySpectralResponse(self: *const ObservationModel) Instrument.SpectralResponse {
        const support = self.primaryOperationalBandSupport();
        return .{
            .slit_index = switch (self.builtin_line_shape) {
                .gaussian => if (support.instrument_line_shape_table.nominal_count > 0 or self.instrument_line_shape_table.nominal_count > 0) .table else .gaussian_modulated,
                .flat_top_n4 => .flat_top_n4,
                .triple_flat_top_n4 => .triple_flat_top_n4,
            },
            .fwhm_nm = self.instrument_line_fwhm_nm,
            .builtin_line_shape = self.builtin_line_shape,
            .high_resolution_step_nm = if (support.high_resolution_step_nm > 0.0)
                support.high_resolution_step_nm
            else
                self.high_resolution_step_nm,
            .high_resolution_half_span_nm = if (support.high_resolution_half_span_nm > 0.0)
                support.high_resolution_half_span_nm
            else
                self.high_resolution_half_span_nm,
            // DECISION:
            //   Legacy channel controls borrow the observation-model line-shape carriers.
            //   The derived controls can be copied into the explicit measurement pipeline,
            //   so they must not inherit ownership and double-free the same backing slices
            //   during teardown.
            .instrument_line_shape = if (support.instrument_line_shape.sample_count > 0)
                borrowedLineShape(support.instrument_line_shape)
            else
                borrowedLineShape(self.instrument_line_shape),
            .instrument_line_shape_table = if (support.instrument_line_shape_table.nominal_count > 0)
                borrowedLineShapeTable(support.instrument_line_shape_table)
            else
                borrowedLineShapeTable(self.instrument_line_shape_table),
        };
    }

    fn legacyOperationalBandSupport(self: *const ObservationModel) OperationalBandSupport {
        return .{
            .id = if (self.instrument != .unset) "primary" else "",
            .high_resolution_step_nm = self.high_resolution_step_nm,
            .high_resolution_half_span_nm = self.high_resolution_half_span_nm,
            .instrument_line_shape = borrowedLineShape(self.instrument_line_shape),
            .instrument_line_shape_table = borrowedLineShapeTable(self.instrument_line_shape_table),
            .operational_refspec_grid = self.operational_refspec_grid,
            .operational_solar_spectrum = self.operational_solar_spectrum,
            .o2_operational_lut = self.o2_operational_lut,
            .o2o2_operational_lut = self.o2o2_operational_lut,
        };
    }

    fn borrowedLineShape(line_shape: InstrumentLineShape) InstrumentLineShape {
        var borrowed = line_shape;
        borrowed.owns_memory = false;
        return borrowed;
    }

    fn borrowedLineShapeTable(line_shape_table: InstrumentLineShapeTable) InstrumentLineShapeTable {
        var borrowed = line_shape_table;
        borrowed.owns_memory = false;
        return borrowed;
    }

    fn legacyNoiseEnabled(model: Instrument.NoiseModelKind, channel: SpectralChannel) bool {
        return switch (channel) {
            .radiance => model != .none,
            .irradiance => switch (model) {
                .shot_noise, .lab_operational => true,
                .none, .s5p_operational, .snr_from_input => false,
            },
        };
    }

    fn legacyNoiseModel(model: Instrument.NoiseModelKind, channel: SpectralChannel) Instrument.NoiseModelKind {
        if (channel == .radiance) return model;
        return switch (model) {
            .shot_noise, .lab_operational => model,
            .none, .s5p_operational, .snr_from_input => .none,
        };
    }

    fn supportReplacementLabelOwned(
        allocator: Allocator,
        support: OperationalBandSupport,
        band_index: usize,
    ) ![]const u8 {
        var buffer = std.ArrayList(u8).empty;
        defer buffer.deinit(allocator);

        if (support.id.len != 0) {
            try buffer.writer(allocator).print("{s}:", .{support.id});
        } else {
            try buffer.writer(allocator).print("band-{d}:", .{band_index});
        }

        if (support.high_resolution_step_nm > 0.0) try buffer.appendSlice(allocator, "hr_grid,");
        if (support.instrument_line_shape.sample_count > 0 or support.instrument_line_shape_table.nominal_count > 0) {
            try buffer.appendSlice(allocator, "isrf,");
        }
        if (support.operational_refspec_grid.enabled()) try buffer.appendSlice(allocator, "refspec,");
        if (support.operational_solar_spectrum.enabled()) try buffer.appendSlice(allocator, "solar,");
        if (support.o2_operational_lut.enabled()) try buffer.appendSlice(allocator, "o2_lut,");
        if (support.o2o2_operational_lut.enabled()) try buffer.appendSlice(allocator, "o2o2_lut,");
        if (buffer.items[buffer.items.len - 1] == ',') _ = buffer.pop();

        return buffer.toOwnedSlice(allocator);
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
        if (self.owns_operational_band_support) {
            for (self.operational_band_support) |support| {
                var owned = support;
                owned.deinitOwned(allocator);
            }
            if (self.operational_band_support.len != 0) allocator.free(self.operational_band_support);
        }
        self.operational_band_support = &.{};
        self.owns_operational_band_support = false;
        self.measurement_pipeline.deinitOwned(allocator);
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

test "observation model rejects lab operational noise without explicit LAB coefficients" {
    const invalid_model: ObservationModel = .{
        .noise_model = .lab_operational,
    };

    try std.testing.expectError(errors.Error.InvalidRequest, invalid_model.validate());
}

test "observation model keeps borrowed legacy noise references when SNR tables are owned" {
    const measured_wavelengths = [_]f64{760.8};
    const reference_radiance = [_]f64{1.2};
    const ingested_noise_sigma = [_]f64{0.02};
    const model: ObservationModel = .{
        .instrument = .tropomi,
        .noise_model = .s5p_operational,
        .measured_wavelengths_nm = &measured_wavelengths,
        .reference_radiance = &reference_radiance,
        .ingested_noise_sigma = &ingested_noise_sigma,
    };

    var controls = model.resolvedChannelControls(.radiance);
    const snr_wavelengths_nm = try std.testing.allocator.dupe(f64, &.{760.8});
    errdefer std.testing.allocator.free(snr_wavelengths_nm);
    const snr_values = try std.testing.allocator.dupe(f64, &.{250.0});
    errdefer std.testing.allocator.free(snr_values);

    controls.noise.snr_wavelengths_nm = snr_wavelengths_nm;
    controls.noise.snr_values = snr_values;
    controls.noise.owns_snr_memory = true;
    defer controls.noise.deinitOwned(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), controls.noise.reference_signal.len);
    try std.testing.expectEqual(@as(usize, 1), controls.noise.reference_sigma.len);
}

test "observation model legacy spectral response borrows owned line-shape carriers" {
    var line_shape: InstrumentLineShape = .{
        .sample_count = 2,
        .offsets_nm = try std.testing.allocator.dupe(f64, &.{ -0.1, 0.1 }),
        .weights = try std.testing.allocator.dupe(f64, &.{ 0.4, 0.6 }),
        .owns_memory = true,
    };
    errdefer line_shape.deinitOwned(std.testing.allocator);

    var line_shape_table: InstrumentLineShapeTable = .{
        .nominal_count = 1,
        .sample_count = 2,
        .nominal_wavelengths_nm = try std.testing.allocator.dupe(f64, &.{760.8}),
        .offsets_nm = try std.testing.allocator.dupe(f64, &.{ -0.1, 0.1 }),
        .weights = try std.testing.allocator.dupe(f64, &.{ 0.45, 0.55 }),
        .owns_memory = true,
    };
    errdefer line_shape_table.deinitOwned(std.testing.allocator);

    var model: ObservationModel = .{
        .instrument = .tropomi,
        .builtin_line_shape = .gaussian,
        .instrument_line_fwhm_nm = 0.38,
        .instrument_line_shape = line_shape,
        .instrument_line_shape_table = line_shape_table,
        .noise_model = .none,
    };
    defer model.deinitOwned(std.testing.allocator);

    var radiance = model.resolvedChannelControls(.radiance);
    radiance.explicit = true;
    model.measurement_pipeline.radiance = radiance;

    try std.testing.expect(!radiance.response.instrument_line_shape.owns_memory);
    try std.testing.expect(!radiance.response.instrument_line_shape_table.owns_memory);
    try std.testing.expectEqual(
        @intFromPtr(model.instrument_line_shape.offsets_nm.ptr),
        @intFromPtr(radiance.response.instrument_line_shape.offsets_nm.ptr),
    );
    try std.testing.expectEqual(
        @intFromPtr(model.instrument_line_shape_table.weights.ptr),
        @intFromPtr(radiance.response.instrument_line_shape_table.weights.ptr),
    );
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
    try std.testing.expectEqual(@as(u32, 5), valid.maximumPolynomialOrder());

    try std.testing.expectError(
        errors.Error.InvalidRequest,
        (CrossSectionFitControls{
            .polynomial_degree_bands = &.{ 4, 2 },
        }).validateForBandCount(1),
    );
    try std.testing.expectError(
        errors.Error.InvalidRequest,
        (CrossSectionFitControls{
            .polynomial_degree_bands = &.{8},
        }).validate(),
    );
}

fn cloneCrossSectionFitControlsWithAllocator(allocator: Allocator) !void {
    const controls: CrossSectionFitControls = .{
        .use_effective_cross_section_oe = true,
        .use_polynomial_expansion = true,
        .xsec_strong_absorption_bands = &.{ true, false },
        .polynomial_degree_bands = &.{ 5, 3 },
    };

    var cloned = try controls.clone(allocator);
    defer cloned.deinitOwned(allocator);
}

test "cross-section fit controls clone cleans up across allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        cloneCrossSectionFitControlsWithAllocator,
        .{},
    );
}

test "observation model rejects multi-band operational support until runtime becomes band-indexed" {
    const support = [_]OperationalBandSupport{
        .{ .id = "band-0" },
        .{ .id = "band-1" },
    };
    var model: ObservationModel = .{
        .operational_band_support = &support,
    };

    try std.testing.expectError(error.InvalidRequest, model.validate());
}
