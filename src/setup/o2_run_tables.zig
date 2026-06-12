const std = @import("std");

const validate = @import("../input/validate.zig");
const o2_case = @import("../input/o2_case.zig");
const aerosol_tables = @import("aerosol_tables.zig");
const atmosphere_layers = @import("atmosphere_layers.zig");
const cia_table = @import("cia_table.zig");
const instrument_tables = @import("instrument_tables.zig");
const line_tables = @import("line_tables.zig");
const phase_table = @import("phase_table.zig");
const solar_table = @import("solar_table.zig");

const Allocator = std.mem.Allocator;

// O2RunTables ------------------------------------------------------------------------------------------------|
// Package boundary for setup tables below radiance math.                                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 1904 B (1.859 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0.. 383] layers    : LayerGrid                                                                          |
// [ 384.. 495] lines     : O2LineTable                                                                        |
// [ 496.. 519] cia       : O2CiaTable                                                                         |
// [ 520.. 583] aerosol   : AerosolLayerTable                                                                  |
// [ 584..1807] phase     : PhaseTable                                                                         |
// [1808..1871] instrument: InstrumentTable                                                                    |
// [1872..1903] solar     : SolarTable                                                                         |
//                                                                                                             |
// boundary                                                                                                    |
//   This owner groups table families only for top-level setup/run functions. Later optics/transport code      |
//   must receive the narrow table slices it needs rather than this full bundle.                               |
//                                                                                                             |
// ownership                                                                                                   |
//   layers, lines, cia, and solar own out-of-line arrays. Aerosol, phase, and instrument tables are inline    |
//   scalar/control rows.                                                                                      |
pub const O2RunTables = struct {
    layers: atmosphere_layers.LayerGrid,
    lines: line_tables.O2LineTable,
    cia: cia_table.O2CiaTable,
    aerosol: aerosol_tables.AerosolLayerTable,
    phase: phase_table.PhaseTable,
    instrument: instrument_tables.InstrumentTable,
    solar: solar_table.SolarTable,

    pub fn deinit(self: *O2RunTables, allocator: Allocator) void {
        // O2RunTables.deinit ---------------------------------------------------------------------------------|
        // Release owned child tables in reverse setup order.                                                  |
        // ----------------------------------------------------------------------------------------------------|
        self.solar.deinit(allocator);
        self.cia.deinit(allocator);
        self.lines.deinit(allocator);
        self.layers.deinit(allocator);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn buildReferenceO2RunTables(allocator: Allocator, case: o2_case.O2Case) !O2RunTables {
    // buildReferenceO2RunTables ------------------------------------------------------------------------------|
    // Validate the reference case and build every WP2 physical setup table.                                   |
    // --------------------------------------------------------------------------------------------------------|
    try validate.referenceCase(case);

    var layers = try atmosphere_layers.build(allocator, case);
    errdefer layers.deinit(allocator);
    var lines = try line_tables.build(allocator, case);
    errdefer lines.deinit(allocator);
    var cia = try cia_table.build(allocator, case);
    errdefer cia.deinit(allocator);
    var solar = try solar_table.build(allocator, case);
    errdefer solar.deinit(allocator);

    return .{
        .layers = layers,
        .lines = lines,
        .cia = cia,
        .aerosol = aerosol_tables.build(case),
        .phase = phase_table.build(case),
        .instrument = instrument_tables.build(case),
        .solar = solar,
    };
}
