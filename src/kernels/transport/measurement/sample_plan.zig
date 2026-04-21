//! Purpose:
//!   Precompute per-sample wavelength and integration plans for measurement
//!   simulation.
//!
//! Physics:
//!   Resolves nominal and calibrated wavelengths together with instrument
//!   integration kernels so radiance, irradiance, and prefetch passes share
//!   one spectral execution plan.
//!
//! Vendor:
//!   `measurement simulation planning`
//!
//! Design:
//!   Keep plan construction separate from the transport execution loops so the
//!   hot path stops rebuilding identical instrument metadata per sample.
//!
//! Invariants:
//!   Each plan entry is keyed to one nominal sample wavelength and contains the
//!   exact channel-specific calibrated wavelength and integration kernel.
//!
//! Validation:
//!   Fast measurement-space suites and O2 A transport smoke tests.

const std = @import("std");
const Scene = @import("../../../model/Scene.zig").Scene;
const OpticsPreparation = @import("../../optics/preparation.zig");
const calibration = @import("../../spectra/calibration.zig");
const grid = @import("../../spectra/grid.zig");
const SpectralEval = @import("spectral_eval.zig");
const Types = @import("types.zig");
const IntegrationKernel = @import("../../../o2a/providers/instrument.zig").IntegrationKernel;
const instrument_integration = @import("../../../o2a/providers/instrument/integration.zig");

const Allocator = std.mem.Allocator;

pub const SamplePlan = struct {
    nominal_wavelength_nm: f64,
    radiance_wavelength_nm: f64,
    irradiance_wavelength_nm: f64,
    radiance_integration: IntegrationKernel,
    irradiance_integration: IntegrationKernel,
};

pub fn buildSamplePlans(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    resolved_axis: *const grid.ResolvedAxis,
    radiance_calibration: calibration.Calibration,
    irradiance_calibration: calibration.Calibration,
    providers: Types.ProviderBindings,
) ![]SamplePlan {
    const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
    const plans = try allocator.alloc(SamplePlan, sample_count);
    errdefer allocator.free(plans);
    const can_cache_adaptive_plan = prepared.spectroscopy_lines != null and
        std.mem.eql(u8, providers.instrument.id, "builtin.generic_response");
    var radiance_adaptive_cache: instrument_integration.AdaptiveKernelCache = .{};
    var irradiance_adaptive_cache: instrument_integration.AdaptiveKernelCache = .{};
    if (can_cache_adaptive_plan) {
        _ = instrument_integration.prepareAdaptiveKernelCache(
            scene,
            prepared,
            .radiance,
            &radiance_adaptive_cache,
        );
        _ = instrument_integration.prepareAdaptiveKernelCache(
            scene,
            prepared,
            .irradiance,
            &irradiance_adaptive_cache,
        );
    }

    for (plans, 0..) |*plan, index| {
        const nominal_wavelength_nm = try resolved_axis.sampleAt(@intCast(index));
        var radiance_integration: IntegrationKernel = undefined;
        if (can_cache_adaptive_plan) {
            try instrument_integration.integrationForWavelengthWithAdaptiveCacheChecked(
                scene,
                prepared,
                .radiance,
                nominal_wavelength_nm,
                &radiance_adaptive_cache,
                &radiance_integration,
            );
        } else {
            try instrument_integration.integrationForWavelengthChecked(
                scene,
                prepared,
                .radiance,
                nominal_wavelength_nm,
                &radiance_integration,
            );
        }
        var irradiance_integration: IntegrationKernel = undefined;
        if (can_cache_adaptive_plan) {
            try instrument_integration.integrationForWavelengthWithAdaptiveCacheChecked(
                scene,
                prepared,
                .irradiance,
                nominal_wavelength_nm,
                &irradiance_adaptive_cache,
                &irradiance_integration,
            );
        } else {
            try instrument_integration.integrationForWavelengthChecked(
                scene,
                prepared,
                .irradiance,
                nominal_wavelength_nm,
                &irradiance_integration,
            );
        }
        plan.* = .{
            .nominal_wavelength_nm = nominal_wavelength_nm,
            .radiance_wavelength_nm = calibration.shiftedWavelength(
                radiance_calibration,
                nominal_wavelength_nm,
            ),
            .irradiance_wavelength_nm = calibration.shiftedWavelength(
                irradiance_calibration,
                nominal_wavelength_nm,
            ),
            .radiance_integration = radiance_integration,
            .irradiance_integration = irradiance_integration,
        };
    }
    return plans;
}

pub fn collectUniqueForwardMisses(
    allocator: Allocator,
    plans: []const SamplePlan,
) ![]SpectralEval.ForwardCacheMiss {
    var seen = std.AutoHashMap(i64, void).init(allocator);
    defer seen.deinit();
    var misses = std.ArrayList(SpectralEval.ForwardCacheMiss).empty;
    errdefer misses.deinit(allocator);

    for (plans) |plan| {
        const integration_sample_count = if (plan.radiance_integration.enabled) plan.radiance_integration.sample_count else 1;
        for (0..integration_sample_count) |sample_index| {
            const wavelength_nm = if (plan.radiance_integration.enabled)
                plan.radiance_wavelength_nm + plan.radiance_integration.offsets_nm[sample_index]
            else
                plan.radiance_wavelength_nm;
            const key = SpectralEval.SpectralEvaluationCache.keyFor(wavelength_nm);
            const entry = try seen.getOrPut(key);
            if (entry.found_existing) continue;
            try misses.append(allocator, .{
                .key = key,
                .wavelength_nm = wavelength_nm,
            });
        }
    }

    return misses.toOwnedSlice(allocator);
}
