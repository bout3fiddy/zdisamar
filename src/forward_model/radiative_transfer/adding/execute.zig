const std = @import("std");
const common = @import("../root.zig");
const derivatives = @import("../derivatives.zig");
const fields = @import("fields.zig");
const labos = @import("../labos/root.zig");

const Allocator = std.mem.Allocator;

const ReflectanceComponents = struct {
    toa_reflectance_factor: f64,
    surface_term: f64,
    scattering_term: f64,
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
    controls: common.RadiativeTransferControls,
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
    controls: common.RadiativeTransferControls,
) common.ExecuteError!ReflectanceComponents {
    const layers = input.layers;
    if (layers.len == 0) {
        return error.UnsupportedRadiativeTransferControls;
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
            const top_down = try fields.calcTopDownField(
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
            const ud = try fields.calcSurfaceUpField(
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
