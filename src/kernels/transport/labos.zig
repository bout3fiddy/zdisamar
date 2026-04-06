//! Purpose:
//!   Facade for the LABOS transport family.
//!
//! Physics:
//!   Orchestrates scalar LABOS transport by combining the basis algebra,
//!   attenuation, layer operators, orders-of-scattering recursion, and
//!   reflectance extraction stages.
//!
//! Vendor:
//!   LABOS transport family
//!
//! Design:
//!   The solver is kept as a thin entrypoint while the numerical stages live in
//!   sibling modules under `labos/`.
//!
//! Invariants:
//!   Public entrypoints and reflectance behavior remain stable while the
//!   internal stage layout is decomposed.
//!
//! Validation:
//!   See `tests/unit/transport_labos_test.zig` for smoke and scenario coverage.

const std = @import("std");
const math = std.math;
const common = @import("common.zig");
const derivatives = @import("derivatives.zig");

const basis = @import("labos/basis.zig");
const attenuation = @import("labos/attenuation.zig");
const layers_mod = @import("labos/layers.zig");
const orders_mod = @import("labos/orders.zig");
const reflectance_mod = @import("labos/reflectance.zig");
const phase_functions = @import("../optics/prepare/phase_functions.zig");

pub const max_gauss = basis.max_gauss;
pub const max_extra = basis.max_extra;
pub const max_nmutot = basis.max_nmutot;
pub const max_n2 = basis.max_n2;
pub const max_phase_coef = basis.max_phase_coef;

pub const Mat = basis.Mat;
pub const Vec = basis.Vec;
pub const Vec2 = basis.Vec2;
pub const Geometry = basis.Geometry;
pub const LayerRT = basis.LayerRT;
pub const UDField = basis.UDField;
pub const UDLocal = basis.UDLocal;
pub const AttenArray = attenuation.AttenArray;
pub const DynamicAttenArray = attenuation.DynamicAttenArray;

pub const smul = basis.smul;
pub const esmul = basis.esmul;
pub const semul = basis.semul;
pub const matAdd = basis.matAdd;
pub const qseries = basis.qseries;
pub const fillZplusZmin = basis.fillZplusZmin;
pub const PhaseKernel = basis.PhaseKernel;

pub const fillAttenuation = attenuation.fillAttenuation;
pub const fillAttenuationDynamic = attenuation.fillAttenuationDynamic;
pub const fillAttenuationDynamicWithGrid = attenuation.fillAttenuationDynamicWithGrid;

pub const calcRTlayersInto = layers_mod.calcRTlayersInto;
pub const calcRTlayersIntoWithBasis = layers_mod.calcRTlayersIntoWithBasis;
pub const calcRTlayers = layers_mod.calcRTlayers;
pub const fillSurface = layers_mod.fillSurface;

pub const dotGauss = orders_mod.dotGauss;

pub const calcReflectance = reflectance_mod.calcReflectance;
pub const calcIntegratedReflectance = reflectance_mod.calcIntegratedReflectance;
pub const calcIntegratedReflectanceWithBasis = reflectance_mod.calcIntegratedReflectanceWithBasis;
pub const resolvedFourierMax = reflectance_mod.resolvedFourierMax;
pub const resolvedPhaseCoefficientMax = reflectance_mod.resolvedPhaseCoefficientMax;
pub const totalScatteringOpticalDepth = reflectance_mod.totalScatteringOpticalDepth;

fn directSurfaceOnlyReflectance(input: common.ForwardInput) f64 {
    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const direct = math.exp(-input.optical_depth / mu0) * math.exp(-input.optical_depth / muv);
    return math.clamp(input.surface_albedo * direct, 0.0, 2.0);
}

fn directSurfaceOnlyReflectanceResolved(
    allocator: std.mem.Allocator,
    input: common.ForwardInput,
    controls: common.RtmControls,
) common.ExecuteError!f64 {
    if (input.layers.len == 0) return directSurfaceOnlyReflectance(input);

    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const n_gauss: usize = controls.nGauss();
    const geo = Geometry.init(n_gauss, mu0, muv);
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
    for (1..input.layers.len + 1) |ilevel| {
        upward_path *= atten.get(view_idx, ilevel - 1, ilevel);
    }

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

/// LABOS implementation for multi-layer atmospheres.
/// This keeps the vendor-shaped execution stages explicit while the heavy
/// numerical helpers live in sibling modules.
fn layerResolvedLabos(
    allocator: std.mem.Allocator,
    input: common.ForwardInput,
    controls: common.RtmControls,
) common.ExecuteError!f64 {
    const nlayer = input.layers.len;
    if (nlayer == 0) return 0.0;

    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const n_gauss: usize = controls.nGauss();
    const nlevel = nlayer + 1;

    const geo = Geometry.init(n_gauss, mu0, muv);
    var atten = try fillAttenuationDynamicWithGrid(
        allocator,
        input.layers,
        input.pseudo_spherical_grid,
        &geo,
        controls.use_spherical_correction,
    );
    defer atten.deinit();

    var rt = try allocator.alloc(LayerRT, nlevel);
    defer allocator.free(rt);

    const start_level: usize = 0;
    const end_level: usize = nlayer;
    const num_orders_max: usize = @intCast(controls.resolvedNumOrdersMax(totalScatteringOpticalDepth(input.layers)));
    const fourier_max = resolvedFourierMax(input, controls);
    const phase_max = resolvedPhaseCoefficientMax(input);
    // DECISION:
    //   Only use the integrated source-function carrier when the route
    //   supplies the aligned source interfaces or RTM quadrature grid.
    const use_integrated_source =
        controls.integrate_source_function and
        nlayer > 1 and
        (input.source_interfaces.len == nlevel or
            input.rtm_quadrature.isValidFor(input.layers.len));

    var reflectance: f64 = 0.0;
    var orders_workspace = try orders_mod.OrdersWorkspace.init(allocator, nlevel);
    defer orders_workspace.deinit();
    const layer_phase_kernels: ?[]basis.PhaseKernel = if (use_integrated_source)
        try allocator.alloc(basis.PhaseKernel, nlevel)
    else
        null;
    defer if (layer_phase_kernels) |cache| allocator.free(cache);
    const layer_phase_kernel_valid: ?[]bool = if (use_integrated_source)
        try allocator.alloc(bool, nlevel)
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
            start_level,
            end_level,
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
                end_level,
                i_fourier,
                &geo,
                &plm_basis,
                layer_phase_kernels,
                layer_phase_kernel_valid,
            )
        else
            calcReflectance(orders_result.ud, end_level, &geo);
        // PARITY:
        //   Fourier-0 carries the direct term; higher Fourier orders are
        //   weighted by the cosine of the relative azimuth.
        const fourier_weight = if (i_fourier == 0)
            1.0
        else
            2.0 * math.cos(@as(f64, @floatFromInt(i_fourier)) * input.relative_azimuth_rad);
        reflectance += fourier_weight * refl_fc;
    }

    return math.clamp(reflectance, 0.0, 2.0);
}

/// Simplified single-layer LABOS for backward compatibility when no layer data
/// is provided. Uses the bulk optical properties from ForwardInput.
fn singleLayerLabos(
    allocator: std.mem.Allocator,
    input: common.ForwardInput,
    controls: common.RtmControls,
) common.ExecuteError!f64 {
    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const n_gauss: usize = controls.nGauss();

    const geo = Geometry.init(n_gauss, mu0, muv);

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

test "labos execution supports semi-analytical derivatives but rejects plugin analytical mode" {
    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    const result = try execute(std.testing.allocator, route, .{
        .spectral_weight = 1.0,
        .air_mass_factor = 1.0,
    });

    try std.testing.expectEqual(common.TransportFamily.labos, result.family);
    try std.testing.expect(result.jacobian_column != null);
    try std.testing.expect(result.jacobian_column.? < 0.0);
    try std.testing.expectError(common.Error.UnsupportedDerivativeMode, common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .analytical_plugin,
    }));
}

test "labos single-layer produces bounded positive reflectance" {
    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    const result = try execute(std.testing.allocator, route, .{
        .mu0 = 0.6,
        .muv = 0.7,
        .optical_depth = 0.5,
        .single_scatter_albedo = 0.95,
        .surface_albedo = 0.05,
    });
    try std.testing.expect(result.toa_reflectance_factor >= 0.0);
    try std.testing.expect(result.toa_reflectance_factor <= 2.0);
}

test "labos multi-layer produces bounded positive reflectance" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.1,
            .single_scatter_albedo = 0.99,
            .solar_mu = 0.5,
            .view_mu = 0.6,
            .phase_coefficients = phase_functions.phaseCoefficientsFromLegacy(.{ 1.0, 0.5, 0.25, 0.125 }),
        },
        .{
            .optical_depth = 0.3,
            .single_scatter_albedo = 0.8,
            .solar_mu = 0.5,
            .view_mu = 0.6,
            .phase_coefficients = phase_functions.phaseCoefficientsFromLegacy(.{ 1.0, 0.3, 0.09, 0.027 }),
        },
        .{
            .optical_depth = 0.2,
            .single_scatter_albedo = 0.95,
            .solar_mu = 0.5,
            .view_mu = 0.6,
            .phase_coefficients = phase_functions.zeroPhaseCoefficients(),
        },
    };

    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    const result = try execute(std.testing.allocator, route, .{
        .mu0 = 0.5,
        .muv = 0.6,
        .optical_depth = 0.6,
        .single_scatter_albedo = 0.9,
        .surface_albedo = 0.05,
        .layers = &layers,
    });
    try std.testing.expect(result.toa_reflectance_factor >= 0.0);
    try std.testing.expect(result.toa_reflectance_factor <= 2.0);
}

test "labos geometry initializes Gauss points on (0,1)" {
    const geo = Geometry.init(3, 0.6, 0.7);
    try std.testing.expectEqual(@as(usize, 5), geo.nmutot);
    for (0..3) |i| {
        try std.testing.expect(geo.u[i] > 0.0);
        try std.testing.expect(geo.u[i] < 1.0);
    }
    try std.testing.expectApproxEqAbs(@as(f64, 0.7), geo.u[3], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.6), geo.u[4], 1e-12);
}

test "labos smul with zero matrices returns zero" {
    const n: usize = 4;
    const a = Mat.zero(n);
    const b = Mat.zero(n);
    const c = smul(n, 2, 1e-12, &a, &b);
    for (0..n * n) |i| {
        try std.testing.expectApproxEqAbs(@as(f64, 0.0), c.data[i], 1e-15);
    }
}

test "labos smul with identity matrix returns original (Gauss block)" {
    const n: usize = 4;
    const n_gauss: usize = 2;
    var a = Mat.identity(n);
    a.set(0, 0, 2.0);
    a.set(1, 1, 2.0);
    var b = Mat.zero(n);
    b.set(0, 0, 3.0);
    b.set(0, 1, 1.0);
    b.set(1, 0, 0.5);
    b.set(1, 1, 2.0);
    const c = smul(n, n_gauss, 1e-12, &a, &b);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), c.get(0, 0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), c.get(0, 1), 1e-12);
}

test "labos esmul scales rows by diagonal" {
    const n: usize = 3;
    var a = Mat.zero(n);
    a.set(0, 0, 1.0);
    a.set(0, 1, 2.0);
    a.set(1, 0, 3.0);
    a.set(1, 1, 4.0);
    var e = Vec.zero(n);
    e.set(0, 0.5);
    e.set(1, 2.0);
    const c = esmul(n, &e, &a);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), c.get(0, 0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), c.get(0, 1), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), c.get(1, 0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), c.get(1, 1), 1e-12);
}

test "labos attenuation is 1.0 for same level" {
    const layers = [_]common.LayerInput{.{
        .optical_depth = 0.5,
        .single_scatter_albedo = 0.9,
    }};
    const geo = Geometry.init(3, 0.6, 0.7);
    const atten = fillAttenuation(&layers, &geo, false);
    for (0..geo.nmutot) |imu| {
        try std.testing.expectApproxEqAbs(@as(f64, 1.0), atten.get(imu, 0, 0), 1e-12);
        try std.testing.expectApproxEqAbs(@as(f64, 1.0), atten.get(imu, 1, 1), 1e-12);
    }
}

test "labos attenuation decreases with optical depth" {
    const layers = [_]common.LayerInput{.{
        .optical_depth = 0.5,
        .single_scatter_albedo = 0.9,
    }};
    const geo = Geometry.init(3, 0.6, 0.7);
    const atten = fillAttenuation(&layers, &geo, false);
    for (0..geo.nmutot) |imu| {
        try std.testing.expect(atten.get(imu, 0, 1) < 1.0);
        try std.testing.expect(atten.get(imu, 0, 1) > 0.0);
    }
}

test "labos surface reflector has correct structure" {
    const geo = Geometry.init(3, 0.6, 0.7);
    const surf = fillSurface(0, 0.3, &geo);
    for (0..geo.nmutot) |i| {
        try std.testing.expect(surf.R.get(i, i) >= 0.0);
    }
    const surf1 = fillSurface(1, 0.3, &geo);
    for (0..geo.nmutot) |i| {
        for (0..geo.nmutot) |j| {
            try std.testing.expectApproxEqAbs(@as(f64, 0.0), surf1.R.get(i, j), 1e-15);
        }
    }
}

test "labos optically thin layer has small reflectance" {
    const layers = [_]common.LayerInput{.{
        .optical_depth = 0.001,
        .single_scatter_albedo = 0.9,
        .solar_mu = 0.5,
        .view_mu = 0.6,
        .phase_coefficients = phase_functions.zeroPhaseCoefficients(),
    }};
    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    const result = try execute(std.testing.allocator, route, .{
        .mu0 = 0.5,
        .muv = 0.6,
        .optical_depth = 0.001,
        .single_scatter_albedo = 0.9,
        .surface_albedo = 0.0,
        .layers = &layers,
    });
    try std.testing.expect(result.toa_reflectance_factor < 0.05);
    try std.testing.expect(result.toa_reflectance_factor >= 0.0);
}
