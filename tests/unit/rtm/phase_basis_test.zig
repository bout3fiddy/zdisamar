const std = @import("std");

const internal = @import("internal");

const gauss_angles = internal.rtm.gauss_angles;
const phase_basis = internal.rtm.phase_basis;
const phase_table = internal.setup.phase_table;

test "Fourier PLM basis keeps fixed layout" {
    try std.testing.expectEqual(@as(usize, 14512), @sizeOf(phase_basis.FourierPlmBasis));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(phase_basis.FourierPlmBasis));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(phase_basis.FourierPlmBasis, "fourier_index"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(phase_basis.FourierPlmBasis, "max_phase_index"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(phase_basis.FourierPlmBasis, "plus"));
}

test "phase kernel rows keep fixed layouts" {
    try std.testing.expectEqual(@as(usize, 2320), @sizeOf(phase_basis.PhaseKernel));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(phase_basis.PhaseKernel));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(phase_basis.PhaseKernel, "zplus"));
    try std.testing.expectEqual(@as(usize, 1160), @offsetOf(phase_basis.PhaseKernel, "zmin"));

    try std.testing.expectEqual(@as(usize, 200), @sizeOf(phase_basis.PhaseKernelRow));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(phase_basis.PhaseKernelRow));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(phase_basis.PhaseKernelRow, "zplus"));
    try std.testing.expectEqual(@as(usize, 96), @offsetOf(phase_basis.PhaseKernelRow, "zmin"));
    try std.testing.expectEqual(@as(usize, 192), @offsetOf(phase_basis.PhaseKernelRow, "n"));
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

test "Fourier PLM basis matches scalar m2 seed" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    const basis = phase_basis.FourierPlmBasis.init(2, 2, &geometry);

    for (0..geometry.stream_count) |stream_index| {
        const mu = geometry.u[stream_index];
        const one_minus_mu_squared = 1.0 - mu * mu;
        const seed = 0.25 * @sqrt(6.0) * one_minus_mu_squared;

        try std.testing.expectApproxEqAbs(seed * geometry.w[stream_index], basis.plus[2][stream_index], 1.0e-15);
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

test "minus canonical sign follows coefficient canonical" {
    try std.testing.expectEqual(@as(f64, 1.0), phase_basis.minusParitySign(0, 0));
    try std.testing.expectEqual(@as(f64, -1.0), phase_basis.minusParitySign(0, 1));
    try std.testing.expectEqual(@as(f64, 1.0), phase_basis.minusParitySign(2, 4));
    try std.testing.expectEqual(@as(f64, -1.0), phase_basis.minusParitySign(2, 5));
}

test "phase kernel matches scalar m0 outer products" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    const basis = phase_basis.FourierPlmBasis.init(0, 2, &geometry);
    var coefficients = phase_table.zeroPhaseCoefficients();
    coefficients[2] = 0.37;

    for (0..geometry.stream_count) |row| {
        const kernel_row = phase_basis.fillZplusZminRowFromBasisLimited(0, &coefficients, 2, &geometry, &basis, row);
        for (0..geometry.stream_count) |col| {
            const expected = scalarM0Coefficient(0, geometry.u[row], geometry.w[row]) *
                scalarM0Coefficient(0, geometry.u[col], geometry.w[col]) +
                coefficients[2] *
                    scalarM0Coefficient(2, geometry.u[row], geometry.w[row]) *
                    scalarM0Coefficient(2, geometry.u[col], geometry.w[col]);
            try std.testing.expectApproxEqAbs(expected, kernel_row.zplus[col], 1.0e-15);
            try std.testing.expectApproxEqAbs(expected, kernel_row.zmin[col], 1.0e-15);
        }
    }
}

test "phase kernel row matches scalar m1 outer products" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    const fourier_index: usize = 1;
    const basis = phase_basis.FourierPlmBasis.init(fourier_index, 3, &geometry);
    var coefficients = phase_table.zeroPhaseCoefficients();
    coefficients[1] = 0.42;
    coefficients[2] = -0.13;
    const row_index: usize = 3;

    const row = phase_basis.fillZplusZminRowFromBasisLimited(
        fourier_index,
        &coefficients,
        2,
        &geometry,
        &basis,
        row_index,
    );

    try std.testing.expectEqual(geometry.stream_count, row.n);
    for (0..geometry.stream_count) |col| {
        var expected_zplus: f64 = 0.0;
        var expected_zmin: f64 = 0.0;
        for (fourier_index..3) |phase_index| {
            const term = coefficients[phase_index] *
                basis.plus[phase_index][row_index] *
                basis.plus[phase_index][col];
            expected_zplus += term;
            expected_zmin += phase_basis.minusParitySign(fourier_index, phase_index) * term;
        }
        try std.testing.expectApproxEqAbs(expected_zplus, row.zplus[col], 1.0e-15);
        try std.testing.expectApproxEqAbs(expected_zmin, row.zmin[col], 1.0e-15);
    }
}

test "weighted phase kernel mixes aerosol and Rayleigh l2" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    const basis = phase_basis.FourierPlmBasis.init(0, 2, &geometry);
    var aerosol = phase_table.zeroPhaseCoefficients();
    aerosol[1] = 0.20;
    aerosol[2] = 0.40;
    const aerosol_weight: f64 = 0.25;
    const rayleigh2_weight: f64 = 0.31;
    const beta1 = aerosol_weight * aerosol[1];
    const beta2 = aerosol_weight * aerosol[2] + rayleigh2_weight;

    const kernel = phase_basis.fillZplusZminFromWeightedPhaseLimited(
        0,
        aerosol_weight,
        rayleigh2_weight,
        &aerosol,
        2,
        &geometry,
        &basis,
    );

    for (0..geometry.stream_count) |row| {
        for (0..geometry.stream_count) |col| {
            const l0 = scalarM0Coefficient(0, geometry.u[row], geometry.w[row]) *
                scalarM0Coefficient(0, geometry.u[col], geometry.w[col]);
            const l1 = beta1 *
                scalarM0Coefficient(1, geometry.u[row], geometry.w[row]) *
                scalarM0Coefficient(1, geometry.u[col], geometry.w[col]);
            const l2 = beta2 *
                scalarM0Coefficient(2, geometry.u[row], geometry.w[row]) *
                scalarM0Coefficient(2, geometry.u[col], geometry.w[col]);
            const expected_zplus = l0 + l1 + l2;
            const expected_zmin = l0 - l1 + l2;
            const index = row * geometry.stream_count + col;
            try std.testing.expectApproxEqAbs(expected_zplus, kernel.zplus.data[index], 1.0e-15);
            try std.testing.expectApproxEqAbs(expected_zmin, kernel.zmin.data[index], 1.0e-15);
        }
    }
}

test "phase row builders return zero rows for inactive inputs" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    const basis = phase_basis.FourierPlmBasis.init(3, 3, &geometry);
    const coefficients = phase_table.zeroPhaseCoefficients();

    const inactive_fourier = phase_basis.fillZplusZminRowFromBasisLimited(
        3,
        &coefficients,
        0,
        &geometry,
        &basis,
        1,
    );
    const invalid_row = phase_basis.fillZplusZminRowFromBasisLimited(
        0,
        &coefficients,
        0,
        &geometry,
        &basis,
        geometry.stream_count,
    );

    for (0..geometry.stream_count) |col| {
        try std.testing.expectApproxEqAbs(0.0, inactive_fourier.zplus[col], 0.0);
        try std.testing.expectApproxEqAbs(0.0, inactive_fourier.zmin[col], 0.0);
        try std.testing.expectApproxEqAbs(0.0, invalid_row.zplus[col], 0.0);
        try std.testing.expectApproxEqAbs(0.0, invalid_row.zmin[col], 0.0);
    }
}

fn scalarM0Coefficient(phase_index: usize, mu: f64, weight: f64) f64 {
    // scalarM0Coefficient ----------------------------------------------------------------------------------- |
    // Test-local reference for `phase_basis.zig` m=0 PLM rows used by Z+/Z- outer products.                   |
    // --------------------------------------------------------------------------------------------------------|
    return switch (phase_index) {
        0 => weight,
        1 => mu * weight,
        2 => ((3.0 * mu * mu - 1.0) * 0.5) * weight,
        else => unreachable,
    };
}
