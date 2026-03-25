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
pub fn simulate(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    providers: Types.ProviderBindings,
    buffers: Workspace.Buffers,
) Workspace.Error!Types.MeasurementSpaceSummary {
    try scene.validate();
    const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
    try Workspace.validateBuffers(sample_count, buffers);
    var evaluation_cache = SpectralEval.SpectralEvaluationCache.init(allocator);
    defer evaluation_cache.deinit();

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

    for (0..sample_count) |index| {
        const nominal_wavelength_nm = try resolved_axis.sampleAt(@intCast(index));
        const evaluation_wavelength_nm = calibration.shiftedWavelength(
            radiance_calibration,
            nominal_wavelength_nm,
        );
        buffers.wavelengths[index] = nominal_wavelength_nm;

        var integration: @import("../../../plugins/providers/instrument.zig").IntegrationKernel = undefined;
        providers.instrument.integrationForWavelength(scene, prepared, .radiance, nominal_wavelength_nm, &integration);

        const integrated = try SpectralEval.integrateForwardAtNominal(
            allocator,
            scene,
            route,
            prepared,
            evaluation_wavelength_nm,
            safe_span,
            providers,
            buffers.layer_inputs[0..transport_layer_count],
            buffers.pseudo_spherical_layers,
            buffers.source_interfaces[0 .. transport_layer_count + 1],
            buffers.rtm_quadrature_levels[0 .. transport_layer_count + 1],
            buffers.pseudo_spherical_samples,
            buffers.pseudo_spherical_level_starts[0 .. transport_layer_count + 1],
            buffers.pseudo_spherical_level_altitudes[0 .. transport_layer_count + 1],
            &evaluation_cache,
            &integration,
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
    try applyChannelCorrections(
        scene,
        .radiance,
        radiance_calibration,
        prepared.depolarization_factor,
        buffers.wavelengths,
        buffers.radiance,
        buffers.scratch_aux,
    );

    for (0..sample_count) |index| {
        const nominal_wavelength_nm = try resolved_axis.sampleAt(@intCast(index));
        const evaluation_wavelength_nm = calibration.shiftedWavelength(
            irradiance_calibration,
            nominal_wavelength_nm,
        );
        var integration: @import("../../../plugins/providers/instrument.zig").IntegrationKernel = undefined;
        providers.instrument.integrationForWavelength(scene, prepared, .irradiance, nominal_wavelength_nm, &integration);
        buffers.scratch[index] = try SpectralEval.integrateIrradianceAtNominal(
            scene,
            prepared,
            evaluation_wavelength_nm,
            safe_span,
            &evaluation_cache,
            &integration,
        );
    }
    if (uses_integrated_irradiance_sampling) {
        @memcpy(buffers.irradiance, buffers.scratch);
    } else {
        try convolution.apply(buffers.scratch, irradiance_slit_kernel[0..], buffers.irradiance);
    }
    try applyChannelCorrections(
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

    if (buffers.noise_sigma) |noise_sigma| {
        if (buffers.radiance_noise_sigma) |radiance_noise_sigma| {
            if (providers.noise.materializesSigma(scene, .radiance)) {
                try providers.noise.materializeSigma(scene, .radiance, buffers.wavelengths, buffers.radiance, radiance_noise_sigma);
            } else {
                @memset(radiance_noise_sigma, 0.0);
            }
            if (noise_sigma.ptr != radiance_noise_sigma.ptr) {
                @memcpy(noise_sigma, radiance_noise_sigma);
            }
        }
        if (buffers.irradiance_noise_sigma) |irradiance_noise_sigma| {
            if (providers.noise.materializesSigma(scene, .irradiance)) {
                try providers.noise.materializeSigma(scene, .irradiance, buffers.wavelengths, buffers.irradiance, irradiance_noise_sigma);
            } else {
                @memset(irradiance_noise_sigma, 0.0);
            }
        }
        if (buffers.reflectance_noise_sigma) |reflectance_noise_sigma| {
            const radiance_sigma = buffers.radiance_noise_sigma orelse noise_sigma;
            const irradiance_sigma = buffers.irradiance_noise_sigma orelse noise_sigma;
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
        for (noise_sigma) |value| noise_sum += value;
    }

    var mean_jacobian: ?f64 = null;
    if (buffers.jacobian) |jacobian| {
        if (uses_integrated_radiance_sampling) {
            for (jacobian) |value| jacobian_sum += value;
        } else {
            try convolution.apply(jacobian, radiance_slit_kernel[0..], buffers.scratch);
            @memcpy(jacobian, buffers.scratch);
            try calibration.applySignal(radiance_calibration, jacobian, jacobian);
            for (jacobian) |value| jacobian_sum += value;
        }
        mean_jacobian = jacobian_sum / @as(f64, @floatFromInt(sample_count));
    }

    return .{
        .sample_count = @intCast(sample_count),
        .wavelength_start_nm = buffers.wavelengths[0],
        .wavelength_end_nm = buffers.wavelengths[sample_count - 1],
        .mean_radiance = radiance_sum / @as(f64, @floatFromInt(sample_count)),
        .mean_irradiance = irradiance_sum / @as(f64, @floatFromInt(sample_count)),
        .mean_reflectance = reflectance_sum / @as(f64, @floatFromInt(sample_count)),
        .mean_noise_sigma = if (buffers.noise_sigma != null)
            noise_sum / @as(f64, @floatFromInt(sample_count))
        else
            0.0,
        .mean_jacobian = mean_jacobian,
    };
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
    return simulate(
        allocator,
        &summary_scene,
        route,
        prepared,
        providers,
        try workspace.buffers(allocator, &summary_scene, route, providers),
    );
}

/// Purpose:
///   Materialize the full measurement-space product arrays.
pub fn simulateProduct(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    providers: Types.ProviderBindings,
) Workspace.Error!Types.MeasurementSpaceProduct {
    const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
    const transport_layer_count = Workspace.resolvedTransportLayerCount(route, prepared);
    const pseudo_spherical_sample_count = Workspace.resolvedPseudoSphericalSampleCount(scene, route, prepared);

    const wavelengths = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(wavelengths);
    const radiance = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(radiance);
    const irradiance = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(irradiance);
    const reflectance = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(reflectance);
    const scratch = try allocator.alloc(f64, sample_count);
    defer allocator.free(scratch);
    const scratch_aux = try allocator.alloc(f64, sample_count);
    defer allocator.free(scratch_aux);
    const wants_radiance_noise = providers.noise.materializesSigma(scene, .radiance);
    const wants_irradiance_noise = providers.noise.materializesSigma(scene, .irradiance);
    const noise_sigma = if (wants_radiance_noise or wants_irradiance_noise)
        try allocator.alloc(f64, sample_count)
    else
        try allocator.alloc(f64, 0);
    errdefer allocator.free(noise_sigma);
    const irradiance_noise_sigma = if (wants_radiance_noise or wants_irradiance_noise)
        try allocator.alloc(f64, sample_count)
    else
        try allocator.alloc(f64, 0);
    errdefer allocator.free(irradiance_noise_sigma);
    const reflectance_noise_sigma = if (wants_radiance_noise or wants_irradiance_noise)
        try allocator.alloc(f64, sample_count)
    else
        try allocator.alloc(f64, 0);
    errdefer allocator.free(reflectance_noise_sigma);

    const jacobian = if (route.derivative_mode == .none)
        null
    else
        try allocator.alloc(f64, sample_count);
    errdefer if (jacobian) |values| allocator.free(values);
    const layer_inputs = try allocator.alloc(common.LayerInput, transport_layer_count);
    defer allocator.free(layer_inputs);
    const pseudo_spherical_layers = try allocator.alloc(common.LayerInput, pseudo_spherical_sample_count);
    defer allocator.free(pseudo_spherical_layers);
    const source_interfaces = try allocator.alloc(common.SourceInterfaceInput, transport_layer_count + 1);
    defer allocator.free(source_interfaces);
    const rtm_quadrature_levels = try allocator.alloc(common.RtmQuadratureLevel, transport_layer_count + 1);
    defer allocator.free(rtm_quadrature_levels);
    const pseudo_spherical_samples = try allocator.alloc(common.PseudoSphericalSample, pseudo_spherical_sample_count);
    defer allocator.free(pseudo_spherical_samples);
    const pseudo_spherical_level_starts = try allocator.alloc(usize, transport_layer_count + 1);
    defer allocator.free(pseudo_spherical_level_starts);
    const pseudo_spherical_level_altitudes = try allocator.alloc(f64, transport_layer_count + 1);
    defer allocator.free(pseudo_spherical_level_altitudes);

    const summary = try simulate(allocator, scene, route, prepared, providers, .{
        .wavelengths = wavelengths,
        .radiance = radiance,
        .irradiance = irradiance,
        .reflectance = reflectance,
        .scratch = scratch,
        .scratch_aux = scratch_aux,
        .layer_inputs = layer_inputs,
        .pseudo_spherical_layers = pseudo_spherical_layers,
        .source_interfaces = source_interfaces,
        .rtm_quadrature_levels = rtm_quadrature_levels,
        .pseudo_spherical_samples = pseudo_spherical_samples,
        .pseudo_spherical_level_starts = pseudo_spherical_level_starts,
        .pseudo_spherical_level_altitudes = pseudo_spherical_level_altitudes,
        .jacobian = jacobian,
        .noise_sigma = if (noise_sigma.len == 0) null else noise_sigma,
        .radiance_noise_sigma = if (noise_sigma.len == 0) null else noise_sigma,
        .irradiance_noise_sigma = if (irradiance_noise_sigma.len == 0) null else irradiance_noise_sigma,
        .reflectance_noise_sigma = if (reflectance_noise_sigma.len == 0) null else reflectance_noise_sigma,
    });

    return .{
        .summary = summary,
        .wavelengths = wavelengths,
        .radiance = radiance,
        .irradiance = irradiance,
        .reflectance = reflectance,
        .noise_sigma = noise_sigma,
        .radiance_noise_sigma = noise_sigma,
        .irradiance_noise_sigma = irradiance_noise_sigma,
        .reflectance_noise_sigma = reflectance_noise_sigma,
        .jacobian = jacobian,
        .effective_air_mass_factor = prepared.effective_air_mass_factor,
        .effective_single_scatter_albedo = prepared.effective_single_scatter_albedo,
        .effective_temperature_k = prepared.effective_temperature_k,
        .effective_pressure_hpa = prepared.effective_pressure_hpa,
        .gas_optical_depth = prepared.gas_optical_depth,
        .cia_optical_depth = prepared.cia_optical_depth,
        .aerosol_optical_depth = prepared.aerosol_optical_depth,
        .cloud_optical_depth = prepared.cloud_optical_depth,
        .total_optical_depth = prepared.total_optical_depth,
        .depolarization_factor = prepared.depolarization_factor,
        .d_optical_depth_d_temperature = prepared.d_optical_depth_d_temperature,
    };
}

fn applyChannelCorrections(
    scene: *const Scene,
    channel: SpectralChannel,
    calibration_config: calibration.Calibration,
    depolarization_factor: f64,
    wavelengths_nm: []const f64,
    signal: []f64,
    scratch: []f64,
) !void {
    const controls = scene.observation_model.resolvedChannelControls(channel);
    try calibration.applySignal(calibration_config, signal, signal);
    try calibration.applySimpleOffsets(controls.simple_offsets, signal);
    try calibration.applySpectralFeatures(controls.spectral_features, wavelengths_nm, signal);
    if (controls.smear_percent != 0.0) {
        try calibration.applySmear(controls.smear_percent, signal, scratch);
    }
    try calibration.applyMultiplicativeNodes(controls.multiplicative_nodes, wavelengths_nm, signal, scratch);
    const stray_reference = if (controls.stray_light_nodes.use_reference_spectrum)
        correctionReferenceSignal(scene, channel, signal.len) orelse signal
    else
        signal;
    try calibration.applyStrayLightNodes(controls.stray_light_nodes, wavelengths_nm, stray_reference, signal, scratch);
    if (channel == .radiance) {
        try calibration.applyPolarizationScramblerBias(
            controls.use_polarization_scrambler,
            depolarization_factor,
            wavelengths_nm,
            signal,
        );
    }
}

fn correctionReferenceSignal(
    scene: *const Scene,
    channel: SpectralChannel,
    sample_count: usize,
) ?[]const f64 {
    const controls = scene.observation_model.resolvedChannelControls(channel);
    if (controls.noise.reference_signal.len == sample_count) {
        return controls.noise.reference_signal;
    }
    if (channel == .radiance and scene.observation_model.reference_radiance.len == sample_count) {
        return scene.observation_model.reference_radiance;
    }
    return null;
}
