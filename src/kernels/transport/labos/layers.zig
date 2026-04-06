//! Purpose:
//!   Own the LABOS per-layer reflection/transmission operators and the surface
//!   Lambertian response.
//!
//! Physics:
//!   Builds homogeneous-layer single-scatter operators, applies doubling for
//!   thick layers, and initializes the surface reflector.
//!
//! Vendor:
//!   LABOS layer R/T stages
//!
//! Design:
//!   The layer operator code is isolated from the basis algebra and the
//!   scattering-order transport so the core solver can be read as a staged
//!   pipeline instead of one monolithic routine.
//!
//! Invariants:
//!   Layer indices are resolved against the transport grid, and the surface is
//!   only active for the zero Fourier term.
//!
//! Validation:
//!   See `tests/unit/transport_labos_test.zig` for layer-operator smoke and
//!   scenario coverage.

const std = @import("std");
const math = std.math;
const phase_functions = @import("../../optics/prepare/phase_functions.zig");
const basis = @import("basis.zig");
const attenuation = @import("attenuation.zig");
const common = @import("../common.zig");

pub const LayerRT = basis.LayerRT;

fn locateLowerIndex(values: []const f64, target: f64) usize {
    if (values.len <= 1) return 0;
    var index: usize = 0;
    while (index + 1 < values.len and values[index + 1] < target) : (index += 1) {}
    return index;
}

fn zeroFourierIntegral(
    zplus: *const basis.Mat,
    zmin: *const basis.Mat,
    geo: *const basis.Geometry,
    column_index: usize,
) f64 {
    const column_weight = @max(geo.w[column_index], 1.0e-30);
    var integral: f64 = 0.0;
    for (0..geo.n_gauss) |imu| {
        const row_weight = @max(geo.w[imu], 1.0e-30);
        integral += geo.wg[imu] *
            ((zplus.get(imu, column_index) + zmin.get(imu, column_index)) /
                (row_weight * column_weight));
    }
    return integral;
}

fn renormalizeZeroFourierPhaseKernel(
    geo: *const basis.Geometry,
    zplus: *basis.Mat,
    zmin: *basis.Mat,
) void {
    if (geo.n_gauss == 0 or geo.nmutot == 0) return;

    var zp = [_][basis.max_nmutot]f64{.{0.0} ** basis.max_nmutot} ** basis.max_nmutot;
    for (0..geo.nmutot) |imu0| {
        const column_weight = @max(geo.w[imu0], 1.0e-30);
        for (0..geo.nmutot) |imu| {
            const row_weight = @max(geo.w[imu], 1.0e-30);
            zp[imu][imu0] = zplus.get(imu, imu0) / (row_weight * column_weight);
        }
    }

    for (0..geo.n_gauss) |imu0| {
        var integral: f64 = 0.0;
        for (0..geo.n_gauss) |imu| {
            integral += geo.wg[imu] * (zp[imu][imu0] + zmin.get(imu, imu0) / (@max(geo.w[imu], 1.0e-30) * @max(geo.w[imu0], 1.0e-30)));
        }
        const denominator = zp[imu0][imu0] * geo.wg[imu0];
        if (@abs(denominator) <= 1.0e-30) continue;
        const fraction = (2.0 - integral) / denominator;
        zp[imu0][imu0] *= 1.0 + fraction;
    }

    for (geo.n_gauss..geo.nmutot) |imu0| {
        const target_mu = geo.u[imu0];
        var integral: f64 = 0.0;
        for (0..geo.n_gauss) |imu| {
            integral += geo.wg[imu] * (zp[imu][imu0] + zmin.get(imu, imu0) / (@max(geo.w[imu], 1.0e-30) * @max(geo.w[imu0], 1.0e-30)));
        }
        const delta = 2.0 - integral;

        if (target_mu > geo.ug[0] and target_mu < geo.ug[geo.n_gauss - 1]) {
            const low = @min(locateLowerIndex(geo.ug[0..geo.n_gauss], target_mu), geo.n_gauss - 2);
            const high = low + 1;
            const span = geo.ug[high] - geo.ug[low];
            if (span <= 0.0) continue;
            const low_weight = (target_mu - geo.ug[low]) / span;
            const high_weight = (geo.ug[high] - target_mu) / span;
            const low_denominator = zp[imu0][low] * geo.wg[low];
            const high_denominator = zp[imu0][high] * geo.wg[high];
            if (@abs(low_denominator) > 1.0e-30) {
                const fraction = low_weight * delta / low_denominator;
                zp[imu0][low] *= 1.0 + fraction;
                zp[low][imu0] = zp[imu0][low];
            }
            if (@abs(high_denominator) > 1.0e-30) {
                const fraction = high_weight * delta / high_denominator;
                zp[imu0][high] *= 1.0 + fraction;
                zp[high][imu0] = zp[imu0][high];
            }
            continue;
        }

        const edge = if (target_mu < geo.ug[0]) 0 else geo.n_gauss - 1;
        const denominator = zp[imu0][edge] * geo.wg[edge];
        if (@abs(denominator) <= 1.0e-30) continue;
        const fraction = delta / denominator;
        zp[imu0][edge] *= 1.0 + fraction;
        zp[edge][imu0] = zp[imu0][edge];
    }

    for (0..geo.nmutot) |imu0| {
        const column_weight = geo.w[imu0];
        for (0..geo.nmutot) |imu| {
            zplus.set(imu, imu0, zp[imu][imu0] * geo.w[imu] * column_weight);
        }
    }
}

/// Rsingle: single-scattering reflection for a homogeneous layer.
fn singleScatterR(
    a: f64,
    E: *const basis.Vec,
    Zmin: *const basis.Mat,
    geo: *const basis.Geometry,
) basis.Mat {
    const n = geo.nmutot;
    var result = basis.Mat.zero(n);

    for (0..n) |j| {
        const uj = geo.u[j];
        const ej = E.get(j);
        for (0..n) |i| {
            const ui = geo.u[i];
            const dmu_plus = 0.25 / @max(ui + uj, 1.0e-12);
            const eer = E.get(i) * ej;
            result.set(i, j, a * Zmin.get(i, j) * (1.0 - eer) * dmu_plus);
        }
    }
    return result;
}

/// Tsingle: single-scattering transmission for a homogeneous layer.
fn singleScatterT(
    a: f64,
    b: f64,
    E: *const basis.Vec,
    Zplus: *const basis.Mat,
    geo: *const basis.Geometry,
) basis.Mat {
    const n = geo.nmutot;
    var result = basis.Mat.zero(n);

    for (0..n) |j| {
        const uj = geo.u[j];
        for (0..n) |i| {
            const ui = geo.u[i];
            const du = ui - uj;
            var eet: f64 = undefined;
            var dmu_min: f64 = undefined;
            if (@abs(du) < 1.0e-6) {
                eet = b * E.get(i);
                dmu_min = 0.25 / @max(ui * uj, 1.0e-12);
            } else {
                eet = E.get(i) - E.get(j);
                dmu_min = 0.25 / du;
            }
            result.set(i, j, a * Zplus.get(i, j) * eet * dmu_min);
        }
    }
    return result;
}

/// Perform ndouble doubling steps on R, T, E for a layer.
fn doDouble(
    ndouble: usize,
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    geo: *const basis.Geometry,
    b_start: f64,
    R: *basis.Mat,
    T: *basis.Mat,
    E: *basis.Vec,
) void {
    var b = b_start;
    for (0..ndouble) |_| {
        const Q = basis.qseries(n, n_gauss, threshold_mul, R, R);
        const qe = basis.semul(n, &Q, E);
        const qt = basis.smul(n, n_gauss, threshold_mul, &Q, T);
        var D = basis.matAdd(n, T, &qe);
        D = basis.matAdd(n, &D, &qt);

        const re = basis.semul(n, R, E);
        const rd = basis.smul(n, n_gauss, threshold_mul, R, &D);
        const U = basis.matAdd(n, &re, &rd);

        const eu = basis.esmul(n, E, &U);
        const tu = basis.smul(n, n_gauss, threshold_mul, T, &U);
        var R_new = basis.matAdd(n, R, &eu);
        R_new = basis.matAdd(n, &R_new, &tu);
        R.* = R_new;

        const ed = basis.esmul(n, E, &D);
        const te = basis.semul(n, T, E);
        const td = basis.smul(n, n_gauss, threshold_mul, T, &D);
        var T_new = basis.matAdd(n, &ed, &te);
        T_new = basis.matAdd(n, &T_new, &td);
        T.* = T_new;

        b *= 2.0;
        if (b < 0.001) {
            for (0..geo.nmutot) |imu| {
                E.set(imu, math.exp(-b / @max(geo.u[imu], 1.0e-12)));
            }
        } else {
            for (0..geo.nmutot) |imu| {
                const e = E.get(imu);
                E.set(imu, e * e);
            }
        }
    }
}

/// Purpose:
///   Build the layer reflection and transmission operators in place.
///
/// Physics:
///   Turns each transport layer into its Fourier-specific single-scatter or
///   doubled response on the LABOS grid.
fn maxLayerPhaseCoefficientIndex(layers: []const common.LayerInput) usize {
    var max_index: usize = 0;
    for (layers) |layer| {
        max_index = @max(max_index, phase_functions.maxPhaseCoefficientIndex(layer.phase_coefficients));
    }
    return max_index;
}

/// Purpose:
///   Build the layer reflection and transmission operators in place using a
///   caller-provided Fourier basis cache.
///
/// Physics:
///   Reuses one Fourier-specific associated-Legendre basis across all layers so
///   the phase-kernel build stays exact without rebuilding the same basis work.
pub fn calcRTlayersIntoWithBasis(
    rt: []LayerRT,
    layers: []const common.LayerInput,
    i_fourier: usize,
    geo: *const basis.Geometry,
    controls: common.RtmControls,
    plm_basis: *const basis.FourierPlmBasis,
    phase_kernel_cache: ?[]basis.PhaseKernel,
    phase_kernel_valid: ?[]bool,
) void {
    const nlayer = layers.len;

    for (rt) |*entry| {
        entry.* = .{
            .R = basis.Mat.zero(geo.nmutot),
            .T = basis.Mat.zero(geo.nmutot),
        };
    }
    if (phase_kernel_valid) |valid| @memset(valid, false);

    for (0..nlayer) |layer_idx| {
        const rt_idx = layer_idx + 1;
        const layer = layers[layer_idx];
        if (i_fourier >= basis.max_phase_coef) continue;

        const phase_coefs = layer.phase_coefficients;
        const max_phase_index = phase_functions.maxPhaseCoefficientIndex(phase_coefs);
        if (i_fourier > max_phase_index) continue;

        var z = basis.fillZplusZminFromBasis(i_fourier, phase_coefs, geo, plm_basis);
        if (phase_kernel_cache) |cache| {
            cache[rt_idx] = z;
            if (phase_kernel_valid) |valid| valid[rt_idx] = true;
        }
        if (layer.optical_depth < 1.0e-20) continue;

        const b = layer.optical_depth;
        const a = layer.single_scatter_albedo;

        var max_beta_eff: f64 = 0.0;
        for (i_fourier..max_phase_index + 1) |ic| {
            const icf: f64 = @floatFromInt(ic);
            const beta_eff = @abs(phase_coefs[ic]) / (2.0 * icf + 1.0);
            if (beta_eff > max_beta_eff) max_beta_eff = beta_eff;
        }
        const a_eff = a * max_beta_eff;

        var use_doubling = false;
        var b_start = b;
        var ndouble: usize = 0;

        if (controls.scattering == .multiple and a_eff * b > controls.threshold_doubl) {
            // DECISION:
            //   Trigger doubling only when the scaled optical thickness crosses
            //   the configured threshold.
            use_doubling = true;
            var bd = b;
            for (0..60) |_| {
                bd /= 2.0;
                ndouble += 1;
                if (a_eff * bd < controls.threshold_doubl) break;
            }
            b_start = bd;
        }

        var E = basis.Vec.zero(geo.nmutot);
        for (0..geo.nmutot) |imu| {
            E.set(imu, math.exp(-b_start / @max(geo.u[imu], 1.0e-12)));
        }

        var R = singleScatterR(a, &E, &z.Zmin, geo);
        var T = singleScatterT(a, b_start, &E, &z.Zplus, geo);

        if (use_doubling) {
            if (i_fourier == 0 and controls.renorm_phase_function) {
                renormalizeZeroFourierPhaseKernel(geo, &z.Zplus, &z.Zmin);
                R = singleScatterR(a, &E, &z.Zmin, geo);
                T = singleScatterT(a, b_start, &E, &z.Zplus, geo);
            }
            doDouble(ndouble, geo.nmutot, geo.n_gauss, controls.threshold_mul, geo, b_start, &R, &T, &E);
        }

        rt[rt_idx].R = R;
        rt[rt_idx].T = T;
    }
}

/// Purpose:
///   Build the layer reflection and transmission operators in place.
///
/// Physics:
///   Turns each transport layer into its Fourier-specific single-scatter or
///   doubled response on the LABOS grid.
pub fn calcRTlayersInto(
    rt: []LayerRT,
    layers: []const common.LayerInput,
    i_fourier: usize,
    geo: *const basis.Geometry,
    controls: common.RtmControls,
) void {
    const plm_basis = basis.FourierPlmBasis.init(
        i_fourier,
        maxLayerPhaseCoefficientIndex(layers),
        geo,
    );
    calcRTlayersIntoWithBasis(
        rt,
        layers,
        i_fourier,
        geo,
        controls,
        &plm_basis,
        null,
        null,
    );
}

test "zero-Fourier renormalization restores Gaussian quadrature closure" {
    const geo = basis.Geometry.init(10, 0.61, 0.67);
    const phase_coefficients = phase_functions.phaseCoefficientsFromLegacy(.{
        1.0,
        0.98,
        0.98 * 0.98,
        0.98 * 0.98 * 0.98,
    });
    var z = basis.fillZplusZmin(0, phase_coefficients, &geo);

    const before_view = zeroFourierIntegral(&z.Zplus, &z.Zmin, &geo, geo.viewIdx());
    const before_solar = zeroFourierIntegral(&z.Zplus, &z.Zmin, &geo, geo.n_gauss + 1);
    try std.testing.expect(@abs(before_view - 2.0) > 1.0e-4);
    try std.testing.expect(@abs(before_solar - 2.0) > 1.0e-4);

    renormalizeZeroFourierPhaseKernel(&geo, &z.Zplus, &z.Zmin);

    try std.testing.expectApproxEqAbs(@as(f64, 2.0), zeroFourierIntegral(&z.Zplus, &z.Zmin, &geo, 0), 1.0e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), zeroFourierIntegral(&z.Zplus, &z.Zmin, &geo, geo.viewIdx()), 1.0e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), zeroFourierIntegral(&z.Zplus, &z.Zmin, &geo, geo.n_gauss + 1), 1.0e-10);
}

test "calcRTlayersInto consumes renorm_phase_function on doubled zero-Fourier layers" {
    const geo = basis.Geometry.init(10, 0.61, 0.67);
    const layers = [_]common.LayerInput{.{
        .optical_depth = 2.4,
        .scattering_optical_depth = 2.2,
        .single_scatter_albedo = 0.92,
        .phase_coefficients = phase_functions.phaseCoefficientsFromLegacy(.{
            1.0,
            0.98,
            0.98 * 0.98,
            0.98 * 0.98 * 0.98,
        }),
    }};

    var rt_without = [_]LayerRT{ undefined, undefined };
    var rt_with = [_]LayerRT{ undefined, undefined };
    calcRTlayersInto(rt_without[0..], &layers, 0, &geo, .{
        .n_streams = 20,
        .threshold_doubl = 1.0e-6,
        .renorm_phase_function = false,
    });
    calcRTlayersInto(rt_with[0..], &layers, 0, &geo, .{
        .n_streams = 20,
        .threshold_doubl = 1.0e-6,
        .renorm_phase_function = true,
    });

    try std.testing.expect(@abs(
        rt_with[1].R.get(geo.viewIdx(), geo.n_gauss + 1) -
            rt_without[1].R.get(geo.viewIdx(), geo.n_gauss + 1),
    ) > 1.0e-8);
}

/// Purpose:
///   Build all layer reflection and transmission operators for one Fourier term.
pub fn calcRTlayers(
    layers: []const common.LayerInput,
    i_fourier: usize,
    geo: *const basis.Geometry,
    controls: common.RtmControls,
) [attenuation.AttenArray.max_levels]LayerRT {
    var rt: [attenuation.AttenArray.max_levels]LayerRT = undefined;
    calcRTlayersInto(rt[0 .. layers.len + 1], layers, i_fourier, geo, controls);
    return rt;
}

/// Purpose:
///   Materialize the zero-Fourier surface Lambertian response.
pub fn fillSurface(
    i_fourier: usize,
    albedo: f64,
    geo: *const basis.Geometry,
) LayerRT {
    const n = geo.nmutot;
    var result: LayerRT = .{
        .R = basis.Mat.zero(n),
        .T = basis.Mat.zero(n),
    };

    if (i_fourier == 0) {
        for (0..n) |j| {
            for (0..n) |i| {
                result.R.set(i, j, geo.w[i] * albedo * geo.w[j]);
            }
        }
    }

    return result;
}
