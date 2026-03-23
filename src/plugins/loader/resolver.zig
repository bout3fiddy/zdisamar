//! Purpose:
//!   Resolve manifest-declared native plugins into validated ABI handles.
//!
//! Physics:
//!   No physics is introduced here; this file is the native-plugin policy and
//!   ABI compatibility gate.
//!
//! Vendor:
//!   `resolver`
//!
//! Design:
//!   Validate the manifest first, then load the library, then compare the
//!   returned native metadata against the declarative manifest. That keeps the
//!   host in control of the trust boundary.
//!
//! Invariants:
//!   Native resolution must reject manifest/entrypoint mismatches before the
//!   resolved plugin is exposed to the runtime.
//!
//! Validation:
//!   Covered by the resolver unit tests in this file.
const std = @import("std");
const Manifest = @import("manifest.zig");
const DynLib = @import("dynlib.zig");
const Abi = @import("../abi/abi_types.zig");
const HostApi = @import("../abi/host_api.zig");

/// Source for a native plugin resolution.
pub const ResolutionSource = union(enum) {
    dynamic_path: []const u8,
    static_symbols: []const DynLib.SymbolEntry,
};

/// Request object for a native plugin resolution.
pub const ResolutionRequest = struct {
    manifest: Manifest.PluginManifest,
    source: ResolutionSource,
};

/// Result of a successful native plugin resolution.
pub const NativeResolution = struct {
    library: DynLib.Library,
    plugin_info: *const Abi.PluginInfo,
    plugin_vtable: *const Abi.PluginVTable,

    pub fn close(self: *NativeResolution) void {
        self.library.close();
        self.* = undefined;
    }
};

/// Errors raised while resolving a native plugin.
pub const Error = Manifest.Error || Abi.ValidationError || std.DynLib.Error || error{
    ManifestNotNative,
    MissingNativeEntryFunction,
    MissingPluginInfo,
    MissingPluginVTable,
    PluginEntryRejected,
    PluginEntryIncompatibleAbi,
    PluginIdMismatch,
    PluginVersionMismatch,
    EntrySymbolMismatch,
    LaneMismatch,
    CapabilityCountMismatch,
    CapabilitySlotMismatch,
    CapabilityNameMismatch,
    MissingVTableHooks,
    EntrySymbolTooLong,
};

/// Resolver state for one host policy context.
pub const Resolver = struct {
    allow_native_plugins: bool,
    host_api: *const Abi.HostApi,

    /// Purpose:
    ///   Build a resolver with the host's native-plugin policy.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `resolver::init`
    ///
    /// Inputs:
    ///   `allow_native_plugins` gates dynamic native loading and `host_api`
    ///   supplies the callback table handed to plugin entrypoints.
    ///
    /// Outputs:
    ///   Returns a resolver ready to resolve one native plugin request at a
    ///   time.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   When `host_api` is null, the resolver uses the noop host API.
    ///
    /// Decisions:
    ///   Keep the host API reference inside the resolver so entrypoint calls do
    ///   not need extra plumbing.
    ///
    /// Validation:
    ///   Covered by the resolver tests in this file.
    pub fn init(allow_native_plugins: bool, host_api: ?*const Abi.HostApi) Resolver {
        return .{
            .allow_native_plugins = allow_native_plugins,
            .host_api = host_api orelse &HostApi.noop_host_api,
        };
    }

    /// Purpose:
    ///   Resolve a manifest-declared native plugin into a validated runtime.
    ///
    /// Physics:
    ///   No direct physics; this prepares the plugin side of the transport or
    ///   retrieval pipeline.
    ///
    /// Vendor:
    ///   `resolver::resolveNative`
    ///
    /// Inputs:
    ///   `request.manifest` carries the declarative contract and `request.source`
    ///   carries the dynamic or static library source.
    ///
    /// Outputs:
    ///   Returns a loaded library, the plugin info struct, and the plugin vtable.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   The entry symbol can fit into the fixed local buffer.
    ///
    /// Decisions:
    ///   Validate the manifest first, then the entrypoint response, then the
    ///   resolved metadata so all compatibility checks stay centralized.
    ///
    /// Validation:
    ///   Covered by the resolver unit tests in this file.
    pub fn resolveNative(self: *const Resolver, request: ResolutionRequest) Error!NativeResolution {
        try request.manifest.validate(self.allow_native_plugins);
        if (request.manifest.lane != .native) return error.ManifestNotNative;

        const native = request.manifest.native orelse return error.MissingNativeContract;
        var entry_symbol_storage: [128]u8 = undefined;
        // GOTCHA:
        //   The entry symbol must be copied into a sentinel buffer because the
        //   ABI lookup helper expects a C-style string.
        const entry_symbol = try toSentinelSymbol(native.entry_symbol, &entry_symbol_storage);

        var library = switch (request.source) {
            .dynamic_path => |path| try DynLib.Library.open(path),
            .static_symbols => |entries| DynLib.Library.fromStaticSymbols(entries),
        };
        errdefer library.close();

        const entry_fn = library.lookup(Abi.PluginEntryFn, entry_symbol) orelse {
            return error.MissingNativeEntryFunction;
        };

        var plugin_info: ?*const Abi.PluginInfo = null;
        var plugin_vtable: ?*const Abi.PluginVTable = null;
        const status = Abi.decodeStatus(entry_fn(
            Abi.plugin_abi_version,
            self.host_api,
            &plugin_info,
            &plugin_vtable,
        ));

        switch (status) {
            .ok => {},
            .incompatible_abi => return error.PluginEntryIncompatibleAbi,
            else => return error.PluginEntryRejected,
        }

        const resolved_info = plugin_info orelse return error.MissingPluginInfo;
        const resolved_vtable = plugin_vtable orelse return error.MissingPluginVTable;

        try Abi.validatePluginInfo(resolved_info);
        try Abi.validatePluginVTable(resolved_vtable);
        try validateResolvedManifestCompatibility(resolved_info, request.manifest);
        try validateVTableHooks(resolved_vtable);

        return .{
            .library = library,
            .plugin_info = resolved_info,
            .plugin_vtable = resolved_vtable,
        };
    }
};

fn toSentinelSymbol(symbol: []const u8, storage: *[128]u8) Error![:0]const u8 {
    if (symbol.len == 0) return error.MissingEntrySymbol;
    // INVARIANT:
    //   The fixed buffer only accepts entry symbols that fit with a trailing
    //   sentinel byte.
    if (symbol.len + 1 > storage.len) return error.EntrySymbolTooLong;
    @memcpy(storage[0..symbol.len], symbol);
    storage[symbol.len] = 0;
    return storage[0..symbol.len :0];
}

fn validateResolvedManifestCompatibility(info: *const Abi.PluginInfo, manifest: Manifest.PluginManifest) Error!void {
    // INVARIANT:
    //   The entrypoint response must match the manifest before any hook table is
    //   trusted by the runtime.
    if (info.lane != .native) return error.LaneMismatch;

    const plugin_id = info.plugin_id orelse return error.MissingPluginId;
    if (!std.mem.eql(u8, std.mem.span(plugin_id), manifest.id)) {
        return error.PluginIdMismatch;
    }

    const plugin_version = info.plugin_version orelse return error.MissingPluginVersion;
    if (!std.mem.eql(u8, std.mem.span(plugin_version), manifest.version)) {
        return error.PluginVersionMismatch;
    }

    const native = manifest.native orelse return error.MissingNativeContract;
    const entry_symbol = info.entry_symbol orelse return error.MissingEntrySymbol;
    if (!std.mem.eql(u8, std.mem.span(entry_symbol), native.entry_symbol)) {
        return error.EntrySymbolMismatch;
    }

    if (info.capability_count != manifest.capabilities.len) {
        return error.CapabilityCountMismatch;
    }

    const capability_count: usize = @intCast(info.capability_count);
    if (capability_count == 0) return;
    const capabilities_ptr = info.capabilities orelse return error.MissingCapabilitiesPointer;
    const capabilities = capabilities_ptr[0..capability_count];
    for (capabilities, 0..) |capability, index| {
        const slot = capability.slot orelse return error.MissingCapabilitySlot;
        const name = capability.name orelse return error.MissingCapabilityName;
        if (!std.mem.eql(u8, std.mem.span(slot), manifest.capabilities[index].slot)) {
            return error.CapabilitySlotMismatch;
        }
        if (!std.mem.eql(u8, std.mem.span(name), manifest.capabilities[index].name)) {
            return error.CapabilityNameMismatch;
        }
    }
}

fn validateVTableHooks(vtable: *const Abi.PluginVTable) Error!void {
    // INVARIANT:
    //   Native plugins are not considered resolved unless prepare, execute, and
    //   destroy hooks are all present.
    if (vtable.prepare == null or vtable.execute == null or vtable.destroy == null) {
        return error.MissingVTableHooks;
    }
}

test "resolver resolves native plugin entry from static symbol source and validates metadata" {
    const Fixture = struct {
        fn prepare(_: ?*const anyopaque, _: ?*anyopaque) callconv(.c) i32 {
            return @intFromEnum(Abi.PluginStatus.ok);
        }

        fn execute(_: ?*const anyopaque, _: ?*anyopaque) callconv(.c) i32 {
            return @intFromEnum(Abi.PluginStatus.ok);
        }

        fn destroy(_: ?*anyopaque) callconv(.c) void {}

        const capabilities = [_]Abi.Capability{
            .{
                .slot = "transport.solver",
                .name = "example.native_transport",
            },
        };

        const plugin_info: Abi.PluginInfo = .{
            .struct_size = @sizeOf(Abi.PluginInfo),
            .plugin_id = "example.native_transport",
            .plugin_version = "0.1.0",
            .abi_version = Abi.plugin_abi_version,
            .lane = .native,
            .capability_count = capabilities.len,
            .capabilities = &capabilities,
            .entry_symbol = Abi.plugin_entry_symbol,
        };

        const plugin_vtable: Abi.PluginVTable = .{
            .struct_size = @sizeOf(Abi.PluginVTable),
            .prepare = prepare,
            .execute = execute,
            .destroy = destroy,
        };

        fn entry(
            expected_plugin_abi_version: u32,
            host_api: *const Abi.HostApi,
            out_info: *?*const Abi.PluginInfo,
            out_vtable: *?*const Abi.PluginVTable,
        ) callconv(.c) i32 {
            if (host_api.log_message) |log_message| {
                log_message(@intFromEnum(HostApi.LogLevel.info), "fixture plugin entry", host_api.user_data);
            }
            if (expected_plugin_abi_version != Abi.plugin_abi_version) {
                return @intFromEnum(Abi.PluginStatus.incompatible_abi);
            }
            out_info.* = &plugin_info;
            out_vtable.* = &plugin_vtable;
            return @intFromEnum(Abi.PluginStatus.ok);
        }
    };

    const Sink = struct {
        messages: usize = 0,

        fn log(user_data: ?*anyopaque, _: HostApi.LogLevel, _: []const u8) void {
            const ptr = user_data orelse return;
            const sink: *@This() = @ptrCast(@alignCast(ptr));
            sink.messages += 1;
        }
    };

    const symbols = [_]DynLib.SymbolEntry{
        .{
            .name = Abi.plugin_entry_symbol,
            .address = @ptrCast(&Fixture.entry),
        },
    };

    var sink = Sink{};
    var host_api_ref: HostApi.HostApiRef = .{};
    host_api_ref.init(Sink.log, &sink);

    const resolver = Resolver.init(true, host_api_ref.asAbi());
    var resolution = try resolver.resolveNative(.{
        .manifest = .{
            .id = "example.native_transport",
            .version = "0.1.0",
            .lane = .native,
            .capabilities = &[_]Manifest.CapabilityDecl{
                .{
                    .slot = "transport.solver",
                    .name = "example.native_transport",
                },
            },
            .native = .{
                .entry_symbol = "zdisamar_plugin_entry_v1",
            },
        },
        .source = .{
            .static_symbols = &symbols,
        },
    });
    defer resolution.close();

    try std.testing.expectEqual(@as(usize, 1), sink.messages);
    const resolved_id = std.mem.span((resolution.plugin_info.plugin_id orelse unreachable));
    try std.testing.expectEqualStrings("example.native_transport", resolved_id);
}

test "resolver rejects entry responses that do not match manifest capabilities" {
    const Fixture = struct {
        fn prepare(_: ?*const anyopaque, _: ?*anyopaque) callconv(.c) i32 {
            return @intFromEnum(Abi.PluginStatus.ok);
        }

        fn execute(_: ?*const anyopaque, _: ?*anyopaque) callconv(.c) i32 {
            return @intFromEnum(Abi.PluginStatus.ok);
        }

        fn destroy(_: ?*anyopaque) callconv(.c) void {}

        const capabilities = [_]Abi.Capability{
            .{
                .slot = "transport.solver",
                .name = "wrong.provider",
            },
        };

        const plugin_info: Abi.PluginInfo = .{
            .struct_size = @sizeOf(Abi.PluginInfo),
            .plugin_id = "example.native_transport",
            .plugin_version = "0.1.0",
            .abi_version = Abi.plugin_abi_version,
            .lane = .native,
            .capability_count = capabilities.len,
            .capabilities = &capabilities,
            .entry_symbol = Abi.plugin_entry_symbol,
        };

        const plugin_vtable: Abi.PluginVTable = .{
            .struct_size = @sizeOf(Abi.PluginVTable),
            .prepare = prepare,
            .execute = execute,
            .destroy = destroy,
        };

        fn entry(
            _: u32,
            _: *const Abi.HostApi,
            out_info: *?*const Abi.PluginInfo,
            out_vtable: *?*const Abi.PluginVTable,
        ) callconv(.c) i32 {
            out_info.* = &plugin_info;
            out_vtable.* = &plugin_vtable;
            return @intFromEnum(Abi.PluginStatus.ok);
        }
    };

    const symbols = [_]DynLib.SymbolEntry{
        .{
            .name = Abi.plugin_entry_symbol,
            .address = @ptrCast(&Fixture.entry),
        },
    };

    const resolver = Resolver.init(true, null);
    try std.testing.expectError(error.CapabilityNameMismatch, resolver.resolveNative(.{
        .manifest = .{
            .id = "example.native_transport",
            .version = "0.1.0",
            .lane = .native,
            .capabilities = &[_]Manifest.CapabilityDecl{
                .{
                    .slot = "transport.solver",
                    .name = "example.native_transport",
                },
            },
            .native = .{
                .entry_symbol = "zdisamar_plugin_entry_v1",
            },
        },
        .source = .{
            .static_symbols = &symbols,
        },
    }));
}
