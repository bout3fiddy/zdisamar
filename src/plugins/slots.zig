pub const absorber_provider = "absorber.provider";
pub const transport_solver = "transport.solver";
pub const retrieval_algorithm = "retrieval.algorithm";
pub const surface_model = "surface.model";
pub const instrument_response = "instrument.response";
pub const noise_model = "noise.model";
pub const diagnostics_metric = "diagnostics.metric";
pub const data_pack = "data.pack";
pub const exporter = "exporter";

pub const known_slots = [_][]const u8{
    absorber_provider,
    transport_solver,
    retrieval_algorithm,
    surface_model,
    instrument_response,
    noise_model,
    diagnostics_metric,
    data_pack,
    exporter,
};

pub fn isKnown(slot: []const u8) bool {
    inline for (known_slots) |candidate| {
        if (std.mem.eql(u8, slot, candidate)) return true;
    }
    return false;
}

const std = @import("std");
