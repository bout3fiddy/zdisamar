const std = @import("std");
const layout = @import("model_layout");

pub const Error = error{
    ShapeMismatch,
} || layout.Axes.Error;

pub fn integrateUniform(axis: layout.Axes.SpectralAxis, values: []const f64) Error!f64 {
    try axis.validate();
    if (values.len != axis.sample_count) return Error.ShapeMismatch;

    const step = try axis.stepNm();
    var sum: f64 = 0.0;

    var i: usize = 1;
    while (i + 1 < values.len) : (i += 1) {
        sum += values[i];
    }

    return step * ((values[0] + values[values.len - 1]) * 0.5 + sum);
}

test "composite trapezoid integrates linear profile" {
    const axis = layout.Axes.SpectralAxis{
        .start_nm = 0.0,
        .end_nm = 10.0,
        .sample_count = 11,
    };

    var values: [11]f64 = undefined;
    for (&values, 0..) |*value, idx| {
        value.* = @floatFromInt(idx);
    }

    const integral = try integrateUniform(axis, &values);
    try std.testing.expectApproxEqRel(@as(f64, 50.0), integral, 1e-12);
}
