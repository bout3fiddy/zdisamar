//! Purpose:
//!   Re-export the DOAS retrieval entrypoint.
//!
//! Physics:
//!   DOAS is the differential-optical-depth retrieval path built on the
//!   shared spectral-fit solver.
//!
//! Vendor:
//!   Classic DOAS retrieval stage.
//!
//! Design:
//!   Keep the package root thin so callers import the solver from a single
//!   namespace.
//!
//! Invariants:
//!   The package must continue to expose the solver entrypoint unchanged.
//!
//! Validation:
//!   DOAS solver tests import this module root.

pub const solver = @import("solver.zig");

test {
    _ = @import("solver.zig");
}
