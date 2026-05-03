const std = @import("std");
const atmospheric_budget = @import("atmospheric_budget.zig");
const Optics = @import("../forward_model/optical_properties/root.zig");
const Scene = @import("../input/Scene.zig").Scene;

const Allocator = std.mem.Allocator;
const PreparedOpticalState = Optics.PreparedOpticalState;

pub const O2O2CIARow = struct {
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

pub fn build(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    wavelengths_nm: []const f64,
) ![]O2O2CIARow {
    const budget = try atmospheric_budget.build(allocator, scene, prepared, wavelengths_nm);
    defer allocator.free(budget);

    const rows = try allocator.alloc(O2O2CIARow, budget.len);
    errdefer allocator.free(rows);
    for (budget, rows) |source, *target| target.* = rowFromBudget(source);
    return rows;
}

fn rowFromBudget(row: atmospheric_budget.AtmosphericBudgetRow) O2O2CIARow {
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
    if (denominator <= 0.0 or !std.math.isFinite(denominator)) return 0.0;
    return numerator / denominator;
}
