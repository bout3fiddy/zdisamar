const linear = @import("linear.zig");
const spline = @import("spline.zig");
const layout = @import("model_layout");

pub const Method = enum {
    linear,
    spline,
};

pub fn resampleUniform(
    axis: layout.Axes.SpectralAxis,
    values: []const f64,
    targets_nm: []const f64,
    method: Method,
    output: []f64,
) !void {
    if (targets_nm.len != output.len) return error.ShapeMismatch;

    switch (method) {
        .linear => {
            for (targets_nm, output) |target, *slot| {
                slot.* = try linear.sampleUniform(axis, values, target);
            }
        },
        .spline => {
            var x: [256]f64 = undefined;
            if (values.len > x.len) return error.ShapeMismatch;
            var i: usize = 0;
            while (i < values.len) : (i += 1) {
                x[i] = try axis.valueAt(@intCast(i));
            }
            for (targets_nm, output) |target, *slot| {
                slot.* = try spline.sampleNatural(x[0..values.len], values, target);
            }
        },
    }
}

test "uniform resampling supports linear and spline methods" {
    const axis = layout.Axes.SpectralAxis{
        .start_nm = 400.0,
        .end_nm = 406.0,
        .sample_count = 4,
    };
    const values = [_]f64{ 0.0, 2.0, 4.0, 6.0 };
    const targets = [_]f64{ 401.0, 403.0, 405.0 };
    var linear_out: [3]f64 = undefined;
    var spline_out: [3]f64 = undefined;

    try resampleUniform(axis, &values, &targets, .linear, &linear_out);
    try resampleUniform(axis, &values, &targets, .spline, &spline_out);

    try std.testing.expectApproxEqRel(@as(f64, 1.0), linear_out[0], 1e-12);
    try std.testing.expect(spline_out[1] > linear_out[0]);
}
