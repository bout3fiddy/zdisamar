const std = @import("std");
const core_errors = @import("../../core/errors.zig");
const Scene = @import("../../model/Scene.zig").Scene;
const PreparedOpticalState = @import("../optics/prepare.zig").PreparedOpticalState;
const grid = @import("../spectra/grid.zig");
const calibration = @import("../spectra/calibration.zig");
const convolution = @import("../spectra/convolution.zig");
const common = @import("common.zig");
const InstrumentProviders = @import("../../plugins/providers/instrument.zig");
const NoiseProviders = @import("../../plugins/providers/noise.zig");
const PluginProviders = @import("../../plugins/providers/root.zig");
const SurfaceProviders = @import("../../plugins/providers/surface.zig");
const TransportProviders = @import("../../plugins/providers/transport.zig");

const Allocator = std.mem.Allocator;
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
    jacobian: []f64 = &.{},
    noise_sigma: []f64 = &.{},

    pub fn deinit(self: *SummaryWorkspace, allocator: Allocator) void {
        freeBuffer(allocator, self.wavelengths);
        freeBuffer(allocator, self.radiance);
        freeBuffer(allocator, self.irradiance);
        freeBuffer(allocator, self.reflectance);
        freeBuffer(allocator, self.scratch);
        freeLayerBuffer(allocator, self.layer_inputs);
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
        const layer_count: usize = @max(@as(usize, @intCast(scene.atmosphere.layer_count)), 1);
        const wants_jacobian = route.derivative_mode != .none;
        const wants_noise = providers.noise.materializesSigma(scene);

        try ensureBufferCapacity(allocator, &self.wavelengths, sample_count);
        try ensureBufferCapacity(allocator, &self.radiance, sample_count);
        try ensureBufferCapacity(allocator, &self.irradiance, sample_count);
        try ensureBufferCapacity(allocator, &self.reflectance, sample_count);
        try ensureBufferCapacity(allocator, &self.scratch, sample_count);
        try ensureLayerBufferCapacity(allocator, &self.layer_inputs, layer_count);
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
            scene,
            route,
            prepared,
            evaluation_wavelength_nm,
            safe_span,
            providers,
            buffers.layer_inputs[0..prepared.layers.len],
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
        buffers.scratch[index] = integrateIrradianceAtNominal(
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
    const layer_inputs = try allocator.alloc(common.LayerInput, prepared.layers.len);
    defer allocator.free(layer_inputs);

    const summary = try simulate(allocator, scene, route, prepared, providers, .{
        .wavelengths = wavelengths,
        .radiance = radiance,
        .irradiance = irradiance,
        .reflectance = reflectance,
        .scratch = scratch,
        .layer_inputs = layer_inputs,
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

fn validateBuffers(sample_count: usize, buffers: Buffers) Error!void {
    if (sample_count == 0 or
        buffers.wavelengths.len != sample_count or
        buffers.radiance.len != sample_count or
        buffers.irradiance.len != sample_count or
        buffers.reflectance.len != sample_count or
        buffers.scratch.len != sample_count or
        buffers.layer_inputs.len == 0)
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

fn freeBuffer(allocator: Allocator, buffer: []f64) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn freeLayerBuffer(allocator: Allocator, buffer: []common.LayerInput) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn configuredForwardInput(
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []common.LayerInput,
) common.ForwardInput {
    return prepared.toForwardInputAtWavelengthWithLayers(scene, wavelength_nm, layer_inputs);
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
    scene: *const Scene,
    route: common.Route,
    prepared: *const PreparedOpticalState,
    nominal_wavelength_nm: f64,
    safe_span: f64,
    providers: ProviderBindings,
    layer_inputs: []common.LayerInput,
    cache: *SpectralEvaluationCache,
    integration: *const OperationalInstrumentIntegration,
) Error!ForwardIntegratedSample {
    if (!integration.enabled) {
        return cachedForwardAtWavelength(
            scene,
            route,
            prepared,
            nominal_wavelength_nm,
            safe_span,
            providers,
            layer_inputs,
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
            scene,
            route,
            prepared,
            wavelength_nm,
            safe_span,
            providers,
            layer_inputs,
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
) f64 {
    if (!integration.enabled) {
        return cachedIrradianceAtWavelength(scene, prepared, nominal_wavelength_nm, safe_span, cache);
    }

    var irradiance_sum: f64 = 0.0;
    for (0..integration.sample_count) |index| {
        const offset_nm = integration.offsets_nm[index];
        const weight = integration.weights[index];
        irradiance_sum += weight * cachedIrradianceAtWavelength(
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
    scene: *const Scene,
    route: common.Route,
    prepared: *const PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
    providers: ProviderBindings,
    layer_inputs: []common.LayerInput,
    cache: *SpectralEvaluationCache,
) Error!ForwardIntegratedSample {
    const key = SpectralEvaluationCache.keyFor(wavelength_nm);
    if (cache.forward.get(key)) |cached| return cached;

    const input = configuredForwardInput(scene, prepared, wavelength_nm, layer_inputs);
    const forward = try providers.transport.executePrepared(route, input);
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
) f64 {
    const key = SpectralEvaluationCache.keyFor(wavelength_nm);
    if (cache.irradiance.get(key)) |cached| return cached;

    const value = irradianceAtWavelength(scene, prepared, wavelength_nm, safe_span);
    cache.irradiance.put(key, value) catch return value;
    return value;
}

fn buildTestPreparedOpticalState(allocator: Allocator) !PreparedOpticalState {
    return .{
        .layers = try allocator.dupe(@import("../optics/prepare.zig").PreparedLayer, &.{
            .{ .layer_index = 0, .altitude_km = 2.0, .pressure_hpa = 820.0, .temperature_k = 280.0, .number_density_cm3 = 2.0e19, .continuum_cross_section_cm2_per_molecule = 5.0e-19, .line_cross_section_cm2_per_molecule = 1.0e-20, .line_mixing_cross_section_cm2_per_molecule = 2.0e-21, .cia_optical_depth = 0.03, .d_cross_section_d_temperature_cm2_per_molecule_per_k = -1.0e-23, .gas_optical_depth = 0.12, .aerosol_optical_depth = 0.05, .cloud_optical_depth = 0.03, .layer_single_scatter_albedo = 0.94, .depolarization_factor = 0.03, .optical_depth = 0.2 },
            .{ .layer_index = 1, .altitude_km = 10.0, .pressure_hpa = 280.0, .temperature_k = 240.0, .number_density_cm3 = 6.0e18, .continuum_cross_section_cm2_per_molecule = 5.0e-19, .line_cross_section_cm2_per_molecule = 5.0e-21, .line_mixing_cross_section_cm2_per_molecule = 1.0e-21, .d_cross_section_d_temperature_cm2_per_molecule_per_k = -5.0e-24, .cia_optical_depth = 0.0, .gas_optical_depth = 0.07, .aerosol_optical_depth = 0.02, .cloud_optical_depth = 0.01, .layer_single_scatter_albedo = 0.96, .depolarization_factor = 0.02, .optical_depth = 0.1 },
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

fn testProviders() ProviderBindings {
    const resolved = PluginProviders.PreparedProviders.resolve(.{}) catch unreachable;
    return .{
        .transport = resolved.transport,
        .surface = resolved.surface,
        .instrument = resolved.instrument,
        .noise = resolved.noise,
    };
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
            .layer_count = 12,
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
            .layer_count = 12,
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
            .layer_count = 12,
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
            .layer_count = 12,
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
            .layer_count = 12,
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
            .layer_count = 12,
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
            .layer_count = 12,
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
            .layer_count = 12,
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
            .layer_count = 12,
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
            .layer_count = 12,
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
            .layer_count = 12,
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
