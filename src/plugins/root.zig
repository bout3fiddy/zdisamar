pub const abi_types = @import("abi/abi_types.zig");
pub const host_api = @import("abi/host_api.zig");
pub const slots = @import("slots.zig");
pub const selection = @import("selection.zig");
pub const manifest = @import("loader/manifest.zig");
pub const dynlib = @import("loader/dynlib.zig");
pub const resolver = @import("loader/resolver.zig");
pub const runtime = @import("loader/runtime.zig");
pub const registry = @import("registry/CapabilityRegistry.zig");
pub const providers = @import("providers/root.zig");
pub const builtin = @import("builtin/root.zig");

test {
    _ = @import("abi/abi_types.zig");
    _ = @import("abi/host_api.zig");
    _ = @import("slots.zig");
    _ = @import("selection.zig");
    _ = @import("loader/manifest.zig");
    _ = @import("loader/dynlib.zig");
    _ = @import("loader/resolver.zig");
    _ = @import("loader/runtime.zig");
    _ = @import("registry/CapabilityRegistry.zig");
    _ = @import("providers/root.zig");
    _ = @import("builtin/root.zig");
}
