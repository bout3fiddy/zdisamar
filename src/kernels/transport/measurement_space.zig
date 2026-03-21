const std = @import("std");
const core_errors = @import("../../core/errors.zig");
const ReferenceData = @import("../../model/ReferenceData.zig");
const Scene = @import("../../model/Scene.zig").Scene;
const PreparedOpticalState = @import("../optics/prepare.zig").PreparedOpticalState;
const gauss_legendre = @import("../quadrature/gauss_legendre.zig");
const grid = @import("../spectra/grid.zig");
const calibration = @import("../spectra/calibration.zig");
const convolution = @import("../spectra/convolution.zig");
const common = @import("common.zig");
const labos = @import("labos.zig");
const InstrumentProviders = @import("../../plugins/providers/instrument.zig");
const NoiseProviders = @import("../../plugins/providers/noise.zig");
const PluginProviders = @import("../../plugins/providers/root.zig");
const SurfaceProviders = @import("../../plugins/providers/surface.zig");
const TransportProviders = @import("../../plugins/providers/transport.zig");

const Allocator = std.mem.Allocator;
const phase_coefficient_count = @import("../optics/prepare/phase_functions.zig").phase_coefficient_count;
const centimeters_per_kilometer = 1.0e5;
const max_summary_samples: u32 = 128;
const bundled_o2a_solar_wavelengths_nm = [_]f64{ 755.0, 758.0, 760.01, 761.99, 764.99, 770.0, 776.0 };
const bundled_o2a_solar_irradiance = [_]f64{
    4.805854615e14,
    4.879049767e14,
    4.858697784e14,
    4.615924814e14,
    4.832478218e14,
    4.60914094e14,
    4.759839792e14,
};

pub const reflectance_export_name = "reflectance";
pub const fitted_reflectance_export_name = "fitted_reflectance";

pub const ProviderBindings = struct {
    transport: TransportProviders.Provider,
    surface: SurfaceProviders.Provider,
    instrument: InstrumentProviders.Provider,
    noise: NoiseProviders.Provider,
};

pub const MeasurementSpaceSummary = struct {
    sample_count: u32,
    wavelength_start_nm: f64,
    wavelength_end_nm: f64,
    mean_radiance: f64,
    mean_irradiance: f64,
    mean_reflectance: f64,
    mean_noise_sigma: f64,
    mean_jacobian: ?f64 = null,
};

pub const MeasurementSpaceProduct = struct {
    summary: MeasurementSpaceSummary,
    wavelengths: []f64,
    radiance: []f64,
    irradiance: []f64,
    reflectance: []f64,
    noise_sigma: []f64,
    jacobian: ?[]f64 = null,
    effective_air_mass_factor: f64,
    effective_single_scatter_albedo: f64,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
    gas_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    cloud_optical_depth: f64,
    total_optical_depth: f64,
    depolarization_factor: f64,
    d_optical_depth_d_temperature: f64,

    pub fn deinit(self: *MeasurementSpaceProduct, allocator: Allocator) void {
        allocator.free(self.wavelengths);
        allocator.free(self.radiance);
        allocator.free(self.irradiance);
        allocator.free(self.reflectance);
        allocator.free(self.noise_sigma);
        if (self.jacobian) |values| allocator.free(values);
        self.* = undefined;
    }
};

pub const Buffers = struct {
    wavelengths: []f64,
    radiance: []f64,
    irradiance: []f64,
    reflectance: []f64,
    scratch: []f64,
    layer_inputs: []common.LayerInput,
    pseudo_spherical_layers: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    jacobian: ?[]f64 = null,
    noise_sigma: ?[]f64 = null,
};

pub const SummaryWorkspace = struct {
    wavelengths: []f64 = &.{},
    radiance: []f64 = &.{},
    irradiance: []f64 = &.{},
    reflectance: []f64 = &.{},
    scratch: []f64 = &.{},
    layer_inputs: []common.LayerInput = &.{},
    pseudo_spherical_layers: []common.LayerInput = &.{},
    source_interfaces: []common.SourceInterfaceInput = &.{},
    rtm_quadrature_levels: []common.RtmQuadratureLevel = &.{},
    pseudo_spherical_samples: []common.PseudoSphericalSample = &.{},
    pseudo_spherical_level_starts: []usize = &.{},
    pseudo_spherical_level_altitudes: []f64 = &.{},
    jacobian: []f64 = &.{},
    noise_sigma: []f64 = &.{},

    pub fn deinit(self: *SummaryWorkspace, allocator: Allocator) void {
        freeBuffer(allocator, self.wavelengths);
        freeBuffer(allocator, self.radiance);
        freeBuffer(allocator, self.irradiance);
        freeBuffer(allocator, self.reflectance);
        freeBuffer(allocator, self.scratch);
        freeLayerBuffer(allocator, self.layer_inputs);
        freeLayerBuffer(allocator, self.pseudo_spherical_layers);
        freeSourceInterfaceBuffer(allocator, self.source_interfaces);
        freeRtmQuadratureBuffer(allocator, self.rtm_quadrature_levels);
        freePseudoSphericalSampleBuffer(allocator, self.pseudo_spherical_samples);
        freeIndexBuffer(allocator, self.pseudo_spherical_level_starts);
        freeBuffer(allocator, self.pseudo_spherical_level_altitudes);
        freeBuffer(allocator, self.jacobian);
        freeBuffer(allocator, self.noise_sigma);
        self.* = .{};
    }

    fn buffers(
        self: *SummaryWorkspace,
        allocator: Allocator,
        scene: *const Scene,
        route: common.Route,
        providers: ProviderBindings,
    ) Error!Buffers {
        const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
        const layer_count = transportLayerCountHint(scene, route);
        const pseudo_spherical_sample_count = pseudoSphericalSampleCountHint(scene, route);
        const wants_jacobian = route.derivative_mode != .none;
        const wants_noise = providers.noise.materializesSigma(scene);

        try ensureBufferCapacity(allocator, &self.wavelengths, sample_count);
        try ensureBufferCapacity(allocator, &self.radiance, sample_count);
        try ensureBufferCapacity(allocator, &self.irradiance, sample_count);
        try ensureBufferCapacity(allocator, &self.reflectance, sample_count);
        try ensureBufferCapacity(allocator, &self.scratch, sample_count);
        try ensureLayerBufferCapacity(allocator, &self.layer_inputs, layer_count);
        try ensureLayerBufferCapacity(allocator, &self.pseudo_spherical_layers, pseudo_spherical_sample_count);
        try ensureSourceInterfaceBufferCapacity(allocator, &self.source_interfaces, layer_count + 1);
        try ensureRtmQuadratureBufferCapacity(allocator, &self.rtm_quadrature_levels, layer_count + 1);
        try ensurePseudoSphericalSampleBufferCapacity(allocator, &self.pseudo_spherical_samples, pseudo_spherical_sample_count);
        try ensureIndexBufferCapacity(allocator, &self.pseudo_spherical_level_starts, layer_count + 1);
        try ensureBufferCapacity(allocator, &self.pseudo_spherical_level_altitudes, layer_count + 1);
        if (wants_jacobian) {
            try ensureBufferCapacity(allocator, &self.jacobian, sample_count);
        }
        if (wants_noise) {
            try ensureBufferCapacity(allocator, &self.noise_sigma, sample_count);
        }

        return .{
            .wavelengths = self.wavelengths[0..sample_count],
            .radiance = self.radiance[0..sample_count],
            .irradiance = self.irradiance[0..sample_count],
            .reflectance = self.reflectance[0..sample_count],
            .scratch = self.scratch[0..sample_count],
            .layer_inputs = self.layer_inputs[0..layer_count],
            .pseudo_spherical_layers = self.pseudo_spherical_layers[0..pseudo_spherical_sample_count],
            .source_interfaces = self.source_interfaces[0 .. layer_count + 1],
            .rtm_quadrature_levels = self.rtm_quadrature_levels[0 .. layer_count + 1],
            .pseudo_spherical_samples = self.pseudo_spherical_samples[0..pseudo_spherical_sample_count],
            .pseudo_spherical_level_starts = self.pseudo_spherical_level_starts[0 .. layer_count + 1],
            .pseudo_spherical_level_altitudes = self.pseudo_spherical_level_altitudes[0 .. layer_count + 1],
            .jacobian = if (wants_jacobian) self.jacobian[0..sample_count] else null,
            .noise_sigma = if (wants_noise) self.noise_sigma[0..sample_count] else null,
        };
    }
};

const OperationalInstrumentIntegration = InstrumentProviders.IntegrationKernel;

const ForwardIntegratedSample = struct {
    radiance: f64,
    jacobian: f64 = 0.0,
};

const spectral_cache_quantization_nm = 1.0e-6;

const SpectralEvaluationCache = struct {
    allocator: Allocator,
    forward: std.AutoHashMap(i64, ForwardIntegratedSample),
    irradiance: std.AutoHashMap(i64, f64),

    fn init(allocator: Allocator) SpectralEvaluationCache {
        return .{
            .allocator = allocator,
            .forward = std.AutoHashMap(i64, ForwardIntegratedSample).init(allocator),
            .irradiance = std.AutoHashMap(i64, f64).init(allocator),
        };
    }

    fn deinit(self: *SpectralEvaluationCache) void {
        self.forward.deinit();
        self.irradiance.deinit();
        self.* = undefined;
    }

    fn keyFor(wavelength_nm: f64) i64 {
        return @as(i64, @intFromFloat(std.math.round(wavelength_nm / spectral_cache_quantization_nm)));
    }
};

pub const Error =
    core_errors.Error ||
    common.Error ||
    grid.Error ||
    convolution.Error ||
    NoiseProviders.Error ||
    error{
        ShapeMismatch,
        OutOfMemory,
    };

pub fn simulate(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const PreparedOpticalState,
    providers: ProviderBindings,
    buffers: Buffers,
) Error!MeasurementSpaceSummary {
    try scene.validate();
    const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
    try validateBuffers(sample_count, buffers);
    var evaluation_cache = SpectralEvaluationCache.init(allocator);
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
    const transport_layer_count = resolvedTransportLayerCount(route, prepared);
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

        var integration: OperationalInstrumentIntegration = undefined;
        providers.instrument.integrationForWavelength(scene, nominal_wavelength_nm, &integration);

        const integrated = try integrateForwardAtNominal(
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
        var integration: OperationalInstrumentIntegration = undefined;
        providers.instrument.integrationForWavelength(scene, nominal_wavelength_nm, &integration);
        buffers.scratch[index] = try integrateIrradianceAtNominal(
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
    prepared: *const PreparedOpticalState,
    providers: ProviderBindings,
) Error!MeasurementSpaceSummary {
    var workspace: SummaryWorkspace = .{};
    defer workspace.deinit(allocator);
    return simulateSummaryWithWorkspace(allocator, &workspace, scene, route, prepared, providers);
}

pub fn simulateSummaryWithWorkspace(
    allocator: Allocator,
    workspace: *SummaryWorkspace,
    scene: *const Scene,
    route: common.Route,
    prepared: *const PreparedOpticalState,
    providers: ProviderBindings,
) Error!MeasurementSpaceSummary {
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
    prepared: *const PreparedOpticalState,
    providers: ProviderBindings,
) Error!MeasurementSpaceProduct {
    const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
    const transport_layer_count = resolvedTransportLayerCount(route, prepared);
    const pseudo_spherical_sample_count = resolvedPseudoSphericalSampleCount(scene, route, prepared);

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

fn transportLayerCountHint(scene: *const Scene, route: common.Route) usize {
    const layer_count = @max(@as(usize, @intCast(scene.atmosphere.layer_count)), 1);
    if (route.family != .adding) return layer_count;
    return layer_count * @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
}

fn pseudoSphericalSampleCountHint(scene: *const Scene, route: common.Route) usize {
    const layer_count = transportLayerCountHint(scene, route);
    return layer_count * pseudoSphericalSubgridDivisions(scene);
}

fn resolvedTransportLayerCount(route: common.Route, prepared: *const PreparedOpticalState) usize {
    return if (route.family == .adding) prepared.transportLayerCount() else prepared.layers.len;
}

fn resolvedPseudoSphericalSampleCount(
    scene: *const Scene,
    route: common.Route,
    prepared: *const PreparedOpticalState,
) usize {
    return resolvedTransportLayerCount(route, prepared) * pseudoSphericalSubgridDivisions(scene);
}

fn pseudoSphericalSubgridDivisions(scene: *const Scene) usize {
    return @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
}

fn validateBuffers(sample_count: usize, buffers: Buffers) Error!void {
    if (sample_count == 0 or
        buffers.wavelengths.len != sample_count or
        buffers.radiance.len != sample_count or
        buffers.irradiance.len != sample_count or
        buffers.reflectance.len != sample_count or
        buffers.scratch.len != sample_count or
        buffers.layer_inputs.len == 0 or
        buffers.pseudo_spherical_layers.len == 0 or
        buffers.source_interfaces.len != buffers.layer_inputs.len + 1 or
        buffers.rtm_quadrature_levels.len != buffers.layer_inputs.len + 1)
    {
        return error.ShapeMismatch;
    }
    if (buffers.pseudo_spherical_samples.len != buffers.pseudo_spherical_layers.len or
        buffers.pseudo_spherical_level_starts.len != buffers.layer_inputs.len + 1 or
        buffers.pseudo_spherical_level_altitudes.len != buffers.layer_inputs.len + 1)
    {
        return error.ShapeMismatch;
    }
    if (buffers.jacobian) |jacobian| {
        if (jacobian.len != sample_count) return error.ShapeMismatch;
    }
    if (buffers.noise_sigma) |noise_sigma| {
        if (noise_sigma.len != sample_count) return error.ShapeMismatch;
    }
}

fn ensureBufferCapacity(allocator: Allocator, buffer: *[]f64, capacity: usize) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(f64, capacity);
    freeBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensureLayerBufferCapacity(allocator: Allocator, buffer: *[]common.LayerInput, capacity: usize) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(common.LayerInput, capacity);
    freeLayerBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensureSourceInterfaceBufferCapacity(
    allocator: Allocator,
    buffer: *[]common.SourceInterfaceInput,
    capacity: usize,
) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(common.SourceInterfaceInput, capacity);
    freeSourceInterfaceBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensureRtmQuadratureBufferCapacity(
    allocator: Allocator,
    buffer: *[]common.RtmQuadratureLevel,
    capacity: usize,
) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(common.RtmQuadratureLevel, capacity);
    freeRtmQuadratureBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensurePseudoSphericalSampleBufferCapacity(
    allocator: Allocator,
    buffer: *[]common.PseudoSphericalSample,
    capacity: usize,
) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(common.PseudoSphericalSample, capacity);
    freePseudoSphericalSampleBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensureIndexBufferCapacity(allocator: Allocator, buffer: *[]usize, capacity: usize) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(usize, capacity);
    freeIndexBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn freeBuffer(allocator: Allocator, buffer: []f64) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn freeLayerBuffer(allocator: Allocator, buffer: []common.LayerInput) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn freeSourceInterfaceBuffer(allocator: Allocator, buffer: []common.SourceInterfaceInput) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn freeRtmQuadratureBuffer(allocator: Allocator, buffer: []common.RtmQuadratureLevel) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn freePseudoSphericalSampleBuffer(allocator: Allocator, buffer: []common.PseudoSphericalSample) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn freeIndexBuffer(allocator: Allocator, buffer: []usize) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn configuredForwardInput(
    scene: *const Scene,
    route: common.Route,
    prepared: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []common.LayerInput,
    pseudo_spherical_layers: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
) common.ForwardInput {
    var input = prepared.toForwardInputAtWavelengthWithLayers(scene, wavelength_nm, layer_inputs);
    prepared.fillSourceInterfacesAtWavelengthWithLayers(
        wavelength_nm,
        input.layers,
        source_interfaces[0 .. input.layers.len + 1],
    );
    input.source_interfaces = source_interfaces[0 .. input.layers.len + 1];
    if (route.family == .adding and route.rtm_controls.integrate_source_function) {
        if (prepared.fillRtmQuadratureAtWavelengthWithLayers(
            wavelength_nm,
            input.layers,
            rtm_quadrature_levels[0 .. input.layers.len + 1],
        )) {
            input.rtm_quadrature = .{
                .levels = rtm_quadrature_levels[0 .. input.layers.len + 1],
            };
        }
    }
    if (route.rtm_controls.use_spherical_correction) {
        if (prepared.fillPseudoSphericalGridAtWavelength(
            scene,
            wavelength_nm,
            input.layers.len,
            pseudo_spherical_layers,
            pseudo_spherical_samples,
            pseudo_spherical_level_starts,
            pseudo_spherical_level_altitudes,
        )) {
            input.pseudo_spherical_grid = .{
                .samples = pseudo_spherical_samples[0..resolvedPseudoSphericalSampleCount(scene, route, prepared)],
                .level_sample_starts = pseudo_spherical_level_starts[0 .. input.layers.len + 1],
                .level_altitudes_km = pseudo_spherical_level_altitudes[0 .. input.layers.len + 1],
            };
        }
    }
    input.rtm_controls = route.rtm_controls;
    return input;
}

fn radianceFromForward(
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    providers: ProviderBindings,
    wavelength_nm: f64,
    safe_span: f64,
    phase: f64,
    forward: common.ForwardResult,
) f64 {
    const solar_irradiance = irradianceAtWavelength(scene, prepared, wavelength_nm, safe_span);
    const solar_cosine = scene.geometry.solarCosineAtAltitude(0.0);
    const surface_gain = providers.surface.brdfFactor(.{
        .scene = scene,
        .prepared = prepared,
        .wavelength_nm = wavelength_nm,
        .safe_span = safe_span,
        .phase = phase,
        .forward = forward,
    });
    return solar_irradiance * solar_cosine * forward.toa_reflectance_factor * surface_gain / std.math.pi;
}

fn irradianceAtWavelength(
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
) f64 {
    const source_irradiance = if (scene.observation_model.operational_solar_spectrum.enabled())
        scene.observation_model.operational_solar_spectrum.interpolateIrradiance(wavelength_nm)
    else if (scene.observation_model.solar_spectrum_source.kind() == .bundle_default)
        bundledSolarIrradiance(wavelength_nm) orelse defaultSolarContinuumIrradiance(wavelength_nm)
    else
        defaultSolarContinuumIrradiance(wavelength_nm);
    _ = prepared;
    _ = safe_span;
    return @max(source_irradiance, 1e-6);
}

fn bundledSolarIrradiance(wavelength_nm: f64) ?f64 {
    if (wavelength_nm < bundled_o2a_solar_wavelengths_nm[0] or wavelength_nm > bundled_o2a_solar_wavelengths_nm[bundled_o2a_solar_wavelengths_nm.len - 1]) {
        return null;
    }

    if (wavelength_nm <= bundled_o2a_solar_wavelengths_nm[0]) return bundled_o2a_solar_irradiance[0];
    for (
        bundled_o2a_solar_wavelengths_nm[0 .. bundled_o2a_solar_wavelengths_nm.len - 1],
        bundled_o2a_solar_wavelengths_nm[1..],
        bundled_o2a_solar_irradiance[0 .. bundled_o2a_solar_irradiance.len - 1],
        bundled_o2a_solar_irradiance[1..],
    ) |left_nm, right_nm, left_irradiance, right_irradiance| {
        if (wavelength_nm <= right_nm) {
            const span = right_nm - left_nm;
            if (span == 0.0) return right_irradiance;
            const blend = (wavelength_nm - left_nm) / span;
            return left_irradiance + blend * (right_irradiance - left_irradiance);
        }
    }
    return bundled_o2a_solar_irradiance[bundled_o2a_solar_irradiance.len - 1];
}

fn defaultSolarContinuumIrradiance(wavelength_nm: f64) f64 {
    const reference_wavelength_nm = 760.0;
    const reference_irradiance = 4.87401e14;
    return reference_irradiance *
        planckContinuumShape(wavelength_nm, 5778.0) /
        planckContinuumShape(reference_wavelength_nm, 5778.0);
}

fn planckContinuumShape(wavelength_nm: f64, temperature_k: f64) f64 {
    const h = 6.62607015e-34;
    const c = 2.99792458e8;
    const k = 1.380649e-23;
    const wavelength_m = @max(wavelength_nm, 1.0) * 1.0e-9;
    const exponent = h * c / (wavelength_m * k * @max(temperature_k, 1.0));
    const denominator = @max(std.math.expm1(exponent), 1.0e-12);
    return (2.0 * h * c * c) /
        std.math.pow(f64, wavelength_m, 5.0) /
        denominator;
}

fn integrateForwardAtNominal(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const PreparedOpticalState,
    nominal_wavelength_nm: f64,
    safe_span: f64,
    providers: ProviderBindings,
    layer_inputs: []common.LayerInput,
    pseudo_spherical_layers: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    cache: *SpectralEvaluationCache,
    integration: *const OperationalInstrumentIntegration,
) Error!ForwardIntegratedSample {
    if (!integration.enabled) {
        return cachedForwardAtWavelength(
            allocator,
            scene,
            route,
            prepared,
            nominal_wavelength_nm,
            safe_span,
            providers,
            layer_inputs,
            pseudo_spherical_layers,
            source_interfaces,
            rtm_quadrature_levels,
            pseudo_spherical_samples,
            pseudo_spherical_level_starts,
            pseudo_spherical_level_altitudes,
            cache,
        );
    }

    var radiance_sum: f64 = 0.0;
    var jacobian_sum: f64 = 0.0;
    for (0..integration.sample_count) |index| {
        const offset_nm = integration.offsets_nm[index];
        const weight = integration.weights[index];
        const wavelength_nm = nominal_wavelength_nm + offset_nm;
        const sample = try cachedForwardAtWavelength(
            allocator,
            scene,
            route,
            prepared,
            wavelength_nm,
            safe_span,
            providers,
            layer_inputs,
            pseudo_spherical_layers,
            source_interfaces,
            rtm_quadrature_levels,
            pseudo_spherical_samples,
            pseudo_spherical_level_starts,
            pseudo_spherical_level_altitudes,
            cache,
        );
        radiance_sum += weight * sample.radiance;
        jacobian_sum += weight * sample.jacobian;
    }

    return .{
        .radiance = radiance_sum,
        .jacobian = jacobian_sum,
    };
}

fn integrateIrradianceAtNominal(
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    nominal_wavelength_nm: f64,
    safe_span: f64,
    cache: *SpectralEvaluationCache,
    integration: *const OperationalInstrumentIntegration,
) Error!f64 {
    if (!integration.enabled) {
        return cachedIrradianceAtWavelength(scene, prepared, nominal_wavelength_nm, safe_span, cache);
    }

    var irradiance_sum: f64 = 0.0;
    for (0..integration.sample_count) |index| {
        const offset_nm = integration.offsets_nm[index];
        const weight = integration.weights[index];
        irradiance_sum += weight * try cachedIrradianceAtWavelength(
            scene,
            prepared,
            nominal_wavelength_nm + offset_nm,
            safe_span,
            cache,
        );
    }
    return irradiance_sum;
}

fn cachedForwardAtWavelength(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
    providers: ProviderBindings,
    layer_inputs: []common.LayerInput,
    pseudo_spherical_layers: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    cache: *SpectralEvaluationCache,
) Error!ForwardIntegratedSample {
    const key = SpectralEvaluationCache.keyFor(wavelength_nm);
    if (cache.forward.get(key)) |cached| return cached;

    const input = configuredForwardInput(
        scene,
        route,
        prepared,
        wavelength_nm,
        layer_inputs,
        pseudo_spherical_layers,
        source_interfaces,
        rtm_quadrature_levels,
        pseudo_spherical_samples,
        pseudo_spherical_level_starts,
        pseudo_spherical_level_altitudes,
    );
    var effective_route = route;
    effective_route.rtm_controls = input.rtm_controls;
    const forward = try providers.transport.executePrepared(allocator, effective_route, input);
    const sample = ForwardIntegratedSample{
        .radiance = radianceFromForward(scene, prepared, providers, wavelength_nm, safe_span, 0.0, forward),
        .jacobian = if (forward.jacobian_column) |value| value else 0.0,
    };
    try cache.forward.put(key, sample);
    return sample;
}

fn cachedIrradianceAtWavelength(
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
    cache: *SpectralEvaluationCache,
) Error!f64 {
    const key = SpectralEvaluationCache.keyFor(wavelength_nm);
    if (cache.irradiance.get(key)) |cached| return cached;

    const value = irradianceAtWavelength(scene, prepared, wavelength_nm, safe_span);
    try cache.irradiance.put(key, value);
    return value;
}

fn buildTestPreparedOpticalState(allocator: Allocator) !PreparedOpticalState {
    return .{
        .layers = try allocator.dupe(@import("../optics/prepare.zig").PreparedLayer, &.{
            .{ .layer_index = 0, .sublayer_start_index = 0, .sublayer_count = 2, .altitude_km = 2.0, .pressure_hpa = 820.0, .temperature_k = 280.0, .number_density_cm3 = 2.0e19, .continuum_cross_section_cm2_per_molecule = 5.0e-19, .line_cross_section_cm2_per_molecule = 1.0e-20, .line_mixing_cross_section_cm2_per_molecule = 2.0e-21, .cia_optical_depth = 0.03, .d_cross_section_d_temperature_cm2_per_molecule_per_k = -1.0e-23, .gas_optical_depth = 0.12, .aerosol_optical_depth = 0.05, .cloud_optical_depth = 0.03, .layer_single_scatter_albedo = 0.94, .depolarization_factor = 0.03, .optical_depth = 0.2 },
            .{ .layer_index = 1, .sublayer_start_index = 2, .sublayer_count = 2, .altitude_km = 10.0, .pressure_hpa = 280.0, .temperature_k = 240.0, .number_density_cm3 = 6.0e18, .continuum_cross_section_cm2_per_molecule = 5.0e-19, .line_cross_section_cm2_per_molecule = 5.0e-21, .line_mixing_cross_section_cm2_per_molecule = 1.0e-21, .d_cross_section_d_temperature_cm2_per_molecule_per_k = -5.0e-24, .cia_optical_depth = 0.0, .gas_optical_depth = 0.07, .aerosol_optical_depth = 0.02, .cloud_optical_depth = 0.01, .layer_single_scatter_albedo = 0.96, .depolarization_factor = 0.02, .optical_depth = 0.1 },
        }),
        .sublayers = try allocator.dupe(@import("../optics/prepare.zig").PreparedSublayer, &.{
            .{
                .parent_layer_index = 0,
                .sublayer_index = 0,
                .altitude_km = 1.0,
                .pressure_hpa = 880.0,
                .temperature_k = 284.0,
                .number_density_cm3 = 2.1e19,
                .oxygen_number_density_cm3 = 4.4e18,
                .path_length_cm = 5.0e4,
                .continuum_cross_section_cm2_per_molecule = 5.0e-19,
                .line_cross_section_cm2_per_molecule = 9.0e-21,
                .line_mixing_cross_section_cm2_per_molecule = 1.8e-21,
                .cia_sigma_cm5_per_molecule2 = 1.0e-46,
                .cia_optical_depth = 0.015,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = -1.0e-23,
                .gas_absorption_optical_depth = 0.06,
                .gas_scattering_optical_depth = 0.02,
                .gas_extinction_optical_depth = 0.08,
                .d_gas_optical_depth_d_temperature = -7.5e-5,
                .d_cia_optical_depth_d_temperature = -1.5e-5,
                .aerosol_optical_depth = 0.028,
                .cloud_optical_depth = 0.018,
                .aerosol_single_scatter_albedo = 0.94,
                .cloud_single_scatter_albedo = 0.96,
                .aerosol_phase_coefficients = .{ 1.0, 0.20, 0.04, 0.0 },
                .cloud_phase_coefficients = .{ 1.0, 0.10, 0.02, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.17, 0.035, 0.0 },
            },
            .{
                .parent_layer_index = 0,
                .sublayer_index = 1,
                .altitude_km = 3.0,
                .pressure_hpa = 760.0,
                .temperature_k = 276.0,
                .number_density_cm3 = 1.9e19,
                .oxygen_number_density_cm3 = 4.0e18,
                .path_length_cm = 5.0e4,
                .continuum_cross_section_cm2_per_molecule = 5.0e-19,
                .line_cross_section_cm2_per_molecule = 1.1e-20,
                .line_mixing_cross_section_cm2_per_molecule = 2.2e-21,
                .cia_sigma_cm5_per_molecule2 = 1.0e-46,
                .cia_optical_depth = 0.015,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = -1.0e-23,
                .gas_absorption_optical_depth = 0.06,
                .gas_scattering_optical_depth = 0.02,
                .gas_extinction_optical_depth = 0.08,
                .d_gas_optical_depth_d_temperature = -7.5e-5,
                .d_cia_optical_depth_d_temperature = -1.5e-5,
                .aerosol_optical_depth = 0.022,
                .cloud_optical_depth = 0.012,
                .aerosol_single_scatter_albedo = 0.94,
                .cloud_single_scatter_albedo = 0.96,
                .aerosol_phase_coefficients = .{ 1.0, 0.18, 0.03, 0.0 },
                .cloud_phase_coefficients = .{ 1.0, 0.08, 0.02, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.15, 0.028, 0.0 },
            },
            .{
                .parent_layer_index = 1,
                .sublayer_index = 0,
                .altitude_km = 8.0,
                .pressure_hpa = 360.0,
                .temperature_k = 248.0,
                .number_density_cm3 = 7.0e18,
                .oxygen_number_density_cm3 = 1.47e18,
                .path_length_cm = 5.0e4,
                .continuum_cross_section_cm2_per_molecule = 5.0e-19,
                .line_cross_section_cm2_per_molecule = 5.2e-21,
                .line_mixing_cross_section_cm2_per_molecule = 1.0e-21,
                .cia_sigma_cm5_per_molecule2 = 1.0e-46,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = -5.0e-24,
                .gas_absorption_optical_depth = 0.035,
                .gas_scattering_optical_depth = 0.012,
                .gas_extinction_optical_depth = 0.047,
                .d_gas_optical_depth_d_temperature = -3.0e-5,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.011,
                .cloud_optical_depth = 0.006,
                .aerosol_single_scatter_albedo = 0.96,
                .cloud_single_scatter_albedo = 0.98,
                .aerosol_phase_coefficients = .{ 1.0, 0.14, 0.02, 0.0 },
                .cloud_phase_coefficients = .{ 1.0, 0.05, 0.01, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.11, 0.018, 0.0 },
            },
            .{
                .parent_layer_index = 1,
                .sublayer_index = 1,
                .altitude_km = 12.0,
                .pressure_hpa = 220.0,
                .temperature_k = 232.0,
                .number_density_cm3 = 5.0e18,
                .oxygen_number_density_cm3 = 1.05e18,
                .path_length_cm = 5.0e4,
                .continuum_cross_section_cm2_per_molecule = 5.0e-19,
                .line_cross_section_cm2_per_molecule = 4.8e-21,
                .line_mixing_cross_section_cm2_per_molecule = 1.0e-21,
                .cia_sigma_cm5_per_molecule2 = 1.0e-46,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = -5.0e-24,
                .gas_absorption_optical_depth = 0.035,
                .gas_scattering_optical_depth = 0.012,
                .gas_extinction_optical_depth = 0.047,
                .d_gas_optical_depth_d_temperature = -3.0e-5,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.009,
                .cloud_optical_depth = 0.004,
                .aerosol_single_scatter_albedo = 0.96,
                .cloud_single_scatter_albedo = 0.98,
                .aerosol_phase_coefficients = .{ 1.0, 0.12, 0.02, 0.0 },
                .cloud_phase_coefficients = .{ 1.0, 0.05, 0.01, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.10, 0.016, 0.0 },
            },
        }),
        .continuum_points = try allocator.dupe(@import("../../model/ReferenceData.zig").CrossSectionPoint, &.{
            .{ .wavelength_nm = 405.0, .sigma_cm2_per_molecule = 6.0e-19 },
            .{ .wavelength_nm = 465.0, .sigma_cm2_per_molecule = 4.0e-19 },
        }),
        .collision_induced_absorption = .{
            .scale_factor_cm5_per_molecule2 = 1.0e-46,
            .points = try allocator.dupe(@import("../../model/ReferenceData.zig").CollisionInducedAbsorptionPoint, &.{
                .{ .wavelength_nm = 405.0, .a0 = 0.5, .a1 = 0.0, .a2 = 0.0 },
                .{ .wavelength_nm = 465.0, .a0 = 1.5, .a1 = 0.0, .a2 = 0.0 },
            }),
        },
        .spectroscopy_lines = .{
            .lines = try allocator.dupe(@import("../../model/ReferenceData.zig").SpectroscopyLine, &.{
                .{ .center_wavelength_nm = 434.6, .line_strength_cm2_per_molecule = 1.0e-20, .air_half_width_nm = 0.04, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.002, .line_mixing_coefficient = 0.06 },
            }),
        },
        .mean_cross_section_cm2_per_molecule = 5.0e-19,
        .line_mean_cross_section_cm2_per_molecule = 7.5e-21,
        .line_mixing_mean_cross_section_cm2_per_molecule = 1.5e-21,
        .cia_mean_cross_section_cm5_per_molecule2 = 1.0e-46,
        .effective_air_mass_factor = 1.25,
        .effective_single_scatter_albedo = 0.92,
        .effective_temperature_k = 266.0,
        .effective_pressure_hpa = 550.0,
        .column_density_factor = 6.0e0,
        .cia_pair_path_factor_cm5 = 4.0e42,
        .aerosol_reference_wavelength_nm = 550.0,
        .aerosol_angstrom_exponent = 1.3,
        .cloud_reference_wavelength_nm = 550.0,
        .cloud_angstrom_exponent = 0.3,
        .gas_optical_depth = 0.19,
        .cia_optical_depth = 0.03,
        .aerosol_optical_depth = 0.07,
        .cloud_optical_depth = 0.04,
        .d_optical_depth_d_temperature = -1.5e-4,
        .depolarization_factor = 0.025,
        .total_optical_depth = 0.3,
    };
}

fn buildQuadratureSensitivePreparedOpticalState(allocator: Allocator) !PreparedOpticalState {
    return .{
        .layers = try allocator.dupe(@import("../optics/prepare.zig").PreparedLayer, &.{
            .{
                .layer_index = 0,
                .sublayer_start_index = 0,
                .sublayer_count = 2,
                .altitude_km = 2.0,
                .pressure_hpa = 820.0,
                .temperature_k = 280.0,
                .number_density_cm3 = 0.0,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_optical_depth = 0.0,
                .aerosol_optical_depth = 0.22,
                .cloud_optical_depth = 0.0,
                .layer_single_scatter_albedo = 1.0,
                .depolarization_factor = 0.0,
                .optical_depth = 0.22,
            },
            .{
                .layer_index = 1,
                .sublayer_start_index = 2,
                .sublayer_count = 2,
                .altitude_km = 8.0,
                .pressure_hpa = 380.0,
                .temperature_k = 245.0,
                .number_density_cm3 = 0.0,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_optical_depth = 0.0,
                .aerosol_optical_depth = 0.13,
                .cloud_optical_depth = 0.0,
                .layer_single_scatter_albedo = 1.0,
                .depolarization_factor = 0.0,
                .optical_depth = 0.13,
            },
        }),
        .sublayers = try allocator.dupe(@import("../optics/prepare.zig").PreparedSublayer, &.{
            .{
                .parent_layer_index = 0,
                .sublayer_index = 0,
                .altitude_km = 1.0,
                .pressure_hpa = 860.0,
                .temperature_k = 283.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 5.0e4,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.11,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.35, 0.12, 0.03 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.35, 0.12, 0.03 },
            },
            .{
                .parent_layer_index = 0,
                .sublayer_index = 1,
                .altitude_km = 3.0,
                .pressure_hpa = 780.0,
                .temperature_k = 277.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 5.0e4,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.11,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.32, 0.10, 0.02 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.32, 0.10, 0.02 },
            },
            .{
                .parent_layer_index = 1,
                .sublayer_index = 2,
                .altitude_km = 7.0,
                .pressure_hpa = 420.0,
                .temperature_k = 250.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 5.0e4,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.065,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.24, 0.09, 0.02 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.24, 0.09, 0.02 },
            },
            .{
                .parent_layer_index = 1,
                .sublayer_index = 3,
                .altitude_km = 9.0,
                .pressure_hpa = 340.0,
                .temperature_k = 240.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 5.0e4,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.065,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.21, 0.08, 0.02 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.21, 0.08, 0.02 },
            },
        }),
        .continuum_points = try allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = 430.0, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 435.0, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 440.0, .sigma_cm2_per_molecule = 0.0 },
        }),
        .mean_cross_section_cm2_per_molecule = 0.0,
        .line_mean_cross_section_cm2_per_molecule = 0.0,
        .line_mixing_mean_cross_section_cm2_per_molecule = 0.0,
        .cia_mean_cross_section_cm5_per_molecule2 = 0.0,
        .effective_air_mass_factor = 1.0,
        .effective_single_scatter_albedo = 1.0,
        .effective_temperature_k = 262.0,
        .effective_pressure_hpa = 560.0,
        .column_density_factor = 0.0,
        .cia_pair_path_factor_cm5 = 0.0,
        .aerosol_reference_wavelength_nm = 435.0,
        .aerosol_angstrom_exponent = 0.0,
        .cloud_reference_wavelength_nm = 435.0,
        .cloud_angstrom_exponent = 0.0,
        .gas_optical_depth = 0.0,
        .cia_optical_depth = 0.0,
        .aerosol_optical_depth = 0.35,
        .cloud_optical_depth = 0.0,
        .d_optical_depth_d_temperature = 0.0,
        .depolarization_factor = 0.0,
        .total_optical_depth = 0.35,
    };
}

fn buildNonuniformQuadraturePreparedOpticalState(allocator: Allocator) !PreparedOpticalState {
    return .{
        .layers = try allocator.dupe(@import("../optics/prepare.zig").PreparedLayer, &.{
            .{
                .layer_index = 0,
                .sublayer_start_index = 0,
                .sublayer_count = 4,
                .altitude_km = 5.0,
                .pressure_hpa = 650.0,
                .temperature_k = 268.0,
                .number_density_cm3 = 0.0,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_optical_depth = 0.0,
                .aerosol_optical_depth = 0.50,
                .cloud_optical_depth = 0.0,
                .layer_single_scatter_albedo = 1.0,
                .depolarization_factor = 0.0,
                .optical_depth = 0.50,
            },
        }),
        .sublayers = try allocator.dupe(@import("../optics/prepare.zig").PreparedSublayer, &.{
            .{
                .parent_layer_index = 0,
                .sublayer_index = 0,
                .altitude_km = 0.5,
                .pressure_hpa = 900.0,
                .temperature_k = 282.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 1.0e5,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.05,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.18, 0.04, 0.0 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.18, 0.04, 0.0 },
            },
            .{
                .parent_layer_index = 0,
                .sublayer_index = 1,
                .altitude_km = 2.0,
                .pressure_hpa = 790.0,
                .temperature_k = 276.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 2.0e5,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.09,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.24, 0.05, 0.0 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.24, 0.05, 0.0 },
            },
            .{
                .parent_layer_index = 0,
                .sublayer_index = 2,
                .altitude_km = 4.5,
                .pressure_hpa = 610.0,
                .temperature_k = 266.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 3.0e5,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.14,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.31, 0.07, 0.01 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.31, 0.07, 0.01 },
            },
            .{
                .parent_layer_index = 0,
                .sublayer_index = 3,
                .altitude_km = 8.0,
                .pressure_hpa = 430.0,
                .temperature_k = 255.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 4.0e5,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.22,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.38, 0.09, 0.02 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.38, 0.09, 0.02 },
            },
        }),
        .continuum_points = try allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = 430.0, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 435.0, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 440.0, .sigma_cm2_per_molecule = 0.0 },
        }),
        .mean_cross_section_cm2_per_molecule = 0.0,
        .line_mean_cross_section_cm2_per_molecule = 0.0,
        .line_mixing_mean_cross_section_cm2_per_molecule = 0.0,
        .cia_mean_cross_section_cm5_per_molecule2 = 0.0,
        .effective_air_mass_factor = 1.0,
        .effective_single_scatter_albedo = 1.0,
        .effective_temperature_k = 268.0,
        .effective_pressure_hpa = 650.0,
        .column_density_factor = 0.0,
        .cia_pair_path_factor_cm5 = 0.0,
        .aerosol_reference_wavelength_nm = 435.0,
        .aerosol_angstrom_exponent = 0.0,
        .cloud_reference_wavelength_nm = 435.0,
        .cloud_angstrom_exponent = 0.0,
        .gas_optical_depth = 0.0,
        .cia_optical_depth = 0.0,
        .aerosol_optical_depth = 0.50,
        .cloud_optical_depth = 0.0,
        .d_optical_depth_d_temperature = 0.0,
        .depolarization_factor = 0.0,
        .total_optical_depth = 0.50,
    };
}

fn buildSingleSubdivisionPreparedOpticalState(allocator: Allocator) !PreparedOpticalState {
    return .{
        .layers = try allocator.dupe(@import("../optics/prepare.zig").PreparedLayer, &.{
            .{
                .layer_index = 0,
                .sublayer_start_index = 0,
                .sublayer_count = 1,
                .altitude_km = 1.5,
                .pressure_hpa = 820.0,
                .temperature_k = 279.0,
                .number_density_cm3 = 0.0,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_optical_depth = 0.0,
                .aerosol_optical_depth = 0.16,
                .cloud_optical_depth = 0.0,
                .layer_single_scatter_albedo = 1.0,
                .depolarization_factor = 0.0,
                .optical_depth = 0.16,
            },
            .{
                .layer_index = 1,
                .sublayer_start_index = 1,
                .sublayer_count = 1,
                .altitude_km = 6.0,
                .pressure_hpa = 470.0,
                .temperature_k = 252.0,
                .number_density_cm3 = 0.0,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_optical_depth = 0.0,
                .aerosol_optical_depth = 0.11,
                .cloud_optical_depth = 0.0,
                .layer_single_scatter_albedo = 1.0,
                .depolarization_factor = 0.0,
                .optical_depth = 0.11,
            },
        }),
        .sublayers = try allocator.dupe(@import("../optics/prepare.zig").PreparedSublayer, &.{
            .{
                .parent_layer_index = 0,
                .sublayer_index = 0,
                .altitude_km = 1.5,
                .pressure_hpa = 820.0,
                .temperature_k = 279.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 3.0e5,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.16,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.22, 0.05, 0.0 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.22, 0.05, 0.0 },
            },
            .{
                .parent_layer_index = 1,
                .sublayer_index = 1,
                .altitude_km = 6.0,
                .pressure_hpa = 470.0,
                .temperature_k = 252.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 6.0e5,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.11,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.31, 0.08, 0.01 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.31, 0.08, 0.01 },
            },
        }),
        .continuum_points = try allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = 430.0, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 435.0, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 440.0, .sigma_cm2_per_molecule = 0.0 },
        }),
        .mean_cross_section_cm2_per_molecule = 0.0,
        .line_mean_cross_section_cm2_per_molecule = 0.0,
        .line_mixing_mean_cross_section_cm2_per_molecule = 0.0,
        .cia_mean_cross_section_cm5_per_molecule2 = 0.0,
        .effective_air_mass_factor = 1.0,
        .effective_single_scatter_albedo = 1.0,
        .effective_temperature_k = 266.0,
        .effective_pressure_hpa = 640.0,
        .column_density_factor = 0.0,
        .cia_pair_path_factor_cm5 = 0.0,
        .aerosol_reference_wavelength_nm = 435.0,
        .aerosol_angstrom_exponent = 0.0,
        .cloud_reference_wavelength_nm = 435.0,
        .cloud_angstrom_exponent = 0.0,
        .gas_optical_depth = 0.0,
        .cia_optical_depth = 0.0,
        .aerosol_optical_depth = 0.27,
        .cloud_optical_depth = 0.0,
        .d_optical_depth_d_temperature = 0.0,
        .depolarization_factor = 0.0,
        .total_optical_depth = 0.27,
    };
}

fn testProviders() ProviderBindings {
    const resolved = PluginProviders.PreparedProviders.resolve(.{}) catch unreachable;
    return .{
        .transport = resolved.transport,
        .surface = resolved.surface,
        .instrument = resolved.instrument,
        .noise = resolved.noise,
    };
}

fn fillSyntheticIntegratedSourceField(
    geo: *const labos.Geometry,
    ud: []labos.UDField,
) void {
    const solar_col: usize = 1;
    const view_idx = geo.viewIdx();
    const solar_idx = geo.n_gauss + 1;

    for (ud, 0..) |*field, ilevel| {
        field.* = .{
            .E = labos.Vec.zero(geo.nmutot),
            .U = labos.Vec2.zero(geo.nmutot),
            .D = labos.Vec2.zero(geo.nmutot),
        };

        const level_scale = @as(f64, @floatFromInt(ilevel + 1));
        field.E.set(view_idx, 0.40 + 0.08 * level_scale);
        field.E.set(solar_idx, 0.22 + 0.05 * level_scale);
        for (0..geo.n_gauss) |imu| {
            const mu_scale = @as(f64, @floatFromInt(imu + 1));
            field.D.col[solar_col].set(imu, 0.12 + 0.02 * level_scale + 0.01 * mu_scale);
            field.U.col[solar_col].set(imu, 0.08 + 0.015 * level_scale + 0.008 * mu_scale);
        }
    }

    // Zero the direct surface addend so changes come only from RTM quadrature nodes.
    ud[0].U.col[solar_col].set(view_idx, 0.0);
}

fn inputWithQuadrature(
    base_input: common.ForwardInput,
    levels: []const common.RtmQuadratureLevel,
) common.ForwardInput {
    var input = base_input;
    input.rtm_quadrature = .{ .levels = levels };
    return input;
}

fn blendLegacyPhaseCoefficients(
    left: [phase_coefficient_count]f64,
    left_weight: f64,
    right: [phase_coefficient_count]f64,
    right_weight: f64,
) [phase_coefficient_count]f64 {
    var blended = [_]f64{0.0} ** phase_coefficient_count;
    blended[0] = 1.0;
    const total_weight = @max(left_weight, 0.0) + @max(right_weight, 0.0);
    if (total_weight <= 0.0) return blended;
    for (0..phase_coefficient_count) |index| {
        blended[index] = (left[index] * @max(left_weight, 0.0) +
            right[index] * @max(right_weight, 0.0)) / total_weight;
    }
    return blended;
}

fn fillLegacyMidpointQuadratureLevels(
    prepared: *const PreparedOpticalState,
    layer_inputs: []const common.LayerInput,
    levels: []common.RtmQuadratureLevel,
) void {
    const sublayers = prepared.sublayers orelse unreachable;
    for (levels) |*level| {
        level.weight = 0.0;
        level.ksca = 0.0;
        level.phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 };
    }

    for (prepared.layers) |layer| {
        const start: usize = @intCast(layer.sublayer_start_index);
        const count: usize = @intCast(layer.sublayer_count);
        if (count <= 1) continue;
        const stop = start + count;

        var parent_scattering: f64 = 0.0;
        for (layer_inputs[start..stop]) |layer_input| {
            parent_scattering += @max(layer_input.scattering_optical_depth, 0.0);
        }

        var raw_scattering_sum: f64 = 0.0;
        for (start + 1..stop) |ilevel| {
            const left_sublayer = sublayers[ilevel - 1];
            const right_sublayer = sublayers[ilevel];
            const left_input = layer_inputs[ilevel - 1];
            const right_input = layer_inputs[ilevel];
            const left_span = @max(left_sublayer.path_length_cm / centimeters_per_kilometer, 0.0);
            const right_span = @max(right_sublayer.path_length_cm / centimeters_per_kilometer, 0.0);
            const node_span = 0.5 * (left_span + right_span);
            const left_scattering = @max(left_input.scattering_optical_depth, 0.0);
            const right_scattering = @max(right_input.scattering_optical_depth, 0.0);
            const node_ksca = if ((left_span + right_span) > 0.0)
                (left_scattering + right_scattering) / (left_span + right_span)
            else
                0.0;

            levels[ilevel].weight = node_span;
            levels[ilevel].ksca = node_ksca;
            levels[ilevel].phase_coefficients = blendLegacyPhaseCoefficients(
                left_input.phase_coefficients,
                left_scattering,
                right_input.phase_coefficients,
                right_scattering,
            );
            raw_scattering_sum += levels[ilevel].weightedScattering();
        }

        if (raw_scattering_sum > 0.0 and parent_scattering > 0.0) {
            const scale = parent_scattering / raw_scattering_sum;
            for (start + 1..stop) |ilevel| {
                levels[ilevel].weight *= scale;
            }
        } else {
            for (start + 1..stop) |ilevel| {
                levels[ilevel].weight = 0.0;
                levels[ilevel].ksca = 0.0;
            }
        }
    }
}

test "configured forward input preserves prepared source-function boundary weights" {
    const scene: Scene = .{
        .id = "measurement-source-interfaces",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .integrate_source_function = true,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [2]common.LayerInput = undefined;
    var pseudo_spherical_layers: [4]common.LayerInput = undefined;
    var source_interfaces: [3]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [3]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [4]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [3]usize = undefined;
    var pseudo_spherical_level_altitudes: [3]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    try std.testing.expectEqual(@as(usize, 2), input.layers.len);
    try std.testing.expectEqual(@as(usize, 3), input.source_interfaces.len);
    try std.testing.expectApproxEqRel(
        input.layers[0].scattering_optical_depth,
        input.source_interfaces[0].source_weight,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.source_interfaces[0].rtm_weight, 1.0e-12);
    try std.testing.expectApproxEqRel(
        0.5 * input.layers[1].scattering_optical_depth,
        input.source_interfaces[2].source_weight,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.source_interfaces[2].rtm_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.source_interfaces[1].source_weight, 1.0e-12);
    try std.testing.expect(input.source_interfaces[1].rtm_weight > 0.0);
    try std.testing.expect(input.source_interfaces[1].ksca_above >= 0.0);
    try std.testing.expectApproxEqRel(
        input.layers[1].scattering_optical_depth,
        input.source_interfaces[1].rtm_weight * input.source_interfaces[1].ksca_above,
        1.0e-12,
    );
    try std.testing.expectApproxEqRel(
        input.layers[1].phase_coefficients[1],
        input.source_interfaces[1].phase_coefficients_above[1],
        1.0e-12,
    );
}

test "configured forward input wires pseudo-spherical attenuation samples from prepared sublayers" {
    const scene: Scene = .{
        .id = "measurement-pseudo-spherical-grid",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .limb,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_spherical_correction = true,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [2]common.LayerInput = undefined;
    var pseudo_spherical_layers: [4]common.LayerInput = undefined;
    var source_interfaces: [3]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [3]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [4]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [3]usize = undefined;
    var pseudo_spherical_level_altitudes: [3]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    try std.testing.expect(input.pseudo_spherical_grid.isValidFor(input.layers.len));
    try std.testing.expectEqualSlices(usize, &.{ 0, 2, 4 }, input.pseudo_spherical_grid.level_sample_starts);
    try std.testing.expectEqualSlices(f64, &.{ 0.75, 7.75, 12.25 }, input.pseudo_spherical_grid.level_altitudes_km);
    try std.testing.expectApproxEqRel(@as(f64, 0.75), input.pseudo_spherical_grid.samples[0].altitude_km, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[0].thickness_km, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[0].optical_depth, 1.0e-12);
    try std.testing.expect(input.pseudo_spherical_grid.samples[1].thickness_km > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[1].optical_depth > 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[2].thickness_km, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[2].optical_depth, 1.0e-12);
    try std.testing.expect(input.pseudo_spherical_grid.samples[3].optical_depth > 0.0);
}

test "configured forward input builds adding pseudo-spherical subgrid within prepared RTM layers" {
    const scene: Scene = .{
        .id = "measurement-adding-pseudo-spherical-subgrid",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 30.0,
            .relative_azimuth_deg = 90.0,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .use_spherical_correction = true,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [4]common.LayerInput = undefined;
    var pseudo_spherical_layers: [8]common.LayerInput = undefined;
    var source_interfaces: [5]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [5]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [8]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [5]usize = undefined;
    var pseudo_spherical_level_altitudes: [5]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    try std.testing.expectEqual(@as(usize, 4), input.layers.len);
    try std.testing.expect(input.pseudo_spherical_grid.isValidFor(input.layers.len));
    try std.testing.expectEqual(@as(usize, 8), input.pseudo_spherical_grid.samples.len);
    try std.testing.expectEqualSlices(usize, &.{ 0, 2, 4, 6, 8 }, input.pseudo_spherical_grid.level_sample_starts);
    try std.testing.expectEqualSlices(f64, &.{ 0.75, 2.75, 7.75, 11.75, 12.25 }, input.pseudo_spherical_grid.level_altitudes_km);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[0].thickness_km, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[2].thickness_km, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[4].thickness_km, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[6].thickness_km, 1.0e-12);
    try std.testing.expect(input.pseudo_spherical_grid.samples[1].thickness_km > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[3].thickness_km > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[5].thickness_km > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[7].thickness_km > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[1].optical_depth > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[3].optical_depth > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[5].optical_depth > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[7].optical_depth > 0.0);
}

test "configured forward input leaves pseudo-spherical attenuation grid empty when prepared sublayers are unavailable" {
    const scene: Scene = .{
        .id = "measurement-pseudo-spherical-grid-fallback",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .limb,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_spherical_correction = true,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    const owned_sublayers = prepared.sublayers.?;
    prepared.sublayers = null;
    defer {
        std.testing.allocator.free(owned_sublayers);
        prepared.deinit(std.testing.allocator);
    }

    var layer_inputs: [2]common.LayerInput = undefined;
    var pseudo_spherical_layers: [4]common.LayerInput = undefined;
    var source_interfaces: [3]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [3]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [4]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [3]usize = undefined;
    var pseudo_spherical_level_altitudes: [3]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    try std.testing.expectEqual(@as(usize, 0), input.pseudo_spherical_grid.samples.len);
    try std.testing.expectEqual(@as(usize, 0), input.pseudo_spherical_grid.level_sample_starts.len);
}

test "configured forward input builds prepared adding RTM quadrature on sublayer grids" {
    const scene: Scene = .{
        .id = "measurement-adding-direct-grid",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .integrate_source_function = true,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [4]common.LayerInput = undefined;
    var pseudo_spherical_layers: [4]common.LayerInput = undefined;
    var source_interfaces: [5]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [5]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [4]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [5]usize = undefined;
    var pseudo_spherical_level_altitudes: [5]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    try std.testing.expectEqual(@as(usize, 4), input.layers.len);
    try std.testing.expectEqual(@as(usize, 5), input.source_interfaces.len);
    try std.testing.expect(input.rtm_controls.integrate_source_function);
    try std.testing.expect(input.rtm_quadrature.isValidFor(input.layers.len));
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.rtm_quadrature.levels[0].weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.rtm_quadrature.levels[2].weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.rtm_quadrature.levels[4].weight, 1.0e-12);
    try std.testing.expect(input.rtm_quadrature.levels[1].weight > 0.0);
    try std.testing.expect(input.rtm_quadrature.levels[3].weight > 0.0);
    try std.testing.expect(input.rtm_quadrature.levels[1].ksca > 0.0);
    try std.testing.expect(input.rtm_quadrature.levels[3].ksca > 0.0);

    var lower_interval_scattering: f64 = 0.0;
    for (input.layers[0..2]) |layer| lower_interval_scattering += @max(layer.scattering_optical_depth, 0.0);
    var upper_interval_scattering: f64 = 0.0;
    for (input.layers[2..4]) |layer| upper_interval_scattering += @max(layer.scattering_optical_depth, 0.0);
    try std.testing.expectApproxEqRel(
        lower_interval_scattering,
        input.rtm_quadrature.levels[1].weightedScattering(),
        1.0e-12,
    );
    try std.testing.expectApproxEqRel(
        upper_interval_scattering,
        input.rtm_quadrature.levels[3].weightedScattering(),
        1.0e-12,
    );
}

test "configured forward input builds prepared adding RTM quadrature from nonuniform sublayer intervals" {
    const scene: Scene = .{
        .id = "measurement-adding-nonuniform-grid",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 1,
            .sublayer_divisions = 4,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .integrate_source_function = true,
        },
    });
    var prepared = try buildNonuniformQuadraturePreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [4]common.LayerInput = undefined;
    var pseudo_spherical_layers: [4]common.LayerInput = undefined;
    var source_interfaces: [5]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [5]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [4]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [5]usize = undefined;
    var pseudo_spherical_level_altitudes: [5]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    try std.testing.expectEqual(@as(usize, 4), input.layers.len);
    try std.testing.expect(input.rtm_quadrature.isValidFor(input.layers.len));
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.rtm_quadrature.levels[0].weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.rtm_quadrature.levels[4].weight, 1.0e-12);
    const three_point = try gauss_legendre.rule(3);
    const expected_total_span_km = 10.0;
    for (0..3) |index| {
        try std.testing.expectApproxEqRel(
            0.5 * three_point.weights[index] * expected_total_span_km,
            input.rtm_quadrature.levels[index + 1].weight,
            1.0e-12,
        );
        try std.testing.expectApproxEqRel(
            0.5 * (three_point.nodes[index] + 1.0) * expected_total_span_km,
            input.rtm_quadrature.levels[index + 1].altitude_km,
            1.0e-12,
        );
    }
    try std.testing.expectApproxEqRel(@as(f64, 0.2050806661517033), input.rtm_quadrature.levels[1].phase_coefficients[1], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.32), input.rtm_quadrature.levels[2].phase_coefficients[1], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.38), input.rtm_quadrature.levels[3].phase_coefficients[1], 1.0e-12);
    try std.testing.expect(@abs(input.rtm_quadrature.levels[1].phase_coefficients[1] - @as(f64, 0.24)) > 1.0e-2);
    try std.testing.expect(@abs(input.rtm_quadrature.levels[2].phase_coefficients[1] - @as(f64, 0.38)) > 1.0e-2);

    const legacy_middle_weight = 2.5 * (10.0 / 7.5);
    try std.testing.expect(@abs(input.rtm_quadrature.levels[2].weight - legacy_middle_weight) > 1.0e-3);

    var total_scattering: f64 = 0.0;
    for (input.layers) |layer| total_scattering += @max(layer.scattering_optical_depth, 0.0);

    var quadrature_scattering: f64 = 0.0;
    for (input.rtm_quadrature.levels[1..4]) |level| {
        quadrature_scattering += level.weightedScattering();
    }
    try std.testing.expectApproxEqRel(total_scattering, quadrature_scattering, 1.0e-12);
}

test "prepared adding RTM quadrature recomputes node phase from prepared sublayer state" {
    var prepared = try buildNonuniformQuadraturePreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    const surrogate_layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.125,
            .scattering_optical_depth = 0.125,
            .single_scatter_albedo = 1.0,
            .phase_coefficients = .{ 1.0, 0.95, 0.0, 0.0 },
        },
        .{
            .optical_depth = 0.125,
            .scattering_optical_depth = 0.125,
            .single_scatter_albedo = 1.0,
            .phase_coefficients = .{ 1.0, 0.95, 0.0, 0.0 },
        },
        .{
            .optical_depth = 0.125,
            .scattering_optical_depth = 0.125,
            .single_scatter_albedo = 1.0,
            .phase_coefficients = .{ 1.0, 0.95, 0.0, 0.0 },
        },
        .{
            .optical_depth = 0.125,
            .scattering_optical_depth = 0.125,
            .single_scatter_albedo = 1.0,
            .phase_coefficients = .{ 1.0, 0.95, 0.0, 0.0 },
        },
    };
    var levels: [5]common.RtmQuadratureLevel = undefined;
    const has_quadrature = prepared.fillRtmQuadratureAtWavelengthWithLayers(435.0, &surrogate_layers, &levels);

    try std.testing.expect(has_quadrature);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), levels[0].weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), levels[4].weight, 1.0e-12);
    try std.testing.expect(@abs(levels[1].phase_coefficients[1] - @as(f64, 0.95)) > 1.0e-1);
    try std.testing.expect(@abs(levels[2].phase_coefficients[1] - @as(f64, 0.95)) > 1.0e-1);
    try std.testing.expect(@abs(levels[3].phase_coefficients[1] - @as(f64, 0.95)) > 1.0e-1);
    try std.testing.expectApproxEqRel(@as(f64, 0.2050806661517033), levels[1].phase_coefficients[1], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.32), levels[2].phase_coefficients[1], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.38), levels[3].phase_coefficients[1], 1.0e-12);
}

test "prepared adding live route uses nonuniform quadrature weights instead of the legacy midpoint surrogate" {
    const scene: Scene = .{
        .id = "measurement-adding-nonuniform-live",
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .surface = .{
            .albedo = 0.03,
        },
        .geometry = .{
            .model = .plane_parallel,
            .solar_zenith_deg = 54.0,
            .viewing_zenith_deg = 46.0,
            .relative_azimuth_deg = 78.0,
        },
        .atmosphere = .{
            .layer_count = 1,
            .sublayer_divisions = 4,
        },
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = true,
        },
    });

    var prepared = try buildNonuniformQuadraturePreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [4]common.LayerInput = undefined;
    var pseudo_spherical_layers: [4]common.LayerInput = undefined;
    var source_interfaces: [5]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [5]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [4]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [5]usize = undefined;
    var pseudo_spherical_level_altitudes: [5]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    var legacy_levels: [5]common.RtmQuadratureLevel = undefined;
    for (input.rtm_quadrature.levels, 0..) |level, index| {
        legacy_levels[index] = level;
    }
    fillLegacyMidpointQuadratureLevels(&prepared, input.layers, &legacy_levels);

    const providers = testProviders();
    const forward_new = try providers.transport.executePrepared(
        std.testing.allocator,
        route,
        input,
    );
    const forward_legacy = try providers.transport.executePrepared(
        std.testing.allocator,
        route,
        inputWithQuadrature(input, &legacy_levels),
    );

    try std.testing.expect(std.math.isFinite(forward_new.toa_reflectance_factor));
    try std.testing.expect(std.math.isFinite(forward_legacy.toa_reflectance_factor));
    try std.testing.expect(forward_new.toa_reflectance_factor > 0.0);
    try std.testing.expect(forward_legacy.toa_reflectance_factor > 0.0);
    try std.testing.expect(@abs(
        forward_new.toa_reflectance_factor - forward_legacy.toa_reflectance_factor,
    ) > 1.0e-8);
}

test "prepared adding live route falls back when no explicit RTM quadrature nodes exist" {
    const scene: Scene = .{
        .id = "measurement-adding-single-subdivision",
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .surface = .{
            .albedo = 0.04,
        },
        .geometry = .{
            .model = .plane_parallel,
            .solar_zenith_deg = 52.0,
            .viewing_zenith_deg = 44.0,
            .relative_azimuth_deg = 70.0,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 1,
        },
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = true,
        },
    });

    var prepared = try buildSingleSubdivisionPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [2]common.LayerInput = undefined;
    var pseudo_spherical_layers: [2]common.LayerInput = undefined;
    var source_interfaces: [3]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [3]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [2]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [3]usize = undefined;
    var pseudo_spherical_level_altitudes: [3]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    try std.testing.expectEqual(@as(usize, 2), input.layers.len);
    try std.testing.expectEqual(@as(usize, 0), input.rtm_quadrature.levels.len);
    try std.testing.expect(input.source_interfaces[1].rtm_weight > 0.0);

    const providers = testProviders();
    const forward_fallback = try providers.transport.executePrepared(
        std.testing.allocator,
        route,
        input,
    );
    const zero_quadrature = [_]common.RtmQuadratureLevel{
        .{},
        .{},
        .{},
    };
    const forward_bad = try providers.transport.executePrepared(
        std.testing.allocator,
        route,
        inputWithQuadrature(input, &zero_quadrature),
    );

    try std.testing.expect(std.math.isFinite(forward_fallback.toa_reflectance_factor));
    try std.testing.expect(forward_fallback.toa_reflectance_factor > 0.0);
    try std.testing.expect(@abs(
        forward_fallback.toa_reflectance_factor - forward_bad.toa_reflectance_factor,
    ) > 1.0e-8);
}

test "cached forward execution preserves prepared adding RTM quadrature and its reflectance semantics" {
    const scene: Scene = .{
        .id = "measurement-adding-direct-execution",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
    };
    const route_integrated = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
        .rtm_controls = .{
            .use_adding = true,
            .integrate_source_function = true,
        },
    });
    const route_direct = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
        .rtm_controls = .{
            .use_adding = true,
            .integrate_source_function = false,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);
    var integrated_cache = SpectralEvaluationCache.init(std.testing.allocator);
    defer integrated_cache.deinit();
    var direct_cache = SpectralEvaluationCache.init(std.testing.allocator);
    defer direct_cache.deinit();
    var integrated_layers: [4]common.LayerInput = undefined;
    var integrated_pseudo_layers: [4]common.LayerInput = undefined;
    var integrated_interfaces: [5]common.SourceInterfaceInput = undefined;
    var integrated_rtm_quadrature: [5]common.RtmQuadratureLevel = undefined;
    var integrated_pseudo_samples: [4]common.PseudoSphericalSample = undefined;
    var integrated_pseudo_level_starts: [5]usize = undefined;
    var integrated_pseudo_level_altitudes: [5]f64 = undefined;
    var direct_layers: [4]common.LayerInput = undefined;
    var direct_pseudo_layers: [4]common.LayerInput = undefined;
    var direct_interfaces: [5]common.SourceInterfaceInput = undefined;
    var direct_rtm_quadrature: [5]common.RtmQuadratureLevel = undefined;
    var direct_pseudo_samples: [4]common.PseudoSphericalSample = undefined;
    var direct_pseudo_level_starts: [5]usize = undefined;
    var direct_pseudo_level_altitudes: [5]f64 = undefined;
    const providers = testProviders();

    const integrated_sample = try cachedForwardAtWavelength(
        std.testing.allocator,
        &scene,
        route_integrated,
        &prepared,
        435.0,
        10.0,
        providers,
        &integrated_layers,
        &integrated_pseudo_layers,
        &integrated_interfaces,
        &integrated_rtm_quadrature,
        &integrated_pseudo_samples,
        &integrated_pseudo_level_starts,
        &integrated_pseudo_level_altitudes,
        &integrated_cache,
    );
    const direct_sample = try cachedForwardAtWavelength(
        std.testing.allocator,
        &scene,
        route_direct,
        &prepared,
        435.0,
        10.0,
        providers,
        &direct_layers,
        &direct_pseudo_layers,
        &direct_interfaces,
        &direct_rtm_quadrature,
        &direct_pseudo_samples,
        &direct_pseudo_level_starts,
        &direct_pseudo_level_altitudes,
        &direct_cache,
    );

    const explicit_input = configuredForwardInput(
        &scene,
        route_integrated,
        &prepared,
        435.0,
        &integrated_layers,
        &integrated_pseudo_layers,
        &integrated_interfaces,
        &integrated_rtm_quadrature,
        &integrated_pseudo_samples,
        &integrated_pseudo_level_starts,
        &integrated_pseudo_level_altitudes,
    );
    var fallback_interfaces: [5]common.SourceInterfaceInput = undefined;
    common.fillSourceInterfacesFromLayers(explicit_input.layers, &fallback_interfaces);
    const explicit_forward = try providers.transport.executePrepared(
        std.testing.allocator,
        route_integrated,
        explicit_input,
    );
    const geo = labos.Geometry.init(route_integrated.rtm_controls.nGauss(), explicit_input.mu0, explicit_input.muv);
    var synthetic_ud: [5]labos.UDField = undefined;
    fillSyntheticIntegratedSourceField(&geo, &synthetic_ud);
    const explicit_reflectance = labos.calcIntegratedReflectance(
        explicit_input.layers,
        explicit_input.source_interfaces,
        explicit_input.rtm_quadrature,
        &synthetic_ud,
        explicit_input.layers.len,
        0,
        &geo,
    );
    const fallback_reflectance = labos.calcIntegratedReflectance(
        explicit_input.layers,
        &fallback_interfaces,
        .{},
        &synthetic_ud,
        explicit_input.layers.len,
        0,
        &geo,
    );

    const cached_radiance = radianceFromForward(
        &scene,
        &prepared,
        providers,
        435.0,
        10.0,
        0.0,
        explicit_forward,
    );
    try std.testing.expect(explicit_input.rtm_quadrature.isValidFor(explicit_input.layers.len));
    try std.testing.expectApproxEqRel(
        cached_radiance,
        integrated_sample.radiance,
        1.0e-12,
    );
    try std.testing.expect(explicit_reflectance > 0.0);
    try std.testing.expect(@abs(fallback_reflectance - explicit_reflectance) > 1.0e-6);

    try std.testing.expect(@abs(
        direct_sample.radiance - integrated_sample.radiance,
    ) > 1.0e-8);
    try std.testing.expect(@abs(
        direct_sample.jacobian - integrated_sample.jacobian,
    ) > 1.0e-10);
}

test "prepared adding RTM quadrature keeps boundaries inert and interior samples active" {
    const scene: Scene = .{
        .id = "measurement-adding-boundary-weights",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
    };
    const route_integrated = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .integrate_source_function = true,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [4]common.LayerInput = undefined;
    var pseudo_spherical_layers: [4]common.LayerInput = undefined;
    var source_interfaces: [5]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [5]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [4]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [5]usize = undefined;
    var pseudo_spherical_level_altitudes: [5]f64 = undefined;
    const baseline_input = configuredForwardInput(
        &scene,
        route_integrated,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );
    const geo = labos.Geometry.init(route_integrated.rtm_controls.nGauss(), baseline_input.mu0, baseline_input.muv);
    var synthetic_ud: [5]labos.UDField = undefined;
    fillSyntheticIntegratedSourceField(&geo, &synthetic_ud);
    const baseline_integrated = labos.calcIntegratedReflectance(
        baseline_input.layers,
        baseline_input.source_interfaces,
        baseline_input.rtm_quadrature,
        &synthetic_ud,
        baseline_input.layers.len,
        0,
        &geo,
    );
    var boundary_quadrature = rtm_quadrature_levels;
    boundary_quadrature[2].ksca = 9.0;
    boundary_quadrature[2].phase_coefficients[1] = 0.95;
    const boundary_integrated = labos.calcIntegratedReflectance(
        baseline_input.layers,
        baseline_input.source_interfaces,
        .{ .levels = &boundary_quadrature },
        &synthetic_ud,
        baseline_input.layers.len,
        0,
        &geo,
    );
    var interior_quadrature = rtm_quadrature_levels;
    interior_quadrature[1].ksca *= 1.5;
    interior_quadrature[1].phase_coefficients[1] = 0.60;
    const interior_integrated = labos.calcIntegratedReflectance(
        baseline_input.layers,
        baseline_input.source_interfaces,
        .{ .levels = &interior_quadrature },
        &synthetic_ud,
        baseline_input.layers.len,
        0,
        &geo,
    );

    try std.testing.expect(baseline_input.rtm_quadrature.isValidFor(baseline_input.layers.len));
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), rtm_quadrature_levels[0].weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), rtm_quadrature_levels[2].weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), rtm_quadrature_levels[4].weight, 1.0e-12);
    try std.testing.expect(rtm_quadrature_levels[1].weight > 0.0);
    try std.testing.expectApproxEqRel(
        baseline_integrated,
        boundary_integrated,
        1.0e-12,
    );
    try std.testing.expect(@abs(
        baseline_integrated - interior_integrated,
    ) > 1.0e-8);
}

test "prepared adding live route consumes RTM quadrature while boundary nodes stay inert" {
    const scene: Scene = .{
        .id = "measurement-adding-live-quadrature",
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .surface = .{
            .albedo = 0.05,
        },
        .geometry = .{
            .model = .plane_parallel,
            .solar_zenith_deg = 53.13,
            .viewing_zenith_deg = 48.19,
            .relative_azimuth_deg = 75.0,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
    };
    const route_integrated = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = true,
        },
    });

    var prepared = try buildQuadratureSensitivePreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [4]common.LayerInput = undefined;
    var pseudo_spherical_layers: [4]common.LayerInput = undefined;
    var source_interfaces: [5]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [5]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [4]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [5]usize = undefined;
    var pseudo_spherical_level_altitudes: [5]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route_integrated,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );
    const providers = testProviders();
    const baseline = try providers.transport.executePrepared(
        std.testing.allocator,
        route_integrated,
        input,
    );

    var boundary_index: usize = 0;
    var interior_index: usize = 0;
    for (1..input.rtm_quadrature.levels.len - 1) |ilevel| {
        if (boundary_index == 0 and @abs(input.rtm_quadrature.levels[ilevel].weight) <= 1.0e-12) {
            boundary_index = ilevel;
        }
        if (interior_index == 0 and input.rtm_quadrature.levels[ilevel].weight > 0.0) {
            interior_index = ilevel;
        }
    }

    try std.testing.expect(input.rtm_quadrature.isValidFor(input.layers.len));
    try std.testing.expect(boundary_index != 0);
    try std.testing.expect(interior_index != 0);
    try std.testing.expect(baseline.toa_reflectance_factor > 0.0);

    var boundary_quadrature = rtm_quadrature_levels;
    boundary_quadrature[boundary_index].ksca = 25.0;
    boundary_quadrature[boundary_index].phase_coefficients[1] = 0.95;
    const boundary_forward = try providers.transport.executePrepared(
        std.testing.allocator,
        route_integrated,
        inputWithQuadrature(input, &boundary_quadrature),
    );

    var interior_quadrature = rtm_quadrature_levels;
    interior_quadrature[interior_index].ksca *= 4.0;
    interior_quadrature[interior_index].phase_coefficients[1] = 0.95;
    const interior_forward = try providers.transport.executePrepared(
        std.testing.allocator,
        route_integrated,
        inputWithQuadrature(input, &interior_quadrature),
    );

    try std.testing.expectApproxEqRel(
        baseline.toa_reflectance_factor,
        boundary_forward.toa_reflectance_factor,
        1.0e-10,
    );
    try std.testing.expect(@abs(
        baseline.toa_reflectance_factor - interior_forward.toa_reflectance_factor,
    ) > 1.0e-6);
}

test "summary workspace sizes adding transport buffers from sublayer hints" {
    const scene: Scene = .{
        .id = "measurement-adding-grid-hint",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
    };
    const route_labos = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    const route_adding = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
        },
    });

    var workspace: SummaryWorkspace = .{};
    defer workspace.deinit(std.testing.allocator);

    const labos_buffers = try workspace.buffers(
        std.testing.allocator,
        &scene,
        route_labos,
        testProviders(),
    );
    try std.testing.expectEqual(@as(usize, 2), labos_buffers.layer_inputs.len);
    try std.testing.expectEqual(@as(usize, 3), labos_buffers.source_interfaces.len);

    const adding_buffers = try workspace.buffers(
        std.testing.allocator,
        &scene,
        route_adding,
        testProviders(),
    );
    try std.testing.expectEqual(@as(usize, 4), adding_buffers.layer_inputs.len);
    try std.testing.expectEqual(@as(usize, 5), adding_buffers.source_interfaces.len);
}

test "measurement-space simulation supports adding routes on prepared sublayer grids" {
    const scene: Scene = .{
        .id = "measurement-space-adding-sublayers",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 16,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 4,
            .integrate_source_function = false,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    const summary = try simulateSummary(std.testing.allocator, &scene, route, &prepared, testProviders());
    try std.testing.expect(summary.mean_radiance > 0.0);
    try std.testing.expect(summary.mean_irradiance > 0.0);
    try std.testing.expect(summary.mean_reflectance > 0.0);
}

test "measurement-space simulation composes transport, calibration, convolution, and noise" {
    const scene: Scene = .{
        .id = "measurement-space",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 16,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    const summary = try simulateSummary(std.testing.allocator, &scene, route, &prepared, testProviders());
    try std.testing.expectEqual(@as(u32, 16), summary.sample_count);
    try std.testing.expect(summary.mean_radiance > 0.0);
    try std.testing.expect(summary.mean_irradiance > 0.0);
    try std.testing.expect(summary.mean_reflectance > 0.0);
    try std.testing.expect(summary.mean_reflectance < 10.0);
    try std.testing.expect(summary.mean_noise_sigma > 0.0);
    try std.testing.expect(summary.mean_jacobian != null);
}

test "measurement-space summary workspace reuses caller-owned buffers and matches full-product summaries" {
    const scene: Scene = .{
        .id = "measurement-summary-workspace",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 16,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var workspace: SummaryWorkspace = .{};
    defer workspace.deinit(std.testing.allocator);

    const first_summary = try simulateSummaryWithWorkspace(
        std.testing.allocator,
        &workspace,
        &scene,
        route,
        &prepared,
        testProviders(),
    );
    const wavelengths_ptr = @intFromPtr(workspace.wavelengths.ptr);
    const radiance_ptr = @intFromPtr(workspace.radiance.ptr);
    const jacobian_ptr = @intFromPtr(workspace.jacobian.ptr);
    const noise_ptr = @intFromPtr(workspace.noise_sigma.ptr);

    const second_summary = try simulateSummaryWithWorkspace(
        std.testing.allocator,
        &workspace,
        &scene,
        route,
        &prepared,
        testProviders(),
    );
    try std.testing.expectEqual(wavelengths_ptr, @intFromPtr(workspace.wavelengths.ptr));
    try std.testing.expectEqual(radiance_ptr, @intFromPtr(workspace.radiance.ptr));
    try std.testing.expectEqual(jacobian_ptr, @intFromPtr(workspace.jacobian.ptr));
    try std.testing.expectEqual(noise_ptr, @intFromPtr(workspace.noise_sigma.ptr));

    var product = try simulateProduct(std.testing.allocator, &scene, route, &prepared, testProviders());
    defer product.deinit(std.testing.allocator);

    try std.testing.expectEqual(first_summary.sample_count, second_summary.sample_count);
    try std.testing.expectApproxEqAbs(first_summary.mean_radiance, second_summary.mean_radiance, 1.0e-12);
    try std.testing.expectApproxEqAbs(first_summary.mean_radiance, product.summary.mean_radiance, 1.0e-12);
    try std.testing.expectApproxEqAbs(first_summary.mean_irradiance, product.summary.mean_irradiance, 1.0e-12);
    try std.testing.expectApproxEqAbs(first_summary.mean_reflectance, product.summary.mean_reflectance, 1.0e-12);
    try std.testing.expectApproxEqAbs(first_summary.mean_noise_sigma, product.summary.mean_noise_sigma, 1.0e-12);
    try std.testing.expectApproxEqAbs(first_summary.mean_jacobian.?, product.summary.mean_jacobian.?, 1.0e-12);
}

test "measurement-space summary workspace supports routes without jacobians or noise materialization" {
    const scene: Scene = .{
        .id = "measurement-summary-no-noise",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 10,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var workspace: SummaryWorkspace = .{};
    defer workspace.deinit(std.testing.allocator);

    const summary = try simulateSummaryWithWorkspace(
        std.testing.allocator,
        &workspace,
        &scene,
        route,
        &prepared,
        testProviders(),
    );
    var product = try simulateProduct(std.testing.allocator, &scene, route, &prepared, testProviders());
    defer product.deinit(std.testing.allocator);

    try std.testing.expect(summary.mean_radiance > 0.0);
    try std.testing.expectEqual(@as(f64, 0.0), summary.mean_noise_sigma);
    try std.testing.expect(summary.mean_jacobian == null);
    try std.testing.expectEqual(@as(usize, 0), workspace.jacobian.len);
    try std.testing.expectEqual(@as(usize, 0), workspace.noise_sigma.len);
    try std.testing.expectEqual(@as(usize, 0), product.noise_sigma.len);
    try std.testing.expect(product.jacobian == null);
}

test "ensureBufferCapacity preserves the original buffer on allocation failure" {
    var storage: [96]u8 = undefined;
    var fixed_buffer = std.heap.FixedBufferAllocator.init(&storage);
    const allocator = fixed_buffer.allocator();

    var buffer = try allocator.alloc(f64, 4);
    errdefer allocator.free(buffer);
    const original_ptr = buffer.ptr;
    const original_len = buffer.len;

    try std.testing.expectError(error.OutOfMemory, ensureBufferCapacity(allocator, &buffer, 32));
    try std.testing.expect(buffer.ptr == original_ptr);
    try std.testing.expectEqual(original_len, buffer.len);

    allocator.free(buffer);
}

test "measurement-space product materializes spectral vectors and physical fields" {
    const scene: Scene = .{
        .id = "measurement-product",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 12,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var product = try simulateProduct(std.testing.allocator, &scene, route, &prepared, testProviders());
    defer product.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 12), product.summary.sample_count);
    try std.testing.expectEqual(@as(usize, 12), product.wavelengths.len);
    try std.testing.expectEqual(product.wavelengths.len, product.radiance.len);
    try std.testing.expect(product.radiance[0] > 0.0);
    try std.testing.expect(product.irradiance[0] > 0.0);
    try std.testing.expect(product.reflectance[0] > 0.0);
    try std.testing.expect(product.noise_sigma[0] > 0.0);
    try std.testing.expect(product.jacobian != null);
    try std.testing.expectEqual(prepared.total_optical_depth, product.total_optical_depth);
    try std.testing.expectEqual(prepared.effective_air_mass_factor, product.effective_air_mass_factor);
    try std.testing.expectEqual(prepared.cia_optical_depth, product.cia_optical_depth);
    try std.testing.expect(product.effective_temperature_k > 0.0);
    try std.testing.expect(product.effective_pressure_hpa > 0.0);
}

test "measurement-space uses external high-resolution solar spectra when operational metadata provides one" {
    const operational_sigma = [_]f64{ 0.02, 0.02, 0.02 };
    const scene: Scene = .{
        .id = "measurement-operational-solar",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .s5p_operational,
            .ingested_noise_sigma = &operational_sigma,
            .reference_radiance = &.{ 1.0, 1.0, 1.0 },
            .operational_solar_spectrum = .{
                .wavelengths_nm = &[_]f64{ 405.0, 435.0, 465.0 },
                .irradiance = &[_]f64{ 1.0e14, 2.0e14, 3.0e14 },
            },
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var product = try simulateProduct(std.testing.allocator, &scene, route, &prepared, testProviders());
    defer product.deinit(std.testing.allocator);

    try std.testing.expect(product.irradiance[0] < product.irradiance[1]);
    try std.testing.expect(product.irradiance[1] < product.irradiance[2]);
    try std.testing.expect(product.reflectance[0] > product.reflectance[2]);
}

test "measurement-space uses bundled O2A solar spectra when bundle_default is requested" {
    const scene: Scene = .{
        .id = "measurement-bundled-o2a-solar",
        .spectral_grid = .{
            .start_nm = 760.0,
            .end_nm = 770.0,
            .sample_count = 11,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .shot_noise,
            .solar_spectrum_source = .bundle_default,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var product = try simulateProduct(std.testing.allocator, &scene, route, &prepared, testProviders());
    defer product.deinit(std.testing.allocator);

    try std.testing.expect(product.irradiance[0] > product.irradiance[2]);
    try std.testing.expect(product.irradiance[2] < product.irradiance[5]);
    try std.testing.expect(product.irradiance[5] > product.irradiance[10]);
}

test "measurement-space operational integration uses high-resolution instrument sampling" {
    const operational_sigma = [_]f64{0.02} ** 12;
    const plain_scene: Scene = .{
        .id = "measurement-plain",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 12,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const operational_scene: Scene = .{
        .id = "measurement-operational",
        .spectral_grid = plain_scene.spectral_grid,
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .measured_channels,
            .noise_model = .snr_from_input,
            .wavelength_shift_nm = 0.018,
            .instrument_line_fwhm_nm = 0.54,
            .ingested_noise_sigma = &operational_sigma,
        },
        .atmosphere = plain_scene.atmosphere,
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var plain_product = try simulateProduct(std.testing.allocator, &plain_scene, route, &prepared, testProviders());
    defer plain_product.deinit(std.testing.allocator);
    var operational_product = try simulateProduct(std.testing.allocator, &operational_scene, route, &prepared, testProviders());
    defer operational_product.deinit(std.testing.allocator);

    try std.testing.expectApproxEqAbs(plain_product.wavelengths[0], operational_product.wavelengths[0], 1.0e-12);
    try std.testing.expect(operational_product.radiance[0] != plain_product.radiance[0]);
    try std.testing.expect(operational_product.irradiance[0] != plain_product.irradiance[0]);
    try std.testing.expect(operational_product.jacobian != null);
}

test "measurement-space honors explicit measured-channel wavelengths from ingest" {
    const sigma = [_]f64{ 0.02, 0.02, 0.02 };
    const measured_wavelengths = [_]f64{ 405.15, 434.85, 464.75 };
    const scene: Scene = .{
        .id = "measurement-measured-wavelength-axis",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .measured_channels,
            .noise_model = .snr_from_input,
            .wavelength_shift_nm = 0.01,
            .measured_wavelengths_nm = &measured_wavelengths,
            .ingested_noise_sigma = &sigma,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var product = try simulateProduct(std.testing.allocator, &scene, route, &prepared, testProviders());
    defer product.deinit(std.testing.allocator);

    try std.testing.expectApproxEqAbs(@as(f64, 405.15), product.wavelengths[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 434.85), product.wavelengths[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 464.75), product.wavelengths[2], 1.0e-12);
}

test "measurement-space applies radiance calibration after instrument integration without rescaling irradiance" {
    const base_scene: Scene = .{
        .id = "measurement-calibration-base",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 12,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.08,
            .high_resolution_half_span_nm = 0.32,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const calibrated_scene: Scene = .{
        .id = "measurement-calibration-adjusted",
        .spectral_grid = base_scene.spectral_grid,
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.08,
            .high_resolution_half_span_nm = 0.32,
            .multiplicative_offset = 1.08,
            .stray_light = 0.03,
        },
        .atmosphere = base_scene.atmosphere,
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var base_product = try simulateProduct(std.testing.allocator, &base_scene, route, &prepared, testProviders());
    defer base_product.deinit(std.testing.allocator);
    var calibrated_product = try simulateProduct(std.testing.allocator, &calibrated_scene, route, &prepared, testProviders());
    defer calibrated_product.deinit(std.testing.allocator);

    try std.testing.expect(calibrated_product.radiance[0] > base_product.radiance[0]);
    try std.testing.expectApproxEqAbs(base_product.irradiance[0], calibrated_product.irradiance[0], 1.0e-12);
    try std.testing.expect(calibrated_product.reflectance[0] > base_product.reflectance[0]);
}

test "measurement-space operational integration honors explicit isrf table weights" {
    const gaussian_sigma = [_]f64{0.02} ** 12;
    const gaussian_scene: Scene = .{
        .id = "measurement-operational-gaussian",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 12,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .measured_channels,
            .noise_model = .snr_from_input,
            .wavelength_shift_nm = 0.018,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.08,
            .high_resolution_half_span_nm = 0.32,
            .ingested_noise_sigma = &gaussian_sigma,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const table_scene: Scene = .{
        .id = "measurement-operational-table",
        .spectral_grid = gaussian_scene.spectral_grid,
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .measured_channels,
            .noise_model = .snr_from_input,
            .wavelength_shift_nm = 0.018,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.08,
            .high_resolution_half_span_nm = 0.32,
            .instrument_line_shape = .{
                .sample_count = 5,
                .offsets_nm = &[_]f64{ -0.32, -0.16, 0.0, 0.16, 0.32 },
                .weights = &[_]f64{ 0.08, 0.24, 0.36, 0.22, 0.10 },
            },
            .ingested_noise_sigma = &gaussian_sigma,
        },
        .atmosphere = gaussian_scene.atmosphere,
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var gaussian_product = try simulateProduct(std.testing.allocator, &gaussian_scene, route, &prepared, testProviders());
    defer gaussian_product.deinit(std.testing.allocator);
    var table_product = try simulateProduct(std.testing.allocator, &table_scene, route, &prepared, testProviders());
    defer table_product.deinit(std.testing.allocator);

    try std.testing.expect(table_product.radiance[0] != gaussian_product.radiance[0]);
    try std.testing.expect(table_product.irradiance[0] != gaussian_product.irradiance[0]);
    try std.testing.expect(table_product.jacobian != null);
}

test "measurement-space operational integration selects wavelength-indexed isrf rows" {
    const indexed_sigma = [_]f64{0.02} ** 3;
    const global_shape_scene: Scene = .{
        .id = "measurement-operational-global-shape",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 407.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .measured_channels,
            .noise_model = .snr_from_input,
            .wavelength_shift_nm = 0.018,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.08,
            .high_resolution_half_span_nm = 0.32,
            .instrument_line_shape = .{
                .sample_count = 5,
                .offsets_nm = &[_]f64{ -0.32, -0.16, 0.0, 0.16, 0.32 },
                .weights = &[_]f64{ 0.08, 0.24, 0.36, 0.22, 0.10 },
            },
            .ingested_noise_sigma = &indexed_sigma,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    var indexed_table_nominals = [_]f64{ 405.0, 406.0, 407.0 };
    var indexed_table_offsets = [_]f64{ -0.32, -0.16, 0.0, 0.16, 0.32 };
    var indexed_table_weights = [_]f64{
        0.08, 0.24, 0.36, 0.22, 0.10,
        0.18, 0.30, 0.30, 0.15, 0.07,
        0.05, 0.18, 0.34, 0.26, 0.17,
    };
    const indexed_table: @import("../../model/Instrument.zig").InstrumentLineShapeTable = .{
        .nominal_count = 3,
        .sample_count = 5,
        .nominal_wavelengths_nm = indexed_table_nominals[0..],
        .offsets_nm = indexed_table_offsets[0..],
        .weights = indexed_table_weights[0..],
    };
    const indexed_table_scene: Scene = .{
        .id = "measurement-operational-indexed-table",
        .spectral_grid = global_shape_scene.spectral_grid,
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .measured_channels,
            .noise_model = .snr_from_input,
            .wavelength_shift_nm = 0.018,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.08,
            .high_resolution_half_span_nm = 0.32,
            .instrument_line_shape = global_shape_scene.observation_model.instrument_line_shape,
            .instrument_line_shape_table = indexed_table,
            .ingested_noise_sigma = &indexed_sigma,
        },
        .atmosphere = global_shape_scene.atmosphere,
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var global_shape_product = try simulateProduct(std.testing.allocator, &global_shape_scene, route, &prepared, testProviders());
    defer global_shape_product.deinit(std.testing.allocator);
    var indexed_table_product = try simulateProduct(std.testing.allocator, &indexed_table_scene, route, &prepared, testProviders());
    defer indexed_table_product.deinit(std.testing.allocator);

    try std.testing.expectApproxEqAbs(global_shape_product.radiance[0], indexed_table_product.radiance[0], 1e-12);
    try std.testing.expect(global_shape_product.radiance[1] != indexed_table_product.radiance[1]);
    try std.testing.expect(global_shape_product.radiance[2] != indexed_table_product.radiance[2]);
}
