const std = @import("std");
const Scene = @import("../../input/Scene.zig").Scene;
const Accumulation = @import("state_build/accumulation.zig");
const Absorbers = @import("state_build/absorbers.zig");
const Context = @import("state_build/context.zig");
const Finalize = @import("state_build/finalize.zig");
const Trace = @import("../instrumentation/trace.zig");

// root.zig ---------------------------------------------------------------------------------------------------|
// Public optical-property preparation facade for Scene -> PreparedOpticalState.                               |
//                                                                                                             |
// called by                                                                                                   |
//   src/root.zig prepare() reaches this through bundled/reference-data loading.                               |
//   input/reference_data/bundled/load.zig uses prepare() after it hydrates the working Scene and reference    |
//   tables. input/o2a_reference/run.zig refreshes PreparedOpticalState for vendor O2 A cases and retrievals.  |
//   optimal_estimation/retrieval.zig calls this while mutating state-dependent O2 A scenes.                   |
//                                                                                                             |
// public surface                                                                                              |
//   PreparationInputs and BorrowedProfilePreparation are setup contracts. PreparedLayer, PreparedSublayer,    |
//   OpticalDepthBreakdown, and PreparedOpticalState are re-exported through this facade so callers have one   |
//   preparation entry point for the state_build split.                                                        |
//                                                                                                             |
// prepare route                                                                                               |
//   Scene + PreparationInputs                                                                                 |
//     -> Context.init                   borrows reference inputs and allocates temporary preparation rows     |
//     -> Absorbers.build                prepares active line/cross-section absorber rows and spectroscopy     |
//     -> Accumulation.accumulate        reduces atmosphere/support rows into layer means and optical depths   |
//     -> Finalize.assemble              moves owners into PreparedOpticalState and clears setup owners        |
//     -> ensureSharedRtmGeometryCache   builds reusable transport geometry for wavelength-time routes         |
//                                                                                                             |
// instrumentation                                                                                             |
//   Trace zones split context setup, absorber preparation, layer accumulation, final assembly, and shared     |
//   RTM geometry so retained benchmark traces can show where optical preparation time moved.                  |
//                                                                                                             |
// ownership                                                                                                   |
//   Context and AbsorberBuildState own temporary arrays until Finalize.assemble moves them into the final     |
//   PreparedOpticalState header. After that handoff, PreparedOpticalState.deinit owns the release order.      |
// ------------------------------------------------------------------------------------------------------------|

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

    const means = accumulation: {

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
        break :prepared Finalize.assemble(&context, &absorber_state, means);
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
