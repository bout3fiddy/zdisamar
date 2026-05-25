const Scene = @import("../../../input/Scene.zig").Scene;
const PhaseSupportKind = @import("../../../input/reference/airmass_phase.zig").PhaseSupportKind;
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
    const aerosol_phase_support = if (scene.aerosol.enabled)
        PhaseSupportKind.analytic_hg
    else
        PhaseSupportKind.none;
    var prepared: State.PreparedOpticalState = .{
        .layers = context.layers,
        .sublayers = context.sublayers,
        .strong_line_states = absorbers.strong_line_states,
        .spectroscopy_profile_strong_line_states = absorbers.profile_strong_line_states,
        .spectroscopy_profile_weak_line_states = absorbers.profile_weak_line_states,
        .continuum_points = context.continuum_points,
        .owns_continuum_points = context.owns_continuum_points,
        .collision_induced_absorption = context.collision_induced_absorption,
        .owns_collision_induced_absorption = context.owns_collision_induced_absorption,
        .spectroscopy_lines = absorbers.owned_lines,
        .spectroscopy_profile_altitudes_km = context.spectroscopy_profile_altitudes_km,
        .spectroscopy_profile_pressures_hpa = context.spectroscopy_profile_pressures_hpa,
        .spectroscopy_profile_temperatures_k = context.spectroscopy_profile_temperatures_k,
        .owns_spectroscopy_profile_arrays = context.owns_spectroscopy_profile_arrays,
        .owns_spectroscopy_profile_strong_line_states = absorbers.owns_profile_strong_line_states,
        .owns_spectroscopy_profile_weak_line_states = absorbers.owns_profile_weak_line_states,
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
        .aerosol_single_scatter_albedo = scene.aerosol.single_scatter_albedo,
        .aerosol_phase_coefficients = context.aerosol_phase_coefficients,
        .effective_temperature_k = means.effective_temperature_k,
        .effective_pressure_hpa = means.effective_pressure_hpa,
        .air_column_density_factor = means.air_column_density_factor,
        .oxygen_column_density_factor = means.oxygen_column_density_factor,
        .column_density_factor = means.column_density_factor,
        .cia_pair_path_factor_cm5 = means.cia_pair_path_factor_cm5,
        .aerosol_reference_wavelength_nm = scene.aerosol.reference_wavelength_nm,
        .aerosol_angstrom_exponent = scene.aerosol.angstrom_exponent,
        .has_aerosol_profile_properties = context.aerosol_profile_layers.len != 0,
        .gas_optical_depth = means.gas_optical_depth,
        .cia_optical_depth = means.cia_optical_depth,
        .aerosol_optical_depth = means.aerosol_optical_depth,
        .aerosol_base_optical_depth = means.aerosol_base_optical_depth,
        .d_optical_depth_d_temperature = means.d_optical_depth_d_temperature,
        .depolarization_factor = means.depolarization_factor,
        .total_optical_depth = means.total_optical_depth,
        .interval_semantics = scene.atmosphere.interval_grid.semantics,
        .fit_interval_index_1based = scene.atmosphere.interval_grid.fit_interval_index_1based,
        .aerosol_phase_support = aerosol_phase_support,
        .aerosol_fraction_control = context.aerosol_fraction_control,
    };
    prepared.spectroscopy_plan_key = if (context.borrowed_spectroscopy_plan_key != 0)
        context.borrowed_spectroscopy_plan_key
    else
        prepared.computeSpectroscopyPlanKey();
    prepared.spectroscopy_profile_cache_inputs_key = if (context.borrowed_spectroscopy_profile_cache_inputs_key != 0)
        context.borrowed_spectroscopy_profile_cache_inputs_key
    else
        prepared.computeSpectroscopyProfileCacheInputsKey();

    context.layers = &.{};
    context.sublayers = &.{};
    context.continuum_points = &.{};
    context.owns_continuum_points = false;
    context.spectroscopy_profile_altitudes_km = &.{};
    context.spectroscopy_profile_pressures_hpa = &.{};
    context.spectroscopy_profile_temperatures_k = &.{};
    context.owns_spectroscopy_profile_arrays = false;
    context.collision_induced_absorption = null;
    context.owns_collision_induced_absorption = false;
    context.spectroscopy_lines = null;
    context.aerosol_fraction_control = .{};
    context.operational_o2_lut = .{};
    context.operational_o2o2_lut = .{};

    absorbers.owned_cross_section_absorbers = &.{};
    absorbers.owned_cross_section_absorber_count = 0;
    absorbers.owned_line_absorbers = &.{};
    absorbers.owned_line_absorber_count = 0;
    absorbers.strong_line_states = null;
    absorbers.strong_line_state_count = 0;
    absorbers.profile_strong_line_states = null;
    absorbers.profile_strong_line_state_count = 0;
    absorbers.profile_weak_line_states = null;
    absorbers.profile_weak_line_state_count = 0;
    absorbers.owns_profile_strong_line_states = true;
    absorbers.owns_profile_weak_line_states = true;
    absorbers.owned_lines = null;

    return prepared;
}
