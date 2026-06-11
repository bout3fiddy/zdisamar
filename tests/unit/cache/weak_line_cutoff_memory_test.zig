const std = @import("std");
const internal = @import("internal");

const evidence_root =
    "scratch/refactor/2026-06-11-explicit-dataflow-refactor/evidence/baseline-main-56605387/";
const max_internal_dump_bytes = 1 << 20;

test "WeakLineCutoffMemory keeps support wavelengths and wavenumbers together" {
    var memory: internal.cache.weak_line_cutoff_memory.WeakLineCutoffMemory = .{};
    defer memory.deinit(std.testing.allocator);

    const wavelengths = [_]f64{ 755.0, 760.0, 776.0 };
    try memory.replaceFromSupport(std.testing.allocator, wavelengths[0..]);

    try std.testing.expect(memory.valid());
    try std.testing.expectEqual(@as(usize, 3), memory.wavelengths_nm.len);
    try std.testing.expectApproxEqAbs(1.0e7 / 760.0, memory.wavenumbers_cm1[1], 1.0e-12);
}

test "WeakLineCutoffMemory accepts the exact high-resolution wavelength evidence list" {
    const allocator = std.testing.allocator;

    const internal_bytes = try std.fs.cwd().readFileAlloc(
        allocator,
        evidence_root ++ "internal-dump-baseline.json",
        max_internal_dump_bytes,
    );
    defer allocator.free(internal_bytes);
    var internal_dump = try std.json.parseFromSlice(InternalDumpEvidence, allocator, internal_bytes, .{
        .ignore_unknown_fields = true,
    });
    defer internal_dump.deinit();

    const route_bytes = try std.fs.cwd().readFileAlloc(
        allocator,
        evidence_root ++ "route-shape-retained-snapshot.json",
        4096,
    );
    defer allocator.free(route_bytes);
    var route_shape = try std.json.parseFromSlice(RouteShapeEvidence, allocator, route_bytes, .{
        .ignore_unknown_fields = true,
    });
    defer route_shape.deinit();

    const forward_misses = internal_dump.value.sampling_table.forward_misses;
    try std.testing.expectEqual(route_shape.value.counts.high_resolution_radiance_samples, forward_misses.len);
    try std.testing.expectEqual(internal_dump.value.workspace_reuse_probe.first_forward_miss_count, forward_misses.len);
    try std.testing.expectEqual(
        internal_dump.value.workspace_reuse_probe.first_profile_cache_count,
        forward_misses.len,
    );
    try std.testing.expectEqual(
        route_shape.value.counts.output_wavelengths,
        internal_dump.value.route.output_wavelengths,
    );

    const support_wavelengths = try allocator.alloc(f64, forward_misses.len);
    defer allocator.free(support_wavelengths);
    for (forward_misses, support_wavelengths, 0..) |miss, *wavelength_nm, index| {
        try std.testing.expectEqual(index, miss.index);
        wavelength_nm.* = miss.wavelength_nm;
    }

    var memory: internal.cache.weak_line_cutoff_memory.WeakLineCutoffMemory = .{};
    defer memory.deinit(allocator);
    try memory.replaceFromSupport(allocator, support_wavelengths);

    try std.testing.expect(memory.valid());
    try std.testing.expectEqual(forward_misses.len, memory.wavelengths_nm.len);
    try std.testing.expectApproxEqAbs(forward_misses[0].wavelength_nm, memory.wavelengths_nm[0], 0.0);
    try std.testing.expectApproxEqAbs(
        forward_misses[forward_misses.len - 1].wavelength_nm,
        memory.wavelengths_nm[memory.wavelengths_nm.len - 1],
        0.0,
    );
    try std.testing.expectApproxEqAbs(
        internal.common.units.wavelengthToWavenumberCm1(memory.wavelengths_nm[0]),
        memory.wavenumbers_cm1[0],
        0.0,
    );
}

const ForwardMissEvidence = struct {
    index: usize,
    wavelength_nm: f64,
};

const InternalDumpEvidence = struct {
    route: struct {
        output_wavelengths: usize,
    },
    sampling_table: struct {
        forward_misses: []ForwardMissEvidence,
    },
    workspace_reuse_probe: struct {
        first_forward_miss_count: usize,
        first_profile_cache_count: usize,
    },
};

const RouteShapeEvidence = struct {
    counts: struct {
        high_resolution_radiance_samples: usize,
        output_wavelengths: usize,
    },
};
