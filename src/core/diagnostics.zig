//! Purpose:
//!   Define the lightweight diagnostic selection and materialization surface attached to
//!   engine results.
//!
//! Physics:
//!   Diagnostics here describe which provenance and Jacobian artifacts accompany a run;
//!   they do not compute new physical quantities themselves.
//!
//! Vendor:
//!   `engine diagnostics selection stage`
//!
//! Design:
//!   The engine records requested diagnostic products as typed flags rather than pushing
//!   exporter-specific formatting or side effects into core execution.
//!
//! Invariants:
//!   Materialized diagnostics mirror the request spec exactly and preserve the summary
//!   label supplied by the caller.
//!
//! Validation:
//!   Unit tests below verify that `fromSpec` copies the requested flags faithfully.
const std = @import("std");

/// Purpose:
///   Request which optional diagnostics the engine should emit.
pub const DiagnosticsSpec = struct {
    provenance: bool = true,
    jacobians: bool = false,
};

/// Purpose:
///   Capture which diagnostic products were actually attached to a result.
pub const Diagnostics = struct {
    summary: []const u8 = "",
    emitted_provenance: bool = false,
    emitted_jacobians: bool = false,

    /// Purpose:
    ///   Materialize the emitted-diagnostics summary from the requested specification.
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
