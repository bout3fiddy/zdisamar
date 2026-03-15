const std = @import("std");
const zdisamar = @import("zdisamar");

const ProvenanceGolden = struct {
    engine_version: []const u8,
    model_family_default: []const u8,
    solver_route_default: []const u8,
    transport_family_default: []const u8,
    derivative_mode_default: []const u8,
    numerical_mode_default: []const u8,
    plugin_inventory_generation_min: u64,
    required_plugin_version: []const u8,
    required_dataset_hash: []const u8,
    required_native_capability_slot: []const u8,
    required_native_entry_symbol: []const u8,
};

test "golden provenance defaults remain stable" {
    const raw = try std.fs.cwd().readFileAlloc(
        std.testing.allocator,
        "validation/golden/result_provenance_golden.json",
        1024 * 1024,
    );
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        ProvenanceGolden,
        std.testing.allocator,
        raw,
        .{},
    );
    defer parsed.deinit();

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();

    try engine.bootstrapBuiltinCatalog();
    const plan = try engine.preparePlan(.{});
    var workspace = engine.createWorkspace("golden-suite");
    const request = zdisamar.Request.init(.{
        .id = "scene-golden-001",
        .spectral_grid = .{ .sample_count = 16 },
    });
    var result = try engine.execute(&plan, &workspace, request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings(parsed.value.engine_version, result.provenance.engine_version);
    try std.testing.expectEqualStrings(parsed.value.model_family_default, result.provenance.model_family);
    try std.testing.expectEqualStrings(parsed.value.solver_route_default, result.provenance.solver_route);
    try std.testing.expectEqualStrings(parsed.value.transport_family_default, result.provenance.transport_family);
    try std.testing.expectEqualStrings(parsed.value.derivative_mode_default, result.provenance.derivative_mode);
    try std.testing.expectEqualStrings(parsed.value.numerical_mode_default, result.provenance.numerical_mode);
    try std.testing.expect(result.provenance.plugin_inventory_generation >= parsed.value.plugin_inventory_generation_min);

    var saw_plugin_version = false;
    for (result.provenance.pluginVersions()) |plugin_version| {
        if (std.mem.eql(u8, plugin_version, parsed.value.required_plugin_version)) {
            saw_plugin_version = true;
            break;
        }
    }
    try std.testing.expect(saw_plugin_version);

    var saw_dataset_hash = false;
    for (result.provenance.dataset_hashes) |dataset_hash| {
        if (std.mem.eql(u8, dataset_hash, parsed.value.required_dataset_hash)) {
            saw_dataset_hash = true;
            break;
        }
    }
    try std.testing.expect(saw_dataset_hash);

    var saw_native_slot = false;
    for (result.provenance.native_capability_slots) |slot| {
        if (std.mem.eql(u8, slot, parsed.value.required_native_capability_slot)) {
            saw_native_slot = true;
            break;
        }
    }
    try std.testing.expect(saw_native_slot);

    var saw_entry_symbol = false;
    for (result.provenance.native_entry_symbols) |entry_symbol| {
        if (std.mem.eql(u8, entry_symbol, parsed.value.required_native_entry_symbol)) {
            saw_entry_symbol = true;
            break;
        }
    }
    try std.testing.expect(saw_entry_symbol);
}
