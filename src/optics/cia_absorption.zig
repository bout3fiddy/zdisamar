const readers = @import("../assets/readers.zig");
const spline = @import("../common/math/spline.zig");
const cia_table = @import("../setup/cia_table.zig");

const max_spline_window_points: usize = 256;

// cia_absorption.zig ---------------------------------------------------------------------------------------- |
// O2-O2 collision-induced absorption coefficient sampling for support-row optics.                             |
//                                                                                                             |
// provenance                                                                                                  |
//   Ported from main:`src/input/reference/cia.zig`. WP2 keeps the parsed BIRA rows in O2CiaTable; WP3 uses    |
//   the same endpoint-secant coefficient interpolation and temperature polynomial in the optics hot path.     |
//                                                                                                             |
// math                                                                                                        |
//   T_C       = temperature_k - 273.15                                                                        |
//   raw_sigma = a0 + a1*T_C + a2*T_C^2                                                                        |
//   sigma     = scale_factor_cm5_per_molecule2 * max(raw_sigma, 0)                                            |
// ------------------------------------------------------------------------------------------------------------|

// CiaCoefficients ------------------------------------------------------------------------------------------- |
// Interpolated CIA coefficient row at one wavelength.                                                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_nm : f64                                                                                |
// [ 8..15] a0            : f64                                                                                |
// [16..23] a1            : f64                                                                                |
// [24..31] a2            : f64                                                                                |
pub const CiaCoefficients = struct {
    wavelength_nm: f64,
    a0: f64,
    a1: f64,
    a2: f64,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn sigmaAt(table: cia_table.O2CiaTable, wavelength_nm: f64, temperature_k: f64) f64 {
    // sigmaAt ----------------------------------------------------------------------------------------------- |
    // Evaluate CIA sigma for one wavelength and support-row temperature.                                      |
    // --------------------------------------------------------------------------------------------------------|
    const coefficients = interpolateCoefficients(table.rows, wavelength_nm);
    const temperature_c = temperature_k - 273.15;
    const raw_sigma = coefficients.a0 +
        coefficients.a1 * temperature_c +
        coefficients.a2 * temperature_c * temperature_c;
    return table.scale_factor_cm5_per_molecule2 * @max(raw_sigma, 0.0);
}

pub fn interpolateCoefficients(rows: []const readers.CiaAssetRow, wavelength_nm: f64) CiaCoefficients {
    // interpolateCoefficients --------------------------------------------------------------------------------|
    // Bracket the CIA table and interpolate the a0/a1/a2 coefficient triplet.                                 |
    // --------------------------------------------------------------------------------------------------------|
    if (rows.len == 0) return .{ .wavelength_nm = wavelength_nm, .a0 = 0.0, .a1 = 0.0, .a2 = 0.0 };
    if (wavelength_nm <= rows[0].wavelength_nm) return rowToCoefficients(rows[0], wavelength_nm);
    if (wavelength_nm >= rows[rows.len - 1].wavelength_nm) {
        return rowToCoefficients(rows[rows.len - 1], wavelength_nm);
    }

    const right_index = lowerBoundRowIndex(rows, wavelength_nm);
    const window = splineWindow(rows.len, right_index);
    if (window.count >= 3) {
        const points = rows[window.start .. window.start + window.count];
        return .{
            .wavelength_nm = wavelength_nm,
            .a0 = sampleCoefficientSpline(points, wavelength_nm, .a0),
            .a1 = sampleCoefficientSpline(points, wavelength_nm, .a1),
            .a2 = sampleCoefficientSpline(points, wavelength_nm, .a2),
        };
    }
    return interpolateCoefficientsLinear(rows[right_index - 1], rows[right_index], wavelength_nm);
}

const CoefficientKind = enum { a0, a1, a2 };

// SplineWindow ---------------------------------------------------------------------------------------------- |
// Bounded coefficient-window descriptor for stack spline sampling.                                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] start : usize                                                                                       |
// [8..15] count : usize                                                                                       |
const SplineWindow = struct {
    start: usize,
    count: usize,
};
// ------------------------------------------------------------------------------------------------------------|

fn splineWindow(point_count: usize, right_index: usize) SplineWindow {
    const count = @min(point_count, max_spline_window_points);
    if (point_count <= max_spline_window_points) return .{ .start = 0, .count = count };

    const half_window = max_spline_window_points / 2;
    var start: usize = if (right_index > half_window) right_index - half_window else 0;
    if (start + count > point_count) start = point_count - count;
    return .{ .start = start, .count = count };
}

fn sampleCoefficientSpline(
    points: []const readers.CiaAssetRow,
    wavelength_nm: f64,
    coefficient_kind: CoefficientKind,
) f64 {
    var x: [max_spline_window_points]f64 = undefined;
    var y: [max_spline_window_points]f64 = undefined;
    for (points, 0..) |point, index| {
        x[index] = point.wavelength_nm;
        y[index] = switch (coefficient_kind) {
            .a0 => point.a0,
            .a1 => point.a1,
            .a2 => point.a2,
        };
    }
    return spline.sampleEndpointSecant(x[0..points.len], y[0..points.len], wavelength_nm) catch
        interpolateCoefficientByKind(points[0], points[points.len - 1], wavelength_nm, coefficient_kind);
}

fn lowerBoundRowIndex(rows: []const readers.CiaAssetRow, wavelength_nm: f64) usize {
    var low: usize = 0;
    var high = rows.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (rows[middle].wavelength_nm < wavelength_nm) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    return low;
}

fn interpolateCoefficientsLinear(
    left: readers.CiaAssetRow,
    right: readers.CiaAssetRow,
    wavelength_nm: f64,
) CiaCoefficients {
    const span = right.wavelength_nm - left.wavelength_nm;
    if (span <= 0.0) return rowToCoefficients(left, wavelength_nm);
    const fraction = (wavelength_nm - left.wavelength_nm) / span;
    return .{
        .wavelength_nm = wavelength_nm,
        .a0 = left.a0 + fraction * (right.a0 - left.a0),
        .a1 = left.a1 + fraction * (right.a1 - left.a1),
        .a2 = left.a2 + fraction * (right.a2 - left.a2),
    };
}

fn interpolateCoefficientByKind(
    left: readers.CiaAssetRow,
    right: readers.CiaAssetRow,
    wavelength_nm: f64,
    coefficient_kind: CoefficientKind,
) f64 {
    return switch (coefficient_kind) {
        .a0 => interpolateCoefficientsLinear(left, right, wavelength_nm).a0,
        .a1 => interpolateCoefficientsLinear(left, right, wavelength_nm).a1,
        .a2 => interpolateCoefficientsLinear(left, right, wavelength_nm).a2,
    };
}

fn rowToCoefficients(row: readers.CiaAssetRow, wavelength_nm: f64) CiaCoefficients {
    return .{
        .wavelength_nm = wavelength_nm,
        .a0 = row.a0,
        .a1 = row.a1,
        .a2 = row.a2,
    };
}
