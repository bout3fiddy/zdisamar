const std = @import("std");

const layer_depths = @import("../optics/layer_depths.zig");
const o2_case = @import("../input/o2_case.zig");
const atmosphere_layers = @import("../setup/atmosphere_layers.zig");
const o2_run_tables = @import("../setup/o2_run_tables.zig");
const profile_line_memory = @import("../cache/profile_line_memory.zig");

const Allocator = std.mem.Allocator;

// atmospheric_budget.zig -------------------------------------------------------------------------------------|
// Public atmospheric support-row diagnostic table for the explicit O2 A route.                                |
//                                                                                                             |
// boundary                                                                                                    |
//   The builder projects existing setup/profile-line/optics rows into the fixed Python C ABI row order. It    |
//   does not parse inputs, own API handles, or enter transport.                                               |
//                                                                                                             |
//   public table exposes support-row optical-depth components at requested diagnostic wavelengths.            |
// ------------------------------------------------------------------------------------------------------------|

const support_row_kind_boundary: u32 = 1;
const support_row_kind_active: u32 = 2;

const SupportBounds = struct {
    top_altitude_km: f64,
    bottom_altitude_km: f64,
    top_pressure_hpa: f64,
    bottom_pressure_hpa: f64,
};

// AtmosphericBudgetRow ---------------------------------------------------------------------------------------|
// One public support-row diagnostic record for one wavelength.                                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 208 B (0.203 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] wavelength_nm                    : f64                                                           |
// [  8.. 11] layer_index                      : u32                                                           |
// [ 12.. 15] sublayer_index                   : u32                                                           |
// [ 16.. 19] global_sublayer_index            : u32                                                           |
// [ 20.. 23] interval_index_1based            : u32                                                           |
// [ 24.. 27] support_row_kind                 : u32                                                           |
// [ 28.. 31] padding                          : 4 B                                                           |
// [ 32.. 39] altitude_km                      : f64                                                           |
// [ 40.. 47] top_altitude_km                  : f64                                                           |
// [ 48.. 55] bottom_altitude_km               : f64                                                           |
// [ 56.. 63] pressure_hpa                     : f64                                                           |
// [ 64.. 71] top_pressure_hpa                 : f64                                                           |
// [ 72.. 79] bottom_pressure_hpa              : f64                                                           |
// [ 80.. 87] temperature_k                    : f64                                                           |
// [ 88.. 95] number_density_cm3               : f64                                                           |
// [ 96..103] oxygen_number_density_cm3        : f64                                                           |
// [104..111] absorber_number_density_cm3      : f64                                                           |
// [112..119] path_length_cm                   : f64                                                           |
// [120..127] aerosol_fraction                 : f64                                                           |
// [128..135] gas_absorption_optical_depth     : f64                                                           |
// [136..143] gas_scattering_optical_depth     : f64                                                           |
// [144..151] cia_optical_depth                : f64                                                           |
// [152..159] aerosol_optical_depth            : f64                                                           |
// [160..167] aerosol_scattering_optical_depth : f64                                                           |
// [168..175] aerosol_absorption_optical_depth : f64                                                           |
// [176..183] total_absorption_optical_depth   : f64                                                           |
// [184..191] total_scattering_optical_depth   : f64                                                           |
// [192..199] total_optical_depth              : f64                                                           |
// [200..207] single_scatter_albedo            : f64                                                           |
pub const AtmosphericBudgetRow = extern struct {
    wavelength_nm: f64,
    layer_index: u32,
    sublayer_index: u32,
    global_sublayer_index: u32,
    interval_index_1based: u32,
    support_row_kind: u32,
    altitude_km: f64,
    top_altitude_km: f64,
    bottom_altitude_km: f64,
    pressure_hpa: f64,
    top_pressure_hpa: f64,
    bottom_pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    oxygen_number_density_cm3: f64,
    absorber_number_density_cm3: f64,
    path_length_cm: f64,
    aerosol_fraction: f64,
    gas_absorption_optical_depth: f64,
    gas_scattering_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    aerosol_scattering_optical_depth: f64,
    aerosol_absorption_optical_depth: f64,
    total_absorption_optical_depth: f64,
    total_scattering_optical_depth: f64,
    total_optical_depth: f64,
    single_scatter_albedo: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// AtmosphericBudget ------------------------------------------------------------------------------------------|
// Owned atmospheric-budget row table returned through root/API calls.                                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0..15] rows : []AtmosphericBudgetRow                                                                       |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows owns wavelength_count * support_row_count records in wavelength-major order.                         |
pub const AtmosphericBudget = struct {
    rows: []AtmosphericBudgetRow = &.{},

    pub fn deinit(self: *AtmosphericBudget, allocator: Allocator) void {
        // AtmosphericBudget.deinit ---------------------------------------------------------------------------|
        // Release the owned diagnostic row table.                                                             |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.rows);
        self.* = .{};
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn build(
    allocator: Allocator,
    case: o2_case.O2Case,
    tables: *const o2_run_tables.O2RunTables,
    wavelengths_nm: []const f64,
) !AtmosphericBudget {
    // build --------------------------------------------------------------------------------------------------|
    // Build the public atmospheric-budget table for caller-selected diagnostic wavelengths.                   |
    //                                                                                                         |
    // memory                                                                                                  |
    //   Allocates one output row table, one temporary profile-line table for requested wavelengths, and two   |
    //   support-row work slices reused across wavelengths.                                                    |
    // --------------------------------------------------------------------------------------------------------|
    const support_count = tables.layers.support_mid_altitudes_km.len;
    const row_count = try std.math.mul(usize, wavelengths_nm.len, support_count);
    const rows = try allocator.alloc(AtmosphericBudgetRow, row_count);
    errdefer allocator.free(rows);

    var profile_values = try profile_line_memory.buildO2ProfileLineValuesForWavelengths(
        allocator,
        case,
        wavelengths_nm,
    );
    defer profile_values.deinit(allocator);

    const support_sigma = try allocator.alloc(f64, support_count);
    defer allocator.free(support_sigma);
    const support_optics = try allocator.alloc(layer_depths.SupportOptics, support_count);
    defer allocator.free(support_optics);

    for (wavelengths_nm, 0..) |wavelength_nm, wavelength_index| {
        try profile_values.fillSupportLineSigmaAtWavelengthIndex(
            tables.layers,
            wavelength_index,
            support_sigma,
        );
        try layer_depths.fillSupportOpticsAtWavelength(
            wavelength_nm,
            tables.layers,
            support_sigma,
            tables.cia,
            tables.aerosol,
            support_optics,
        );

        const row_start = wavelength_index * support_count;
        for (support_optics, 0..) |support, support_index| {
            rows[row_start + support_index] = rowFromSupport(tables.layers, support, support_index);
        }
    }

    return .{ .rows = rows };
}

fn rowFromSupport(
    layers: atmosphere_layers.LayerGrid,
    support: layer_depths.SupportOptics,
    support_index: usize,
) AtmosphericBudgetRow {
    // rowFromSupport -----------------------------------------------------------------------------------------|
    // Project one support-row optics record into the fixed public diagnostic row order.                       |
    // --------------------------------------------------------------------------------------------------------|
    const layer_index = supportLayerIndex(layers, support_index);
    const boundary = layers.support_path_lengths_cm[support_index] == 0.0;
    const bounds = supportBounds(layers, layer_index, support_index, boundary);
    const support_row_kind = if (boundary)
        support_row_kind_boundary
    else
        support_row_kind_active;
    const aerosol_absorption = @max(
        support.aerosol_optical_depth - support.aerosol_scattering_optical_depth,
        0.0,
    );

    return .{
        .wavelength_nm = support.wavelength_nm,
        .layer_index = 0,
        .sublayer_index = 0,
        .global_sublayer_index = @intCast(support_index),
        .interval_index_1based = support.interval_index_1based,
        .support_row_kind = support_row_kind,
        .altitude_km = layers.support_mid_altitudes_km[support_index],
        .top_altitude_km = bounds.top_altitude_km,
        .bottom_altitude_km = bounds.bottom_altitude_km,
        .pressure_hpa = layers.support_pressures_hpa[support_index],
        .top_pressure_hpa = bounds.top_pressure_hpa,
        .bottom_pressure_hpa = bounds.bottom_pressure_hpa,
        .temperature_k = layers.support_temperatures_k[support_index],
        .number_density_cm3 = layers.support_air_number_densities_cm3[support_index],
        .oxygen_number_density_cm3 = layers.support_o2_number_densities_cm3[support_index],
        .absorber_number_density_cm3 = layers.support_o2_number_densities_cm3[support_index],
        .path_length_cm = layers.support_path_lengths_cm[support_index],
        .aerosol_fraction = 0.0,
        .gas_absorption_optical_depth = support.gas_absorption_optical_depth,
        .gas_scattering_optical_depth = support.gas_scattering_optical_depth,
        .cia_optical_depth = support.cia_optical_depth,
        .aerosol_optical_depth = support.aerosol_optical_depth,
        .aerosol_scattering_optical_depth = support.aerosol_scattering_optical_depth,
        .aerosol_absorption_optical_depth = aerosol_absorption,
        .total_absorption_optical_depth = support.gas_absorption_optical_depth +
            support.cia_optical_depth +
            aerosol_absorption,
        .total_scattering_optical_depth = support.total_scattering_optical_depth,
        .total_optical_depth = support.total_optical_depth,
        .single_scatter_albedo = support.single_scatter_albedo,
    };
}

fn supportBounds(
    layers: atmosphere_layers.LayerGrid,
    layer_index: usize,
    support_index: usize,
    boundary: bool,
) SupportBounds {
    // supportBounds ------------------------------------------------------------------------------------------|
    // Select public top/bottom geometry for active layer rows and zero-path boundary rows.                    |
    // --------------------------------------------------------------------------------------------------------|
    if (!boundary) {
        return .{
            .top_altitude_km = layers.layer_top_altitudes_km[layer_index],
            .bottom_altitude_km = layers.layer_bottom_altitudes_km[layer_index],
            .top_pressure_hpa = layers.layer_top_pressures_hpa[layer_index],
            .bottom_pressure_hpa = layers.layer_bottom_pressures_hpa[layer_index],
        };
    }

    const pressure_hpa = boundaryPressureHpa(layers, layer_index, support_index);
    return .{
        .top_altitude_km = layers.support_mid_altitudes_km[support_index],
        .bottom_altitude_km = layers.support_mid_altitudes_km[support_index],
        .top_pressure_hpa = pressure_hpa,
        .bottom_pressure_hpa = pressure_hpa,
    };
}

fn boundaryPressureHpa(layers: atmosphere_layers.LayerGrid, layer_index: usize, support_index: usize) f64 {
    // boundaryPressureHpa ------------------------------------------------------------------------------------|
    // Public diagnostics keep representative pressure in pressure_hpa, but top/bottom pressure on zero-path   |
    // support rows comes from the layer-boundary pressure field. Surface/top endpoints therefore keep         |
    // configured interval bounds even when the interpolated support pressure differs by a few bits.           |
    // --------------------------------------------------------------------------------------------------------|
    const layer_start: usize = @intCast(layers.layer_support_starts[layer_index]);
    const layer_count: usize = @intCast(layers.layer_support_counts[layer_index]);
    if (support_index == layer_start) return layers.layer_bottom_pressures_hpa[layer_index];
    if (support_index + 1 == layer_start + layer_count) return layers.layer_top_pressures_hpa[layer_index];
    return layers.support_pressures_hpa[support_index];
}

fn supportLayerIndex(layers: atmosphere_layers.LayerGrid, support_index: usize) usize {
    // supportLayerIndex --------------------------------------------------------------------------------------|
    // Find the layer whose support window owns a support row.                                                 |
    // --------------------------------------------------------------------------------------------------------|
    for (layers.layer_support_starts, layers.layer_support_counts, 0..) |start_raw, count_raw, layer_index| {
        const start: usize = @intCast(start_raw);
        const count: usize = @intCast(count_raw);
        if (support_index >= start and support_index < start + count) return layer_index;
    }
    return 0;
}

comptime {
    std.debug.assert(@sizeOf(AtmosphericBudgetRow) == 208);
    std.debug.assert(@sizeOf(AtmosphericBudget) == 16);
}
