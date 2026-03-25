//! Purpose:
//!   Materialize the owned provenance record returned with execution results.
//!
//! Physics:
//!   Captures the model family, transport/retrieval maturity, derivative semantics, plugin
//!   inventory, and dataset hashes that define how a request was evaluated.
//!
//! Vendor:
//!   `result provenance assembly`
//!
//! Design:
//!   Provenance is derived from the prepared plan snapshot and duplicated into owned storage so
//!   result lifetimes do not depend on engine or plugin internals.
//!
//! Invariants:
//!   All plugin-version, dataset-hash, and native-capability slices refer to the same plan
//!   snapshot generation. Owned provenance must be deinitialized as one unit.
//!
//! Validation:
//!   Provenance ownership tests and the validation/golden result-provenance checks.

const std = @import("std");
const PreparedPlan = @import("Plan.zig").PreparedPlan;

pub const IntervalSemantics = enum {
    none,
    altitude_layering_approximation,
    explicit_pressure_bounds,
};

pub const SubcolumnSemantics = enum {
    none,
    derived_partitions,
    configured_partitions,
};

pub const PhaseSupport = enum {
    none,
    analytic_hg,
    mie_table,
};

/// Purpose:
///   Store the owned execution provenance reported alongside a result.
pub const Provenance = struct {
    engine_version: []const u8 = "0.1.0-dev",
    model_family: []const u8 = "disamar_standard",
    solver_route: []const u8 = "builtin.dispatcher",
    transport_family: []const u8 = "baseline_labos",
    transport_maturity: []const u8 = "method_faithful",
    retrieval_maturity: []const u8 = "not_requested",
    derivative_mode: []const u8 = "none",
    derivative_semantics: []const u8 = "none",
    numerical_mode: []const u8 = "scalar",
    interval_semantics: IntervalSemantics = .none,
    subcolumn_semantics: SubcolumnSemantics = .none,
    aerosol_phase_support: PhaseSupport = .none,
    cloud_phase_support: PhaseSupport = .none,
    plan_id: u64 = 0,
    plugin_inventory_generation: u64 = 0,
    workspace_label: []const u8 = "",
    scene_id: []const u8 = "",
    plugin_version_entries: []const []const u8 = &.{},
    dataset_hashes: []const []const u8 = &.{},
    native_capability_slots: []const []const u8 = &.{},
    native_entry_symbols: []const []const u8 = &.{},
    native_library_paths: []const []const u8 = &.{},
    owns_entries: bool = false,

    /// Purpose:
    ///   Duplicate the plan snapshot and execution labels into owned provenance storage.
    pub fn fromPlanOwned(
        self: *Provenance,
        allocator: std.mem.Allocator,
        plan: *const PreparedPlan,
        workspace_label: []const u8,
        scene_id: []const u8,
        numerical_mode: []const u8,
    ) !void {
        // DECISION:
        //   Provenance records the larger of the plugin-snapshot dataset count and the engine's
        //   dataset cache coverage elsewhere in plan preparation so result metadata always speaks
        //   in terms of the resolved prepared-plan snapshot, not a borrowed runtime view.
        const plugin_version_entries = try dupeSnapshotVersionLabels(allocator, plan.plugin_snapshot.capabilities);
        errdefer freeStringSlice(allocator, plugin_version_entries);
        const dataset_hashes = try dupeStringSlice(allocator, plan.plugin_snapshot.datasetHashes());
        errdefer freeStringSlice(allocator, dataset_hashes);
        const native_capability_slots = try dupeStringSlice(allocator, plan.plugin_snapshot.nativeCapabilitySlots());
        errdefer freeStringSlice(allocator, native_capability_slots);
        const native_entry_symbols = try dupeStringSlice(allocator, plan.plugin_snapshot.nativeEntrySymbols());
        errdefer freeStringSlice(allocator, native_entry_symbols);
        const native_library_paths = try dupeStringSlice(allocator, plan.plugin_snapshot.nativeLibraryPaths());
        errdefer freeStringSlice(allocator, native_library_paths);

        const model_family = try allocator.dupe(u8, plan.template.model_family);
        errdefer allocator.free(model_family);
        const solver_route = try allocator.dupe(u8, plan.template.providers.transport_solver);
        errdefer allocator.free(solver_route);
        const transport_family = try allocator.dupe(
            u8,
            plan.providers.transport.provenanceLabelForRoute(plan.transport_route),
        );
        errdefer allocator.free(transport_family);
        const transport_maturity = try allocator.dupe(
            u8,
            if (std.mem.indexOf(u8, transport_family, "surrogate") != null) "surrogate" else "method_faithful",
        );
        errdefer allocator.free(transport_maturity);
        const retrieval_maturity = try allocator.dupe(
            u8,
            retrievalMaturityLabel(plan),
        );
        errdefer allocator.free(retrieval_maturity);
        const derivative_mode = try allocator.dupe(u8, @tagName(plan.transport_route.derivative_mode));
        errdefer allocator.free(derivative_mode);
        const derivative_semantics = try allocator.dupe(
            u8,
            @tagName(plan.providers.transport.derivativeSemanticsForRoute(plan.transport_route)),
        );
        errdefer allocator.free(derivative_semantics);
        const owned_numerical_mode = try allocator.dupe(u8, numerical_mode);
        errdefer allocator.free(owned_numerical_mode);
        const owned_workspace_label = try allocator.dupe(u8, workspace_label);
        errdefer allocator.free(owned_workspace_label);
        const owned_scene_id = try allocator.dupe(u8, scene_id);
        errdefer allocator.free(owned_scene_id);

        self.* = .{
            .model_family = model_family,
            .solver_route = solver_route,
            .transport_family = transport_family,
            .transport_maturity = transport_maturity,
            .retrieval_maturity = retrieval_maturity,
            .derivative_mode = derivative_mode,
            .derivative_semantics = derivative_semantics,
            .numerical_mode = owned_numerical_mode,
            .plan_id = plan.id,
            .plugin_inventory_generation = plan.plugin_snapshot.generation,
            .workspace_label = owned_workspace_label,
            .scene_id = owned_scene_id,
            .plugin_version_entries = plugin_version_entries,
            .dataset_hashes = dataset_hashes,
            .native_capability_slots = native_capability_slots,
            .native_entry_symbols = native_entry_symbols,
            .native_library_paths = native_library_paths,
            .owns_entries = true,
        };
    }

    pub fn fromPlan(
        allocator: std.mem.Allocator,
        plan: *const PreparedPlan,
        workspace_label: []const u8,
        scene_id: []const u8,
        numerical_mode: []const u8,
    ) !Provenance {
        var provenance: Provenance = undefined;
        try provenance.fromPlanOwned(allocator, plan, workspace_label, scene_id, numerical_mode);
        return provenance;
    }

    /// Purpose:
    ///   Release any strings and string slices owned by this provenance record.
    pub fn deinit(self: *Provenance, allocator: std.mem.Allocator) void {
        if (!self.owns_entries) {
            self.* = .{};
            return;
        }
        freeStringSlice(allocator, self.plugin_version_entries);
        freeStringSlice(allocator, self.dataset_hashes);
        freeStringSlice(allocator, self.native_capability_slots);
        freeStringSlice(allocator, self.native_entry_symbols);
        freeStringSlice(allocator, self.native_library_paths);
        allocator.free(self.model_family);
        allocator.free(self.solver_route);
        allocator.free(self.transport_family);
        allocator.free(self.transport_maturity);
        allocator.free(self.retrieval_maturity);
        allocator.free(self.derivative_mode);
        allocator.free(self.derivative_semantics);
        allocator.free(self.numerical_mode);
        allocator.free(self.workspace_label);
        allocator.free(self.scene_id);
        self.* = .{};
    }

    pub fn pluginVersionCount(self: *const Provenance) usize {
        return self.plugin_version_entries.len;
    }

    pub fn pluginVersions(self: *const Provenance) []const []const u8 {
        return self.plugin_version_entries;
    }

    pub fn pluginVersionAt(self: *const Provenance, index: usize) []const u8 {
        std.debug.assert(index < self.plugin_version_entries.len);
        return self.plugin_version_entries[index];
    }

    pub fn setPluginVersions(self: *Provenance, values: []const []const u8) void {
        self.owns_entries = false;
        self.plugin_version_entries = values;
    }

    /// Purpose:
    ///   Record whether the executed scene used explicit interval and subcolumn
    ///   semantics plus which particle phase support path was active.
    pub fn annotateAtmosphereSemantics(
        self: *Provenance,
        interval_semantics: IntervalSemantics,
        subcolumn_semantics: SubcolumnSemantics,
        aerosol_phase_support: PhaseSupport,
        cloud_phase_support: PhaseSupport,
    ) void {
        self.interval_semantics = interval_semantics;
        self.subcolumn_semantics = subcolumn_semantics;
        self.aerosol_phase_support = aerosol_phase_support;
        self.cloud_phase_support = cloud_phase_support;
    }
};

fn dupeStringSlice(allocator: std.mem.Allocator, values: []const []const u8) ![]const []const u8 {
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

fn dupeSnapshotVersionLabels(
    allocator: std.mem.Allocator,
    values: []const @import("../plugins/registry/CapabilityRegistry.zig").SnapshotCapability,
) ![]const []const u8 {
    const owned = try allocator.alloc([]const u8, values.len);
    errdefer allocator.free(owned);

    var copied: usize = 0;
    errdefer {
        for (owned[0..copied]) |value| allocator.free(value);
    }
    for (values, 0..) |value, index| {
        owned[index] = try allocator.dupe(u8, value.version_label);
        copied = index + 1;
    }
    return owned;
}

fn freeStringSlice(allocator: std.mem.Allocator, values: []const []const u8) void {
    if (values.len == 0) return;
    for (values) |value| allocator.free(value);
    allocator.free(values);
}

fn retrievalMaturityLabel(plan: *const PreparedPlan) []const u8 {
    const provider = plan.providers.retrieval orelse return "not_requested";
    if (std.mem.eql(u8, provider.id, "builtin.oe_solver")) return "real_spectral_fit";
    if (std.mem.eql(u8, provider.id, "builtin.doas_solver")) return "real_spectral_fit";
    if (std.mem.eql(u8, provider.id, "builtin.dismas_solver")) return "real_spectral_fit";
    return "surrogate";
}
