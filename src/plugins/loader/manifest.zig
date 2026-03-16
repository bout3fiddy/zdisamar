const std = @import("std");
const Slots = @import("../slots.zig");

pub const ExecutionLane = enum {
    declarative,
    native,
};

pub const ProvenanceMetadata = struct {
    description: []const u8 = "",
    dataset_hashes: []const []const u8 = &[_][]const u8{},
};

pub const NativeContract = struct {
    abi_version: u32 = 1,
    entry_symbol: []const u8 = "zdisamar_plugin_entry_v1",
    library_path: ?[]const u8 = null,
};

pub const CapabilityDecl = struct {
    slot: []const u8,
    name: []const u8,
};

pub const PluginManifest = struct {
    schema_version: u32 = 1,
    id: []const u8,
    package: ?[]const u8 = null,
    version: []const u8,
    lane: ExecutionLane = .declarative,
    capabilities: []const CapabilityDecl = &[_]CapabilityDecl{},
    native: ?NativeContract = null,
    provenance: ProvenanceMetadata = .{},

    pub fn isCompatible(self: PluginManifest, abi_version: u32) bool {
        return self.schema_version == abi_version;
    }

    pub fn validate(self: PluginManifest, allow_native_plugins: bool) Error!void {
        if (self.id.len == 0 or self.version.len == 0) {
            return Error.InvalidManifest;
        }
        if (self.capabilities.len == 0) {
            return Error.MissingCapabilities;
        }
        for (self.capabilities) |capability| {
            if (capability.slot.len == 0 or capability.name.len == 0) {
                return Error.InvalidManifest;
            }
            if (!Slots.isKnown(capability.slot)) {
                return Error.UnknownCapabilitySlot;
            }
        }

        switch (self.lane) {
            .declarative => {
                if (self.native != null) {
                    return Error.InvalidManifest;
                }
            },
            .native => {
                if (!allow_native_plugins) return Error.NativePluginsDisabled;
                const native = self.native orelse return Error.MissingNativeContract;
                if (native.abi_version != 1) return Error.UnsupportedNativeAbiVersion;
                if (native.entry_symbol.len == 0) return Error.MissingEntrySymbol;
            },
        }
    }
};

pub const Error = error{
    InvalidManifest,
    MissingCapabilities,
    MissingNativeContract,
    MissingEntrySymbol,
    NativePluginsDisabled,
    UnsupportedNativeAbiVersion,
    UnknownCapabilitySlot,
};

test "declarative plugin validates without native contract" {
    const manifest: PluginManifest = .{
        .id = "example.cross_sections",
        .package = "disamar_standard",
        .version = "0.1.0",
        .lane = .declarative,
        .capabilities = &[_]CapabilityDecl{
            .{ .slot = "absorber.provider", .name = "example.cross_sections" },
        },
    };

    try manifest.validate(false);
}

test "native plugin requires explicit opt-in and contract" {
    const manifest: PluginManifest = .{
        .id = "example.native_surface",
        .package = "mission_s5p",
        .version = "0.1.0",
        .lane = .native,
        .capabilities = &[_]CapabilityDecl{
            .{ .slot = "surface.model", .name = "example.native_surface" },
        },
        .native = .{},
    };

    try std.testing.expectError(Error.NativePluginsDisabled, manifest.validate(false));
    try manifest.validate(true);
}

test "manifest validation rejects unknown capability slots" {
    const manifest: PluginManifest = .{
        .id = "example.invalid_slot",
        .version = "0.1.0",
        .lane = .declarative,
        .capabilities = &[_]CapabilityDecl{
            .{ .slot = "surface.typo", .name = "example.invalid_slot" },
        },
    };

    try std.testing.expectError(Error.UnknownCapabilitySlot, manifest.validate(false));
}
