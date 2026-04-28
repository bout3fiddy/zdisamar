const std = @import("std");
const errors = @import("../common/errors.zig");
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
const legacy_support = @import("observation_legacy_support.zig");

pub const ObservationRegime = enum {
    nadir,
    limb,
    occultation,
};

pub const CrossSectionFitControls = struct {
    use_effective_cross_section_oe: bool = false,
    use_polynomial_expansion: bool = false,
    xsec_strong_absorption_bands: []const bool = &.{},
    polynomial_degree_bands: []const u32 = &.{},

    pub fn validate(self: CrossSectionFitControls) errors.Error!void {
        for (self.polynomial_degree_bands) |degree| {
            if (degree > 7) return errors.Error.InvalidRequest;
        }
    }

    pub fn validateForBandCount(self: CrossSectionFitControls, band_count: usize) errors.Error!void {
        try self.validate();
        if (self.xsec_strong_absorption_bands.len != 0 and self.xsec_strong_absorption_bands.len != band_count) {
            return errors.Error.InvalidRequest;
        }
        if (self.polynomial_degree_bands.len != 0 and self.polynomial_degree_bands.len != band_count) {
            return errors.Error.InvalidRequest;
        }
    }

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

    pub fn deinitOwned(self: *CrossSectionFitControls, allocator: Allocator) void {
        if (self.xsec_strong_absorption_bands.len != 0) allocator.free(self.xsec_strong_absorption_bands);
        if (self.polynomial_degree_bands.len != 0) allocator.free(self.polynomial_degree_bands);
        self.* = .{};
    }

    pub fn strongAbsorptionForBand(self: CrossSectionFitControls, band_index: usize) bool {
        if (band_index >= self.xsec_strong_absorption_bands.len) return false;
        return self.xsec_strong_absorption_bands[band_index];
    }

    pub fn polynomialOrderForBand(self: CrossSectionFitControls, band_index: usize) u32 {
        if (band_index >= self.polynomial_degree_bands.len) return 0;
        return self.polynomial_degree_bands[band_index];
    }

    pub fn maximumPolynomialOrder(self: CrossSectionFitControls) u32 {
        var maximum: u32 = 0;
        for (self.polynomial_degree_bands) |degree| {
            maximum = @max(maximum, degree);
        }
        return maximum;
    }
};

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
                //   Input-driven noise models require an explicit sigma vector so radiative transfer and
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

    pub fn resolvedChannelControls(self: *const ObservationModel, channel: SpectralChannel) Instrument.SpectralChannelControls {
        return legacy_support.resolvedChannelControls(self, channel);
    }

    pub fn resolvedRingControls(self: *const ObservationModel) Instrument.RingControls {
        return self.measurement_pipeline.ring;
    }

    pub fn operationalBandCount(self: *const ObservationModel) usize {
        return legacy_support.operationalBandCount(self);
    }

    pub fn primaryOperationalBandSupport(self: *const ObservationModel) OperationalBandSupport {
        return legacy_support.primaryOperationalBandSupport(self);
    }

    pub fn lutSamplingHalfSpanNm(self: *const ObservationModel) f64 {
        return legacy_support.lutSamplingHalfSpanNm(self.primaryOperationalBandSupport());
    }

    pub fn resolvedOperationalBandSupport(
        self: *const ObservationModel,
        band_index: usize,
    ) ?OperationalBandSupport {
        return legacy_support.resolvedOperationalBandSupport(self, band_index);
    }

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

    pub fn resolvedReflectanceCalibration(self: *const ObservationModel) Instrument.ReflectanceCalibration {
        return self.measurement_pipeline.reflectance_calibration;
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
