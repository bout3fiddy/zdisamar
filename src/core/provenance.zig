const std = @import("std");
const Plan = @import("Plan.zig").Plan;
const PluginRegistry = @import("../plugins/registry/CapabilityRegistry.zig");

pub const Provenance = struct {
    engine_version: []const u8 = "0.1.0-dev",
    model_family: []const u8 = "disamar_standard",
    solver_route: []const u8 = "transport.dispatcher",
    transport_family: []const u8 = "adding",
    derivative_mode: []const u8 = "none",
    numerical_mode: []const u8 = "scalar",
    plan_id: u64 = 0,
    plugin_inventory_generation: u64 = 0,
    workspace_label: []const u8 = "",
    scene_id: []const u8 = "",
    plugin_version_count: usize = 0,
    plugin_version_entries: [PluginRegistry.max_snapshot_capabilities][]const u8 = undefined,
    dataset_hashes: []const []const u8 = &[_][]const u8{},
    native_capability_slots: []const []const u8 = &[_][]const u8{},
    native_entry_symbols: []const []const u8 = &[_][]const u8{},
    native_library_paths: []const []const u8 = &[_][]const u8{},

    pub fn fromPlan(
        plan: *const Plan,
        workspace_label: []const u8,
        scene_id: []const u8,
        numerical_mode: []const u8,
    ) Provenance {
        var provenance: Provenance = .{
            .model_family = plan.template.model_family,
            .solver_route = plan.template.transport,
            .transport_family = @tagName(plan.transport_route.family),
            .derivative_mode = @tagName(plan.transport_route.derivative_mode),
            .numerical_mode = numerical_mode,
            .plan_id = plan.id,
            .plugin_inventory_generation = plan.plugin_snapshot.generation,
            .workspace_label = workspace_label,
            .scene_id = scene_id,
            .dataset_hashes = plan.plugin_snapshot.datasetHashes(),
            .native_capability_slots = plan.plugin_snapshot.nativeCapabilitySlots(),
            .native_entry_symbols = plan.plugin_snapshot.nativeEntrySymbols(),
            .native_library_paths = plan.plugin_snapshot.nativeLibraryPaths(),
        };
        for (0..plan.plugin_snapshot.pluginVersionCount()) |index| {
            provenance.plugin_version_entries[index] = plan.plugin_snapshot.pluginVersionAt(index);
        }
        provenance.plugin_version_count = plan.plugin_snapshot.pluginVersionCount();
        return provenance;
    }

    pub fn pluginVersionCount(self: *const Provenance) usize {
        return self.plugin_version_count;
    }

    pub fn pluginVersions(self: *const Provenance) []const []const u8 {
        return self.plugin_version_entries[0..self.plugin_version_count];
    }

    pub fn pluginVersionAt(self: *const Provenance, index: usize) []const u8 {
        std.debug.assert(index < self.plugin_version_count);
        return self.plugin_version_entries[index];
    }

    pub fn setPluginVersions(self: *Provenance, values: []const []const u8) void {
        std.debug.assert(values.len <= self.plugin_version_entries.len);
        for (values, 0..) |value, index| {
            self.plugin_version_entries[index] = value;
        }
        self.plugin_version_count = values.len;
    }
};
