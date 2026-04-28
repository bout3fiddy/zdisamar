const std = @import("std");
const BandMeans = @import("../shared/band_means.zig");
const LayerAccumulation = @import("layer_accumulation.zig");
const Context = @import("context.zig").PreparationContext;
const Absorbers = @import("absorbers.zig");

const Allocator = std.mem.Allocator;

pub const PreparedMeans = struct {
    cross_section_mean_cm2_per_molecule: f64 = 0.0,
    line_means: BandMeans.LineBandMeans = .{},
    cia_mean_cross_section_cm5_per_molecule2: f64 = 0.0,
    effective_air_mass_factor: f64 = 0.0,
    effective_single_scatter_albedo: f64 = 0.0,
    effective_temperature_k: f64 = 0.0,
    effective_pressure_hpa: f64 = 0.0,
    air_column_density_factor: f64 = 0.0,
    oxygen_column_density_factor: f64 = 0.0,
    column_density_factor: f64 = 0.0,
    cia_pair_path_factor_cm5: f64 = 0.0,
    gas_optical_depth: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64 = 0.0,
    aerosol_base_optical_depth: f64 = 0.0,
    cloud_optical_depth: f64 = 0.0,
    cloud_base_optical_depth: f64 = 0.0,
    d_optical_depth_d_temperature: f64 = 0.0,
    total_optical_depth: f64 = 0.0,
    depolarization_factor: f64 = 0.0,
};

pub const AccumulationResult = struct {
    means: PreparedMeans = .{},
};

pub fn accumulate(
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
) !AccumulationResult {
    const layer_totals = try LayerAccumulation.populate(allocator, context, absorbers);
    return .{
        .means = try computePreparedMeans(
            allocator,
            context,
            absorbers,
            layer_totals,
        ),
    };
}

fn computePreparedMeans(
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
    layer_totals: LayerAccumulation.LayerAccumulation,
) !PreparedMeans {
    const scene = context.scene;
    const operational_o2_lut = context.operational_o2_lut;
    const operational_o2o2_lut = context.operational_o2o2_lut;
    const effective_temperature = if (layer_totals.total_weight == 0.0)
        0.0
    else
        layer_totals.total_temperature_weighted / layer_totals.total_weight;
    const effective_pressure = if (layer_totals.total_weight == 0.0)
        0.0
    else
        layer_totals.total_pressure_weighted / layer_totals.total_weight;

    const cross_section_mean = if (absorbers.owned_cross_section_absorbers.len != 0) blk: {
        var cross_section_total_weight: f64 = 0.0;
        var weighted_mean: f64 = 0.0;
        for (absorbers.owned_cross_section_absorbers) |*cross_section_absorber| {
            const weight = cross_section_absorber.column_density_factor;
            if (weight <= 0.0) continue;
            cross_section_total_weight += weight;
            weighted_mean += cross_section_absorber.meanSigmaInRange(
                scene.spectral_grid.start_nm,
                scene.spectral_grid.end_nm,
                effective_temperature,
                effective_pressure,
            ) * weight;
        }
        if (cross_section_total_weight <= 0.0) break :blk 0.0;
        break :blk weighted_mean / cross_section_total_weight;
    } else absorbers.mean_sigma;

    const line_means = if (absorbers.owned_line_absorbers.len != 0 or operational_o2_lut.enabled()) blk: {
        var line_mean_weight: f64 = 0.0;
        var weighted: BandMeans.LineBandMeans = .{};
        if (operational_o2_lut.enabled() and layer_totals.oxygen_column_density_factor > 0.0) {
            const operational_mean = BandMeans.computeOperationalBandMean(
                scene,
                operational_o2_lut,
                effective_temperature,
                effective_pressure,
            );
            line_mean_weight += layer_totals.oxygen_column_density_factor;
            weighted.line_mean_cross_section_cm2_per_molecule +=
                operational_mean * layer_totals.oxygen_column_density_factor;
        }
        for (absorbers.owned_line_absorbers) |*line_absorber| {
            if (operational_o2_lut.enabled() and line_absorber.species == .o2) continue;
            const weight = line_absorber.column_density_factor;
            if (weight <= 0.0) continue;
            const means = try BandMeans.computeBandLineMeans(
                allocator,
                scene,
                &line_absorber.line_list,
                effective_temperature,
                effective_pressure,
            );
            line_mean_weight += weight;
            weighted.line_mean_cross_section_cm2_per_molecule +=
                means.line_mean_cross_section_cm2_per_molecule * weight;
            weighted.line_mixing_mean_cross_section_cm2_per_molecule +=
                means.line_mixing_mean_cross_section_cm2_per_molecule * weight;
        }
        if (line_mean_weight > 0.0) {
            weighted.line_mean_cross_section_cm2_per_molecule /= line_mean_weight;
            weighted.line_mixing_mean_cross_section_cm2_per_molecule /= line_mean_weight;
        }
        break :blk weighted;
    } else if (absorbers.owned_lines) |*line_list|
        try BandMeans.computeBandLineMeans(allocator, scene, line_list, effective_temperature, effective_pressure)
    else
        BandMeans.LineBandMeans{};

    const cia_mean_sigma = if (operational_o2o2_lut.enabled())
        BandMeans.computeOperationalBandMean(
            scene,
            operational_o2o2_lut,
            @max(effective_temperature, 150.0),
            effective_pressure,
        )
    else if (context.collision_induced_absorption) |cia_table|
        cia_table.meanSigmaInRange(
            scene.spectral_grid.start_nm,
            scene.spectral_grid.end_nm,
            @max(effective_temperature, 150.0),
        )
    else
        0.0;

    return .{
        .cross_section_mean_cm2_per_molecule = cross_section_mean,
        .line_means = line_means,
        .cia_mean_cross_section_cm5_per_molecule2 = cia_mean_sigma,
        .effective_air_mass_factor = absorbers.air_mass_factor,
        .effective_single_scatter_albedo = if (layer_totals.total_optical_depth == 0.0)
            layer_totals.base_single_scatter_albedo
        else
            layer_totals.total_scattering_optical_depth / layer_totals.total_optical_depth,
        .effective_temperature_k = effective_temperature,
        .effective_pressure_hpa = effective_pressure,
        .air_column_density_factor = layer_totals.air_column_density_factor,
        .oxygen_column_density_factor = layer_totals.oxygen_column_density_factor,
        .column_density_factor = layer_totals.column_density_factor,
        .cia_pair_path_factor_cm5 = layer_totals.cia_pair_path_factor_cm5,
        .gas_optical_depth = layer_totals.total_gas_optical_depth,
        .cia_optical_depth = layer_totals.total_cia_optical_depth,
        .aerosol_optical_depth = layer_totals.total_aerosol_optical_depth,
        .aerosol_base_optical_depth = layer_totals.total_aerosol_base_optical_depth,
        .cloud_optical_depth = layer_totals.total_cloud_optical_depth,
        .cloud_base_optical_depth = layer_totals.total_cloud_base_optical_depth,
        .d_optical_depth_d_temperature = layer_totals.total_d_optical_depth_d_temperature,
        .total_optical_depth = layer_totals.total_optical_depth,
        .depolarization_factor = if (layer_totals.total_optical_depth == 0.0)
            0.0
        else
            layer_totals.depolarization_weighted / layer_totals.total_optical_depth,
    };
}
