const adaptive_plan = @import("adaptive_plan.zig");
const types = @import("types.zig");
const PreparedOpticalState = @import("../../optical_properties/root.zig").PreparedOpticalState;
const InstrumentModel = @import("../../../input/Instrument.zig").Instrument;
const Scene = @import("../../../input/Scene.zig").Scene;

// layout(64-bit):
//   size: 49184 B, align: 8 B
//   field storage: global_start_nm=8 B, global_end_nm=8 B, plan=49160 B, ready=1 B; padding: 7 B (56 bits)
//   unused bits: 56 padding + 7 bool-storage slack = 63 bits
//   cache span: 769 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 49184 B (48.0 KiB); total = per instance * live instance count
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
    apply_disamar_midpoint_bias: bool,
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
        apply_disamar_midpoint_bias,
        &sample_wavelengths_nm,
        &sample_raw_weights,
        &sample_count,
    )) return false;

    return adaptive_plan.finalizeAdaptiveKernel(
        kernel,
        nominal_wavelength_nm,
        sample_wavelengths_nm[0..sample_count],
        sample_raw_weights[0..sample_count],
    );
}
