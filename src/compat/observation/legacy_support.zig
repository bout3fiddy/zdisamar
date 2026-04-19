//! Purpose:
//!   Own the retained observation-model compatibility rules that merge legacy
//!   singleton controls into the explicit per-channel and per-band model.
//!
//! Physics:
//!   Resolves spectral response, operational band support, and noise controls
//!   for scenes that still provide older observation-model fields.
//!
//! Vendor:
//!   `observation-model legacy compatibility`
//!
//! Design:
//!   Keep the fallback policy out of `ObservationModel.zig` so the canonical
//!   model type remains focused on typed data ownership and validation.
//!
//! Invariants:
//!   Borrowed line-shape carriers must not claim ownership, and merged
//!   operational support must preserve explicit overrides over legacy defaults.
//!
//! Validation:
//!   Observation-model tests in `ObservationModel.zig` cover the compatibility
//!   merge behavior through the public model methods.

const Instrument = @import("../../model/Instrument.zig").Instrument;
const InstrumentLineShape = @import("../../model/Instrument.zig").InstrumentLineShape;
const InstrumentLineShapeTable = @import("../../model/Instrument.zig").InstrumentLineShapeTable;
const OperationalBandSupport = @import("../../model/Instrument.zig").Instrument.OperationalBandSupport;
const SpectralChannel = @import("../../model/Instrument.zig").SpectralChannel;

pub fn resolvedChannelControls(model: anytype, channel: SpectralChannel) Instrument.SpectralChannelControls {
    return switch (channel) {
        .radiance => if (model.measurement_pipeline.radiance.explicit)
            model.measurement_pipeline.radiance
        else
            legacyChannelControls(model, .radiance),
        .irradiance => if (model.measurement_pipeline.irradiance.explicit)
            model.measurement_pipeline.irradiance
        else
            legacyChannelControls(model, .irradiance),
    };
}

pub fn operationalBandCount(model: anytype) usize {
    if (model.operational_band_support.len != 0) return model.operational_band_support.len;
    return if (legacyOperationalBandSupport(model).enabled()) 1 else 0;
}

pub fn primaryOperationalBandSupport(model: anytype) OperationalBandSupport {
    return resolvedOperationalBandSupport(model, 0) orelse .{};
}

pub fn resolvedOperationalBandSupport(
    model: anytype,
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

pub fn lutSamplingHalfSpanNm(support: OperationalBandSupport) f64 {
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

fn legacyChannelControls(model: anytype, channel: SpectralChannel) Instrument.SpectralChannelControls {
    var controls: Instrument.SpectralChannelControls = .{
        .response = legacySpectralResponse(model),
        .wavelength_shift_nm = model.wavelength_shift_nm,
        .noise = .{
            .enabled = legacyNoiseEnabled(model.noise_model, channel),
            .model = legacyNoiseModel(model.noise_model, channel),
            .reference_signal = if (channel == .radiance) model.reference_radiance else &.{},
            .reference_sigma = if (channel == .radiance) model.ingested_noise_sigma else &.{},
        },
    };
    if (channel == .radiance) {
        controls.multiplicative_offset = model.multiplicative_offset;
        controls.stray_light = model.stray_light;
        controls.use_polarization_scrambler = true;
    }
    return controls;
}

fn legacySpectralResponse(model: anytype) Instrument.SpectralResponse {
    const support = primaryOperationalBandSupport(model);
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
        .integration_mode = if (model.adaptive_reference_grid.enabled())
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

fn legacyOperationalBandSupport(model: anytype) OperationalBandSupport {
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
