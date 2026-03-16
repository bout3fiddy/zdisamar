const diagnostics = @import("diagnostics.zig");
const exporter = @import("exporter.zig");
const instrument = @import("instrument.zig");
const noise = @import("noise.zig");
const optics = @import("optics.zig");
const retrieval = @import("retrieval.zig");
const selection = @import("../selection.zig");
const surface = @import("surface.zig");
const transport = @import("transport.zig");

pub const PreparedProviders = struct {
    optics: optics.Provider = undefined,
    transport: transport.Provider = undefined,
    surface: surface.Provider = undefined,
    instrument: instrument.Provider = undefined,
    noise: noise.Provider = undefined,
    diagnostics: diagnostics.Provider = undefined,
    retrieval: ?retrieval.Provider = null,

    pub fn resolve(provider_selection: selection.ProviderSelection) Error!PreparedProviders {
        return .{
            .optics = optics.resolve(provider_selection.absorber_provider) orelse return error.UnknownOpticsProvider,
            .transport = transport.resolve(provider_selection.transport_solver) orelse return error.UnknownTransportProvider,
            .surface = surface.resolve(provider_selection.surface_model) orelse return error.UnknownSurfaceProvider,
            .instrument = instrument.resolve(provider_selection.instrument_response) orelse return error.UnknownInstrumentProvider,
            .noise = noise.resolve(provider_selection.noise_model) orelse return error.UnknownNoiseProvider,
            .diagnostics = diagnostics.resolve(provider_selection.diagnostics_metric) orelse return error.UnknownDiagnosticsProvider,
            .retrieval = if (provider_selection.retrieval_algorithm) |provider_id|
                retrieval.resolve(provider_id) orelse return error.UnknownRetrievalProvider
            else
                null,
        };
    }
};

pub const Transport = transport;
pub const Optics = optics;
pub const Surface = surface;
pub const Instrument = instrument;
pub const Noise = noise;
pub const Diagnostics = diagnostics;
pub const Exporter = exporter;
pub const Retrieval = retrieval;

pub const Error = error{
    UnknownOpticsProvider,
    UnknownTransportProvider,
    UnknownSurfaceProvider,
    UnknownInstrumentProvider,
    UnknownNoiseProvider,
    UnknownDiagnosticsProvider,
    UnknownRetrievalProvider,
};

test "prepared providers resolve builtin execution stack" {
    const resolved = try PreparedProviders.resolve(.{ .retrieval_algorithm = "builtin.oe_solver" });
    try std.testing.expectEqualStrings("builtin.cross_sections", resolved.optics.id);
    try std.testing.expectEqualStrings("builtin.dispatcher", resolved.transport.id);
    try std.testing.expectEqualStrings("builtin.lambertian_surface", resolved.surface.id);
    try std.testing.expectEqualStrings("builtin.generic_response", resolved.instrument.id);
    try std.testing.expectEqualStrings("builtin.scene_noise", resolved.noise.id);
    try std.testing.expectEqualStrings("builtin.default_diagnostics", resolved.diagnostics.id);
    try std.testing.expectEqualStrings("builtin.oe_solver", resolved.retrieval.?.id);
}

const std = @import("std");
