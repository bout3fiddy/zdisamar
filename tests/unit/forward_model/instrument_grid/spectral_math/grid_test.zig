const std = @import("std");
const internal = @import("internal");

const grid_mod = internal.forward_model.instrument_grid.spectral_math.grid;
const SpectralGrid = grid_mod.SpectralGrid;
const ResolvedAxis = grid_mod.ResolvedAxis;
const validateExplicitSamples = grid_mod.validateExplicitSamples;
const sampleAtExplicit = grid_mod.sampleAtExplicit;

test "spectral grid validates and resolves sample coordinates" {
    const grid = SpectralGrid{
        .start_nm = 405.0,
        .end_nm = 465.0,
        .sample_count = 7,
    };
    try grid.validate();
    try std.testing.expectApproxEqRel(@as(f64, 405.0), try grid.sampleAt(0), 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 465.0), try grid.sampleAt(6), 1e-12);
}

test "explicit spectral axes validate strict monotonic measured-channel wavelengths" {
    try validateExplicitSamples(&.{ 760.8, 761.02, 761.31 });
    try std.testing.expectApproxEqAbs(@as(f64, 761.02), try sampleAtExplicit(&.{ 760.8, 761.02, 761.31 }, 1), 1.0e-12);
    try std.testing.expectError(error.InvalidExplicitSamples, validateExplicitSamples(&.{ 761.0, 760.9 }));
}

test "resolved spectral axes unify native and measured-channel addressing" {
    const native_axis: ResolvedAxis = .{
        .base = .{
            .start_nm = 760.0,
            .end_nm = 761.0,
            .sample_count = 3,
        },
    };
    try std.testing.expectApproxEqAbs(@as(f64, 760.5), try native_axis.sampleAt(1), 1.0e-12);

    const measured_axis: ResolvedAxis = .{
        .base = native_axis.base,
        .explicit_wavelengths_nm = &.{ 760.02, 760.41, 760.93 },
    };
    try std.testing.expectApproxEqAbs(@as(f64, 760.41), try measured_axis.sampleAt(1), 1.0e-12);
}
