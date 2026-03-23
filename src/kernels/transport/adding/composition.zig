//! Purpose:
//!   Own the adding-method layer-composition algebra for transport scenes.
//!
//! Physics:
//!   Combines layer reflection and transmission blocks into the accumulated
//!   upward and downward transport state used by the adding method.
//!
//! Vendor:
//!   `adding` composition stage
//!
//! Design:
//!   The Zig version keeps the top-down and surface-up recurrences explicit
//!   while isolating the matrix-composition algebra from field reconstruction
//!   and execution orchestration.
//!
//! Invariants:
//!   The returned scattering summaries must preserve the Fourier-0 vendor
//!   scalar reductions and zero the higher-order scalar closures.
//!
//! Validation:
//!   `tests/unit/transport_adding_test.zig` and transport integration suites.

const common = @import("../common.zig");
const labos = @import("../labos.zig");

/// Purpose:
///   Accumulate the transport state associated with one partially composed
///   atmosphere.
///
/// Physics:
///   Stores the reflection, transmission, and source-function closures needed
///   to continue the adding recursion through the column.
///
/// Vendor:
///   `adding` partial-atmosphere state
pub const PartAtmosphere = struct {
    R: labos.Mat,
    T: labos.Mat,
    Rst: labos.Mat,
    Tst: labos.Mat,
    U: labos.Mat,
    D: labos.Mat,
    Ust: labos.Mat,
    Dst: labos.Mat,
    tpl: labos.Vec,
    tplst: labos.Vec,
    s: f64,
    sst: f64,

    pub fn zero(n: usize) PartAtmosphere {
        return .{
            .R = labos.Mat.zero(n),
            .T = labos.Mat.zero(n),
            .Rst = labos.Mat.zero(n),
            .Tst = labos.Mat.zero(n),
            .U = labos.Mat.zero(n),
            .D = labos.Mat.zero(n),
            .Ust = labos.Mat.zero(n),
            .Dst = labos.Mat.zero(n),
            .tpl = labos.Vec.zero(n),
            .tplst = labos.Vec.zero(n),
            .s = 0.0,
            .sst = 0.0,
        };
    }
};

/// Purpose:
///   Combine the bottom layer with the atmosphere above it using the adding
///   recurrence.
///
/// Physics:
///   Propagates reflection/transmission blocks through the lower boundary so
///   the composed state preserves the vendor scalar and Fourier behavior.
///
/// Vendor:
///   `adding::addLayerToBottom`
pub fn addLayerToBottom(
    i_fourier: usize,
    etop: *const labos.Vec,
    top: *const PartAtmosphere,
    ebot: *const labos.Vec,
    bottom: *const labos.LayerRT,
    geo: *const labos.Geometry,
    threshold_mul: f64,
) common.ExecuteError!PartAtmosphere {
    const n = geo.nmutot;
    const n_gauss = geo.n_gauss;
    const qst = labos.qseries(n, n_gauss, threshold_mul, &bottom.R, &top.Rst);
    const dst = labos.matAdd(
        n,
        &bottom.T,
        &labos.matAdd(
            n,
            &labos.semul(n, &qst, ebot),
            &labos.smul(n, n_gauss, threshold_mul, &qst, &bottom.T),
        ),
    );
    const ust = labos.matAdd(
        n,
        &labos.semul(n, &top.Rst, ebot),
        &labos.smul(n, n_gauss, threshold_mul, &top.Rst, &dst),
    );
    const rst = labos.matAdd(
        n,
        &bottom.R,
        &labos.matAdd(
            n,
            &labos.esmul(n, ebot, &ust),
            &labos.smul(n, n_gauss, threshold_mul, &bottom.T, &ust),
        ),
    );
    const tst = labos.matAdd(
        n,
        &labos.esmul(n, etop, &dst),
        &labos.matAdd(
            n,
            &labos.semul(n, &top.Tst, ebot),
            &labos.smul(n, n_gauss, threshold_mul, &top.Tst, &dst),
        ),
    );
    const q = transposeMat(&qst);
    const d = labos.matAdd(
        n,
        &top.T,
        &labos.matAdd(
            n,
            &labos.semul(n, &q, etop),
            &labos.smul(n, n_gauss, threshold_mul, &q, &top.T),
        ),
    );
    const u = labos.matAdd(
        n,
        &labos.semul(n, &bottom.R, etop),
        &labos.smul(n, n_gauss, threshold_mul, &bottom.R, &d),
    );
    const r = labos.matAdd(
        n,
        &top.R,
        &labos.matAdd(
            n,
            &labos.esmul(n, etop, &u),
            &labos.smul(n, n_gauss, threshold_mul, &top.Tst, &u),
        ),
    );
    const t = labos.matAdd(
        n,
        &labos.esmul(n, ebot, &d),
        &labos.matAdd(
            n,
            &labos.semul(n, &bottom.T, etop),
            &labos.smul(n, n_gauss, threshold_mul, &bottom.T, &d),
        ),
    );
    const tpl = vendorIntegratedDiffuseTransmission(i_fourier, &t, ebot, etop, geo);

    return .{
        .R = r,
        .T = t,
        .Rst = rst,
        .Tst = tst,
        .U = u,
        .D = d,
        .Ust = ust,
        .Dst = dst,
        .tpl = tpl,
        .tplst = labos.Vec.zero(n),
        .s = vendorSphericalAlbedo(i_fourier, &r, geo),
        .sst = vendorSphericalAlbedo(i_fourier, &rst, geo),
    };
}

/// Purpose:
///   Combine the top layer with the atmosphere below it using the adding
///   recurrence.
///
/// Physics:
///   Propagates reflection/transmission blocks through the upper boundary so
///   the composed state preserves the vendor scalar and Fourier behavior.
///
/// Vendor:
///   `adding::addLayerToTop`
pub fn addLayerToTop(
    i_fourier: usize,
    etop: *const labos.Vec,
    ebot: *const labos.Vec,
    top: *const labos.LayerRT,
    bottom: *const PartAtmosphere,
    geo: *const labos.Geometry,
    threshold_mul: f64,
) common.ExecuteError!PartAtmosphere {
    const n = geo.nmutot;
    const n_gauss = geo.n_gauss;
    const q = labos.qseries(n, n_gauss, threshold_mul, &top.R, &bottom.R);
    const d = labos.matAdd(
        n,
        &top.T,
        &labos.matAdd(
            n,
            &labos.semul(n, &q, etop),
            &labos.smul(n, n_gauss, threshold_mul, &q, &top.T),
        ),
    );
    const u = labos.matAdd(
        n,
        &labos.semul(n, &bottom.R, etop),
        &labos.smul(n, n_gauss, threshold_mul, &bottom.R, &d),
    );
    const r = labos.matAdd(
        n,
        &top.R,
        &labos.matAdd(
            n,
            &labos.esmul(n, etop, &u),
            &labos.smul(n, n_gauss, threshold_mul, &top.T, &u),
        ),
    );
    const t = labos.matAdd(
        n,
        &labos.esmul(n, ebot, &d),
        &labos.matAdd(
            n,
            &labos.semul(n, &bottom.T, etop),
            &labos.smul(n, n_gauss, threshold_mul, &bottom.T, &d),
        ),
    );
    const tpl = vendorIntegratedDiffuseTransmission(i_fourier, &t, ebot, etop, geo);

    return .{
        .R = r,
        .T = t,
        .Rst = r,
        .Tst = t,
        .U = u,
        .D = d,
        .Ust = labos.Mat.zero(n),
        .Dst = labos.Mat.zero(n),
        .tpl = tpl,
        .tplst = labos.Vec.zero(n),
        .s = vendorSphericalAlbedo(i_fourier, &r, geo),
        .sst = 0.0,
    };
}

fn transposeMat(input: *const labos.Mat) labos.Mat {
    var result = labos.Mat.zero(input.n);
    for (0..input.n) |j| {
        for (0..input.n) |i| {
            result.set(i, j, input.get(j, i));
        }
    }
    return result;
}

fn vendorSphericalAlbedo(
    i_fourier: usize,
    reflectance: *const labos.Mat,
    geo: *const labos.Geometry,
) f64 {
    if (i_fourier != 0) return 0.0;

    var total: f64 = 0.0;
    for (0..geo.n_gauss) |imu| {
        for (0..geo.n_gauss) |imu0| {
            total += geo.w[imu] * geo.w[imu0] * reflectance.get(imu, imu0);
        }
    }
    return total;
}

fn vendorIntegratedDiffuseTransmission(
    i_fourier: usize,
    transmission: *const labos.Mat,
    ebot: *const labos.Vec,
    etop: *const labos.Vec,
    geo: *const labos.Geometry,
) labos.Vec {
    var tpl = labos.Vec.zero(geo.nmutot);
    if (i_fourier != 0) return tpl;

    for (0..geo.nmutot) |imu| {
        var total: f64 = 0.0;
        for (0..geo.n_gauss) |imu0| {
            total += geo.w[imu0] * transmission.get(imu, imu0);
        }
        tpl.set(
            imu,
            total / @max(geo.w[imu], 1.0e-12) + ebot.get(imu) * etop.get(imu),
        );
    }
    return tpl;
}

/// Purpose:
///   Materialize the top-down recursive composition state for every level.
///
/// Physics:
///   Walks the atmosphere from the top boundary downward, combining each
///   layer into the partially composed state used by the adding method.
///
/// Vendor:
///   `adding::addingFromTopDown`
pub fn addingFromTopDown(
    part_upper: []PartAtmosphere,
    end_level: usize,
    i_fourier: usize,
    atten: *const labos.DynamicAttenArray,
    rt: []const labos.LayerRT,
    geo: *const labos.Geometry,
    threshold_mul: f64,
) common.ExecuteError!void {
    const n = geo.nmutot;
    part_upper[end_level] = .{
        .R = rt[end_level].R,
        .T = rt[end_level].T,
        .Rst = rt[end_level].R,
        .Tst = rt[end_level].T,
        .U = rt[end_level].R,
        .D = labos.Mat.zero(n),
        .Ust = labos.Mat.zero(n),
        .Dst = rt[end_level].T,
        .tpl = labos.Vec.zero(n),
        .tplst = labos.Vec.zero(n),
        .s = 0.0,
        .sst = 0.0,
    };

    var ilevel = end_level;
    while (ilevel > 0) {
        ilevel -= 1;
        var etop = labos.Vec.zero(n);
        var ebot = labos.Vec.zero(n);
        for (0..n) |imu| {
            etop.set(imu, atten.get(imu, end_level, ilevel));
            if (ilevel != 0) {
                ebot.set(imu, atten.get(imu, ilevel, ilevel - 1));
            }
        }
        part_upper[ilevel] = try addLayerToBottom(
            i_fourier,
            &etop,
            &part_upper[ilevel + 1],
            &ebot,
            &rt[ilevel],
            geo,
            threshold_mul,
        );
    }
}

/// Purpose:
///   Materialize the surface-up recursive composition state for every level.
///
/// Physics:
///   Walks the atmosphere from the lower boundary upward, combining each
///   layer into the partially composed state used by the adding method.
///
/// Vendor:
///   `adding::addingFromSurfaceUp`
pub fn addingFromSurfaceUp(
    part_lower: []PartAtmosphere,
    end_level: usize,
    i_fourier: usize,
    atten: *const labos.DynamicAttenArray,
    rt: []const labos.LayerRT,
    geo: *const labos.Geometry,
    threshold_mul: f64,
) common.ExecuteError!void {
    const n = geo.nmutot;
    part_lower[0] = .{
        .R = rt[0].R,
        .T = rt[0].T,
        .Rst = rt[0].R,
        .Tst = rt[0].T,
        .U = rt[0].R,
        .D = labos.Mat.zero(n),
        .Ust = labos.Mat.zero(n),
        .Dst = labos.Mat.zero(n),
        .tpl = labos.Vec.zero(n),
        .tplst = labos.Vec.zero(n),
        .s = 0.0,
        .sst = 0.0,
    };

    for (1..end_level + 1) |ilevel| {
        var etop = labos.Vec.zero(n);
        var ebot = labos.Vec.zero(n);
        for (0..n) |imu| {
            etop.set(imu, atten.get(imu, ilevel, ilevel - 1));
            ebot.set(imu, atten.get(imu, ilevel - 1, 0));
        }
        part_lower[ilevel] = try addLayerToTop(
            i_fourier,
            &etop,
            &ebot,
            &rt[ilevel],
            &part_lower[ilevel - 1],
            geo,
            threshold_mul,
        );
    }
}
