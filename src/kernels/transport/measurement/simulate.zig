const std = @import("std");
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

    const calibration_config = providers.instrument.calibrationForScene(scene);
    const slit_kernel = providers.instrument.slitKernelForScene(scene);
    const uses_integrated_sampling = providers.instrument.usesIntegratedSampling(scene);
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
            calibration_config,
            nominal_wavelength_nm,
        );
        buffers.wavelengths[index] = nominal_wavelength_nm;

        var integration: @import("../../../plugins/providers/instrument.zig").IntegrationKernel = undefined;
        providers.instrument.integrationForWavelength(scene, prepared, nominal_wavelength_nm, &integration);

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
    if (uses_integrated_sampling) {
        @memcpy(buffers.radiance, buffers.scratch);
    } else {
        try convolution.apply(buffers.scratch, slit_kernel[0..], buffers.radiance);
    }
    try calibration.applySignal(calibration_config, buffers.radiance, buffers.radiance);

    for (0..sample_count) |index| {
        const nominal_wavelength_nm = try resolved_axis.sampleAt(@intCast(index));
        const evaluation_wavelength_nm = calibration.shiftedWavelength(
            calibration_config,
            nominal_wavelength_nm,
        );
        var integration: @import("../../../plugins/providers/instrument.zig").IntegrationKernel = undefined;
        providers.instrument.integrationForWavelength(scene, prepared, nominal_wavelength_nm, &integration);
        buffers.scratch[index] = try SpectralEval.integrateIrradianceAtNominal(
            scene,
            prepared,
            evaluation_wavelength_nm,
            safe_span,
            &evaluation_cache,
            &integration,
        );
    }
    if (uses_integrated_sampling) {
        @memcpy(buffers.irradiance, buffers.scratch);
    } else {
        try convolution.apply(buffers.scratch, slit_kernel[0..], buffers.irradiance);
    }

    const solar_cosine = scene.geometry.solarCosineAtAltitude(0.0);
    for (0..sample_count) |index| {
        buffers.reflectance[index] = (buffers.radiance[index] * std.math.pi) /
            @max(buffers.irradiance[index] * solar_cosine, 1e-9);
        radiance_sum += buffers.radiance[index];
        irradiance_sum += buffers.irradiance[index];
        reflectance_sum += buffers.reflectance[index];
    }

    if (buffers.noise_sigma) |noise_sigma| {
        try providers.noise.materializeSigma(scene, buffers.radiance, noise_sigma);
        for (noise_sigma) |value| noise_sum += value;
    }

    var mean_jacobian: ?f64 = null;
    if (buffers.jacobian) |jacobian| {
        if (uses_integrated_sampling) {
            for (jacobian) |value| jacobian_sum += value;
        } else {
            try convolution.apply(jacobian, slit_kernel[0..], buffers.scratch);
            @memcpy(jacobian, buffers.scratch);
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

pub fn simulateSummaryWithWorkspace(
    allocator: Allocator,
    workspace: *Workspace.SummaryWorkspace,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    providers: Types.ProviderBindings,
) Workspace.Error!Types.MeasurementSpaceSummary {
    var summary_scene = scene.*;
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
    const noise_sigma = if (providers.noise.materializesSigma(scene))
        try allocator.alloc(f64, sample_count)
    else
        try allocator.alloc(f64, 0);
    errdefer allocator.free(noise_sigma);

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
        .layer_inputs = layer_inputs,
        .pseudo_spherical_layers = pseudo_spherical_layers,
        .source_interfaces = source_interfaces,
        .rtm_quadrature_levels = rtm_quadrature_levels,
        .pseudo_spherical_samples = pseudo_spherical_samples,
        .pseudo_spherical_level_starts = pseudo_spherical_level_starts,
        .pseudo_spherical_level_altitudes = pseudo_spherical_level_altitudes,
        .jacobian = jacobian,
        .noise_sigma = if (noise_sigma.len == 0) null else noise_sigma,
    });

    return .{
        .summary = summary,
        .wavelengths = wavelengths,
        .radiance = radiance,
        .irradiance = irradiance,
        .reflectance = reflectance,
        .noise_sigma = noise_sigma,
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
