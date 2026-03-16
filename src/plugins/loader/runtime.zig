const std = @import("std");
const Abi = @import("../abi/abi_types.zig");
const BuiltinPlugins = @import("../builtin/root.zig");
const CapabilityRegistry = @import("../registry/CapabilityRegistry.zig");
const HostApi = @import("../abi/host_api.zig");
const ResolverModule = @import("resolver.zig");

pub const PlanPrepareContext = struct {
    plan_id: u64,
    model_family: []const u8,
    transport_provider: []const u8,
    solver_mode: []const u8,
};

pub const RequestExecuteContext = struct {
    plan_id: u64,
    scene_id: []const u8,
    workspace_label: []const u8,
    requested_product_count: u32,
};

pub const NativePluginRuntime = struct {
    manifest_id: []const u8,
    version: []const u8,
    resolution: ResolverModule.NativeResolution,

    pub fn deinit(self: *NativePluginRuntime) void {
        if (self.resolution.plugin_vtable.destroy) |destroy| {
            destroy(null);
        }
        self.resolution.close();
        self.* = undefined;
    }
};

pub const PreparedPluginRuntime = struct {
    host_api_ref: HostApi.HostApiRef = .{},
    native_plugins: []NativePluginRuntime = &.{},

    pub fn init() PreparedPluginRuntime {
        var runtime: PreparedPluginRuntime = .{};
        runtime.host_api_ref.initNoop();
        return runtime;
    }

    pub fn deinit(self: *PreparedPluginRuntime, allocator: std.mem.Allocator) void {
        for (self.native_plugins) |*plugin| plugin.deinit();
        if (self.native_plugins.len != 0) allocator.free(self.native_plugins);
        self.* = init();
    }

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

    pub fn prepareForPlan(self: *PreparedPluginRuntime, context: PlanPrepareContext) Error!void {
        for (self.native_plugins) |plugin| {
            const prepare = plugin.resolution.plugin_vtable.prepare orelse return error.MissingPrepareHook;
            try mapPrepareStatus(prepare(&context, null));
        }
    }

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
