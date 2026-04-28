pub const state = @import("preparation/state.zig");
pub const builder = @import("preparation/builder.zig");
pub const spectroscopy = @import("preparation/spectroscopy.zig");
pub const evaluation = @import("preparation/evaluation.zig");
pub const transport = @import("preparation/transport.zig");
pub const internal = @import("preparation/internal.zig");
pub const carrier_eval = @import("preparation/carrier_eval.zig");
pub const forward_layers = @import("preparation/forward_layers.zig");
pub const layer_accumulation = @import("preparation/layer_accumulation.zig");
pub const pseudo_spherical = @import("preparation/pseudo_spherical.zig");
pub const rtm_quadrature = @import("preparation/rtm_quadrature.zig");
pub const source_interfaces = @import("preparation/source_interfaces.zig");
pub const shared_geometry = @import("preparation/shared_geometry.zig");
pub const shared_carrier = @import("preparation/shared_carrier.zig");
pub const state_spectroscopy = @import("preparation/state_spectroscopy.zig");

pub const PreparationInputs = builder.PreparationInputs;
pub const PreparedLayer = state.PreparedLayer;
pub const PreparedSublayer = state.PreparedSublayer;
pub const OpticalDepthBreakdown = state.OpticalDepthBreakdown;
pub const PreparedOpticalState = state.PreparedOpticalState;

pub fn prepare(
    allocator: @import("std").mem.Allocator,
    scene: *const @import("../../model/Scene.zig").Scene,
    inputs: PreparationInputs,
) !PreparedOpticalState {
    return builder.prepare(allocator, scene, inputs);
}

test {
    _ = state;
    _ = builder;
    _ = spectroscopy;
    _ = evaluation;
    _ = transport;
}
