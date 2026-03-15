const std = @import("std");
const DynLib = @import("../loader/dynlib.zig");
const Manifest = @import("../loader/manifest.zig");
const Instruments = @import("instruments/root.zig");
const Retrieval = @import("retrieval/root.zig");
const Surfaces = @import("surfaces/root.zig");
const Transport = @import("transport/root.zig");

pub const builtin_manifests = [_]Manifest.PluginManifest{
    Transport.transport_dispatcher_manifest,
    Retrieval.oe_solver_manifest,
    Surfaces.lambertian_surface_manifest,
    Instruments.tropomi_response_manifest,
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
    if (std.mem.eql(u8, manifest_id, Instruments.tropomi_response_manifest.id)) {
        return Instruments.staticSymbols();
    }
    return null;
}

test "builtin native families publish transport retrieval surface and instrument packs" {
    try std.testing.expectEqual(@as(usize, 4), builtin_manifests.len);
    try std.testing.expect(staticSymbolsFor("builtin.transport_dispatcher") != null);
    try std.testing.expect(staticSymbolsFor("builtin.oe_solver") != null);
    try std.testing.expect(staticSymbolsFor("builtin.lambertian_surface") != null);
    try std.testing.expect(staticSymbolsFor("builtin.tropomi_response") != null);
}
