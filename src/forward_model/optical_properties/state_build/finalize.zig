const Scene = @import("../../../input/Scene.zig").Scene;
const PhaseSupportKind = @import("../../../input/reference/airmass_phase.zig").PhaseSupportKind;
const Accumulation = @import("accumulation.zig");
const Absorbers = @import("absorbers.zig");
const Context = @import("context.zig").PreparationContext;
const State = @import("state.zig");

// finalize.zig -----------------------------------------------------------------------------------------------|
// One-way handoff from mutable optical-preparation storage to the stable PreparedOpticalState header. This    |
// file is the last step of Scene -> prepared optics: it copies scalar summaries, moves prepared rows and      |
// owned reference payloads, writes cache identity keys, and clears each moved-from owner before setup         |
// errdefer/deinit paths can run.                                                                              |
//                                                                                                             |
// called by                                                                                                   |
//   optical_properties/root.zig calls assemble after Context.init, Absorbers.build, and                       |
//   Accumulation.accumulate have all succeeded. instrument-grid simulation, O2 A reference setup,             |
//   diagnostics, and retrieval code then read through PreparedOpticalState; they never see Context or         |
//   AbsorberBuildState directly. prepared_state.zig owns the final deinit contract for the header built here. |
//                                                                                                             |
// incoming state                                                                                              |
//   Context            owns or borrows layer rows, sublayer rows, continuum/CIA payloads, profile arrays,     |
//                      aerosol fraction controls, and operational LUT copies.                                 |
//   AbsorberBuildState owns line/cross-section absorber rows, owned line lists, strong-line states, and       |
//                      profile spectroscopy state arrays.                                                     |
//   PreparedMeans      is a by-value summary of optical depths, thermodynamics, columns, and band means.      |
//   Scene              is borrowed; only scalar controls and semantics are copied into the final header.      |
//                                                                                                             |
// handoff order                                                                                               |
//   1. build the PreparedOpticalState header from copied scalars and moved owner/view headers                 |
//   2. compute missing spectroscopy cache keys from the assembled final state                                 |
//   3. clear moved Context and AbsorberBuildState owners so their deinit methods release only leftovers       |
//                                                                                                             |
// cache identity                                                                                              |
//   Prepared profile-cache routes can pass borrowed keys from reusable input state. When those keys are       |
//   absent, assemble computes keys after all moved line/LUT/profile fields have landed in                     |
//   PreparedOpticalState, so the cache identity hashes the exact retained state used later.                   |
//                                                                                                             |
// ownership                                                                                                   |
//   This file does not allocate, clone, or run wavelength-time physics. A field is either copied by value or  |
//   moved as an owner/view header into PreparedOpticalState. The reset block is part of correctness: removing |
//   it would make setup cleanup and PreparedOpticalState.deinit both believe they own the same buffers.       |
// ------------------------------------------------------------------------------------------------------------|

pub fn assemble(
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
    means: Accumulation.PreparedMeans,
) State.PreparedOpticalState {
    // assemble -----------------------------------------------------------------------------------------------|
    // Build the final prepared-state header and make the setup owners safe to deinitialize.                   |
    //                                                                                                         |
    // writes                                                                                                  |
    //   moved owners : layers, sublayers, continuum/CIA payloads, spectroscopy line lists, absorber rows,     |
    //                  profile arrays, strong/weak spectroscopy states, operational LUT handles               |
    //   copied values : scalar means, aerosol constants, interval semantics, fit interval                     |
    //   derived keys  : spectroscopy_plan_key and spectroscopy_profile_cache_inputs_key                       |
    //                                                                                                         |
    // ownership                                                                                               |
    //   After this returns, PreparedOpticalState owns the moved buffers. context and absorbers are left in a  |
    //   moved-from shape where their deinit methods can only release storage that was not transferred.        |
    //                                                                                                         |
    // cache keys                                                                                              |
    //   Borrowed keys win when profile-cache input supplied them. Otherwise the keys are computed from        |
    //   prepared after the moved rows are attached, so hashing sees the same state as later evaluators.       |
    // --------------------------------------------------------------------------------------------------------|

    const scene = context.scene;
    const aerosol_phase_support = if (scene.aerosol.enabled)
        PhaseSupportKind.analytic_hg
    else
        PhaseSupportKind.none;
    const mean_cross_section_cm2_per_molecule =
        means.cross_section_mean_cm2_per_molecule +
        means.line_means.line_mean_cross_section_cm2_per_molecule +
        means.line_means.line_mixing_mean_cross_section_cm2_per_molecule;
    const line_mixing_mean_cross_section_cm2_per_molecule =
        means.line_means.line_mixing_mean_cross_section_cm2_per_molecule;

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

        .mean_cross_section_cm2_per_molecule = mean_cross_section_cm2_per_molecule,
        .line_mean_cross_section_cm2_per_molecule = means.line_means.line_mean_cross_section_cm2_per_molecule,
        .line_mixing_mean_cross_section_cm2_per_molecule = line_mixing_mean_cross_section_cm2_per_molecule,
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
    const spectroscopy_plan_key = choose_spectroscopy_plan_key: {
        if (context.borrowed_spectroscopy_plan_key != 0) {
            break :choose_spectroscopy_plan_key context.borrowed_spectroscopy_plan_key;
        }

        break :choose_spectroscopy_plan_key prepared.computeSpectroscopyPlanKey();
    };
    prepared.spectroscopy_plan_key = spectroscopy_plan_key;

    const spectroscopy_profile_cache_inputs_key = choose_profile_cache_inputs_key: {
        if (context.borrowed_spectroscopy_profile_cache_inputs_key != 0) {
            break :choose_profile_cache_inputs_key context.borrowed_spectroscopy_profile_cache_inputs_key;
        }

        break :choose_profile_cache_inputs_key prepared.computeSpectroscopyProfileCacheInputsKey();
    };
    prepared.spectroscopy_profile_cache_inputs_key = spectroscopy_profile_cache_inputs_key;

    // moved-from reset ---------------------------------------------------------------------------------------|
    // Context.deinit and AbsorberBuildState.deinit still run after assemble returns. Clear every owner/view   |
    // header moved above so those cleanup paths cannot free buffers that now belong to PreparedOpticalState.  |
    // The bools are reset with the moved slices because ownership is encoded by header plus owns_* flag.      |
    // --------------------------------------------------------------------------------------------------------|

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
