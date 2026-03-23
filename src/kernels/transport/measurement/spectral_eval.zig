//! Purpose:
//!   Evaluate transport output at instrument wavelengths and cache the
//!   spectral samples used by measurement-space materialization.
//!
//! Physics:
//!   Combines transport forward results with solar irradiance and instrument
//!   integration kernels, then reuses quantized wavelength caches for repeated
//!   samples.
//!
//! Vendor:
//!   `measurement spectral evaluation` stage
//!
//! Design:
//!   Caches at a fixed wavelength quantization so the measurement reduction
//!   can reuse forward and irradiance results without changing solver physics.
//!
//! Invariants:
//!   Cache keys must be stable for a given wavelength quantization and the
//!   bundled O2A irradiance reference remains band-limited.
//!
//! Validation:
//!   Measurement-space summary and product tests.

const std = @import("std");
const Scene = @import("../../../model/Scene.zig").Scene;
const OpticsPreparation = @import("../../optics/preparation.zig");
const common = @import("../common.zig");
const ForwardInput = @import("forward_input.zig");
const Types = @import("types.zig");
const Workspace = @import("workspace.zig");

const Allocator = std.mem.Allocator;
const OperationalInstrumentIntegration = @import("../../../plugins/providers/instrument.zig").IntegrationKernel;
const Error = Workspace.Error;

// DECISION:
//   Quantize spectral cache keys at the sub-picometer scale so repeated
//   transport samples reuse the same cache entry without altering physics.
const spectral_cache_quantization_nm = 1.0e-6;
// DECISION:
//   Keep the bundled O2A solar reference as a short reference band for the
//   default solar spectrum fallback.
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

pub const ForwardIntegratedSample = struct {
    radiance: f64,
    jacobian: f64 = 0.0,
};

/// Quantized spectral cache for repeated forward and irradiance samples.
pub const SpectralEvaluationCache = struct {
    allocator: Allocator,
    forward: std.AutoHashMap(i64, ForwardIntegratedSample),
    irradiance: std.AutoHashMap(i64, f64),

    /// Purpose:
    ///   Initialize the cache buckets for one measurement-space sweep.
    pub fn init(allocator: Allocator) SpectralEvaluationCache {
        return .{
            .allocator = allocator,
            .forward = std.AutoHashMap(i64, ForwardIntegratedSample).init(allocator),
            .irradiance = std.AutoHashMap(i64, f64).init(allocator),
        };
    }

    /// Purpose:
    ///   Release both spectral cache maps.
    pub fn deinit(self: *SpectralEvaluationCache) void {
        self.forward.deinit();
        self.irradiance.deinit();
        self.* = undefined;
    }

    /// Purpose:
    ///   Quantize a wavelength into the cache key space.
    pub fn keyFor(wavelength_nm: f64) i64 {
        return @as(i64, @intFromFloat(std.math.round(wavelength_nm / spectral_cache_quantization_nm)));
    }
};

/// Purpose:
///   Convert a transport forward result into radiance at one wavelength.
///
/// Vendor:
///   `measurement spectral evaluation`
pub fn radianceFromForward(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    providers: Types.ProviderBindings,
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
    prepared: *const OpticsPreparation.PreparedOpticalState,
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
        // PARITY:
        //   Preserve the bundled O2A band shape so the default spectrum matches
        //   the vendor reference range.
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

/// Purpose:
///   Integrate the forward model at one nominal instrument wavelength.
///
/// Vendor:
///   `measurement spectral evaluation`
pub fn integrateForwardAtNominal(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    nominal_wavelength_nm: f64,
    safe_span: f64,
    providers: Types.ProviderBindings,
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
    // DECISION:
    //   When the instrument has no internal integration kernel, fall back to
    //   the quantized cached forward sample at the nominal wavelength.
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

/// Purpose:
///   Integrate the solar irradiance at one nominal instrument wavelength.
///
/// Vendor:
///   `measurement spectral evaluation`
pub fn integrateIrradianceAtNominal(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    nominal_wavelength_nm: f64,
    safe_span: f64,
    cache: *SpectralEvaluationCache,
    integration: *const OperationalInstrumentIntegration,
) Error!f64 {
    // DECISION:
    //   Integrated instruments sample irradiance through the same kernel used
    //   for radiance so the instrument response stays aligned.
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

/// Purpose:
///   Cache and return a forward sample at one wavelength.
///
/// Vendor:
///   `measurement spectral evaluation`
pub fn cachedForwardAtWavelength(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
    providers: Types.ProviderBindings,
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

    // GOTCHA:
    //   Cache keys are quantized, so nearby samples share the same storage
    //   entry to match the measurement-space reuse contract.
    const input = ForwardInput.configuredForwardInput(
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

/// Purpose:
///   Cache and return a solar irradiance sample at one wavelength.
///
/// Vendor:
///   `measurement spectral evaluation`
fn cachedIrradianceAtWavelength(
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
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
