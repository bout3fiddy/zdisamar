pub const state = @import("preparation/state.zig");
pub const builder = @import("preparation/builder.zig");
pub const spectroscopy = @import("preparation/spectroscopy.zig");
pub const evaluation = @import("preparation/evaluation.zig");
pub const transport = @import("preparation/transport.zig");

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
