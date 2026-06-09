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
