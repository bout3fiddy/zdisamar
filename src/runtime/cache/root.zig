//! Purpose:
//!   Expose the runtime caches used to reuse prepared layouts, datasets, and LUT metadata.
//!
//! Physics:
//!   Preserve cache state for repeated retrieval and optics preparation without changing the
//!   underlying scientific data.
//!
//! Vendor:
//!   `runtime cache package`
//!
//! Design:
//!   Keep the barrel thin and let each cache own its own lifecycle and invariants.
//!
//! Invariants:
//!   Cache implementations remain the only owners of their internal storage.
//!
//! Validation:
//!   Unit tests for `PreparedLayout`, `DatasetCache`, `LUTCache`, and `PlanCache`.

pub const PreparedLayout = @import("PreparedLayout.zig").PreparedLayout;
pub const DatasetCache = @import("DatasetCache.zig").DatasetCache;
pub const LUTCache = @import("LUTCache.zig").LUTCache;
pub const PlanCache = @import("PlanCache.zig").PlanCache;

test {
    _ = @import("PreparedLayout.zig");
    _ = @import("DatasetCache.zig");
    _ = @import("LUTCache.zig");
    _ = @import("PlanCache.zig");
}
