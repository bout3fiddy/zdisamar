const std = @import("std");

const internal = @import("internal");

const gauss_angles = internal.transport.gauss_angles;
const phase_basis = internal.transport.phase_basis;

test "Fourier PLM basis keeps old fixed layout" {
    try std.testing.expectEqual(@as(usize, 14512), @sizeOf(phase_basis.FourierPlmBasis));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(phase_basis.FourierPlmBasis));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(phase_basis.FourierPlmBasis, "fourier_index"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(phase_basis.FourierPlmBasis, "max_phase_index"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(phase_basis.FourierPlmBasis, "plus"));
}

test "Fourier PLM basis matches scalar m0 recurrence" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    const basis = phase_basis.FourierPlmBasis.init(0, 3, &geometry);

    try std.testing.expectEqual(@as(usize, 0), basis.fourier_index);
    try std.testing.expectEqual(@as(usize, 3), basis.max_phase_index);

    for (0..geometry.stream_count) |stream_index| {
        const mu = geometry.u[stream_index];
        const weight = geometry.w[stream_index];
        try std.testing.expectApproxEqAbs(weight, basis.plus[0][stream_index], 1.0e-15);
        try std.testing.expectApproxEqAbs(mu * weight, basis.plus[1][stream_index], 1.0e-15);
        try std.testing.expectApproxEqAbs(((3.0 * mu * mu - 1.0) * 0.5) * weight, basis.plus[2][stream_index], 1.0e-15);
    }
}

test "Fourier PLM basis matches scalar m1 seed and recurrence" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    const basis = phase_basis.FourierPlmBasis.init(1, 3, &geometry);

    for (0..geometry.stream_count) |stream_index| {
        const mu = geometry.u[stream_index];
        const one_minus_mu_squared = 1.0 - mu * mu;
        const seed = @sqrt(@max(one_minus_mu_squared, 0.0)) / @sqrt(2.0);
        const p2 = @sqrt(3.0) * mu * seed;

        try std.testing.expectApproxEqAbs(seed * geometry.w[stream_index], basis.plus[1][stream_index], 1.0e-15);
        try std.testing.expectApproxEqAbs(p2 * geometry.w[stream_index], basis.plus[2][stream_index], 1.0e-15);
    }
}

test "Fourier PLM basis handles high-order seed" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    const basis = phase_basis.FourierPlmBasis.init(3, 3, &geometry);

    for (0..geometry.stream_count) |stream_index| {
        const mu = geometry.u[stream_index];
        const one_minus_mu_squared = 1.0 - mu * mu;
        const seed_base = 0.375 * one_minus_mu_squared * one_minus_mu_squared;
        const seed = @sqrt(@max(seed_base * one_minus_mu_squared * 2.5 / 3.0, 0.0));

        try std.testing.expectApproxEqAbs(seed * geometry.w[stream_index], basis.plus[3][stream_index], 1.0e-15);
    }
}

test "minus parity sign follows old coefficient parity" {
    try std.testing.expectEqual(@as(f64, 1.0), phase_basis.minusParitySign(0, 0));
    try std.testing.expectEqual(@as(f64, -1.0), phase_basis.minusParitySign(0, 1));
    try std.testing.expectEqual(@as(f64, 1.0), phase_basis.minusParitySign(2, 4));
    try std.testing.expectEqual(@as(f64, -1.0), phase_basis.minusParitySign(2, 5));
}
