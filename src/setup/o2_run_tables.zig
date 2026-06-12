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
// size: 1920 B (1.875 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0.. 399] layers    : LayerGrid                                                                          |
// [ 400.. 511] lines     : O2LineTable                                                                        |
// [ 512.. 535] cia       : O2CiaTable                                                                         |
// [ 536.. 599] aerosol   : AerosolLayerTable                                                                  |
// [ 600..1823] phase     : PhaseTable                                                                         |
// [1824..1887] instrument: InstrumentTable                                                                    |
// [1888..1919] solar     : SolarTable                                                                         |
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
