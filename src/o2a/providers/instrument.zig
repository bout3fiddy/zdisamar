//! Purpose:
//!   Provide builtin instrument-response behavior for the registry-selected
//!   observation model.

const adaptive_trace = @import("instrument/adaptive_trace.zig");
const provider = @import("instrument/provider.zig");
const types = @import("instrument/types.zig");

pub const default_integration_sample_count = types.default_integration_sample_count;
pub const max_integration_sample_count = types.max_integration_sample_count;

pub const IntegrationKernel = types.IntegrationKernel;
pub const AdaptiveTraceIntervalKind = adaptive_trace.AdaptiveTraceIntervalKind;
pub const AdaptiveTraceInterval = adaptive_trace.AdaptiveTraceInterval;
pub const AdaptiveKernelTrace = adaptive_trace.AdaptiveKernelTrace;

pub const Provider = provider.Provider;

pub fn resolve(provider_id: []const u8) ?Provider {
    return provider.resolve(provider_id);
}

pub fn traceAdaptiveIntegrationKernel(
    allocator: @import("std").mem.Allocator,
    scene: *const @import("../../model/Scene.zig").Scene,
    prepared: *const @import("../../kernels/optics/preparation.zig").PreparedOpticalState,
    channel: @import("../../model/Instrument.zig").SpectralChannel,
    nominal_wavelength_nm: f64,
) !?AdaptiveKernelTrace {
    return adaptive_trace.traceAdaptiveIntegrationKernel(allocator, scene, prepared, channel, nominal_wavelength_nm);
}
