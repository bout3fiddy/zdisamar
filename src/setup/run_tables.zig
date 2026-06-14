const std = @import("std");

const validate = @import("../input/validate.zig");
const scene_input = @import("../input/scene.zig");
const aerosol_tables = @import("aerosol_tables.zig");
const atmosphere_layers = @import("atmosphere_layers.zig");
const cia_table = @import("cia_table.zig");
const instrument_tables = @import("instrument_tables.zig");
const line_tables = @import("line_tables.zig");
const phase_table = @import("phase_table.zig");
const solar_table = @import("solar_table.zig");

const Allocator = std.mem.Allocator;

// RunTables --------------------------------------------------------------------------------------------------|
// Package boundary for setup tables below radiance math.                                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 2016 B (1.969 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0.. 391] layers    : LayerGrid                                                                          |
// [ 392.. 479] quadrature: LayerQuadrature                                                                    |
// [ 480.. 591] lines     : LineTable                                                                          |
// [ 592.. 615] cia       : CiaTable                                                                           |
// [ 616.. 695] aerosol   : AerosolLayerTable                                                                  |
// [ 696..1919] phase     : PhaseTable                                                                         |
// [1920..1983] instrument: InstrumentTable                                                                    |
// [1984..2015] solar     : SolarTable                                                                         |
//                                                                                                             |
// boundary                                                                                                    |
//   This owner groups table families only for top-level setup/run functions. Later optics/transport code      |
//   must receive the narrow table slices it needs rather than this full bundle.                               |
//                                                                                                             |
// ownership                                                                                                   |
//   layers, quadrature, lines, cia, and solar own out-of-line arrays. Aerosol, phase, and instrument tables   |
//   are inline scalar/control rows.                                                                           |
pub const RunTables = struct {
    layers: atmosphere_layers.LayerGrid,
    quadrature: atmosphere_layers.LayerQuadrature,
    lines: line_tables.LineTable,
    cia: cia_table.CiaTable,
    aerosol: aerosol_tables.AerosolLayerTable,
    phase: phase_table.PhaseTable,
    instrument: instrument_tables.InstrumentTable,
    solar: solar_table.SolarTable,

    pub fn deinit(self: *RunTables, allocator: Allocator) void {
        // RunTables.deinit -----------------------------------------------------------------------------------|
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

pub fn buildRunTables(allocator: Allocator, scene: scene_input.Scene) !RunTables {
    // buildRunTables -----------------------------------------------------------------------------------------|
    // Validate the O2 A case and build every physical setup table.                                            |
    // --------------------------------------------------------------------------------------------------------|
    try validate.sceneControls(scene);

    var quadrature = try atmosphere_layers.buildLayerQuadrature(allocator, scene);
    errdefer quadrature.deinit(allocator);
    var layers = try atmosphere_layers.buildWithQuadrature(allocator, scene, quadrature);
    errdefer layers.deinit(allocator);
    var lines = try line_tables.build(allocator, scene);
    errdefer lines.deinit(allocator);
    var cia = try cia_table.build(allocator, scene);
    errdefer cia.deinit(allocator);
    var solar = try solar_table.build(allocator, scene);
    errdefer solar.deinit(allocator);

    return .{
        .layers = layers,
        .quadrature = quadrature,
        .lines = lines,
        .cia = cia,
        .aerosol = aerosol_tables.build(scene),
        .phase = phase_table.build(scene),
        .instrument = instrument_tables.build(scene),
        .solar = solar,
    };
}
