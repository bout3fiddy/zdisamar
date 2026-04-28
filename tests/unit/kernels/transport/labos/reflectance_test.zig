const std = @import("std");
const internal = @import("internal");

const labos = internal.kernels.transport.labos;
const common = internal.kernels.transport.common;

const Geometry = labos.Geometry;
const UDField = labos.UDField;
const Vec = labos.Vec;
const Vec2 = labos.Vec2;
const PhaseKernel = labos.PhaseKernel;
const FourierPlmBasis = labos.FourierPlmBasis;
const fillZplusZminFromBasis = labos.fillZplusZminFromBasis;
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
    var kernel_cache: [3]PhaseKernel = undefined;
    var kernel_valid = [_]bool{false} ** 3;
    for (0..layers.len) |layer_idx| {
        kernel_cache[layer_idx + 1] = fillZplusZminFromBasis(
            i_fourier,
            layers[layer_idx].phase_coefficients,
            &geo,
            &plm_basis,
        );
        kernel_valid[layer_idx + 1] = true;
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
        &kernel_cache,
        &kernel_valid,
    );

    try std.testing.expectApproxEqAbs(baseline, cached, 1.0e-12);
}

test "integrated source truncates quadrature phase kernels by adjacent layers" {
    const geo = Geometry.init(4, 0.58, 0.64);
    const layer_phase = .{ 1.0, 0.18, 0.31 } ++ .{0.0} ** (max_phase_coef - 3);
    const source_phase_with_tail = .{ 1.0, 0.18, 0.31, 4.0 } ++ .{0.0} ** (max_phase_coef - 4);
    const source_phase_truncated = .{ 1.0, 0.18, 0.31 } ++ .{0.0} ** (max_phase_coef - 3);
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
            .phase_coefficients = source_phase_with_tail,
        },
        .{},
    } };
    const rtm_quadrature_truncated = common.RtmQuadratureGrid{ .levels = &.{
        .{},
        .{
            .weight = 1.0,
            .ksca = 1.0,
            .phase_coefficients = source_phase_truncated,
        },
        .{},
    } };
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
    );

    try std.testing.expectApproxEqAbs(expected, actual, 1.0e-12);
}
