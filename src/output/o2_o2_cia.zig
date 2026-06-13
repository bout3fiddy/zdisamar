const std = @import("std");

const atmospheric_budget = @import("atmospheric_budget.zig");

const Allocator = std.mem.Allocator;

// o2_o2_cia.zig ----------------------------------------------------------------------------------------------|
// O2-O2 collision-induced absorption diagnostic rows for the explicit O2 A route.                             |
//                                                                                                             |
// boundary                                                                                                    |
//   The builder projects the already-public atmospheric-budget rows into the fixed Python C ABI row order.    |
//   It does not parse inputs, own C handles, or call transport.                                               |
//                                                                                                             |
//   the CIA-focused table and budget table keep identical wavelength/support-row ordering.                    |
//                                                                                                             |
// math                                                                                                        |
//   pair path         = oxygen_number_density_cm3^2 * path_length_cm                                          |
//   CIA cross section = cia_optical_depth / pair path                                                         |
//   CIA share         = cia_optical_depth / total absorption or total optical depth                           |
//                                                                                                             |
// memory                                                                                                      |
//   `build` allocates one output row table and frees the temporary atmospheric-budget owner before returning. |
// ------------------------------------------------------------------------------------------------------------|

// O2O2CIARow -------------------------------------------------------------------------------------------------|
// One public O2-O2 CIA diagnostic row for one wavelength and support row.                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 112 B (0.109 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] wavelength_nm                      : f64                                                         |
// [  8.. 11] layer_index                        : u32                                                         |
// [ 12.. 15] sublayer_index                     : u32                                                         |
// [ 16.. 19] global_sublayer_index              : u32                                                         |
// [ 20.. 23] interval_index_1based              : u32                                                         |
// [ 24.. 31] altitude_km                        : f64                                                         |
// [ 32.. 39] pressure_hpa                       : f64                                                         |
// [ 40.. 47] temperature_k                      : f64                                                         |
// [ 48.. 55] oxygen_number_density_cm3          : f64                                                         |
// [ 56.. 63] path_length_cm                     : f64                                                         |
// [ 64.. 71] cia_cross_section_cm5_per_molecule2: f64                                                         |
// [ 72.. 79] cia_optical_depth                  : f64                                                         |
// [ 80.. 87] total_absorption_optical_depth     : f64                                                         |
// [ 88.. 95] total_optical_depth                : f64                                                         |
// [ 96..103] cia_share_of_total_absorption      : f64                                                         |
// [104..111] cia_share_of_total_optical_depth   : f64                                                         |
pub const O2O2CIARow = extern struct {
    wavelength_nm: f64,
    layer_index: u32,
    sublayer_index: u32,
    global_sublayer_index: u32,
    interval_index_1based: u32,
    altitude_km: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    oxygen_number_density_cm3: f64,
    path_length_cm: f64,
    cia_cross_section_cm5_per_molecule2: f64,
    cia_optical_depth: f64,
    total_absorption_optical_depth: f64,
    total_optical_depth: f64,
    cia_share_of_total_absorption: f64,
    cia_share_of_total_optical_depth: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// O2O2CIADiagnostics -----------------------------------------------------------------------------------------|
// Owned O2-O2 CIA diagnostic table returned through root/API calls.                                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0..15] rows : []O2O2CIARow                                                                                 |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows owns wavelength_count * support_row_count records in wavelength-major order.                         |
pub const O2O2CIADiagnostics = struct {
    rows: []O2O2CIARow = &.{},

    pub fn deinit(self: *O2O2CIADiagnostics, allocator: Allocator) void {
        // O2O2CIADiagnostics.deinit --------------------------------------------------------------------------|
        // Release the owned CIA diagnostic row table.                                                         |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.rows);
        self.* = .{};
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn build(
    allocator: Allocator,
    budget: atmospheric_budget.AtmosphericBudget,
) !O2O2CIADiagnostics {
    // build --------------------------------------------------------------------------------------------------|
    // Build CIA-focused rows from an atmospheric-budget table with the same row order.                        |
    // --------------------------------------------------------------------------------------------------------|
    const rows = try allocator.alloc(O2O2CIARow, budget.rows.len);
    errdefer allocator.free(rows);

    for (budget.rows, rows) |source, *target| {
        target.* = rowFromBudget(source);
    }

    return .{ .rows = rows };
}

fn rowFromBudget(row: atmospheric_budget.AtmosphericBudgetRow) O2O2CIARow {
    // rowFromBudget ------------------------------------------------------------------------------------------|
    // Derive the public CIA-focused columns from one atmospheric-budget row.                                  |
    // --------------------------------------------------------------------------------------------------------|
    const pair_path = row.oxygen_number_density_cm3 * row.oxygen_number_density_cm3 * row.path_length_cm;

    return .{
        .wavelength_nm = row.wavelength_nm,
        .layer_index = row.layer_index,
        .sublayer_index = row.sublayer_index,
        .global_sublayer_index = row.global_sublayer_index,
        .interval_index_1based = row.interval_index_1based,
        .altitude_km = row.altitude_km,
        .pressure_hpa = row.pressure_hpa,
        .temperature_k = row.temperature_k,
        .oxygen_number_density_cm3 = row.oxygen_number_density_cm3,
        .path_length_cm = row.path_length_cm,
        .cia_cross_section_cm5_per_molecule2 = safeDivide(row.cia_optical_depth, pair_path),
        .cia_optical_depth = row.cia_optical_depth,
        .total_absorption_optical_depth = row.total_absorption_optical_depth,
        .total_optical_depth = row.total_optical_depth,
        .cia_share_of_total_absorption = safeDivide(row.cia_optical_depth, row.total_absorption_optical_depth),
        .cia_share_of_total_optical_depth = safeDivide(row.cia_optical_depth, row.total_optical_depth),
    };
}

fn safeDivide(numerator: f64, denominator: f64) f64 {
    // safeDivide ---------------------------------------------------------------------------------------------|
    // Keep diagnostics finite on zero-path boundary rows and malformed denominator guards.                    |
    // --------------------------------------------------------------------------------------------------------|
    if (denominator <= 0.0 or !std.math.isFinite(denominator)) return 0.0;
    return numerator / denominator;
}

comptime {
    std.debug.assert(@sizeOf(O2O2CIARow) == 112);
    std.debug.assert(@sizeOf(O2O2CIADiagnostics) == 16);
}
