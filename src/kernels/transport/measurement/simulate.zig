//! Purpose:
//!   Materialize measurement-space radiance, irradiance, reflectance, and
//!   optional Jacobian products from prepared transport input.
//!
//! Physics:
//!   Runs the transport executor across the resolved spectral grid, applies
//!   instrument integration and slit convolution, and reduces the results into
//!   summary and product-level outputs.
//!
//! Vendor:
//!   `measurement simulation` stage
//!
//! Design:
//!   The transport executor is kept separate from the measurement reduction so
//!   the same prepared state can feed summary and full-product materialization.
//!
//! Invariants:
//!   The transport workspace must be shape-compatible with the scene's sample
//!   count and the resolved transport layer count.
//!
//! Validation:
//!   Measurement-space summary and product tests.

const std = @import("std");
const SpectralChannel = @import("../../../model/Instrument.zig").SpectralChannel;
const Scene = @import("../../../model/Scene.zig").Scene;
const OpticsPreparation = @import("../../optics/preparation.zig");
const calibration = @import("../../spectra/calibration.zig");
const convolution = @import("../../spectra/convolution.zig");
const grid = @import("../../spectra/grid.zig");
const common = @import("../common.zig");
const Postprocess = @import("postprocess.zig");
const SamplePlan = @import("sample_plan.zig");
const SpectralEval = @import("spectral_eval.zig");
const Types = @import("types.zig");
const Workspace = @import("workspace.zig");

const Allocator = std.mem.Allocator;
const max_summary_samples: u32 = 128;

/// Purpose:
///   Execute the transport solver across the scene spectral grid.
///
/// Physics:
///   Materializes radiance, irradiance, reflectance, and optional Jacobian
///   arrays after route-specific integration and calibration.
///
/// Inputs:
///   `scene` defines the resolved spectral grid, `route` selects the transport
///   family, `prepared` carries the optical state, and `buffers` provides the
///   reusable scratch slices.
///
/// Outputs:
///   Returns measurement-space summary statistics and fills the product
///   buffers in place.
///
/// Validation:
///   Measurement-space summary and product tests.
pub fn simulateInternal(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    providers: Types.ProviderBindings,
    buffers: Workspace.Buffers,
    evaluation_cache: *SpectralEval.SpectralEvaluationCache,
) Workspace.Error!Types.MeasurementSpaceSummary {
    try scene.validate();
    const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
    try Workspace.validateBuffers(sample_count, buffers);

    const spectral_grid: grid.SpectralGrid = .{
        .start_nm = scene.spectral_grid.start_nm,
        .end_nm = scene.spectral_grid.end_nm,
        .sample_count = scene.spectral_grid.sample_count,
    };
    const resolved_axis: grid.ResolvedAxis = .{
        .base = spectral_grid,
        .explicit_wavelengths_nm = scene.observation_model.measured_wavelengths_nm,
    };
    try resolved_axis.validate();

    const radiance_calibration = providers.instrument.calibrationForScene(scene, .radiance);
    const irradiance_calibration = providers.instrument.calibrationForScene(scene, .irradiance);
    const radiance_slit_kernel = providers.instrument.slitKernelForScene(scene, .radiance);
    const irradiance_slit_kernel = providers.instrument.slitKernelForScene(scene, .irradiance);
    const uses_integrated_radiance_sampling = providers.instrument.usesIntegratedSampling(scene, .radiance);
    const uses_integrated_irradiance_sampling = providers.instrument.usesIntegratedSampling(scene, .irradiance);
    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const safe_span = if (span_nm <= 0.0) 1.0 else span_nm;
    const sample_plans = try SamplePlan.buildSamplePlans(
        allocator,
        scene,
        prepared,
        &resolved_axis,
        radiance_calibration,
        irradiance_calibration,
        providers,
    );
    defer allocator.free(sample_plans);
    const forward_misses = try SamplePlan.collectUniqueForwardMisses(
        allocator,
        sample_plans,
    );
    defer allocator.free(forward_misses);
    try SpectralEval.prefetchForwardSamples(
        allocator,
        scene,
        route,
        prepared,
        providers,
        safe_span,
        forward_misses,
        evaluation_cache,
    );

    var radiance_sum: f64 = 0.0;
    var irradiance_sum: f64 = 0.0;
    var reflectance_sum: f64 = 0.0;
    var noise_sum: f64 = 0.0;
    var jacobian_sum: f64 = 0.0;
    const transport_layer_count = Workspace.resolvedTransportLayerCount(route, prepared);
    if (buffers.layer_inputs.len < transport_layer_count or
        buffers.source_interfaces.len < transport_layer_count + 1 or
        buffers.rtm_quadrature_levels.len < transport_layer_count + 1 or
        buffers.pseudo_spherical_level_starts.len < transport_layer_count + 1)
    {
        return error.ShapeMismatch;
    }

    for (sample_plans, 0..) |plan, index| {
        const nominal_wavelength_nm = plan.nominal_wavelength_nm;
        buffers.wavelengths[index] = nominal_wavelength_nm;

        const integrated = try SpectralEval.integrateForwardAtNominal(
            allocator,
            scene,
            route,
            prepared,
            plan.radiance_wavelength_nm,
            safe_span,
            providers,
            buffers.layer_inputs[0..transport_layer_count],
            buffers.pseudo_spherical_layers,
            buffers.source_interfaces[0 .. transport_layer_count + 1],
            buffers.rtm_quadrature_levels[0 .. transport_layer_count + 1],
            buffers.pseudo_spherical_samples,
            buffers.pseudo_spherical_level_starts[0 .. transport_layer_count + 1],
            buffers.pseudo_spherical_level_altitudes[0 .. transport_layer_count + 1],
            evaluation_cache,
            &plan.radiance_integration,
        );
        buffers.scratch[index] = integrated.radiance;
        if (buffers.jacobian) |jacobian| jacobian[index] = integrated.jacobian;
    }
    if (uses_integrated_radiance_sampling) {
        // DECISION:
        //   Integrated sampling bypasses slit convolution because the
        //   instrument already performed the spectral integration.
        @memcpy(buffers.radiance, buffers.scratch);
    } else {
        try convolution.apply(buffers.scratch, radiance_slit_kernel[0..], buffers.radiance);
    }
    try Postprocess.applyChannelCorrections(
        scene,
        .radiance,
        radiance_calibration,
        prepared.depolarization_factor,
        buffers.wavelengths,
        buffers.radiance,
        buffers.scratch_aux,
    );
    for (sample_plans, 0..) |plan, index| {
        buffers.scratch[index] = try SpectralEval.integrateIrradianceAtNominal(
            scene,
            prepared,
            plan.irradiance_wavelength_nm,
            safe_span,
            evaluation_cache,
            &plan.irradiance_integration,
        );
    }
    if (uses_integrated_irradiance_sampling) {
        @memcpy(buffers.irradiance, buffers.scratch);
    } else {
        try convolution.apply(buffers.scratch, irradiance_slit_kernel[0..], buffers.irradiance);
    }
    try Postprocess.applyChannelCorrections(
        scene,
        .irradiance,
        irradiance_calibration,
        prepared.depolarization_factor,
        buffers.wavelengths,
        buffers.irradiance,
        buffers.scratch_aux,
    );
    try calibration.applyRingSpectrum(
        scene.observation_model.resolvedRingControls(),
        buffers.wavelengths,
        buffers.irradiance,
        buffers.radiance,
        buffers.scratch_aux,
    );
    const solar_cosine = scene.geometry.solarCosineAtAltitude(0.0);
    for (0..sample_count) |index| {
        buffers.reflectance[index] = (buffers.radiance[index] * std.math.pi) /
            @max(buffers.irradiance[index] * solar_cosine, 1e-9);
        radiance_sum += buffers.radiance[index];
        irradiance_sum += buffers.irradiance[index];
        reflectance_sum += buffers.reflectance[index];
    }

    const radiance_noise_sigma = if (buffers.radiance_noise_sigma) |sigma|
        sigma
    else if (buffers.noise_sigma) |sigma|
        sigma
    else if (buffers.reflectance_noise_sigma != null)
        buffers.scratch
    else
        null;
    if (radiance_noise_sigma) |sigma| {
        try Postprocess.materializeChannelSigma(providers, scene, .radiance, buffers.wavelengths, buffers.radiance, sigma);
    }
    if (buffers.noise_sigma) |noise_sigma| {
        const sigma = radiance_noise_sigma orelse return error.ShapeMismatch;
        if (noise_sigma.ptr != sigma.ptr) {
            @memcpy(noise_sigma, sigma);
        }
    }

    const irradiance_noise_sigma = if (buffers.irradiance_noise_sigma) |sigma|
        sigma
    else if (buffers.reflectance_noise_sigma != null)
        buffers.scratch_aux
    else
        null;
    if (irradiance_noise_sigma) |sigma| {
        try Postprocess.materializeChannelSigma(providers, scene, .irradiance, buffers.wavelengths, buffers.irradiance, sigma);
    }

    if (buffers.reflectance_noise_sigma) |reflectance_noise_sigma| {
        const radiance_sigma = radiance_noise_sigma orelse return error.ShapeMismatch;
        const irradiance_sigma = irradiance_noise_sigma orelse return error.ShapeMismatch;
        for (0..sample_count) |index| {
            const radiance_term = if (radiance_sigma.len == sample_count and buffers.radiance[index] > 0.0)
                buffers.reflectance[index] * (radiance_sigma[index] / @max(buffers.radiance[index], 1.0e-12))
            else
                0.0;
            const irradiance_term = if (irradiance_sigma.len == sample_count and buffers.irradiance[index] > 0.0)
                buffers.reflectance[index] * (irradiance_sigma[index] / @max(buffers.irradiance[index], 1.0e-12))
            else
                0.0;
            reflectance_noise_sigma[index] = std.math.sqrt(radiance_term * radiance_term + irradiance_term * irradiance_term);
        }
        try calibration.applyReflectanceCalibrationErrorSigma(
            scene.observation_model.resolvedReflectanceCalibration(),
            buffers.wavelengths,
            buffers.reflectance,
            reflectance_noise_sigma,
            buffers.scratch_aux,
        );
    }

    if (radiance_noise_sigma) |sigma| {
        for (sigma) |value| noise_sum += value;
    }

    var mean_jacobian: ?f64 = null;
    if (buffers.jacobian) |jacobian| {
        if (!uses_integrated_radiance_sampling) {
            try convolution.apply(jacobian, radiance_slit_kernel[0..], buffers.scratch);
            @memcpy(jacobian, buffers.scratch);
        }
        try Postprocess.applyChannelJacobianCorrections(
            scene,
            .radiance,
            radiance_calibration,
            prepared.depolarization_factor,
            buffers.wavelengths,
            jacobian,
            buffers.scratch_aux,
        );
        // DECISION:
        //   Ring synthesis uses the irradiance-only basis from the current
        //   forward model, so it does not change the routed radiance Jacobian.
        for (jacobian) |value| jacobian_sum += value;
        mean_jacobian = jacobian_sum / @as(f64, @floatFromInt(sample_count));
    }
    return .{
        .sample_count = @intCast(sample_count),
        .wavelength_start_nm = buffers.wavelengths[0],
        .wavelength_end_nm = buffers.wavelengths[sample_count - 1],
        .mean_radiance = radiance_sum / @as(f64, @floatFromInt(sample_count)),
        .mean_irradiance = irradiance_sum / @as(f64, @floatFromInt(sample_count)),
        .mean_reflectance = reflectance_sum / @as(f64, @floatFromInt(sample_count)),
        .mean_noise_sigma = if (radiance_noise_sigma != null)
            noise_sum / @as(f64, @floatFromInt(sample_count))
        else
            0.0,
        .mean_jacobian = mean_jacobian,
    };
}

pub fn simulate(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    providers: Types.ProviderBindings,
    buffers: Workspace.Buffers,
) Workspace.Error!Types.MeasurementSpaceSummary {
    var evaluation_cache = SpectralEval.SpectralEvaluationCache.init(allocator);
    defer evaluation_cache.deinit();
    evaluation_cache.reset();
    return simulateInternal(allocator, scene, route, prepared, providers, buffers, &evaluation_cache);
}

/// Purpose:
///   Materialize a summary-only measurement-space product.
pub fn simulateSummary(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    providers: Types.ProviderBindings,
) Workspace.Error!Types.MeasurementSpaceSummary {
    var workspace: Workspace.SummaryWorkspace = .{};
    defer workspace.deinit(allocator);
    return simulateSummaryWithWorkspace(allocator, &workspace, scene, route, prepared, providers);
}

/// Purpose:
///   Materialize a summary-only measurement-space product with reusable buffers.
pub fn simulateSummaryWithWorkspace(
    allocator: Allocator,
    workspace: *Workspace.SummaryWorkspace,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    providers: Types.ProviderBindings,
) Workspace.Error!Types.MeasurementSpaceSummary {
    var summary_scene = scene.*;
    // GOTCHA:
    //   Summary mode truncates very long spectral grids so it can stay
    //   lightweight while preserving the full-product path for complete runs.
    if (summary_scene.spectral_grid.sample_count > max_summary_samples) {
        summary_scene.spectral_grid.sample_count = max_summary_samples;
    }
    return simulateInternal(
        allocator,
        &summary_scene,
        route,
        prepared,
        providers,
        try workspace.buffers(allocator, &summary_scene, route, providers),
        try workspace.spectralCache(allocator),
    );
}
