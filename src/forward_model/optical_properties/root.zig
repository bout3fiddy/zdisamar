pub const state = @import("state_build/state.zig");
pub const builder = @import("state_build/builder.zig");
pub const spectroscopy = @import("state_build/spectroscopy.zig");
pub const evaluation = @import("state_build/evaluation.zig");
pub const transport = @import("state_build/transport.zig");
pub const internal = @import("state_build/internal.zig");
pub const carrier_eval = @import("state_build/carrier_eval.zig");
pub const forward_layers = @import("state_build/forward_layers.zig");
pub const layer_accumulation = @import("state_build/layer_accumulation.zig");
pub const pseudo_spherical = @import("state_build/pseudo_spherical.zig");
pub const rtm_quadrature = @import("state_build/rtm_quadrature.zig");
pub const source_interfaces = @import("state_build/source_interfaces.zig");
pub const shared_geometry = @import("state_build/shared_geometry.zig");
pub const shared_carrier = @import("state_build/shared_carrier.zig");
pub const state_spectroscopy = @import("state_build/state_spectroscopy.zig");

pub const PreparationInputs = builder.PreparationInputs;
pub const PreparedLayer = state.PreparedLayer;
pub const PreparedSublayer = state.PreparedSublayer;
pub const OpticalDepthBreakdown = state.OpticalDepthBreakdown;
pub const PreparedOpticalState = state.PreparedOpticalState;

pub fn prepare(
    allocator: @import("std").mem.Allocator,
    scene: *const @import("../../input/Scene.zig").Scene,
    inputs: PreparationInputs,
) !PreparedOpticalState {
    return builder.prepare(allocator, scene, inputs);
}
