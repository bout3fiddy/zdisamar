const std = @import("std");
const common = @import("../common.zig");
const derivatives = @import("../derivatives.zig");
const basis = @import("basis.zig");
const attenuation = @import("attenuation.zig");
const layers_mod = @import("layers.zig");
const orders_mod = @import("orders.zig");
const reflectance_mod = @import("reflectance.zig");
const phase_functions = @import("../../optics/prepare/phase_functions.zig");

const math = std.math;
const Geometry = basis.Geometry;
const LayerRT = basis.LayerRT;
const fillAttenuation = attenuation.fillAttenuation;
const fillAttenuationDynamicWithGrid = attenuation.fillAttenuationDynamicWithGrid;
const fillSurface = layers_mod.fillSurface;
const calcRTlayers = layers_mod.calcRTlayers;
const calcRTlayersIntoWithBasis = layers_mod.calcRTlayersIntoWithBasis;
const calcReflectance = reflectance_mod.calcReflectance;
const calcIntegratedReflectanceWithBasis = reflectance_mod.calcIntegratedReflectanceWithBasis;
const resolvedFourierMax = reflectance_mod.resolvedFourierMax;
const resolvedPhaseCoefficientMax = reflectance_mod.resolvedPhaseCoefficientMax;
const totalScatteringOpticalDepth = reflectance_mod.totalScatteringOpticalDepth;

fn directSurfaceOnlyReflectance(input: common.ForwardInput) f64 {
    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const direct = math.exp(-input.optical_depth / mu0) * math.exp(-input.optical_depth / muv);
    return math.clamp(input.surface_albedo * direct, 0.0, 2.0);
}

fn directSurfaceOnlyReflectanceResolved(
    allocator: std.mem.Allocator,
    input: common.ForwardInput,
    controls: common.RadiativeTransferControls,
) common.ExecuteError!f64 {
    if (input.layers.len == 0) return directSurfaceOnlyReflectance(input);

    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const geo = Geometry.init(controls.nGauss(), mu0, muv);
    var atten = try fillAttenuationDynamicWithGrid(
        allocator,
        input.layers,
        input.pseudo_spherical_grid,
        &geo,
        controls.use_spherical_correction,
    );
    defer atten.deinit();

    const view_idx = geo.viewIdx();
    const solar_idx = geo.n_gauss + 1;
    const surface = fillSurface(0, input.surface_albedo, &geo);
    var upward_path: f64 = 1.0;
    for (1..input.layers.len + 1) |ilevel| upward_path *= atten.get(view_idx, ilevel - 1, ilevel);

    return math.clamp(
        surface.R.get(view_idx, solar_idx) *
            atten.get(solar_idx, input.layers.len, 0) *
            upward_path,
        0.0,
        2.0,
    );
}

pub fn execute(
    allocator: std.mem.Allocator,
    route: common.Route,
    input: common.ForwardInput,
) common.ExecuteError!common.ForwardResult {
    if (route.family != .labos) unreachable;
    if (route.derivative_mode == .analytical_plugin) {
        return common.Error.UnsupportedDerivativeMode;
    }

    const controls = route.rtm_controls;
    const toa = if (controls.scattering == .none)
        try directSurfaceOnlyReflectanceResolved(allocator, input, controls)
    else if (input.layers.len > 0)
        try layerResolvedLabos(allocator, input, controls)
    else
        try singleLayerLabos(allocator, input, controls);

    return .{
        .family = route.family,
        .regime = route.regime,
        .execution_mode = route.execution_mode,
        .derivative_mode = route.derivative_mode,
        .toa_reflectance_factor = toa,
        .jacobian_column = switch (route.derivative_mode) {
            .none => null,
            .semi_analytical => derivatives.proxyJacobianColumn(toa, input.optical_depth, 0.06),
            .analytical_plugin => null,
            .numerical => derivatives.proxyJacobianColumn(toa, input.optical_depth, 0.05),
        },
    };
}

fn layerResolvedLabos(
    allocator: std.mem.Allocator,
    input: common.ForwardInput,
    controls: common.RadiativeTransferControls,
) common.ExecuteError!f64 {
    const nlayer = input.layers.len;
    if (nlayer == 0) return 0.0;

    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const geo = Geometry.init(controls.nGauss(), mu0, muv);
    var atten = try fillAttenuationDynamicWithGrid(
        allocator,
        input.layers,
        input.pseudo_spherical_grid,
        &geo,
        controls.use_spherical_correction,
    );
    defer atten.deinit();

    var rt = try allocator.alloc(LayerRT, nlayer + 1);
    defer allocator.free(rt);

    const num_orders_max: usize = @intCast(controls.resolvedNumOrdersMax(totalScatteringOpticalDepth(input.layers)));
    const fourier_max = resolvedFourierMax(input, controls);
    const phase_max = resolvedPhaseCoefficientMax(input);
    const use_integrated_source =
        controls.integrate_source_function and
        nlayer > 1 and
        (input.source_interfaces.len == nlayer + 1 or
            input.rtm_quadrature.isValidFor(input.layers.len));

    var reflectance: f64 = 0.0;
    var orders_workspace = try orders_mod.OrdersWorkspace.init(allocator, nlayer + 1);
    defer orders_workspace.deinit();
    const layer_phase_kernels: ?[]basis.PhaseKernel = if (use_integrated_source)
        try allocator.alloc(basis.PhaseKernel, nlayer + 1)
    else
        null;
    defer if (layer_phase_kernels) |cache| allocator.free(cache);
    const layer_phase_kernel_valid: ?[]bool = if (use_integrated_source)
        try allocator.alloc(bool, nlayer + 1)
    else
        null;
    defer if (layer_phase_kernel_valid) |valid| allocator.free(valid);

    for (0..fourier_max + 1) |i_fourier| {
        const plm_basis = basis.FourierPlmBasis.init(i_fourier, phase_max, &geo);
        calcRTlayersIntoWithBasis(
            rt,
            input.layers,
            i_fourier,
            &geo,
            controls,
            &plm_basis,
            layer_phase_kernels,
            layer_phase_kernel_valid,
        );
        rt[0] = fillSurface(i_fourier, input.surface_albedo, &geo);
        const orders_result = orders_mod.ordersScatInto(
            &orders_workspace,
            0,
            nlayer,
            &geo,
            &atten,
            rt,
            controls,
            num_orders_max,
        );
        const refl_fc = if (use_integrated_source)
            calcIntegratedReflectanceWithBasis(
                input.layers,
                input.source_interfaces,
                input.rtm_quadrature,
                orders_result.ud,
                nlayer,
                i_fourier,
                &geo,
                &plm_basis,
                layer_phase_kernels,
                layer_phase_kernel_valid,
            )
        else
            calcReflectance(orders_result.ud, nlayer, &geo);
        const fourier_weight = if (i_fourier == 0)
            1.0
        else
            2.0 * math.cos(@as(f64, @floatFromInt(i_fourier)) * input.relative_azimuth_rad);
        reflectance += fourier_weight * refl_fc;
    }

    return math.clamp(reflectance, 0.0, 2.0);
}

fn singleLayerLabos(
    allocator: std.mem.Allocator,
    input: common.ForwardInput,
    controls: common.RadiativeTransferControls,
) common.ExecuteError!f64 {
    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const geo = Geometry.init(controls.nGauss(), mu0, muv);

    const layer = common.LayerInput{
        .optical_depth = input.optical_depth,
        .single_scatter_albedo = input.single_scatter_albedo,
        .solar_mu = mu0,
        .view_mu = muv,
        .phase_coefficients = phase_functions.zeroPhaseCoefficients(),
    };
    const layers = [_]common.LayerInput{layer};
    const atten = fillAttenuation(&layers, &geo, controls.use_spherical_correction);
    const num_orders_max: usize = @intCast(controls.resolvedNumOrdersMax(layer.scattering_optical_depth));
    const fourier_max = resolvedFourierMax(input, controls);

    var reflectance: f64 = 0.0;
    var orders_workspace = try orders_mod.OrdersWorkspace.init(allocator, 2);
    defer orders_workspace.deinit();
    for (0..fourier_max + 1) |i_fourier| {
        var rt = calcRTlayers(&layers, i_fourier, &geo, controls);
        rt[0] = fillSurface(i_fourier, input.surface_albedo, &geo);
        const orders_result = orders_mod.ordersScatInto(
            &orders_workspace,
            0,
            1,
            &geo,
            &atten,
            rt[0..2],
            controls,
            num_orders_max,
        );
        const refl_fc = calcReflectance(orders_result.ud, 1, &geo);
        const fourier_weight = if (i_fourier == 0)
            1.0
        else
            2.0 * math.cos(@as(f64, @floatFromInt(i_fourier)) * input.relative_azimuth_rad);
        reflectance += fourier_weight * refl_fc;
    }

    return math.clamp(reflectance, 0.0, 2.0);
}
