const std = @import("std");
const internal = @import("internal");

const labos = internal.forward_model.radiative_transfer.labos;
const common = internal.forward_model.radiative_transfer;

const Geometry = labos.Geometry;
const UDField = labos.UDField;
const Vec = labos.Vec;
const Vec2 = labos.Vec2;
const PhaseKernelRow = labos.PhaseKernelRow;
const FourierPlmBasis = labos.FourierPlmBasis;
const fillZplusZminFromBasis = labos.fillZplusZminFromBasis;
const calcRTlayersIntoWithBasis = labos.calcRTlayersIntoWithBasis;
const max_phase_coef = labos.max_phase_coef;
const calcIntegratedReflectance = labos.calcIntegratedReflectance;
const calcIntegratedReflectanceWithBasis = labos.calcIntegratedReflectanceWithBasis;
const resolvedPhaseCoefficientMax = labos.resolvedPhaseCoefficientMax;

test "cached layer kernels preserve integrated reflectance when source interfaces mirror layers" {
    const geo = Geometry.init(4, 0.58, 0.64);
    const layers = [_]common.LayerInput{
        .{
            .scattering_optical_depth = 0.22,
            .phase_coefficients = .{ 1.0, 0.56, 0.24, 0.09 } ++
                .{0.0} ** (max_phase_coef - 4),
        },
        .{
            .scattering_optical_depth = 0.18,
            .phase_coefficients = .{ 1.0, 0.41, 0.17, 0.05 } ++
                .{0.0} ** (max_phase_coef - 4),
        },
    };
    var ud: [3]UDField = undefined;
    for (&ud) |*field| {
        field.* = .{
            .E = Vec.zero(geo.nmutot),
            .U = Vec2.zero(geo.nmutot),
            .D = Vec2.zero(geo.nmutot),
        };
    }
    for (0..ud.len) |ilevel| {
        for (0..geo.nmutot) |imu| {
            ud[ilevel].E.set(imu, 0.8 - 0.1 * @as(f64, @floatFromInt(ilevel)));
            for (0..2) |imu0| {
                ud[ilevel].U.col[imu0].set(imu, 0.02 * @as(f64, @floatFromInt((ilevel + 1) * (imu + 1) * (imu0 + 1))));
                ud[ilevel].D.col[imu0].set(imu, 0.01 * @as(f64, @floatFromInt((ilevel + 2) * (imu + 1) * (imu0 + 1))));
            }
        }
    }

    var source_interfaces: [3]common.SourceInterfaceInput = undefined;
    common.fillSourceInterfacesFromLayers(&layers, &source_interfaces);
    const input: common.ForwardInput = .{
        .layers = &layers,
        .source_interfaces = &source_interfaces,
    };
    const i_fourier: usize = 1;
    const plm_basis = FourierPlmBasis.init(i_fourier, resolvedPhaseCoefficientMax(input), &geo);
    var row_cache: [3]PhaseKernelRow = undefined;
    var row_valid = [_]bool{false} ** 3;
    for (0..layers.len) |layer_idx| {
        const kernel = fillZplusZminFromBasis(
            i_fourier,
            &layers[layer_idx].phase_coefficients,
            &geo,
            &plm_basis,
        );
        var row = PhaseKernelRow{
            .zplus = undefined,
            .zmin = undefined,
            .n = geo.nmutot,
        };
        const view_row_offset = geo.viewIdx() * geo.nmutot;
        for (0..geo.nmutot) |col| {
            row.zplus[col] = kernel.Zplus.data[view_row_offset + col];
            row.zmin[col] = kernel.Zmin.data[view_row_offset + col];
        }
        row_cache[layer_idx + 1] = row;
        row_valid[layer_idx + 1] = true;
    }

    const baseline = calcIntegratedReflectance(
        &layers,
        &source_interfaces,
        .{},
        &ud,
        layers.len,
        i_fourier,
        &geo,
    );
    const cached = calcIntegratedReflectanceWithBasis(
        &layers,
        &source_interfaces,
        .{},
        &ud,
        layers.len,
        i_fourier,
        &geo,
        &plm_basis,
        null,
        &row_cache,
        &row_valid,
    );

    try std.testing.expectApproxEqAbs(baseline, cached, 1.0e-12);
}

test "layer build caches observer phase row for integrated-source reflectance" {
    const geo = Geometry.init(4, 0.58, 0.64);
    const layer_phase = .{ 1.0, 0.47, 0.18, 0.06 } ++ .{0.0} ** (max_phase_coef - 4);
    const layers = [_]common.LayerInput{.{
        .optical_depth = 0.2,
        .scattering_optical_depth = 0.18,
        .single_scatter_albedo = 0.9,
        .phase_coefficients = layer_phase,
    }};
    const i_fourier: usize = 1;
    const plm_basis = FourierPlmBasis.init(i_fourier, 3, &geo);
    var rt: [2]labos.LayerRT = undefined;
    var row_cache: [2]PhaseKernelRow = undefined;
    var row_valid = [_]bool{false} ** 2;

    calcRTlayersIntoWithBasis(
        &rt,
        &layers,
        i_fourier,
        &geo,
        .{ .n_streams = 8, .scattering = .single },
        &plm_basis,
        null,
        null,
        max_phase_coef,
        &row_cache,
        &row_valid,
        null,
    );

    const expected_kernel = fillZplusZminFromBasis(
        i_fourier,
        &layers[0].phase_coefficients,
        &geo,
        &plm_basis,
    );
    const row_offset = geo.viewIdx() * geo.nmutot;
    try std.testing.expect(row_valid[1]);
    try std.testing.expectEqual(geo.nmutot, row_cache[1].n);
    for (0..geo.nmutot) |col| {
        try std.testing.expectApproxEqAbs(expected_kernel.Zplus.data[row_offset + col], row_cache[1].zplus[col], 1.0e-12);
        try std.testing.expectApproxEqAbs(expected_kernel.Zmin.data[row_offset + col], row_cache[1].zmin[col], 1.0e-12);
    }
}

test "integrated source truncates quadrature phase kernels by adjacent layers" {
    const geo = Geometry.init(4, 0.58, 0.64);
    const layer_phase: [max_phase_coef]f64 = .{ 1.0, 0.18, 0.31 } ++ .{0.0} ** (max_phase_coef - 3);
    const source_phase_with_tail: [max_phase_coef]f64 = .{ 1.0, 0.18, 0.31, 4.0 } ++ .{0.0} ** (max_phase_coef - 4);
    const source_phase_truncated: [max_phase_coef]f64 = .{ 1.0, 0.18, 0.31 } ++ .{0.0} ** (max_phase_coef - 3);
    const layers = [_]common.LayerInput{
        .{
            .scattering_optical_depth = 0.1,
            .phase_coefficients = layer_phase,
        },
        .{
            .scattering_optical_depth = 0.1,
            .phase_coefficients = layer_phase,
        },
    };
    var ud: [3]UDField = undefined;
    for (&ud, 0..) |*field, ilevel| {
        field.* = .{
            .E = Vec.zero(geo.nmutot),
            .U = Vec2.zero(geo.nmutot),
            .D = Vec2.zero(geo.nmutot),
        };
        for (0..geo.nmutot) |imu| {
            field.E.set(imu, 0.8 + 0.03 * @as(f64, @floatFromInt(ilevel + imu)));
            for (0..2) |col| {
                field.U.col[col].set(imu, 0.015 * @as(f64, @floatFromInt((ilevel + 1) * (imu + 2) * (col + 1))));
                field.D.col[col].set(imu, 0.011 * @as(f64, @floatFromInt((ilevel + 2) * (imu + 1) * (col + 1))));
            }
        }
    }

    const rtm_quadrature_with_tail = common.RtmQuadratureGrid{ .levels = &.{
        .{},
        .{
            .weight = 1.0,
            .ksca = 1.0,
            .phase_aerosol_weight = 1.0,
        },
        .{},
    }, .aerosol_phase_coefficients = &source_phase_with_tail };
    const rtm_quadrature_truncated = common.RtmQuadratureGrid{ .levels = &.{
        .{},
        .{
            .weight = 1.0,
            .ksca = 1.0,
            .phase_aerosol_weight = 1.0,
        },
        .{},
    }, .aerosol_phase_coefficients = &source_phase_truncated };
    const i_fourier: usize = 0;
    const plm_basis = FourierPlmBasis.init(i_fourier, 3, &geo);

    const actual = calcIntegratedReflectanceWithBasis(
        &layers,
        &.{},
        rtm_quadrature_with_tail,
        &ud,
        layers.len,
        i_fourier,
        &geo,
        &plm_basis,
        null,
        null,
        null,
    );
    const expected = calcIntegratedReflectanceWithBasis(
        &layers,
        &.{},
        rtm_quadrature_truncated,
        &ud,
        layers.len,
        i_fourier,
        &geo,
        &plm_basis,
        null,
        null,
        null,
    );

    try std.testing.expectApproxEqAbs(expected, actual, 1.0e-12);
}
