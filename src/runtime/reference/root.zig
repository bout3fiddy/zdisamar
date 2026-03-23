//! Purpose:
//!   Expose the bundled reference optics loaders used by the runtime.
//!
//! Physics:
//!   Surface the climatology, spectroscopy, CIA, LUT, and Mie reference pathways without
//!   duplicating the selection or parsing rules.
//!
//! Vendor:
//!   `bundled optics reference package`
//!
//! Design:
//!   Keep this barrel thin so the concrete loader and asset-selection logic stays in the
//!   dedicated modules.
//!
//! Invariants:
//!   Imported modules must remain the single source of truth for bundled reference data.
//!
//! Validation:
//!   `tests/unit/bundled_optics_test.zig` and the optics validation helpers.

pub const bundled_optics = @import("BundledOptics.zig");
pub const bundled_optics_assets = @import("bundled_optics_assets.zig");

test {
    _ = @import("BundledOptics.zig");
    _ = @import("bundled_optics_assets.zig");
}
