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
// size: 2024 B (1.977 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0.. 399] layers    : LayerGrid                                                                          |
// [ 400.. 487] quadrature: LayerQuadrature                                                                    |
// [ 488.. 599] lines     : O2LineTable                                                                        |
// [ 600.. 623] cia       : O2CiaTable                                                                         |
// [ 624.. 703] aerosol   : AerosolLayerTable                                                                  |
// [ 704..1927] phase     : PhaseTable                                                                         |
// [1928..1991] instrument: InstrumentTable                                                                    |
// [1992..2023] solar     : SolarTable                                                                         |
//                                                                                                             |
// boundary                                                                                                    |
//   This owner groups table families only for top-level setup/run functions. Later optics/transport code      |
//   must receive the narrow table slices it needs rather than this full bundle.                               |
//                                                                                                             |
// ownership                                                                                                   |
//   layers, quadrature, lines, cia, and solar own out-of-line arrays. Aerosol, phase, and instrument tables  |
//   are inline scalar/control rows.                                                                           |
pub const O2RunTables = struct {
    layers: atmosphere_layers.LayerGrid,
    quadrature: atmosphere_layers.LayerQuadrature,
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
        self.quadrature.deinit(allocator);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn buildO2RunTables(allocator: Allocator, case: o2_case.O2Case) !O2RunTables {
    // buildO2RunTables ---------------------------------------------------------------------------------------|
    // Validate the O2 A case and build every physical setup table.                                            |
    // --------------------------------------------------------------------------------------------------------|
    try validate.o2Case(case);

    var quadrature = try atmosphere_layers.buildLayerQuadrature(allocator, case);
    errdefer quadrature.deinit(allocator);
    var layers = try atmosphere_layers.buildWithQuadrature(allocator, case, quadrature);
    errdefer layers.deinit(allocator);
    var lines = try line_tables.build(allocator, case);
    errdefer lines.deinit(allocator);
    var cia = try cia_table.build(allocator, case);
    errdefer cia.deinit(allocator);
    var solar = try solar_table.build(allocator, case);
    errdefer solar.deinit(allocator);

    return .{
        .layers = layers,
        .quadrature = quadrature,
        .lines = lines,
        .cia = cia,
        .aerosol = aerosol_tables.build(case),
        .phase = phase_table.build(case),
        .instrument = instrument_tables.build(case),
        .solar = solar,
    };
}
