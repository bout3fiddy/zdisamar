const std = @import("std");
const Scene = @import("../../input/Scene.zig").Scene;
const Accumulation = @import("state_build/accumulation.zig");
const Absorbers = @import("state_build/absorbers.zig");
const Context = @import("state_build/context.zig");
const Finalize = @import("state_build/finalize.zig");
const Trace = @import("../performance_trace.zig");

pub const state = @import("state_build/state.zig");
pub const spectroscopy = @import("state_build/spectroscopy.zig");
pub const evaluation = @import("state_build/evaluation.zig");
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

pub const PreparationInputs = Context.PreparationInputs;
pub const BorrowedProfilePreparation = Context.BorrowedProfilePreparation;
pub const PreparedLayer = state.PreparedLayer;
pub const PreparedSublayer = state.PreparedSublayer;
pub const OpticalDepthBreakdown = state.OpticalDepthBreakdown;
pub const PreparedOpticalState = state.PreparedOpticalState;

pub fn prepare(
    allocator: std.mem.Allocator,
    scene: *const Scene,
    inputs: PreparationInputs,
) !PreparedOpticalState {
    var context = context: {
        // instrumentation: trace zone
        // captures: optical preparation context initialization
        // why: separate input-owned setup from absorber and layer construction.
        const zone = Trace.staticZone(@src(), "optical_prepare.context_init");
        defer zone.end();
        break :context try Context.init(allocator, scene, inputs);
    };
    defer context.deinit(allocator);

    var absorber_state = absorber_state: {
        // instrumentation: trace zone
        // captures: absorber preparation wall time
        // why: isolate spectroscopy and cross-section setup before layer accumulation.
        const zone = Trace.staticZone(@src(), "optical_prepare.absorbers_build");
        defer zone.end();
        break :absorber_state try Absorbers.build(allocator, &context);
    };
    defer absorber_state.deinit(allocator);

    const accumulation = accumulation: {
        // instrumentation: trace zone
        // captures: layer accumulation wall time
        // why: show cost of reducing atmospheric/spectroscopy data into RTM layers.
        const zone = Trace.staticZone(@src(), "optical_prepare.accumulation");
        defer zone.end();
        break :accumulation try Accumulation.accumulate(allocator, &context, &absorber_state);
    };

    var prepared = prepared: {
        // instrumentation: trace zone
        // captures: prepared optical-state finalization wall time
        // why: separate final data-layout assembly from physical layer accumulation.
        const zone = Trace.staticZone(@src(), "optical_prepare.finalize");
        defer zone.end();
        break :prepared Finalize.assemble(&context, &absorber_state, accumulation);
    };
    errdefer prepared.deinit(allocator);

    {
        // instrumentation: trace zone
        // captures: shared RTM geometry cache construction
        // why: distinguish reusable geometry setup from wavelength-dependent optical work.
        const zone = Trace.staticZone(@src(), "optical_prepare.shared_geometry");
        defer zone.end();
        try prepared.ensureSharedRtmGeometryCache(allocator);
    }
    return prepared;
}
