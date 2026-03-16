const std = @import("std");
const DynLib = @import("../loader/dynlib.zig");
const Manifest = @import("../loader/manifest.zig");
const Diagnostics = @import("diagnostics/root.zig");
const Exporters = @import("exporters/root.zig");
const Instruments = @import("instruments/root.zig");
const Noise = @import("noise/root.zig");
const Reference = @import("reference/root.zig");
const Retrieval = @import("retrieval/root.zig");
const Surfaces = @import("surfaces/root.zig");
const Transport = @import("transport/root.zig");

pub const execution_manifests = [_]Manifest.PluginManifest{
    Reference.cross_sections_manifest,
    Transport.transport_dispatcher_manifest,
    Retrieval.oe_solver_manifest,
    Retrieval.doas_solver_manifest,
    Retrieval.dismas_solver_manifest,
    Surfaces.lambertian_surface_manifest,
    Instruments.generic_response_manifest,
    Noise.scene_noise_manifest,
    Noise.none_noise_manifest,
    Noise.shot_noise_manifest,
    Noise.s5p_operational_noise_manifest,
    Diagnostics.default_diagnostics_manifest,
    Exporters.netcdf_cf_manifest,
    Exporters.zarr_manifest,
};

pub fn staticSymbolsFor(manifest_id: []const u8) ?[]const DynLib.SymbolEntry {
    if (std.mem.eql(u8, manifest_id, Transport.transport_dispatcher_manifest.id)) {
        return Transport.staticSymbols();
    }
    if (std.mem.eql(u8, manifest_id, Retrieval.oe_solver_manifest.id)) {
        return Retrieval.staticSymbols();
    }
    if (std.mem.eql(u8, manifest_id, Surfaces.lambertian_surface_manifest.id)) {
        return Surfaces.staticSymbols();
    }
    return null;
}

test "builtin native families publish transport retrieval and surface packs" {
    try std.testing.expect(execution_manifests.len >= 7);
    try std.testing.expect(staticSymbolsFor("builtin.transport_dispatcher") != null);
    try std.testing.expect(staticSymbolsFor("builtin.oe_solver") != null);
    try std.testing.expect(staticSymbolsFor("builtin.lambertian_surface") != null);
}
