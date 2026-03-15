pub const DiagnosticsSpec = struct {
    provenance: bool = true,
    jacobians: bool = false,
    internal_fields: bool = false,
    materialize_cache_keys: bool = false,
};

pub const Diagnostics = struct {
    summary: []const u8 = "",
    emitted_provenance: bool = false,
    emitted_jacobians: bool = false,
    emitted_internal_fields: bool = false,
    materialized_cache_keys: bool = false,

    pub fn fromSpec(spec: DiagnosticsSpec, summary: []const u8) Diagnostics {
        return .{
            .summary = summary,
            .emitted_provenance = spec.provenance,
            .emitted_jacobians = spec.jacobians,
            .emitted_internal_fields = spec.internal_fields,
            .materialized_cache_keys = spec.materialize_cache_keys,
        };
    }
};

test "diagnostics materialization mirrors the requested spec" {
    const diagnostics = Diagnostics.fromSpec(.{
        .provenance = true,
        .jacobians = true,
        .internal_fields = false,
        .materialize_cache_keys = true,
    }, "prepared");

    try std.testing.expectEqualStrings("prepared", diagnostics.summary);
    try std.testing.expect(diagnostics.emitted_provenance);
    try std.testing.expect(diagnostics.emitted_jacobians);
    try std.testing.expect(!diagnostics.emitted_internal_fields);
    try std.testing.expect(diagnostics.materialized_cache_keys);
}

const std = @import("std");
