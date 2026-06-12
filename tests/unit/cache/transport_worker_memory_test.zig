const std = @import("std");
const builtin = @import("builtin");

const internal = @import("internal");

const phase_table = internal.setup.phase_table;
const transport_worker_memory = internal.cache.transport_worker_memory;

test "TransportWorkerMemory layout matches LABOS worker owner contract" {
    try std.testing.expectEqual(@as(usize, 3192), @sizeOf(transport_worker_memory.TransportWorkerMemory));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(transport_worker_memory.TransportWorkerMemory));
    try std.testing.expectEqual(
        @as(usize, 0),
        @offsetOf(transport_worker_memory.TransportWorkerMemory, "attenuation_data"),
    );
    try std.testing.expectEqual(
        @as(usize, 352),
        @offsetOf(transport_worker_memory.TransportWorkerMemory, "cached_geometry"),
    );
    try std.testing.expectEqual(
        @as(usize, 3184),
        @offsetOf(transport_worker_memory.TransportWorkerMemory, "cached_geometry_valid"),
    );
}

test "TransportWorkerMemory reserves active transport prefixes without physics inputs" {
    var memory = transport_worker_memory.TransportWorkerMemory{};
    defer memory.deinit(std.testing.allocator);

    try memory.ensureCapacity(std.testing.allocator, 4, 6, 5, 3, true);

    try std.testing.expectEqual(@as(usize, 4), (try memory.layerRt(4)).len);
    try std.testing.expectEqual(@as(usize, 3), (try memory.layerPhaseMaxIndices(3)).len);
    try std.testing.expectEqual(@as(usize, 15), (try memory.layerEffectiveScatteringSuffixes(3, 5)).len);
    try std.testing.expectEqual(@as(usize, 4), (try memory.sourcePhaseMaxIndices(4)).len);
    try std.testing.expectEqual(@as(usize, 96), (try memory.dynamicAttenuationBuffer(6, 3)).len);
    try std.testing.expectEqual(@as(usize, 96), (try memory.dynamicAttenuationTangentBuffer(6, 3)).len);
    try std.testing.expectEqual(@as(usize, 18), (try memory.layerTransmittanceBuffer(6, 3)).len);
    try std.testing.expectEqual(@as(usize, 24), (try memory.topToLevelBuffer(6, 3)).len);

    const orders = try memory.ordersWorkArrays(4, true);
    try std.testing.expectEqual(@as(usize, 4), orders.ud.len);
    try std.testing.expectEqual(@as(usize, 4), orders.ud_sum_local.len);
    try std.testing.expectEqual(@as(usize, 4), orders.ud_orde.len);
    try std.testing.expectEqual(@as(usize, 4), orders.ud_local.len);
    try std.testing.expectEqual(@as(usize, 4), orders.ud_tangent_orde.len);
    try std.testing.expectEqual(@as(usize, 4), orders.ud_tangent_local.len);
    try std.testing.expectEqual(@as(usize, 4), orders.rt_active.len);

    const solve_work = try memory.solveWorkArrays(3, 6);
    try std.testing.expectEqual(@as(usize, 96), solve_work.dynamic_attenuation_data.len);
    try std.testing.expectEqual(@as(usize, 96), solve_work.dynamic_attenuation_tangent_data.len);
    try std.testing.expectEqual(@as(usize, 18), solve_work.layer_transmittance.len);
    try std.testing.expectEqual(@as(usize, 4), solve_work.rt_layers.len);
    try std.testing.expectEqual(@as(usize, 4), solve_work.rt_layers_tangent.len);
    try std.testing.expectEqual(@as(usize, 3), solve_work.layer_phase_max_indices.len);
    try std.testing.expectEqual(@as(usize, 4), solve_work.orders.ud.len);
    try std.testing.expectEqual(@as(usize, 3), solve_work.plm_basis_cache.len);
}

test "TransportWorkerMemory geometry changes invalidate geometry-dependent caches" {
    var memory = transport_worker_memory.TransportWorkerMemory{};
    defer memory.deinit(std.testing.allocator);
    try memory.ensureCapacity(std.testing.allocator, 3, 6, 4, 2, false);

    var basis_valid = try memory.phaseRowValid(3);
    basis_valid[0] = true;
    memory.plm_basis_cache_valid[0] = true;
    memory.previous_layer_phase_signature_valid[0] = true;

    const first = try memory.geometryWithStatus(4, 0.58, 0.64);
    try std.testing.expect(!first.hit);
    try std.testing.expect(!memory.plm_basis_cache_valid[0]);
    try std.testing.expect(!memory.previous_layer_phase_signature_valid[0]);

    memory.plm_basis_cache_valid[0] = true;
    memory.previous_layer_phase_signature_valid[0] = true;
    const second = try memory.geometryWithStatus(4, 0.58, 0.64);
    try std.testing.expect(second.hit);
    try std.testing.expect(memory.plm_basis_cache_valid[0]);
    try std.testing.expect(memory.previous_layer_phase_signature_valid[0]);

    const changed = try memory.geometryWithStatus(4, 0.57, 0.64);
    try std.testing.expect(!changed.hit);
    try std.testing.expect(!memory.plm_basis_cache_valid[0]);
    try std.testing.expect(!memory.previous_layer_phase_signature_valid[0]);
}

test "TransportWorkerMemory reuses and extends Fourier PLM basis rows" {
    var memory = transport_worker_memory.TransportWorkerMemory{};
    defer memory.deinit(std.testing.allocator);
    try memory.ensureCapacity(std.testing.allocator, 3, 6, 4, 4, false);
    const geometry = (try memory.geometryWithStatus(4, 0.58, 0.64)).geometry;

    const first = try memory.fourierPlmBasisWithStatus(1, 2, 3, geometry);
    try std.testing.expect(!first.hit);
    try std.testing.expect(!first.extended);
    try std.testing.expectEqual(@as(usize, 2), first.plm_basis.max_phase_index);

    const second = try memory.fourierPlmBasisWithStatus(1, 2, 3, geometry);
    try std.testing.expect(second.hit);
    try std.testing.expect(!second.extended);

    const third = try memory.fourierPlmBasisWithStatus(1, 3, 3, geometry);
    try std.testing.expect(third.hit);
    try std.testing.expect(third.extended);
    try std.testing.expectEqual(@as(usize, 3), third.plm_basis.max_phase_index);

    try std.testing.expectError(
        error.ShapeMismatch,
        memory.fourierPlmBasisWithStatus(phase_table.coefficient_count, 3, 3, geometry),
    );
}

test "TransportWorkerMemory rejects oversized borrowed prefixes" {
    var memory = transport_worker_memory.TransportWorkerMemory{};
    defer memory.deinit(std.testing.allocator);
    try memory.ensureCapacity(std.testing.allocator, 2, 4, 2, 1, false);

    try std.testing.expectError(error.ShapeMismatch, memory.layerRt(3));
    try std.testing.expectError(error.ShapeMismatch, memory.ordersWorkArrays(2, true));
    try std.testing.expectError(
        error.ShapeMismatch,
        memory.layerEffectiveScatteringSuffixes(1, phase_table.coefficient_count + 1),
    );
}

test "TransportWorkerMemory resetValidity keeps buffers and clears validity flags" {
    var memory = transport_worker_memory.TransportWorkerMemory{};
    defer memory.deinit(std.testing.allocator);
    try memory.ensureCapacity(std.testing.allocator, 3, 6, 4, 2, true);
    const before_ptr = memory.order_ud.ptr;

    memory.cached_geometry_valid = true;
    memory.plm_basis_cache_valid[0] = true;
    memory.layer_phase_row_valid[0] = true;
    memory.previous_layer_phase_signature_valid[0] = true;
    memory.resetValidity();

    try std.testing.expectEqual(before_ptr, memory.order_ud.ptr);
    try std.testing.expect(!memory.cached_geometry_valid);
    try std.testing.expect(!memory.plm_basis_cache_valid[0]);
    try std.testing.expect(!memory.layer_phase_row_valid[0]);
    try std.testing.expect(!memory.previous_layer_phase_signature_valid[0]);
}

test "TransportWorkerMemory size is stable across build modes" {
    _ = builtin;
    try std.testing.expectEqual(@as(usize, 3192), @sizeOf(transport_worker_memory.TransportWorkerMemory));
}
