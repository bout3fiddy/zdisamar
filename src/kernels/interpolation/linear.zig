const std = @import("std");
const layout = @import("model_layout");

pub const Error = error{
    ShapeMismatch,
    OutOfDomain,
} || layout.Axes.Error;

pub fn sampleUniform(
    axis: layout.Axes.SpectralAxis,
    values: []const f64,
    wavelength_nm: f64,
) Error!f64 {
    try axis.validate();
    if (values.len != axis.sample_count) return Error.ShapeMismatch;

    if (wavelength_nm < axis.start_nm or wavelength_nm > axis.end_nm) {
        return Error.OutOfDomain;
    }

    const step = try axis.stepNm();
    const normalized = (wavelength_nm - axis.start_nm) / step;

    const left_index_f = @floor(normalized);
    const left_index: u32 = @intFromFloat(left_index_f);
    const right_index: u32 = @min(left_index + 1, axis.sample_count - 1);
    const alpha = normalized - left_index_f;

    const left_value = values[left_index];
    const right_value = values[right_index];
    return (1.0 - alpha) * left_value + alpha * right_value;
}

test "linear interpolation samples inside spectral axis bounds" {
    const axis = layout.Axes.SpectralAxis{
        .start_nm = 400.0,
        .end_nm = 410.0,
        .sample_count = 6,
    };
    const values = [_]f64{ 0.0, 10.0, 20.0, 30.0, 40.0, 50.0 };

    const v = try sampleUniform(axis, &values, 405.0);
    try std.testing.expectApproxEqRel(@as(f64, 25.0), v, 1e-12);
}
