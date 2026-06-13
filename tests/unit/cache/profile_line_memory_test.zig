const std = @import("std");
const builtin = @import("builtin");
const internal = @import("internal");

const profile_line_test_sample_count = 7;

fn profileLineRow(
    values: internal.cache.profile_line_memory.ProfileLineValues,
    wavelength_index: usize,
    profile_node_index: usize,
) ?internal.cache.profile_line_memory.ProfileLineValue {
    // profileLineRow -----------------------------------------------------------------------------------------|
    // Return one test evidence row from the public owned row slice.                                           |
    // --------------------------------------------------------------------------------------------------------|
    if (wavelength_index >= values.wavelength_count or profile_node_index >= values.profile_node_count) return null;
    return values.values[wavelength_index * values.profile_node_count + profile_node_index];
}

fn supportProfileLineRow(
    values: internal.cache.profile_line_memory.ProfileLineValues,
    wavelength_index: usize,
    profile_node_index: usize,
) ?internal.cache.profile_line_memory.ProfileSupportLineValue {
    // supportProfileLineRow ----------------------------------------------------------------------------------|
    // Return one test evidence row from the public support-profile row slice.                                 |
    // --------------------------------------------------------------------------------------------------------|
    if (wavelength_index >= values.wavelength_count or
        profile_node_index >= values.support_profile_node_count)
    {
        return null;
    }
    return values.support_profile_values[
        wavelength_index * values.support_profile_node_count + profile_node_index
    ];
}

test "ProfileLineValues keep wavelength-major line values for each layer node" {
    var case = internal.input.defaults.referenceCase();
    case.spectral_grid.sample_count = profile_line_test_sample_count;

    var values = try internal.cache.profile_line_memory.buildO2ProfileLineValues(
        std.testing.allocator,
        case,
    );
    defer values.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, profile_line_test_sample_count), values.wavelength_count);
    try std.testing.expectEqual(@as(usize, 45), values.profile_node_count);
    try std.testing.expectEqual(@as(usize, 47), values.support_profile_node_count);
    try std.testing.expectEqual(values.wavelength_count * values.profile_node_count, values.values.len);
    try std.testing.expectEqual(
        values.wavelength_count * values.support_profile_node_count,
        values.support_profile_values.len,
    );
    try std.testing.expect(values.reuse_stamp.value != 0);

    const first = profileLineRow(values, 0, 0) orelse return error.MissingProfileLineValue;
    const last = profileLineRow(values, values.wavelength_count - 1, values.profile_node_count - 1) orelse
        return error.MissingProfileLineValue;
    const support_first = supportProfileLineRow(values, 0, 0) orelse return error.MissingProfileLineValue;
    try std.testing.expectApproxEqAbs(755.0, first.wavelength_nm, 0.0);
    try std.testing.expectApproxEqAbs(776.0, last.wavelength_nm, 0.0);
    try std.testing.expectApproxEqAbs(755.0, support_first.wavelength_nm, 0.0);
    try std.testing.expectEqual(@as(u32, 0), first.layer_index);
    try std.testing.expectEqual(@as(u32, 44), last.layer_index);
    try std.testing.expectEqual(@as(u32, 0), support_first.profile_node_index);
}

test "ProfileLineValues support-profile layouts stay compiler backed" {
    try std.testing.expectEqual(@as(usize, 80), @sizeOf(internal.cache.profile_line_memory.ProfileLineValue));
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(internal.cache.profile_line_memory.ProfileSupportLineValue));
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(internal.cache.profile_line_memory.ProfileLineValues));
    try std.testing.expectEqual(
        @as(usize, 16),
        @offsetOf(internal.cache.profile_line_memory.ProfileLineValues, "support_profile_values"),
    );
}

test "ProfileLineValues contain computed finite weak-line sigma rows" {
    var case = internal.input.defaults.referenceCase();
    case.spectral_grid.sample_count = profile_line_test_sample_count;

    var values = try internal.cache.profile_line_memory.buildO2ProfileLineValues(
        std.testing.allocator,
        case,
    );
    defer values.deinit(std.testing.allocator);

    var nonzero_count: usize = 0;
    var max_sigma: f64 = 0.0;
    for (values.values) |value| {
        try std.testing.expect(std.math.isFinite(value.weak_line_sigma_cm2_per_molecule));
        try std.testing.expect(value.weak_line_sigma_cm2_per_molecule >= 0.0);
        try std.testing.expect(std.math.isFinite(value.d_sigma_d_temperature_cm2_per_molecule_per_k));
        if (value.weak_line_sigma_cm2_per_molecule > 0.0) nonzero_count += 1;
        max_sigma = @max(max_sigma, value.weak_line_sigma_cm2_per_molecule);
    }

    try std.testing.expect(nonzero_count > values.profile_node_count);
    try std.testing.expect(max_sigma > 1.0e-28);
}

test "ProfileLineValues build the full reference wavelength route in optimized mode" {
    if (builtin.mode == .Debug) return error.SkipZigTest;

    var values = try internal.cache.profile_line_memory.buildO2ProfileLineValues(
        std.testing.allocator,
        internal.input.defaults.referenceCase(),
    );
    defer values.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 701), values.wavelength_count);
    try std.testing.expectEqual(@as(usize, 45), values.profile_node_count);
    try std.testing.expectEqual(@as(usize, 47), values.support_profile_node_count);
    try std.testing.expectEqual(values.wavelength_count * values.profile_node_count, values.values.len);
    try std.testing.expectEqual(
        values.wavelength_count * values.support_profile_node_count,
        values.support_profile_values.len,
    );
}

test "ProfileLineValues match profile-node line math evidence" {
    if (builtin.mode == .Debug) return error.SkipZigTest;

    var probe_index: usize = 0;
    while (probe_index < profile_line_probe_evidence.len) {
        const wavelength_nm = profile_line_probe_evidence[probe_index].wavelength_nm;
        var case = internal.input.defaults.referenceCase();
        case.spectral_grid = .{
            .start_nm = wavelength_nm,
            .end_nm = wavelength_nm,
            .sample_count = 1,
        };

        var values = try internal.cache.profile_line_memory.buildO2ProfileLineValues(
            std.testing.allocator,
            case,
        );
        defer values.deinit(std.testing.allocator);

        try std.testing.expectEqual(@as(usize, 1), values.wavelength_count);
        while (probe_index < profile_line_probe_evidence.len and
            profile_line_probe_evidence[probe_index].wavelength_nm == wavelength_nm)
        {
            const expected = profile_line_probe_evidence[probe_index];
            const actual = profileLineRow(values, 0, expected.profile_node_index) orelse
                return error.MissingProfileLineValue;
            try std.testing.expectApproxEqAbs(expected.wavelength_nm, actual.wavelength_nm, 0.0);
            try std.testing.expectApproxEqAbs(expected.pressure_hpa, actual.pressure_hpa, 1.0e-10);
            try std.testing.expectApproxEqAbs(expected.temperature_k, actual.temperature_k, 1.0e-10);
            try std.testing.expectApproxEqRel(
                expected.weak_line_sigma_cm2_per_molecule,
                actual.weak_line_sigma_cm2_per_molecule,
                1.0e-12,
            );
            try std.testing.expectApproxEqRel(
                expected.d_sigma_d_temperature_cm2_per_molecule_per_k,
                actual.d_sigma_d_temperature_cm2_per_molecule_per_k,
                1.0e-12,
            );
            probe_index += 1;
        }
    }
}

test "ProfileLineValues match profile-node total line sidecar evidence" {
    if (builtin.mode == .Debug) return error.SkipZigTest;

    var probe_index: usize = 0;
    while (probe_index < profile_line_total_probe_evidence.len) {
        const wavelength_nm = profile_line_total_probe_evidence[probe_index].wavelength_nm;
        var case = internal.input.defaults.referenceCase();
        case.spectral_grid = .{
            .start_nm = wavelength_nm,
            .end_nm = wavelength_nm,
            .sample_count = 1,
        };

        var values = try internal.cache.profile_line_memory.buildO2ProfileLineValues(
            std.testing.allocator,
            case,
        );
        defer values.deinit(std.testing.allocator);

        while (probe_index < profile_line_total_probe_evidence.len and
            profile_line_total_probe_evidence[probe_index].wavelength_nm == wavelength_nm)
        {
            const expected = profile_line_total_probe_evidence[probe_index];
            const actual = profileLineRow(values, 0, expected.profile_node_index) orelse
                return error.MissingProfileLineValue;
            try std.testing.expectApproxEqRel(
                expected.strong_line_sigma_cm2_per_molecule,
                actual.strong_line_sigma_cm2_per_molecule,
                1.0e-12,
            );
            try std.testing.expectApproxEqRel(
                expected.line_mixing_sigma_cm2_per_molecule,
                actual.line_mixing_sigma_cm2_per_molecule,
                1.0e-12,
            );
            try std.testing.expectApproxEqRel(
                expected.total_sigma_cm2_per_molecule,
                actual.total_sigma_cm2_per_molecule,
                1.0e-12,
            );
            probe_index += 1;
        }
    }
}

test "ProfileLineValues preserve caller-provided exact wavelength order" {
    if (builtin.mode == .Debug) return error.SkipZigTest;

    const wavelengths_nm = [_]f64{ 760.0, 758.0, 776.0 };
    var values = try internal.cache.profile_line_memory.buildO2ProfileLineValuesForWavelengths(
        std.testing.allocator,
        internal.input.defaults.referenceCase(),
        wavelengths_nm[0..],
    );
    defer values.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, wavelengths_nm.len), values.wavelength_count);
    try std.testing.expectEqual(@as(usize, 45), values.profile_node_count);
    try std.testing.expectEqual(@as(usize, 47), values.support_profile_node_count);

    const row_760 = profileLineRow(values, 0, 0) orelse return error.MissingProfileLineValue;
    const row_758 = profileLineRow(values, 1, 0) orelse return error.MissingProfileLineValue;
    const row_776 = profileLineRow(values, 2, 44) orelse return error.MissingProfileLineValue;
    try std.testing.expectApproxEqAbs(760.0, row_760.wavelength_nm, 0.0);
    try std.testing.expectApproxEqAbs(758.0, row_758.wavelength_nm, 0.0);
    try std.testing.expectApproxEqAbs(776.0, row_776.wavelength_nm, 0.0);

    const expected_760 = findProfileLineProbeEvidence(760.0, 0) orelse return error.MissingProfileLineValue;
    try std.testing.expectApproxEqAbs(expected_760.wavelength_nm, row_760.wavelength_nm, 0.0);
    try std.testing.expectApproxEqRel(
        expected_760.weak_line_sigma_cm2_per_molecule,
        row_760.weak_line_sigma_cm2_per_molecule,
        1.0e-12,
    );

    var tables = try internal.setup.o2_run_tables.buildO2RunTables(
        std.testing.allocator,
        internal.input.defaults.referenceCase(),
    );
    defer tables.deinit(std.testing.allocator);
    const support_sigma = try std.testing.allocator.alloc(f64, tables.layers.support_mid_altitudes_km.len);
    defer std.testing.allocator.free(support_sigma);

    try values.fillSupportLineSigmaAtWavelengthIndex(tables.layers, 1, support_sigma, null);
    const expected_support = support_line_sigma_evidence[0];
    const support_index: usize = @intCast(expected_support.support_index);
    const expected_sigma =
        expected_support.gas_absorption_optical_depth /
        (expected_support.oxygen_number_density_cm3 * expected_support.path_length_cm);
    try std.testing.expectApproxEqRel(expected_sigma, support_sigma[support_index], 1.0e-12);
}

test "ProfileLineValues parallel wavelength build matches serial rows" {
    if (builtin.mode == .Debug) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const wavelengths_nm = [_]f64{ 758.0, 760.0, 765.0, 767.0, 776.0 };

    var serial = try internal.cache.profile_line_memory.buildO2ProfileLineValuesForWavelengthsWithCutoffGrid(
        allocator,
        internal.input.defaults.referenceCase(),
        wavelengths_nm[0..],
        wavelengths_nm[0..],
        true,
        true,
        null,
        1,
        &.{},
    );
    defer serial.deinit(allocator);

    var parallel = try internal.cache.profile_line_memory.buildO2ProfileLineValuesForWavelengthsWithCutoffGrid(
        allocator,
        internal.input.defaults.referenceCase(),
        wavelengths_nm[0..],
        wavelengths_nm[0..],
        true,
        true,
        null,
        2,
        &.{},
    );
    defer parallel.deinit(allocator);

    try std.testing.expectEqual(serial.wavelength_count, parallel.wavelength_count);
    try std.testing.expectEqual(serial.profile_node_count, parallel.profile_node_count);
    try std.testing.expectEqual(serial.support_profile_node_count, parallel.support_profile_node_count);
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(serial.values), std.mem.sliceAsBytes(parallel.values));
    try std.testing.expectEqualSlices(
        u8,
        std.mem.sliceAsBytes(serial.support_profile_values),
        std.mem.sliceAsBytes(parallel.support_profile_values),
    );
}

test "ProfileLineValues fill support-row sigma from atmospheric-budget evidence" {
    if (builtin.mode == .Debug) return error.SkipZigTest;

    var tables = try internal.setup.o2_run_tables.buildO2RunTables(
        std.testing.allocator,
        internal.input.defaults.referenceCase(),
    );
    defer tables.deinit(std.testing.allocator);

    const support_sigma = try std.testing.allocator.alloc(f64, tables.layers.support_mid_altitudes_km.len);
    defer std.testing.allocator.free(support_sigma);

    for (support_line_sigma_evidence) |expected| {
        var case = internal.input.defaults.referenceCase();
        case.spectral_grid = .{
            .start_nm = expected.wavelength_nm,
            .end_nm = expected.wavelength_nm,
            .sample_count = 1,
        };
        var values = try internal.cache.profile_line_memory.buildO2ProfileLineValues(
            std.testing.allocator,
            case,
        );
        defer values.deinit(std.testing.allocator);

        try values.fillSupportLineSigmaAtWavelengthIndex(tables.layers, 0, support_sigma, null);

        const support_index: usize = @intCast(expected.support_index);
        const expected_sigma =
            expected.gas_absorption_optical_depth /
            (expected.oxygen_number_density_cm3 * expected.path_length_cm);
        try std.testing.expectApproxEqRel(expected_sigma, support_sigma[support_index], 1.0e-12);
    }
}

// ProfileLineProbeEvidence -----------------------------------------------------------------------------------|
// One canonical weak-line value anchor for a diagnostic wavelength and layer node.                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_nm                                   : f64                                              |
// [ 8..15] profile_node_index                              : usize                                            |
// [16..23] pressure_hpa                                    : f64                                              |
// [24..31] temperature_k                                   : f64                                              |
// [32..39] weak_line_sigma_cm2_per_molecule                : f64                                              |
// [40..47] d_sigma_d_temperature_cm2_per_molecule_per_k    : f64                                              |
const ProfileLineProbeEvidence = struct {
    wavelength_nm: f64,
    profile_node_index: usize,
    pressure_hpa: f64,
    temperature_k: f64,
    weak_line_sigma_cm2_per_molecule: f64,
    d_sigma_d_temperature_cm2_per_molecule_per_k: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// SupportLineSigmaEvidence -----------------------------------------------------------------------------------|
// One canonical support-row gas-absorption anchor uses derive expected sigma_total.                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_nm                 : f64                                                                |
// [ 8..15] path_length_cm                : f64                                                                |
// [16..23] oxygen_number_density_cm3     : f64                                                                |
// [24..31] gas_absorption_optical_depth  : f64                                                                |
// [32..35] support_index                 : u32                                                                |
// [36..39] trailing padding              : 4 B                                                                |
const SupportLineSigmaEvidence = struct {
    wavelength_nm: f64,
    support_index: u32,
    path_length_cm: f64,
    oxygen_number_density_cm3: f64,
    gas_absorption_optical_depth: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// Canonical expected values owned by this repository.
// public-python-baseline.json .diagnostics.atmospheric_budget.rows, support row 1 at the five O2 A probes.
const support_line_sigma_evidence = [_]SupportLineSigmaEvidence{
    .{
        .wavelength_nm = 758.0,
        .support_index = 1,
        .path_length_cm = 1889.5354494827166,
        .oxygen_number_density_cm3 = 5.220552365887917e18,
        .gas_absorption_optical_depth = 0.000014827869850978738,
    },
    .{
        .wavelength_nm = 760.0,
        .support_index = 1,
        .path_length_cm = 1889.5354494827166,
        .oxygen_number_density_cm3 = 5.220552365887917e18,
        .gas_absorption_optical_depth = 0.003851103825908674,
    },
    .{
        .wavelength_nm = 765.0,
        .support_index = 1,
        .path_length_cm = 1889.5354494827166,
        .oxygen_number_density_cm3 = 5.220552365887917e18,
        .gas_absorption_optical_depth = 0.0006483670238492417,
    },
    .{
        .wavelength_nm = 767.0,
        .support_index = 1,
        .path_length_cm = 1889.5354494827166,
        .oxygen_number_density_cm3 = 5.220552365887917e18,
        .gas_absorption_optical_depth = 0.00007927523435585222,
    },
    .{
        .wavelength_nm = 776.0,
        .support_index = 1,
        .path_length_cm = 1889.5354494827166,
        .oxygen_number_density_cm3 = 5.220552365887917e18,
        .gas_absorption_optical_depth = 5.35307046857685e-7,
    },
};

// ProfileLineTotalProbeEvidence ------------------------------------------------------------------------------|
// One canonical total line-sidecar value anchor for a diagnostic wavelength and layer node.                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_nm                        : f64                                                         |
// [ 8..15] profile_node_index                   : usize                                                       |
// [16..23] strong_line_sigma_cm2_per_molecule   : f64                                                         |
// [24..31] line_mixing_sigma_cm2_per_molecule   : f64                                                         |
// [32..39] total_sigma_cm2_per_molecule         : f64                                                         |
const ProfileLineTotalProbeEvidence = struct {
    wavelength_nm: f64,
    profile_node_index: usize,
    strong_line_sigma_cm2_per_molecule: f64,
    line_mixing_sigma_cm2_per_molecule: f64,
    total_sigma_cm2_per_molecule: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// Source: canonical O2 A profile-line evidence fixtures.
// The O2 A artifacts do not expose per-profile-node total line sidecar rows, so this table is derived by running
// nodes at the five diagnostic wavelengths used by public-python-baseline.json.
const profile_line_total_probe_evidence = [_]ProfileLineTotalProbeEvidence{
    .{
        .wavelength_nm = 758.0,
        .profile_node_index = 0,
        .strong_line_sigma_cm2_per_molecule = 1.08375416811245930e-27,
        .line_mixing_sigma_cm2_per_molecule = -6.36581934975572000e-28,
        .total_sigma_cm2_per_molecule = 1.50447588856829870e-27,
    },
    .{
        .wavelength_nm = 758.0,
        .profile_node_index = 16,
        .strong_line_sigma_cm2_per_molecule = 5.68094292336209900e-28,
        .line_mixing_sigma_cm2_per_molecule = -3.42362256072298930e-28,
        .total_sigma_cm2_per_molecule = 7.79182051245344000e-28,
    },
    .{
        .wavelength_nm = 758.0,
        .profile_node_index = 44,
        .strong_line_sigma_cm2_per_molecule = 3.47182869052960440e-31,
        .line_mixing_sigma_cm2_per_molecule = -2.09770626609104530e-31,
        .total_sigma_cm2_per_molecule = 4.75612080957699400e-31,
    },
    .{
        .wavelength_nm = 760.0,
        .profile_node_index = 0,
        .strong_line_sigma_cm2_per_molecule = 1.88996664645741630e-25,
        .line_mixing_sigma_cm2_per_molecule = 5.36769482601947000e-27,
        .total_sigma_cm2_per_molecule = 3.90752649812722270e-25,
    },
    .{
        .wavelength_nm = 760.0,
        .profile_node_index = 16,
        .strong_line_sigma_cm2_per_molecule = 8.66770413123742800e-26,
        .line_mixing_sigma_cm2_per_molecule = 1.97333189521312800e-27,
        .total_sigma_cm2_per_molecule = 1.79074991420843870e-25,
    },
    .{
        .wavelength_nm = 760.0,
        .profile_node_index = 44,
        .strong_line_sigma_cm2_per_molecule = 5.20713357554555600e-29,
        .line_mixing_sigma_cm2_per_molecule = 1.13834333633611140e-30,
        .total_sigma_cm2_per_molecule = 1.07667255483614820e-28,
    },
    .{
        .wavelength_nm = 765.0,
        .profile_node_index = 0,
        .strong_line_sigma_cm2_per_molecule = 3.27944235549163400e-26,
        .line_mixing_sigma_cm2_per_molecule = 7.27610753617510900e-28,
        .total_sigma_cm2_per_molecule = 6.57853381468159100e-26,
    },
    .{
        .wavelength_nm = 765.0,
        .profile_node_index = 16,
        .strong_line_sigma_cm2_per_molecule = 1.63289111232408520e-26,
        .line_mixing_sigma_cm2_per_molecule = 2.82103546711251350e-28,
        .total_sigma_cm2_per_molecule = 3.26893945979713840e-26,
    },
    .{
        .wavelength_nm = 765.0,
        .profile_node_index = 44,
        .strong_line_sigma_cm2_per_molecule = 9.92867376068587300e-30,
        .line_mixing_sigma_cm2_per_molecule = 1.65708220076861960e-31,
        .total_sigma_cm2_per_molecule = 1.98766385535399770e-29,
    },
    .{
        .wavelength_nm = 767.0,
        .profile_node_index = 0,
        .strong_line_sigma_cm2_per_molecule = 4.31165328433395900e-27,
        .line_mixing_sigma_cm2_per_molecule = -6.33640793800627300e-28,
        .total_sigma_cm2_per_molecule = 8.04385949169926200e-27,
    },
    .{
        .wavelength_nm = 767.0,
        .profile_node_index = 16,
        .strong_line_sigma_cm2_per_molecule = 1.82960685012479400e-27,
        .line_mixing_sigma_cm2_per_molecule = -3.50377046617917600e-28,
        .total_sigma_cm2_per_molecule = 3.32518563919886650e-27,
    },
    .{
        .wavelength_nm = 767.0,
        .profile_node_index = 44,
        .strong_line_sigma_cm2_per_molecule = 1.09285971325984700e-30,
        .line_mixing_sigma_cm2_per_molecule = -2.14667815227410840e-31,
        .total_sigma_cm2_per_molecule = 1.98012419276012700e-30,
    },
    .{
        .wavelength_nm = 776.0,
        .profile_node_index = 0,
        .strong_line_sigma_cm2_per_molecule = 7.08414487184700100e-29,
        .line_mixing_sigma_cm2_per_molecule = -4.17126954818559600e-29,
        .total_sigma_cm2_per_molecule = 5.43147625680958100e-29,
    },
    .{
        .wavelength_nm = 776.0,
        .profile_node_index = 16,
        .strong_line_sigma_cm2_per_molecule = 3.76899249170105570e-29,
        .line_mixing_sigma_cm2_per_molecule = -2.28866030107605070e-29,
        .total_sigma_cm2_per_molecule = 2.60578800898636100e-29,
    },
    .{
        .wavelength_nm = 776.0,
        .profile_node_index = 44,
        .strong_line_sigma_cm2_per_molecule = 2.30656087811877360e-32,
        .line_mixing_sigma_cm2_per_molecule = -1.40488148961054600e-32,
        .total_sigma_cm2_per_molecule = 1.58002063730110300e-32,
    },
};

fn findProfileLineProbeEvidence(
    wavelength_nm: f64,
    profile_node_index: u32,
) ?ProfileLineProbeEvidence {
    // findProfileLineProbeEvidence -------------------------------------------------------------------------- |
    // Resolve one test evidence row by physical key instead of by table position.                             |
    // --------------------------------------------------------------------------------------------------------|
    for (profile_line_probe_evidence) |row| {
        if (row.wavelength_nm == wavelength_nm and row.profile_node_index == profile_node_index) return row;
    }
    return null;
}

// Source: canonical O2 A profile-line evidence fixtures.
// The O2 A public artifacts contain diagnostic optical depths, not per-layer line-cache rows, so this table is
// wavelengths used by public-python-baseline.json.
const profile_line_probe_evidence = [_]ProfileLineProbeEvidence{
    .{
        .wavelength_nm = 758.0,
        .profile_node_index = 0,
        .pressure_hpa = 1013.249997412,
        .temperature_k = 294.202056207578,
        .weak_line_sigma_cm2_per_molecule = 1.05726969292054615e-27,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = -1.83595503527988427e-30,
    },
    .{
        .wavelength_nm = 758.0,
        .profile_node_index = 7,
        .pressure_hpa = 558.458199121273,
        .temperature_k = 267.57720774615,
        .weak_line_sigma_cm2_per_molecule = 6.11944055373625292e-28,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = -1.18536201795389974e-30,
    },
    .{
        .wavelength_nm = 758.0,
        .profile_node_index = 16,
        .pressure_hpa = 500.000004070198,
        .temperature_k = 262.439089747901,
        .weak_line_sigma_cm2_per_molecule = 5.53440020740344944e-28,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = -1.09677396542423947e-30,
    },
    .{
        .wavelength_nm = 758.0,
        .profile_node_index = 29,
        .pressure_hpa = 17.351474312025,
        .temperature_k = 229.646997591592,
        .weak_line_sigma_cm2_per_molecule = 2.06091670097212271e-29,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = -4.80320128223989631e-32,
    },
    .{
        .wavelength_nm = 758.0,
        .profile_node_index = 44,
        .pressure_hpa = 0.303708050815,
        .temperature_k = 259.502897487829,
        .weak_line_sigma_cm2_per_molecule = 3.38194079559902818e-31,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = -6.79114241671697228e-34,
    },
    .{
        .wavelength_nm = 760.0,
        .profile_node_index = 0,
        .pressure_hpa = 1013.249997412,
        .temperature_k = 294.202056207578,
        .weak_line_sigma_cm2_per_molecule = 1.96387183565113823e-25,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 3.41659597628889760e-28,
    },
    .{
        .wavelength_nm = 760.0,
        .profile_node_index = 7,
        .pressure_hpa = 558.458199121273,
        .temperature_k = 267.57720774615,
        .weak_line_sigma_cm2_per_molecule = 1.02384922563819883e-25,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 2.64247929549664367e-28,
    },
    .{
        .wavelength_nm = 760.0,
        .profile_node_index = 16,
        .pressure_hpa = 500.000004070198,
        .temperature_k = 262.439089747901,
        .weak_line_sigma_cm2_per_molecule = 9.04243012588960301e-26,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 2.51176133229739802e-28,
    },
    .{
        .wavelength_nm = 760.0,
        .profile_node_index = 29,
        .pressure_hpa = 17.351474312025,
        .temperature_k = 229.646997591592,
        .weak_line_sigma_cm2_per_molecule = 2.79583210321738751e-27,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 1.22244579875582963e-29,
    },
    .{
        .wavelength_nm = 760.0,
        .profile_node_index = 44,
        .pressure_hpa = 0.303708050815,
        .temperature_k = 259.502897487829,
        .weak_line_sigma_cm2_per_molecule = 5.44573943793696381e-29,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 1.57019570621925716e-31,
    },
    .{
        .wavelength_nm = 765.0,
        .profile_node_index = 0,
        .pressure_hpa = 1013.249997412,
        .temperature_k = 294.202056207578,
        .weak_line_sigma_cm2_per_molecule = 3.22632892489860087e-26,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = -1.64717214020881762e-29,
    },
    .{
        .wavelength_nm = 765.0,
        .profile_node_index = 7,
        .pressure_hpa = 558.458199121273,
        .temperature_k = 267.57720774615,
        .weak_line_sigma_cm2_per_molecule = 1.79551941170372428e-26,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = -7.39700758793966184e-31,
    },
    .{
        .wavelength_nm = 765.0,
        .profile_node_index = 16,
        .pressure_hpa = 500.000004070198,
        .temperature_k = 262.439089747901,
        .weak_line_sigma_cm2_per_molecule = 1.60783757155988610e-26,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 1.14047281928550909e-30,
    },
    .{
        .wavelength_nm = 765.0,
        .profile_node_index = 29,
        .pressure_hpa = 17.351474312025,
        .temperature_k = 229.646997591592,
        .weak_line_sigma_cm2_per_molecule = 5.49809079452546309e-28,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 5.56850013368800901e-31,
    },
    .{
        .wavelength_nm = 765.0,
        .profile_node_index = 44,
        .pressure_hpa = 0.303708050815,
        .temperature_k = 259.502897487829,
        .weak_line_sigma_cm2_per_molecule = 9.78225414489972006e-30,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 1.37423779824044953e-33,
    },
    .{
        .wavelength_nm = 767.0,
        .profile_node_index = 0,
        .pressure_hpa = 1013.249997412,
        .temperature_k = 294.202056207578,
        .weak_line_sigma_cm2_per_molecule = 4.36567880988005421e-27,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 1.84445006847780998e-29,
    },
    .{
        .wavelength_nm = 767.0,
        .profile_node_index = 7,
        .pressure_hpa = 558.458199121273,
        .temperature_k = 267.57720774615,
        .weak_line_sigma_cm2_per_molecule = 2.11957461524255781e-27,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 1.11345392485255979e-29,
    },
    .{
        .wavelength_nm = 767.0,
        .profile_node_index = 16,
        .pressure_hpa = 500.000004070198,
        .temperature_k = 262.439089747901,
        .weak_line_sigma_cm2_per_molecule = 1.84589899908685568e-27,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 1.00971749402109018e-29,
    },
    .{
        .wavelength_nm = 767.0,
        .profile_node_index = 29,
        .pressure_hpa = 17.351474312025,
        .temperature_k = 229.646997591592,
        .weak_line_sigma_cm2_per_molecule = 5.22269420322659805e-29,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 3.61870776201212978e-31,
    },
    .{
        .wavelength_nm = 767.0,
        .profile_node_index = 44,
        .pressure_hpa = 0.303708050815,
        .temperature_k = 259.502897487829,
        .weak_line_sigma_cm2_per_molecule = 1.10189905694067465e-30,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 6.16462519843508840e-33,
    },
    .{
        .wavelength_nm = 776.0,
        .profile_node_index = 0,
        .pressure_hpa = 1013.249997412,
        .temperature_k = 294.202056207578,
        .weak_line_sigma_cm2_per_molecule = 2.51588836605153841e-29,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 9.27419151490685533e-32,
    },
    .{
        .wavelength_nm = 776.0,
        .profile_node_index = 7,
        .pressure_hpa = 558.458199121273,
        .temperature_k = 267.57720774615,
        .weak_line_sigma_cm2_per_molecule = 1.27406181163098260e-29,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 3.49547764082895642e-32,
    },
    .{
        .wavelength_nm = 776.0,
        .profile_node_index = 16,
        .pressure_hpa = 500.000004070198,
        .temperature_k = 262.439089747901,
        .weak_line_sigma_cm2_per_molecule = 1.12507393405501891e-29,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 2.95042246033502089e-32,
    },
    .{
        .wavelength_nm = 776.0,
        .profile_node_index = 29,
        .pressure_hpa = 17.351474312025,
        .temperature_k = 229.646997591592,
        .weak_line_sigma_cm2_per_molecule = 3.60584079613569218e-31,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 8.57551093752559266e-34,
    },
    .{
        .wavelength_nm = 776.0,
        .profile_node_index = 44,
        .pressure_hpa = 0.303708050815,
        .temperature_k = 259.502897487829,
        .weak_line_sigma_cm2_per_molecule = 6.78137085917089848e-33,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 1.73662029992673027e-35,
    },
};
