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
const basis = @import("basis.zig");
const attenuation = @import("attenuation.zig");
const common = @import("../common.zig");

pub const LayerRT = basis.LayerRT;

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
pub fn calcRTlayersInto(
    rt: []LayerRT,
    layers: []const common.LayerInput,
    i_fourier: usize,
    geo: *const basis.Geometry,
    controls: common.RtmControls,
) void {
    const nlayer = layers.len;

    for (rt) |*entry| {
        entry.* = .{
            .R = basis.Mat.zero(geo.nmutot),
            .T = basis.Mat.zero(geo.nmutot),
        };
    }

    for (0..nlayer) |layer_idx| {
        const rt_idx = layer_idx + 1;
        const layer = layers[layer_idx];

        if (layer.optical_depth < 1.0e-20) continue;
        if (i_fourier >= basis.max_phase_coef) continue;

        const b = layer.optical_depth;
        const a = layer.single_scatter_albedo;
        const phase_coefs = layer.phase_coefficients;

        var max_beta_eff: f64 = 0.0;
        for (i_fourier..basis.max_phase_coef) |ic| {
            const icf: f64 = @floatFromInt(ic);
            const beta_eff = @abs(phase_coefs[ic]) / (2.0 * icf + 1.0);
            if (beta_eff > max_beta_eff) max_beta_eff = beta_eff;
        }
        const a_eff = a * max_beta_eff;

        const z = basis.fillZplusZmin(i_fourier, phase_coefs, geo);

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
            doDouble(ndouble, geo.nmutot, geo.n_gauss, controls.threshold_mul, geo, b_start, &R, &T, &E);
        }

        rt[rt_idx].R = R;
        rt[rt_idx].T = T;
    }
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
