const std = @import("std");
const Manifest = @import("../loader/manifest.zig");

pub const max_snapshot_capabilities: usize = 16;
pub const max_snapshot_dataset_hashes: usize = 16;

pub const Lane = enum {
    declarative,
    native,
};

pub const Capability = struct {
    slot: []const u8,
    provider: []const u8,
    manifest_id: []const u8,
    package: ?[]const u8,
    version: []const u8,
    lane: Lane,
    dataset_hashes: []const []const u8 = &[_][]const u8{},
};

pub const ResolvedCapability = struct {
    slot: []const u8,
    provider: []const u8,
    manifest_id: []const u8,
    package: ?[]const u8,
    version: []const u8,
    lane: Lane,
    version_label_storage: [96]u8 = [_]u8{0} ** 96,
    version_label_len: u8 = 0,

    pub fn versionLabel(self: *const ResolvedCapability) []const u8 {
        return self.version_label_storage[0..self.version_label_len];
    }
};

pub const PluginSnapshot = struct {
    generation: u64 = 0,
    capability_count: usize = 0,
    capabilities: [max_snapshot_capabilities]ResolvedCapability = undefined,
    plugin_version_entries: [max_snapshot_capabilities][]const u8 = undefined,
    dataset_hash_count: usize = 0,
    dataset_hash_entries: [max_snapshot_dataset_hashes][]const u8 = undefined,

    pub fn init(generation: u64) PluginSnapshot {
        return .{ .generation = generation };
    }

    pub fn appendCapability(self: *PluginSnapshot, capability: Capability) !void {
        if (self.capability_count >= max_snapshot_capabilities) {
            return error.PluginSnapshotOverflow;
        }

        var resolved: ResolvedCapability = .{
            .slot = capability.slot,
            .provider = capability.provider,
            .manifest_id = capability.manifest_id,
            .package = capability.package,
            .version = capability.version,
            .lane = capability.lane,
        };
        fillVersionLabel(&resolved);

        self.capabilities[self.capability_count] = resolved;
        self.plugin_version_entries[self.capability_count] =
            self.capabilities[self.capability_count].versionLabel();
        self.capability_count += 1;

        for (capability.dataset_hashes) |dataset_hash| {
            if (self.dataset_hash_count >= max_snapshot_dataset_hashes) {
                return error.PluginSnapshotOverflow;
            }
            self.dataset_hash_entries[self.dataset_hash_count] = dataset_hash;
            self.dataset_hash_count += 1;
        }
    }

    pub fn pluginVersions(self: *const PluginSnapshot) []const []const u8 {
        return self.plugin_version_entries[0..self.capability_count];
    }

    pub fn datasetHashes(self: *const PluginSnapshot) []const []const u8 {
        return self.dataset_hash_entries[0..self.dataset_hash_count];
    }
};

pub const CapabilityRegistry = struct {
    capabilities: std.ArrayListUnmanaged(Capability) = .{},
    generation: u64 = 0,

    pub fn register(self: *CapabilityRegistry, allocator: std.mem.Allocator, capability: Capability) !void {
        try self.capabilities.append(allocator, capability);
        self.generation += 1;
    }

    pub fn registerManifest(
        self: *CapabilityRegistry,
        allocator: std.mem.Allocator,
        manifest: Manifest.PluginManifest,
        allow_native_plugins: bool,
    ) !void {
        try manifest.validate(allow_native_plugins);

        for (manifest.capabilities) |capability| {
            try self.register(allocator, .{
                .slot = capability.slot,
                .provider = capability.name,
                .manifest_id = manifest.id,
                .package = manifest.package,
                .version = manifest.version,
                .lane = switch (manifest.lane) {
                    .declarative => .declarative,
                    .native => .native,
                },
                .dataset_hashes = manifest.provenance.dataset_hashes,
            });
        }
    }

    pub fn snapshot(self: *const CapabilityRegistry) !PluginSnapshot {
        var plugin_snapshot = PluginSnapshot.init(self.generation);
        for (self.capabilities.items) |capability| {
            try plugin_snapshot.appendCapability(capability);
        }
        return plugin_snapshot;
    }

    pub fn bootstrapBuiltin(self: *CapabilityRegistry, allocator: std.mem.Allocator) !void {
        if (self.capabilities.items.len != 0) return;

        try self.registerManifest(allocator, .{
            .id = "builtin.cross_sections",
            .package = "disamar_standard",
            .version = "0.1.0",
            .lane = .declarative,
            .capabilities = &[_]Manifest.CapabilityDecl{
                .{ .slot = "absorber.provider", .name = "builtin.cross_sections" },
            },
            .provenance = .{
                .description = "Built-in spectroscopy data pack",
                .dataset_hashes = &[_][]const u8{
                    "sha256:builtin-cross-sections-demo",
                },
            },
        }, false);
        try self.registerManifest(allocator, .{
            .id = "builtin.transport_dispatcher",
            .package = "disamar_standard",
            .version = "0.1.0",
            .lane = .native,
            .capabilities = &[_]Manifest.CapabilityDecl{
                .{ .slot = "transport.solver", .name = "builtin.dispatcher" },
            },
            .native = .{},
        }, true);
        try self.registerManifest(allocator, .{
            .id = "builtin.netcdf_cf_exporter",
            .package = "builtin_exporters",
            .version = "0.1.0",
            .lane = .native,
            .capabilities = &[_]Manifest.CapabilityDecl{
                .{ .slot = "exporter", .name = "builtin.netcdf_cf" },
            },
            .native = .{},
        }, true);
        try self.registerManifest(allocator, .{
            .id = "builtin.zarr_exporter",
            .package = "builtin_exporters",
            .version = "0.1.0",
            .lane = .native,
            .capabilities = &[_]Manifest.CapabilityDecl{
                .{ .slot = "exporter", .name = "builtin.zarr" },
            },
            .native = .{},
        }, true);
    }

    pub fn deinit(self: *CapabilityRegistry, allocator: std.mem.Allocator) void {
        self.capabilities.deinit(allocator);
        self.* = .{};
    }
};

fn fillVersionLabel(resolved: *ResolvedCapability) void {
    const label = std.fmt.bufPrint(
        &resolved.version_label_storage,
        "{s}@{s}",
        .{ resolved.provider, resolved.version },
    ) catch {
        const fallback_len = @min(resolved.provider.len, resolved.version_label_storage.len);
        @memcpy(
            resolved.version_label_storage[0..fallback_len],
            resolved.provider[0..fallback_len],
        );
        resolved.version_label_len = @intCast(fallback_len);
        return;
    };
    resolved.version_label_len = @intCast(label.len);
}

test "register manifest enforces native lane opt-in" {
    var registry: CapabilityRegistry = .{};
    defer registry.deinit(std.testing.allocator);

    const native_manifest: Manifest.PluginManifest = .{
        .id = "example.native_surface",
        .version = "0.1.0",
        .lane = .native,
        .capabilities = &[_]Manifest.CapabilityDecl{
            .{ .slot = "surface.model", .name = "example.native_surface" },
        },
        .native = .{},
    };

    try std.testing.expectError(
        Manifest.Error.NativePluginsDisabled,
        registry.registerManifest(std.testing.allocator, native_manifest, false),
    );
}

test "bootstrap registers declarative and native lanes" {
    var registry: CapabilityRegistry = .{};
    defer registry.deinit(std.testing.allocator);

    try registry.bootstrapBuiltin(std.testing.allocator);

    var saw_declarative = false;
    var saw_native = false;
    for (registry.capabilities.items) |capability| {
        if (capability.lane == .declarative) saw_declarative = true;
        if (capability.lane == .native) saw_native = true;
    }

    try std.testing.expect(saw_declarative);
    try std.testing.expect(saw_native);
}

test "snapshot freezes plugin provenance entries by generation" {
    var registry: CapabilityRegistry = .{};
    defer registry.deinit(std.testing.allocator);

    try registry.bootstrapBuiltin(std.testing.allocator);
    const before = try registry.snapshot();

    try registry.registerManifest(std.testing.allocator, .{
        .id = "example.extra_dataset",
        .package = "disamar_standard",
        .version = "0.2.0",
        .lane = .declarative,
        .capabilities = &[_]Manifest.CapabilityDecl{
            .{ .slot = "data.pack", .name = "example.extra_dataset" },
        },
        .provenance = .{
            .dataset_hashes = &[_][]const u8{
                "sha256:example-extra-dataset",
            },
        },
    }, false);

    const after = try registry.snapshot();

    try std.testing.expect(after.generation > before.generation);
    try std.testing.expect(after.pluginVersions().len > before.pluginVersions().len);
    try std.testing.expect(after.datasetHashes().len > before.datasetHashes().len);
    try std.testing.expectEqualStrings(
        "builtin.cross_sections@0.1.0",
        before.pluginVersions()[0],
    );
}
