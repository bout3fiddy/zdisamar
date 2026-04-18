//! Purpose:
//!   Define the shared ingest-side reference-asset kinds and embedded-asset
//!   carriers.
//!
//! Physics:
//!   These types identify which scientific table family is being hydrated and
//!   how embedded manifest bytes are addressed before parsing.
//!
//! Vendor:
//!   `reference asset ingest types`
//!
//! Design:
//!   Keep the shared enum and embedded-byte carrier separate from the loader
//!   and parser logic so the public ingest surface stays small.
//!
//! Invariants:
//!   Asset kinds remain stable across manifest hydration and external-file
//!   loading.
//!
//! Validation:
//!   Reference-asset loader tests.

pub const AssetKind = enum {
    climatology_profile,
    cross_section_table,
    collision_induced_absorption_table,
    spectroscopy_line_list,
    spectroscopy_strong_line_set,
    spectroscopy_relaxation_matrix,
    lookup_table,
    mie_phase_table,
};

pub const EmbeddedAsset = struct {
    path: []const u8,
    contents: []const u8,
};
