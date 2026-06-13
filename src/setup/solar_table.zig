const std = @import("std");

const readers = @import("../assets/readers.zig");
const errors = @import("../common/errors.zig");
const o2_case = @import("../input/o2_case.zig");

const Allocator = std.mem.Allocator;

// SolarTable -------------------------------------------------------------------------------------------------|
// Owner for parsed solar irradiance rows plus DISAMAR spline state.                                           |
//                                                                                                             |
//   route prepared second derivatives once on the operational solar table, then reused them on irradiance     |
//   cache misses.                                                                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] rows                     : []SolarAssetRow                                                         |
// [16..31] spline_second_derivatives: []f64                                                                   |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows owns parsed solar irradiance rows. spline_second_derivatives owns one f64 per row when the table has |
//   enough samples for the endpoint-secant spline route.                                                      |
pub const SolarTable = struct {
    rows: []readers.SolarAssetRow,
    spline_second_derivatives: []f64 = &.{},

    pub fn deinit(self: *SolarTable, allocator: Allocator) void {
        // SolarTable.deinit ----------------------------------------------------------------------------------|
        // Release parsed solar rows and prepared interpolation state owned by this setup table.               |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.spline_second_derivatives);
        allocator.free(self.rows);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn hashAll(hasher: *std.hash.Wyhash, table: SolarTable) void {
    // hashAll ----------------------------------------------------------------------------------------------- |
    // Hash operational solar rows and prepared endpoint-secant spline state used by irradiance lookup.        |
    // --------------------------------------------------------------------------------------------------------|
    hasher.update(std.mem.sliceAsBytes(table.rows));
    hasher.update(std.mem.sliceAsBytes(table.spline_second_derivatives));
}
// ------------------------------------------------------------------------------------------------------------|

pub fn build(allocator: Allocator, case: o2_case.O2Case) !SolarTable {
    // build --------------------------------------------------------------------------------------------------|
    // Load solar reference rows and prepare the operational-table spline state once during setup.             |
    // --------------------------------------------------------------------------------------------------------|
    const rows = try readers.readSolarReference(allocator, case.observation.solar_reference.path);
    errdefer allocator.free(rows);

    const second_derivatives = try buildSplineSecondDerivatives(allocator, rows);
    errdefer allocator.free(second_derivatives);

    return .{
        .rows = rows,
        .spline_second_derivatives = second_derivatives,
    };
}

fn buildSplineSecondDerivatives(
    allocator: Allocator,
    rows: []const readers.SolarAssetRow,
) ![]f64 {
    // buildSplineSecondDerivatives ---------------------------------------------------------------------------|
    // Prepare DISAMAR endpoint-secant spline second derivatives for the operational solar table.              |
    //                                                                                                         |
    // math                                                                                                    |
    //   This uses `OperationalSolarSpectrum.prepareInterpolation`: endpoint slopes are adjacent               |
    //   secants, a tridiagonal solve recovers first derivatives, then the values are converted to the         |
    //   `splint` second-derivative form consumed by `spectrum/solar_lookup.zig`.                              |
    //                                                                                                         |
    // allocation                                                                                              |
    //   Setup owns the three work arrays. Per-wavelength irradiance lookup reads only the retained output.    |
    // --------------------------------------------------------------------------------------------------------|
    try validateRows(rows);
    if (rows.len < 3) return &.{};

    const second_derivatives = try allocator.alloc(f64, rows.len);
    errdefer allocator.free(second_derivatives);

    const slopes = try allocator.alloc(f64, rows.len);
    defer allocator.free(slopes);
    const intervals = try allocator.alloc(f64, rows.len);
    defer allocator.free(intervals);
    const divided = try allocator.alloc(f64, rows.len);
    defer allocator.free(divided);

    @memset(slopes, 0.0);
    @memset(intervals, 0.0);
    @memset(divided, 0.0);

    const first_span_nm = rows[1].wavelength_nm - rows[0].wavelength_nm;
    const last_span_nm = rows[rows.len - 1].wavelength_nm - rows[rows.len - 2].wavelength_nm;
    if (first_span_nm <= 0.0 or last_span_nm <= 0.0) return errors.Error.InvalidAssetFormat;

    slopes[0] = (rows[1].irradiance - rows[0].irradiance) / first_span_nm;
    slopes[rows.len - 1] =
        (rows[rows.len - 1].irradiance - rows[rows.len - 2].irradiance) / last_span_nm;

    var index: usize = 1;
    while (index < rows.len) : (index += 1) {
        intervals[index] = rows[index].wavelength_nm - rows[index - 1].wavelength_nm;
        if (intervals[index] <= 0.0) return errors.Error.InvalidAssetFormat;
        divided[index] = (rows[index].irradiance - rows[index - 1].irradiance) / intervals[index];
    }

    divided[0] = 1.0;
    intervals[0] = 0.0;

    index = 1;
    while (index + 1 < rows.len) : (index += 1) {
        const elimination_ratio = -intervals[index + 1] / divided[index - 1];
        slopes[index] = elimination_ratio * slopes[index - 1] +
            3.0 * (intervals[index] * divided[index + 1] + intervals[index + 1] * divided[index]);
        divided[index] = elimination_ratio * intervals[index - 1] +
            2.0 * (intervals[index] + intervals[index + 1]);
    }

    index = rows.len - 1;
    while (index > 0) : (index -= 1) {
        slopes[index - 1] =
            (slopes[index - 1] - intervals[index - 1] * slopes[index]) / divided[index - 1];
    }

    index = 1;
    while (index < rows.len) : (index += 1) {
        const span_nm = intervals[index];
        const first_divided_difference = (rows[index].irradiance - rows[index - 1].irradiance) / span_nm;
        const third_divided_difference =
            slopes[index - 1] + slopes[index] - (2.0 * first_divided_difference);
        intervals[index - 1] =
            2.0 * (first_divided_difference - slopes[index - 1] - third_divided_difference) / span_nm;
        divided[index - 1] = 6.0 * third_divided_difference / (span_nm * span_nm);
    }

    second_derivatives[0] = -0.5 * intervals[1];
    for (1..rows.len - 1) |interior_index| {
        second_derivatives[interior_index] = intervals[interior_index];
    }
    second_derivatives[rows.len - 1] = -0.5 * intervals[rows.len - 2];

    return second_derivatives;
}

fn validateRows(rows: []const readers.SolarAssetRow) errors.Error!void {
    // validateRows -------------------------------------------------------------------------------------------|
    // Check the operational solar table assumptions before retaining spline state.                            |
    // --------------------------------------------------------------------------------------------------------|
    if (rows.len == 0) return errors.Error.EmptyAsset;

    var previous_wavelength: ?f64 = null;
    for (rows) |row| {
        if (!std.math.isFinite(row.wavelength_nm) or
            !std.math.isFinite(row.irradiance) or
            row.irradiance < 0.0)
        {
            return errors.Error.InvalidAssetFormat;
        }

        if (previous_wavelength) |previous| {
            if (row.wavelength_nm <= previous) return errors.Error.InvalidAssetFormat;
        }
        previous_wavelength = row.wavelength_nm;
    }
}
