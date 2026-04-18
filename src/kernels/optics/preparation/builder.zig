//! Purpose:
//!   Build the prepared optical state consumed by transport and measurement
//!   evaluation.
//!
//! Physics:
//!   Resolves climatology, spectroscopy, continuum, aerosol, cloud, and
//!   pseudo-spherical preparation into the typed transport-ready carriers.
//!
//! Vendor:
//!   `optics preparation builder`
//!
//! Design:
//!   Keeps the preparation logic in a typed staging area so the transport
//!   kernels do not own file-driven selection or mutable global state.
//!
//! Invariants:
//!   Prepared layers, sublayers, and sidecar state must remain aligned with
//!   the scene's atmospheric and spectral grid.
//!
//! Validation:
//!   Optics-preparation transport tests and transport integration suites.

const std = @import("std");
const Scene = @import("../../../model/Scene.zig").Scene;
const Accumulation = @import("accumulation.zig");
const Absorbers = @import("absorbers.zig");
const Context = @import("context.zig");
const Finalize = @import("finalize.zig");
const State = @import("state.zig");

const Allocator = std.mem.Allocator;

pub const PreparationInputs = Context.PreparationInputs;

/// Purpose:
///   Build the prepared optical state for one scene and input bundle.
pub fn prepare(
    allocator: Allocator,
    scene: *const Scene,
    inputs: PreparationInputs,
) !State.PreparedOpticalState {
    var context = try Context.init(allocator, scene, inputs);
    defer context.deinit(allocator);

    var absorber_state = try Absorbers.build(allocator, &context);
    defer absorber_state.deinit(allocator);

    const accumulation = try Accumulation.accumulate(allocator, &context, &absorber_state);

    var prepared = Finalize.assemble(&context, &absorber_state, accumulation);
    errdefer prepared.deinit(allocator);

    try prepared.ensureSharedRtmGeometryCache(allocator);
    return prepared;
}
