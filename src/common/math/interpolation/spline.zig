const std = @import("std");
const max_spline_point_count = 256;

pub const Error = error{
    ShapeMismatch,
    NotEnoughPoints,
    OutOfDomain,
};

pub fn sampleNatural(x: []const f64, y: []const f64, target_x: f64) Error!f64 {
    if (x.len != y.len) return Error.ShapeMismatch;
    if (x.len < 3) return Error.NotEnoughPoints;
    if (target_x < x[0] or target_x > x[x.len - 1]) return Error.OutOfDomain;

    // DECISION:
    //   Fixed scratch buffers keep the helper allocation-free for short spectral windows.
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
    if (x.len != y.len) return Error.ShapeMismatch;
    if (x.len < 3) return Error.NotEnoughPoints;
    if (target_x < x[0] or target_x > x[x.len - 1]) return Error.OutOfDomain;

    var second: [max_spline_point_count]f64 = undefined;
    var c1: [max_spline_point_count]f64 = undefined;
    var c2: [max_spline_point_count]f64 = undefined;
    var c3: [max_spline_point_count]f64 = undefined;
    var c4: [max_spline_point_count]f64 = undefined;
    if (x.len > second.len) return Error.NotEnoughPoints;

    // PARITY:
    //   DISAMAR `mathTools::spline` wraps de Boor `cubspl` with endpoint
    //   slopes set to the adjacent secants, then exposes a derived
    //   second-derivative array to `splint`. This intentionally mirrors that
    //   wrapper instead of a textbook clamped-spline tridiagonal system.
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
