//! Purpose:
//!   Define the typed execution mode carried across request, plan, and result
//!   surfaces.
//!
//! Physics:
//!   Separates synthetic-scene execution from operational measured-input
//!   execution so runtime handling and provenance can stay explicit.
//!
//! Vendor:
//!   `operational vs synthetic execution mode`
//!
//! Design:
//!   Keep the enum small and stable so adapters can opt into operational
//!   behavior without introducing stringly typed mode switches.
//!
//! Invariants:
//!   Operational measured-input requests must never be reported as synthetic.
//!
//! Validation:
//!   Execution-mode matching is covered by request/plan validation and mission
//!   integration tests.

pub const ExecutionMode = enum {
    synthetic,
    operational_measured_input,

    pub fn label(self: ExecutionMode) []const u8 {
        return @tagName(self);
    }
};
