const std = @import("std");
const common = @import("common.zig");
const derivatives = @import("derivatives.zig");
const labos = @import("labos.zig");
const Allocator = std.mem.Allocator;

const ReflectanceComponents = struct {
    toa_reflectance_factor: f64,
    surface_term: f64,
    scattering_term: f64,
};

const PartAtmosphere = struct {
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

    fn zero(n: usize) PartAtmosphere {
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

const TopDownField = struct {
    ud: []labos.UDField,
    ud_sum_local: []labos.UDLocal,

    fn deinit(self: TopDownField, allocator: Allocator) void {
        allocator.free(self.ud);
        allocator.free(self.ud_sum_local);
    }
};

const BoundarySurfaceDiagnostics = struct {
    r0: labos.Mat,
    td: labos.Vec,
    expt: labos.Vec,
    s_star: f64,
};

pub fn execute(
    allocator: Allocator,
    route: common.Route,
    input: common.ForwardInput,
) common.ExecuteError!common.ForwardResult {
    if (route.family != .adding) unreachable;
    if (route.derivative_mode == .analytical_plugin) {
        return common.Error.UnsupportedDerivativeMode;
    }

    const controls = route.rtm_controls;
    const components = if (controls.scattering == .none)
        try directSurfaceOnlyReflectance(allocator, input, controls)
    else
        try layerResolvedReflectance(allocator, input, controls);

    return .{
        .family = route.family,
        .regime = route.regime,
        .execution_mode = route.execution_mode,
        .derivative_mode = route.derivative_mode,
        .toa_reflectance_factor = components.toa_reflectance_factor,
        .jacobian_column = switch (route.derivative_mode) {
            .none => null,
            .semi_analytical => derivatives.proxyOpticalDepthSensitivity(
                components.surface_term,
                components.scattering_term,
                (1.0 / input.mu0) + (1.0 / input.muv),
                0.5 * ((1.0 / input.mu0) + (1.0 / input.muv)),
            ),
            .analytical_plugin => null,
            .numerical => derivatives.proxyOpticalDepthSensitivity(
                components.surface_term,
                components.scattering_term,
                (1.0 / input.mu0) + (1.0 / input.muv),
                0.5 * ((1.0 / input.mu0) + (1.0 / input.muv)),
            ),
        },
    };
}

fn bulkDirectSurfaceOnlyReflectance(input: common.ForwardInput) ReflectanceComponents {
    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const surface_term = input.surface_albedo *
        std.math.exp(-input.optical_depth / mu0) *
        std.math.exp(-input.optical_depth / muv);
    return .{
        .toa_reflectance_factor = std.math.clamp(surface_term, 0.0, 1.5),
        .surface_term = surface_term,
        .scattering_term = 0.0,
    };
}

fn lambertianSurfaceReflectanceFromAttenuation(
    surface_albedo: f64,
    end_level: usize,
    geo: *const labos.Geometry,
    atten: anytype,
) ReflectanceComponents {
    const view_idx = geo.viewIdx();
    const solar_idx = geo.n_gauss + 1;
    const surface = labos.fillSurface(0, surface_albedo, geo);
    var upward_path: f64 = 1.0;
    for (1..end_level + 1) |ilevel| {
        upward_path *= atten.get(view_idx, ilevel - 1, ilevel);
    }
    const surface_term =
        surface.R.get(view_idx, solar_idx) *
        atten.get(solar_idx, end_level, 0) *
        upward_path;
    return .{
        .toa_reflectance_factor = std.math.clamp(surface_term, 0.0, 1.5),
        .surface_term = surface_term,
        .scattering_term = 0.0,
    };
}

fn directSurfaceOnlyReflectance(
    allocator: Allocator,
    input: common.ForwardInput,
    controls: common.RtmControls,
) common.ExecuteError!ReflectanceComponents {
    if (input.layers.len == 0) return bulkDirectSurfaceOnlyReflectance(input);

    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const geo = labos.Geometry.init(controls.nGauss(), mu0, muv);
    var atten = try labos.fillAttenuationDynamicWithGrid(
        allocator,
        input.layers,
        input.pseudo_spherical_grid,
        &geo,
        controls.use_spherical_correction,
    );
    defer atten.deinit();
    return lambertianSurfaceReflectanceFromAttenuation(
        input.surface_albedo,
        input.layers.len,
        &geo,
        &atten,
    );
}

fn layerResolvedReflectance(
    allocator: Allocator,
    input: common.ForwardInput,
    controls: common.RtmControls,
) common.ExecuteError!ReflectanceComponents {
    const layers = input.layers;
    if (layers.len == 0) {
        return error.UnsupportedRtmControls;
    }

    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const geo = labos.Geometry.init(controls.nGauss(), mu0, muv);
    const end_level = layers.len;
    const nlevel = end_level + 1;
    const fourier_max = labos.resolvedFourierMax(input, controls);
    const use_integrated_source = controls.integrate_source_function and layers.len > 1;
    var atten = try labos.fillAttenuationDynamicWithGrid(
        allocator,
        layers,
        input.pseudo_spherical_grid,
        &geo,
        controls.use_spherical_correction,
    );
    defer atten.deinit();
    var rt = try allocator.alloc(labos.LayerRT, nlevel);
    defer allocator.free(rt);

    var total: f64 = 0.0;
    for (0..fourier_max + 1) |i_fourier| {
        labos.calcRTlayersInto(rt, layers, i_fourier, &geo, controls);
        rt[0] = labos.fillSurface(i_fourier, input.surface_albedo, &geo);
        const refl_fc = if (controls.use_spherical_correction) blk: {
            const top_down = try calcTopDownField(
                allocator,
                end_level,
                i_fourier,
                &atten,
                rt,
                &geo,
                controls.threshold_mul,
            );
            defer top_down.deinit(allocator);
            break :blk if (use_integrated_source)
                labos.calcIntegratedReflectance(
                    layers,
                    input.source_interfaces,
                    input.rtm_quadrature,
                    top_down.ud,
                    end_level,
                    i_fourier,
                    &geo,
                )
            else
                labos.calcReflectance(top_down.ud, end_level, &geo);
        } else blk: {
            const ud = try calcSurfaceUpField(
                allocator,
                end_level,
                i_fourier,
                &atten,
                rt,
                &geo,
                controls.threshold_mul,
            );
            defer allocator.free(ud);
            break :blk if (use_integrated_source)
                labos.calcIntegratedReflectance(
                    layers,
                    input.source_interfaces,
                    input.rtm_quadrature,
                    ud,
                    end_level,
                    i_fourier,
                    &geo,
                )
            else
                labos.calcReflectance(ud, end_level, &geo);
        };
        const fourier_weight = if (i_fourier == 0)
            1.0
        else
            2.0 * std.math.cos(@as(f64, @floatFromInt(i_fourier)) * input.relative_azimuth_rad);
        total += fourier_weight * refl_fc;
    }

    total = std.math.clamp(total, 0.0, 2.0);
    const direct_surface = bulkDirectSurfaceOnlyReflectance(input).toa_reflectance_factor;
    const surface_term = @min(total, direct_surface);

    return .{
        .toa_reflectance_factor = total,
        .surface_term = surface_term,
        .scattering_term = @max(total - surface_term, 0.0),
    };
}

fn calcTopDownField(
    allocator: Allocator,
    end_level: usize,
    i_fourier: usize,
    atten: *const labos.DynamicAttenArray,
    rt: []const labos.LayerRT,
    geo: *const labos.Geometry,
    threshold_mul: f64,
) common.ExecuteError!TopDownField {
    const part_upper = try buildTopDownPartAtmosphere(
        allocator,
        end_level,
        i_fourier,
        atten,
        rt,
        geo,
        threshold_mul,
    );
    defer allocator.free(part_upper);

    const nlevel = end_level + 1;
    const ud = try allocator.alloc(labos.UDField, nlevel);
    errdefer allocator.free(ud);
    const ud_sum_local = try allocator.alloc(labos.UDLocal, nlevel);
    errdefer allocator.free(ud_sum_local);

    calcUD_FromTopDown(ud, part_upper, end_level, atten, geo);
    calcUDsumLocal(ud_sum_local, rt, ud, end_level, atten, geo);
    return .{
        .ud = ud,
        .ud_sum_local = ud_sum_local,
    };
}

fn calcSurfaceUpField(
    allocator: Allocator,
    end_level: usize,
    i_fourier: usize,
    atten: *const labos.DynamicAttenArray,
    rt: []const labos.LayerRT,
    geo: *const labos.Geometry,
    threshold_mul: f64,
) common.ExecuteError![]labos.UDField {
    const nlevel = end_level + 1;
    const part_lower = try allocator.alloc(PartAtmosphere, nlevel);
    defer allocator.free(part_lower);
    for (part_lower) |*entry| entry.* = PartAtmosphere.zero(geo.nmutot);

    const ud = try allocator.alloc(labos.UDField, nlevel);
    errdefer allocator.free(ud);

    try addingFromSurfaceUp(part_lower, end_level, i_fourier, atten, rt, geo, threshold_mul);
    calcUD_FromSurfaceUp(ud, part_lower, end_level, atten, geo);
    return ud;
}

fn buildTopDownPartAtmosphere(
    allocator: Allocator,
    end_level: usize,
    i_fourier: usize,
    atten: *const labos.DynamicAttenArray,
    rt: []const labos.LayerRT,
    geo: *const labos.Geometry,
    threshold_mul: f64,
) common.ExecuteError![]PartAtmosphere {
    const nlevel = end_level + 1;
    const part_upper = try allocator.alloc(PartAtmosphere, nlevel);
    errdefer allocator.free(part_upper);
    for (part_upper) |*entry| entry.* = PartAtmosphere.zero(geo.nmutot);
    try addingFromTopDown(part_upper, end_level, i_fourier, atten, rt, geo, threshold_mul);
    return part_upper;
}

pub fn calcTopDownBoundarySurfaceDiagnostics(
    allocator: Allocator,
    level: usize,
    end_level: usize,
    i_fourier: usize,
    atten: *const labos.DynamicAttenArray,
    rt: []const labos.LayerRT,
    geo: *const labos.Geometry,
    threshold_mul: f64,
) common.ExecuteError!BoundarySurfaceDiagnostics {
    if (level > end_level) return error.UnsupportedRtmControls;

    const part_upper = try buildTopDownPartAtmosphere(
        allocator,
        end_level,
        i_fourier,
        atten,
        rt,
        geo,
        threshold_mul,
    );
    defer allocator.free(part_upper);

    var r0 = labos.Mat.zero(geo.nmutot);
    for (0..geo.nmutot) |imu| {
        for (0..geo.nmutot) |imu0| {
            r0.set(
                imu,
                imu0,
                part_upper[level].R.get(imu, imu0) / @max(geo.w[imu] * geo.w[imu0], 1.0e-12),
            );
        }
    }

    var td = labos.Vec.zero(geo.nmutot);
    var expt = labos.Vec.zero(geo.nmutot);
    var s_star: f64 = 0.0;
    if (i_fourier == 0) {
        td = part_upper[level].tpl;
        s_star = part_upper[level].sst;
        for (0..geo.nmutot) |imu| {
            expt.set(imu, atten.get(imu, end_level, level));
        }
    }

    return .{
        .r0 = r0,
        .td = td,
        .expt = expt,
        .s_star = s_star,
    };
}

fn addingFromTopDown(
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

fn addingFromSurfaceUp(
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

fn calcUD_FromTopDown(
    ud: []labos.UDField,
    part_upper: []const PartAtmosphere,
    end_level: usize,
    atten: *const labos.DynamicAttenArray,
    geo: *const labos.Geometry,
) void {
    const n = geo.nmutot;
    for (0..end_level + 1) |ilevel| {
        ud[ilevel] = .{
            .E = labos.Vec.zero(n),
            .U = labos.Vec2.zero(n),
            .D = labos.Vec2.zero(n),
        };
        for (0..n) |imu| {
            ud[ilevel].E.set(imu, atten.get(imu, end_level, ilevel));
        }
    }

    for (0..2) |imu0| {
        const col_idx = geo.n_gauss + imu0;
        for (0..n) |imu| {
            ud[0].D.col[imu0].set(imu, part_upper[0].D.get(imu, col_idx));
            ud[0].U.col[imu0].set(imu, part_upper[0].U.get(imu, col_idx));
        }
    }

    for (1..end_level + 1) |ilevel| {
        for (0..2) |imu0| {
            const col_idx = geo.n_gauss + imu0;
            for (0..n) |imu| {
                const down = labos.dotGauss(&part_upper[ilevel].Ust, imu, &ud[ilevel - 1].U.col[imu0], geo.n_gauss) +
                    part_upper[ilevel].D.get(imu, col_idx);
                const up = labos.dotGauss(&part_upper[ilevel].Dst, imu, &ud[ilevel - 1].U.col[imu0], geo.n_gauss) +
                    atten.get(imu, ilevel - 1, ilevel) * ud[ilevel - 1].U.col[imu0].get(imu) +
                    part_upper[ilevel].U.get(imu, col_idx);
                ud[ilevel].D.col[imu0].set(imu, down);
                ud[ilevel].U.col[imu0].set(imu, up);
            }
        }
    }
}

fn calcUDsumLocal(
    ud_sum_local: []labos.UDLocal,
    rt: []const labos.LayerRT,
    ud: []const labos.UDField,
    end_level: usize,
    atten: *const labos.DynamicAttenArray,
    geo: *const labos.Geometry,
) void {
    const n = geo.nmutot;
    for (0..end_level + 1) |ilevel| {
        ud_sum_local[ilevel] = .{
            .U = labos.Vec2.zero(n),
            .D = labos.Vec2.zero(n),
        };
    }

    ud_sum_local[0].U = ud[0].U;

    for (1..end_level + 1) |ilevel| {
        for (0..2) |imu0| {
            const col_idx = geo.n_gauss + imu0;
            for (0..n) |imu| {
                const local_up =
                    labos.dotGauss(&rt[ilevel].R, imu, &ud[ilevel].D.col[imu0], geo.n_gauss) +
                    labos.dotGauss(&rt[ilevel].T, imu, &ud[ilevel - 1].U.col[imu0], geo.n_gauss) +
                    rt[ilevel].R.get(imu, col_idx) * atten.get(col_idx, end_level, ilevel);
                ud_sum_local[ilevel].U.col[imu0].set(imu, local_up);
            }
        }
    }
}

fn calcUD_FromSurfaceUp(
    ud: []labos.UDField,
    part_lower: []const PartAtmosphere,
    end_level: usize,
    atten: *const labos.DynamicAttenArray,
    geo: *const labos.Geometry,
) void {
    const n = geo.nmutot;
    for (0..end_level + 1) |ilevel| {
        ud[ilevel] = .{
            .E = labos.Vec.zero(n),
            .U = labos.Vec2.zero(n),
            .D = labos.Vec2.zero(n),
        };
        for (0..n) |imu| {
            ud[ilevel].E.set(imu, atten.get(imu, end_level, ilevel));
        }
    }

    for (0..n) |imu| {
        ud[end_level].E.set(imu, 1.0);
    }
    ud[end_level].D = labos.Vec2.zero(n);
    for (0..2) |imu0| {
        const col_idx = geo.n_gauss + imu0;
        for (0..n) |imu| {
            ud[end_level].U.col[imu0].set(imu, part_lower[end_level].R.get(imu, col_idx));
        }
    }

    var ilevel = end_level;
    while (ilevel > 0) {
        ilevel -= 1;
        for (0..2) |imu0| {
            const col_idx = geo.n_gauss + imu0;
            const direct_att = atten.get(col_idx, end_level, ilevel + 1);
            for (0..n) |imu| {
                const down = labos.dotGauss(&part_lower[ilevel + 1].D, imu, &ud[ilevel + 1].D.col[imu0], geo.n_gauss) +
                    atten.get(imu, ilevel, ilevel + 1) * ud[ilevel + 1].D.col[imu0].get(imu) +
                    part_lower[ilevel + 1].D.get(imu, col_idx) * direct_att;
                const up = labos.dotGauss(&part_lower[ilevel + 1].U, imu, &ud[ilevel + 1].D.col[imu0], geo.n_gauss) +
                    part_lower[ilevel + 1].U.get(imu, col_idx) * direct_att;
                ud[ilevel].D.col[imu0].set(imu, down);
                ud[ilevel].U.col[imu0].set(imu, up);
            }
        }
    }
}

fn addLayerToBottom(
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

fn addLayerToTop(
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

test "adding execution returns deterministic scalar output" {
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{ .use_adding = true },
    });
    const layers = [_]common.LayerInput{.{
        .optical_depth = 0.42,
        .scattering_optical_depth = 0.34,
        .single_scatter_albedo = 0.81,
        .solar_mu = 0.74,
        .view_mu = 0.63,
        .phase_coefficients = .{ 1.0, 0.2, 0.05, 0.0 },
    }};
    const result = try execute(std.testing.allocator, route, .{
        .spectral_weight = 1.2,
        .air_mass_factor = 0.8,
        .mu0 = 0.74,
        .muv = 0.63,
        .optical_depth = 0.42,
        .single_scatter_albedo = 0.81,
        .layers = &layers,
    });

    try std.testing.expectEqual(common.TransportFamily.adding, result.family);
    try std.testing.expect(result.toa_reflectance_factor > 0.0);
    try std.testing.expectEqual(@as(?f64, null), result.jacobian_column);
}

test "adding rejects multiple-scattering execution without explicit layers" {
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{ .use_adding = true },
    });

    try std.testing.expectError(error.UnsupportedRtmControls, execute(std.testing.allocator, route, .{
        .spectral_weight = 1.2,
        .air_mass_factor = 0.8,
    }));
}

test "adding anisotropic layers respond to relative azimuth once Fourier terms are enabled" {
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 6,
        },
    });
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.31,
            .scattering_optical_depth = 0.26,
            .single_scatter_albedo = 0.92,
            .solar_mu = 0.58,
            .view_mu = 0.64,
            .phase_coefficients = .{ 1.0, 0.52, 0.21, 0.07 },
        },
        .{
            .optical_depth = 0.19,
            .scattering_optical_depth = 0.15,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.61,
            .view_mu = 0.67,
            .phase_coefficients = .{ 1.0, 0.38, 0.14, 0.04 },
        },
    };

    const result_zero = try execute(std.testing.allocator, route, .{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.50,
        .single_scatter_albedo = 0.91,
        .surface_albedo = 0.12,
        .layers = &layers,
    });
    const result_oblique = try execute(std.testing.allocator, route, .{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.50,
        .single_scatter_albedo = 0.91,
        .surface_albedo = 0.12,
        .relative_azimuth_rad = std.math.degreesToRadians(120.0),
        .layers = &layers,
    });

    try std.testing.expect(@abs(result_zero.toa_reflectance_factor - result_oblique.toa_reflectance_factor) > 1.0e-5);
}

test "adding no-scattering layered path responds to per-layer solar geometry" {
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .scattering = .none,
            .use_spherical_correction = true,
        },
    });
    const baseline_layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.24,
            .scattering_optical_depth = 0.0,
            .single_scatter_albedo = 0.0,
            .solar_mu = 0.41,
            .view_mu = 0.54,
            .phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
        },
        .{
            .optical_depth = 0.16,
            .scattering_optical_depth = 0.0,
            .single_scatter_albedo = 0.0,
            .solar_mu = 0.52,
            .view_mu = 0.60,
            .phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
        },
    };
    var altered_layers = baseline_layers;
    altered_layers[0].solar_mu = 0.33;
    altered_layers[1].solar_mu = 0.68;

    const baseline = try execute(std.testing.allocator, route, .{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.40,
        .single_scatter_albedo = 0.0,
        .surface_albedo = 0.10,
        .layers = &baseline_layers,
    });
    const altered = try execute(std.testing.allocator, route, .{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.40,
        .single_scatter_albedo = 0.0,
        .surface_albedo = 0.10,
        .layers = &altered_layers,
    });

    try std.testing.expect(@abs(
        baseline.toa_reflectance_factor - altered.toa_reflectance_factor,
    ) > 1.0e-5);
}

test "adding no-scattering layered path matches Lambertian attenuation identity" {
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .scattering = .none,
            .n_streams = 8,
            .use_spherical_correction = true,
        },
    });
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.21,
            .scattering_optical_depth = 0.0,
            .single_scatter_albedo = 0.0,
            .solar_mu = 0.39,
            .view_mu = 0.51,
            .phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
        },
        .{
            .optical_depth = 0.11,
            .scattering_optical_depth = 0.0,
            .single_scatter_albedo = 0.0,
            .solar_mu = 0.47,
            .view_mu = 0.58,
            .phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
        },
    };
    const input = common.ForwardInput{
        .mu0 = 0.57,
        .muv = 0.64,
        .optical_depth = 0.32,
        .single_scatter_albedo = 0.0,
        .surface_albedo = 0.18,
        .layers = &layers,
    };

    const result = try execute(std.testing.allocator, route, input);

    const geo = labos.Geometry.init(route.rtm_controls.nGauss(), input.mu0, input.muv);
    var atten = try labos.fillAttenuationDynamic(std.testing.allocator, &layers, &geo, true);
    defer atten.deinit();
    const view_idx = geo.viewIdx();
    const solar_idx = geo.n_gauss + 1;
    const surface = labos.fillSurface(0, input.surface_albedo, &geo);
    var upward_path: f64 = 1.0;
    for (1..layers.len + 1) |ilevel| {
        upward_path *= atten.get(view_idx, ilevel - 1, ilevel);
    }
    const expected = std.math.clamp(
        surface.R.get(view_idx, solar_idx) *
            atten.get(solar_idx, layers.len, 0) *
            upward_path,
        0.0,
        1.5,
    );

    try std.testing.expectApproxEqAbs(expected, result.toa_reflectance_factor, 1.0e-12);
}

test "adding raw-layer integrated source-function fallback stays close to direct TOA extraction" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.28,
            .scattering_optical_depth = 0.22,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.58,
            .view_mu = 0.64,
            .phase_coefficients = .{ 1.0, 0.35, 0.12, 0.03 },
        },
        .{
            .optical_depth = 0.17,
            .scattering_optical_depth = 0.13,
            .single_scatter_albedo = 0.88,
            .solar_mu = 0.61,
            .view_mu = 0.67,
            .phase_coefficients = .{ 1.0, 0.24, 0.09, 0.02 },
        },
    };

    const route_integrated = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = true,
        },
    });
    const route_direct = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = false,
        },
    });

    const forward_input = common.ForwardInput{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.45,
        .single_scatter_albedo = 0.89,
        .surface_albedo = 0.10,
        .relative_azimuth_rad = std.math.degreesToRadians(75.0),
        .layers = &layers,
    };
    const result_integrated = try execute(std.testing.allocator, route_integrated, forward_input);
    const result_direct = try execute(std.testing.allocator, route_direct, forward_input);

    try std.testing.expectApproxEqRel(
        result_direct.toa_reflectance_factor,
        result_integrated.toa_reflectance_factor,
        6.0e-3,
    );
}

test "adding single-layer integrated source-function falls back to direct TOA extraction" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.31,
            .scattering_optical_depth = 0.24,
            .single_scatter_albedo = 0.91,
            .solar_mu = 0.59,
            .view_mu = 0.65,
            .phase_coefficients = .{ 1.0, 0.28, 0.07, 0.01 },
        },
    };

    const route_integrated = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = true,
        },
    });
    const route_direct = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = false,
        },
    });

    const forward_input = common.ForwardInput{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.31,
        .single_scatter_albedo = 0.91,
        .surface_albedo = 0.10,
        .relative_azimuth_rad = std.math.degreesToRadians(70.0),
        .layers = &layers,
    };
    const result_integrated = try execute(std.testing.allocator, route_integrated, forward_input);
    const result_direct = try execute(std.testing.allocator, route_direct, forward_input);

    try std.testing.expectApproxEqRel(
        result_direct.toa_reflectance_factor,
        result_integrated.toa_reflectance_factor,
        1.0e-12,
    );
}

test "adding top-down spherical path computes vendor-style local upward field sums" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.24,
            .scattering_optical_depth = 0.18,
            .single_scatter_albedo = 0.88,
            .solar_mu = 0.42,
            .view_mu = 0.54,
            .phase_coefficients = .{ 1.0, 0.31, 0.10, 0.02 },
        },
        .{
            .optical_depth = 0.16,
            .scattering_optical_depth = 0.12,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.48,
            .view_mu = 0.60,
            .phase_coefficients = .{ 1.0, 0.26, 0.08, 0.02 },
        },
    };
    const controls = common.RtmControls{
        .use_adding = true,
        .n_streams = 8,
        .num_orders_max = 6,
        .use_spherical_correction = true,
    };
    const geo = labos.Geometry.init(controls.nGauss(), 0.60, 0.66);
    var atten = try labos.fillAttenuationDynamic(std.testing.allocator, &layers, &geo, true);
    defer atten.deinit();
    var rt: [3]labos.LayerRT = undefined;
    labos.calcRTlayersInto(&rt, &layers, 0, &geo, controls);
    rt[0] = labos.fillSurface(0, 0.10, &geo);

    const top_down = try calcTopDownField(
        std.testing.allocator,
        layers.len,
        0,
        &atten,
        &rt,
        &geo,
        controls.threshold_mul,
    );
    defer top_down.deinit(std.testing.allocator);

    try std.testing.expectEqual(top_down.ud[0].U.col[0].get(0), top_down.ud_sum_local[0].U.col[0].get(0));
    for (1..layers.len + 1) |ilevel| {
        for (0..2) |imu0| {
            const col_idx = geo.n_gauss + imu0;
            for (0..geo.nmutot) |imu| {
                const expected =
                    labos.dotGauss(&rt[ilevel].R, imu, &top_down.ud[ilevel].D.col[imu0], geo.n_gauss) +
                    labos.dotGauss(&rt[ilevel].T, imu, &top_down.ud[ilevel - 1].U.col[imu0], geo.n_gauss) +
                    rt[ilevel].R.get(imu, col_idx) * atten.get(col_idx, layers.len, ilevel);
                try std.testing.expectApproxEqAbs(
                    expected,
                    top_down.ud_sum_local[ilevel].U.col[imu0].get(imu),
                    1.0e-10,
                );
                try std.testing.expectApproxEqAbs(
                    @as(f64, 0.0),
                    top_down.ud_sum_local[ilevel].D.col[imu0].get(imu),
                    1.0e-12,
                );
            }
        }
    }
}

test "adding top-down boundary diagnostics expose vendor black-surface quantities for Fourier-0" {
    const controls = common.RtmControls{
        .use_adding = true,
        .n_streams = 8,
        .num_orders_max = 6,
        .use_spherical_correction = true,
    };
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.24,
            .scattering_optical_depth = 0.18,
            .single_scatter_albedo = 0.88,
            .solar_mu = 0.42,
            .view_mu = 0.54,
            .phase_coefficients = .{ 1.0, 0.31, 0.10, 0.02 },
        },
        .{
            .optical_depth = 0.16,
            .scattering_optical_depth = 0.12,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.48,
            .view_mu = 0.60,
            .phase_coefficients = .{ 1.0, 0.26, 0.08, 0.02 },
        },
    };
    const geo = labos.Geometry.init(controls.nGauss(), 0.60, 0.66);
    var atten = try labos.fillAttenuationDynamic(std.testing.allocator, &layers, &geo, true);
    defer atten.deinit();
    var rt: [3]labos.LayerRT = undefined;
    labos.calcRTlayersInto(&rt, &layers, 0, &geo, controls);
    rt[0] = labos.fillSurface(0, 0.10, &geo);

    const level: usize = 1;
    const diagnostics = try calcTopDownBoundarySurfaceDiagnostics(
        std.testing.allocator,
        level,
        layers.len,
        0,
        &atten,
        &rt,
        &geo,
        controls.threshold_mul,
    );

    const part_upper = try buildTopDownPartAtmosphere(
        std.testing.allocator,
        layers.len,
        0,
        &atten,
        &rt,
        &geo,
        controls.threshold_mul,
    );
    defer std.testing.allocator.free(part_upper);

    try std.testing.expectApproxEqAbs(part_upper[level].sst, diagnostics.s_star, 1.0e-12);
    for (0..geo.nmutot) |imu| {
        try std.testing.expectApproxEqAbs(part_upper[level].tpl.get(imu), diagnostics.td.get(imu), 1.0e-12);
        try std.testing.expectApproxEqAbs(atten.get(imu, layers.len, level), diagnostics.expt.get(imu), 1.0e-12);
        for (0..geo.nmutot) |imu0| {
            const expected_r0 = part_upper[level].R.get(imu, imu0) /
                @max(geo.w[imu] * geo.w[imu0], 1.0e-12);
            try std.testing.expectApproxEqAbs(expected_r0, diagnostics.r0.get(imu, imu0), 1.0e-12);
        }
    }
}

test "adding top-down boundary diagnostics zero Chandrasekhar scalars for higher Fourier orders" {
    const controls = common.RtmControls{
        .use_adding = true,
        .n_streams = 8,
        .num_orders_max = 6,
        .use_spherical_correction = true,
    };
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.24,
            .scattering_optical_depth = 0.18,
            .single_scatter_albedo = 0.88,
            .solar_mu = 0.42,
            .view_mu = 0.54,
            .phase_coefficients = .{ 1.0, 0.31, 0.10, 0.02 },
        },
        .{
            .optical_depth = 0.16,
            .scattering_optical_depth = 0.12,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.48,
            .view_mu = 0.60,
            .phase_coefficients = .{ 1.0, 0.26, 0.08, 0.02 },
        },
    };
    const geo = labos.Geometry.init(controls.nGauss(), 0.60, 0.66);
    var atten = try labos.fillAttenuationDynamic(std.testing.allocator, &layers, &geo, true);
    defer atten.deinit();
    var rt: [3]labos.LayerRT = undefined;
    labos.calcRTlayersInto(&rt, &layers, 1, &geo, controls);
    rt[0] = labos.fillSurface(1, 0.10, &geo);

    const level: usize = 1;
    const diagnostics = try calcTopDownBoundarySurfaceDiagnostics(
        std.testing.allocator,
        level,
        layers.len,
        1,
        &atten,
        &rt,
        &geo,
        controls.threshold_mul,
    );

    const part_upper = try buildTopDownPartAtmosphere(
        std.testing.allocator,
        layers.len,
        1,
        &atten,
        &rt,
        &geo,
        controls.threshold_mul,
    );
    defer std.testing.allocator.free(part_upper);

    try std.testing.expectApproxEqAbs(@as(f64, 0.0), diagnostics.s_star, 1.0e-12);
    for (0..geo.nmutot) |imu| {
        try std.testing.expectApproxEqAbs(@as(f64, 0.0), diagnostics.td.get(imu), 1.0e-12);
        try std.testing.expectApproxEqAbs(@as(f64, 0.0), diagnostics.expt.get(imu), 1.0e-12);
        for (0..geo.nmutot) |imu0| {
            const expected_r0 = part_upper[level].R.get(imu, imu0) /
                @max(geo.w[imu] * geo.w[imu0], 1.0e-12);
            try std.testing.expectApproxEqAbs(expected_r0, diagnostics.r0.get(imu, imu0), 1.0e-12);
        }
    }
}

test "adding integrated source-function path uses explicit source interface metadata" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.28,
            .scattering_optical_depth = 0.22,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.58,
            .view_mu = 0.64,
            .phase_coefficients = .{ 1.0, 0.35, 0.12, 0.03 },
        },
        .{
            .optical_depth = 0.17,
            .scattering_optical_depth = 0.13,
            .single_scatter_albedo = 0.88,
            .solar_mu = 0.61,
            .view_mu = 0.67,
            .phase_coefficients = .{ 1.0, 0.24, 0.09, 0.02 },
        },
    };
    var source_interfaces: [3]common.SourceInterfaceInput = undefined;
    common.fillSourceInterfacesFromLayers(&layers, &source_interfaces);

    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = true,
        },
    });
    const route_direct = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = false,
        },
    });

    source_interfaces[1].rtm_weight = 2.0;
    source_interfaces[1].ksca_above = source_interfaces[1].source_weight / source_interfaces[1].rtm_weight;
    source_interfaces[1].source_weight = 0.0;

    const base_input = common.ForwardInput{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.45,
        .single_scatter_albedo = 0.89,
        .surface_albedo = 0.10,
        .relative_azimuth_rad = std.math.degreesToRadians(75.0),
        .layers = &layers,
        .source_interfaces = &source_interfaces,
    };
    const baseline = try execute(std.testing.allocator, route, base_input);
    const direct_baseline = try execute(std.testing.allocator, route_direct, base_input);

    var altered_interfaces = source_interfaces;
    altered_interfaces[1].ksca_above *= 1.8;
    altered_interfaces[1].phase_coefficients_above[1] = 0.60;
    const altered = try execute(std.testing.allocator, route, .{
        .mu0 = base_input.mu0,
        .muv = base_input.muv,
        .optical_depth = base_input.optical_depth,
        .single_scatter_albedo = base_input.single_scatter_albedo,
        .surface_albedo = base_input.surface_albedo,
        .relative_azimuth_rad = base_input.relative_azimuth_rad,
        .layers = &layers,
        .source_interfaces = &altered_interfaces,
    });
    const direct_altered = try execute(std.testing.allocator, route_direct, .{
        .mu0 = base_input.mu0,
        .muv = base_input.muv,
        .optical_depth = base_input.optical_depth,
        .single_scatter_albedo = base_input.single_scatter_albedo,
        .surface_albedo = base_input.surface_albedo,
        .relative_azimuth_rad = base_input.relative_azimuth_rad,
        .layers = &layers,
        .source_interfaces = &altered_interfaces,
    });

    try std.testing.expect(@abs(
        baseline.toa_reflectance_factor - altered.toa_reflectance_factor,
    ) > 1.0e-5);
    try std.testing.expectApproxEqRel(
        direct_baseline.toa_reflectance_factor,
        direct_altered.toa_reflectance_factor,
        1.0e-12,
    );
}

test "adding bottom composition populates vendor scalar integrated states for Fourier-0" {
    const controls = common.RtmControls{
        .use_adding = true,
        .n_streams = 8,
        .num_orders_max = 6,
    };
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.24,
            .scattering_optical_depth = 0.18,
            .single_scatter_albedo = 0.88,
            .solar_mu = 0.42,
            .view_mu = 0.54,
            .phase_coefficients = .{ 1.0, 0.31, 0.10, 0.02 },
        },
        .{
            .optical_depth = 0.16,
            .scattering_optical_depth = 0.12,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.48,
            .view_mu = 0.60,
            .phase_coefficients = .{ 1.0, 0.26, 0.08, 0.02 },
        },
    };
    const geo = labos.Geometry.init(controls.nGauss(), 0.60, 0.66);
    var atten = try labos.fillAttenuationDynamic(std.testing.allocator, &layers, &geo, false);
    defer atten.deinit();
    var rt: [3]labos.LayerRT = undefined;
    labos.calcRTlayersInto(&rt, &layers, 0, &geo, controls);
    rt[0] = labos.fillSurface(0, 0.10, &geo);

    var top = PartAtmosphere.zero(geo.nmutot);
    top.R = rt[2].R;
    top.T = rt[2].T;
    top.Rst = rt[2].R;
    top.Tst = rt[2].T;
    top.U = rt[2].R;
    top.Dst = rt[2].T;

    var etop = labos.Vec.zero(geo.nmutot);
    var ebot = labos.Vec.zero(geo.nmutot);
    for (0..geo.nmutot) |imu| {
        etop.set(imu, atten.get(imu, layers.len, 1));
        ebot.set(imu, atten.get(imu, 1, 0));
    }

    const combined = try addLayerToBottom(
        0,
        &etop,
        &top,
        &ebot,
        &rt[1],
        &geo,
        controls.threshold_mul,
    );

    var expected_s: f64 = 0.0;
    var expected_sst: f64 = 0.0;
    for (0..geo.n_gauss) |imu| {
        for (0..geo.n_gauss) |imu0| {
            const weight = geo.w[imu] * geo.w[imu0];
            expected_s += weight * combined.R.get(imu, imu0);
            expected_sst += weight * combined.Rst.get(imu, imu0);
        }
    }
    try std.testing.expectApproxEqAbs(expected_s, combined.s, 1.0e-12);
    try std.testing.expectApproxEqAbs(expected_sst, combined.sst, 1.0e-12);
    for (0..geo.nmutot) |imu| {
        var expected_tpl: f64 = 0.0;
        for (0..geo.n_gauss) |imu0| {
            expected_tpl += geo.w[imu0] * combined.T.get(imu, imu0);
        }
        expected_tpl = expected_tpl / geo.w[imu] + ebot.get(imu) * etop.get(imu);
        try std.testing.expectApproxEqAbs(expected_tpl, combined.tpl.get(imu), 1.0e-12);
        try std.testing.expectApproxEqAbs(@as(f64, 0.0), combined.tplst.get(imu), 1.0e-12);
    }
}

test "adding top composition populates vendor scalar integrated states for Fourier-0" {
    const controls = common.RtmControls{
        .use_adding = true,
        .n_streams = 8,
        .num_orders_max = 6,
    };
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.24,
            .scattering_optical_depth = 0.18,
            .single_scatter_albedo = 0.88,
            .solar_mu = 0.42,
            .view_mu = 0.54,
            .phase_coefficients = .{ 1.0, 0.31, 0.10, 0.02 },
        },
        .{
            .optical_depth = 0.16,
            .scattering_optical_depth = 0.12,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.48,
            .view_mu = 0.60,
            .phase_coefficients = .{ 1.0, 0.26, 0.08, 0.02 },
        },
    };
    const geo = labos.Geometry.init(controls.nGauss(), 0.60, 0.66);
    var atten = try labos.fillAttenuationDynamic(std.testing.allocator, &layers, &geo, false);
    defer atten.deinit();
    var rt: [3]labos.LayerRT = undefined;
    labos.calcRTlayersInto(&rt, &layers, 0, &geo, controls);
    rt[0] = labos.fillSurface(0, 0.10, &geo);

    var bottom = PartAtmosphere.zero(geo.nmutot);
    bottom.R = rt[0].R;
    bottom.T = rt[0].T;
    bottom.Rst = rt[0].R;
    bottom.Tst = rt[0].T;
    bottom.U = rt[0].R;

    var etop = labos.Vec.zero(geo.nmutot);
    var ebot = labos.Vec.zero(geo.nmutot);
    for (0..geo.nmutot) |imu| {
        etop.set(imu, atten.get(imu, 1, 0));
        ebot.set(imu, atten.get(imu, 0, 0));
    }

    const combined = try addLayerToTop(
        0,
        &etop,
        &ebot,
        &rt[1],
        &bottom,
        &geo,
        controls.threshold_mul,
    );

    var expected_s: f64 = 0.0;
    for (0..geo.n_gauss) |imu| {
        for (0..geo.n_gauss) |imu0| {
            expected_s += geo.w[imu] * geo.w[imu0] * combined.R.get(imu, imu0);
        }
    }
    try std.testing.expectApproxEqAbs(expected_s, combined.s, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), combined.sst, 1.0e-12);
    for (0..geo.nmutot) |imu| {
        var expected_tpl: f64 = 0.0;
        for (0..geo.n_gauss) |imu0| {
            expected_tpl += geo.w[imu0] * combined.T.get(imu, imu0);
        }
        expected_tpl = expected_tpl / geo.w[imu] + ebot.get(imu) * etop.get(imu);
        try std.testing.expectApproxEqAbs(expected_tpl, combined.tpl.get(imu), 1.0e-12);
        try std.testing.expectApproxEqAbs(@as(f64, 0.0), combined.tplst.get(imu), 1.0e-12);
    }
}

test "adding composition zeroes vendor scalar integrated states for higher Fourier orders" {
    const controls = common.RtmControls{
        .use_adding = true,
        .n_streams = 8,
        .num_orders_max = 6,
    };
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.24,
            .scattering_optical_depth = 0.18,
            .single_scatter_albedo = 0.88,
            .solar_mu = 0.42,
            .view_mu = 0.54,
            .phase_coefficients = .{ 1.0, 0.31, 0.10, 0.02 },
        },
        .{
            .optical_depth = 0.16,
            .scattering_optical_depth = 0.12,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.48,
            .view_mu = 0.60,
            .phase_coefficients = .{ 1.0, 0.26, 0.08, 0.02 },
        },
    };
    const geo = labos.Geometry.init(controls.nGauss(), 0.60, 0.66);
    var atten = try labos.fillAttenuationDynamic(std.testing.allocator, &layers, &geo, false);
    defer atten.deinit();
    var rt: [3]labos.LayerRT = undefined;
    labos.calcRTlayersInto(&rt, &layers, 1, &geo, controls);
    rt[0] = labos.fillSurface(1, 0.10, &geo);

    var top = PartAtmosphere.zero(geo.nmutot);
    top.R = rt[2].R;
    top.T = rt[2].T;
    top.Rst = rt[2].R;
    top.Tst = rt[2].T;
    top.U = rt[2].R;
    top.Dst = rt[2].T;

    var bottom = PartAtmosphere.zero(geo.nmutot);
    bottom.R = rt[0].R;
    bottom.T = rt[0].T;
    bottom.Rst = rt[0].R;
    bottom.Tst = rt[0].T;
    bottom.U = rt[0].R;

    var etop = labos.Vec.zero(geo.nmutot);
    var ebot = labos.Vec.zero(geo.nmutot);
    for (0..geo.nmutot) |imu| {
        etop.set(imu, atten.get(imu, layers.len, 1));
        ebot.set(imu, atten.get(imu, 1, 0));
    }

    const added_bottom = try addLayerToBottom(
        1,
        &etop,
        &top,
        &ebot,
        &rt[1],
        &geo,
        controls.threshold_mul,
    );
    const added_top = try addLayerToTop(
        1,
        &etop,
        &ebot,
        &rt[1],
        &bottom,
        &geo,
        controls.threshold_mul,
    );

    try std.testing.expectApproxEqAbs(@as(f64, 0.0), added_bottom.s, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), added_bottom.sst, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), added_top.s, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), added_top.sst, 1.0e-12);
    for (0..geo.nmutot) |imu| {
        try std.testing.expectApproxEqAbs(@as(f64, 0.0), added_bottom.tpl.get(imu), 1.0e-12);
        try std.testing.expectApproxEqAbs(@as(f64, 0.0), added_bottom.tplst.get(imu), 1.0e-12);
        try std.testing.expectApproxEqAbs(@as(f64, 0.0), added_top.tpl.get(imu), 1.0e-12);
        try std.testing.expectApproxEqAbs(@as(f64, 0.0), added_top.tplst.get(imu), 1.0e-12);
    }
}

test "adding spherical correction changes reflectance for layered scalar scenes" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.24,
            .scattering_optical_depth = 0.18,
            .single_scatter_albedo = 0.88,
            .solar_mu = 0.42,
            .view_mu = 0.54,
            .phase_coefficients = .{ 1.0, 0.31, 0.10, 0.02 },
        },
        .{
            .optical_depth = 0.16,
            .scattering_optical_depth = 0.12,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.48,
            .view_mu = 0.60,
            .phase_coefficients = .{ 1.0, 0.26, 0.08, 0.02 },
        },
    };

    const route_plane = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 6,
            .use_spherical_correction = false,
        },
    });
    const route_spherical = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 6,
            .use_spherical_correction = true,
        },
    });

    const forward_input = common.ForwardInput{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.40,
        .single_scatter_albedo = 0.89,
        .surface_albedo = 0.10,
        .layers = &layers,
    };
    const plane = try execute(std.testing.allocator, route_plane, forward_input);
    const spherical = try execute(std.testing.allocator, route_spherical, forward_input);

    try std.testing.expect(@abs(plane.toa_reflectance_factor - spherical.toa_reflectance_factor) > 1.0e-5);
}

test "adding supports 80 transport layers without rejecting the explicit multi-layer path" {
    var layers: [80]common.LayerInput = undefined;
    for (&layers, 0..) |*layer, index| {
        const lower_haze = index < 36;
        layer.* = .{
            .optical_depth = if (lower_haze) 0.016 else 0.009,
            .scattering_optical_depth = if (lower_haze) 0.003 else 0.008,
            .single_scatter_albedo = if (lower_haze) 0.19 else 0.90,
            .solar_mu = 0.48,
            .view_mu = 0.61,
            .phase_coefficients = if (lower_haze)
                .{ 1.0, 0.03, 0.0, 0.0 }
            else
                .{ 1.0, 0.51, 0.18, 0.06 },
        };
    }

    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 6,
        },
    });

    const result = try execute(std.testing.allocator, route, .{
        .mu0 = 0.48,
        .muv = 0.61,
        .optical_depth = 0.88,
        .single_scatter_albedo = 0.53,
        .surface_albedo = 0.11,
        .layers = &layers,
    });

    try std.testing.expect(result.toa_reflectance_factor >= 0.0);
    try std.testing.expect(result.toa_reflectance_factor <= 2.0);
}
