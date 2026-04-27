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
