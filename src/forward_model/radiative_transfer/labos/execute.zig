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

// Profiled O2 A validation keeps reflectance max_abs below 1e-13 here; 1e-13 is too loose.
const fourier_tail_reflectance_epsilon: f64 = 3.0e-14;

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
    reflectance_phase_kernel_ns: i128 = 0,
    reflectance_contribution_ns: i128 = 0,
    sample_count: usize = 0,
    fourier_count: usize = 0,
    geometry_cache_hits: usize = 0,
    geometry_cache_misses: usize = 0,
    plm_basis_hits: usize = 0,
    plm_basis_misses: usize = 0,
    plm_basis_extensions: usize = 0,
    phase_signature_layers: usize = 0,
    phase_signature_max_matches: usize = 0,
    phase_signature_matches: usize = 0,
    reusable_layer_templates: usize = 0,
    possible_layer_templates: usize = 0,
    cutoff_1e13_samples: usize = 0,
    cutoff_1e13_saved_terms: usize = 0,
    cutoff_1e13_tail_abs: f64 = 0.0,
    cutoff_1e13_tail_signed_abs: f64 = 0.0,
    cutoff_1e12_samples: usize = 0,
    cutoff_1e12_saved_terms: usize = 0,
    cutoff_1e12_tail_abs: f64 = 0.0,
    cutoff_1e12_tail_signed_abs: f64 = 0.0,
    cutoff_1e10_samples: usize = 0,
    cutoff_1e10_saved_terms: usize = 0,
    cutoff_1e10_tail_abs: f64 = 0.0,
    cutoff_1e10_tail_signed_abs: f64 = 0.0,

    pub const Sample = struct {
        attenuation_ns: i128 = 0,
        allocation_ns: i128 = 0,
        phase_index_ns: i128 = 0,
        plm_basis_ns: i128 = 0,
        rt_layers_ns: i128 = 0,
        surface_ns: i128 = 0,
        orders_ns: i128 = 0,
        reflectance_ns: i128 = 0,
        reflectance_phase_kernel_ns: i128 = 0,
        reflectance_contribution_ns: i128 = 0,
        fourier_count: usize = 0,
        geometry_cache_hits: usize = 0,
        geometry_cache_misses: usize = 0,
        plm_basis_hits: usize = 0,
        plm_basis_misses: usize = 0,
        plm_basis_extensions: usize = 0,
        phase_signature_layers: usize = 0,
        phase_signature_max_matches: usize = 0,
        phase_signature_matches: usize = 0,
        reusable_layer_templates: usize = 0,
        possible_layer_templates: usize = 0,
        cutoff_1e13_samples: usize = 0,
        cutoff_1e13_saved_terms: usize = 0,
        cutoff_1e13_tail_abs: f64 = 0.0,
        cutoff_1e13_tail_signed_abs: f64 = 0.0,
        cutoff_1e12_samples: usize = 0,
        cutoff_1e12_saved_terms: usize = 0,
        cutoff_1e12_tail_abs: f64 = 0.0,
        cutoff_1e12_tail_signed_abs: f64 = 0.0,
        cutoff_1e10_samples: usize = 0,
        cutoff_1e10_saved_terms: usize = 0,
        cutoff_1e10_tail_abs: f64 = 0.0,
        cutoff_1e10_tail_signed_abs: f64 = 0.0,
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
        self.reflectance_phase_kernel_ns += sample.reflectance_phase_kernel_ns;
        self.reflectance_contribution_ns += sample.reflectance_contribution_ns;
        self.sample_count += 1;
        self.fourier_count += sample.fourier_count;
        self.geometry_cache_hits += sample.geometry_cache_hits;
        self.geometry_cache_misses += sample.geometry_cache_misses;
        self.plm_basis_hits += sample.plm_basis_hits;
        self.plm_basis_misses += sample.plm_basis_misses;
        self.plm_basis_extensions += sample.plm_basis_extensions;
        self.phase_signature_layers += sample.phase_signature_layers;
        self.phase_signature_max_matches += sample.phase_signature_max_matches;
        self.phase_signature_matches += sample.phase_signature_matches;
        self.reusable_layer_templates += sample.reusable_layer_templates;
        self.possible_layer_templates += sample.possible_layer_templates;
        self.cutoff_1e13_samples += sample.cutoff_1e13_samples;
        self.cutoff_1e13_saved_terms += sample.cutoff_1e13_saved_terms;
        self.cutoff_1e13_tail_abs += sample.cutoff_1e13_tail_abs;
        self.cutoff_1e13_tail_signed_abs += sample.cutoff_1e13_tail_signed_abs;
        self.cutoff_1e12_samples += sample.cutoff_1e12_samples;
        self.cutoff_1e12_saved_terms += sample.cutoff_1e12_saved_terms;
        self.cutoff_1e12_tail_abs += sample.cutoff_1e12_tail_abs;
        self.cutoff_1e12_tail_signed_abs += sample.cutoff_1e12_tail_signed_abs;
        self.cutoff_1e10_samples += sample.cutoff_1e10_samples;
        self.cutoff_1e10_saved_terms += sample.cutoff_1e10_saved_terms;
        self.cutoff_1e10_tail_abs += sample.cutoff_1e10_tail_abs;
        self.cutoff_1e10_tail_signed_abs += sample.cutoff_1e10_tail_signed_abs;
    }

    pub fn print(self: *Profile) void {
        const fourier_denom = @max(@as(f64, @floatFromInt(self.fourier_count)), 1.0);
        const geometry_total = self.geometry_cache_hits + self.geometry_cache_misses;
        const plm_total = self.plm_basis_hits + self.plm_basis_misses + self.plm_basis_extensions;
        const phase_layer_denom = @max(@as(f64, @floatFromInt(self.phase_signature_layers)), 1.0);
        const phase_template_denom = @max(@as(f64, @floatFromInt(self.possible_layer_templates)), 1.0);
        std.debug.print(
            "[zds-profile] labos_samples={} fourier_terms={} attenuation={d:.3}ms allocation={d:.3}ms phase_indices={d:.3}ms plm_basis={d:.3}ms rt_layers={d:.3}ms surface={d:.3}ms orders={d:.3}ms reflectance={d:.3}ms reflectance_phase_kernel={d:.3}ms reflectance_contribution={d:.3}ms orders_mean={d:.3}ms/fourier rt_layers_mean={d:.3}ms/fourier\n",
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
                nsToMs(self.reflectance_phase_kernel_ns),
                nsToMs(self.reflectance_contribution_ns),
                nsToMs(self.orders_ns) / fourier_denom,
                nsToMs(self.rt_layers_ns) / fourier_denom,
            },
        );
        std.debug.print(
            "[zds-profile] labos_reuse geometry_hits={} geometry_misses={} geometry_hit_rate={d:.3} plm_hits={} plm_misses={} plm_extensions={} plm_hit_rate={d:.3} phase_max_matches={} phase_signature_matches={} phase_signature_match_rate={d:.3} reusable_layer_templates={} possible_layer_templates={} layer_template_reuse_rate={d:.3}\n",
            .{
                self.geometry_cache_hits,
                self.geometry_cache_misses,
                ratio(self.geometry_cache_hits, geometry_total),
                self.plm_basis_hits,
                self.plm_basis_misses,
                self.plm_basis_extensions,
                ratio(self.plm_basis_hits, plm_total),
                self.phase_signature_max_matches,
                self.phase_signature_matches,
                @as(f64, @floatFromInt(self.phase_signature_matches)) / phase_layer_denom,
                self.reusable_layer_templates,
                self.possible_layer_templates,
                @as(f64, @floatFromInt(self.reusable_layer_templates)) / phase_template_denom,
            },
        );
        std.debug.print(
            "[zds-profile] labos_fourier_cutoffs tol_1e-13_samples={} tol_1e-13_saved_terms={} tol_1e-13_tail_abs={e:.6} tol_1e-13_tail_signed_abs={e:.6} tol_1e-12_samples={} tol_1e-12_saved_terms={} tol_1e-12_tail_abs={e:.6} tol_1e-12_tail_signed_abs={e:.6} tol_1e-10_samples={} tol_1e-10_saved_terms={} tol_1e-10_tail_abs={e:.6} tol_1e-10_tail_signed_abs={e:.6}\n",
            .{
                self.cutoff_1e13_samples,
                self.cutoff_1e13_saved_terms,
                self.cutoff_1e13_tail_abs,
                self.cutoff_1e13_tail_signed_abs,
                self.cutoff_1e12_samples,
                self.cutoff_1e12_saved_terms,
                self.cutoff_1e12_tail_abs,
                self.cutoff_1e12_tail_signed_abs,
                self.cutoff_1e10_samples,
                self.cutoff_1e10_saved_terms,
                self.cutoff_1e10_tail_abs,
                self.cutoff_1e10_tail_signed_abs,
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

fn ratio(numerator: usize, denominator: usize) f64 {
    if (denominator == 0) return 0.0;
    return @as(f64, @floatFromInt(numerator)) / @as(f64, @floatFromInt(denominator));
}

const FourierCutoffStats = struct {
    sample_count: usize = 0,
    saved_terms: usize = 0,
    tail_abs: f64 = 0.0,
    tail_signed_abs: f64 = 0.0,
};

fn fourierCutoffStats(
    raw_abs_terms: []const f64,
    weighted_terms: []const f64,
    floor_scalar: usize,
    tolerance: f64,
) FourierCutoffStats {
    std.debug.assert(raw_abs_terms.len == weighted_terms.len);
    for (raw_abs_terms, 0..) |raw_abs, index| {
        if (index < floor_scalar or raw_abs > tolerance) continue;

        var tail_abs: f64 = 0.0;
        var tail_signed: f64 = 0.0;
        for (weighted_terms[index + 1 ..]) |weighted| {
            tail_abs += @abs(weighted);
            tail_signed += weighted;
        }
        return .{
            .sample_count = 1,
            .saved_terms = raw_abs_terms.len - index - 1,
            .tail_abs = tail_abs,
            .tail_signed_abs = @abs(tail_signed),
        };
    }
    return .{};
}

fn addCutoffStats(sample: *Profile.Sample, raw_abs_terms: []const f64, weighted_terms: []const f64, floor_scalar: usize) void {
    const stats_1e13 = fourierCutoffStats(raw_abs_terms, weighted_terms, floor_scalar, 1.0e-13);
    sample.cutoff_1e13_samples += stats_1e13.sample_count;
    sample.cutoff_1e13_saved_terms += stats_1e13.saved_terms;
    sample.cutoff_1e13_tail_abs += stats_1e13.tail_abs;
    sample.cutoff_1e13_tail_signed_abs += stats_1e13.tail_signed_abs;

    const stats_1e12 = fourierCutoffStats(raw_abs_terms, weighted_terms, floor_scalar, 1.0e-12);
    sample.cutoff_1e12_samples += stats_1e12.sample_count;
    sample.cutoff_1e12_saved_terms += stats_1e12.saved_terms;
    sample.cutoff_1e12_tail_abs += stats_1e12.tail_abs;
    sample.cutoff_1e12_tail_signed_abs += stats_1e12.tail_signed_abs;

    const stats_1e10 = fourierCutoffStats(raw_abs_terms, weighted_terms, floor_scalar, 1.0e-10);
    sample.cutoff_1e10_samples += stats_1e10.sample_count;
    sample.cutoff_1e10_saved_terms += stats_1e10.saved_terms;
    sample.cutoff_1e10_tail_abs += stats_1e10.tail_abs;
    sample.cutoff_1e10_tail_signed_abs += stats_1e10.tail_signed_abs;
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
    const geo = if (workspace) |scratch| blk: {
        if (profile_enabled) {
            const status = scratch.geometryWithStatus(controls.nGauss(), mu0, muv);
            if (status.hit) {
                profile_sample.geometry_cache_hits += 1;
            } else {
                profile_sample.geometry_cache_misses += 1;
            }
            break :blk status.geometry;
        }
        break :blk scratch.geometry(controls.nGauss(), mu0, muv);
    } else blk: {
        owned_geo = Geometry.init(controls.nGauss(), mu0, muv);
        if (profile_enabled) profile_sample.geometry_cache_misses += 1;
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
    if (profile_enabled) {
        if (workspace) |scratch| {
            if (layer_phase_max_indices) |indices| {
                const probe = try scratch.probeLayerPhaseSignatures(input.layers, indices, fourier_max);
                profile_sample.phase_signature_layers += probe.layer_count;
                profile_sample.phase_signature_max_matches += probe.max_index_matches;
                profile_sample.phase_signature_matches += probe.signature_matches;
                profile_sample.reusable_layer_templates += probe.reusable_fourier_layer_templates;
                profile_sample.possible_layer_templates += probe.possible_fourier_layer_templates;
            }
        }
    }
    if (profile_enabled) profile_sample.phase_index_ns += std.time.nanoTimestamp() - phase_index_start;

    var raw_abs_terms: [basis.max_phase_coef]f64 = undefined;
    var weighted_terms: [basis.max_phase_coef]f64 = undefined;
    var stored_fourier_terms: usize = 0;

    for (0..fourier_max + 1) |i_fourier| {
        profile_sample.fourier_count += 1;
        const plm_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
        var owned_plm_basis: basis.FourierPlmBasis = undefined;
        const plm_basis = if (workspace) |scratch| blk: {
            if (profile_enabled) {
                const status = try scratch.fourierPlmBasisWithStatus(i_fourier, phase_max, geo);
                if (status.hit) {
                    profile_sample.plm_basis_hits += 1;
                } else if (status.extended) {
                    profile_sample.plm_basis_extensions += 1;
                } else {
                    profile_sample.plm_basis_misses += 1;
                }
                break :blk status.plm_basis;
            }
            break :blk try scratch.fourierPlmBasis(i_fourier, phase_max, geo);
        } else blk: {
            owned_plm_basis = basis.FourierPlmBasis.init(i_fourier, phase_max, geo);
            if (profile_enabled) profile_sample.plm_basis_misses += 1;
            break :blk &owned_plm_basis;
        };
        if (profile_enabled) profile_sample.plm_basis_ns += std.time.nanoTimestamp() - plm_start;
        const rt_layers_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
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
        );
        if (profile_enabled) profile_sample.rt_layers_ns += std.time.nanoTimestamp() - rt_layers_start;
        const surface_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
        rt[0] = fillSurface(i_fourier, input.surface_albedo, geo);
        if (workspace != null) orders_workspace.rt_active[0] = i_fourier == 0 and input.surface_albedo != 0.0;
        if (profile_enabled) profile_sample.surface_ns += std.time.nanoTimestamp() - surface_start;
        const orders_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
        const orders_result = if (use_integrated_source)
            if (workspace != null) orders_mod.ordersScatIntoWithActive(
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
        if (profile_enabled) profile_sample.orders_ns += std.time.nanoTimestamp() - orders_start;
        const reflectance_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
        var reflectance_profile = reflectance_mod.IntegratedReflectanceProfileSample{};
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
                if (profile_enabled) &reflectance_profile else null,
            )
        else
            calcReflectance(orders_result.ud, nlayer, geo);
        if (profile_enabled) {
            profile_sample.reflectance_ns += std.time.nanoTimestamp() - reflectance_start;
            profile_sample.reflectance_phase_kernel_ns += reflectance_profile.phase_kernel_ns;
            profile_sample.reflectance_contribution_ns += reflectance_profile.contribution_ns;
        }
        const weighted_refl_fc = if (i_fourier == 0) blk: {
            break :blk refl_fc;
        } else blk: {
            const cos_m_dphi = math.cos(@as(f64, @floatFromInt(i_fourier)) * input.relative_azimuth_rad);
            break :blk (2.0 * refl_fc) * cos_m_dphi;
        };
        reflectance += weighted_refl_fc;
        if (profile_enabled and stored_fourier_terms < raw_abs_terms.len) {
            raw_abs_terms[stored_fourier_terms] = @abs(refl_fc);
            weighted_terms[stored_fourier_terms] = weighted_refl_fc;
            stored_fourier_terms += 1;
        }
        if (i_fourier >= controls.fourier_floor_scalar and @abs(refl_fc) <= fourier_tail_reflectance_epsilon) break;
    }

    if (profile_enabled) {
        addCutoffStats(
            &profile_sample,
            raw_abs_terms[0..stored_fourier_terms],
            weighted_terms[0..stored_fourier_terms],
            controls.fourier_floor_scalar,
        );
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
