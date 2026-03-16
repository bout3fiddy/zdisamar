const Abi = @import("../../abi/abi_types.zig");
const DynLib = @import("../../loader/dynlib.zig");
const Manifest = @import("../../loader/manifest.zig");
const Slots = @import("../../slots.zig");

pub const oe_solver_manifest: Manifest.PluginManifest = .{
    .id = "builtin.oe_solver",
    .package = "disamar_standard",
    .version = "0.1.0",
    .lane = .native,
    .capabilities = &[_]Manifest.CapabilityDecl{
        .{
            .slot = Slots.retrieval_algorithm,
            .name = "builtin.oe_solver",
        },
    },
    .native = .{},
};

pub const doas_solver_manifest: Manifest.PluginManifest = .{
    .id = "builtin.doas_solver",
    .package = "disamar_standard",
    .version = "0.1.0",
    .lane = .declarative,
    .capabilities = &[_]Manifest.CapabilityDecl{
        .{
            .slot = Slots.retrieval_algorithm,
            .name = "builtin.doas_solver",
        },
    },
};

pub const dismas_solver_manifest: Manifest.PluginManifest = .{
    .id = "builtin.dismas_solver",
    .package = "disamar_standard",
    .version = "0.1.0",
    .lane = .declarative,
    .capabilities = &[_]Manifest.CapabilityDecl{
        .{
            .slot = Slots.retrieval_algorithm,
            .name = "builtin.dismas_solver",
        },
    },
};

const capabilities = [_]Abi.Capability{
    .{
        .slot = Slots.retrieval_algorithm,
        .name = "builtin.oe_solver",
    },
};

const plugin_info: Abi.PluginInfo = .{
    .struct_size = @sizeOf(Abi.PluginInfo),
    .plugin_id = "builtin.oe_solver",
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

pub fn staticSymbols() []const DynLib.SymbolEntry {
    return &[_]DynLib.SymbolEntry{
        .{
            .name = Abi.plugin_entry_symbol,
            .address = @ptrCast(&entry),
        },
    };
}

fn prepare(_: ?*const anyopaque, _: ?*anyopaque) callconv(.c) i32 {
    return @intFromEnum(Abi.PluginStatus.ok);
}

fn execute(_: ?*const anyopaque, _: ?*anyopaque) callconv(.c) i32 {
    return @intFromEnum(Abi.PluginStatus.ok);
}

fn destroy(_: ?*anyopaque) callconv(.c) void {}

fn entry(
    expected_plugin_abi_version: u32,
    host_api: *const Abi.HostApi,
    out_info: *?*const Abi.PluginInfo,
    out_vtable: *?*const Abi.PluginVTable,
) callconv(.c) i32 {
    if (expected_plugin_abi_version != Abi.plugin_abi_version) {
        return @intFromEnum(Abi.PluginStatus.incompatible_abi);
    }

    if (host_api.log_message) |log_message| {
        log_message(1, "builtin OE retrieval ready", host_api.user_data);
    }

    out_info.* = &plugin_info;
    out_vtable.* = &plugin_vtable;
    return @intFromEnum(Abi.PluginStatus.ok);
}
