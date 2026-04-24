//! Purpose:
//!   Assemble the final prepared optical state from the staged context,
//!   absorber state, and accumulated means.

const Scene = @import("../../../model/Scene.zig").Scene;
const PhaseSupportKind = @import("../../../model/reference/airmass_phase.zig").PhaseSupportKind;
const Accumulation = @import("accumulation.zig");
const Absorbers = @import("absorbers.zig");
const Context = @import("context.zig").PreparationContext;
const State = @import("state.zig");

pub fn assemble(
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
    accumulation: Accumulation.AccumulationResult,
) State.PreparedOpticalState {
    const scene = context.scene;
    const means = accumulation.means;
    const aerosol_phase_support = if (context.aerosol_mie != null)
        PhaseSupportKind.mie_table
    else if (scene.aerosol.enabled)
        PhaseSupportKind.analytic_hg
    else
        PhaseSupportKind.none;
    const cloud_phase_support = if (context.cloud_mie != null)
        PhaseSupportKind.mie_table
    else if (scene.cloud.enabled)
        PhaseSupportKind.analytic_hg
    else
        PhaseSupportKind.none;

    const prepared: State.PreparedOpticalState = .{
        .layers = context.layers,
        .sublayers = context.sublayers,
        .strong_line_states = absorbers.strong_line_states,
        .continuum_points = context.continuum_points,
        .collision_induced_absorption = context.collision_induced_absorption,
        .spectroscopy_lines = absorbers.owned_lines,
        .spectroscopy_profile_altitudes_km = context.spectroscopy_profile_altitudes_km,
        .spectroscopy_profile_pressures_hpa = context.spectroscopy_profile_pressures_hpa,
        .spectroscopy_profile_temperatures_k = context.spectroscopy_profile_temperatures_k,
        .cross_section_absorbers = absorbers.owned_cross_section_absorbers,
        .line_absorbers = absorbers.owned_line_absorbers,
        .continuum_owner_species = absorbers.continuum_owner_species,
        .operational_o2_lut = context.operational_o2_lut,
        .operational_o2o2_lut = context.operational_o2o2_lut,
        .owns_operational_o2_lut = context.operational_o2_lut.enabled(),
        .owns_operational_o2o2_lut = context.operational_o2o2_lut.enabled(),
        .mean_cross_section_cm2_per_molecule = means.cross_section_mean_cm2_per_molecule +
            means.line_means.line_mean_cross_section_cm2_per_molecule +
            means.line_means.line_mixing_mean_cross_section_cm2_per_molecule,
        .line_mean_cross_section_cm2_per_molecule = means.line_means.line_mean_cross_section_cm2_per_molecule,
        .line_mixing_mean_cross_section_cm2_per_molecule = means.line_means.line_mixing_mean_cross_section_cm2_per_molecule,
        .cia_mean_cross_section_cm5_per_molecule2 = means.cia_mean_cross_section_cm5_per_molecule2,
        .effective_air_mass_factor = means.effective_air_mass_factor,
        .effective_single_scatter_albedo = means.effective_single_scatter_albedo,
        .aerosol_single_scatter_albedo = if (context.aerosol_mie) |table|
            table.interpolate(context.midpoint_nm).single_scatter_albedo
        else
            scene.aerosol.single_scatter_albedo,
        .cloud_single_scatter_albedo = if (context.cloud_mie) |table|
            table.interpolate(context.midpoint_nm).single_scatter_albedo
        else
            scene.cloud.single_scatter_albedo,
        .effective_temperature_k = means.effective_temperature_k,
        .effective_pressure_hpa = means.effective_pressure_hpa,
        .air_column_density_factor = means.air_column_density_factor,
        .oxygen_column_density_factor = means.oxygen_column_density_factor,
        .column_density_factor = means.column_density_factor,
        .cia_pair_path_factor_cm5 = means.cia_pair_path_factor_cm5,
        .aerosol_reference_wavelength_nm = scene.aerosol.reference_wavelength_nm,
        .aerosol_angstrom_exponent = scene.aerosol.angstrom_exponent,
        .cloud_reference_wavelength_nm = scene.cloud.reference_wavelength_nm,
        .cloud_angstrom_exponent = scene.cloud.angstrom_exponent,
        .gas_optical_depth = means.gas_optical_depth,
        .cia_optical_depth = means.cia_optical_depth,
        .aerosol_optical_depth = means.aerosol_optical_depth,
        .aerosol_base_optical_depth = means.aerosol_base_optical_depth,
        .cloud_optical_depth = means.cloud_optical_depth,
        .cloud_base_optical_depth = means.cloud_base_optical_depth,
        .d_optical_depth_d_temperature = means.d_optical_depth_d_temperature,
        .depolarization_factor = means.depolarization_factor,
        .total_optical_depth = means.total_optical_depth,
        .interval_semantics = scene.atmosphere.interval_grid.semantics,
        .fit_interval_index_1based = scene.atmosphere.interval_grid.fit_interval_index_1based,
        .subcolumn_semantics_enabled = scene.atmosphere.subcolumns.enabled,
        .aerosol_phase_support = aerosol_phase_support,
        .cloud_phase_support = cloud_phase_support,
        .aerosol_fraction_control = context.aerosol_fraction_control,
        .cloud_fraction_control = context.cloud_fraction_control,
    };

    context.layers = &.{};
    context.sublayers = &.{};
    context.continuum_points = &.{};
    context.spectroscopy_profile_altitudes_km = &.{};
    context.spectroscopy_profile_pressures_hpa = &.{};
    context.spectroscopy_profile_temperatures_k = &.{};
    context.collision_induced_absorption = null;
    context.spectroscopy_lines = null;
    context.aerosol_fraction_control = .{};
    context.cloud_fraction_control = .{};
    context.operational_o2_lut = .{};
    context.operational_o2o2_lut = .{};

    absorbers.owned_cross_section_absorbers = &.{};
    absorbers.owned_cross_section_absorber_count = 0;
    absorbers.owned_line_absorbers = &.{};
    absorbers.owned_line_absorber_count = 0;
    absorbers.strong_line_states = null;
    absorbers.strong_line_state_count = 0;
    absorbers.owned_lines = null;

    return prepared;
}
