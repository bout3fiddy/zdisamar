const std = @import("std");
const Allocator = std.mem.Allocator;
const Manifest = @import("../loader/manifest.zig");
const BuiltinPlugins = @import("../builtin/root.zig");

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
    native_entry_symbol: ?[]const u8 = null,
    native_library_path: ?[]const u8 = null,

    pub fn clone(self: Capability, allocator: Allocator) !Capability {
        const slot = try allocator.dupe(u8, self.slot);
        errdefer allocator.free(slot);

        const provider = try allocator.dupe(u8, self.provider);
        errdefer allocator.free(provider);

        const manifest_id = try allocator.dupe(u8, self.manifest_id);
        errdefer allocator.free(manifest_id);

        const package = if (self.package) |value|
            try allocator.dupe(u8, value)
        else
            null;
        errdefer if (package) |value| allocator.free(value);

        const version = try allocator.dupe(u8, self.version);
        errdefer allocator.free(version);

        const dataset_hashes = try dupeStringSlice(allocator, self.dataset_hashes);
        errdefer freeStringSlice(allocator, dataset_hashes);

        const native_entry_symbol = if (self.native_entry_symbol) |value|
            try allocator.dupe(u8, value)
        else
            null;
        errdefer if (native_entry_symbol) |value| allocator.free(value);

        const native_library_path = if (self.native_library_path) |value|
            try allocator.dupe(u8, value)
        else
            null;
        errdefer if (native_library_path) |value| allocator.free(value);

        return .{
            .slot = slot,
            .provider = provider,
            .manifest_id = manifest_id,
            .package = package,
            .version = version,
            .lane = self.lane,
            .dataset_hashes = dataset_hashes,
            .native_entry_symbol = native_entry_symbol,
            .native_library_path = native_library_path,
        };
    }

    pub fn deinit(self: *Capability, allocator: Allocator) void {
        allocator.free(self.slot);
        allocator.free(self.provider);
        allocator.free(self.manifest_id);
        if (self.package) |value| allocator.free(value);
        allocator.free(self.version);
        freeStringSlice(allocator, self.dataset_hashes);
        if (self.native_entry_symbol) |value| allocator.free(value);
        if (self.native_library_path) |value| allocator.free(value);
        self.* = undefined;
    }
};

pub const ResolvedCapability = struct {
    slot: []const u8,
    provider: []const u8,
    manifest_id: []const u8,
    package: ?[]const u8,
    version: []const u8,
    lane: Lane,
    native_entry_symbol: ?[]const u8 = null,
    native_library_path: ?[]const u8 = null,
    version_label_storage: [96]u8 = [_]u8{0} ** 96,
    version_label_len: usize = 0,

    pub fn versionLabel(self: *const ResolvedCapability) []const u8 {
        return self.version_label_storage[0..self.version_label_len];
    }
};

pub const PluginSnapshot = struct {
    generation: u64 = 0,
    capability_count: usize = 0,
    capabilities: [max_snapshot_capabilities]ResolvedCapability = undefined,
    dataset_hash_count: usize = 0,
    dataset_hash_entries: [max_snapshot_dataset_hashes][]const u8 = undefined,
    native_capability_count: usize = 0,
    native_slot_entries: [max_snapshot_capabilities][]const u8 = undefined,
    native_entry_symbol_entries: [max_snapshot_capabilities][]const u8 = undefined,
    native_library_path_entries: [max_snapshot_capabilities][]const u8 = undefined,

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
            .native_entry_symbol = capability.native_entry_symbol,
            .native_library_path = capability.native_library_path,
        };
        try fillVersionLabel(&resolved);

        self.capabilities[self.capability_count] = resolved;
        self.capability_count += 1;

        for (capability.dataset_hashes) |dataset_hash| {
            if (self.dataset_hash_count >= max_snapshot_dataset_hashes) {
                return error.PluginSnapshotOverflow;
            }
            self.dataset_hash_entries[self.dataset_hash_count] = dataset_hash;
            self.dataset_hash_count += 1;
        }

        if (capability.lane == .native) {
            if (self.native_capability_count >= max_snapshot_capabilities) {
                return error.PluginSnapshotOverflow;
            }
            self.native_slot_entries[self.native_capability_count] = capability.slot;
            self.native_entry_symbol_entries[self.native_capability_count] =
                capability.native_entry_symbol orelse "";
            self.native_library_path_entries[self.native_capability_count] =
                capability.native_library_path orelse "";
            self.native_capability_count += 1;
        }
    }

    pub fn pluginVersionCount(self: *const PluginSnapshot) usize {
        return self.capability_count;
    }

    pub fn pluginVersionAt(self: *const PluginSnapshot, index: usize) []const u8 {
        std.debug.assert(index < self.capability_count);
        return self.capabilities[index].versionLabel();
    }

    pub fn datasetHashes(self: *const PluginSnapshot) []const []const u8 {
        return self.dataset_hash_entries[0..self.dataset_hash_count];
    }

    pub fn nativeCapabilitySlots(self: *const PluginSnapshot) []const []const u8 {
        return self.native_slot_entries[0..self.native_capability_count];
    }

    pub fn nativeEntrySymbols(self: *const PluginSnapshot) []const []const u8 {
        return self.native_entry_symbol_entries[0..self.native_capability_count];
    }

    pub fn nativeLibraryPaths(self: *const PluginSnapshot) []const []const u8 {
        return self.native_library_path_entries[0..self.native_capability_count];
    }
};

pub const CapabilityRegistry = struct {
    capabilities: std.ArrayListUnmanaged(Capability) = .{},
    generation: u64 = 0,
    bootstrapped: bool = false,

    pub fn register(self: *CapabilityRegistry, allocator: Allocator, capability: Capability) !void {
        var owned = try capability.clone(allocator);
        errdefer owned.deinit(allocator);

        try self.capabilities.append(allocator, owned);
        self.generation += 1;
    }

    pub fn registerManifest(
        self: *CapabilityRegistry,
        allocator: Allocator,
        manifest: Manifest.PluginManifest,
        allow_native_plugins: bool,
    ) !void {
        try manifest.validate(allow_native_plugins);

        const start_len = self.capabilities.items.len;
        const start_generation = self.generation;
        const start_bootstrapped = self.bootstrapped;
        errdefer self.rollback(allocator, start_len, start_generation, start_bootstrapped);

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
                .native_entry_symbol = if (manifest.native) |native| native.entry_symbol else null,
                .native_library_path = if (manifest.native) |native| native.library_path else null,
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

    pub fn bootstrapBuiltin(self: *CapabilityRegistry, allocator: Allocator) !void {
        if (self.bootstrapped) return;

        const start_len = self.capabilities.items.len;
        const start_generation = self.generation;
        const start_bootstrapped = self.bootstrapped;
        errdefer self.rollback(allocator, start_len, start_generation, start_bootstrapped);

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
        try self.registerManifest(allocator, BuiltinPlugins.builtin_manifests[1], true);
        try self.registerManifest(allocator, BuiltinPlugins.builtin_manifests[2], true);
        try self.registerManifest(allocator, BuiltinPlugins.builtin_manifests[3], true);
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

        self.bootstrapped = true;
    }

    pub fn deinit(self: *CapabilityRegistry, allocator: Allocator) void {
        for (self.capabilities.items) |*capability| {
            capability.deinit(allocator);
        }
        self.capabilities.deinit(allocator);
        self.* = .{};
    }

    fn rollback(
        self: *CapabilityRegistry,
        allocator: Allocator,
        start_len: usize,
        start_generation: u64,
        start_bootstrapped: bool,
    ) void {
        while (self.capabilities.items.len > start_len) {
            const last_index = self.capabilities.items.len - 1;
            self.capabilities.items[last_index].deinit(allocator);
            self.capabilities.items.len = last_index;
        }
        self.generation = start_generation;
        self.bootstrapped = start_bootstrapped;
    }
};

fn fillVersionLabel(resolved: *ResolvedCapability) !void {
    const label = std.fmt.bufPrint(
        &resolved.version_label_storage,
        "{s}@{s}",
        .{ resolved.provider, resolved.version },
    ) catch return error.PluginVersionLabelTooLong;
    resolved.version_label_len = label.len;
}

fn dupeStringSlice(allocator: Allocator, values: []const []const u8) ![]const []const u8 {
    var owned = try allocator.alloc([]const u8, values.len);
    errdefer allocator.free(owned);

    var copied: usize = 0;
    errdefer {
        for (owned[0..copied]) |value| allocator.free(value);
    }

    for (values, 0..) |value, index| {
        owned[index] = try allocator.dupe(u8, value);
        copied = index + 1;
    }

    return owned;
}

fn freeStringSlice(allocator: Allocator, values: []const []const u8) void {
    for (values) |value| allocator.free(value);
    allocator.free(values);
}

fn bootstrapBuiltinWithAllocator(allocator: Allocator) !void {
    var registry: CapabilityRegistry = .{};
    defer registry.deinit(allocator);

    try registry.bootstrapBuiltin(allocator);
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
    try std.testing.expect(after.pluginVersionCount() > before.pluginVersionCount());
    try std.testing.expect(after.datasetHashes().len > before.datasetHashes().len);
    try std.testing.expectEqualStrings(
        "builtin.cross_sections@0.1.0",
        before.pluginVersionAt(0),
    );
}

test "register manifest clones caller-owned storage" {
    var registry: CapabilityRegistry = .{};
    defer registry.deinit(std.testing.allocator);

    const id = try std.testing.allocator.dupe(u8, "example.mutable_manifest");
    defer std.testing.allocator.free(id);
    const package = try std.testing.allocator.dupe(u8, "mutable_package");
    defer std.testing.allocator.free(package);
    const version = try std.testing.allocator.dupe(u8, "1.2.3");
    defer std.testing.allocator.free(version);
    const slot = try std.testing.allocator.dupe(u8, "data.pack");
    defer std.testing.allocator.free(slot);
    const provider = try std.testing.allocator.dupe(u8, "example.mutable_provider");
    defer std.testing.allocator.free(provider);
    const dataset_hash = try std.testing.allocator.dupe(u8, "sha256:mutable-dataset");
    defer std.testing.allocator.free(dataset_hash);

    try registry.registerManifest(std.testing.allocator, .{
        .id = id,
        .package = package,
        .version = version,
        .lane = .declarative,
        .capabilities = &[_]Manifest.CapabilityDecl{
            .{ .slot = slot, .name = provider },
        },
        .provenance = .{
            .dataset_hashes = &[_][]const u8{
                dataset_hash,
            },
        },
    }, false);

    id[0] = 'X';
    package[0] = 'X';
    version[0] = '9';
    slot[0] = 'X';
    provider[0] = 'X';
    dataset_hash[0] = 'X';

    const snapshot = try registry.snapshot();
    try std.testing.expectEqualStrings("example.mutable_manifest", registry.capabilities.items[0].manifest_id);
    try std.testing.expectEqualStrings("mutable_package", registry.capabilities.items[0].package.?);
    try std.testing.expectEqualStrings("1.2.3", registry.capabilities.items[0].version);
    try std.testing.expectEqualStrings("data.pack", registry.capabilities.items[0].slot);
    try std.testing.expectEqualStrings("example.mutable_provider", registry.capabilities.items[0].provider);
    try std.testing.expectEqualStrings("sha256:mutable-dataset", registry.capabilities.items[0].dataset_hashes[0]);
    try std.testing.expectEqualStrings("example.mutable_provider@1.2.3", snapshot.pluginVersionAt(0));
}

test "bootstrap rolls back after allocation failure and can retry" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, bootstrapBuiltinWithAllocator, .{});

    var registry: CapabilityRegistry = .{};
    defer registry.deinit(std.testing.allocator);

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 3,
    });
    const allocator = failing.allocator();

    try std.testing.expectError(error.OutOfMemory, registry.bootstrapBuiltin(allocator));
    try std.testing.expectEqual(@as(usize, 0), registry.capabilities.items.len);
    try std.testing.expectEqual(@as(u64, 0), registry.generation);
    try std.testing.expect(!registry.bootstrapped);
    try std.testing.expect(failing.allocations > 0);
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);

    try registry.bootstrapBuiltin(std.testing.allocator);
    try std.testing.expect(registry.bootstrapped);
    try std.testing.expect(registry.capabilities.items.len > 0);
}

test "snapshot rejects provider labels that do not fit fixed provenance storage" {
    var snapshot = PluginSnapshot.init(1);
    const long_provider = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnop";

    try std.testing.expectError(error.PluginVersionLabelTooLong, snapshot.appendCapability(.{
        .slot = "data.pack",
        .provider = long_provider,
        .manifest_id = "example.long_provider",
        .package = "disamar_standard",
        .version = "2026.03.14",
        .lane = .declarative,
    }));
}
