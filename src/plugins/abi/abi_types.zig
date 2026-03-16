const std = @import("std");

pub const plugin_abi_version: u32 = 1;
pub const host_api_version: u32 = 1;
pub const plugin_entry_symbol: [:0]const u8 = "zdisamar_plugin_entry_v1";

pub const PluginStatus = enum(i32) {
    ok = 0,
    invalid_argument = 1,
    incompatible_abi = 2,
    internal = 3,
};

pub const PluginLane = enum(u32) {
    declarative = 0,
    native = 1,
};

pub const Capability = extern struct {
    slot: ?[*:0]const u8 = null,
    name: ?[*:0]const u8 = null,
};

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

pub const HostApi = extern struct {
    struct_size: u32,
    host_api_version: u32,
    log_message: ?*const fn (level: i32, message: ?[*:0]const u8, user_data: ?*anyopaque) callconv(.c) void = null,
    user_data: ?*anyopaque = null,
};

pub const PluginVTable = extern struct {
    struct_size: u32,
    prepare: ?*const fn (plan_context: ?*const anyopaque, plugin_state: ?*anyopaque) callconv(.c) i32 = null,
    execute: ?*const fn (request_view: ?*const anyopaque, plugin_state: ?*anyopaque) callconv(.c) i32 = null,
    destroy: ?*const fn (plugin_state: ?*anyopaque) callconv(.c) void = null,
};

pub const PluginEntryFn = *const fn (
    expected_plugin_abi_version: u32,
    host_api: *const HostApi,
    out_info: *?*const PluginInfo,
    out_vtable: *?*const PluginVTable,
) callconv(.c) i32;

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

pub fn decodeStatus(raw: i32) PluginStatus {
    return std.meta.intToEnum(PluginStatus, raw) catch .internal;
}

pub fn validateHostApi(host_api: *const HostApi) ValidationError!void {
    if (host_api.struct_size != @sizeOf(HostApi)) {
        return error.InvalidHostApiStructSize;
    }
    if (host_api.host_api_version != host_api_version) {
        return error.UnsupportedHostApiVersion;
    }
}

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
