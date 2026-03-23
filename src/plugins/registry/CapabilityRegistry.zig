//! Purpose:
//!   Store plugin manifests, derive capability views, and materialize snapshot
//!   selections for the runtime.
//!
//! Physics:
//!   No physics is introduced here; this is registry and provenance plumbing
//!   for plugin selection.
//!
//! Vendor:
//!   `CapabilityRegistry`
//!
//! Design:
//!   Keep the registry immutable to callers once a snapshot is materialized.
//!   The registry owns cloned manifest data, and snapshot views are flattened
//!   for downstream runtime consumption.
//!
//! Invariants:
//!   Manifest ownership must be duplicated into the registry, snapshot views
//!   must be consistent with the selected capabilities, and native manifests
//!   may only appear when policy allows them.
//!
//! Validation:
//!   Covered by the registry unit tests in this file.
const std = @import("std");
const Allocator = std.mem.Allocator;
const BuiltinPlugins = @import("../builtin/root.zig");
const Manifest = @import("../loader/manifest.zig");
const Selection = @import("../selection.zig");
const Slots = @import("../slots.zig");

/// Registry lane classification for stored capabilities.
pub const Lane = enum {
    declarative,
    native,
};

/// Capability entry stored in the registry index.
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

/// Registry-owned manifest copy with duplicated string storage.
pub const OwnedManifest = struct {
    manifest: Manifest.PluginManifest,

    /// Purpose:
    ///   Clone a manifest into registry-owned storage.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `CapabilityRegistry::OwnedManifest.clone`
    ///
    /// Inputs:
    ///   `manifest` is the declarative plugin manifest to copy.
    ///
    /// Outputs:
    ///   Returns a manifest clone with all owned strings duplicated.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   The manifest is already validated before cloning.
    ///
    /// Decisions:
    ///   Duplicate the manifest instead of borrowing it so registry snapshots
    ///   remain stable after the caller mutates its input structures.
    ///
    /// Validation:
    ///   Covered by the registry tests that mutate manifests after snapshotting.
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

    /// Purpose:
    ///   Release the registry-owned manifest storage.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `CapabilityRegistry::OwnedManifest.deinit`
    ///
    /// Inputs:
    ///   The manifest stored on `self`.
    ///
    /// Outputs:
    ///   Frees all duplicated manifest storage.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   The manifest was cloned by this registry.
    ///
    /// Decisions:
    ///   Tear down nested strings before clearing the wrapper.
    ///
    /// Validation:
    ///   Covered indirectly by registry teardown tests.
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

/// Snapshot-time capability view derived from the registry.
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

    /// Purpose:
    ///   Release the derived version label for a snapshot capability.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `CapabilityRegistry::SnapshotCapability.deinit`
    ///
    /// Inputs:
    ///   The snapshot capability stored on `self`.
    ///
    /// Outputs:
    ///   Frees the derived version label and poisons the wrapper.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   `version_label` was allocated by the registry.
    ///
    /// Decisions:
    ///   Keep the snapshot capability lightweight and derive the label only
    ///   once per snapshot build.
    ///
    /// Validation:
    ///   Covered indirectly by snapshot teardown tests.
    pub fn deinit(self: *SnapshotCapability, allocator: Allocator) void {
        allocator.free(self.version_label);
        self.* = undefined;
    }
};

/// Flattened snapshot view consumed by the runtime.
pub const PluginSnapshot = struct {
    generation: u64 = 0,
    manifests: []OwnedManifest = &.{},
    capabilities: []SnapshotCapability = &.{},
    dataset_hash_entries: [][]const u8 = &.{},
    native_slot_entries: [][]const u8 = &.{},
    native_entry_symbol_entries: [][]const u8 = &.{},
    native_library_path_entries: [][]const u8 = &.{},

    /// Purpose:
    ///   Tear down a plugin snapshot and its flattened view tables.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `CapabilityRegistry::PluginSnapshot.deinit`
    ///
    /// Inputs:
    ///   The materialized snapshot data on `self`.
    ///
    /// Outputs:
    ///   Frees all owned manifest and view storage.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   Snapshot view arrays were allocated by the registry helpers below.
    ///
    /// Decisions:
    ///   Free snapshot capabilities before manifests so derived labels are
    ///   released before the manifest clones they reference.
    ///
    /// Validation:
    ///   Covered indirectly by snapshot teardown tests.
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

    /// Purpose:
    ///   Return the number of rendered plugin-version labels in the snapshot.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `CapabilityRegistry::PluginSnapshot.pluginVersionCount`
    ///
    /// Inputs:
    ///   The materialized snapshot view.
    ///
    /// Outputs:
    ///   Returns the number of derived version labels.
    ///
    /// Units:
    ///   Count.
    ///
    /// Assumptions:
    ///   The capability array and version-label array stay aligned.
    ///
    /// Decisions:
    ///   Expose a narrow view instead of the whole snapshot internals.
    ///
    /// Validation:
    ///   Covered by the registry snapshot tests.
    pub fn pluginVersionCount(self: *const PluginSnapshot) usize {
        return self.capabilities.len;
    }

    /// Purpose:
    ///   Read a derived plugin-version label from the snapshot.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `CapabilityRegistry::PluginSnapshot.pluginVersionAt`
    ///
    /// Inputs:
    ///   `index` selects a materialized capability version label.
    ///
    /// Outputs:
    ///   Returns the derived label at `index`.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   `index` is in bounds.
    ///
    /// Decisions:
    ///   Assert on out-of-bounds access because this is an internal snapshot
    ///   view.
    ///
    /// Validation:
    ///   Covered by the registry snapshot tests.
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

/// Registry of manifests and capabilities.
pub const CapabilityRegistry = struct {
    manifests: std.ArrayListUnmanaged(OwnedManifest) = .{},
    capabilities: std.ArrayListUnmanaged(Capability) = .{},
    generation: u64 = 0,
    bootstrapped: bool = false,

    /// Purpose:
    ///   Register a validated manifest in the capability index.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `CapabilityRegistry::registerManifest`
    ///
    /// Inputs:
    ///   `manifest` is the validated plugin contract and `allow_native_plugins`
    ///   gates native lane registration.
    ///
    /// Outputs:
    ///   Stores the manifest and appends its capability entries.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   The manifest has already passed policy validation.
    ///
    /// Decisions:
    ///   Clone the manifest before indexing it so later snapshots do not borrow
    ///   caller-owned data.
    ///
    /// Validation:
    ///   Covered by the registry opt-in tests in this file.
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

    /// Purpose:
    ///   Materialize the selected capabilities into a runtime snapshot.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `CapabilityRegistry::snapshotSelection`
    ///
    /// Inputs:
    ///   `provider_selection` names the providers used by the current plan.
    ///
    /// Outputs:
    ///   Returns a flattened snapshot of the selected manifests and capabilities.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   The provider selection uses registered capability names.
    ///
    /// Decisions:
    ///   Collapse the selection into snapshot-owned view tables so runtime code
    ///   does not have to re-scan the registry.
    ///
    /// Validation:
    ///   Covered by the snapshot selection tests in this file.
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

    /// Purpose:
    ///   Seed the registry with builtin manifests.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `CapabilityRegistry::bootstrapBuiltin`
    ///
    /// Inputs:
    ///   `allow_native_plugins` controls whether builtin native manifests retain
    ///   their native lane.
    ///
    /// Outputs:
    ///   Registers the builtin declarative and native manifests exactly once.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   The builtin manifest catalog is static for the process lifetime.
    ///
    /// Decisions:
    ///   Downgrade builtin native manifests to declarative-only copies when
    ///   native loading is disallowed so the registry still exposes their
    ///   capability metadata.
    ///
    /// Validation:
    ///   Covered by the bootstrap policy tests in this file.
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
            // DECISION:
            //   Preserve builtin capability metadata while stripping the native
            //   lane so declarative-only policy still sees the same slot names.
            inline for (BuiltinPlugins.manifests.native_runtime) |manifest| {
                try self.registerManifest(allocator, manifestWithoutNativeLane(manifest), false);
            }
        }

        self.bootstrapped = true;
    }

    /// Purpose:
    ///   Materialize a complete inventory snapshot.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `CapabilityRegistry::snapshotInventory`
    ///
    /// Inputs:
    ///   No additional inputs beyond the registry state.
    ///
    /// Outputs:
    ///   Returns a snapshot containing every registered manifest and capability.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   The caller needs a full inventory rather than a plan-specific slice.
    ///
    /// Decisions:
    ///   Use the same snapshot materialization path as selection so the runtime
    ///   sees a consistent view layout.
    ///
    /// Validation:
    ///   Covered by the registry snapshot tests.
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

    /// Purpose:
    ///   Release the registry and all cloned manifest storage.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `CapabilityRegistry::deinit`
    ///
    /// Inputs:
    ///   The registry state on `self`.
    ///
    /// Outputs:
    ///   Frees all registry-owned storage and resets the wrapper.
    ///
    /// Units:
    ///   N/A.
    ///
    /// Assumptions:
    ///   The registry owns every stored manifest clone.
    ///
    /// Decisions:
    ///   Tear down manifests before array lists so nested strings are released
    ///   while indices are still valid.
    ///
    /// Validation:
    ///   Covered indirectly by registry teardown tests.
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
    // INVARIANT:
    //   The copied manifest keeps the original capability metadata but clears
    //   the native contract so declarative-only bootstraps can still register it.
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
    // DECISION:
    //   Flatten dataset hashes into one contiguous view so the runtime can
    //   inspect provenance without walking every manifest clone.
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
    // INVARIANT:
    //   Native view tables remain aligned by index across slot, entry symbol,
    //   and library-path arrays.
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
