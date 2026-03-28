//! Purpose:
//!   Define the typed plan template and the prepared-plan record used between engine
//!   preparation and execution.
//!
//! Physics:
//!   Captures the model family, solver mode, transport controls, plugin/provider selection, and
//!   prepared layout needed to evaluate a scene request consistently.
//!
//! Vendor:
//!   `plan preparation and prepared-plan state`
//!
//! Design:
//!   Keep the user-facing template lightweight and string-addressable today while the prepared
//!   plan stores the resolved transport route, plugin snapshot, runtime hooks, and reuse
//!   metadata.
//!
//! Invariants:
//!   Templates must name a supported model family and transport provider. Prepared plans own the
//!   plugin snapshot/runtime state associated with a unique plan id.
//!
//! Validation:
//!   Template validation tests in this file plus engine preparation tests that materialize and
//!   execute prepared plans.

const SceneModel = @import("../model/Scene.zig");
const ExecutionMode = @import("execution_mode.zig").ExecutionMode;
const PluginRegistry = @import("../plugins/registry/CapabilityRegistry.zig");
const PluginRuntime = @import("../plugins/loader/runtime.zig");
const PluginProviders = @import("../plugins/providers/root.zig");
const PluginSelection = @import("../plugins/selection.zig");
const PreparedLayout = @import("../runtime/cache/PreparedLayout.zig").PreparedLayout;
const RtmControls = @import("../kernels/transport/common.zig").RtmControls;
const TransportRoute = @import("../kernels/transport/common.zig").Route;
const std = @import("std");
const errors = @import("errors.zig");

pub const SolverMode = enum {
    scalar,
    polarized,
    derivative_enabled,
};

/// Purpose:
///   Describe the user-visible inputs required to prepare a typed execution plan.
pub const Template = struct {
    // TODO(owner=core, issue=WP-01, remove_when=model_family is represented by a typed enum across call sites):
    //   `model_family` is still stringly typed because the replacement touches the public root,
    //   adapters, exporters, plugins, and API wrappers in one coordinated migration.
    model_family: []const u8 = "disamar_standard",
    providers: PluginSelection.ProviderSelection = .{},
    solver_mode: SolverMode = .scalar,
    scene_blueprint: SceneModel.Blueprint = .{},
    rtm_controls: RtmControls = .{},

    /// Purpose:
    ///   Reject incomplete plan templates before provider resolution and plugin snapshotting.
    pub fn validate(self: Template) errors.TemplateError!void {
        if (self.model_family.len == 0) {
            return errors.TemplateError.MissingModelFamily;
        }
        if (self.providers.transport_solver.len == 0) {
            return errors.TemplateError.MissingTransportRoute;
        }
    }
};

/// Purpose:
///   Store the resolved execution contract produced by plan preparation.
///
/// Invariants:
///   The prepared layout, transport route, plugin snapshot, and plugin runtime all describe the
///   same plan id and must be deinitialized together.
pub const PreparedPlan = struct {
    allocator: std.mem.Allocator,
    id: u64,
    template: Template,
    execution_mode: ExecutionMode,
    operational_band_count: u32,
    transport_route: TransportRoute,
    prepared_layout: PreparedLayout = .{},
    plugin_snapshot: PluginRegistry.PluginSnapshot = .{},
    plugin_runtime: PluginRuntime.PreparedPluginRuntime = PluginRuntime.PreparedPluginRuntime.init(),
    providers: PluginProviders.PreparedProviders = .{},

    pub fn init(
        allocator: std.mem.Allocator,
        id: u64,
        template: Template,
        transport_route: TransportRoute,
        prepared_layout: PreparedLayout,
        plugin_snapshot: PluginRegistry.PluginSnapshot,
        plugin_runtime: PluginRuntime.PreparedPluginRuntime,
        providers: PluginProviders.PreparedProviders,
    ) PreparedPlan {
        return .{
            .allocator = allocator,
            .id = id,
            .template = template,
            .execution_mode = template.scene_blueprint.execution_mode,
            .operational_band_count = template.scene_blueprint.operational_band_count_hint,
            .transport_route = transport_route,
            .prepared_layout = prepared_layout,
            .plugin_snapshot = plugin_snapshot,
            .plugin_runtime = plugin_runtime,
            .providers = providers,
        };
    }

    /// Purpose:
    ///   Release the owned plugin runtime and snapshot captured during plan preparation.
    pub fn deinit(self: *PreparedPlan) void {
        self.plugin_runtime.deinit(self.allocator);
        self.plugin_snapshot.deinit(self.allocator);
        self.* = undefined;
    }
};

test "plan template validates existing provider selection" {
    try (Template{
        .providers = .{ .transport_solver = "builtin.dispatcher" },
    }).validate();
}
