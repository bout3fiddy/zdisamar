//! Purpose:
//!   Define the stable native plugin ABI shared by host and plugin code.
//!
//! Physics:
//!   No physics is introduced here; this file is the contract layer for plugin
//!   metadata, lifecycle hooks, and validation.
//!
//! Vendor:
//!   `abi_types`
//!
//! Design:
//!   Keep the ABI explicit and versioned. Validation is separated from the
//!   struct definitions so host code can reject layout mismatches before any
//!   callback is trusted.
//!
//! Invariants:
//!   All exported ABI structs must retain their exact size checks and version
//!   tags.
//!
//! Validation:
//!   Exercised by the ABI validation tests at the bottom of this file.
const std = @import("std");

/// ABI version expected by plugin binaries.
pub const plugin_abi_version: u32 = 1;
/// ABI version expected by host API shims.
pub const host_api_version: u32 = 1;
/// Default entry symbol for native plugins.
pub const plugin_entry_symbol: [:0]const u8 = "zdisamar_plugin_entry_v1";

/// Native plugin status codes.
pub const PluginStatus = enum(i32) {
    ok = 0,
    invalid_argument = 1,
    incompatible_abi = 2,
    internal = 3,
};

/// Execution lane advertised by a plugin manifest.
pub const PluginLane = enum(u32) {
    declarative = 0,
    native = 1,
};

/// Capability slot/name pair exported by a native plugin.
pub const Capability = extern struct {
    slot: ?[*:0]const u8 = null,
    name: ?[*:0]const u8 = null,
};

/// Native plugin metadata returned from the entrypoint.
pub const PluginInfo = extern struct {
    struct_size: u32,
    plugin_id: ?[*:0]const u8 = null,
    plugin_version: ?[*:0]const u8 = null,
    abi_version: u32,
    lane: PluginLane,
    capability_count: u32,
    capabilities: ?[*]const Capability = null,
    entry_symbol: ?[*:0]const u8 = null,
};

/// Host callback table passed into native plugins.
pub const HostApi = extern struct {
    struct_size: u32,
    host_api_version: u32,
    log_message: ?*const fn (level: i32, message: ?[*:0]const u8, user_data: ?*anyopaque) callconv(.c) void = null,
    user_data: ?*anyopaque = null,
};

/// Native plugin vtable returned from the entrypoint.
pub const PluginVTable = extern struct {
    struct_size: u32,
    prepare: ?*const fn (plan_context: ?*const anyopaque, plugin_state: ?*anyopaque) callconv(.c) i32 = null,
    execute: ?*const fn (request_view: ?*const anyopaque, plugin_state: ?*anyopaque) callconv(.c) i32 = null,
    destroy: ?*const fn (plugin_state: ?*anyopaque) callconv(.c) void = null,
};

/// Native plugin entrypoint signature.
pub const PluginEntryFn = *const fn (
    expected_plugin_abi_version: u32,
    host_api: *const HostApi,
    out_info: *?*const PluginInfo,
    out_vtable: *?*const PluginVTable,
) callconv(.c) i32;

/// Validation errors raised while checking ABI contracts.
pub const ValidationError = error{
    InvalidPluginInfoStructSize,
    InvalidHostApiStructSize,
    InvalidPluginVTableStructSize,
    MissingPluginId,
    MissingPluginVersion,
    MissingEntrySymbol,
    MissingCapabilitiesPointer,
    MissingCapabilitySlot,
    MissingCapabilityName,
    UnsupportedPluginAbiVersion,
    UnsupportedHostApiVersion,
};

/// Purpose:
///   Translate a raw C integer status into the typed plugin status.
///
/// Physics:
///   None.
///
/// Vendor:
///   `abi_types::decodeStatus`
///
/// Inputs:
///   `raw` is the integer returned by a native callback.
///
/// Outputs:
///   Returns a typed status or `.internal` when the value is unknown.
///
/// Units:
///   Status code only.
///
/// Assumptions:
///   Unknown integers are treated as internal failures.
///
/// Decisions:
///   Keep the enum decode permissive so a broken plugin does not crash the
///   host.
///
/// Validation:
///   Covered implicitly by resolver and host API tests.
pub fn decodeStatus(raw: i32) PluginStatus {
    return std.meta.intToEnum(PluginStatus, raw) catch .internal;
}

/// Purpose:
///   Validate the host callback table before native plugins use it.
///
/// Physics:
///   None.
///
/// Vendor:
///   `abi_types::validateHostApi`
///
/// Inputs:
///   `host_api` is the ABI struct supplied to native plugins.
///
/// Outputs:
///   Returns success when the layout and version match.
///
/// Units:
///   N/A.
///
/// Assumptions:
///   The plugin and host agree on the ABI version.
///
/// Decisions:
///   Reject any mismatched struct size instead of attempting partial use.
///
/// Validation:
///   Covered by the host API tests and resolver tests.
pub fn validateHostApi(host_api: *const HostApi) ValidationError!void {
    if (host_api.struct_size != @sizeOf(HostApi)) {
        return error.InvalidHostApiStructSize;
    }
    if (host_api.host_api_version != host_api_version) {
        return error.UnsupportedHostApiVersion;
    }
}

/// Purpose:
///   Validate the plugin metadata contract returned from the entrypoint.
///
/// Physics:
///   None.
///
/// Vendor:
///   `abi_types::validatePluginInfo`
///
/// Inputs:
///   `info` is the plugin metadata pointer returned by the entry function.
///
/// Outputs:
///   Returns success when all required metadata fields are present.
///
/// Units:
///   N/A.
///
/// Assumptions:
///   The entrypoint returns sentinel-terminated strings and a valid capability
///   array when the count is non-zero.
///
/// Decisions:
///   Validate metadata eagerly so later resolution code can compare by value.
///
/// Validation:
///   Covered by the plugin-info unit test in this file.
pub fn validatePluginInfo(info: *const PluginInfo) ValidationError!void {
    if (info.struct_size != @sizeOf(PluginInfo)) {
        return error.InvalidPluginInfoStructSize;
    }
    if (info.abi_version != plugin_abi_version) {
        return error.UnsupportedPluginAbiVersion;
    }
    const plugin_id = info.plugin_id orelse return error.MissingPluginId;
    if (std.mem.len(plugin_id) == 0) {
        return error.MissingPluginId;
    }
    const plugin_version = info.plugin_version orelse return error.MissingPluginVersion;
    if (std.mem.len(plugin_version) == 0) {
        return error.MissingPluginVersion;
    }
    const entry_symbol = info.entry_symbol orelse return error.MissingEntrySymbol;
    if (std.mem.len(entry_symbol) == 0) {
        return error.MissingEntrySymbol;
    }
    if (info.capability_count > 0 and info.capabilities == null) {
        return error.MissingCapabilitiesPointer;
    }
    if (info.capabilities) |capabilities| {
        const count: usize = @intCast(info.capability_count);
        for (capabilities[0..count]) |capability| {
            const slot = capability.slot orelse return error.MissingCapabilitySlot;
            if (std.mem.len(slot) == 0) return error.MissingCapabilitySlot;
            const name = capability.name orelse return error.MissingCapabilityName;
            if (std.mem.len(name) == 0) return error.MissingCapabilityName;
        }
    }
}

/// Purpose:
///   Validate the native plugin vtable layout.
///
/// Physics:
///   None.
///
/// Vendor:
///   `abi_types::validatePluginVTable`
///
/// Inputs:
///   `vtable` is the hook table returned by the plugin entrypoint.
///
/// Outputs:
///   Returns success when the struct size matches the ABI contract.
///
/// Units:
///   N/A.
///
/// Assumptions:
///   Hook presence is checked by higher-level resolver code.
///
/// Decisions:
///   Keep this check focused on layout so hook validation can stay separate.
///
/// Validation:
///   Covered by resolver tests.
pub fn validatePluginVTable(vtable: *const PluginVTable) ValidationError!void {
    if (vtable.struct_size != @sizeOf(PluginVTable)) {
        return error.InvalidPluginVTableStructSize;
    }
}

test "plugin info validation rejects empty metadata and accepts complete contract" {
    const capabilities = [_]Capability{
        .{
            .slot = "transport.solver",
            .name = "builtin.dispatcher",
        },
    };

    const valid_info: PluginInfo = .{
        .struct_size = @sizeOf(PluginInfo),
        .plugin_id = "builtin.transport_dispatcher",
        .plugin_version = "0.1.0",
        .abi_version = plugin_abi_version,
        .lane = .native,
        .capability_count = capabilities.len,
        .capabilities = &capabilities,
        .entry_symbol = plugin_entry_symbol,
    };
    try validatePluginInfo(&valid_info);

    var invalid_info = valid_info;
    invalid_info.plugin_id = "";
    try std.testing.expectError(error.MissingPluginId, validatePluginInfo(&invalid_info));
}
