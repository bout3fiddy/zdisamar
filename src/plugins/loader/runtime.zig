//! Purpose:
//!   Resolve a capability snapshot into prepared native plugin runtimes.
//!
//! Physics:
//!   No physics is introduced here; this coordinates native plugin lifecycle
//!   hooks around the prepared plan and request execution stages.
//!
//! Vendor:
//!   `runtime`
//!
//! Design:
//!   Keep one runtime wrapper per snapshot, reuse a noop host API by default,
//!   and resolve builtin static plugins even when dynamic native plugins are
//!   disabled.
//!
//! Invariants:
//!   Resolved native plugins must be deinitialized in reverse ownership order
//!   and may only be prepared/executed after the resolver validates them.
//!
//! Validation:
//!   Covered by the prepared plugin runtime unit test in this file.
const std = @import("std");
const Abi = @import("../abi/abi_types.zig");
const BuiltinPlugins = @import("../builtin/root.zig");
const CapabilityRegistry = @import("../registry/CapabilityRegistry.zig");
const HostApi = @import("../abi/host_api.zig");
const ResolverModule = @import("resolver.zig");

/// Context passed to native plugins during plan preparation.
pub const PlanPrepareContext = struct {
    plan_id: u64,
    model_family: []const u8,
    transport_provider: []const u8,
    solver_mode: []const u8,
};

/// Context passed to native plugins during request execution.
pub const RequestExecuteContext = struct {
    plan_id: u64,
    scene_id: []const u8,
    workspace_label: []const u8,
    requested_product_count: u32,
};

/// Resolved native plugin and its ABI-owned resolution state.
pub const NativePluginRuntime = struct {
    manifest_id: []const u8,
    version: []const u8,
    resolution: ResolverModule.NativeResolution,

    /// Purpose:
    ///   Tear down the resolved native plugin and its library handle.
    ///
    /// Physics:
    ///   No physics; this is lifecycle cleanup for the plugin runtime.
    ///
    /// Vendor:
    ///   `runtime::NativePluginRuntime::deinit`
    ///
    /// Inputs:
    ///   The resolved plugin state stored on `self`.
    ///
    /// Outputs:
    ///   Calls the plugin destroy hook, closes the library, and poisons `self`.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   The plugin destroy hook accepts a null state for builtin fixtures.
    ///
    /// Decisions:
    ///   Destroy the plugin before closing the library so the hook remains
    ///   callable while its code is still loaded.
    ///
    /// Validation:
    ///   Covered by the prepared plugin runtime test in this file.
    pub fn deinit(self: *NativePluginRuntime) void {
        if (self.resolution.plugin_vtable.destroy) |destroy| {
            destroy(null);
        }
        self.resolution.close();
        self.* = undefined;
    }
};

/// Prepared runtime state for a plugin snapshot.
pub const PreparedPluginRuntime = struct {
    host_api_ref: HostApi.HostApiRef = .{},
    native_plugins: []NativePluginRuntime = &.{},

    /// Purpose:
    ///   Create a runtime wrapper with a noop host API.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `runtime::PreparedPluginRuntime::init`
    ///
    /// Inputs:
    ///   None.
    ///
    /// Outputs:
    ///   Returns an empty runtime ready for snapshot resolution.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   The caller will resolve a snapshot before preparing or executing.
    ///
    /// Decisions:
    ///   Start with a noop logger so code paths remain valid even without host
    ///   instrumentation.
    ///
    /// Validation:
    ///   Covered indirectly by the runtime unit test in this file.
    pub fn init() PreparedPluginRuntime {
        var runtime: PreparedPluginRuntime = .{};
        runtime.host_api_ref.initNoop();
        return runtime;
    }

    /// Purpose:
    ///   Release the resolved plugins and reset the runtime wrapper.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `runtime::PreparedPluginRuntime::deinit`
    ///
    /// Inputs:
    ///   `allocator` owns the native plugin array when present.
    ///
    /// Outputs:
    ///   Tears down all resolved plugins and frees their backing storage.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   The runtime may be deinitialized even if resolution failed partway.
    ///
    /// Decisions:
    ///   Reset the host API reference to the noop state after cleanup.
    ///
    /// Validation:
    ///   Covered by the runtime unit test in this file.
    pub fn deinit(self: *PreparedPluginRuntime, allocator: std.mem.Allocator) void {
        for (self.native_plugins) |*plugin| plugin.deinit();
        if (self.native_plugins.len != 0) allocator.free(self.native_plugins);
        self.* = init();
    }

    /// Purpose:
    ///   Resolve the plugin snapshot into native runtime handles.
    ///
    /// Physics:
    ///   No direct physics; this binds the planned plugin set to the host
    ///   execution context.
    ///
    /// Vendor:
    ///   `runtime::PreparedPluginRuntime::resolveSnapshot`
    ///
    /// Inputs:
    ///   `snapshot` is the filtered capability set selected for a plan.
    ///
    /// Outputs:
    ///   Populates `native_plugins` with resolved plugin runtimes.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   Builtin static plugins are available through the builtin registry when
    ///   the manifest does not point at a dynamic library.
    ///
    /// Decisions:
    ///   Allow builtin static symbols even when dynamic native plugins are
    ///   disallowed, because builtin support is part of the process image.
    ///
    /// Validation:
    ///   Covered by the runtime unit test in this file.
    pub fn resolveSnapshot(
        self: *PreparedPluginRuntime,
        allocator: std.mem.Allocator,
        snapshot: *const CapabilityRegistry.PluginSnapshot,
        allow_native_plugins: bool,
    ) Error!void {
        var native_count: usize = 0;
        for (snapshot.manifests) |manifest| {
            if (manifest.manifest.lane == .native) native_count += 1;
        }

        self.native_plugins = try allocator.alloc(NativePluginRuntime, native_count);
        errdefer allocator.free(self.native_plugins);

        var resolved_count: usize = 0;
        errdefer {
            for (self.native_plugins[0..resolved_count]) |*plugin| plugin.deinit();
        }

        for (snapshot.manifests) |manifest| {
            if (manifest.manifest.lane != .native) continue;

            const source = if (manifest.manifest.native.?.library_path) |path|
                ResolverModule.ResolutionSource{ .dynamic_path = path }
            else if (BuiltinPlugins.runtime_support.staticSymbolsFor(manifest.manifest.id)) |symbols|
                ResolverModule.ResolutionSource{ .static_symbols = symbols }
            else
                return error.MissingNativeSource;

            const native_allowed = switch (source) {
                .dynamic_path => allow_native_plugins,
                .static_symbols => true,
            };
            // DECISION:
            //   Static builtin symbols bypass the dynamic opt-in gate because
            //   they are already linked into the process image.
            const resolver = ResolverModule.Resolver.init(native_allowed, self.host_api_ref.asAbi());
            var resolution = try resolver.resolveNative(.{
                .manifest = manifest.manifest,
                .source = source,
            });
            errdefer resolution.close();

            self.native_plugins[resolved_count] = .{
                .manifest_id = manifest.manifest.id,
                .version = manifest.manifest.version,
                .resolution = resolution,
            };
            resolved_count += 1;
        }
    }

    /// Purpose:
    ///   Call each resolved plugin's prepare hook for a plan snapshot.
    ///
    /// Physics:
    ///   No direct physics; this is a lifecycle hook before retrieval or
    ///   forward execution begins.
    ///
    /// Vendor:
    ///   `runtime::PreparedPluginRuntime::prepareForPlan`
    ///
    /// Inputs:
    ///   `context` carries the plan metadata visible to native plugins.
    ///
    /// Outputs:
    ///   Returns success when every plugin accepts the prepare call.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   The resolver already validated that prepare hooks exist.
    ///
    /// Decisions:
    ///   Keep the hook call linear so the first failure aborts the plan.
    ///
    /// Validation:
    ///   Covered by the runtime unit test in this file.
    pub fn prepareForPlan(self: *PreparedPluginRuntime, context: PlanPrepareContext) Error!void {
        for (self.native_plugins) |plugin| {
            const prepare = plugin.resolution.plugin_vtable.prepare orelse return error.MissingPrepareHook;
            try mapPrepareStatus(prepare(&context, null));
        }
    }

    /// Purpose:
    ///   Call each resolved plugin's execute hook for a request snapshot.
    ///
    /// Physics:
    ///   No direct physics; this dispatches the request-time plugin hooks.
    ///
    /// Vendor:
    ///   `runtime::PreparedPluginRuntime::executeForRequest`
    ///
    /// Inputs:
    ///   `context` carries the request metadata visible to native plugins.
    ///
    /// Outputs:
    ///   Returns success when every plugin accepts the execution call.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   The resolver already validated that execute hooks exist.
    ///
    /// Decisions:
    ///   Keep request dispatch separate from plan preparation so the runtime can
    ///   report hook failures at the correct stage.
    ///
    /// Validation:
    ///   Covered by the runtime unit test in this file.
    pub fn executeForRequest(self: *const PreparedPluginRuntime, context: RequestExecuteContext) Error!void {
        for (self.native_plugins) |plugin| {
            const execute = plugin.resolution.plugin_vtable.execute orelse return error.MissingExecuteHook;
            try mapExecuteStatus(execute(&context, null));
        }
    }
};

pub const Error = ResolverModule.Error || error{
    MissingNativeSource,
    MissingPrepareHook,
    MissingExecuteHook,
    PluginPrepareRejected,
    PluginExecutionFailed,
};

fn mapPrepareStatus(raw_status: i32) Error!void {
    return switch (Abi.decodeStatus(raw_status)) {
        .ok => {},
        .invalid_argument => error.PluginPrepareRejected,
        .incompatible_abi => error.PluginEntryIncompatibleAbi,
        .internal => error.PluginPrepareRejected,
    };
}

fn mapExecuteStatus(raw_status: i32) Error!void {
    return switch (Abi.decodeStatus(raw_status)) {
        .ok => {},
        .invalid_argument => error.PluginExecutionFailed,
        .incompatible_abi => error.PluginEntryIncompatibleAbi,
        .internal => error.PluginExecutionFailed,
    };
}

test "prepared plugin runtime resolves selected builtin native manifests once per plan snapshot" {
    var registry: CapabilityRegistry.CapabilityRegistry = .{};
    defer registry.deinit(std.testing.allocator);
    try registry.bootstrapBuiltin(std.testing.allocator, true);

    var snapshot = try registry.snapshotSelection(std.testing.allocator, .{
        .retrieval_algorithm = "builtin.oe_solver",
        .instrument_response = "builtin.generic_response",
    });
    defer snapshot.deinit(std.testing.allocator);

    var runtime = PreparedPluginRuntime.init();
    defer runtime.deinit(std.testing.allocator);

    try runtime.resolveSnapshot(std.testing.allocator, &snapshot, true);
    try std.testing.expectEqual(@as(usize, 3), runtime.native_plugins.len);
    try runtime.prepareForPlan(.{
        .plan_id = 1,
        .model_family = "disamar_standard",
        .transport_provider = "builtin.dispatcher",
        .solver_mode = "scalar",
    });
    try runtime.executeForRequest(.{
        .plan_id = 1,
        .scene_id = "scene-plugin-runtime",
        .workspace_label = "unit",
        .requested_product_count = 0,
    });
}
