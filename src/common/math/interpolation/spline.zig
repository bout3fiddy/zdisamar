const std = @import("std");
const max_spline_point_count = 256;

// spline.zig -------------------------------------------------------------------------------------------------|
// Cubic-spline helpers for profile, spectroscopy, CIA, HITRAN partition, and reference-atmosphere sampling.   |
// The important route is DISAMAR-compatible endpoint-secant interpolation: callers either sample once with    |
// temporary stack storage or prepare second derivatives once and reuse them for repeated altitude/wavelength  |
// reads.                                                                                                      |
//                                                                                                             |
// called by                                                                                                   |
//   climatology.zig samples altitude, pressure, and temperature profiles while building vertical grids        |
//   state_spectroscopy.zig, layer_spectroscopy.zig, and layer_accumulation.zig prepare profile caches         |
//   cia.zig and hitran_partition_tables.zig sample bounded reference-data windows                             |
//                                                                                                             |
// main paths                                                                                                  |
//   sampleNatural                    builds a natural spline on a bounded stack workspace and samples once    |
//   sampleEndpointSecant             builds DISAMAR-compatible endpoint-secant second derivatives             |
//   endpointSecantSecondDerivatives  writes second derivatives for one series                                 |
//   endpointSecantSecondDerivatives3 writes second derivatives for three colocated series                     |
//   endpointSecantSecondDerivatives5 writes second derivatives for five colocated series                      |
//   sampleWithSecondDerivatives      samples a precomputed second-derivative spline                           |
//                                                                                                             |
// route choice                                                                                                |
//   sampleEndpointSecant is the one-shot path for small reference windows. endpointSecantSecondDerivatives*   |
//   prepares reusable curvature for profile caches. The 3-series and 5-series variants share interval and     |
//   diagonal work across colocated series so cache preparation does one tridiagonal setup per altitude grid.  |
//                                                                                                             |
// hot path                                                                                                    |
//   Sampling is repeated by profile caches after forward misses and by reference interpolation. Preparation   |
//   is capped at max_spline_point_count to keep these helpers allocation-free inside source-tree compute.     |
//                                                                                                             |
// memory                                                                                                      |
//   Preparation uses bounded stack arrays capped by max_spline_point_count. Reusable callers pass their own   |
//   second-derivative output slices and later sample those slices with sampleWithSecondDerivatives.           |
// ------------------------------------------------------------------------------------------------------------|

pub const Error = error{
    ShapeMismatch,
    NotEnoughPoints,
    OutOfDomain,
};

pub fn sampleNatural(x: []const f64, y: []const f64, target_x: f64) Error!f64 {
    if (x.len != y.len) return Error.ShapeMismatch;
    if (x.len < 3) return Error.NotEnoughPoints;
    if (target_x < x[0] or target_x > x[x.len - 1]) return Error.OutOfDomain;

    // Fixed scratch buffers keep the helper allocation-free for short spectral windows.
    var second: [max_spline_point_count]f64 = undefined;
    if (x.len > second.len) return Error.NotEnoughPoints;
    var u: [max_spline_point_count]f64 = undefined;

    second[0] = 0.0;
    u[0] = 0.0;

    var i: usize = 1;
    while (i + 1 < x.len) : (i += 1) {
        const sig = (x[i] - x[i - 1]) / (x[i + 1] - x[i - 1]);
        const p = sig * second[i - 1] + 2.0;
        second[i] = (sig - 1.0) / p;
        const ddydx = ((y[i + 1] - y[i]) / (x[i + 1] - x[i])) - ((y[i] - y[i - 1]) / (x[i] - x[i - 1]));
        u[i] = (6.0 * ddydx / (x[i + 1] - x[i - 1]) - sig * u[i - 1]) / p;
    }

    second[x.len - 1] = 0.0;
    var k: usize = x.len - 1;
    while (k > 0) : (k -= 1) {
        second[k - 1] = second[k - 1] * second[k] + u[k - 1];
    }

    var klo: usize = 0;
    var khi: usize = x.len - 1;
    while (khi - klo > 1) {
        const mid = (khi + klo) / 2;
        if (x[mid] > target_x) {
            khi = mid;
        } else {
            klo = mid;
        }
    }

    const h = x[khi] - x[klo];
    const a = (x[khi] - target_x) / h;
    const b = (target_x - x[klo]) / h;
    return a * y[klo] + b * y[khi] +
        ((a * a * a - a) * second[klo] + (b * b * b - b) * second[khi]) * (h * h) / 6.0;
}

pub fn sampleEndpointSecant(x: []const f64, y: []const f64, target_x: f64) Error!f64 {
    // sampleEndpointSecant -----------------------------------------------------------------------------------|
    // Builds DISAMAR-compatible endpoint-secant second derivatives and samples one target value.              |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : small climatology, CIA, and partition-table reference windows                              |
    //   costly   : full second-derivative preparation for one sample                                          |
    //   memory   : one stack second-derivative array capped at max_spline_point_count                         |
    //                                                                                                         |
    // calls                                                                                                   |
    //   endpointSecantSecondDerivatives                                                                       |
    //   sampleWithSecondDerivatives                                                                           |
    // --------------------------------------------------------------------------------------------------------|

    if (x.len != y.len) return Error.ShapeMismatch;
    if (x.len < 3) return Error.NotEnoughPoints;
    if (target_x < x[0] or target_x > x[x.len - 1]) return Error.OutOfDomain;

    var second: [max_spline_point_count]f64 = undefined;
    if (x.len > second.len) return Error.NotEnoughPoints;

    try endpointSecantSecondDerivatives(x, y, second[0..x.len]);
    return sampleWithSecondDerivatives(x, y, second[0..x.len], target_x);
}

pub fn endpointSecantSecondDerivatives(
    x: []const f64,
    y: []const f64,
    second: []f64,
) Error!void {
    // endpointSecantSecondDerivatives ------------------------------------------------------------------------|
    // Writes DISAMAR-compatible endpoint-secant second derivatives for one sampled series.                    |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : profile-cache preparation and one-shot endpoint-secant sampling                            |
    //   costly   : tridiagonal setup, back substitution, and conversion to splint-style second derivatives    |
    //   memory   : four stack work arrays plus caller-owned second output                                     |
    //                                                                                                         |
    // math                                                                                                    |
    //   Endpoint slopes are adjacent secants. This mirrors DISAMAR mathTools::spline wrapping de Boor         |
    //   cubspl before exposing second derivatives to splint-style sampling.                                   |
    // --------------------------------------------------------------------------------------------------------|

    if (x.len != y.len or x.len != second.len) return Error.ShapeMismatch;
    if (x.len < 3) return Error.NotEnoughPoints;
    if (x.len > max_spline_point_count) return Error.NotEnoughPoints;

    var c1: [max_spline_point_count]f64 = undefined;
    var c2: [max_spline_point_count]f64 = undefined;
    var c3: [max_spline_point_count]f64 = undefined;
    var c4: [max_spline_point_count]f64 = undefined;

    for (0..x.len) |index| {
        c1[index] = y[index];
        c2[index] = 0.0;
        c3[index] = 0.0;
        c4[index] = 0.0;
    }

    c2[0] = (y[1] - y[0]) / (x[1] - x[0]);
    c2[x.len - 1] = (y[x.len - 1] - y[x.len - 2]) / (x[x.len - 1] - x[x.len - 2]);

    for (1..x.len) |index| {
        c3[index] = x[index] - x[index - 1];
        c4[index] = (c1[index] - c1[index - 1]) / c3[index];
    }

    c4[0] = 1.0;
    c3[0] = 0.0;

    if (x.len > 2) {
        for (1..x.len - 1) |index| {
            const g = -c3[index + 1] / c4[index - 1];
            c2[index] = g * c2[index - 1] +
                3.0 * (c3[index] * c4[index + 1] + c3[index + 1] * c4[index]);
            c4[index] = g * c3[index - 1] + 2.0 * (c3[index] + c3[index + 1]);
        }
    }

    var solve_index = x.len - 1;
    while (solve_index > 0) {
        solve_index -= 1;
        c2[solve_index] = (c2[solve_index] - c3[solve_index] * c2[solve_index + 1]) / c4[solve_index];
    }

    for (1..x.len) |index| {
        const dtau = c3[index];
        const divdf1 = (c1[index] - c1[index - 1]) / dtau;
        const divdf3 = c2[index - 1] + c2[index] - 2.0 * divdf1;
        c3[index - 1] = 2.0 * (divdf1 - c2[index - 1] - divdf3) / dtau;
        c4[index - 1] = 6.0 * divdf3 / (dtau * dtau);
    }

    second[0] = -0.5 * c3[1];
    for (1..x.len - 1) |index| {
        second[index] = c3[index];
    }
    second[x.len - 1] = -0.5 * c3[x.len - 2];
}

pub fn endpointSecantSecondDerivatives3(
    x: []const f64,
    y0: []const f64,
    y1: []const f64,
    y2: []const f64,
    second0: []f64,
    second1: []f64,
    second2: []f64,
) Error!void {
    // endpointSecantSecondDerivatives3 -----------------------------------------------------------------------|
    // Computes DISAMAR-compatible endpoint-secant second derivatives for three colocated profile series.      |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : profile spectroscopy cache preparation on a forward miss                                   |
    //   costly   : one tridiagonal setup shared across three value series                                     |
    //   memory   : caller-owned outputs plus stack arrays capped at 256 points                                |
    //                                                                                                         |
    // data                                                                                                    |
    //   x is the shared altitude grid. y0, y1, and y2 are sampled at the same x points.                       |
    // --------------------------------------------------------------------------------------------------------|

    const values = [_][]const f64{ y0, y1, y2 };
    const seconds = [_][]f64{ second0, second1, second2 };

    inline for (values, seconds) |y, second| {
        if (x.len != y.len or x.len != second.len) return Error.ShapeMismatch;
    }

    if (x.len < 3) return Error.NotEnoughPoints;
    if (x.len > max_spline_point_count) return Error.NotEnoughPoints;

    var intervals: [max_spline_point_count]f64 = undefined;
    var diagonal: [max_spline_point_count]f64 = undefined;
    var slopes: [3][max_spline_point_count]f64 = undefined;
    var c2: [3][max_spline_point_count]f64 = undefined;
    var c3: [3][max_spline_point_count]f64 = undefined;

    intervals[0] = 0.0;
    diagonal[0] = 1.0;
    inline for (0..3) |series| {
        slopes[series][0] = 1.0;
        c2[series][0] = (values[series][1] - values[series][0]) / (x[1] - x[0]);
        c2[series][x.len - 1] =
            (values[series][x.len - 1] - values[series][x.len - 2]) /
            (x[x.len - 1] - x[x.len - 2]);
    }

    for (1..x.len) |index| {
        intervals[index] = x[index] - x[index - 1];
        inline for (0..3) |series| {
            slopes[series][index] =
                (values[series][index] - values[series][index - 1]) / intervals[index];
        }
    }

    for (1..x.len - 1) |index| {
        const g = -intervals[index + 1] / diagonal[index - 1];
        inline for (0..3) |series| {
            c2[series][index] = g * c2[series][index - 1] +
                3.0 * (intervals[index] * slopes[series][index + 1] +
                    intervals[index + 1] * slopes[series][index]);
        }
        diagonal[index] = g * intervals[index - 1] +
            2.0 * (intervals[index] + intervals[index + 1]);
    }

    var solve_index = x.len - 1;
    while (solve_index > 0) {
        solve_index -= 1;
        inline for (0..3) |series| {
            c2[series][solve_index] =
                (c2[series][solve_index] - intervals[solve_index] * c2[series][solve_index + 1]) /
                diagonal[solve_index];
        }
    }

    for (1..x.len) |index| {
        const dtau = intervals[index];
        inline for (0..3) |series| {
            const divdf1 = slopes[series][index];
            const divdf3 = c2[series][index - 1] + c2[series][index] - 2.0 * divdf1;
            c3[series][index - 1] = 2.0 * (divdf1 - c2[series][index - 1] - divdf3) / dtau;
        }
    }

    inline for (0..3) |series| {
        seconds[series][0] = -0.5 * c3[series][1];
        for (1..x.len - 1) |index| {
            seconds[series][index] = c3[series][index];
        }
        seconds[series][x.len - 1] = -0.5 * c3[series][x.len - 2];
    }
}

pub fn endpointSecantSecondDerivatives5(
    x: []const f64,
    y0: []const f64,
    y1: []const f64,
    y2: []const f64,
    y3: []const f64,
    y4: []const f64,
    second0: []f64,
    second1: []f64,
    second2: []f64,
    second3: []f64,
    second4: []f64,
) Error!void {
    // endpointSecantSecondDerivatives5 -----------------------------------------------------------------------|
    // Computes DISAMAR-compatible endpoint-secant second derivatives for five colocated profile series.       |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : profile spectroscopy cache preparation on a forward miss                                   |
    //   costly   : one tridiagonal setup shared across five value series                                      |
    //   memory   : caller-owned outputs plus stack arrays capped at 256 points                                |
    //                                                                                                         |
    // data                                                                                                    |
    //   x is the shared altitude grid. y0 through y4 are sampled at the same x points.                        |
    // --------------------------------------------------------------------------------------------------------|

    const values = [_][]const f64{ y0, y1, y2, y3, y4 };
    const seconds = [_][]f64{ second0, second1, second2, second3, second4 };

    inline for (values, seconds) |y, second| {
        if (x.len != y.len or x.len != second.len) return Error.ShapeMismatch;
    }

    if (x.len < 3) return Error.NotEnoughPoints;
    if (x.len > max_spline_point_count) return Error.NotEnoughPoints;

    var intervals: [max_spline_point_count]f64 = undefined;
    var diagonal: [max_spline_point_count]f64 = undefined;
    var slopes: [5][max_spline_point_count]f64 = undefined;
    var c2: [5][max_spline_point_count]f64 = undefined;
    var c3: [5][max_spline_point_count]f64 = undefined;

    intervals[0] = 0.0;
    diagonal[0] = 1.0;
    inline for (0..5) |series| {
        slopes[series][0] = 1.0;
        c2[series][0] = (values[series][1] - values[series][0]) / (x[1] - x[0]);
        c2[series][x.len - 1] =
            (values[series][x.len - 1] - values[series][x.len - 2]) /
            (x[x.len - 1] - x[x.len - 2]);
    }

    for (1..x.len) |index| {
        intervals[index] = x[index] - x[index - 1];
        inline for (0..5) |series| {
            slopes[series][index] =
                (values[series][index] - values[series][index - 1]) / intervals[index];
        }
    }

    for (1..x.len - 1) |index| {
        const g = -intervals[index + 1] / diagonal[index - 1];
        inline for (0..5) |series| {
            c2[series][index] = g * c2[series][index - 1] +
                3.0 * (intervals[index] * slopes[series][index + 1] +
                    intervals[index + 1] * slopes[series][index]);
        }
        diagonal[index] = g * intervals[index - 1] +
            2.0 * (intervals[index] + intervals[index + 1]);
    }

    var solve_index = x.len - 1;
    while (solve_index > 0) {
        solve_index -= 1;
        inline for (0..5) |series| {
            c2[series][solve_index] =
                (c2[series][solve_index] - intervals[solve_index] * c2[series][solve_index + 1]) /
                diagonal[solve_index];
        }
    }

    for (1..x.len) |index| {
        const dtau = intervals[index];
        inline for (0..5) |series| {
            const divdf1 = slopes[series][index];
            const divdf3 = c2[series][index - 1] + c2[series][index] - 2.0 * divdf1;
            c3[series][index - 1] = 2.0 * (divdf1 - c2[series][index - 1] - divdf3) / dtau;
        }
    }

    inline for (0..5) |series| {
        seconds[series][0] = -0.5 * c3[series][1];
        for (1..x.len - 1) |index| {
            seconds[series][index] = c3[series][index];
        }
        seconds[series][x.len - 1] = -0.5 * c3[series][x.len - 2];
    }
}

pub fn sampleWithSecondDerivatives(
    x: []const f64,
    y: []const f64,
    second: []const f64,
    target_x: f64,
) Error!f64 {
    // sampleWithSecondDerivatives ----------------------------------------------------------------------------|
    // Samples one cubic spline value from caller-prepared second derivatives.                                 |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : support-row spectroscopy samples cached profile series at altitude                         |
    //   costly   : bracket search and cubic blend                                                             |
    //   memory   : borrowed x, y, and second-derivative slices                                                |
    //                                                                                                         |
    // math                                                                                                    |
    //   The returned value is the linear blend plus cubic curvature correction over the bracketing interval.  |
    // --------------------------------------------------------------------------------------------------------|

    if (x.len != y.len or x.len != second.len) return Error.ShapeMismatch;
    if (x.len < 3) return Error.NotEnoughPoints;
    if (target_x < x[0] or target_x > x[x.len - 1]) return Error.OutOfDomain;

    var klo: usize = 0;
    var khi: usize = x.len - 1;
    while (khi - klo > 1) {
        const mid = (khi + klo) / 2;
        if (x[mid] > target_x) {
            khi = mid;
        } else {
            klo = mid;
        }
    }

    const h = x[khi] - x[klo];
    const a = (x[khi] - target_x) / h;
    const b = (target_x - x[klo]) / h;
    return a * y[klo] + b * y[khi] +
        ((a * a * a - a) * second[klo] + (b * b * b - b) * second[khi]) * (h * h) / 6.0;
}
