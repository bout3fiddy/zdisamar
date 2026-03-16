const std = @import("std");
const Allocator = std.mem.Allocator;
const BuiltinPlugins = @import("../builtin/root.zig");
const Manifest = @import("../loader/manifest.zig");
const Selection = @import("../selection.zig");
const Slots = @import("../slots.zig");

pub const Lane = enum {
    declarative,
    native,
};

pub const Capability = struct {
    manifest_index: usize,
    capability_index: usize,
    slot: []const u8,
    provider: []const u8,
    manifest_id: []const u8,
    package: ?[]const u8,
    version: []const u8,
    lane: Lane,
};

pub const OwnedManifest = struct {
    manifest: Manifest.PluginManifest,

    pub fn clone(allocator: Allocator, manifest: Manifest.PluginManifest) !OwnedManifest {
        const id = try allocator.dupe(u8, manifest.id);
        errdefer allocator.free(id);

        const package = if (manifest.package) |value|
            try allocator.dupe(u8, value)
        else
            null;
        errdefer if (package) |value| allocator.free(value);

        const version = try allocator.dupe(u8, manifest.version);
        errdefer allocator.free(version);

        const capabilities = try allocator.alloc(Manifest.CapabilityDecl, manifest.capabilities.len);
        errdefer allocator.free(capabilities);
        var copied_capabilities: usize = 0;
        errdefer {
            for (capabilities[0..copied_capabilities]) |capability| {
                allocator.free(capability.slot);
                allocator.free(capability.name);
            }
        }
        for (manifest.capabilities, 0..) |capability, index| {
            const slot = try allocator.dupe(u8, capability.slot);
            errdefer allocator.free(slot);
            const name = try allocator.dupe(u8, capability.name);
            errdefer allocator.free(name);
            capabilities[index] = .{
                .slot = slot,
                .name = name,
            };
            copied_capabilities = index + 1;
        }

        const native = if (manifest.native) |value| blk: {
            const entry_symbol = try allocator.dupe(u8, value.entry_symbol);
            errdefer allocator.free(entry_symbol);
            const library_path = if (value.library_path) |path|
                try allocator.dupe(u8, path)
            else
                null;
            errdefer if (library_path) |path| allocator.free(path);
            break :blk Manifest.NativeContract{
                .abi_version = value.abi_version,
                .entry_symbol = entry_symbol,
                .library_path = library_path,
            };
        } else null;
        errdefer if (native) |value| {
            allocator.free(value.entry_symbol);
            if (value.library_path) |path| allocator.free(path);
        };

        const provenance_description = try allocator.dupe(u8, manifest.provenance.description);
        errdefer allocator.free(provenance_description);

        const dataset_hashes = try dupeStringSlice(allocator, manifest.provenance.dataset_hashes);
        errdefer freeStringSlice(allocator, dataset_hashes);

        return .{
            .manifest = .{
                .schema_version = manifest.schema_version,
                .id = id,
                .package = package,
                .version = version,
                .lane = manifest.lane,
                .capabilities = capabilities,
                .native = native,
                .provenance = .{
                    .description = provenance_description,
                    .dataset_hashes = dataset_hashes,
                },
            },
        };
    }

    pub fn deinit(self: *OwnedManifest, allocator: Allocator) void {
        allocator.free(self.manifest.id);
        if (self.manifest.package) |value| allocator.free(value);
        allocator.free(self.manifest.version);
        for (self.manifest.capabilities) |capability| {
            allocator.free(capability.slot);
            allocator.free(capability.name);
        }
        allocator.free(self.manifest.capabilities);
        if (self.manifest.native) |native| {
            allocator.free(native.entry_symbol);
            if (native.library_path) |value| allocator.free(value);
        }
        allocator.free(self.manifest.provenance.description);
        freeStringSlice(allocator, self.manifest.provenance.dataset_hashes);
        self.* = undefined;
    }
};

pub const SnapshotCapability = struct {
    slot: []const u8,
    provider: []const u8,
    manifest_id: []const u8,
    package: ?[]const u8,
    version: []const u8,
    lane: Lane,
    native_entry_symbol: ?[]const u8,
    native_library_path: ?[]const u8,
    version_label: []const u8,

    pub fn deinit(self: *SnapshotCapability, allocator: Allocator) void {
        allocator.free(self.version_label);
        self.* = undefined;
    }
};

pub const PluginSnapshot = struct {
    generation: u64 = 0,
    manifests: []OwnedManifest = &.{},
    capabilities: []SnapshotCapability = &.{},
    dataset_hash_entries: [][]const u8 = &.{},
    native_slot_entries: [][]const u8 = &.{},
    native_entry_symbol_entries: [][]const u8 = &.{},
    native_library_path_entries: [][]const u8 = &.{},

    pub fn deinit(self: *PluginSnapshot, allocator: Allocator) void {
        for (self.capabilities) |*capability| capability.deinit(allocator);
        if (self.capabilities.len != 0) allocator.free(self.capabilities);

        for (self.manifests) |*manifest| manifest.deinit(allocator);
        if (self.manifests.len != 0) allocator.free(self.manifests);

        if (self.dataset_hash_entries.len != 0) allocator.free(self.dataset_hash_entries);
        if (self.native_slot_entries.len != 0) allocator.free(self.native_slot_entries);
        if (self.native_entry_symbol_entries.len != 0) allocator.free(self.native_entry_symbol_entries);
        if (self.native_library_path_entries.len != 0) allocator.free(self.native_library_path_entries);
        self.* = .{};
    }

    pub fn pluginVersionCount(self: *const PluginSnapshot) usize {
        return self.capabilities.len;
    }

    pub fn pluginVersionAt(self: *const PluginSnapshot, index: usize) []const u8 {
        std.debug.assert(index < self.capabilities.len);
        return self.capabilities[index].version_label;
    }

    pub fn datasetHashes(self: *const PluginSnapshot) []const []const u8 {
        return self.dataset_hash_entries;
    }

    pub fn nativeCapabilitySlots(self: *const PluginSnapshot) []const []const u8 {
        return self.native_slot_entries;
    }

    pub fn nativeEntrySymbols(self: *const PluginSnapshot) []const []const u8 {
        return self.native_entry_symbol_entries;
    }

    pub fn nativeLibraryPaths(self: *const PluginSnapshot) []const []const u8 {
        return self.native_library_path_entries;
    }
};

pub const CapabilityRegistry = struct {
    manifests: std.ArrayListUnmanaged(OwnedManifest) = .{},
    capabilities: std.ArrayListUnmanaged(Capability) = .{},
    generation: u64 = 0,
    bootstrapped: bool = false,

    pub fn registerManifest(
        self: *CapabilityRegistry,
        allocator: Allocator,
        manifest: Manifest.PluginManifest,
        allow_native_plugins: bool,
    ) !void {
        try manifest.validate(allow_native_plugins);

        const start_manifest_len = self.manifests.items.len;
        const start_capability_len = self.capabilities.items.len;
        const start_generation = self.generation;
        const start_bootstrapped = self.bootstrapped;
        errdefer self.rollback(allocator, start_manifest_len, start_capability_len, start_generation, start_bootstrapped);

        const manifest_index = blk: {
            var owned_manifest = try OwnedManifest.clone(allocator, manifest);
            errdefer owned_manifest.deinit(allocator);

            try self.manifests.append(allocator, owned_manifest);
            break :blk self.manifests.items.len - 1;
        };
        const stored = self.manifests.items[manifest_index].manifest;

        for (stored.capabilities, 0..) |capability, capability_index| {
            try self.capabilities.append(allocator, .{
                .manifest_index = manifest_index,
                .capability_index = capability_index,
                .slot = capability.slot,
                .provider = capability.name,
                .manifest_id = stored.id,
                .package = stored.package,
                .version = stored.version,
                .lane = switch (stored.lane) {
                    .declarative => .declarative,
                    .native => .native,
                },
            });
        }

        self.generation += 1;
    }

    pub fn snapshotSelection(
        self: *const CapabilityRegistry,
        allocator: Allocator,
        provider_selection: Selection.ProviderSelection,
    ) !PluginSnapshot {
        var snapshot: PluginSnapshot = .{ .generation = self.generation };
        errdefer snapshot.deinit(allocator);

        var selected_manifest_indices = std.ArrayListUnmanaged(usize){};
        defer selected_manifest_indices.deinit(allocator);

        try appendSelection(self, allocator, &snapshot, &selected_manifest_indices, Slots.absorber_provider, provider_selection.absorber_provider);
        try appendSelection(self, allocator, &snapshot, &selected_manifest_indices, Slots.transport_solver, provider_selection.transport_solver);
        try appendSelection(self, allocator, &snapshot, &selected_manifest_indices, Slots.surface_model, provider_selection.surface_model);
        try appendSelection(self, allocator, &snapshot, &selected_manifest_indices, Slots.instrument_response, provider_selection.instrument_response);
        try appendSelection(self, allocator, &snapshot, &selected_manifest_indices, Slots.noise_model, provider_selection.noise_model);
        try appendSelection(self, allocator, &snapshot, &selected_manifest_indices, Slots.diagnostics_metric, provider_selection.diagnostics_metric);
        if (provider_selection.retrieval_algorithm) |provider_id| {
            try appendSelection(self, allocator, &snapshot, &selected_manifest_indices, Slots.retrieval_algorithm, provider_id);
        }
        try appendAllForSlot(self, allocator, &snapshot, &selected_manifest_indices, Slots.data_pack);

        try materializeSnapshotViews(allocator, &snapshot);
        return snapshot;
    }

    pub fn bootstrapBuiltin(
        self: *CapabilityRegistry,
        allocator: Allocator,
        allow_native_plugins: bool,
    ) !void {
        if (self.bootstrapped) return;

        const start_manifest_len = self.manifests.items.len;
        const start_capability_len = self.capabilities.items.len;
        const start_generation = self.generation;
        const start_bootstrapped = self.bootstrapped;
        errdefer self.rollback(allocator, start_manifest_len, start_capability_len, start_generation, start_bootstrapped);

        inline for (BuiltinPlugins.manifests.declarative) |manifest| {
            try self.registerManifest(allocator, manifest, false);
        }
        if (allow_native_plugins) {
            inline for (BuiltinPlugins.manifests.native_runtime) |manifest| {
                try self.registerManifest(allocator, manifest, true);
            }
        } else {
            inline for (BuiltinPlugins.manifests.native_runtime) |manifest| {
                try self.registerManifest(allocator, manifestWithoutNativeLane(manifest), false);
            }
        }

        self.bootstrapped = true;
    }

    pub fn snapshotInventory(self: *const CapabilityRegistry, allocator: Allocator) !PluginSnapshot {
        var snapshot: PluginSnapshot = .{ .generation = self.generation };
        errdefer snapshot.deinit(allocator);

        snapshot.manifests = try allocator.alloc(OwnedManifest, self.manifests.items.len);
        for (self.manifests.items, 0..) |manifest, index| {
            snapshot.manifests[index] = try OwnedManifest.clone(allocator, manifest.manifest);
        }

        snapshot.capabilities = try allocator.alloc(SnapshotCapability, self.capabilities.items.len);
        for (self.capabilities.items, 0..) |capability, index| {
            snapshot.capabilities[index] = try snapshotCapabilityFor(
                allocator,
                capability,
                &snapshot.manifests[capability.manifest_index].manifest,
            );
        }
        try materializeSnapshotViews(allocator, &snapshot);
        return snapshot;
    }

    pub fn deinit(self: *CapabilityRegistry, allocator: Allocator) void {
        for (self.manifests.items) |*manifest| manifest.deinit(allocator);
        self.manifests.deinit(allocator);
        self.capabilities.deinit(allocator);
        self.* = .{};
    }

    fn rollback(
        self: *CapabilityRegistry,
        allocator: Allocator,
        start_manifest_len: usize,
        start_capability_len: usize,
        start_generation: u64,
        start_bootstrapped: bool,
    ) void {
        while (self.manifests.items.len > start_manifest_len) {
            const last_index = self.manifests.items.len - 1;
            self.manifests.items[last_index].deinit(allocator);
            self.manifests.items.len = last_index;
        }
        self.capabilities.items.len = start_capability_len;
        self.generation = start_generation;
        self.bootstrapped = start_bootstrapped;
    }
};

fn appendSelection(
    registry: *const CapabilityRegistry,
    allocator: Allocator,
    snapshot: *PluginSnapshot,
    selected_manifest_indices: *std.ArrayListUnmanaged(usize),
    slot: []const u8,
    provider: []const u8,
) !void {
    const capability = findCapability(registry, slot, provider) orelse return error.MissingSelectedProvider;
    try appendCapability(registry, allocator, snapshot, selected_manifest_indices, capability.*);
}

fn manifestWithoutNativeLane(manifest: Manifest.PluginManifest) Manifest.PluginManifest {
    return .{
        .schema_version = manifest.schema_version,
        .id = manifest.id,
        .package = manifest.package,
        .version = manifest.version,
        .lane = .declarative,
        .capabilities = manifest.capabilities,
        .native = null,
        .provenance = manifest.provenance,
    };
}

fn appendAllForSlot(
    registry: *const CapabilityRegistry,
    allocator: Allocator,
    snapshot: *PluginSnapshot,
    selected_manifest_indices: *std.ArrayListUnmanaged(usize),
    slot: []const u8,
) !void {
    for (registry.capabilities.items) |capability| {
        if (!std.mem.eql(u8, capability.slot, slot)) continue;
        try appendCapability(registry, allocator, snapshot, selected_manifest_indices, capability);
    }
}

fn appendCapability(
    registry: *const CapabilityRegistry,
    allocator: Allocator,
    snapshot: *PluginSnapshot,
    selected_manifest_indices: *std.ArrayListUnmanaged(usize),
    capability: Capability,
) !void {
    const manifest = &registry.manifests.items[capability.manifest_index].manifest;

    var snapshot_manifest_index: ?usize = null;
    for (selected_manifest_indices.items, 0..) |existing_manifest_index, index| {
        if (existing_manifest_index == capability.manifest_index) {
            snapshot_manifest_index = index;
            break;
        }
    }

    if (snapshot_manifest_index == null) {
        try selected_manifest_indices.append(allocator, capability.manifest_index);
        {
            var cloned = try OwnedManifest.clone(allocator, manifest.*);
            errdefer cloned.deinit(allocator);

            snapshot.manifests = try allocator.realloc(snapshot.manifests, snapshot.manifests.len + 1);
            snapshot.manifests[snapshot.manifests.len - 1] = cloned;
        }
        snapshot_manifest_index = snapshot.manifests.len - 1;
    }

    {
        var snapshot_capability = try snapshotCapabilityFor(
            allocator,
            capability,
            &snapshot.manifests[snapshot_manifest_index.?].manifest,
        );
        errdefer snapshot_capability.deinit(allocator);

        snapshot.capabilities = try allocator.realloc(snapshot.capabilities, snapshot.capabilities.len + 1);
        snapshot.capabilities[snapshot.capabilities.len - 1] = snapshot_capability;
    }
}

fn snapshotCapabilityFor(
    allocator: Allocator,
    capability: Capability,
    manifest: *const Manifest.PluginManifest,
) !SnapshotCapability {
    const stored_capability = manifest.capabilities[capability.capability_index];
    return .{
        .slot = stored_capability.slot,
        .provider = stored_capability.name,
        .manifest_id = manifest.id,
        .package = manifest.package,
        .version = manifest.version,
        .lane = switch (manifest.lane) {
            .declarative => .declarative,
            .native => .native,
        },
        .native_entry_symbol = if (manifest.native) |native| native.entry_symbol else null,
        .native_library_path = if (manifest.native) |native| native.library_path else null,
        .version_label = try std.fmt.allocPrint(allocator, "{s}@{s}", .{ stored_capability.name, manifest.version }),
    };
}

fn findCapability(registry: *const CapabilityRegistry, slot: []const u8, provider: []const u8) ?*const Capability {
    for (registry.capabilities.items) |*capability| {
        if (!std.mem.eql(u8, capability.slot, slot)) continue;
        if (std.mem.eql(u8, capability.provider, provider)) return capability;
    }
    return null;
}

fn materializeSnapshotViews(allocator: Allocator, snapshot: *PluginSnapshot) !void {
    var dataset_hash_count: usize = 0;
    for (snapshot.manifests) |manifest| {
        dataset_hash_count += manifest.manifest.provenance.dataset_hashes.len;
    }
    snapshot.dataset_hash_entries = try allocator.alloc([]const u8, dataset_hash_count);
    var dataset_hash_index: usize = 0;
    for (snapshot.manifests) |manifest| {
        for (manifest.manifest.provenance.dataset_hashes) |dataset_hash| {
            snapshot.dataset_hash_entries[dataset_hash_index] = dataset_hash;
            dataset_hash_index += 1;
        }
    }

    var native_count: usize = 0;
    for (snapshot.capabilities) |capability| {
        if (capability.lane == .native) native_count += 1;
    }
    snapshot.native_slot_entries = try allocator.alloc([]const u8, native_count);
    snapshot.native_entry_symbol_entries = try allocator.alloc([]const u8, native_count);
    snapshot.native_library_path_entries = try allocator.alloc([]const u8, native_count);
    var native_index: usize = 0;
    for (snapshot.capabilities) |capability| {
        if (capability.lane != .native) continue;
        snapshot.native_slot_entries[native_index] = capability.slot;
        snapshot.native_entry_symbol_entries[native_index] = capability.native_entry_symbol orelse "";
        snapshot.native_library_path_entries[native_index] = capability.native_library_path orelse "";
        native_index += 1;
    }
}

fn dupeStringSlice(allocator: Allocator, values: []const []const u8) ![]const []const u8 {
    const owned = try allocator.alloc([]const u8, values.len);
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
    if (values.len == 0) return;
    for (values) |value| allocator.free(value);
    allocator.free(values);
}

fn bootstrapBuiltinWithAllocator(allocator: Allocator) !void {
    var registry: CapabilityRegistry = .{};
    defer registry.deinit(allocator);

    try registry.bootstrapBuiltin(allocator, true);
}

test "register manifest enforces native lane opt-in" {
    var registry: CapabilityRegistry = .{};
    defer registry.deinit(std.testing.allocator);

    const native_manifest: Manifest.PluginManifest = .{
        .id = "example.native_surface",
        .version = "0.1.0",
        .lane = .native,
        .capabilities = &[_]Manifest.CapabilityDecl{
            .{ .slot = Slots.surface_model, .name = "example.native_surface" },
        },
        .native = .{},
    };

    try std.testing.expectError(
        Manifest.Error.NativePluginsDisabled,
        registry.registerManifest(std.testing.allocator, native_manifest, false),
    );
}

test "bootstrap registers declarative and native lanes when policy allows them" {
    var registry: CapabilityRegistry = .{};
    defer registry.deinit(std.testing.allocator);

    try registry.bootstrapBuiltin(std.testing.allocator, true);

    var saw_declarative = false;
    var saw_native = false;
    for (registry.capabilities.items) |capability| {
        if (capability.lane == .declarative) saw_declarative = true;
        if (capability.lane == .native) saw_native = true;
    }

    try std.testing.expect(saw_declarative);
    try std.testing.expect(saw_native);
}

test "bootstrap omits native runtime manifests when policy disallows them" {
    var registry: CapabilityRegistry = .{};
    defer registry.deinit(std.testing.allocator);

    try registry.bootstrapBuiltin(std.testing.allocator, false);

    for (registry.capabilities.items) |capability| {
        try std.testing.expectEqual(Lane.declarative, capability.lane);
    }
    try std.testing.expect(findCapability(&registry, Slots.transport_solver, "builtin.dispatcher") != null);
    try std.testing.expect(findCapability(&registry, Slots.surface_model, "builtin.lambertian_surface") != null);
    try std.testing.expect(findCapability(&registry, Slots.retrieval_algorithm, "builtin.oe_solver") != null);
}

test "selection snapshot freezes only the providers used by the plan" {
    var registry: CapabilityRegistry = .{};
    defer registry.deinit(std.testing.allocator);

    try registry.bootstrapBuiltin(std.testing.allocator, true);
    var before = try registry.snapshotSelection(std.testing.allocator, .{});
    defer before.deinit(std.testing.allocator);

    try registry.registerManifest(std.testing.allocator, .{
        .id = "example.extra_dataset",
        .package = "disamar_standard",
        .version = "0.2.0",
        .lane = .declarative,
        .capabilities = &[_]Manifest.CapabilityDecl{
            .{ .slot = Slots.exporter, .name = "example.extra_dataset" },
        },
        .provenance = .{
            .dataset_hashes = &[_][]const u8{
                "sha256:example-extra-dataset",
            },
        },
    }, false);

    var after = try registry.snapshotSelection(std.testing.allocator, .{});
    defer after.deinit(std.testing.allocator);

    try std.testing.expectEqual(before.generation + 1, after.generation);
    try std.testing.expectEqual(before.pluginVersionCount(), after.pluginVersionCount());
    try std.testing.expectEqual(before.datasetHashes().len, after.datasetHashes().len);
    try std.testing.expectEqualStrings("builtin.cross_sections@0.1.0", before.pluginVersionAt(0));
}

test "snapshot selection owns manifest data independently from the registry" {
    var registry: CapabilityRegistry = .{};
    defer registry.deinit(std.testing.allocator);

    try registry.bootstrapBuiltin(std.testing.allocator, true);
    try registry.registerManifest(std.testing.allocator, .{
        .id = "example.mutable_manifest",
        .package = "mutable_package",
        .version = "1.2.3",
        .lane = .declarative,
        .capabilities = &[_]Manifest.CapabilityDecl{
            .{ .slot = Slots.absorber_provider, .name = "example.mutable_provider" },
        },
        .provenance = .{
            .dataset_hashes = &[_][]const u8{
                "sha256:mutable-dataset",
            },
        },
    }, false);

    var snapshot = try registry.snapshotSelection(std.testing.allocator, .{
        .absorber_provider = "example.mutable_provider",
        .transport_solver = "builtin.dispatcher",
        .surface_model = "builtin.lambertian_surface",
        .instrument_response = "builtin.generic_response",
        .noise_model = "builtin.scene_noise",
        .diagnostics_metric = "builtin.default_diagnostics",
    });
    defer snapshot.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("example.mutable_provider@1.2.3", snapshot.pluginVersionAt(0));
    try std.testing.expectEqualStrings("sha256:mutable-dataset", snapshot.datasetHashes()[0]);
}

test "bootstrap rolls back after allocation failure and can retry" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, bootstrapBuiltinWithAllocator, .{});

    var registry: CapabilityRegistry = .{};
    defer registry.deinit(std.testing.allocator);

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 3,
    });
    const allocator = failing.allocator();

    try std.testing.expectError(error.OutOfMemory, registry.bootstrapBuiltin(allocator, true));
    try std.testing.expectEqual(@as(usize, 0), registry.capabilities.items.len);
    try std.testing.expectEqual(@as(u64, 0), registry.generation);
    try std.testing.expect(!registry.bootstrapped);

    try registry.bootstrapBuiltin(std.testing.allocator, true);
    try std.testing.expect(registry.bootstrapped);
    try std.testing.expect(registry.capabilities.items.len > 0);
}
