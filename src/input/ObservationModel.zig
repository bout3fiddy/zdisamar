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

pub const ObservationRegime = enum {
    nadir,
    limb,
    occultation,
};

// layout(64-bit):
//   size: 40 B, align: 8 B
//   field storage: xsec_strong_absorption_bands=16 B, polynomial_degree_bands=16 B, use_effective_cross_section_oe=1 B, use_polynomial_expansion=1 B; padding: 6 B (48 bits)
//   unused bits: 48 padding + 14 bool-storage slack = 62 bits
//   out-of-line: xsec_strong_absorption_bands, polynomial_degree_bands carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 40 B (0.039 KiB); total also includes referenced storage above
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

// layout(64-bit):
//   size: 600 B, align: 8 B
//   field storage: 596 B across 25 fields; largest: o2o2_operational_lut=72 B, o2_operational_lut=72 B; padding: 4 B (32 bits)
//   unused bits: 32 padding + 14 bool-storage slack = 46 bits
//   out-of-line: measured_wavelengths_nm and operational_band_support carry references/descriptors; referenced storage is not included in size
//   cache span: 10 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 600 B (0.586 KiB); total also includes referenced storage above
pub const ObservationModel = struct {
    instrument: InstrumentId = .generic,
    regime: ObservationRegime = .nadir,
    sampling: Instrument.SamplingMode = .native,
    wavelength_shift_nm: f64 = 0.0,
    multiplicative_offset: f64 = 1.0,
    stray_light: f64 = 0.0,
    instrument_line_fwhm_nm: f64 = 0.0,
    builtin_line_shape: BuiltinLineShapeKind = .gaussian,
    high_resolution_step_nm: f64 = 0.0,
    high_resolution_half_span_nm: f64 = 0.0,
    integration_mode: Instrument.SpectralResponse.IntegrationMode = .auto,
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
    cross_section_fit: CrossSectionFitControls = .{},
    measured_wavelengths_nm: []const f64 = &.{},
    owns_measured_wavelengths: bool = false,

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
        if (self.measured_wavelengths_nm.len != 0) {
            var previous_wavelength: ?f64 = null;
            for (self.measured_wavelengths_nm) |wavelength_nm| {
                if (!std.math.isFinite(wavelength_nm)) return errors.Error.InvalidRequest;
                if (previous_wavelength) |previous| {
                    if (wavelength_nm <= previous) return errors.Error.InvalidRequest;
                }
                previous_wavelength = wavelength_nm;
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
        try self.cross_section_fit.validate();
    }

    pub fn resolvedChannelControls(self: *const ObservationModel, channel: SpectralChannel) Instrument.SpectralChannelControls {
        return legacyChannelControls(self, channel);
    }

    pub fn operationalBandCount(self: *const ObservationModel) usize {
        return operationalBandCountFromLegacy(self);
    }

    pub fn primaryOperationalBandSupport(self: *const ObservationModel) OperationalBandSupport {
        return primaryOperationalBandSupportFromLegacy(self);
    }

    pub fn lutSamplingHalfSpanNm(self: *const ObservationModel) f64 {
        return lutSamplingHalfSpanForSupport(self.primaryOperationalBandSupport());
    }

    pub fn resolvedOperationalBandSupport(
        self: *const ObservationModel,
        band_index: usize,
    ) ?OperationalBandSupport {
        return resolvedOperationalBandSupportFromLegacy(self, band_index);
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
        self.cross_section_fit.deinitOwned(allocator);
        if (self.owns_measured_wavelengths and self.measured_wavelengths_nm.len != 0) allocator.free(self.measured_wavelengths_nm);
        self.measured_wavelengths_nm = &.{};
        self.owns_measured_wavelengths = false;
    }
};

fn operationalBandCountFromLegacy(model: *const ObservationModel) usize {
    if (model.operational_band_support.len != 0) return model.operational_band_support.len;
    return if (legacyOperationalBandSupport(model).enabled()) 1 else 0;
}

fn primaryOperationalBandSupportFromLegacy(model: *const ObservationModel) OperationalBandSupport {
    return resolvedOperationalBandSupportFromLegacy(model, 0) orelse .{};
}

fn resolvedOperationalBandSupportFromLegacy(
    model: *const ObservationModel,
    band_index: usize,
) ?OperationalBandSupport {
    if (band_index < model.operational_band_support.len) {
        return mergedOperationalBandSupport(
            model.operational_band_support[band_index],
            legacyOperationalBandSupport(model),
        );
    }
    if (band_index == 0) {
        const legacy = legacyOperationalBandSupport(model);
        if (legacy.enabled()) return legacy;
    }
    return null;
}

fn lutSamplingHalfSpanForSupport(support: OperationalBandSupport) f64 {
    if (support.high_resolution_step_nm <= 0.0) return 0.0;

    var half_span_nm = support.high_resolution_half_span_nm;
    if (support.instrument_line_shape.sample_count > 0) {
        for (support.instrument_line_shape.offsets_nm[0..support.instrument_line_shape.sample_count]) |offset_nm| {
            half_span_nm = @max(half_span_nm, @abs(offset_nm));
        }
    }
    if (support.instrument_line_shape_table.sample_count > 0) {
        for (support.instrument_line_shape_table.offsets_nm[0..support.instrument_line_shape_table.sample_count]) |offset_nm| {
            half_span_nm = @max(half_span_nm, @abs(offset_nm));
        }
    }
    return half_span_nm;
}

fn legacyChannelControls(model: *const ObservationModel, channel: SpectralChannel) Instrument.SpectralChannelControls {
    var controls: Instrument.SpectralChannelControls = .{
        .response = legacySpectralResponse(model),
        .wavelength_shift_nm = model.wavelength_shift_nm,
    };
    if (channel == .radiance) {
        controls.multiplicative_offset = model.multiplicative_offset;
        controls.stray_light = model.stray_light;
    }
    return controls;
}

fn legacySpectralResponse(model: *const ObservationModel) Instrument.SpectralResponse {
    const support = primaryOperationalBandSupportFromLegacy(model);
    const resolved_high_resolution_step_nm = if (support.high_resolution_step_nm > 0.0)
        support.high_resolution_step_nm
    else
        model.high_resolution_step_nm;
    const resolved_high_resolution_half_span_nm = if (support.high_resolution_half_span_nm > 0.0)
        support.high_resolution_half_span_nm
    else
        model.high_resolution_half_span_nm;
    return .{
        .slit_index = switch (model.builtin_line_shape) {
            .gaussian => if (support.instrument_line_shape_table.nominal_count > 0 or model.instrument_line_shape_table.nominal_count > 0) .table else .gaussian_modulated,
            .flat_top_n4 => .flat_top_n4,
            .triple_flat_top_n4 => .triple_flat_top_n4,
        },
        .fwhm_nm = model.instrument_line_fwhm_nm,
        .builtin_line_shape = model.builtin_line_shape,
        .integration_mode = if (model.integration_mode != .auto)
            model.integration_mode
        else if (model.adaptive_reference_grid.enabled())
            .adaptive
        else if (resolved_high_resolution_step_nm > 0.0 and resolved_high_resolution_half_span_nm > 0.0)
            .explicit_hr_grid
        else
            .auto,
        .high_resolution_step_nm = resolved_high_resolution_step_nm,
        .high_resolution_half_span_nm = resolved_high_resolution_half_span_nm,
        .instrument_line_shape = if (support.instrument_line_shape.sample_count > 0)
            borrowedLineShape(support.instrument_line_shape)
        else
            borrowedLineShape(model.instrument_line_shape),
        .instrument_line_shape_table = if (support.instrument_line_shape_table.nominal_count > 0)
            borrowedLineShapeTable(support.instrument_line_shape_table)
        else
            borrowedLineShapeTable(model.instrument_line_shape_table),
    };
}

fn legacyOperationalBandSupport(model: *const ObservationModel) OperationalBandSupport {
    return .{
        .id = if (model.instrument != .unset) "primary" else "",
        .high_resolution_step_nm = model.high_resolution_step_nm,
        .high_resolution_half_span_nm = model.high_resolution_half_span_nm,
        .instrument_line_shape = borrowedLineShape(model.instrument_line_shape),
        .instrument_line_shape_table = borrowedLineShapeTable(model.instrument_line_shape_table),
        .operational_refspec_grid = model.operational_refspec_grid,
        .operational_solar_spectrum = model.operational_solar_spectrum,
        .o2_operational_lut = model.o2_operational_lut,
        .o2o2_operational_lut = model.o2o2_operational_lut,
    };
}

fn mergedOperationalBandSupport(
    explicit: OperationalBandSupport,
    legacy: OperationalBandSupport,
) OperationalBandSupport {
    var merged = legacy;
    if (explicit.id.len != 0) {
        merged.id = explicit.id;
        merged.owns_id = explicit.owns_id;
    }
    if (explicit.high_resolution_step_nm > 0.0) {
        merged.high_resolution_step_nm = explicit.high_resolution_step_nm;
        merged.high_resolution_half_span_nm = explicit.high_resolution_half_span_nm;
    }
    if (explicit.instrument_line_shape.sample_count > 0) merged.instrument_line_shape = explicit.instrument_line_shape;
    if (explicit.instrument_line_shape_table.nominal_count > 0) merged.instrument_line_shape_table = explicit.instrument_line_shape_table;
    if (explicit.operational_refspec_grid.enabled()) merged.operational_refspec_grid = explicit.operational_refspec_grid;
    if (explicit.operational_solar_spectrum.enabled()) merged.operational_solar_spectrum = explicit.operational_solar_spectrum;
    if (explicit.o2_operational_lut.enabled()) merged.o2_operational_lut = explicit.o2_operational_lut;
    if (explicit.o2o2_operational_lut.enabled()) merged.o2o2_operational_lut = explicit.o2o2_operational_lut;
    return merged;
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
