const std = @import("std");
const internal = @import("internal");

const instrument_response = internal.output.instrument_response;

const allocator = std.testing.allocator;

// RowEvidence ------------------------------------------------------------------------------------------------|
// `rtm.instrument_response(o2a.reference_scene(), [758.0, 760.0, 765.0, 767.0, 776.0])`.                      |
// The O2 A public artifact records no instrument-response rows, so this canonical probe is the source oracle. |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 104 B (0.102 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] row_index: usize                                                                                 |
// [  8..103] row      : InstrumentResponseRow                                                                 |
const RowEvidence = struct {
    row_index: usize,
    row: instrument_response.InstrumentResponseRow,
};
// ------------------------------------------------------------------------------------------------------------|

const expected_rows = [_]RowEvidence{
    .{
        .row_index = 0,
        .row = .{
            .nominal_index = 100,
            .nominal_wavelength_nm = 758.0,
            .channel = 0,
            .sample_index = 0,
            .support_count = 242,
            .offset_nm = -1.1421219262290379,
            .support_wavelength_nm = 756.857878073771,
            .weight = 0.0,
            .support_width_nm = 2.288798250087325,
            .instrument_fwhm_nm = 0.38,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
            .integration_mode = 2,
            .response_enabled = 1,
        },
    },
    .{
        .row_index = 1,
        .row = .{
            .nominal_index = 100,
            .nominal_wavelength_nm = 758.0,
            .channel = 0,
            .sample_index = 1,
            .support_count = 242,
            .offset_nm = -1.1333236761416856,
            .support_wavelength_nm = 756.8666763238583,
            .weight = 0.0,
            .support_width_nm = 2.288798250087325,
            .instrument_fwhm_nm = 0.38,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
            .integration_mode = 2,
            .response_enabled = 1,
        },
    },
    .{
        .row_index = 241,
        .row = .{
            .nominal_index = 100,
            .nominal_wavelength_nm = 758.0,
            .channel = 0,
            .sample_index = 241,
            .support_count = 242,
            .offset_nm = 1.146676323858287,
            .support_wavelength_nm = 759.1466763238583,
            .weight = 0.0,
            .support_width_nm = 2.288798250087325,
            .instrument_fwhm_nm = 0.38,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
            .integration_mode = 2,
            .response_enabled = 1,
        },
    },
    .{
        .row_index = 242,
        .row = .{
            .nominal_index = 100,
            .nominal_wavelength_nm = 758.0,
            .channel = 1,
            .sample_index = 0,
            .support_count = 242,
            .offset_nm = -1.1421219262290379,
            .support_wavelength_nm = 756.857878073771,
            .weight = 0.0,
            .support_width_nm = 2.288798250087325,
            .instrument_fwhm_nm = 0.38,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
            .integration_mode = 2,
            .response_enabled = 1,
        },
    },
    .{
        .row_index = 2231,
        .row = .{
            .nominal_index = 167,
            .nominal_wavelength_nm = 760.0,
            .channel = 1,
            .sample_index = 690,
            .support_count = 1057,
            .offset_nm = 0.20390806762350167,
            .support_wavelength_nm = 760.2039080676235,
            .weight = 0.0013061505693578597,
            .support_width_nm = 2.2917266303010138,
            .instrument_fwhm_nm = 0.38,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
            .integration_mode = 2,
            .response_enabled = 1,
        },
    },
    .{
        .row_index = 2232,
        .row = .{
            .nominal_index = 167,
            .nominal_wavelength_nm = 760.0,
            .channel = 1,
            .sample_index = 691,
            .support_count = 1057,
            .offset_nm = 0.20515891946615739,
            .support_wavelength_nm = 760.2051589194662,
            .weight = 0.001276744801798927,
            .support_width_nm = 2.2917266303010138,
            .instrument_fwhm_nm = 0.38,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
            .integration_mode = 2,
            .response_enabled = 1,
        },
    },
    .{
        .row_index = 4456,
        .row = .{
            .nominal_index = 700,
            .nominal_wavelength_nm = 776.0,
            .channel = 1,
            .sample_index = 199,
            .support_count = 207,
            .offset_nm = 0.7916922621676576,
            .support_wavelength_nm = 776.7916922621677,
            .weight = 3.975190843504198e-93,
            .support_width_nm = 1.9669824805035887,
            .instrument_fwhm_nm = 0.38,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
            .integration_mode = 2,
            .response_enabled = 1,
        },
    },
    .{
        .row_index = 4463,
        .row = .{
            .nominal_index = 700,
            .nominal_wavelength_nm = 776.0,
            .channel = 1,
            .sample_index = 206,
            .support_count = 207,
            .offset_nm = 0.8246811031543757,
            .support_wavelength_nm = 776.8246811031544,
            .weight = 3.27853995787421e-110,
            .support_width_nm = 1.9669824805035887,
            .instrument_fwhm_nm = 0.38,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
            .integration_mode = 2,
            .response_enabled = 1,
        },
    },
};

test "instrument response rows match public route at probe wavelengths" {
    var prepared = try internal.public.prepare(allocator, internal.input.defaults.referenceScene());
    defer prepared.deinit(allocator);

    const wavelengths_nm = [_]f64{ 758.0, 760.0, 765.0, 767.0, 776.0 };
    var response = try internal.public.buildInstrumentResponse(
        allocator,
        &prepared,
        wavelengths_nm[0..],
        instrument_response.channel_mask_radiance | instrument_response.channel_mask_irradiance,
    );
    defer response.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 4464), response.rows.len);

    for (expected_rows) |expected| {
        try expectRowEqual(expected.row, response.rows[expected.row_index]);
    }
}

test "instrument response channel mask selects one public channel" {
    var prepared = try internal.public.prepare(allocator, internal.input.defaults.referenceScene());
    defer prepared.deinit(allocator);

    const wavelengths_nm = [_]f64{ 758.0, 760.0, 765.0, 767.0, 776.0 };
    var radiance = try internal.public.buildInstrumentResponse(
        allocator,
        &prepared,
        wavelengths_nm[0..],
        instrument_response.channel_mask_radiance,
    );
    defer radiance.deinit(allocator);
    var irradiance = try internal.public.buildInstrumentResponse(
        allocator,
        &prepared,
        wavelengths_nm[0..],
        instrument_response.channel_mask_irradiance,
    );
    defer irradiance.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2232), radiance.rows.len);
    try std.testing.expectEqual(@as(usize, 2232), irradiance.rows.len);
    try std.testing.expectEqual(@as(u32, 0), radiance.rows[0].channel);
    try std.testing.expectEqual(@as(u32, 1), irradiance.rows[0].channel);
}

test "instrument response rejects empty and unsupported channel masks" {
    var prepared = try internal.public.prepare(allocator, internal.input.defaults.referenceScene());
    defer prepared.deinit(allocator);

    const wavelengths_nm = [_]f64{758.0};
    try std.testing.expectError(
        error.InvalidControl,
        internal.public.buildInstrumentResponse(allocator, &prepared, wavelengths_nm[0..], 0),
    );
    try std.testing.expectError(
        error.InvalidControl,
        internal.public.buildInstrumentResponse(allocator, &prepared, wavelengths_nm[0..], 4),
    );
}

fn expectRowEqual(
    expected: instrument_response.InstrumentResponseRow,
    actual: instrument_response.InstrumentResponseRow,
) !void {
    // expectRowEqual -----------------------------------------------------------------------------------------|
    // Compare one public instrument-response row field-by-field so drift names the first diverging column.    |
    // --------------------------------------------------------------------------------------------------------|
    try std.testing.expectEqual(expected.nominal_index, actual.nominal_index);
    try expectF64Bits(expected.nominal_wavelength_nm, actual.nominal_wavelength_nm);
    try std.testing.expectEqual(expected.channel, actual.channel);
    try std.testing.expectEqual(expected.sample_index, actual.sample_index);
    try std.testing.expectEqual(expected.support_count, actual.support_count);
    try expectF64Bits(expected.offset_nm, actual.offset_nm);
    try expectF64Bits(expected.support_wavelength_nm, actual.support_wavelength_nm);
    try expectF64Bits(expected.weight, actual.weight);
    try expectF64Bits(expected.support_width_nm, actual.support_width_nm);
    try expectF64Bits(expected.instrument_fwhm_nm, actual.instrument_fwhm_nm);
    try expectF64Bits(expected.high_resolution_step_nm, actual.high_resolution_step_nm);
    try expectF64Bits(expected.high_resolution_half_span_nm, actual.high_resolution_half_span_nm);
    try std.testing.expectEqual(expected.integration_mode, actual.integration_mode);
    try std.testing.expectEqual(expected.response_enabled, actual.response_enabled);
}

fn expectF64Bits(expected: f64, actual: f64) !void {
    // expectF64Bits ------------------------------------------------------------------------------------------|
    // Enforce exact f64 bits for canonical probe values that are copied from kernel rows without new math.    |
    // --------------------------------------------------------------------------------------------------------|
    const expected_bits: u64 = @bitCast(expected);
    const actual_bits: u64 = @bitCast(actual);
    try std.testing.expectEqual(expected_bits, actual_bits);
}
