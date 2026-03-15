const std = @import("std");
const Abi = @import("../abi/abi_types.zig");
const HostApi = @import("../abi/host_api.zig");
const BuiltinPlugins = @import("../builtin/root.zig");
const Manifest = @import("manifest.zig");
const ResolverModule = @import("resolver.zig");
const CapabilityRegistry = @import("../registry/CapabilityRegistry.zig");

pub const max_prepared_native_capabilities: usize = CapabilityRegistry.max_snapshot_capabilities;

pub const PlanPrepareContext = struct {
    plan_id: u64,
    model_family: []const u8,
    transport_route: []const u8,
    solver_mode: []const u8,
};

pub const RequestExecuteContext = struct {
    plan_id: u64,
    scene_id: []const u8,
    workspace_label: []const u8,
    requested_product_count: u32,
};

pub const NativeCapabilityRuntime = struct {
    slot: []const u8,
    provider: []const u8,
    manifest_id: []const u8,
    version: []const u8,
    resolution: ResolverModule.NativeResolution,

    pub fn deinit(self: *NativeCapabilityRuntime) void {
        if (self.resolution.plugin_vtable.destroy) |destroy| {
            destroy(null);
        }
        self.resolution.close();
        self.* = undefined;
    }
};

pub const PreparedPluginRuntime = struct {
    host_api_ref: HostApi.HostApiRef = .{},
    native_count: usize = 0,
    native_capabilities: [max_prepared_native_capabilities]NativeCapabilityRuntime = undefined,

    pub fn init() PreparedPluginRuntime {
        var runtime: PreparedPluginRuntime = .{};
        runtime.host_api_ref.initNoop();
        return runtime;
    }

    pub fn deinit(self: *PreparedPluginRuntime) void {
        var remaining = self.native_count;
        while (remaining > 0) {
            remaining -= 1;
            self.native_capabilities[remaining].deinit();
        }
        self.* = init();
    }

    pub fn resolveSnapshot(
        self: *PreparedPluginRuntime,
        snapshot: *const CapabilityRegistry.PluginSnapshot,
    ) Error!void {
        for (snapshot.capabilities[0..snapshot.capability_count]) |capability| {
            if (capability.lane != .native) continue;
            if (std.mem.eql(u8, capability.slot, "exporter")) continue;
            if (self.native_count >= self.native_capabilities.len) {
                return error.TooManyNativeCapabilities;
            }

            const source = if (capability.native_library_path) |path|
                ResolverModule.ResolutionSource{ .dynamic_path = path }
            else if (BuiltinPlugins.staticSymbolsFor(capability.manifest_id)) |symbols|
                ResolverModule.ResolutionSource{ .static_symbols = symbols }
            else
                return error.MissingNativeSource;

            const resolver = ResolverModule.Resolver.init(true, self.host_api_ref.asAbi());
            const native_entry_symbol = capability.native_entry_symbol orelse Abi.plugin_entry_symbol;
            const manifest_capabilities = [_]Manifest.CapabilityDecl{
                .{
                    .slot = capability.slot,
                    .name = capability.provider,
                },
            };
            const manifest: Manifest.PluginManifest = .{
                .id = capability.manifest_id,
                .package = capability.package,
                .version = capability.version,
                .lane = .native,
                .capabilities = &manifest_capabilities,
                .native = .{
                    .entry_symbol = native_entry_symbol,
                    .library_path = capability.native_library_path,
                },
            };
            var resolution = try resolver.resolveNative(.{
                .manifest = manifest,
                .source = source,
            });
            errdefer resolution.close();

            self.native_capabilities[self.native_count] = .{
                .slot = capability.slot,
                .provider = capability.provider,
                .manifest_id = capability.manifest_id,
                .version = capability.version,
                .resolution = resolution,
            };
            self.native_count += 1;
        }
    }

    pub fn prepareForPlan(self: *PreparedPluginRuntime, context: PlanPrepareContext) Error!void {
        for (self.native_capabilities[0..self.native_count]) |capability| {
            const prepare = capability.resolution.plugin_vtable.prepare orelse return error.MissingPrepareHook;
            try mapPrepareStatus(prepare(&context, null));
        }
    }

    pub fn executeForRequest(self: *const PreparedPluginRuntime, context: RequestExecuteContext) Error!void {
        for (self.native_capabilities[0..self.native_count]) |capability| {
            const execute = capability.resolution.plugin_vtable.execute orelse return error.MissingExecuteHook;
            try mapExecuteStatus(execute(&context, null));
        }
    }
};

pub const Error = ResolverModule.Error || error{
    MissingNativeSource,
    TooManyNativeCapabilities,
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

test "prepared plugin runtime resolves builtin native capabilities once per snapshot" {
    var registry: CapabilityRegistry.CapabilityRegistry = .{};
    defer registry.deinit(std.testing.allocator);
    try registry.bootstrapBuiltin(std.testing.allocator);

    const snapshot = try registry.snapshot();
    var runtime = PreparedPluginRuntime.init();
    defer runtime.deinit();

    try runtime.resolveSnapshot(&snapshot);
    try std.testing.expectEqual(@as(usize, 4), runtime.native_count);
    try runtime.prepareForPlan(.{
        .plan_id = 1,
        .model_family = "disamar_standard",
        .transport_route = "transport.dispatcher",
        .solver_mode = "scalar",
    });
    try runtime.executeForRequest(.{
        .plan_id = 1,
        .scene_id = "scene-plugin-runtime",
        .workspace_label = "unit",
        .requested_product_count = 0,
    });
}
