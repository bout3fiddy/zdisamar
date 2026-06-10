const std = @import("std");
const Scene = @import("../input/Scene.zig").Scene;
const Optics = @import("../forward_model/optical_properties/root.zig");
const Rayleigh = @import("../input/reference/rayleigh.zig");
const Spectroscopy = @import("../forward_model/optical_properties/state_build/state_spectroscopy.zig");
const StateTypes = @import("../forward_model/optical_properties/state_build/state.zig");

const Allocator = std.mem.Allocator;
const OpticalDepthBreakdown = Optics.OpticalDepthBreakdown;
const PreparedLayer = Optics.PreparedLayer;
const PreparedOpticalState = Optics.PreparedOpticalState;
const PreparedSublayer = Optics.PreparedSublayer;

// atmospheric_budget.zig -------------------------------------------------------------------------------------|
// Base vertical diagnostic table for prepared optical state. It materializes wavelength x layer/sublayer rows |
// shared by output tables that need vertical optical-depth views.                                             |
//                                                                                                             |
// called by                                                                                                   |
//   root.zig exposes buildAtmosphericBudget for Zig callers. api/c.zig copies rows into Context-owned C ABI   |
//   storage. output.o2_o2_cia reuses the rows for CIA share columns. output.radiative_transfer_diagnostics    |
//   reuses the rows for RTM proxy columns.                                                                    |
//                                                                                                             |
// main paths                                                                                                  |
//   build       -> allocate full wavelength x vertical-row table                                              |
//   sublayerRow -> evaluate sublayer-resolved optical properties through the profile spectroscopy cache       |
//   layerRow    -> write legacy layer-level rows when sublayers are not prepared                              |
//                                                                                                             |
// row model                                                                                                   |
//   Sublayer rows preserve interval-grid support kind and global sublayer index. Layer rows preserve the      |
//   older layer-level output shape when no prepared sublayer grid exists.                                     |
//                                                                                                             |
// hot path                                                                                                    |
//   Diagnostics can request many wavelengths. For sublayer grids, build creates one profile spectroscopy      |
//   cache per wavelength and reuses it while walking all vertical support rows at that wavelength.            |
//                                                                                                             |
// memory                                                                                                      |
//   The returned row slice is owned by the caller. Rows are value records with no referenced storage.         |
// ------------------------------------------------------------------------------------------------------------|

pub const SupportRowKind = enum(u32) {
    physical = 0,
    parity_boundary = 1,
    parity_active = 2,
};

// AtmosphericBudgetRow ---------------------------------------------------------------------------------------|
// Stores one vertical diagnostic row for one wavelength and one layer or sublayer.                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 208 B (0.203 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] oxygen_number_density_cm3        : f64                                                           |
// [  8.. 15] aerosol_absorption_optical_depth : f64                                                           |
// [ 16.. 23] single_scatter_albedo            : f64                                                           |
// [ 24.. 31] total_optical_depth              : f64                                                           |
// [ 32.. 39] wavelength_nm                    : f64                                                           |
// [ 40.. 47] total_scattering_optical_depth   : f64                                                           |
// [ 48.. 55] altitude_km                      : f64                                                           |
// [ 56.. 63] top_altitude_km                  : f64                                                           |
// [ 64.. 71] bottom_altitude_km               : f64                                                           |
// [ 72.. 79] pressure_hpa                     : f64                                                           |
// [ 80.. 87] top_pressure_hpa                 : f64                                                           |
// [ 88.. 95] bottom_pressure_hpa              : f64                                                           |
// [ 96..103] total_absorption_optical_depth   : f64                                                           |
// [104..111] temperature_k                    : f64                                                           |
// [112..119] number_density_cm3               : f64                                                           |
// [120..127] absorber_number_density_cm3      : f64                                                           |
// [128..135] path_length_cm                   : f64                                                           |
// [136..143] aerosol_fraction                 : f64                                                           |
// [144..151] gas_absorption_optical_depth     : f64                                                           |
// [152..159] gas_scattering_optical_depth     : f64                                                           |
// [160..167] cia_optical_depth                : f64                                                           |
// [168..175] aerosol_optical_depth            : f64                                                           |
// [176..183] aerosol_scattering_optical_depth : f64                                                           |
// [184..187] interval_index_1based            : u32                                                           |
// [188..191] layer_index                      : u32                                                           |
// [192..195] support_row_kind                 : SupportRowKind                                                |
// [196..199] global_sublayer_index            : u32                                                           |
// [200..203] sublayer_index                   : u32                                                           |
// [204..207] trailing padding                                                                                 |
//                                                                                                             |
// unused bits: 32 padding + 0 bool-storage slack = 32 bits                                                    |
// footprint: per instance = 208 B (0.203 KiB); total = per instance * live instance count                     |
pub const AtmosphericBudgetRow = struct {
    wavelength_nm: f64,
    layer_index: u32,
    sublayer_index: u32,
    global_sublayer_index: u32,
    interval_index_1based: u32,
    support_row_kind: SupportRowKind,
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

pub fn build(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    wavelengths_nm: []const f64,
) ![]AtmosphericBudgetRow {
    // build --------------------------------------------------------------------------------------------------|
    // Allocates and fills the atmospheric-budget table for every requested wavelength and vertical row.       |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : diagnostics requested over wavelength x layer/sublayer grids                               |
    //   costly   : profile-cache spectroscopy evaluation for each sublayer row                                |
    //   memory   : one owned output slice; profile spectroscopy cache is rebuilt per wavelength               |
    //                                                                                                         |
    // calls                                                                                                   |
    //   sublayerRow                                                                                           |
    //   layerRow                                                                                              |
    // --------------------------------------------------------------------------------------------------------|

    const vertical_count = if (prepared.sublayers) |sublayers| sublayers.len else prepared.layers.len;
    const row_count = try std.math.mul(usize, wavelengths_nm.len, vertical_count);
    const rows = try allocator.alloc(AtmosphericBudgetRow, row_count);
    errdefer allocator.free(rows);

    var write_index: usize = 0;
    for (wavelengths_nm) |wavelength_nm| {
        if (prepared.sublayers) |sublayers| {
            var profile_cache = Spectroscopy.ProfileNodeSpectroscopyCache.init(prepared, wavelength_nm);
            for (sublayers, 0..) |sublayer, sublayer_index| {
                rows[write_index] = sublayerRow(
                    prepared,
                    scene,
                    wavelength_nm,
                    sublayers,
                    sublayer,
                    sublayer_index,
                    &profile_cache,
                );
                write_index += 1;
            }
        } else {
            for (prepared.layers) |layer| {
                rows[write_index] = layerRow(prepared, wavelength_nm, layer);
                write_index += 1;
            }
        }
    }

    return rows;
}

fn sublayerRow(
    prepared: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    sublayer: PreparedSublayer,
    sublayer_index: usize,
    profile_cache: *const Spectroscopy.ProfileNodeSpectroscopyCache,
) AtmosphericBudgetRow {
    const strong_line_states = choose_strong_line_states: {
        const states = prepared.strong_line_states orelse break :choose_strong_line_states null;
        if (sublayer_index >= states.len) break :choose_strong_line_states null;
        break :choose_strong_line_states states[sublayer_index .. sublayer_index + 1];
    };

    const evaluated = prepared.evaluateLayerAtWavelengthWithSpectroscopyCache(
        scene,
        sublayer.altitude_km,
        wavelength_nm,
        sublayer_index,
        sublayers[sublayer_index .. sublayer_index + 1],
        strong_line_states,
        profile_cache,
    );
    const totals = derivedTotals(evaluated.breakdown);

    const global_sublayer_index = choose_global_sublayer_index: {
        if (sublayer.global_sublayer_index != 0) break :choose_global_sublayer_index sublayer.global_sublayer_index;
        break :choose_global_sublayer_index @as(u32, @intCast(sublayer_index));
    };

    return .{
        .wavelength_nm = wavelength_nm,
        .layer_index = sublayer.parent_layer_index,
        .sublayer_index = sublayer.sublayer_index,
        .global_sublayer_index = global_sublayer_index,
        .interval_index_1based = sublayer.interval_index_1based,
        .support_row_kind = supportRowKind(sublayer.support_row_kind),
        .altitude_km = sublayer.altitude_km,
        .top_altitude_km = sublayer.top_altitude_km,
        .bottom_altitude_km = sublayer.bottom_altitude_km,
        .pressure_hpa = sublayer.pressure_hpa,
        .top_pressure_hpa = sublayer.top_pressure_hpa,
        .bottom_pressure_hpa = sublayer.bottom_pressure_hpa,
        .temperature_k = sublayer.temperature_k,
        .number_density_cm3 = sublayer.number_density_cm3,
        .oxygen_number_density_cm3 = sublayer.oxygen_number_density_cm3,
        .absorber_number_density_cm3 = sublayer.absorber_number_density_cm3,
        .path_length_cm = sublayer.path_length_cm,
        .aerosol_fraction = sublayer.aerosol_fraction,
        .gas_absorption_optical_depth = evaluated.breakdown.gas_absorption_optical_depth,
        .gas_scattering_optical_depth = evaluated.breakdown.gas_scattering_optical_depth,
        .cia_optical_depth = evaluated.breakdown.cia_optical_depth,
        .aerosol_optical_depth = evaluated.breakdown.aerosol_optical_depth,
        .aerosol_scattering_optical_depth = evaluated.breakdown.aerosol_scattering_optical_depth,
        .aerosol_absorption_optical_depth = totals.aerosol_absorption,
        .total_absorption_optical_depth = totals.absorption,
        .total_scattering_optical_depth = totals.scattering,
        .total_optical_depth = totals.optical_depth,
        .single_scatter_albedo = totals.single_scatter_albedo,
    };
}

fn layerRow(
    prepared: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer: PreparedLayer,
) AtmosphericBudgetRow {
    const aerosol_single_scatter_albedo = prepared.resolvedAerosolSingleScatterAlbedo();
    const aerosol_optical_depth = PreparedOpticalState.particleOpticalDepthAtWavelength(
        layer.aerosol_optical_depth,
        layer.aerosol_base_optical_depth,
        prepared.aerosol_reference_wavelength_nm,
        prepared.aerosol_angstrom_exponent,
        prepared.aerosol_fraction_control,
        wavelength_nm,
    );
    const gas_scattering_optical_depth = compute_gas_scattering_optical_depth: {
        if (layer.gas_scattering_optical_depth > 0.0) {
            break :compute_gas_scattering_optical_depth layer.gas_scattering_optical_depth;
        }

        break :compute_gas_scattering_optical_depth Rayleigh.crossSectionCm2(wavelength_nm) *
            layer.number_density_cm3 *
            @max(layer.top_altitude_km - layer.bottom_altitude_km, 0.0) *
            1.0e5;
    };

    const breakdown = OpticalDepthBreakdown{
        .gas_absorption_optical_depth = @max(layer.gas_optical_depth - gas_scattering_optical_depth, 0.0),
        .gas_scattering_optical_depth = gas_scattering_optical_depth,
        .cia_optical_depth = layer.cia_optical_depth,
        .aerosol_optical_depth = aerosol_optical_depth,
        .aerosol_scattering_optical_depth = aerosol_optical_depth * aerosol_single_scatter_albedo,
    };
    const totals = derivedTotals(breakdown);

    return .{
        .wavelength_nm = wavelength_nm,
        .layer_index = layer.layer_index,
        .sublayer_index = std.math.maxInt(u32),
        .global_sublayer_index = std.math.maxInt(u32),
        .interval_index_1based = layer.interval_index_1based,
        .support_row_kind = .physical,
        .altitude_km = layer.altitude_km,
        .top_altitude_km = layer.top_altitude_km,
        .bottom_altitude_km = layer.bottom_altitude_km,
        .pressure_hpa = layer.pressure_hpa,
        .top_pressure_hpa = layer.top_pressure_hpa,
        .bottom_pressure_hpa = layer.bottom_pressure_hpa,
        .temperature_k = layer.temperature_k,
        .number_density_cm3 = layer.number_density_cm3,
        .oxygen_number_density_cm3 = 0.0,
        .absorber_number_density_cm3 = 0.0,
        .path_length_cm = @max(layer.top_altitude_km - layer.bottom_altitude_km, 0.0) * 1.0e5,
        .aerosol_fraction = layer.aerosol_fraction,
        .gas_absorption_optical_depth = breakdown.gas_absorption_optical_depth,
        .gas_scattering_optical_depth = breakdown.gas_scattering_optical_depth,
        .cia_optical_depth = breakdown.cia_optical_depth,
        .aerosol_optical_depth = breakdown.aerosol_optical_depth,
        .aerosol_scattering_optical_depth = breakdown.aerosol_scattering_optical_depth,
        .aerosol_absorption_optical_depth = totals.aerosol_absorption,
        .total_absorption_optical_depth = totals.absorption,
        .total_scattering_optical_depth = totals.scattering,
        .total_optical_depth = totals.optical_depth,
        .single_scatter_albedo = totals.single_scatter_albedo,
    };
}

// DerivedTotals ----------------------------------------------------------------------------------------------|
// Carries optical-depth totals derived from one breakdown before they are copied into an output row.          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] aerosol_absorption    : f64                                                                        |
// [ 8..15] absorption            : f64                                                                        |
// [16..23] scattering            : f64                                                                        |
// [24..31] optical_depth         : f64                                                                        |
// [32..39] single_scatter_albedo : f64                                                                        |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per value = 40 B (0.039 KiB); total = caller-local temporary                                     |
const DerivedTotals = struct {
    aerosol_absorption: f64,
    absorption: f64,
    scattering: f64,
    optical_depth: f64,
    single_scatter_albedo: f64,
};
// ------------------------------------------------------------------------------------------------------------|

fn derivedTotals(breakdown: OpticalDepthBreakdown) DerivedTotals {
    const aerosol_absorption = @max(
        breakdown.aerosol_optical_depth - breakdown.aerosol_scattering_optical_depth,
        0.0,
    );
    const scattering = breakdown.totalScatteringOpticalDepth();
    const optical_depth = breakdown.totalOpticalDepth();
    const single_scatter_albedo = if (optical_depth > 0.0)
        std.math.clamp(scattering / optical_depth, 0.0, 1.0)
    else
        0.0;

    return .{
        .aerosol_absorption = aerosol_absorption,
        .absorption = breakdown.gas_absorption_optical_depth +
            breakdown.cia_optical_depth +
            aerosol_absorption,
        .scattering = scattering,
        .optical_depth = optical_depth,
        .single_scatter_albedo = single_scatter_albedo,
    };
}

fn supportRowKind(kind: StateTypes.PreparedSupportRowKind) SupportRowKind {
    return switch (kind) {
        .physical => .physical,
        .parity_boundary => .parity_boundary,
        .parity_active => .parity_active,
    };
}
