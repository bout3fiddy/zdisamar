const std = @import("std");
const common = @import("../root.zig");
const derivatives = @import("../derivatives.zig");
const basis = @import("basis.zig");
const attenuation = @import("attenuation.zig");
const layers_mod = @import("layers.zig");
const orders_mod = @import("orders.zig");
const reflectance_mod = @import("reflectance.zig");
const phase_functions = @import("../../optical_properties/shared/phase_functions.zig");
const workspace_mod = @import("workspace.zig");

const math = std.math;
const Geometry = basis.Geometry;
const LayerRT = basis.LayerRT;
const fillAttenuation = attenuation.fillAttenuation;
const fillAttenuationDynamicWithGrid = attenuation.fillAttenuationDynamicWithGrid;
const fillSurface = layers_mod.fillSurface;
const calcRTlayers = layers_mod.calcRTlayers;
const calcRTlayersIntoWithBasis = layers_mod.calcRTlayersIntoWithBasis;
const fillLayerPhaseMaxIndices = layers_mod.fillLayerPhaseMaxIndices;
const calcReflectance = reflectance_mod.calcReflectance;
const calcIntegratedReflectanceWithBasis = reflectance_mod.calcIntegratedReflectanceWithBasis;
const fillAdjacentLayerPhaseMaxIndices = reflectance_mod.fillAdjacentLayerPhaseMaxIndices;
const resolvedFourierMax = reflectance_mod.resolvedFourierMax;
const resolvedPhaseCoefficientMax = reflectance_mod.resolvedPhaseCoefficientMax;
const totalScatteringOpticalDepth = reflectance_mod.totalScatteringOpticalDepth;

pub const Profile = struct {
    mutex: std.Thread.Mutex = .{},
    attenuation_ns: i128 = 0,
    allocation_ns: i128 = 0,
    phase_index_ns: i128 = 0,
    plm_basis_ns: i128 = 0,
    rt_layers_ns: i128 = 0,
    surface_ns: i128 = 0,
    orders_ns: i128 = 0,
    reflectance_ns: i128 = 0,
    sample_count: usize = 0,
    fourier_count: usize = 0,

    pub const Sample = struct {
        attenuation_ns: i128 = 0,
        allocation_ns: i128 = 0,
        phase_index_ns: i128 = 0,
        plm_basis_ns: i128 = 0,
        rt_layers_ns: i128 = 0,
        surface_ns: i128 = 0,
        orders_ns: i128 = 0,
        reflectance_ns: i128 = 0,
        fourier_count: usize = 0,
    };

    pub fn addSample(self: *Profile, sample: Sample) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.attenuation_ns += sample.attenuation_ns;
        self.allocation_ns += sample.allocation_ns;
        self.phase_index_ns += sample.phase_index_ns;
        self.plm_basis_ns += sample.plm_basis_ns;
        self.rt_layers_ns += sample.rt_layers_ns;
        self.surface_ns += sample.surface_ns;
        self.orders_ns += sample.orders_ns;
        self.reflectance_ns += sample.reflectance_ns;
        self.sample_count += 1;
        self.fourier_count += sample.fourier_count;
    }

    pub fn print(self: *Profile) void {
        const fourier_denom = @max(@as(f64, @floatFromInt(self.fourier_count)), 1.0);
        std.debug.print(
            "[zds-profile] labos_samples={} fourier_terms={} attenuation={d:.3}ms allocation={d:.3}ms phase_indices={d:.3}ms plm_basis={d:.3}ms rt_layers={d:.3}ms surface={d:.3}ms orders={d:.3}ms reflectance={d:.3}ms orders_mean={d:.3}ms/fourier rt_layers_mean={d:.3}ms/fourier\n",
            .{
                self.sample_count,
                self.fourier_count,
                nsToMs(self.attenuation_ns),
                nsToMs(self.allocation_ns),
                nsToMs(self.phase_index_ns),
                nsToMs(self.plm_basis_ns),
                nsToMs(self.rt_layers_ns),
                nsToMs(self.surface_ns),
                nsToMs(self.orders_ns),
                nsToMs(self.reflectance_ns),
                nsToMs(self.orders_ns) / fourier_denom,
                nsToMs(self.rt_layers_ns) / fourier_denom,
            },
        );
    }
};

threadlocal var active_profile: ?*Profile = null;

pub fn setProfile(profile: ?*Profile) ?*Profile {
    const previous = active_profile;
    active_profile = profile;
    return previous;
}

fn nsToMs(ns: i128) f64 {
    return @as(f64, @floatFromInt(ns)) / 1.0e6;
}

fn directSurfaceOnlyReflectance(input: common.ForwardInput) f64 {
    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const direct = math.exp(-input.optical_depth / mu0) * math.exp(-input.optical_depth / muv);
    return math.clamp(input.surface_albedo * direct, 0.0, 2.0);
}

fn directSurfaceOnlyReflectanceResolvedWithWorkspace(
    allocator: std.mem.Allocator,
    input: common.ForwardInput,
    controls: common.RadiativeTransferControls,
    workspace: ?*workspace_mod.Workspace,
) common.ExecuteError!f64 {
    if (input.layers.len == 0) return directSurfaceOnlyReflectance(input);

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
    const toa = if (controls.scattering == .none)
        try directSurfaceOnlyReflectanceResolvedWithWorkspace(allocator, input, controls, workspace)
    else if (input.layers.len > 0)
        try layerResolvedLabosWithWorkspace(allocator, input, controls, workspace)
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
            .numerical => derivatives.proxyJacobianColumn(toa, input.optical_depth, 0.05),
        },
    };
}

fn layerResolvedLabosWithWorkspace(
    allocator: std.mem.Allocator,
    input: common.ForwardInput,
    controls: common.RadiativeTransferControls,
    workspace: ?*workspace_mod.Workspace,
) common.ExecuteError!f64 {
    const nlayer = input.layers.len;
    if (nlayer == 0) return 0.0;

    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    var owned_geo: Geometry = undefined;
    const profile_enabled = active_profile != null;
    var profile_sample = Profile.Sample{};
    const geo = if (workspace) |scratch|
        scratch.geometry(controls.nGauss(), mu0, muv)
    else blk: {
        owned_geo = Geometry.init(controls.nGauss(), mu0, muv);
        break :blk &owned_geo;
    };
    const owned_atten = workspace == null;
    const attenuation_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
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
    if (profile_enabled) profile_sample.attenuation_ns += std.time.nanoTimestamp() - attenuation_start;

    const allocation_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
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
    const use_integrated_source =
        controls.integrate_source_function and
        nlayer > 1 and
        (input.source_interfaces.len == nlayer + 1 or
            input.rtm_quadrature.isValidFor(input.layers.len));

    var reflectance: f64 = 0.0;
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
    if (profile_enabled) profile_sample.allocation_ns += std.time.nanoTimestamp() - allocation_start;

    const phase_index_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
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
    if (profile_enabled) profile_sample.phase_index_ns += std.time.nanoTimestamp() - phase_index_start;

    for (0..fourier_max + 1) |i_fourier| {
        profile_sample.fourier_count += 1;
        const plm_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
        const plm_basis = basis.FourierPlmBasis.init(i_fourier, phase_max, geo);
        if (profile_enabled) profile_sample.plm_basis_ns += std.time.nanoTimestamp() - plm_start;
        const rt_layers_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
        calcRTlayersIntoWithBasis(
            rt,
            input.layers,
            i_fourier,
            geo,
            controls,
            &plm_basis,
            layer_phase_max_indices,
            layer_phase_kernels,
            layer_phase_kernel_valid,
        );
        if (profile_enabled) profile_sample.rt_layers_ns += std.time.nanoTimestamp() - rt_layers_start;
        const surface_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
        rt[0] = fillSurface(i_fourier, input.surface_albedo, geo);
        if (profile_enabled) profile_sample.surface_ns += std.time.nanoTimestamp() - surface_start;
        const orders_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
        const orders_result = if (use_integrated_source)
            orders_mod.ordersScatInto(
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
        if (profile_enabled) profile_sample.orders_ns += std.time.nanoTimestamp() - orders_start;
        const reflectance_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
        const refl_fc = if (use_integrated_source)
            calcIntegratedReflectanceWithBasis(
                input.layers,
                input.source_interfaces,
                input.rtm_quadrature,
                orders_result.ud,
                nlayer,
                i_fourier,
                geo,
                &plm_basis,
                adjacent_layer_phase_max_indices,
                layer_phase_kernels,
                layer_phase_kernel_valid,
            )
        else
            calcReflectance(orders_result.ud, nlayer, geo);
        if (profile_enabled) profile_sample.reflectance_ns += std.time.nanoTimestamp() - reflectance_start;
        const fourier_weight = if (i_fourier == 0)
            1.0
        else
            2.0 * math.cos(@as(f64, @floatFromInt(i_fourier)) * input.relative_azimuth_rad);
        reflectance += fourier_weight * refl_fc;
    }

    if (active_profile) |profiler| profiler.addSample(profile_sample);
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
    }

    return math.clamp(reflectance, 0.0, 2.0);
}
