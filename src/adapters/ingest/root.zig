//! Purpose:
//!   Expose retained ingest adapters for bundled reference assets.
//!
//! Physics:
//!   Normalize vendor and bundled scientific tables into typed inputs before they reach the
//!   engine and kernels.
//!
//! Vendor:
//!   `ingest adapter package`
//!
//! Design:
//!   Keep the adapter barrel thin so file-format logic stays in the dedicated loaders.
//!
//! Invariants:
//!   Parsing and asset hydration remain isolated from core and kernel code.
//!
//! Validation:
//!   Ingest unit tests and the reference-asset loader tests.

pub const reference_assets = @import("reference_assets.zig");

test "ingest package includes retained reference loaders" {
    _ = @import("reference_assets.zig");
}
