const std = @import("std");
const common = @import("../root.zig");
const jacobian = @import("../../jacobian/root.zig");
const basis = @import("basis.zig");
const attenuation = @import("attenuation.zig");
const layers_mod = @import("layers.zig");
const orders_mod = @import("orders.zig");
const reflectance_mod = @import("reflectance.zig");
const workspace_mod = @import("workspace.zig");
const Telemetry = @import("../../instrumentation/telemetry.zig");
const Perturbation = @import("../../instrumentation/sensitivity.zig");
const Trace = @import("../../instrumentation/trace.zig");

// execute.zig ------------------------------------------------------------------------------------------------|
// LABOS solve coordinator. Prepared input -> attenuation -> RT layers -> scattering orders.                   |
// Then reflectance and optional Jacobian output are packed into the public result.                            |
//                                                                                                             |
// called by                                                                                                   |
//   radiative_transfer/root.zig after RTM config preparation                                                  |
//                                                                                                             |
// exported by                                                                                                 |
//   radiative_transfer/root.zig under the labos namespace                                                     |
//                                                                                                             |
// reference order                                                                                             |
//   zdisamar mirrors LabosModule.f90 layerBasedOrdersScattering: attenuation, PLM basis, RT_fc, surface,      |
//   scattering orders, reflectance, then requested weighting functions.                                       |
//                                                                                                             |
// main paths                                                                                                  |
//   execute                                                                                                   |
//     -> executeWithWorkspace                                                                                 |
//        -> directSurfaceOnlyResolvedWithWorkspace  when scattering is disabled                               |
//        -> layerResolvedLabosWithWorkspace         when input has RT layers                                  |
//        -> singleLayerLabos                        when scalar layer fields are used                         |
//                                                                                                             |
// layer-resolved path                                                                                         |
//   1. fill attenuation                                                                                       |
//   2. loop retained Fourier terms:                                                                           |
//        Plm basis                                                                                            |
//          -> RT_fc                                                                                           |
//          -> surface matrix                                                                                  |
//          -> UD_fc / UDsumLocal_fc                                                                           |
//          -> rho_m                                                                                           |
//   3. add Fourier-weighted rho_m into total reflectance                                                      |
//   4. calculate requested Jacobians                                                                          |
//                                                                                                             |
// reference names                                                                                             |
//   RT_fc         : layer reflection/transmission matrices                                                    |
//   UD_fc         : radiation fields from scattering orders                                                   |
//   UDsumLocal_fc : local source sums used by integrated-source Jacobians                                     |
//   iFourier      : Fourier index                                                                             |
//   rho_m         : reflectance coefficient before Fourier weighting                                          |
//   rho           : top-of-atmosphere reflectance                                                             |
//   c_m           : Fourier weight                                                                            |
//                                                                                                             |
// memory                                                                                                      |
//   workspace is caller-owned scratch memory reused across wavelength samples                                 |
//   layer math lives in attenuation.zig, layers.zig, orders.zig, reflectance.zig                              |
// ------------------------------------------------------------------------------------------------------------|
const math = std.math;
const Geometry = basis.Geometry;
const LayerRT = basis.LayerRT;
const fillAttenuationDynamicWithGrid = attenuation.fillAttenuationDynamicWithGrid;
const fillAttenuationTangentDynamic = attenuation.fillAttenuationTangentDynamic;
const fillSurface = layers_mod.fillSurface;
const calcRTlayers = layers_mod.calcRTlayers;
const calcRTlayersIntoWithBasis = layers_mod.calcRTlayersIntoWithBasis;
const calcRTlayersTangentIntoWithBasis = layers_mod.calcRTlayersTangentIntoWithBasis;
const fillLayerEffectiveScatteringSuffixes = layers_mod.fillLayerEffectiveScatteringSuffixes;
const fillLayerPhaseMaxIndices = layers_mod.fillLayerPhaseMaxIndices;
const calcReflectance = reflectance_mod.calcReflectance;
const calcIntegratedReflectanceWithBasis = reflectance_mod.calcIntegratedReflectanceWithBasis;
const calcAerosolOpticalDepthWeightingWithBasis = reflectance_mod.calcAerosolOpticalDepthWeightingWithBasis;
const calcAerosolLayerPressureShiftWeightingWithBasis = reflectance_mod.calcAerosolLayerPressureShiftWeightingWithBasis;
const calcAerosolDerivativeWeightingWithBasis = reflectance_mod.calcAerosolDerivativeWeightingWithBasis;
const fillAdjacentLayerPhaseMaxIndices = reflectance_mod.fillAdjacentLayerPhaseMaxIndices;
const resolvedFourierMax = reflectance_mod.resolvedFourierMax;
const resolvedPhaseCoefficientMax = reflectance_mod.resolvedPhaseCoefficientMax;
const totalScatteringOpticalDepth = reflectance_mod.totalScatteringOpticalDepth;

// LabosComputation -------------------------------------------------------------------------------------------|
// One LABOS solve before it is copied into ForwardResult.                                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] reflectance : f64                                                                                  |
// [ 8..31] jacobian    : [3]f64                                                                               |
//          |----- [ 8..15] jacobian[0]                                                                        |
//          |----- [16..23] jacobian[1]                                                                        |
//          |----- [24..31] jacobian[2]                                                                        |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 32 B (0.031 KiB); total = per instance * live instance count                      |
const LabosComputation = struct {
    reflectance: f64,
    jacobian: jacobian.Vector = jacobian.zero(),
};
// ------------------------------------------------------------------------------------------------------------|

// DirectSurfaceOnlyComputation -------------------------------------------------------------------------------|
// Direct-surface result before optional Jacobian packing.                                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] reflectance             : f64                                                                      |
// [ 8..15] surface_albedo_tangent  : f64                                                                      |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count                      |
const DirectSurfaceOnlyComputation = struct {
    reflectance: f64,
    surface_albedo_tangent: f64,
};
// ------------------------------------------------------------------------------------------------------------|

fn directSurfaceOnly(
    input: common.ForwardInput,
    compute_surface_albedo_tangent: bool,
) DirectSurfaceOnlyComputation {
    // directSurfaceOnly --------------------------------------------------------------------------------------|
    // Scalar direct-surface path. Steps:                                                                      |
    //                                                                                                         |
    //   1. calculate direct path through total optical depth                                                  |
    //   2. multiply by surface albedo                                                                         |
    //   3. return reflectance and optional surface-albedo Jacobian                                            |
    //                                                                                                         |
    // math                                                                                                    |
    //   direct path = exp(-tau / mu0) * exp(-tau / muv)                                                       |
    //   reflectance = surface_albedo * direct path                                                            |
    //                                                                                                         |
    // tau : total optical depth                                                                               |
    // mu0 : solar zenith cosine                                                                               |
    // muv : view zenith cosine                                                                                |
    // --------------------------------------------------------------------------------------------------------|

    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);

    const direct = math.exp(-input.optical_depth / mu0) * math.exp(-input.optical_depth / muv);

    const reflectance = input.surface_albedo * direct;
    const should_report_surface_albedo =
        compute_surface_albedo_tangent and
        reflectance >= 0.0 and
        reflectance < 2.0;
    const surface_albedo_tangent = if (should_report_surface_albedo) direct else 0.0;

    return .{
        .reflectance = math.clamp(reflectance, 0.0, 2.0),
        .surface_albedo_tangent = surface_albedo_tangent,
    };
}

fn directSurfaceOnlyResolvedWithWorkspace(
    allocator: std.mem.Allocator,
    input: common.ForwardInput,
    controls: common.RadiativeTransferControls,
    workspace: ?*workspace_mod.Workspace,
    compute_surface_albedo_tangent: bool,
) common.ExecuteError!DirectSurfaceOnlyComputation {
    // directSurfaceOnlyResolvedWithWorkspace -----------------------------------------------------------------|
    // Direct-surface path for layer-resolved input. Steps:                                                    |
    //                                                                                                         |
    //   1. build the same geometry and attenuation table as the scattering path                               |
    //   2. skip RT layer scattering orders because scattering is disabled                                     |
    //   3. multiply surface reflection by solar and view transmittance                                        |
    //   4. return reflectance and optional surface-albedo Jacobian                                            |
    //                                                                                                         |
    // math                                                                                                    |
    //   path = T_sun(top -> surface) * product of view-layer transmittances                                   |
    //   direct reflectance = surface.R(view, sun) * path                                                      |
    // --------------------------------------------------------------------------------------------------------|

    if (input.layers.len == 0) return directSurfaceOnly(input, compute_surface_albedo_tangent);

    // Keep the same angle/index layout as the scattering path.
    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);

    var owned_geo: Geometry = undefined;
    const geo = if (workspace) |scratch|
        scratch.geometry(controls.nGauss(), mu0, muv)
    else choose_owned_geometry: {
        owned_geo = Geometry.init(controls.nGauss(), mu0, muv);
        break :choose_owned_geometry &owned_geo;
    };

    // Direct reflection still needs Beer-Lambert survival through the layers.
    const owned_atten = workspace == null;
    var atten: attenuation.DynamicAttenArray = undefined;
    if (workspace) |scratch| {
        atten = try scratch.attenuation(
            input.layers,
            input.pseudo_spherical_grid,
            geo,
            controls.use_spherical_correction,
        );
    } else {
        atten = try fillAttenuationDynamicWithGrid(
            allocator,
            input.layers,
            input.pseudo_spherical_grid,
            geo,
            controls.use_spherical_correction,
        );
    }
    defer if (owned_atten) atten.deinit();

    // View and solar rays are stored as extra directions in Geometry.
    const view_idx = geo.viewIdx();
    const solar_idx = geo.n_gauss + 1;

    const surface = fillSurface(0, input.surface_albedo, geo);

    // The view ray climbs one layer at a time. The solar table already stores
    // top-to-surface transmittance.
    var upward_path: f64 = 1.0;
    for (1..input.layers.len + 1) |ilevel| upward_path *= atten.get(view_idx, ilevel - 1, ilevel);

    const path = atten.get(solar_idx, input.layers.len, 0) * upward_path;

    const reflectance = surface.R.get(view_idx, solar_idx) * path;

    // Once reflectance is clamped outside [0,2], the albedo tangent should not
    // report sensitivity from the unclamped expression.
    const should_report_surface_albedo =
        compute_surface_albedo_tangent and
        reflectance >= 0.0 and
        reflectance < 2.0;
    const surface_albedo_tangent = if (should_report_surface_albedo) choose_surface_tangent: {
        const surface_derivative = fillSurface(0, 1.0, geo);
        break :choose_surface_tangent surface_derivative.R.get(view_idx, solar_idx) * path;
    } else 0.0;

    return .{
        .reflectance = math.clamp(reflectance, 0.0, 2.0),
        .surface_albedo_tangent = surface_albedo_tangent,
    };
}

pub fn execute(
    allocator: std.mem.Allocator,
    rtm_config: common.SolveConfig,
    input: common.ForwardInput,
) common.ExecuteError!common.ForwardResult {
    // execute ------------------------------------------------------------------------------------------------|
    // Allocation-owning LABOS entry point.                                                                    |
    // Passes null workspace so executeWithWorkspace allocates its temporary memory.                           |
    // --------------------------------------------------------------------------------------------------------|

    return executeWithWorkspace(allocator, rtm_config, input, null);
}

pub fn executeWithWorkspace(
    allocator: std.mem.Allocator,
    rtm_config: common.SolveConfig,
    input: common.ForwardInput,
    workspace: ?*workspace_mod.Workspace,
) common.ExecuteError!common.ForwardResult {
    // executeWithWorkspace -----------------------------------------------------------------------------------|
    // Called once per high-resolution forward sample after RTM config preparation. Steps:                     |
    //                                                                                                         |
    //   1. choose the cheapest LABOS path that still matches the requested physics                            |
    //   2. return reflectance and the requested Jacobian                                                      |
    //                                                                                                         |
    // path choice                                                                                             |
    // controls.scattering == none -> direct surface reflection                                                |
    // input.layers.len > 0       -> layer-resolved LABOS Fourier loop                                         |
    // otherwise                  -> scalar input converted to one LayerInput                                  |
    //                                                                                                         |
    // hot path                                                                                                |
    // keep dispatch cheap; real work is in the selected LABOS path                                            |
    // pass workspace through so lower layers can reuse scratch memory                                         |
    //                                                                                                         |
    // boundary                                                                                                |
    // no solver dispatch, file I/O, input parsing, or hidden global state                                     |
    // --------------------------------------------------------------------------------------------------------|

    // SolveConfig preparation has already validated the controls and derivative
    // state. This function only chooses the concrete LABOS calculation path.
    const controls = rtm_config.rtm_controls;
    const compute_jacobian = rtm_config.derivative_mode != .none;
    const wants_surface_albedo =
        compute_jacobian and
        jacobian.includes(rtm_config.derivative_state_mask, .surface_albedo);

    // Pick the smallest calculation that still matches the requested physics.
    const computation = choose_labos_path: {
        if (controls.scattering == .none) {
            const direct = try directSurfaceOnlyResolvedWithWorkspace(
                allocator,
                input,
                controls,
                workspace,
                wants_surface_albedo,
            );

            // With scattering disabled, the only supported derivative here is
            // surface albedo.
            var direct_jacobian = jacobian.zero();
            if (wants_surface_albedo) {
                jacobian.set(&direct_jacobian, .surface_albedo, direct.surface_albedo_tangent);
            }

            break :choose_labos_path LabosComputation{
                .reflectance = direct.reflectance,
                .jacobian = direct_jacobian,
            };
        }

        if (input.layers.len > 0) {
            break :choose_labos_path try layerResolvedLabosWithWorkspace(
                allocator,
                input,
                controls,
                compute_jacobian,
                rtm_config.derivative_state_mask,
                workspace,
            );
        }

        break :choose_labos_path try singleLayerLabos(
            allocator,
            input,
            controls,
            compute_jacobian,
            rtm_config.derivative_state_mask,
        );
    };

    return .{
        .toa_reflectance_factor = computation.reflectance,
        .jacobian = switch (rtm_config.derivative_mode) {
            .none => null,
            .semi_analytical => computation.jacobian,
        },
    };
}

fn layerResolvedLabosWithWorkspace(
    allocator: std.mem.Allocator,
    input: common.ForwardInput,
    controls: common.RadiativeTransferControls,
    compute_jacobian: bool,
    derivative_state_mask: jacobian.StateMask,
    workspace: ?*workspace_mod.Workspace,
) common.ExecuteError!LabosComputation {
    // layerResolvedLabosWithWorkspace ------------------------------------------------------------------------|
    // Runs layer-resolved LABOS transport for one high-resolution wavelength. Steps:                          |
    //                                                                                                         |
    //   1. build attenuation for this geometry and spherical-correction setting                               |
    //   2. loop retained Fourier terms:                                                                       |
    //        Plm basis                                                                                        |
    //          -> RT_fc                                                                                       |
    //          -> UD_fc / UDsumLocal_fc                                                                       |
    //          -> Fourier reflectance term                                                                    |
    //   3. add c_m * rho_m into total reflectance rho                                                         |
    //   4. add requested surface, aerosol-depth, and aerosol-pressure Jacobians                               |
    //   5. stop when the Fourier tail is below the threshold                                                  |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : every retained Fourier term                                                                |
    //   costly   : Plm basis                                                                                  |
    //              RT_fc build                                                                                |
    //              scattering-order propagation                                                               |
    //              reflectance integral                                                                       |
    //   Jacobian : aerosol weighting, only when requested                                                     |
    //   memory   : workspace buffers reused when this config allows                                           |
    //                                                                                                         |
    // calls                                                                                                   |
    //   calcRTlayersIntoWithBasis                                                                             |
    //   ordersScat*                                                                                           |
    //   calcIntegratedReflectanceWithBasis or calcReflectance                                                 |
    //                                                                                                         |
    // math                                                                                                    |
    //   total reflectance += Fourier weight * Fourier reflectance term                                        |
    //                                                                                                         |
    //   Fourier weight                                                                                        |
    //     = 1                                      when m = 0                                                 |
    //     = 2 * cos(m * relative_azimuth)          when m > 0                                                 |
    //                                                                                                         |
    //   m : Fourier index                                                                                     |
    // --------------------------------------------------------------------------------------------------------|

    const nlayer = input.layers.len;
    if (nlayer == 0) return .{ .reflectance = 0.0 };

    // Integrated-source reflectance needs source values at every level.
    // It can use explicit source_interfaces or the RTM quadrature grid.
    const use_integrated_source =
        controls.integrate_source_function and
        nlayer > 1 and
        (input.source_interfaces.len == nlayer + 1 or
            input.rtm_quadrature.isValidFor(input.layers.len));

    // The pseudo-spherical derivative path is implemented for integrated
    // source weighting. The non-integrated tangent rtm_config rejects it here.
    if (compute_jacobian and !use_integrated_source and controls.use_spherical_correction) {
        return error.UnsupportedDerivativeMode;
    }

    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);

    // Geometry holds Gaussian quadrature directions plus view and solar rays.
    var owned_geo: Geometry = undefined;
    const geo = if (workspace) |scratch|
        scratch.geometry(controls.nGauss(), mu0, muv)
    else choose_owned_geometry: {
        owned_geo = Geometry.init(controls.nGauss(), mu0, muv);
        break :choose_owned_geometry &owned_geo;
    };

    // Integrated-source reflectance only reads adjacent-layer and top-to-level
    // transmittance. With a workspace, that smaller table is enough. The
    // non-integrated tangent rtm_config still needs attenuation for any direction
    // and any pair of levels, so it keeps the full table.
    var runtime_atten: ?attenuation.RuntimeAttenArray = null;
    var dynamic_atten: ?attenuation.DynamicAttenArray = null;
    if (workspace) |scratch| {
        if (use_integrated_source) {
            runtime_atten = try scratch.runtimeAttenuation(
                input.layers,
                input.pseudo_spherical_grid,
                geo,
                controls.use_spherical_correction,
            );
        } else {
            dynamic_atten = try scratch.attenuation(
                input.layers,
                input.pseudo_spherical_grid,
                geo,
                controls.use_spherical_correction,
            );
        }
    } else {
        dynamic_atten = try fillAttenuationDynamicWithGrid(
            allocator,
            input.layers,
            input.pseudo_spherical_grid,
            geo,
            controls.use_spherical_correction,
        );
    }
    defer if (workspace == null) if (dynamic_atten) |*atten| atten.deinit();

    // RT_fc uses one surface slot plus one slot for each optical layer.
    const rt = if (workspace) |scratch|
        try scratch.layerRt(nlayer + 1)
    else choose_owned_rt: {
        const owned_rt = try allocator.alloc(LayerRT, nlayer + 1);
        break :choose_owned_rt owned_rt;
    };
    defer if (workspace == null) allocator.free(rt);

    // The loop bounds come from the actual layer optics and phase support.
    const num_orders_max: usize = @intCast(
        controls.resolvedNumOrdersMax(totalScatteringOpticalDepth(input.layers)),
    );
    const fourier_max = resolvedFourierMax(input, controls);
    const phase_max = resolvedPhaseCoefficientMax(input);
    const plm_cache_max = @min(phase_max, fourier_max);
    const phase_suffix_stride = plm_cache_max + 1;

    // Only requested derivative states are accumulated.
    const wants_surface_albedo =
        compute_jacobian and
        jacobian.includes(derivative_state_mask, .surface_albedo);
    const wants_aerosol_optical_depth =
        compute_jacobian and
        jacobian.includes(derivative_state_mask, .aerosol_optical_depth);
    const wants_aerosol_layer_mid_pressure =
        compute_jacobian and
        jacobian.includes(derivative_state_mask, .aerosol_layer_mid_pressure_hpa);

    var reflectance: f64 = 0.0;
    var surface_albedo_tangent: f64 = 0.0;
    var aerosol_optical_depth_tangent: f64 = 0.0;
    var aerosol_layer_mid_pressure_tangent: f64 = 0.0;

    // Integrated-source aerosol Jacobians need UDsumLocal_fc-style local
    // source sums from orders.zig. Plain reflectance only needs UD_fc.
    // Do not ask orders.zig to keep local source sums unless a Jacobian will
    // read them later.
    const needs_order_local_sum = use_integrated_source and compute_jacobian;
    var owned_orders_workspace: ?orders_mod.OrdersWorkspace = null;
    defer if (owned_orders_workspace) |*orders_workspace| orders_workspace.deinit();

    var orders_workspace: *orders_mod.OrdersWorkspace = undefined;
    if (workspace) |scratch| {
        orders_workspace = try scratch.ordersWorkspace(nlayer + 1, needs_order_local_sum);
    } else {
        owned_orders_workspace = try orders_mod.OrdersWorkspace.initWithLocalSumStorage(
            allocator,
            nlayer + 1,
            needs_order_local_sum,
        );
        orders_workspace = &(owned_orders_workspace.?);
    }

    // calcRTlayersIntoWithBasis saves the phase row for each RT layer while it
    // builds RT_fc. Integrated-source reflectance can reuse that row for a
    // matching source level. layer_phase_row_valid is false when the layer was
    // skipped and the saved row must not be read.
    var layer_phase_rows: ?[]basis.PhaseKernelRow = null;
    var layer_phase_row_valid: ?[]bool = null;
    if (use_integrated_source) {
        if (workspace) |scratch| {
            layer_phase_rows = try scratch.phaseRowCache(nlayer + 1);
            layer_phase_row_valid = try scratch.phaseRowValid(nlayer + 1);
        } else {
            layer_phase_rows = try allocator.alloc(basis.PhaseKernelRow, nlayer + 1);
            layer_phase_row_valid = try allocator.alloc(bool, nlayer + 1);
        }
    }

    defer if (workspace == null) if (layer_phase_rows) |cache| allocator.free(cache);
    defer if (workspace == null) if (layer_phase_row_valid) |valid| allocator.free(valid);

    // The RT layer builder and integrated-source reflectance both need the
    // highest useful phase coefficient per layer. Compute it once per solve.
    var layer_phase_max_indices: ?[]usize = null;
    if (workspace) |scratch| {
        const indices = try scratch.layerPhaseMaxIndices(nlayer);
        fillLayerPhaseMaxIndices(indices, input.layers);
        layer_phase_max_indices = indices;
    }

    // For each layer and Fourier term, this stores the largest remaining phase
    // coefficient used by layer doubling: suffix_m = max_{l>=m} |beta_l|/(2l+1).
    // beta_l is the layer phase coefficient at order l.
    var layer_effective_scattering_suffixes: ?[]f64 = null;
    if (workspace) |scratch| {
        if (layer_phase_max_indices) |indices| {
            const suffixes = try scratch.layerEffectiveScatteringSuffix(
                nlayer,
                phase_suffix_stride,
            );
            fillLayerEffectiveScatteringSuffixes(
                suffixes,
                input.layers,
                indices,
                phase_suffix_stride,
            );
            layer_effective_scattering_suffixes = suffixes;
        }
    }

    // Integrated-source reflectance is evaluated at level interfaces, so it
    // needs the phase limit from the layers touching each interface.
    var adjacent_layer_phase_max_indices: ?[]usize = null;
    if (workspace) |scratch| {
        if (layer_phase_max_indices) |layer_indices| {
            const indices = try scratch.sourcePhaseMaxIndices(nlayer + 1);
            fillAdjacentLayerPhaseMaxIndices(indices, layer_indices);
            adjacent_layer_phase_max_indices = indices;
        }
    }

    for (0..fourier_max + 1) |i_fourier| {
        var stop_fourier_loop = false;
        {

            // One Fourier term follows the reference order:
            // Plm basis -> RT_fc -> surface -> UD_fc -> refl_fc -> sum.

            // instrumentation: trace zone: Fourier term ------------------------------------------------------|
            // captures: one LABOS Fourier term wall time and index                                            |
            // why: expose which Fourier orders dominate reflectance and tangent work.                         |
            const fourier_zone = Trace.deepStaticZone(@src(), "labos.fourier_loop");
            fourier_zone.value(@intCast(i_fourier));
            defer fourier_zone.end();

            // instrumentation: trace counter -----------------------------------------------------------------|
            // captures: evaluated Fourier term count                                                          |
            // why: compare threshold pruning against actual term count.                                       |
            Trace.plotU("fourier_terms", 1);
            // end instrumentation: trace counter -------------------------------------------------------------|

            // Plm depends on Fourier order and geometry, not on layer, so one
            // basis is reused for all layers in this Fourier term.
            var owned_plm_basis: basis.FourierPlmBasis = undefined;
            const plm_basis = plm_basis: {

                // instrumentation: trace zone: PLM basis -----------------------------------------------------|
                // captures: PLM basis preparation wall time                                                   |
                // why: separate Fourier basis setup from RT layer and order propagation.                      |
                const zone = Trace.deepStaticZone(@src(), "labos.plm_basis");
                defer zone.end();
                break :plm_basis if (workspace) |scratch| choose_workspace_plm: {
                    break :choose_workspace_plm try scratch.fourierPlmBasis(
                        i_fourier,
                        phase_max,
                        plm_cache_max,
                        geo,
                    );
                } else choose_owned_plm: {
                    owned_plm_basis = basis.FourierPlmBasis.init(i_fourier, phase_max, geo);
                    break :choose_owned_plm &owned_plm_basis;
                };
                // end instrumentation: trace zone: PLM basis -------------------------------------------------|

            };

            {

                // Build RT_fc for the surface/layer stack at this Fourier term
                // before order transport starts.

                // instrumentation: trace zone: RT layer build ------------------------------------------------|
                // captures: per-Fourier RT layer construction wall time                                       |
                // why: isolate phase matrix/layer doubling cost before order propagation.                     |
                const zone = Trace.deepStaticZone(@src(), "labos.rt_layer_build");
                defer zone.end();
                calcRTlayersIntoWithBasis(
                    rt,
                    input.layers,
                    i_fourier,
                    geo,
                    controls,
                    plm_basis,
                    layer_phase_max_indices,
                    layer_effective_scattering_suffixes,
                    phase_suffix_stride,
                    layer_phase_rows,
                    layer_phase_row_valid,
                    if (workspace != null) orders_workspace.rt_active else null,
                );
                // end instrumentation: trace zone: RT layer build --------------------------------------------|

            }

            // Surface reflection is represented as layer index 0, matching the
            // reference RT layer convention.
            rt[0] = fillSurface(i_fourier, input.surface_albedo, geo);
            if (workspace != null) {
                orders_workspace.rt_active[0] = i_fourier == 0 and input.surface_albedo != 0.0;
            }

            const orders_result = orders_result: {

                // instrumentation: trace zone: scattering orders ---------------------------------------------|
                // captures: scattering-order propagation wall time                                            |
                // why: keep multiple-scattering transport separate from layer setup.                          |
                const zone = Trace.deepStaticZone(@src(), "labos.orders.total");
                defer zone.end();
                break :orders_result if (use_integrated_source) choose_integrated_orders: {
                    if (runtime_atten) |*atten| {

                        // Workspace runs pass orders.zig the layers that are
                        // active for this Fourier term. That list is filled
                        // while RT_fc is built.
                        if (compute_jacobian) {
                            break :choose_integrated_orders orders_mod.ordersScatIntoWithActiveLocalSum(
                                orders_workspace,
                                0,
                                nlayer,
                                geo,
                                atten,
                                rt,
                                controls,
                                num_orders_max,
                            );
                        }

                        break :choose_integrated_orders orders_mod.ordersScatIntoWithActive(
                            orders_workspace,
                            0,
                            nlayer,
                            geo,
                            atten,
                            rt,
                            controls,
                            num_orders_max,
                        );
                    }

                    if (dynamic_atten) |*atten| {

                        // Runs without a workspace let orders.zig decide the
                        // active layers again.
                        if (compute_jacobian) {
                            break :choose_integrated_orders orders_mod.ordersScatIntoWithLocalSum(
                                orders_workspace,
                                0,
                                nlayer,
                                geo,
                                atten,
                                rt,
                                controls,
                                num_orders_max,
                            );
                        }

                        break :choose_integrated_orders orders_mod.ordersScatInto(
                            orders_workspace,
                            0,
                            nlayer,
                            geo,
                            atten,
                            rt,
                            controls,
                            num_orders_max,
                        );
                    }

                    unreachable;
                } else choose_non_integrated_orders: {

                    // Non-integrated reflectance takes the transported UD_fc
                    // field directly from the scattering-order solve.
                    if (dynamic_atten) |*atten| {
                        break :choose_non_integrated_orders orders_mod.ordersScatTransportInto(
                            orders_workspace,
                            0,
                            nlayer,
                            geo,
                            atten,
                            rt,
                            controls,
                            num_orders_max,
                        );
                    }

                    unreachable;
                };
                // end instrumentation: trace zone: scattering orders -----------------------------------------|

            };

            // Convert the internal radiation field into rho_m, the
            // top-of-atmosphere reflectance coefficient for this Fourier term.
            const refl_fc = refl_fc: {

                // instrumentation: trace zone: reflectance integral ------------------------------------------|
                // captures: reflectance integral wall time                                                    |
                // why: separate order-field integration from Fourier loop setup.                              |
                const zone = Trace.deepStaticZone(@src(), "labos.reflectance_integral");
                defer zone.end();
                break :refl_fc if (use_integrated_source)
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
                        layer_phase_rows,
                        layer_phase_row_valid,
                    )
                else
                    calcReflectance(orders_result.ud, nlayer, geo);
                // end instrumentation: trace zone: reflectance integral --------------------------------------|

            };

            // c_0 = 1. For m > 0, c_m = 2 * cos(m * dphi).
            // This Fourier term is added to the total as rho += c_m * rho_m.
            const fourier_weight = if (i_fourier == 0)
                1.0
            else
                2.0 * math.cos(@as(f64, @floatFromInt(i_fourier)) * input.relative_azimuth_rad);

            // instrumentation: perturbation: reflectance term ------------------------------------------------|
            // captures: c_m * rho_m before adding it to total reflectance                                     |
            // why: test whether late Fourier terms can be pruned by tolerance.                                |
            const fourier_coord = Perturbation.Coord{ .fourier_index = @intCast(i_fourier) };
            const weighted_reflectance = Perturbation.scalar(
                .fourier_weighted_reflectance,
                fourier_coord,
                fourier_weight * refl_fc,
            );
            reflectance += weighted_reflectance;
            // end instrumentation: perturbation: reflectance term --------------------------------------------|

            if (wants_surface_albedo and i_fourier == 0) {

                // Surface albedo only contributes through the zero-Fourier
                // surface reflection term.
                surface_albedo_tangent += surfaceAlbedoWeightingFunction(orders_result.ud, geo);
            }

            // ------------------------------------------------------------------------------------------------|
            // ------------------------------------------------------------------------------------------------|
            // tradeoff: aerosol tangent Fourier cap                                                           |
            // Skip aerosol Jacobian Fourier terms above aerosol_tangent_order_cap when that cap is set.       |
            // ------------------------------------------------------------------------------------------------|
            // Aerosol weighting functions are Fourier-weighted just like reflectance. By default the cap is   |
            // null, so every retained Fourier term is evaluated. Fastmode research uses cap = 11 to reduce    |
            // derivative work while keeping the retrieval correction small enough for that config.            |
            const evaluate_aerosol_tangent =
                controls.performance_thresholds.shouldEvaluateAerosolTangent(i_fourier);
            const wants_aod_tangent = wants_aerosol_optical_depth and evaluate_aerosol_tangent;
            const wants_pressure_tangent = wants_aerosol_layer_mid_pressure and evaluate_aerosol_tangent;
            const use_paired_aerosol_weighting =
                use_integrated_source and wants_aod_tangent and wants_pressure_tangent;
            // end tradeoff: aerosol tangent Fourier cap ------------------------------------------------------|

            // The integrated-source rtm_config can calculate AOD and pressure
            // weighting in one shared pass when both are requested.
            if (use_paired_aerosol_weighting) {
                const tangent_refl_fc = tangent_refl_fc: {

                    // instrumentation: trace zone: paired aerosol weighting ----------------------------------|
                    // captures: paired aerosol tangent weighting wall time                                    |
                    // why: quantify derivative work shared by AOD and pressure states.                        |
                    const zone = Trace.deepStaticZone(@src(), "labos.reflectance.aerosol_weighting");
                    defer zone.end();
                    break :tangent_refl_fc calcAerosolDerivativeWeightingWithBasis(
                        input.layers,
                        input.rtm_quadrature,
                        orders_result.ud,
                        orders_result.ud_sum_local,
                        nlayer,
                        i_fourier,
                        controls.use_spherical_correction,
                        geo,
                        plm_basis,
                    );
                    // end instrumentation: trace zone: paired aerosol weighting ------------------------------|

                };

                // instrumentation: perturbation: paired aerosol tangents -------------------------------------|
                // captures: paired aerosol derivative Fourier contributions                                   |
                // why: test whether OE can ignore late tangent terms.                                         |
                aerosol_optical_depth_tangent += Perturbation.scalar(
                    .aerosol_aod_tangent,
                    .{
                        .fourier_index = @intCast(i_fourier),
                        .state_index = @intCast(@intFromEnum(jacobian.State.aerosol_optical_depth)),
                    },
                    fourier_weight * tangent_refl_fc.aerosol_optical_depth,
                );
                aerosol_layer_mid_pressure_tangent += Perturbation.scalar(
                    .aerosol_pressure_tangent,
                    .{
                        .fourier_index = @intCast(i_fourier),
                        .state_index = @intCast(@intFromEnum(jacobian.State.aerosol_layer_mid_pressure_hpa)),
                    },
                    fourier_weight * tangent_refl_fc.aerosol_layer_mid_pressure_hpa,
                );
                // end instrumentation: perturbation: paired aerosol tangents ---------------------------------|

            } else if (wants_aod_tangent) {
                const tangent_refl_fc = tangent_refl_fc: {

                    // instrumentation: trace zone: AOD weighting ---------------------------------------------|
                    // captures: aerosol optical-depth tangent weighting wall time                             |
                    // why: isolate derivative work for the AOD retrieval state.                               |
                    const zone = Trace.deepStaticZone(@src(), "labos.reflectance.aod_weighting");
                    defer zone.end();
                    break :tangent_refl_fc if (use_integrated_source)
                        calcAerosolOpticalDepthWeightingWithBasis(
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
                        )
                    else choose_non_integrated_aod_tangent: {
                        if (dynamic_atten) |*atten| {
                            break :choose_non_integrated_aod_tangent try nonIntegratedReflectanceTangent(
                                allocator,
                                input.layers,
                                .aerosol_optical_depth,
                                i_fourier,
                                geo,
                                atten,
                                rt,
                                controls,
                                plm_basis,
                                num_orders_max,
                            );
                        }
                        unreachable;
                    };
                    // end instrumentation: trace zone: AOD weighting -----------------------------------------|

                };

                // instrumentation: perturbation: AOD tangent -------------------------------------------------|
                // captures: AOD derivative Fourier contribution                                               |
                // why: test whether late AOD tangent work changes retrieval output.                           |
                aerosol_optical_depth_tangent += Perturbation.scalar(
                    .aerosol_aod_tangent,
                    .{
                        .fourier_index = @intCast(i_fourier),
                        .state_index = @intCast(@intFromEnum(jacobian.State.aerosol_optical_depth)),
                    },
                    fourier_weight * tangent_refl_fc,
                );
                // end instrumentation: perturbation: AOD tangent ---------------------------------------------|

            }
            if (!use_paired_aerosol_weighting and wants_pressure_tangent) {
                const pressure_tangent_refl_fc = pressure_tangent_refl_fc: {

                    // instrumentation: trace zone: pressure weighting ----------------------------------------|
                    // captures: aerosol pressure tangent weighting wall time                                  |
                    // why: isolate derivative work for pressure-placement retrieval.                          |
                    const zone = Trace.deepStaticZone(@src(), "labos.reflectance.pressure_weighting");
                    defer zone.end();
                    break :pressure_tangent_refl_fc if (use_integrated_source)
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
                    else choose_non_integrated_pressure_tangent: {
                        if (!hasLayerJacobian(input.layers, .aerosol_layer_mid_pressure_hpa)) {
                            return error.UnsupportedDerivativeMode;
                        }

                        if (dynamic_atten) |*atten| {
                            break :choose_non_integrated_pressure_tangent try nonIntegratedReflectanceTangent(
                                allocator,
                                input.layers,
                                .aerosol_layer_mid_pressure_hpa,
                                i_fourier,
                                geo,
                                atten,
                                rt,
                                controls,
                                plm_basis,
                                num_orders_max,
                            );
                        }
                        unreachable;
                    };
                    // end instrumentation: trace zone: pressure weighting ------------------------------------|

                };

                // instrumentation: perturbation: pressure tangent --------------------------------------------|
                // captures: aerosol-pressure derivative Fourier contribution                                  |
                // why: test whether late pressure tangent work changes retrieval output.                      |
                aerosol_layer_mid_pressure_tangent += Perturbation.scalar(
                    .aerosol_pressure_tangent,
                    .{
                        .fourier_index = @intCast(i_fourier),
                        .state_index = @intCast(@intFromEnum(jacobian.State.aerosol_layer_mid_pressure_hpa)),
                    },
                    fourier_weight * pressure_tangent_refl_fc,
                );
                // end instrumentation: perturbation: pressure tangent ----------------------------------------|

            }

            // ------------------------------------------------------------------------------------------------|
            // ------------------------------------------------------------------------------------------------|
            // tradeoff: Fourier tail stop                                                                     |
            // Stop the Fourier loop when the current term is below fourier_tail_reflectance_epsilon.          |
            // ------------------------------------------------------------------------------------------------|
            // The stop is only allowed after fourier_floor_scalar = 2. The reflectance epsilon is 3.0e-14 by  |
            // generic default and in O2 A. Lower epsilon keeps more Fourier terms; higher epsilon stops       |
            // sooner and drops more of the azimuthal tail.                                                    |
            //                                                                                                 |
            // tail_break = m >= fourier_floor_scalar and abs(rho_m) <= epsilon.                               |

            // instrumentation: telemetry and perturbation: tail break ----------------------------------------|
            // captures: Fourier tail-stop decision and term magnitude                                         |
            // why: compare current convergence threshold against forced early stops.                          |
            const tail_break_base =
                i_fourier >= controls.performance_thresholds.fourier_floor_scalar and
                @abs(refl_fc) <= controls.performance_thresholds.fourier_tail_reflectance_epsilon;
            const tail_break = Perturbation.decision(.fourier_tail_break, fourier_coord, tail_break_base);
            // end instrumentation: telemetry and perturbation: tail break ------------------------------------|

            // instrumentation: calculation telemetry: Fourier contribution -----------------------------------|
            // captures: Fourier contribution size and tail-break decision                                     |
            // why: compare tolerance pruning against each retained term.                                      |
            Telemetry.fourierContribution(
                i_fourier,
                fourier_weight,
                refl_fc,
                weighted_reflectance,
                controls.performance_thresholds.fourier_tail_reflectance_epsilon,
                tail_break,
            );
            // end instrumentation: calculation telemetry: Fourier contribution -------------------------------|

            if (tail_break) {

                // instrumentation: trace counter: tail break -------------------------------------------------|
                // captures: Fourier tail breaks                                                               |
                // why: validate the tail-pruning threshold against observed exits.                            |
                Trace.plotU("fourier_tail_breaks", 1);
                // end instrumentation: trace counter: tail break ---------------------------------------------|

                stop_fourier_loop = true;
            }
            // end tradeoff: Fourier tail stop ----------------------------------------------------------------|

            // end instrumentation: trace zone: Fourier term --------------------------------------------------|

        }

        if (stop_fourier_loop) break;
    }

    // Pack the public Jacobian vector after the Fourier loop. Unrequested
    // states remain zero.
    const result_jacobian = result_jacobian: {

        // instrumentation: trace zone: Jacobian assembly -----------------------------------------------------|
        // captures: final LABOS Jacobian assembly wall time                                                   |
        // why: distinguish derivative vector packing from Fourier/tangent evaluation.                         |
        const zone = Trace.deepStaticZone(@src(), "labos.reflectance.jacobian_assembly");
        defer zone.end();
        var assembled = jacobian.zero();
        jacobian.set(&assembled, .surface_albedo, surface_albedo_tangent);
        jacobian.set(&assembled, .aerosol_optical_depth, aerosol_optical_depth_tangent);
        jacobian.set(&assembled, .aerosol_layer_mid_pressure_hpa, aerosol_layer_mid_pressure_tangent);
        break :result_jacobian assembled;
        // end instrumentation: trace zone: Jacobian assembly -------------------------------------------------|

    };

    // Public reflectance is clamped to the range expected by forward-model
    // callers and validation outputs.
    const clamped_reflectance = math.clamp(reflectance, 0.0, 2.0);

    // instrumentation: calculation telemetry: LABOS result ---------------------------------------------------|
    // captures: final raw/clamped reflectance and Jacobian norm                                               |
    // why: find suspicious outputs or derivative-negligible samples.                                          |
    if (Telemetry.enabled) {
        var jacobian_norm1: f64 = 0.0;
        for (result_jacobian) |value| jacobian_norm1 += @abs(value);
        Telemetry.labosResult(reflectance, clamped_reflectance, jacobian_norm1);
    }
    // end instrumentation: calculation telemetry: LABOS result -----------------------------------------------|

    return .{
        .reflectance = clamped_reflectance,
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
    // nonIntegratedReflectanceTangent ------------------------------------------------------------------------|
    // Non-integrated Jacobian path for one retrieval state and Fourier term. Steps:                           |
    //                                                                                                         |
    //   1. build derivative attenuation                                                                       |
    //   2. build derivative RT_fc                                                                             |
    //   3. run tangent scattering-order transport                                                             |
    //   4. extract derivative reflectance from the tangent order field                                        |
    //                                                                                                         |
    // hot path                                                                                                |
    //   costly   : derivative attenuation, derivative RT_fc, tangent orders                                   |
    //   memory   : allocates tangent attenuation, RT_fc, and order fields                                     |
    //                                                                                                         |
    // math                                                                                                    |
    //   d reflectance / dx follows the linearized attenuation, RT_fc, orders, and final reflectance           |
    // --------------------------------------------------------------------------------------------------------|

    // Build d attenuation/dx and d RT_fc/dx, propagate them through
    // ordersScatTangent, then extract d rho_m/dx.
    var atten_tangent = try fillAttenuationTangentDynamic(
        allocator,
        layers,
        state,
        geo,
    );
    defer atten_tangent.deinit();

    const rt_tangent = try allocator.alloc(LayerRT, layers.len + 1);
    defer allocator.free(rt_tangent);

    // Tangent RT_fc mirrors the base RT_fc shape: surface slot plus layers.
    calcRTlayersTangentIntoWithBasis(
        rt_tangent,
        layers,
        state,
        i_fourier,
        geo,
        controls,
        plm_basis,
    );

    // Run the same scattering-order transport on the derivative fields.
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
    derivative_state_mask: jacobian.StateMask,
) common.ExecuteError!LabosComputation {
    // singleLayerLabos ---------------------------------------------------------------------------------------|
    // LABOS path for scalar optical depth and single-scattering albedo input. Steps:                          |
    //                                                                                                         |
    //   1. convert scalar input into one LayerInput                                                           |
    //   2. build fixed local attenuation arrays                                                               |
    //   3. loop Fourier terms through RT_fc, orders, and reflectance                                          |
    //   4. return reflectance and optional surface-albedo Jacobian                                            |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : retained Fourier terms                                                                     |
    //   costly   : phase basis, single-layer orders, reflectance extraction                                   |
    //   memory   : one-layer attenuation arrays and order workspace                                           |
    //                                                                                                         |
    // math                                                                                                    |
    //   same Fourier sum as the layer-resolved path, but with one optical layer                               |
    // --------------------------------------------------------------------------------------------------------|

    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const geo = Geometry.init(controls.nGauss(), mu0, muv);

    // Convert the scalar fields into the same layer shape used by the normal
    // LABOS path, so the downstream RT/order code stays shared.
    const layer = common.LayerInput{
        .optical_depth = input.optical_depth,
        .single_scatter_albedo = input.single_scatter_albedo,
        .solar_mu = mu0,
        .view_mu = muv,
        .phase = .{},
    };
    const layers = [_]common.LayerInput{layer};

    // A one-layer solve can use fixed local attenuation arrays.
    var layer_transmittance: [basis.max_nmutot]f64 = undefined;
    var top_to_level: [basis.max_nmutot * 2]f64 = undefined;
    const atten = attenuation.fillRuntimeAttenuationWithGridInBuffers(
        &layer_transmittance,
        &top_to_level,
        &layers,
        .{},
        &geo,
        controls.use_spherical_correction,
    );

    // Fourier and order limits still come from the same controls as the
    // layer-resolved path.
    const num_orders_max: usize = @intCast(controls.resolvedNumOrdersMax(layer.scattering_optical_depth));
    const fourier_max = resolvedFourierMax(input, controls);
    const wants_surface_albedo = compute_jacobian and jacobian.includes(derivative_state_mask, .surface_albedo);

    var reflectance: f64 = 0.0;
    var surface_albedo_tangent: f64 = 0.0;

    var orders_workspace = try orders_mod.OrdersWorkspace.initWithLocalSumStorage(allocator, 2, false);
    defer orders_workspace.deinit();

    // Same per-Fourier sequence as the layer-resolved path, with one optical
    // layer and the surface boundary.
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

        // c_0 = 1. For m > 0, c_m = 2 * cos(m * dphi).
        const fourier_weight = if (i_fourier == 0)
            1.0
        else
            2.0 * math.cos(@as(f64, @floatFromInt(i_fourier)) * input.relative_azimuth_rad);
        reflectance += fourier_weight * refl_fc;

        if (wants_surface_albedo and i_fourier == 0) {
            surface_albedo_tangent += surfaceAlbedoWeightingFunction(orders_result.ud, &geo);
        }
    }

    // The scalar one-layer rtm_config only fills the surface-albedo derivative.
    var result_jacobian = jacobian.zero();
    if (wants_surface_albedo) {
        jacobian.set(&result_jacobian, .surface_albedo, surface_albedo_tangent);
    }

    return .{
        .reflectance = math.clamp(reflectance, 0.0, 2.0),
        .jacobian = result_jacobian,
    };
}

fn hasLayerJacobian(layers: []const common.LayerInput, state: common.Jacobian.State) bool {
    // hasLayerJacobian ---------------------------------------------------------------------------------------|
    // Returns true when any layer carries the requested Jacobian state.                                       |
    // Non-integrated pressure weighting only makes sense with a pressure derivative.                          |
    // --------------------------------------------------------------------------------------------------------|

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
    // surfaceAlbedoWeightingFunction -------------------------------------------------------------------------|
    // Surface-albedo Jacobian for the zero-Fourier term.                                                      |
    // Uses the surface level of UD_fc. E is direct light; D is downward diffuse light.                        |
    //                                                                                                         |
    // math                                                                                                    |
    //   d reflectance / d albedo = (E_view + integral D_view dmu)                                             |
    //                              * (E_sun  + integral D_sun  dmu)                                           |
    // --------------------------------------------------------------------------------------------------------|

    const surface_level: usize = 0;
    const view_col: usize = 0;
    const solar_col: usize = 1;
    var diffuse_view: f64 = 0.0;
    var diffuse_solar: f64 = 0.0;

    // Add the diffuse part by integrating over Gaussian directions.
    for (0..geo.n_gauss) |i_gauss| {
        diffuse_view += ud[surface_level].D.col[view_col].get(i_gauss) * geo.w[i_gauss];
        diffuse_solar += ud[surface_level].D.col[solar_col].get(i_gauss) * geo.w[i_gauss];
    }

    // Direct view and solar terms are stored in UD_fc.E.
    const view_direct = ud[surface_level].E.get(geo.viewIdx());
    const solar_direct = ud[surface_level].E.get(geo.n_gauss + 1);

    return (view_direct + diffuse_view) * (solar_direct + diffuse_solar);
}
