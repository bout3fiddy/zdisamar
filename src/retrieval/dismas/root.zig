//! Purpose:
//!   Re-export the DISMAS retrieval entrypoint.
//!
//! Physics:
//!   DISMAS is the direct-intensity retrieval path built on the shared
//!   spectral-fit solver.
//!
//! Vendor:
//!   Direct-intensity DISMAS retrieval stage.
//!
//! Design:
//!   Keep the package root thin so callers import the solver from a single
//!   namespace.
//!
//! Invariants:
//!   The package must continue to expose the solver entrypoint unchanged.
//!
//! Validation:
//!   DISMAS solver tests import this module root.

pub const solver = @import("solver.zig");

test {
    _ = @import("solver.zig");
}
