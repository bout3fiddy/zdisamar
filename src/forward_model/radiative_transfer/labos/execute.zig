const std = @import("std");
const common = @import("../root.zig");
const jacobian = @import("../../jacobian/root.zig");
const basis = @import("basis.zig");
const attenuation = @import("attenuation.zig");
const layers_mod = @import("layers.zig");
const orders_mod = @import("orders.zig");
const reflectance_mod = @import("reflectance.zig");
const phase_functions = @import("../../optical_properties/shared/phase_functions.zig");
const workspace_mod = @import("workspace.zig");
const Trace = @import("../../performance_trace.zig");

const math = std.math;
const Geometry = basis.Geometry;
const LayerRT = basis.LayerRT;
const fillAttenuation = attenuation.fillAttenuation;
const fillAttenuationDynamicWithGrid = attenuation.fillAttenuationDynamicWithGrid;
const fillAttenuationTangentDynamic = attenuation.fillAttenuationTangentDynamic;
const fillSurface = layers_mod.fillSurface;
const calcRTlayers = layers_mod.calcRTlayers;
const calcRTlayersIntoWithBasis = layers_mod.calcRTlayersIntoWithBasis;
const calcRTlayersTangentIntoWithBasis = layers_mod.calcRTlayersTangentIntoWithBasis;
const fillLayerPhaseMaxIndices = layers_mod.fillLayerPhaseMaxIndices;
const calcReflectance = reflectance_mod.calcReflectance;
const calcIntegratedReflectanceWithBasis = reflectance_mod.calcIntegratedReflectanceWithBasis;
const calcAerosolOpticalDepthWeightingWithBasis = reflectance_mod.calcAerosolOpticalDepthWeightingWithBasis;
const calcAerosolLayerPressureShiftWeightingWithBasis = reflectance_mod.calcAerosolLayerPressureShiftWeightingWithBasis;
const fillAdjacentLayerPhaseMaxIndices = reflectance_mod.fillAdjacentLayerPhaseMaxIndices;
const resolvedFourierMax = reflectance_mod.resolvedFourierMax;
const resolvedPhaseCoefficientMax = reflectance_mod.resolvedPhaseCoefficientMax;
const totalScatteringOpticalDepth = reflectance_mod.totalScatteringOpticalDepth;

// O2 A validation keeps reflectance max_abs below 1e-13 here; 1e-13 is too loose.
const fourier_tail_reflectance_epsilon: f64 = 3.0e-14;

const LabosComputation = struct {
    reflectance: f64,
    jacobian: jacobian.Vector = jacobian.zero(),
};

const DirectSurfaceOnlyComputation = struct {
    reflectance: f64,
    surface_albedo_tangent: f64,
};

fn directSurfaceOnly(input: common.ForwardInput) DirectSurfaceOnlyComputation {
    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const direct = math.exp(-input.optical_depth / mu0) * math.exp(-input.optical_depth / muv);
    const reflectance = input.surface_albedo * direct;
    return .{
        .reflectance = math.clamp(reflectance, 0.0, 2.0),
        .surface_albedo_tangent = if (reflectance >= 0.0 and reflectance < 2.0) direct else 0.0,
    };
}

fn directSurfaceOnlyResolvedWithWorkspace(
    allocator: std.mem.Allocator,
    input: common.ForwardInput,
    controls: common.RadiativeTransferControls,
    workspace: ?*workspace_mod.Workspace,
) common.ExecuteError!DirectSurfaceOnlyComputation {
    if (input.layers.len == 0) return directSurfaceOnly(input);

    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    var owned_geo: Geometry = undefined;
    const geo = if (workspace) |scratch|
        scratch.geometry(controls.nGauss(), mu0, muv)
    else blk: {
        owned_geo = Geometry.init(controls.nGauss(), mu0, muv);
        break :blk &owned_geo;
    };
    const owned_atten = workspace == null;
    var atten = if (workspace) |scratch|
        try scratch.attenuation(
            input.layers,
            input.pseudo_spherical_grid,
            geo,
            controls.use_spherical_correction,
        )
    else
        try fillAttenuationDynamicWithGrid(
            allocator,
            input.layers,
            input.pseudo_spherical_grid,
            geo,
            controls.use_spherical_correction,
        );
    defer if (owned_atten) atten.deinit();

    const view_idx = geo.viewIdx();
    const solar_idx = geo.n_gauss + 1;
    const surface = fillSurface(0, input.surface_albedo, geo);
    const surface_derivative = fillSurface(0, 1.0, geo);
    var upward_path: f64 = 1.0;
    for (1..input.layers.len + 1) |ilevel| upward_path *= atten.get(view_idx, ilevel - 1, ilevel);

    const path = atten.get(solar_idx, input.layers.len, 0) * upward_path;
    const reflectance = surface.R.get(view_idx, solar_idx) * path;
    return .{
        .reflectance = math.clamp(reflectance, 0.0, 2.0),
        .surface_albedo_tangent = if (reflectance >= 0.0 and reflectance < 2.0)
            surface_derivative.R.get(view_idx, solar_idx) * path
        else
            0.0,
    };
}

pub fn execute(
    allocator: std.mem.Allocator,
    route: common.Route,
    input: common.ForwardInput,
) common.ExecuteError!common.ForwardResult {
    return executeWithWorkspace(allocator, route, input, null);
}

pub fn executeWithWorkspace(
    allocator: std.mem.Allocator,
    route: common.Route,
    input: common.ForwardInput,
    workspace: ?*workspace_mod.Workspace,
) common.ExecuteError!common.ForwardResult {
    if (route.family != .labos) unreachable;

    const controls = route.rtm_controls;
    const computation = if (controls.scattering == .none) blk: {
        const direct = try directSurfaceOnlyResolvedWithWorkspace(allocator, input, controls, workspace);
        var direct_jacobian = jacobian.zero();
        jacobian.set(&direct_jacobian, .surface_albedo, direct.surface_albedo_tangent);
        break :blk LabosComputation{
            .reflectance = direct.reflectance,
            .jacobian = direct_jacobian,
        };
    } else if (input.layers.len > 0)
        try layerResolvedLabosWithWorkspace(allocator, input, controls, route.derivative_mode != .none, workspace)
    else
        try singleLayerLabos(allocator, input, controls, route.derivative_mode != .none);

    return .{
        .family = route.family,
        .regime = route.regime,
        .execution_mode = route.execution_mode,
        .derivative_mode = route.derivative_mode,
        .toa_reflectance_factor = computation.reflectance,
        .jacobian = switch (route.derivative_mode) {
            .none => null,
            .semi_analytical => computation.jacobian,
            .numerical => computation.jacobian,
        },
    };
}

fn layerResolvedLabosWithWorkspace(
    allocator: std.mem.Allocator,
    input: common.ForwardInput,
    controls: common.RadiativeTransferControls,
    compute_jacobian: bool,
    workspace: ?*workspace_mod.Workspace,
) common.ExecuteError!LabosComputation {
    const nlayer = input.layers.len;
    if (nlayer == 0) return .{ .reflectance = 0.0 };
    const use_integrated_source =
        controls.integrate_source_function and
        nlayer > 1 and
        (input.source_interfaces.len == nlayer + 1 or
            input.rtm_quadrature.isValidFor(input.layers.len));
    if (compute_jacobian and !use_integrated_source and controls.use_spherical_correction) {
        return error.UnsupportedDerivativeMode;
    }

    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    var owned_geo: Geometry = undefined;
    const geo = if (workspace) |scratch|
        scratch.geometry(controls.nGauss(), mu0, muv)
    else blk: {
        owned_geo = Geometry.init(controls.nGauss(), mu0, muv);
        break :blk &owned_geo;
    };
    const owned_atten = workspace == null;
    var atten = if (workspace) |scratch|
        try scratch.attenuation(
            input.layers,
            input.pseudo_spherical_grid,
            geo,
            controls.use_spherical_correction,
        )
    else
        try fillAttenuationDynamicWithGrid(
            allocator,
            input.layers,
            input.pseudo_spherical_grid,
            geo,
            controls.use_spherical_correction,
        );
    defer if (owned_atten) atten.deinit();
    const rt = if (workspace) |scratch|
        try scratch.layerRt(nlayer + 1)
    else blk: {
        const owned_rt = try allocator.alloc(LayerRT, nlayer + 1);
        break :blk owned_rt;
    };
    defer if (workspace == null) allocator.free(rt);

    const num_orders_max: usize = @intCast(controls.resolvedNumOrdersMax(totalScatteringOpticalDepth(input.layers)));
    const fourier_max = resolvedFourierMax(input, controls);
    const phase_max = resolvedPhaseCoefficientMax(input);
    var reflectance: f64 = 0.0;
    var surface_albedo_tangent: f64 = 0.0;
    var aerosol_optical_depth_tangent: f64 = 0.0;
    var aerosol_layer_mid_pressure_tangent: f64 = 0.0;
    var owned_orders_workspace: ?orders_mod.OrdersWorkspace = null;
    defer if (owned_orders_workspace) |*orders_workspace| orders_workspace.deinit();
    const orders_workspace = if (workspace) |scratch|
        try scratch.ordersWorkspace(nlayer + 1)
    else blk: {
        owned_orders_workspace = try orders_mod.OrdersWorkspace.init(allocator, nlayer + 1);
        break :blk &(owned_orders_workspace.?);
    };
    const layer_phase_kernels: ?[]basis.PhaseKernel = if (use_integrated_source)
        if (workspace) |scratch| try scratch.phaseKernelCache(nlayer + 1) else try allocator.alloc(basis.PhaseKernel, nlayer + 1)
    else
        null;
    defer if (workspace == null) if (layer_phase_kernels) |cache| allocator.free(cache);
    const layer_phase_kernel_valid: ?[]bool = if (use_integrated_source)
        if (workspace) |scratch| try scratch.phaseKernelValid(nlayer + 1) else try allocator.alloc(bool, nlayer + 1)
    else
        null;
    defer if (workspace == null) if (layer_phase_kernel_valid) |valid| allocator.free(valid);

    const layer_phase_max_indices = if (workspace) |scratch| blk: {
        const indices = try scratch.layerPhaseMaxIndices(nlayer);
        fillLayerPhaseMaxIndices(indices, input.layers);
        break :blk indices;
    } else null;
    const adjacent_layer_phase_max_indices = if (workspace) |scratch| blk: {
        if (layer_phase_max_indices) |layer_indices| {
            const indices = try scratch.sourcePhaseMaxIndices(nlayer + 1);
            fillAdjacentLayerPhaseMaxIndices(indices, layer_indices);
            break :blk indices;
        }
        break :blk null;
    } else null;
    const trace: Trace.WorkerRef = if (Trace.enabled) blk: {
        if (workspace) |scratch| break :blk scratch.trace;
        break :blk Trace.noWorker();
    } else {};

    for (0..fourier_max + 1) |i_fourier| {
        const fourier_start = Trace.begin();
        if (Trace.enabled) if (Trace.asWorker(trace)) |sink| sink.addCounter(.fourier_terms, 1);
        var owned_plm_basis: basis.FourierPlmBasis = undefined;
        const plm_start = Trace.begin();
        const plm_basis = if (workspace) |scratch| blk: {
            break :blk try scratch.fourierPlmBasis(i_fourier, phase_max, geo);
        } else blk: {
            owned_plm_basis = basis.FourierPlmBasis.init(i_fourier, phase_max, geo);
            break :blk &owned_plm_basis;
        };
        if (Trace.enabled) if (Trace.asWorker(trace)) |sink| sink.addSection(.plm_basis, Trace.elapsed(plm_start));
        const rt_start = Trace.begin();
        calcRTlayersIntoWithBasis(
            rt,
            input.layers,
            i_fourier,
            geo,
            controls,
            plm_basis,
            layer_phase_max_indices,
            layer_phase_kernels,
            layer_phase_kernel_valid,
            if (workspace != null) orders_workspace.rt_active else null,
            trace,
        );
        if (Trace.enabled) if (Trace.asWorker(trace)) |sink| sink.addSection(.rt_layer_build, Trace.elapsed(rt_start));
        rt[0] = fillSurface(i_fourier, input.surface_albedo, geo);
        if (workspace != null) orders_workspace.rt_active[0] = i_fourier == 0 and input.surface_albedo != 0.0;
        if (Trace.enabled) orders_workspace.trace = trace;
        const orders_start = Trace.begin();
        const orders_result = if (use_integrated_source)
            if (compute_jacobian)
                if (workspace != null) orders_mod.ordersScatIntoWithActiveLocalSum(
                    orders_workspace,
                    0,
                    nlayer,
                    geo,
                    &atten,
                    rt,
                    controls,
                    num_orders_max,
                ) else orders_mod.ordersScatIntoWithLocalSum(
                    orders_workspace,
                    0,
                    nlayer,
                    geo,
                    &atten,
                    rt,
                    controls,
                    num_orders_max,
                )
            else if (workspace != null) orders_mod.ordersScatIntoWithActive(
                orders_workspace,
                0,
                nlayer,
                geo,
                &atten,
                rt,
                controls,
                num_orders_max,
            ) else orders_mod.ordersScatInto(
                orders_workspace,
                0,
                nlayer,
                geo,
                &atten,
                rt,
                controls,
                num_orders_max,
            )
        else
            orders_mod.ordersScatTransportInto(
                orders_workspace,
                0,
                nlayer,
                geo,
                &atten,
                rt,
                controls,
                num_orders_max,
            );
        if (Trace.enabled) if (Trace.asWorker(trace)) |sink| sink.addSection(.orders_total, Trace.elapsed(orders_start));
        const reflectance_start = Trace.begin();
        const refl_fc = if (use_integrated_source)
            calcIntegratedReflectanceWithBasis(
                input.layers,
                input.source_interfaces,
                input.rtm_quadrature,
                orders_result.ud,
                nlayer,
                i_fourier,
                geo,
                plm_basis,
                adjacent_layer_phase_max_indices,
                layer_phase_kernels,
                layer_phase_kernel_valid,
            )
        else
            calcReflectance(orders_result.ud, nlayer, geo);
        if (Trace.enabled) if (Trace.asWorker(trace)) |sink| sink.addSection(.reflectance_integral, Trace.elapsed(reflectance_start));
        const weighted_refl_fc = if (i_fourier == 0) blk: {
            break :blk refl_fc;
        } else blk: {
            const cos_m_dphi = math.cos(@as(f64, @floatFromInt(i_fourier)) * input.relative_azimuth_rad);
            break :blk (2.0 * refl_fc) * cos_m_dphi;
        };
        reflectance += weighted_refl_fc;
        if (compute_jacobian and i_fourier == 0) {
            surface_albedo_tangent += surfaceAlbedoWeightingFunction(orders_result.ud, geo);
        }
        if (compute_jacobian) {
            const tangent_refl_fc = if (use_integrated_source) blk: {
                break :blk calcAerosolOpticalDepthWeightingWithBasis(
                    input.layers,
                    input.rtm_quadrature,
                    orders_result.ud,
                    orders_result.ud_sum_local,
                    nlayer,
                    i_fourier,
                    controls.use_spherical_correction,
                    geo,
                    plm_basis,
                    adjacent_layer_phase_max_indices,
                );
            } else try nonIntegratedReflectanceTangent(
                allocator,
                input.layers,
                .aerosol_optical_depth,
                i_fourier,
                geo,
                &atten,
                rt,
                controls,
                plm_basis,
                num_orders_max,
            );
            const weighted_tangent_refl_fc = if (i_fourier == 0) blk: {
                break :blk tangent_refl_fc;
            } else blk: {
                const cos_m_dphi = math.cos(@as(f64, @floatFromInt(i_fourier)) * input.relative_azimuth_rad);
                break :blk (2.0 * tangent_refl_fc) * cos_m_dphi;
            };
            aerosol_optical_depth_tangent += weighted_tangent_refl_fc;
            const pressure_tangent_refl_fc = if (use_integrated_source)
                calcAerosolLayerPressureShiftWeightingWithBasis(
                    input.layers,
                    input.rtm_quadrature,
                    orders_result.ud,
                    orders_result.ud_sum_local,
                    nlayer,
                    i_fourier,
                    controls.use_spherical_correction,
                    geo,
                    plm_basis,
                )
            else blk: {
                if (!hasLayerJacobian(input.layers, .aerosol_layer_mid_pressure_hpa)) {
                    return error.UnsupportedDerivativeMode;
                }
                break :blk try nonIntegratedReflectanceTangent(
                    allocator,
                    input.layers,
                    .aerosol_layer_mid_pressure_hpa,
                    i_fourier,
                    geo,
                    &atten,
                    rt,
                    controls,
                    plm_basis,
                    num_orders_max,
                );
            };
            const weighted_pressure_tangent_refl_fc = if (i_fourier == 0) blk: {
                break :blk pressure_tangent_refl_fc;
            } else blk: {
                const cos_m_dphi = math.cos(@as(f64, @floatFromInt(i_fourier)) * input.relative_azimuth_rad);
                break :blk (2.0 * pressure_tangent_refl_fc) * cos_m_dphi;
            };
            aerosol_layer_mid_pressure_tangent += weighted_pressure_tangent_refl_fc;
        }
        if (Trace.enabled) if (Trace.asWorker(trace)) |sink| sink.addSection(.labos_fourier_total, Trace.elapsed(fourier_start));
        if (i_fourier >= controls.fourier_floor_scalar and @abs(refl_fc) <= fourier_tail_reflectance_epsilon) {
            if (Trace.enabled) if (Trace.asWorker(trace)) |sink| sink.addCounter(.fourier_tail_breaks, 1);
            break;
        }
    }

    var result_jacobian = jacobian.zero();
    jacobian.set(&result_jacobian, .surface_albedo, surface_albedo_tangent);
    jacobian.set(&result_jacobian, .aerosol_optical_depth, aerosol_optical_depth_tangent);
    jacobian.set(&result_jacobian, .aerosol_layer_mid_pressure_hpa, aerosol_layer_mid_pressure_tangent);
    return .{
        .reflectance = math.clamp(reflectance, 0.0, 2.0),
        .jacobian = result_jacobian,
    };
}

fn nonIntegratedReflectanceTangent(
    allocator: std.mem.Allocator,
    layers: []const common.LayerInput,
    state: common.Jacobian.State,
    i_fourier: usize,
    geo: *const Geometry,
    atten: anytype,
    rt: []const LayerRT,
    controls: common.RadiativeTransferControls,
    plm_basis: *const basis.FourierPlmBasis,
    num_orders_max: usize,
) !f64 {
    var atten_tangent = try fillAttenuationTangentDynamic(
        allocator,
        layers,
        state,
        geo,
    );
    defer atten_tangent.deinit();

    const rt_tangent = try allocator.alloc(LayerRT, layers.len + 1);
    defer allocator.free(rt_tangent);
    calcRTlayersTangentIntoWithBasis(
        rt_tangent,
        layers,
        state,
        i_fourier,
        geo,
        controls,
        plm_basis,
    );

    var tangent_orders = try orders_mod.ordersScatTangent(
        allocator,
        0,
        layers.len,
        geo,
        atten,
        &atten_tangent,
        rt,
        rt_tangent,
        controls,
        num_orders_max,
    );
    defer tangent_orders.deinit();
    return reflectance_mod.calcReflectanceTangent(tangent_orders.ud, layers.len, geo);
}

fn singleLayerLabos(
    allocator: std.mem.Allocator,
    input: common.ForwardInput,
    controls: common.RadiativeTransferControls,
    compute_jacobian: bool,
) common.ExecuteError!LabosComputation {
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
    var surface_albedo_tangent: f64 = 0.0;
    var orders_workspace = try orders_mod.OrdersWorkspace.init(allocator, 2);
    defer orders_workspace.deinit();
    for (0..fourier_max + 1) |i_fourier| {
        var rt = calcRTlayers(&layers, i_fourier, &geo, controls);
        rt[0] = fillSurface(i_fourier, input.surface_albedo, &geo);
        const orders_result = orders_mod.ordersScatTransportInto(
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
        if (compute_jacobian and i_fourier == 0) {
            surface_albedo_tangent += surfaceAlbedoWeightingFunction(orders_result.ud, &geo);
        }
    }

    var result_jacobian = jacobian.zero();
    jacobian.set(&result_jacobian, .surface_albedo, surface_albedo_tangent);
    return .{
        .reflectance = math.clamp(reflectance, 0.0, 2.0),
        .jacobian = result_jacobian,
    };
}

fn hasLayerJacobian(layers: []const common.LayerInput, state: common.Jacobian.State) bool {
    for (layers) |layer| {
        if (common.Jacobian.get(layer.optical_depth_jacobian, state) != 0.0) return true;
        if (common.Jacobian.get(layer.scattering_optical_depth_jacobian, state) != 0.0) return true;
        if (common.Jacobian.get(layer.single_scatter_albedo_jacobian, state) != 0.0) return true;
    }
    return false;
}

fn surfaceAlbedoWeightingFunction(
    ud: []const basis.UDField,
    geo: *const basis.Geometry,
) f64 {
    const surface_level: usize = 0;
    const view_col: usize = 0;
    const solar_col: usize = 1;
    var diffuse_view: f64 = 0.0;
    var diffuse_solar: f64 = 0.0;
    for (0..geo.n_gauss) |i_gauss| {
        diffuse_view += ud[surface_level].D.col[view_col].get(i_gauss) * geo.w[i_gauss];
        diffuse_solar += ud[surface_level].D.col[solar_col].get(i_gauss) * geo.w[i_gauss];
    }
    const view_direct = ud[surface_level].E.get(geo.viewIdx());
    const solar_direct = ud[surface_level].E.get(geo.n_gauss + 1);
    return (view_direct + diffuse_view) * (solar_direct + diffuse_solar);
}
