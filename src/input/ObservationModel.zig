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
const SpectralChannel = @import("Instrument.zig").SpectralChannel;
const Allocator = std.mem.Allocator;

// ObservationModel.zig --------------------------------------------------------------------------------------|
// Instrument, sampling, calibration, and operational support controls nested inside Scene.                   |
//                                                                                                            |
// called by                                                                                                  |
//   Scene.validate before a request reaches optical-property or instrument-grid setup                        |
//   instrument integration and calibration code through resolvedChannelControls                              |
//   LUT selection and bundled workflows through primaryOperationalBandSupport and lutSamplingHalfSpanNm      |
//                                                                                                            |
// main paths                                                                                                 |
//   validate                                                                                                 |
//     -> check bindings, instrument identity, measured wavelength ordering, integration-mode prerequisites,  |
//        adaptive grid controls, and the current single operational-band support boundary                    |
//                                                                                                            |
//   resolvedChannelControls                                                                                  |
//     -> build SpectralResponse from builtin line shape, explicit line-shape rows, adaptive grid, and HR grid|
//     -> add radiance-only gain and stray-light controls; irradiance keeps neutral post-calibration          |
//                                                                                                            |
//   deinitOwned                                                                                              |
//     -> release only support and measured-wavelength storage this model owns                                |
//                                                                                                            |
// control resolution                                                                                         |
//   integration_mode = auto chooses adaptive first, then explicit high-resolution grid, then default kernel. |
//   Requested modes are validated up front so later code does not silently ignore missing grid or FWHM data. |
//                                                                                                            |
// ownership                                                                                                  |
//   operational_band_support and measured_wavelengths_nm may be borrowed or owned by loaders.                |
//   resolved SpectralResponse rows borrow explicit line-shape storage so downstream code cannot free it.     |
// -----------------------------------------------------------------------------------------------------------|

pub const ObservationRegime = enum {
    nadir,
};

// ResolvedHighResolutionGrid --------------------------------------------------------------------------------|
// Effective high-resolution grid controls after scene-level defaults and operational support are resolved.   |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 16 B (0.016 KiB), align: 8 B                                                                         |
//                                                                                                            |
// memory                                                                                                     |
// [ 0.. 7] step_nm      : f64                                                                                |
// [ 8..15] half_span_nm : f64                                                                                |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// footprint: per instance = 16 B (0.016 KiB); stack value while resolving SpectralResponse                   |
const ResolvedHighResolutionGrid = struct {
    step_nm: f64,
    half_span_nm: f64,

    fn enabled(self: ResolvedHighResolutionGrid) bool {
        return self.step_nm > 0.0 and self.half_span_nm > 0.0;
    }
};
// -----------------------------------------------------------------------------------------------------------|

// ObservationModel ------------------------------------------------------------------------------------------|
// Public instrument and measurement-control row nested in Scene.                                             |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 216 B (0.211 KiB), align: 8 B                                                                        |
//                                                                                                            |
// memory                                                                                                     |
// [  0.. 23] instrument                     : InstrumentId                                                   |
// [ 24.. 31] wavelength_shift_nm            : f64                                                            |
// [ 32.. 39] multiplicative_offset          : f64                                                            |
// [ 40.. 47] stray_light                    : f64                                                            |
// [ 48.. 55] instrument_line_fwhm_nm        : f64                                                            |
// [ 56..111] solar_spectrum_source          : Binding                                                        |
// [112..167] weighted_reference_grid_source : Binding                                                        |
// [168..183] operational_band_support       : []const OperationalBandSupport                                 |
// [184..199] measured_wavelengths_nm        : []const f64                                                    |
// [200..205] adaptive_reference_grid        : AdaptiveReferenceGrid                                          |
// [206..206] sampling                       : SamplingMode                                                   |
// [207..207] builtin_line_shape             : BuiltinLineShapeKind                                           |
// [208..208] integration_mode               : RequestedIntegrationMode                                       |
// [209..209] owns_operational_band_support  : bool                                                           |
// [210..210] owns_measured_wavelengths      : bool                                                           |
// [211..215] trailing padding               : 5 B                                                            |
//                                                                                                            |
// zero-size fields                                                                                           |
//   regime has one value today, so it has no stored bytes.                                                   |
//                                                                                                            |
// referenced storage                                                                                         |
//   operational_band_support and measured_wavelengths_nm are borrowed unless the owns_* flags are set.       |
//                                                                                                            |
// unused bits: 40 padding + 14 bool-storage slack = 54 bits                                                  |
// cache span: 4 cache lines at 64 B per line                                                                 |
// footprint: per instance = 216 B (0.211 KiB); total also includes referenced support/wavelength storage     |
pub const ObservationModel = struct {
    instrument: InstrumentId = .generic,
    regime: ObservationRegime = .nadir,
    sampling: Instrument.SamplingMode = .native,
    wavelength_shift_nm: f64 = 0.0,
    multiplicative_offset: f64 = 1.0,
    stray_light: f64 = 0.0,
    instrument_line_fwhm_nm: f64 = 0.0,
    builtin_line_shape: BuiltinLineShapeKind = .gaussian,
    integration_mode: Instrument.SpectralResponse.RequestedIntegrationMode = .auto,
    adaptive_reference_grid: AdaptiveReferenceGrid = .{},
    solar_spectrum_source: Binding = .none,
    weighted_reference_grid_source: Binding = .none,
    operational_band_support: []const OperationalBandSupport = &.{},
    owns_operational_band_support: bool = false,
    measured_wavelengths_nm: []const f64 = &.{},
    owns_measured_wavelengths: bool = false,

    pub fn validate(self: *const ObservationModel) errors.Error!void {
        // ObservationModel.validate -------------------------------------------------------------------------|
        // Reject instrument controls that later product paths would otherwise have to guess about.           |
        //                                                                                                    |
        // checks                                                                                             |
        //   bindings and instrument identity                                                                 |
        //   radiance calibration scalars                                                                     |
        //   measured wavelengths are finite and strictly increasing                                          |
        //   requested integration modes have the FWHM/grid/adaptive controls they require                    |
        //   one operational-band support row only, until the runtime is truly band-indexed                   |
        //                                                                                                    |
        // contract                                                                                           |
        //   Missing requested physics fails here. integration.zig can then choose routes without silently    |
        //   falling back from an explicitly requested high-resolution or adaptive mode.                      |
        // ---------------------------------------------------------------------------------------------------|

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

        const high_resolution_grid = resolvedHighResolutionGrid(self);
        const has_explicit_hr_grid =
            high_resolution_grid.step_nm > 0.0 and high_resolution_grid.half_span_nm > 0.0;
        const has_instrument_width = self.instrument_line_fwhm_nm > 0.0;

        switch (self.integration_mode) {
            .auto, .default_kernel => {},

            .explicit_hr_grid => {
                if (!has_explicit_hr_grid) {
                    return errors.Error.InvalidRequest;
                }
            },

            .disamar_hr_grid => {
                if (!has_instrument_width) return errors.Error.InvalidRequest;
            },

            .adaptive => {
                const has_adaptive_grid = self.adaptive_reference_grid.enabled();
                if (!has_instrument_width or !has_adaptive_grid) {
                    return errors.Error.InvalidRequest;
                }
            },
        }
        try self.adaptive_reference_grid.validate();

        if (self.operational_band_support.len > 1) {

            // Runtime consumers still resolve one operational support record per scene.
            // Reject multi-band support until optics and measurement prep are band-indexed
            // and can consume every enabled replacement.
            return errors.Error.InvalidRequest;
        }

        for (self.operational_band_support, 0..) |*support, index| {
            try support.validate();
            for (self.operational_band_support[index + 1 ..]) |other| {
                if (std.mem.eql(u8, support.id, other.id)) return errors.Error.InvalidRequest;
            }
        }
    }

    pub fn resolvedChannelControls(
        self: *const ObservationModel,
        channel: SpectralChannel,
    ) Instrument.SpectralChannelControls {
        // ObservationModel.resolvedChannelControls ----------------------------------------------------------|
        // Return the per-channel controls consumed by instrument integration and calibration.                |
        //                                                                                                    |
        // route                                                                                              |
        //   both channels share the resolved SpectralResponse                                                |
        //   radiance keeps gain/stray-light post-calibration                                                 |
        //   irradiance keeps neutral post-calibration                                                        |
        // ---------------------------------------------------------------------------------------------------|

        return channelControls(self, channel);
    }

    pub fn operationalBandCount(self: *const ObservationModel) usize {
        return self.operational_band_support.len;
    }

    pub fn primaryOperationalBandSupport(self: *const ObservationModel) OperationalBandSupport {
        return self.resolvedOperationalBandSupport(0) orelse .{};
    }

    pub fn lutSamplingHalfSpanNm(self: *const ObservationModel) f64 {
        return lutSamplingHalfSpanForSupport(self.primaryOperationalBandSupport());
    }

    pub fn resolvedOperationalBandSupport(
        self: *const ObservationModel,
        band_index: usize,
    ) ?OperationalBandSupport {
        if (band_index < self.operational_band_support.len) return self.operational_band_support[band_index];
        return null;
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
        if (self.owns_operational_band_support) {
            for (self.operational_band_support) |support| {
                var owned = support;
                owned.deinitOwned(allocator);
            }
            if (self.operational_band_support.len != 0) allocator.free(self.operational_band_support);
        }
        self.operational_band_support = &.{};
        self.owns_operational_band_support = false;
        if (self.owns_measured_wavelengths and self.measured_wavelengths_nm.len != 0) {
            allocator.free(self.measured_wavelengths_nm);
        }
        self.measured_wavelengths_nm = &.{};
        self.owns_measured_wavelengths = false;
    }
};

fn lutSamplingHalfSpanForSupport(support: OperationalBandSupport) f64 {
    if (support.high_resolution_step_nm <= 0.0) return 0.0;

    var half_span_nm = support.high_resolution_half_span_nm;
    if (support.instrument_line_shape.sample_count > 0) {
        const line_shape = support.instrument_line_shape;
        for (line_shape.offsets_nm[0..line_shape.sample_count]) |offset_nm| {
            half_span_nm = @max(half_span_nm, @abs(offset_nm));
        }
    }
    if (support.instrument_line_shape_table.sample_count > 0) {
        const line_shape_table = support.instrument_line_shape_table;
        for (line_shape_table.offsets_nm[0..line_shape_table.sample_count]) |offset_nm| {
            half_span_nm = @max(half_span_nm, @abs(offset_nm));
        }
    }
    return half_span_nm;
}

fn channelControls(model: *const ObservationModel, channel: SpectralChannel) Instrument.SpectralChannelControls {
    var controls: Instrument.SpectralChannelControls = .{
        .response = spectralResponse(model),
        .wavelength_shift_nm = model.wavelength_shift_nm,
    };
    if (channel == .radiance) {
        controls.multiplicative_offset = model.multiplicative_offset;
        controls.stray_light = model.stray_light;
    }
    return controls;
}

fn spectralResponse(model: *const ObservationModel) Instrument.SpectralResponse {
    // spectralResponse --------------------------------------------------------------------------------------|
    // Resolve the instrument-response row used by integration.zig and diagnostic output.                     |
    //                                                                                                        |
    // route                                                                                                  |
    //   1. choose primary operational support                                                                |
    //   2. borrow explicit line-shape kernel/table storage when present                                      |
    //   3. choose the built-in slit index                                                                    |
    //   4. resolve integration mode from requested mode, adaptive grid, and explicit HR grid                 |
    //                                                                                                        |
    // ownership                                                                                              |
    //   Returned line-shape rows borrow storage from ObservationModel. They must not free those slices.      |
    // -------------------------------------------------------------------------------------------------------|

    const support = model.primaryOperationalBandSupport();
    const high_resolution_grid = resolvedHighResolutionGrid(model);
    const has_line_shape_table = support.instrument_line_shape_table.nominal_count > 0;

    var line_shape: InstrumentLineShape = .{};
    if (support.instrument_line_shape.sample_count > 0) {
        line_shape = borrowedLineShape(support.instrument_line_shape);
    }

    var line_shape_table: InstrumentLineShapeTable = .{};
    if (has_line_shape_table) {
        line_shape_table = borrowedLineShapeTable(support.instrument_line_shape_table);
    }

    const slit_index: Instrument.SlitIndex = switch (model.builtin_line_shape) {
        .gaussian => if (has_line_shape_table) .table else .gaussian_modulated,
        .flat_top_n4 => .flat_top_n4,
        .triple_flat_top_n4 => .triple_flat_top_n4,
    };

    return .{
        .slit_index = slit_index,
        .fwhm_nm = model.instrument_line_fwhm_nm,
        .builtin_line_shape = model.builtin_line_shape,
        .integration_mode = resolvedIntegrationMode(model, high_resolution_grid),
        .high_resolution_step_nm = high_resolution_grid.step_nm,
        .high_resolution_half_span_nm = high_resolution_grid.half_span_nm,
        .instrument_line_shape = line_shape,
        .instrument_line_shape_table = line_shape_table,
    };
}

fn resolvedIntegrationMode(
    model: *const ObservationModel,
    high_resolution_grid: ResolvedHighResolutionGrid,
) Instrument.SpectralResponse.IntegrationMode {
    // resolvedIntegrationMode -------------------------------------------------------------------------------|
    // Turn the requested integration mode into the concrete response route.                                  |
    //                                                                                                        |
    // order                                                                                                  |
    //   explicit requested mode wins after validate has checked prerequisites                                |
    //   auto chooses adaptive first, then explicit high-resolution grid, then the default kernel             |
    // -------------------------------------------------------------------------------------------------------|

    switch (model.integration_mode) {
        .auto => {},
        .default_kernel => return .default_kernel,
        .explicit_hr_grid => return .explicit_hr_grid,
        .disamar_hr_grid => return .disamar_hr_grid,
        .adaptive => return .adaptive,
    }

    if (model.adaptive_reference_grid.enabled()) return .adaptive;
    if (high_resolution_grid.enabled()) return .explicit_hr_grid;
    return .default_kernel;
}

fn resolvedHighResolutionGrid(model: *const ObservationModel) ResolvedHighResolutionGrid {
    // resolvedHighResolutionGrid ----------------------------------------------------------------------------|
    // Copy high-resolution grid controls from the primary operational-band support row.                      |
    //                                                                                                        |
    // why                                                                                                    |
    //   The active product path still resolves one support row per scene. Keeping this as a tiny value       |
    //   makes the single-band boundary explicit at the response-resolution point.                            |
    // -------------------------------------------------------------------------------------------------------|

    const support = model.primaryOperationalBandSupport();
    return .{
        .step_nm = support.high_resolution_step_nm,
        .half_span_nm = support.high_resolution_half_span_nm,
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
