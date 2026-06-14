const std = @import("std");

const internal = @import("internal");

const radiance_wavelengths = internal.spectrum.radiance_wavelengths;
const sampling_table = internal.spectrum.sampling_table;

test "RadianceWavelengthList deduplicates only exact f64 bit keys" {
    const side_offsets = [_]f64{ 0.0, 0.01, 0.0 };
    const side_weights = [_]f64{ 0.25, 0.5, 0.25 };
    const rows = [_]sampling_table.SpectrumSamplingRow{
        .{
            .nominal_wavelength_nm = 0.0,
            .radiance_wavelength_nm = 0.0,
            .irradiance_wavelength_nm = 0.0,
            .radiance_integration = .disabled(),
            .irradiance_integration = .disabled(),
        },
        .{
            .nominal_wavelength_nm = -0.0,
            .radiance_wavelength_nm = -0.0,
            .irradiance_wavelength_nm = -0.0,
            .radiance_integration = .disabled(),
            .irradiance_integration = .disabled(),
        },
        .{
            .nominal_wavelength_nm = 760.0,
            .radiance_wavelength_nm = 760.0,
            .irradiance_wavelength_nm = 760.0,
            .radiance_integration = .{
                .side_start = 0,
                .sample_count = 3,
                .encoding = .side_samples,
            },
            .irradiance_integration = .disabled(),
        },
    };
    const table = sampling_table.SpectrumSamplingTable{
        .rows = rows[0..],
        .kernel_storage = .{
            .offsets_nm = side_offsets[0..],
            .weights = side_weights[0..],
        },
    };

    var list = try radiance_wavelengths.buildRadianceWavelengthList(std.testing.allocator, table);
    defer list.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), list.rows.len);
    try std.testing.expectEqual(@as(usize, 5), list.sample_indices.len);
    try std.testing.expectEqual(@as(usize, 4), list.wavelengths.len);
    try std.testing.expectEqual(@as(u32, 0), list.rows[0].start);
    try std.testing.expectEqual(@as(u32, 1), list.rows[1].start);
    try std.testing.expectEqual(@as(u32, 2), list.rows[2].start);

    try std.testing.expectEqual(radiance_wavelengths.keyFor(0.0), list.wavelengths[0].key);
    try std.testing.expectEqual(radiance_wavelengths.keyFor(-0.0), list.wavelengths[1].key);
    try std.testing.expect(list.wavelengths[0].key != list.wavelengths[1].key);

    try std.testing.expectEqual(@as(u32, 2), list.sample_indices[2]);
    try std.testing.expectEqual(@as(u32, 3), list.sample_indices[3]);
    try std.testing.expectEqual(@as(u32, 2), list.sample_indices[4]);
}

test "RadianceWavelengthList evidence anchors keep O2 A exact-key route shape" {

    // Source: canonical O2 A radiance-wavelength evidence fixtures.
    // Canonical expected values owned by this repository.

    try std.testing.expectEqual(@as(usize, 3874), radiance_wavelength_evidence.count);
    try std.testing.expectEqual(@as(u64, 4649845583965292708), radiance_wavelength_evidence.first_key);
    try std.testing.expectApproxEqAbs(754.240334835155, radiance_wavelength_evidence.first_wavelength_nm, 0.0);
    try std.testing.expectEqual(@as(u64, 4650044237975911787), radiance_wavelength_evidence.last_key);
    try std.testing.expectApproxEqAbs(776.8246811031544, radiance_wavelength_evidence.last_wavelength_nm, 0.0);
    try std.testing.expectEqual(
        radiance_wavelength_evidence.first_key,
        radiance_wavelengths.keyFor(radiance_wavelength_evidence.first_wavelength_nm),
    );
    try std.testing.expectEqual(
        radiance_wavelength_evidence.last_key,
        radiance_wavelengths.keyFor(radiance_wavelength_evidence.last_wavelength_nm),
    );
}

// RadianceWavelengthEvidence -------------------------------------------------------------------------------- |
// Exact-key canonical radiance wavelength evidence from the O2 A internal dump.                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] count              : usize                                                                         |
// [ 8..15] first_key          : u64                                                                           |
// [16..23] first_wavelength_nm: f64                                                                           |
// [24..31] last_key           : u64                                                                           |
// [32..39] last_wavelength_nm : f64                                                                           |
const RadianceWavelengthEvidence = struct {
    count: usize,
    first_key: u64,
    first_wavelength_nm: f64,
    last_key: u64,
    last_wavelength_nm: f64,
};
// ------------------------------------------------------------------------------------------------------------|

const radiance_wavelength_evidence = RadianceWavelengthEvidence{
    .count = 3874,
    .first_key = 4649845583965292708,
    .first_wavelength_nm = 754.240334835155,
    .last_key = 4650044237975911787,
    .last_wavelength_nm = 776.8246811031544,
};
