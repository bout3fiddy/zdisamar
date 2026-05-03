const std = @import("std");
const Scene = @import("../input/Scene.zig").Scene;
const AtmosphereModel = @import("../input/Atmosphere.zig");
const Optics = @import("../forward_model/optical_properties/root.zig");
const Rayleigh = @import("../input/reference/rayleigh.zig");
const Spectroscopy = @import("../forward_model/optical_properties/state_build/state_spectroscopy.zig");
const StateTypes = @import("../forward_model/optical_properties/state_build/state_types.zig");

const Allocator = std.mem.Allocator;
const OpticalDepthBreakdown = Optics.OpticalDepthBreakdown;
const PreparedLayer = Optics.PreparedLayer;
const PreparedOpticalState = Optics.PreparedOpticalState;
const PreparedSublayer = Optics.PreparedSublayer;

pub const SupportRowKind = enum(u32) {
    physical = 0,
    parity_boundary = 1,
    parity_active = 2,
};

pub const SubcolumnLabel = enum(u32) {
    unspecified = 0,
    boundary_layer = 1,
    free_troposphere = 2,
    fit_interval = 3,
    stratosphere = 4,
};

pub const AtmosphericBudgetRow = struct {
    wavelength_nm: f64,
    layer_index: u32,
    sublayer_index: u32,
    global_sublayer_index: u32,
    interval_index_1based: u32,
    support_row_kind: SupportRowKind,
    subcolumn_label: SubcolumnLabel,
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
    cloud_fraction: f64,
    gas_absorption_optical_depth: f64,
    gas_scattering_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    aerosol_scattering_optical_depth: f64,
    aerosol_absorption_optical_depth: f64,
    cloud_optical_depth: f64,
    cloud_scattering_optical_depth: f64,
    cloud_absorption_optical_depth: f64,
    total_absorption_optical_depth: f64,
    total_scattering_optical_depth: f64,
    total_optical_depth: f64,
    single_scatter_albedo: f64,
};

pub fn build(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    wavelengths_nm: []const f64,
) ![]AtmosphericBudgetRow {
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
    const strong_line_states = if (prepared.strong_line_states) |states|
        if (sublayer_index < states.len) states[sublayer_index .. sublayer_index + 1] else null
    else
        null;
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

    return .{
        .wavelength_nm = wavelength_nm,
        .layer_index = sublayer.parent_layer_index,
        .sublayer_index = sublayer.sublayer_index,
        .global_sublayer_index = if (sublayer.global_sublayer_index != 0)
            sublayer.global_sublayer_index
        else
            @intCast(sublayer_index),
        .interval_index_1based = sublayer.interval_index_1based,
        .support_row_kind = supportRowKind(sublayer.support_row_kind),
        .subcolumn_label = subcolumnLabel(sublayer.subcolumn_label),
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
        .cloud_fraction = sublayer.cloud_fraction,
        .gas_absorption_optical_depth = evaluated.breakdown.gas_absorption_optical_depth,
        .gas_scattering_optical_depth = evaluated.breakdown.gas_scattering_optical_depth,
        .cia_optical_depth = evaluated.breakdown.cia_optical_depth,
        .aerosol_optical_depth = evaluated.breakdown.aerosol_optical_depth,
        .aerosol_scattering_optical_depth = evaluated.breakdown.aerosol_scattering_optical_depth,
        .aerosol_absorption_optical_depth = totals.aerosol_absorption,
        .cloud_optical_depth = evaluated.breakdown.cloud_optical_depth,
        .cloud_scattering_optical_depth = evaluated.breakdown.cloud_scattering_optical_depth,
        .cloud_absorption_optical_depth = totals.cloud_absorption,
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
    const particle_single_scatter_albedos = prepared.resolvedParticleSingleScatterAlbedos();
    const aerosol_optical_depth = PreparedOpticalState.particleOpticalDepthAtWavelength(
        layer.aerosol_optical_depth,
        layer.aerosol_base_optical_depth,
        prepared.aerosol_reference_wavelength_nm,
        prepared.aerosol_angstrom_exponent,
        prepared.aerosol_fraction_control,
        wavelength_nm,
    );
    const cloud_optical_depth = PreparedOpticalState.particleOpticalDepthAtWavelength(
        layer.cloud_optical_depth,
        layer.cloud_base_optical_depth,
        prepared.cloud_reference_wavelength_nm,
        prepared.cloud_angstrom_exponent,
        prepared.cloud_fraction_control,
        wavelength_nm,
    );
    const gas_scattering_optical_depth = if (layer.gas_scattering_optical_depth > 0.0)
        layer.gas_scattering_optical_depth
    else
        Rayleigh.crossSectionCm2(wavelength_nm) *
            layer.number_density_cm3 *
            @max(layer.top_altitude_km - layer.bottom_altitude_km, 0.0) *
            1.0e5;
    const breakdown = OpticalDepthBreakdown{
        .gas_absorption_optical_depth = @max(layer.gas_optical_depth - gas_scattering_optical_depth, 0.0),
        .gas_scattering_optical_depth = gas_scattering_optical_depth,
        .cia_optical_depth = layer.cia_optical_depth,
        .aerosol_optical_depth = aerosol_optical_depth,
        .aerosol_scattering_optical_depth = aerosol_optical_depth * particle_single_scatter_albedos.aerosol,
        .cloud_optical_depth = cloud_optical_depth,
        .cloud_scattering_optical_depth = cloud_optical_depth * particle_single_scatter_albedos.cloud,
    };
    const totals = derivedTotals(breakdown);

    return .{
        .wavelength_nm = wavelength_nm,
        .layer_index = layer.layer_index,
        .sublayer_index = std.math.maxInt(u32),
        .global_sublayer_index = std.math.maxInt(u32),
        .interval_index_1based = layer.interval_index_1based,
        .support_row_kind = .physical,
        .subcolumn_label = subcolumnLabel(layer.subcolumn_label),
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
        .cloud_fraction = layer.cloud_fraction,
        .gas_absorption_optical_depth = breakdown.gas_absorption_optical_depth,
        .gas_scattering_optical_depth = breakdown.gas_scattering_optical_depth,
        .cia_optical_depth = breakdown.cia_optical_depth,
        .aerosol_optical_depth = breakdown.aerosol_optical_depth,
        .aerosol_scattering_optical_depth = breakdown.aerosol_scattering_optical_depth,
        .aerosol_absorption_optical_depth = totals.aerosol_absorption,
        .cloud_optical_depth = breakdown.cloud_optical_depth,
        .cloud_scattering_optical_depth = breakdown.cloud_scattering_optical_depth,
        .cloud_absorption_optical_depth = totals.cloud_absorption,
        .total_absorption_optical_depth = totals.absorption,
        .total_scattering_optical_depth = totals.scattering,
        .total_optical_depth = totals.optical_depth,
        .single_scatter_albedo = totals.single_scatter_albedo,
    };
}

fn derivedTotals(breakdown: OpticalDepthBreakdown) struct {
    aerosol_absorption: f64,
    cloud_absorption: f64,
    absorption: f64,
    scattering: f64,
    optical_depth: f64,
    single_scatter_albedo: f64,
} {
    const aerosol_absorption = @max(
        breakdown.aerosol_optical_depth - breakdown.aerosol_scattering_optical_depth,
        0.0,
    );
    const cloud_absorption = @max(
        breakdown.cloud_optical_depth - breakdown.cloud_scattering_optical_depth,
        0.0,
    );
    const scattering = breakdown.totalScatteringOpticalDepth();
    const optical_depth = breakdown.totalOpticalDepth();
    return .{
        .aerosol_absorption = aerosol_absorption,
        .cloud_absorption = cloud_absorption,
        .absorption = breakdown.gas_absorption_optical_depth +
            breakdown.cia_optical_depth +
            aerosol_absorption +
            cloud_absorption,
        .scattering = scattering,
        .optical_depth = optical_depth,
        .single_scatter_albedo = if (optical_depth > 0.0)
            std.math.clamp(scattering / optical_depth, 0.0, 1.0)
        else
            0.0,
    };
}

fn supportRowKind(kind: StateTypes.PreparedSupportRowKind) SupportRowKind {
    return switch (kind) {
        .physical => .physical,
        .parity_boundary => .parity_boundary,
        .parity_active => .parity_active,
    };
}

fn subcolumnLabel(label: AtmosphereModel.PartitionLabel) SubcolumnLabel {
    return switch (label) {
        .unspecified => .unspecified,
        .boundary_layer => .boundary_layer,
        .free_troposphere => .free_troposphere,
        .fit_interval => .fit_interval,
        .stratosphere => .stratosphere,
    };
}
