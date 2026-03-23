//! Purpose:
//!   Parse and validate declarative plugin manifests before they enter the
//!   capability registry.
//!
//! Physics:
//!   No physics is introduced here; this is policy and metadata validation for
//!   plugin discovery.
//!
//! Vendor:
//!   `manifest`
//!
//! Design:
//!   Keep native and declarative plugin policy explicit at the manifest layer
//!   so later resolution code can compare resolved metadata without guessing.
//!
//! Invariants:
//!   Declarative manifests must not carry native contracts, and native
//!   manifests must supply the ABI version, entry symbol, and capability list.
//!
//! Validation:
//!   Exercised by the manifest validation unit tests in this file.
const std = @import("std");
const Slots = @import("../slots.zig");

/// Execution lane declared by a manifest.
pub const ExecutionLane = enum {
    declarative,
    native,
};

/// Provenance metadata carried by a manifest.
pub const ProvenanceMetadata = struct {
    description: []const u8 = "",
    dataset_hashes: []const []const u8 = &[_][]const u8{},
};

/// Native plugin contract data stored in a manifest.
pub const NativeContract = struct {
    abi_version: u32 = 1,
    entry_symbol: []const u8 = "zdisamar_plugin_entry_v1",
    library_path: ?[]const u8 = null,
};

/// Static capability declaration found in a manifest.
pub const CapabilityDecl = struct {
    slot: []const u8,
    name: []const u8,
};

/// Plugin manifest accepted by the registry.
pub const PluginManifest = struct {
    schema_version: u32 = 1,
    id: []const u8,
    package: ?[]const u8 = null,
    version: []const u8,
    lane: ExecutionLane = .declarative,
    capabilities: []const CapabilityDecl = &[_]CapabilityDecl{},
    native: ?NativeContract = null,
    provenance: ProvenanceMetadata = .{},

    /// Purpose:
    ///   Check whether the manifest schema matches the expected ABI version.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `manifest::isCompatible`
    ///
    /// Inputs:
    ///   `abi_version` is the loader's expected schema revision.
    ///
    /// Outputs:
    ///   Returns true when the manifest schema matches `abi_version`.
    ///
    /// Units:
    ///   Version number only.
    ///
    /// Assumptions:
    ///   Schema versioning is integer-based.
    ///
    /// Decisions:
    ///   Keep the check simple so manifest compatibility is easy to audit.
    ///
    /// Validation:
    ///   Covered indirectly by manifest validation tests.
    pub fn isCompatible(self: PluginManifest, abi_version: u32) bool {
        return self.schema_version == abi_version;
    }

    /// Purpose:
    ///   Validate manifest policy before registration or resolution.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `manifest::validate`
    ///
    /// Inputs:
    ///   `allow_native_plugins` controls whether native contracts may be used.
    ///
    /// Outputs:
    ///   Returns success when the manifest is internally consistent.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   Capability slots are known to the registry slots table.
    ///
    /// Decisions:
    ///   Reject missing or empty metadata eagerly so later code can assume the
    ///   manifest is fully formed.
    ///
    /// Validation:
    ///   Covered by the manifest unit tests in this file.
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
                // INVARIANT:
                //   Declarative manifests must not carry a native contract.
                if (self.native != null) {
                    return Error.InvalidManifest;
                }
            },
            .native => {
                // DECISION:
                //   Native plugins remain opt-in so the runtime can keep a
                //   declarative-only default policy.
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
