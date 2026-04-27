//! Purpose:
//!   Facade for the adding-method transport kernel.
//!
//! Physics:
//!   Orchestrates layered adding-method transport for scattering scenes.
//!
//! Vendor:
//!   `adding`
//!
//! Design:
//!   Keeps the public surface stable while pushing execution, composition, and
//!   field reconstruction into sibling modules.
//!
//! Invariants:
//!   Public callers continue to use `execute` with unchanged behavior.
//!
//! Validation:
//!   `tests/unit/transport_adding_test.zig` and transport integration suites.

pub const execution = @import("adding/execute.zig");
pub const composition = @import("adding/composition.zig");
pub const fields = @import("adding/fields.zig");

pub const execute = execution.execute;

test {
    _ = execution;
    _ = composition;
    _ = fields;
}
