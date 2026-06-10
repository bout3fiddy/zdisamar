const std = @import("std");
const BandMeans = @import("../shared/band_means.zig");
const LayerAccumulation = @import("layer_accumulation.zig");
const Context = @import("context.zig").PreparationContext;
const Absorbers = @import("absorbers.zig");

const Allocator = std.mem.Allocator;

// accumulation.zig -------------------------------------------------------------------------------------------|
// Scalar reduction stage for optical-property preparation. layer_accumulation.zig has already filled the      |
// retained PreparedLayer/PreparedSublayer rows and produced running totals; this file turns those totals plus |
// absorber state into the compact PreparedMeans row copied into PreparedOpticalState by finalize.zig.         |
//                                                                                                             |
// called by                                                                                                   |
//   root.prepare calls accumulate after Context.init has allocated preparation storage and Absorbers.build    |
//   has prepared line/cross-section absorber rows, LUT handles, density columns, and optional line states.    |
//                                                                                                             |
// route map                                                                                                   |
//   LayerAccumulation.populate : fills layer/sublayer rows and returns optical-depth/column running totals    |
//   computePreparedMeans       : folds totals into effective T/p, band means, column factors, and summaries   |
//   Finalize.assemble          : copies the returned PreparedMeans into the final PreparedOpticalState header |
//                                                                                                             |
// reduction model                                                                                             |
//   Layer totals provide atmosphere-weighted thermodynamics and optical depths. Absorber rows provide         |
//   band-mean cross sections; operational O2/O2-O2 LUTs replace the corresponding line/CIA table route when   |
//   enabled. Aerosol single-scatter albedo and depolarization are weighted by optical depth.                  |
//                                                                                                             |
// hot path                                                                                                    |
//   Runs once per prepared scene, but retrievals rebuild it for every trial state. The repeated heavy work    |
//   stays in layer_accumulation and band-mean scans; PreparedMeans remains a small by-value handoff so final  |
//   assembly does not need to reread wide layer or absorber rows.                                             |
//                                                                                                             |
// ownership                                                                                                   |
//   Reads Context and AbsorberBuildState, allocates only through delegated band-mean helpers, and returns     |
//   PreparedMeans by value. It does not retain borrowed rows or move ownership; finalize.zig owns that step.  |
// ------------------------------------------------------------------------------------------------------------|

// PreparedMeans ----------------------------------------------------------------------------------------------|
// Scalar and band means copied into PreparedOpticalState during final assembly. This is the compact summary   |
// row produced after layer accumulation has filled the retained layer/sublayer arrays.                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 152 B (0.148 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] cross_section_mean_cm2_per_molecule      : f64                                                   |
// [  8.. 23] line_means                               : BandMeans.LineBandMeans                               |
// [ 24.. 31] cia_mean_cross_section_cm5_per_molecule2 : f64                                                   |
// [ 32.. 39] effective_air_mass_factor                : f64                                                   |
// [ 40.. 47] effective_single_scatter_albedo          : f64                                                   |
// [ 48.. 55] effective_temperature_k                  : f64                                                   |
// [ 56.. 63] effective_pressure_hpa                   : f64                                                   |
// [ 64.. 71] air_column_density_factor                : f64                                                   |
// [ 72.. 79] oxygen_column_density_factor             : f64                                                   |
// [ 80.. 87] column_density_factor                    : f64                                                   |
// [ 88.. 95] cia_pair_path_factor_cm5                 : f64                                                   |
// [ 96..103] gas_optical_depth                        : f64                                                   |
// [104..111] cia_optical_depth                        : f64                                                   |
// [112..119] aerosol_optical_depth                    : f64                                                   |
// [120..127] aerosol_base_optical_depth               : f64                                                   |
// [128..135] d_optical_depth_d_temperature            : f64                                                   |
// [136..143] total_optical_depth                      : f64                                                   |
// [144..151] depolarization_factor                    : f64                                                   |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 3 cache lines at 64 B per line                                                                  |
// footprint: per instance = 152 B (0.148 KiB); total = per instance * live instance count                     |
// ------------------------------------------------------------------------------------------------------------|
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
    d_optical_depth_d_temperature: f64 = 0.0,
    total_optical_depth: f64 = 0.0,
    depolarization_factor: f64 = 0.0,
};

pub fn accumulate(
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
) !PreparedMeans {
    // accumulate ---------------------------------------------------------------------------------------------|
    // Build layer totals, particle/phase/spectroscopy support rows, and the PreparedMeans summary.            |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Optical-state preparation calls this once per prepared scene. The layer population step writes the    |
    //   wide retained rows; the second step reduces their totals into the small by-value handoff.             |
    //                                                                                                         |
    // calls                                                                                                   |
    //   LayerAccumulation.populate -> computePreparedMeans                                                    |
    // --------------------------------------------------------------------------------------------------------|

    const layer_totals = try LayerAccumulation.populate(allocator, context, absorbers);
    return computePreparedMeans(
        allocator,
        context,
        absorbers,
        layer_totals,
    );
}

fn computePreparedMeans(
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
    layer_totals: LayerAccumulation.LayerAccumulation,
) !PreparedMeans {
    // computePreparedMeans -----------------------------------------------------------------------------------|
    // Reduce layer/sublayer sums into effective T, p, column factors, band means, and optical-depth totals.   |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Runs once per optical-state preparation after all layer rows have been accumulated. The loops over    |
    //   absorber rows use pointer capture because absorber rows own or reference out-of-line spectroscopy     |
    //   storage that should not be copied while computing band means.                                         |
    //                                                                                                         |
    // math                                                                                                    |
    //   T_eff     = sum(T_i * n_i * w_i) / sum(n_i * w_i); p_eff uses the same weights.                       |
    //   sigma_bar = sum(sigma_k * column_k) / sum(column_k).                                                  |
    //   omega0    = tau_scattering / tau_total.                                                               |
    //                                                                                                         |
    // route notes                                                                                             |
    //   Operational O2 contributes with oxygen_column_density_factor and skips prepared O2 line absorbers.    |
    //   Operational O2-O2 contributes the CIA band mean when enabled; otherwise the prepared CIA table does.  |
    // --------------------------------------------------------------------------------------------------------|

    const EffectiveThermodynamics = struct {
        temperature_k: f64,
        pressure_hpa: f64,
    };
    const OpticalDepthWeightedMeans = struct {
        single_scatter_albedo: f64,
        depolarization_factor: f64,
    };

    const scene = context.scene;
    const operational_o2_lut = context.operational_o2_lut;
    const operational_o2o2_lut = context.operational_o2o2_lut;

    const effective: EffectiveThermodynamics = choose_effective_thermodynamics: {
        if (layer_totals.total_weight == 0.0) {
            break :choose_effective_thermodynamics .{
                .temperature_k = 0.0,
                .pressure_hpa = 0.0,
            };
        }

        break :choose_effective_thermodynamics .{
            .temperature_k = layer_totals.total_temperature_weighted / layer_totals.total_weight,
            .pressure_hpa = layer_totals.total_pressure_weighted / layer_totals.total_weight,
        };
    };

    const cross_section_mean = choose_cross_section_mean: {
        if (absorbers.owned_cross_section_absorbers.len == 0) {
            break :choose_cross_section_mean absorbers.mean_sigma;
        }

        var cross_section_total_weight: f64 = 0.0;
        var weighted_mean: f64 = 0.0;
        for (absorbers.owned_cross_section_absorbers) |*cross_section_absorber| {
            const weight = cross_section_absorber.column_density_factor;
            if (weight <= 0.0) continue;

            cross_section_total_weight += weight;
            weighted_mean += cross_section_absorber.meanSigmaInRange(
                scene.spectral_grid.start_nm,
                scene.spectral_grid.end_nm,
                effective.temperature_k,
                effective.pressure_hpa,
            ) * weight;
        }

        if (cross_section_total_weight <= 0.0) break :choose_cross_section_mean 0.0;
        break :choose_cross_section_mean weighted_mean / cross_section_total_weight;
    };

    const line_means = choose_line_means: {
        if (absorbers.owned_line_absorbers.len == 0 and !operational_o2_lut.enabled()) {
            if (absorbers.owned_lines) |*line_list| {
                break :choose_line_means try BandMeans.computeBandLineMeans(
                    allocator,
                    scene,
                    line_list,
                    effective.temperature_k,
                    effective.pressure_hpa,
                );
            }

            break :choose_line_means BandMeans.LineBandMeans{};
        }

        var line_mean_weight: f64 = 0.0;
        var weighted: BandMeans.LineBandMeans = .{};
        if (operational_o2_lut.enabled() and layer_totals.oxygen_column_density_factor > 0.0) {
            const operational_mean = BandMeans.computeOperationalBandMean(
                scene,
                operational_o2_lut,
                effective.temperature_k,
                effective.pressure_hpa,
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
                effective.temperature_k,
                effective.pressure_hpa,
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

        break :choose_line_means weighted;
    };

    const cia_mean_sigma = choose_cia_mean_sigma: {
        if (operational_o2o2_lut.enabled()) {
            break :choose_cia_mean_sigma BandMeans.computeOperationalBandMean(
                scene,
                operational_o2o2_lut,
                @max(effective.temperature_k, 150.0),
                effective.pressure_hpa,
            );
        }

        if (context.collision_induced_absorption) |cia_table| {
            break :choose_cia_mean_sigma cia_table.meanSigmaInRange(
                scene.spectral_grid.start_nm,
                scene.spectral_grid.end_nm,
                @max(effective.temperature_k, 150.0),
            );
        }

        break :choose_cia_mean_sigma 0.0;
    };

    const optical_depth_weighted_means: OpticalDepthWeightedMeans = choose_optical_depth_weighted_means: {
        if (layer_totals.total_optical_depth == 0.0) {
            break :choose_optical_depth_weighted_means .{
                .single_scatter_albedo = layer_totals.base_single_scatter_albedo,
                .depolarization_factor = 0.0,
            };
        }

        break :choose_optical_depth_weighted_means .{
            .single_scatter_albedo = layer_totals.total_scattering_optical_depth / layer_totals.total_optical_depth,
            .depolarization_factor = layer_totals.depolarization_weighted / layer_totals.total_optical_depth,
        };
    };

    return .{
        .cross_section_mean_cm2_per_molecule = cross_section_mean,
        .line_means = line_means,
        .cia_mean_cross_section_cm5_per_molecule2 = cia_mean_sigma,
        .effective_air_mass_factor = absorbers.air_mass_factor,
        .effective_single_scatter_albedo = optical_depth_weighted_means.single_scatter_albedo,
        .effective_temperature_k = effective.temperature_k,
        .effective_pressure_hpa = effective.pressure_hpa,
        .air_column_density_factor = layer_totals.air_column_density_factor,
        .oxygen_column_density_factor = layer_totals.oxygen_column_density_factor,
        .column_density_factor = layer_totals.column_density_factor,
        .cia_pair_path_factor_cm5 = layer_totals.cia_pair_path_factor_cm5,
        .gas_optical_depth = layer_totals.total_gas_optical_depth,
        .cia_optical_depth = layer_totals.total_cia_optical_depth,
        .aerosol_optical_depth = layer_totals.total_aerosol_optical_depth,
        .aerosol_base_optical_depth = layer_totals.total_aerosol_base_optical_depth,
        .d_optical_depth_d_temperature = layer_totals.total_d_optical_depth_d_temperature,
        .total_optical_depth = layer_totals.total_optical_depth,
        .depolarization_factor = optical_depth_weighted_means.depolarization_factor,
    };
}
