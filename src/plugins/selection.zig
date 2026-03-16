pub const ProviderSelection = struct {
    absorber_provider: []const u8 = "builtin.cross_sections",
    transport_solver: []const u8 = "builtin.dispatcher",
    retrieval_algorithm: ?[]const u8 = null,
    surface_model: []const u8 = "builtin.lambertian_surface",
    instrument_response: []const u8 = "builtin.generic_response",
    noise_model: []const u8 = "builtin.scene_noise",
    diagnostics_metric: []const u8 = "builtin.default_diagnostics",
};
