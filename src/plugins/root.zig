pub const slots = @import("slots.zig");
pub const selection = @import("selection.zig");
pub const providers = @import("providers/root.zig");
pub const builtin = struct {
    pub const manifests = @import("builtin/root.zig").manifests;
};
pub const internal = struct {
    pub const abi_types = @import("abi/abi_types.zig");
    pub const host_api = @import("abi/host_api.zig");
    pub const manifest = @import("loader/manifest.zig");
    pub const dynlib = @import("loader/dynlib.zig");
    pub const resolver = @import("loader/resolver.zig");
    pub const runtime = @import("loader/runtime.zig");
    pub const registry = @import("registry/CapabilityRegistry.zig");
    pub const builtin_runtime_support = @import("builtin/root.zig").runtime_support;
};

test {
    _ = @import("slots.zig");
    _ = @import("selection.zig");
    _ = @import("providers/root.zig");
    _ = @import("builtin/root.zig");
    _ = @import("loader/manifest.zig");
    _ = @import("loader/runtime.zig");
}

test "plugin root favors typed providers and keeps runtime internals nested" {
    try std.testing.expect(builtin.manifests.declarative.len > 0);
    try std.testing.expect(internal.builtin_runtime_support.staticSymbolsFor("builtin.transport_dispatcher") != null);
}

const std = @import("std");
