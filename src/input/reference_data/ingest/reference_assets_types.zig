// reference_assets_types.zig ---------------------------------------------------------------------------------|
// Shared manifest-level reference-asset tags and embedded-byte views.                                         |
//                                                                                                             |
// called by                                                                                                   |
//   reference_assets.zig re-exports these names for bundled, embedded, and external asset loading.            |
//   reference_assets_loaded_asset.zig stores AssetKind on ParsedTable output before typed conversion.         |
//   bundled/assets.zig passes EmbeddedAsset rows for compile-time embedded O2 A reference tables.             |
//                                                                                                             |
// asset kind map                                                                                              |
//   climatology_profile                    -> atmospheric profile rows                                        |
//   cross_section_table / lookup_table     -> absorber xsec tables and generated/consumed LUT inputs          |
//   collision_induced_absorption_table     -> O2-O2 CIA polynomial rows                                       |
//   spectroscopy_line_list/strong_line_set -> HITRAN/LISA line and strong-line support                        |
//   spectroscopy_relaxation_matrix         -> LISA relaxation-matrix sidecar                                  |
//                                                                                                             |
// embedded asset shape                                                                                        |
//   EmbeddedAsset.path is the manifest path key. EmbeddedAsset.contents is the byte slice produced by         |
//   @embedFile. Both slices borrow binary-image storage; loaders must not free or mutate them.                |
//                                                                                                             |
// boundary                                                                                                    |
//   This file performs no parsing, allocation, hashing, or typed conversion. It only names the dispatch       |
//   categories used by the ingest layer so forward-model code receives typed ReferenceData owners later.      |
//                                                                                                             |
// memory                                                                                                      |
//   AssetKind is an enum tag. EmbeddedAsset is two borrowed slices, 32 B on 64-bit targets, with no owner     |
//   state and no deinit path.                                                                                 |
// ------------------------------------------------------------------------------------------------------------|

pub const AssetKind = enum {
    climatology_profile,
    cross_section_table,
    collision_induced_absorption_table,
    spectroscopy_line_list,
    spectroscopy_strong_line_set,
    spectroscopy_relaxation_matrix,
    lookup_table,
};

// EmbeddedAsset ----------------------------------------------------------------------------------------------|
// One compile-time embedded asset used by bundle loaders.                                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] path     : []const u8                                                                              |
// [16..31] contents : []const u8                                                                              |
//                                                                                                             |
// referenced storage                                                                                          |
//   path and contents point at embedded byte strings; referenced storage is not included in this row.         |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 32 B (0.031 KiB); total also includes embedded byte storage                       |
pub const EmbeddedAsset = struct {
    path: []const u8,
    contents: []const u8,
};
// ------------------------------------------------------------------------------------------------------------|
