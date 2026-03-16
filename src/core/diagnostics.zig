pub const DiagnosticsSpec = struct {
    provenance: bool = true,
    jacobians: bool = false,
};

pub const Diagnostics = struct {
    summary: []const u8 = "",
    emitted_provenance: bool = false,
    emitted_jacobians: bool = false,

    pub fn fromSpec(spec: DiagnosticsSpec, summary: []const u8) Diagnostics {
        return .{
            .summary = summary,
            .emitted_provenance = spec.provenance,
            .emitted_jacobians = spec.jacobians,
        };
    }
};

test "diagnostics materialization mirrors the requested spec" {
    const diagnostics = Diagnostics.fromSpec(.{
        .provenance = true,
        .jacobians = true,
    }, "prepared");

    try std.testing.expectEqualStrings("prepared", diagnostics.summary);
    try std.testing.expect(diagnostics.emitted_provenance);
    try std.testing.expect(diagnostics.emitted_jacobians);
}

const std = @import("std");
