const std = @import("std");
const builtin = @import("builtin");

const internal = @import("internal");

const transport_worker_memory = internal.cache.transport_worker_memory;

test "TransportWorkerMemory layout matches LABOS worker owner contract" {
    try std.testing.expectEqual(@as(usize, 3272), @sizeOf(transport_worker_memory.TransportWorkerMemory));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(transport_worker_memory.TransportWorkerMemory));
    try std.testing.expectEqual(
        @as(usize, 0),
        @offsetOf(transport_worker_memory.TransportWorkerMemory, "attenuation_data"),
    );
    try std.testing.expectEqual(
        @as(usize, 320),
        @offsetOf(transport_worker_memory.TransportWorkerMemory, "line_sigma_cm2_per_molecule"),
    );
    try std.testing.expectEqual(
        @as(usize, 432),
        @offsetOf(transport_worker_memory.TransportWorkerMemory, "cached_geometry"),
    );
    try std.testing.expectEqual(
        @as(usize, 3264),
        @offsetOf(transport_worker_memory.TransportWorkerMemory, "cached_geometry_valid"),
    );
}

test "TransportWorkerMemory layout exposes worker collection shape" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(transport_worker_memory.TransportWorkerMemoryCollection));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(transport_worker_memory.TransportWorkerMemoryCollection));
    try std.testing.expectEqual(
        @as(usize, 0),
        @offsetOf(transport_worker_memory.TransportWorkerMemoryCollection, "workers"),
    );
}

test "TransportWorkerMemory reserves optics scratch rows" {
    var memory = transport_worker_memory.TransportWorkerMemory{};
    defer memory.deinit(std.testing.allocator);

    try memory.ensureOpticsCapacity(std.testing.allocator, 5, 3);
    try std.testing.expectEqual(@as(usize, 5), memory.line_sigma_cm2_per_molecule.len);
    try std.testing.expectEqual(@as(usize, 5), memory.support_optics.len);
    try std.testing.expectEqual(@as(usize, 3), memory.layer_optics.len);
    try std.testing.expectEqual(@as(usize, 4), memory.source_level_rows.len);
    try std.testing.expectEqual(@as(usize, 5), memory.curved_samples.len);
    try std.testing.expectEqual(@as(usize, 4), memory.curved_level_starts.len);
    try std.testing.expectEqual(@as(usize, 4), memory.curved_level_altitudes_km.len);

    const line_sigma_ptr = memory.line_sigma_cm2_per_molecule.ptr;
    const support_ptr = memory.support_optics.ptr;
    try memory.ensureOpticsCapacity(std.testing.allocator, 4, 2);
    try std.testing.expectEqual(line_sigma_ptr, memory.line_sigma_cm2_per_molecule.ptr);
    try std.testing.expectEqual(support_ptr, memory.support_optics.ptr);
}

test "TransportWorkerMemory reserves active transport prefixes without physics inputs" {
    var memory = transport_worker_memory.TransportWorkerMemory{};
    defer memory.deinit(std.testing.allocator);

    try memory.ensureCapacity(std.testing.allocator, 4, 6, 5, 3, true);

    try std.testing.expectEqual(@as(usize, 4), memory.rt_layers.len);
    try std.testing.expectEqual(@as(usize, 3), memory.layer_phase_max_indices.len);
    try std.testing.expectEqual(@as(usize, 15), memory.layer_effective_scattering_suffixes.len);
    try std.testing.expectEqual(@as(usize, 4), memory.source_phase_max_indices.len);
    try std.testing.expectEqual(@as(usize, 96), memory.attenuation_data.len);
    try std.testing.expectEqual(@as(usize, 96), memory.attenuation_tangent_data.len);
    try std.testing.expectEqual(@as(usize, 18), memory.attenuation_layer_transmittance.len);
    try std.testing.expectEqual(@as(usize, 24), memory.attenuation_top_to_level.len);

    const solve_work = try memory.solveWorkArrays(3, 6, true);
    try std.testing.expectEqual(@as(usize, 96), solve_work.dynamic_attenuation_data.len);
    try std.testing.expectEqual(@as(usize, 96), solve_work.dynamic_attenuation_tangent_data.len);
    try std.testing.expectEqual(@as(usize, 18), solve_work.layer_transmittance.len);
    try std.testing.expectEqual(@as(usize, 4), solve_work.rt_layers.len);
    try std.testing.expectEqual(@as(usize, 4), solve_work.rt_layers_tangent.len);
    try std.testing.expectEqual(@as(usize, 3), solve_work.layer_phase_max_indices.len);
    try std.testing.expectEqual(@as(usize, 4), solve_work.orders.ud.len);
    try std.testing.expectEqual(@as(usize, 4), solve_work.orders.ud_sum_local.len);
    try std.testing.expectEqual(@as(usize, 3), solve_work.plm_basis_cache.len);
    try std.testing.expectEqual(&memory.cached_geometry_valid, solve_work.geometry_valid);
}

test "TransportWorkerMemory rejects oversized borrowed prefixes" {
    var memory = transport_worker_memory.TransportWorkerMemory{};
    defer memory.deinit(std.testing.allocator);
    try memory.ensureCapacity(std.testing.allocator, 2, 4, 2, 1, false);

    try std.testing.expectError(error.ShapeMismatch, memory.solveWorkArrays(1, 4, true));
}

test "TransportWorkerMemory size is stable across build modes" {
    _ = builtin;
    try std.testing.expectEqual(@as(usize, 3272), @sizeOf(transport_worker_memory.TransportWorkerMemory));
}
