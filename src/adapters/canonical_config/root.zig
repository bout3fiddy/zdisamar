//! Purpose:
//!   Re-export the canonical configuration parser, document model, and
//!   execution compiler.
//!
//! Physics:
//!   This package does not implement scientific behavior directly; it turns
//!   canonical YAML into typed plan, scene, and execution records that the
//!   engine can consume.
//!
//! Vendor:
//!   Canonical configuration adapter surface.
//!
//! Design:
//!   Keep the adapter surface in one namespace so callers can import YAML
//!   parsing and execution compilation together.
//!
//! Invariants:
//!   The package must preserve the canonical document and execution entrypoint
//!   names.
//!
//! Validation:
//!   Canonical config tests import this root module.

pub const yaml = @import("yaml.zig");
pub const Error = @import("Document.zig").Error;
pub const Document = @import("Document.zig").Document;
pub const ResolvedExperiment = @import("Document.zig").ResolvedExperiment;
pub const ProductKind = @import("Document.zig").ProductKind;
pub const resolveFile = @import("Document.zig").resolveFile;
pub const execution = @import("execution.zig");
pub const ExecutionProgram = execution.ExecutionProgram;
pub const ExecutionOutcome = execution.ExecutionOutcome;
pub const compileResolved = execution.compileResolved;
pub const resolveCompileAndExecute = execution.resolveCompileAndExecute;

test "canonical config package exposes parser and resolver" {
    _ = @import("yaml.zig");
    _ = @import("Document.zig");
    _ = @import("execution.zig");
}
