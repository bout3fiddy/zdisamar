const adaptive_plan = @import("adaptive_plan.zig");
const types = @import("types.zig");
const PreparedOpticalState = @import("../../../kernels/optics/preparation.zig").PreparedOpticalState;
const InstrumentModel = @import("../../../model/Instrument.zig").Instrument;
const Scene = @import("../../../model/Scene.zig").Scene;

pub const AdaptiveKernelCache = struct {
    ready: bool = false,
    global_start_nm: f64 = 0.0,
    global_end_nm: f64 = 0.0,
    plan: adaptive_plan.AdaptiveIntervalPlan = .{},
};

pub fn prepareAdaptiveKernelCache(
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    response: InstrumentModel.SpectralResponse,
    cache: *AdaptiveKernelCache,
) bool {
    cache.* = .{};
    const support_window = adaptive_plan.adaptiveKernelSupportWindow(
        scene,
        response,
        scene.spectral_grid.start_nm,
    );
    if (!adaptive_plan.buildAdaptiveIntervalPlan(scene, prepared, response, &cache.plan)) {
        return false;
    }
    cache.ready = true;
    cache.global_start_nm = support_window.global_start_nm;
    cache.global_end_nm = support_window.global_end_nm;
    return true;
}

pub fn buildAdaptiveIntegrationKernelFromCache(
    response: InstrumentModel.SpectralResponse,
    nominal_wavelength_nm: f64,
    cache: *const AdaptiveKernelCache,
    kernel: *types.IntegrationKernel,
) bool {
    if (!cache.ready) return false;

    var sample_wavelengths_nm: [types.max_integration_sample_count]f64 = undefined;
    var sample_raw_weights: [types.max_integration_sample_count]f64 = undefined;
    var sample_count: usize = 0;
    if (!adaptive_plan.appendAdaptiveSamplesFromPlan(
        &cache.plan,
        response,
        nominal_wavelength_nm,
        cache.global_start_nm,
        cache.global_end_nm,
        &sample_wavelengths_nm,
        &sample_raw_weights,
        &sample_count,
        null,
    )) return false;

    return adaptive_plan.finalizeAdaptiveKernel(
        kernel,
        nominal_wavelength_nm,
        sample_wavelengths_nm[0..sample_count],
        sample_raw_weights[0..sample_count],
    );
}
