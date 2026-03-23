//! Purpose:
//!   Facade for the adding-method transport kernel.
//!
//! Physics:
//!   Orchestrates layered adding-method transport for scattering scenes and
//!   exposes the top-level boundary diagnostic entrypoint.
//!
//! Vendor:
//!   `adding`
//!
//! Design:
//!   Keeps the public surface stable while pushing execution, composition,
//!   field reconstruction, and diagnostics into sibling modules.
//!
//! Invariants:
//!   Public callers continue to use `execute` and the top-down diagnostics
//!   helper with unchanged behavior.
//!
//! Validation:
//!   `tests/unit/transport_adding_test.zig` and transport integration suites.

pub const execution = @import("adding/execute.zig");
pub const composition = @import("adding/composition.zig");
pub const fields = @import("adding/fields.zig");
pub const diagnostics = @import("adding/diagnostics.zig");

pub const execute = execution.execute;
pub const calcTopDownBoundarySurfaceDiagnostics = diagnostics.calcTopDownBoundarySurfaceDiagnostics;

test {
    _ = execution;
    _ = composition;
    _ = fields;
    _ = diagnostics;
}
