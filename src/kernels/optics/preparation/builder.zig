//! Purpose:
//!   Build the prepared optical state consumed by transport and measurement
//!   evaluation.
//!
//! Physics:
//!   Resolves climatology, spectroscopy, continuum, aerosol, cloud, and
//!   pseudo-spherical preparation into the typed transport-ready carriers.
//!
//! Vendor:
//!   `optics preparation builder`
//!
//! Design:
//!   Keeps the preparation logic in a typed staging area so the transport
//!   kernels do not own file-driven selection or mutable global state.
//!
//! Invariants:
//!   Prepared layers, sublayers, and sidecar state must remain aligned with
//!   the scene's atmospheric and spectral grid.
//!
//! Validation:
//!   Optics-preparation transport tests and transport integration suites.

const std = @import("std");
const AbsorberModel = @import("../../../model/Absorber.zig");
const AtmosphereModel = @import("../../../model/Atmosphere.zig");
const Scene = @import("../../../model/Scene.zig").Scene;
const ReferenceData = @import("../../../model/ReferenceData.zig");
const Rayleigh = @import("../../../model/reference/rayleigh.zig");
const State = @import("state.zig");
const Spectroscopy = @import("spectroscopy.zig");
const BandMeans = @import("../prepare/band_means.zig");
const ParticleProfiles = @import("../prepare/particle_profiles.zig");
const PhaseFunctions = @import("../prepare/phase_functions.zig");

const Allocator = std.mem.Allocator;
const phase_coefficient_count = PhaseFunctions.phase_coefficient_count;
const oxygen_volume_mixing_ratio = 0.2095;
const centimeters_per_kilometer = 1.0e5;

const PreparedOpticalState = State.PreparedOpticalState;
const PreparedLayer = State.PreparedLayer;
const PreparedSublayer = State.PreparedSublayer;
const PreparedLineAbsorber = State.PreparedLineAbsorber;
const PreparedCrossSectionAbsorber = State.PreparedCrossSectionAbsorber;

/// Preparation inputs required to build the prepared optical state.
pub const PreparationInputs = struct {
    profile: *const ReferenceData.ClimatologyProfile,
    cross_sections: *const ReferenceData.CrossSectionTable,
    lut: *const ReferenceData.AirmassFactorLut,
    collision_induced_absorption: ?*const ReferenceData.CollisionInducedAbsorptionTable = null,
    spectroscopy_lines: ?*const ReferenceData.SpectroscopyLineList = null,
    aerosol_mie: ?*const ReferenceData.MiePhaseTable = null,
    cloud_mie: ?*const ReferenceData.MiePhaseTable = null,
};

/// Purpose:
///   Build the prepared optical state for one scene and input bundle.
///
/// Physics:
///   Stages the climatology, spectroscopy, aerosol, cloud, and continuum data
///   needed by the transport kernels.
pub fn prepare(
    allocator: Allocator,
    scene: *const Scene,
    inputs: PreparationInputs,
) !PreparedOpticalState {
    return prepareWithInputs(allocator, scene, inputs);
}

/// Purpose:
///   Stage the optical-preparation inputs into owned transport carriers.
///
/// Physics:
///   Builds the layer, sublayer, spectroscopy, and sidecar state that the
///   transport and measurement kernels reuse.
///
/// Vendor:
///   `optics preparation builder`
///
/// Inputs:
///   `scene` provides the resolved geometry and absorber layout, while
///   `inputs` supplies the climatology and spectroscopy references.
///
/// Outputs:
///   Returns the fully prepared optical state with owned layer and sidecar
///   storage.
///
/// Validation:
///   Optics-preparation transport tests and transport integration suites.
fn prepareWithInputs(
    allocator: Allocator,
    scene: *const Scene,
    inputs: PreparationInputs,
) !PreparedOpticalState {
    const profile = inputs.profile;
    const cross_sections = inputs.cross_sections;
    const collision_induced_absorption = inputs.collision_induced_absorption;
    const spectroscopy_lines = inputs.spectroscopy_lines;
    const lut = inputs.lut;
    const aerosol_mie = inputs.aerosol_mie;
    const cloud_mie = inputs.cloud_mie;

    try scene.validate();

    var vertical_grid = try buildVerticalGrid(allocator, scene, profile);
    defer vertical_grid.deinit(allocator);

    const layer_count: u32 = @intCast(vertical_grid.layer_top_altitudes_km.len);
    const total_sublayer_count = vertical_grid.sublayer_mid_altitudes_km.len;
    const layers = try allocator.alloc(PreparedLayer, layer_count);
    errdefer allocator.free(layers);
    const sublayers = try allocator.alloc(PreparedSublayer, total_sublayer_count);
    errdefer allocator.free(sublayers);
    const continuum_points = try allocator.dupe(ReferenceData.CrossSectionPoint, cross_sections.points);
    errdefer allocator.free(continuum_points);
    const owned_cia = if (collision_induced_absorption) |cia|
        try cia.clone(allocator)
    else
        null;
    errdefer if (owned_cia) |table| {
        var owned = table;
        owned.deinit(allocator);
    };
    var owned_lines = if (spectroscopy_lines) |line_list|
        try line_list.clone(allocator)
    else
        null;
    errdefer if (owned_lines) |line_list| {
        var owned = line_list;
        owned.deinit(allocator);
    };
    var aerosol_fraction_control = try scene.aerosol.fraction.clone(allocator);
    errdefer aerosol_fraction_control.deinitOwned(allocator);
    var cloud_fraction_control = try scene.cloud.fraction.clone(allocator);
    errdefer cloud_fraction_control.deinitOwned(allocator);
    const operational_o2_lut = scene.observation_model.o2_operational_lut;
    const operational_o2o2_lut = scene.observation_model.o2o2_operational_lut;
    const active_line_absorbers = try Spectroscopy.collectActiveLineAbsorbers(allocator, scene);
    defer allocator.free(active_line_absorbers);
    const active_cross_section_absorbers = try Spectroscopy.collectActiveCrossSectionAbsorbers(
        allocator,
        scene,
        cross_sections,
    );
    defer allocator.free(active_cross_section_absorbers);
    const single_active_line_absorber = if (active_line_absorbers.len == 1)
        active_line_absorbers[0]
    else
        null;

    var owned_cross_section_absorbers: []PreparedCrossSectionAbsorber = &.{};
    var owned_cross_section_absorber_count: usize = 0;
    errdefer if (owned_cross_section_absorbers.len != 0) {
        for (owned_cross_section_absorbers[0..owned_cross_section_absorber_count]) |*cross_section_absorber| {
            cross_section_absorber.deinit(allocator);
        }
        allocator.free(owned_cross_section_absorbers);
    };

    var owned_line_absorbers: []PreparedLineAbsorber = &.{};
    var owned_line_absorber_count: usize = 0;
    errdefer if (owned_line_absorbers.len != 0) {
        for (owned_line_absorbers[0..owned_line_absorber_count]) |*line_absorber| {
            line_absorber.deinit(allocator);
        }
        allocator.free(owned_line_absorbers);
    };

    if (active_cross_section_absorbers.len != 0) {
        owned_cross_section_absorbers = try allocator.alloc(
            PreparedCrossSectionAbsorber,
            active_cross_section_absorbers.len,
        );
        for (active_cross_section_absorbers, 0..) |cross_section_absorber, index| {
            const representation_kind = switch (cross_section_absorber.representation) {
                .xsec_table => if (cross_section_absorber.use_effective_cross_section)
                    State.CrossSectionRepresentationKind.effective_table
                else
                    State.CrossSectionRepresentationKind.table,
                .xsec_lut => if (cross_section_absorber.use_effective_cross_section)
                    State.CrossSectionRepresentationKind.effective_lut
                else
                    State.CrossSectionRepresentationKind.lut,
                .line_abs, .none => unreachable,
            };
            const representation = switch (cross_section_absorber.representation) {
                .xsec_table => |table| State.PreparedCrossSectionRepresentation{
                    .table = .{
                        .points = try allocator.dupe(ReferenceData.CrossSectionPoint, table.points),
                    },
                },
                .xsec_lut => |cross_section_lut| State.PreparedCrossSectionRepresentation{
                    .lut = try cross_section_lut.clone(allocator),
                },
                .line_abs, .none => unreachable,
            };
            errdefer switch (representation) {
                .table => |table| {
                    var owned = table;
                    owned.deinit(allocator);
                },
                .lut => |cross_section_lut| {
                    var owned = cross_section_lut;
                    owned.deinitOwned(allocator);
                },
            };
            const number_densities_cm3 = try allocator.alloc(f64, total_sublayer_count);
            errdefer allocator.free(number_densities_cm3);

            owned_cross_section_absorbers[index] = .{
                .species = cross_section_absorber.species,
                .representation_kind = representation_kind,
                .polynomial_order = cross_section_absorber.polynomial_order,
                .representation = representation,
                .number_densities_cm3 = number_densities_cm3,
            };
            @memset(owned_cross_section_absorbers[index].number_densities_cm3, 0.0);
            owned_cross_section_absorber_count += 1;
        }
    }

    if (owned_lines) |*line_list| {
        // DECISION:
        //   Clone the line list per active absorber when the runtime controls
        //   can diverge, especially when the operational O2 LUT is active.
        if (active_line_absorbers.len > 1 or (operational_o2_lut.enabled() and active_line_absorbers.len != 0)) {
            owned_line_absorbers = try allocator.alloc(PreparedLineAbsorber, active_line_absorbers.len);

            for (active_line_absorbers, 0..) |line_absorber, index| {
                var filtered = try line_list.clone(allocator);
                errdefer filtered.deinit(allocator);
                const use_operational_o2_lut = operational_o2_lut.enabled() and line_absorber.species == .o2;

                try filtered.applyRuntimeControls(
                    allocator,
                    if (line_absorber.species.hitranIndex()) |hitran_index|
                        @as(u16, hitran_index)
                    else
                        null,
                    line_absorber.controls.activeIsotopes(),
                    line_absorber.controls.activeThresholdLine(),
                    line_absorber.controls.activeCutoffCm1(),
                    if (line_absorber.species == .o2)
                        line_absorber.controls.activeLineMixingFactor()
                    else
                        0.0,
                );
                if (!use_operational_o2_lut and filtered.lines.len == 0) {
                    return error.InvalidRequest;
                }
                std.sort.pdq(
                    ReferenceData.SpectroscopyLine,
                    filtered.lines,
                    {},
                    struct {
                        fn lessThan(_: void, left: ReferenceData.SpectroscopyLine, right: ReferenceData.SpectroscopyLine) bool {
                            return left.center_wavelength_nm < right.center_wavelength_nm;
                        }
                    }.lessThan,
                );
                filtered.lines_sorted_ascending = true;
                if (!use_operational_o2_lut) {
                    try filtered.buildStrongLineMatchIndex(allocator);
                }
                const has_strong_line_states = !use_operational_o2_lut and filtered.hasStrongLineSidecars();
                // GOTCHA:
                //   Strong-line sidecars are only materialized when the
                //   operational O2 LUT is not replacing the line-by-line path.
                const strong_line_states = if (has_strong_line_states)
                    try allocator.alloc(ReferenceData.StrongLinePreparedState, total_sublayer_count)
                else
                    null;
                errdefer if (strong_line_states) |states| allocator.free(states);
                const strong_line_state_initialized = if (has_strong_line_states)
                    try allocator.alloc(bool, total_sublayer_count)
                else
                    null;
                errdefer if (strong_line_state_initialized) |initialized| allocator.free(initialized);

                owned_line_absorbers[index] = .{
                    .species = line_absorber.species,
                    .line_list = filtered,
                    .number_densities_cm3 = try allocator.alloc(f64, total_sublayer_count),
                    .strong_line_states = strong_line_states,
                    .strong_line_state_initialized = strong_line_state_initialized,
                };
                @memset(owned_line_absorbers[index].number_densities_cm3, 0.0);
                if (owned_line_absorbers[index].strong_line_state_initialized) |initialized| @memset(initialized, false);
                owned_line_absorber_count += 1;
            }

            var owned = line_list.*;
            owned.deinit(allocator);
            owned_lines = null;
        } else {
            if (single_active_line_absorber) |line_absorber| {
                try line_list.applyRuntimeControls(
                    allocator,
                    if (line_absorber.species.hitranIndex()) |hitran_index|
                        @as(u16, hitran_index)
                    else
                        null,
                    line_absorber.controls.activeIsotopes(),
                    line_absorber.controls.activeThresholdLine(),
                    line_absorber.controls.activeCutoffCm1(),
                    if (line_absorber.species == .o2)
                        line_absorber.controls.activeLineMixingFactor()
                    else
                        0.0,
                );
                if (!operational_o2_lut.enabled() and line_list.lines.len == 0) {
                    return error.InvalidRequest;
                }
            }
            std.sort.pdq(
                ReferenceData.SpectroscopyLine,
                line_list.lines,
                {},
                struct {
                    fn lessThan(_: void, left: ReferenceData.SpectroscopyLine, right: ReferenceData.SpectroscopyLine) bool {
                        return left.center_wavelength_nm < right.center_wavelength_nm;
                    }
                }.lessThan,
            );
            line_list.lines_sorted_ascending = true;
            if (!operational_o2_lut.enabled()) {
                try line_list.buildStrongLineMatchIndex(allocator);
            }
        }
    }
    const strong_line_states = if (owned_line_absorbers.len == 0)
        if (owned_lines) |line_list|
            if (!operational_o2_lut.enabled() and line_list.hasStrongLineSidecars())
                try allocator.alloc(ReferenceData.StrongLinePreparedState, total_sublayer_count)
            else
                null
        else
            null
    else
        null;
    var strong_line_state_count: usize = 0;
    errdefer if (strong_line_states) |states| {
        for (states[0..strong_line_state_count]) |*state| state.deinit(allocator);
        allocator.free(states);
    };

    const midpoint_nm = (scene.spectral_grid.start_nm + scene.spectral_grid.end_nm) * 0.5;
    const has_line_absorbers = single_active_line_absorber != null or owned_line_absorbers.len != 0;
    const active_line_species = if (owned_line_absorbers.len == 0)
        Spectroscopy.resolveActiveLineSpecies(single_active_line_absorber, owned_lines, operational_o2_lut)
    else
        null;
    const continuum_owner_species = Spectroscopy.resolveContinuumOwnerSpecies(
        active_line_species,
        owned_line_absorbers,
        operational_o2_lut,
    );
    const mean_sigma = if (owned_cross_section_absorbers.len == 0)
        cross_sections.meanSigmaInRange(
            scene.spectral_grid.start_nm,
            scene.spectral_grid.end_nm,
        )
    else
        0.0;
    const midpoint_continuum_sigma = if (owned_cross_section_absorbers.len == 0)
        cross_sections.interpolateSigma(midpoint_nm)
    else
        0.0;
    const air_mass_factor = lut.nearest(
        scene.geometry.solar_zenith_deg,
        scene.geometry.viewing_zenith_deg,
        scene.geometry.relative_azimuth_deg,
    );
    const base_single_scatter_albedo = PhaseFunctions.computeSingleScatterAlbedo(scene, midpoint_nm);

    var total_optical_depth: f64 = 0.0;
    var total_temperature_weighted: f64 = 0.0;
    var total_pressure_weighted: f64 = 0.0;
    var total_weight: f64 = 0.0;
    var air_column_density_factor: f64 = 0.0;
    var oxygen_column_density_factor: f64 = 0.0;
    var column_density_factor: f64 = 0.0;
    var cia_pair_path_factor_cm5: f64 = 0.0;
    var total_gas_optical_depth: f64 = 0.0;
    var total_cia_optical_depth: f64 = 0.0;
    var total_aerosol_optical_depth: f64 = 0.0;
    var total_aerosol_base_optical_depth: f64 = 0.0;
    var total_cloud_optical_depth: f64 = 0.0;
    var total_cloud_base_optical_depth: f64 = 0.0;
    var total_scattering_optical_depth: f64 = 0.0;
    var total_d_optical_depth_d_temperature: f64 = 0.0;
    var depolarization_weighted: f64 = 0.0;

    const aerosol_sublayer_distribution = try ParticleProfiles.buildAerosolSublayerDistribution(
        allocator,
        scene,
        vertical_grid.borrow(),
    );
    defer allocator.free(aerosol_sublayer_distribution);
    const cloud_sublayer_distribution = try ParticleProfiles.buildCloudSublayerDistribution(
        allocator,
        scene,
        vertical_grid.borrow(),
    );
    defer allocator.free(cloud_sublayer_distribution);
    const aerosol_mie_point = if (aerosol_mie) |table| table.interpolate(midpoint_nm) else null;
    const cloud_mie_point = if (cloud_mie) |table| table.interpolate(midpoint_nm) else null;
    const aerosol_phase_coefficients = if (aerosol_mie_point) |point| point.phase_coefficients else PhaseFunctions.hgPhaseCoefficients(scene.aerosol.asymmetry_factor);
    const cloud_phase_coefficients = if (cloud_mie_point) |point| point.phase_coefficients else PhaseFunctions.hgPhaseCoefficients(scene.cloud.asymmetry_factor);
    const aerosol_single_scatter_albedo = if (aerosol_mie_point) |point| point.single_scatter_albedo else scene.aerosol.single_scatter_albedo;
    const cloud_single_scatter_albedo = if (cloud_mie_point) |point| point.single_scatter_albedo else scene.cloud.single_scatter_albedo;
    const aerosol_extinction_scale = if (aerosol_mie_point) |point| point.extinction_scale else 1.0;
    const cloud_extinction_scale = if (cloud_mie_point) |point| point.extinction_scale else 1.0;
    const aerosol_fraction = if (scene.aerosol.fraction.enabled)
        scene.aerosol.fraction.valueAtWavelength(midpoint_nm)
    else if (scene.aerosol.enabled)
        @as(f64, 1.0)
    else
        @as(f64, 0.0);
    const cloud_fraction = if (scene.cloud.fraction.enabled)
        scene.cloud.fraction.valueAtWavelength(midpoint_nm)
    else if (scene.cloud.enabled)
        @as(f64, 1.0)
    else
        @as(f64, 0.0);

    var sublayer_write_index: usize = 0;
    for (layers, 0..) |*layer, index| {
        const layer_top_altitude_km = vertical_grid.layer_top_altitudes_km[index];
        const layer_bottom_altitude_km = vertical_grid.layer_bottom_altitudes_km[index];
        const layer_center_altitude_km = 0.5 * (layer_top_altitude_km + layer_bottom_altitude_km);
        const layer_top_pressure_hpa = vertical_grid.layer_top_pressures_hpa[index];
        const layer_bottom_pressure_hpa = vertical_grid.layer_bottom_pressures_hpa[index];
        const layer_sublayer_start_index = vertical_grid.layer_sublayer_starts[index];
        const layer_sublayer_count = vertical_grid.layer_sublayer_counts[index];
        const layer_interval_index_1based = vertical_grid.layer_interval_indices_1based[index];
        const layer_subcolumn_label = vertical_grid.layer_subcolumn_labels[index];
        const layer_thickness_km = @max(layer_top_altitude_km - layer_bottom_altitude_km, 1.0e-9);

        var layer_density_weight: f64 = 0.0;
        var layer_density_sum: f64 = 0.0;
        var layer_temperature_sum: f64 = 0.0;
        var layer_pressure_sum: f64 = 0.0;
        var layer_line_sigma_sum: f64 = 0.0;
        var layer_line_mixing_sum: f64 = 0.0;
        var layer_d_cross_section_sum: f64 = 0.0;
        var layer_gas_optical_depth: f64 = 0.0;
        var layer_gas_scattering_optical_depth: f64 = 0.0;
        var layer_cia_optical_depth: f64 = 0.0;
        var layer_aerosol_optical_depth: f64 = 0.0;
        var layer_aerosol_base_optical_depth: f64 = 0.0;
        var layer_cloud_optical_depth: f64 = 0.0;
        var layer_cloud_base_optical_depth: f64 = 0.0;

        for (0..layer_sublayer_count) |sublayer_index| {
            sublayer_write_index = @as(usize, layer_sublayer_start_index) + sublayer_index;
            const sublayer_top_altitude_km = vertical_grid.sublayer_top_altitudes_km[sublayer_write_index];
            const sublayer_bottom_altitude_km = vertical_grid.sublayer_bottom_altitudes_km[sublayer_write_index];
            const sublayer_top_pressure_hpa = vertical_grid.sublayer_top_pressures_hpa[sublayer_write_index];
            const sublayer_bottom_pressure_hpa = vertical_grid.sublayer_bottom_pressures_hpa[sublayer_write_index];
            const altitude_km = vertical_grid.sublayer_mid_altitudes_km[sublayer_write_index];
            const density = profile.interpolateDensity(altitude_km);
            const pressure = if (scene.atmosphere.interval_grid.enabled() and
                sublayer_top_pressure_hpa > 0.0 and
                sublayer_bottom_pressure_hpa > 0.0)
                @sqrt(sublayer_top_pressure_hpa * sublayer_bottom_pressure_hpa)
            else
                profile.interpolatePressure(altitude_km);
            const temperature = profile.interpolateTemperature(altitude_km);
            const sublayer_thickness_km = @max(sublayer_top_altitude_km - sublayer_bottom_altitude_km, 0.0);
            const sublayer_path_length_cm = @max(sublayer_thickness_km, 1.0e-9) * centimeters_per_kilometer;
            const sublayer_weight = sublayer_thickness_km / layer_thickness_km;
            const oxygen_mixing_ratio = Spectroscopy.speciesMixingRatioAtPressure(
                scene,
                .o2,
                &.{},
                pressure,
                oxygen_volume_mixing_ratio,
            ) orelse oxygen_volume_mixing_ratio;
            var absorber_density_cm3: f64 = 0.0;
            var cross_section_absorber_density_cm3: f64 = 0.0;
            var cross_section_optical_depth: f64 = 0.0;
            var cross_section_d_optical_depth_d_temperature: f64 = 0.0;
            for (owned_cross_section_absorbers, active_cross_section_absorbers) |*cross_section_absorber, active_absorber| {
                const absorber_mixing_ratio = Spectroscopy.speciesMixingRatioAtPressure(
                    scene,
                    cross_section_absorber.species,
                    active_absorber.volume_mixing_ratio_profile_ppmv,
                    pressure,
                    if (cross_section_absorber.species == .o2)
                        oxygen_volume_mixing_ratio
                    else
                        null,
                ) orelse return error.InvalidRequest;
                const absorber_density = density * absorber_mixing_ratio;
                cross_section_absorber.number_densities_cm3[sublayer_write_index] = absorber_density;
                cross_section_absorber_density_cm3 += absorber_density;
                if (absorber_density <= 0.0) continue;

                const sigma = cross_section_absorber.sigmaAt(midpoint_nm, temperature, pressure);
                const d_sigma_d_temperature = cross_section_absorber.dSigmaDTemperatureAt(midpoint_nm, temperature, pressure);
                cross_section_optical_depth += sigma * absorber_density * sublayer_path_length_cm;
                cross_section_d_optical_depth_d_temperature +=
                    d_sigma_d_temperature * absorber_density * sublayer_path_length_cm;
                cross_section_absorber.column_density_factor += absorber_density * sublayer_path_length_cm;
            }
            const spectroscopy_eval = if (owned_line_absorbers.len != 0) blk: {
                const delta_t = 0.5;
                var spectroscopy_weight: f64 = 0.0;
                var weighted: ReferenceData.SpectroscopyEvaluation = .{
                    .line_sigma_cm2_per_molecule = 0.0,
                    .line_mixing_sigma_cm2_per_molecule = 0.0,
                    .total_sigma_cm2_per_molecule = 0.0,
                    .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
                };

                if (operational_o2_lut.enabled()) {
                    const o2_density_cm3 = density * oxygen_mixing_ratio;
                    absorber_density_cm3 += o2_density_cm3;
                    if (o2_density_cm3 > 0.0) {
                        const o2_evaluation = Spectroscopy.operationalO2EvaluationAtWavelength(
                            operational_o2_lut,
                            midpoint_nm,
                            temperature,
                            pressure,
                        );
                        spectroscopy_weight += o2_density_cm3;
                        weighted.weak_line_sigma_cm2_per_molecule +=
                            o2_evaluation.weak_line_sigma_cm2_per_molecule * o2_density_cm3;
                        weighted.strong_line_sigma_cm2_per_molecule +=
                            o2_evaluation.strong_line_sigma_cm2_per_molecule * o2_density_cm3;
                        weighted.line_sigma_cm2_per_molecule +=
                            o2_evaluation.line_sigma_cm2_per_molecule * o2_density_cm3;
                        weighted.line_mixing_sigma_cm2_per_molecule +=
                            o2_evaluation.line_mixing_sigma_cm2_per_molecule * o2_density_cm3;
                        weighted.total_sigma_cm2_per_molecule +=
                            o2_evaluation.total_sigma_cm2_per_molecule * o2_density_cm3;
                        weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
                            o2_evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * o2_density_cm3;
                    }
                }

                for (owned_line_absorbers, active_line_absorbers, 0..) |*line_absorber, active_absorber, line_absorber_index| {
                    if (operational_o2_lut.enabled() and line_absorber.species == .o2) {
                        line_absorber.number_densities_cm3[sublayer_write_index] = 0.0;
                        _ = line_absorber_index;
                        continue;
                    }
                    const absorber_mixing_ratio = Spectroscopy.speciesMixingRatioAtPressure(
                        scene,
                        line_absorber.species,
                        active_absorber.volume_mixing_ratio_profile_ppmv,
                        pressure,
                        if (line_absorber.species == .o2)
                            oxygen_volume_mixing_ratio
                        else
                            null,
                    ) orelse return error.InvalidRequest;
                    const line_absorber_density_cm3 = density * absorber_mixing_ratio;
                    line_absorber.number_densities_cm3[sublayer_write_index] = line_absorber_density_cm3;
                    absorber_density_cm3 += line_absorber_density_cm3;
                    if (line_absorber_density_cm3 <= 0.0) continue;

                    var evaluation = if (line_absorber.strong_line_states) |states| blk_eval: {
                        states[sublayer_write_index] = (try line_absorber.line_list.prepareStrongLineState(
                            allocator,
                            temperature,
                            pressure,
                        )).?;
                        line_absorber.strong_line_state_initialized.?[sublayer_write_index] = true;
                        line_absorber.strong_line_state_count += 1;
                        const prepared_evaluation = line_absorber.line_list.evaluateAtPrepared(
                            midpoint_nm,
                            temperature,
                            pressure,
                            &states[sublayer_write_index],
                        );
                        break :blk_eval prepared_evaluation;
                    } else line_absorber.line_list.evaluateAt(midpoint_nm, temperature, pressure);

                    const upper = line_absorber.line_list.evaluateAt(midpoint_nm, temperature + delta_t, pressure);
                    const lower = line_absorber.line_list.evaluateAt(
                        midpoint_nm,
                        @max(temperature - delta_t, 150.0),
                        pressure,
                    );
                    evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k =
                        (upper.total_sigma_cm2_per_molecule - lower.total_sigma_cm2_per_molecule) / (2.0 * delta_t);

                    spectroscopy_weight += line_absorber_density_cm3;
                    weighted.weak_line_sigma_cm2_per_molecule += evaluation.weak_line_sigma_cm2_per_molecule * line_absorber_density_cm3;
                    weighted.strong_line_sigma_cm2_per_molecule += evaluation.strong_line_sigma_cm2_per_molecule * line_absorber_density_cm3;
                    weighted.line_sigma_cm2_per_molecule += evaluation.line_sigma_cm2_per_molecule * line_absorber_density_cm3;
                    weighted.line_mixing_sigma_cm2_per_molecule += evaluation.line_mixing_sigma_cm2_per_molecule * line_absorber_density_cm3;
                    weighted.total_sigma_cm2_per_molecule += evaluation.total_sigma_cm2_per_molecule * line_absorber_density_cm3;
                    weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
                        evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * line_absorber_density_cm3;

                    const line_absorber_column_density_cm2 = line_absorber_density_cm3 * sublayer_path_length_cm;
                    line_absorber.column_density_factor += line_absorber_column_density_cm2;
                    _ = line_absorber_index;
                }

                if (spectroscopy_weight <= 0.0) {
                    break :blk ReferenceData.SpectroscopyEvaluation{
                        .line_sigma_cm2_per_molecule = 0.0,
                        .line_mixing_sigma_cm2_per_molecule = 0.0,
                        .total_sigma_cm2_per_molecule = 0.0,
                        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
                    };
                }

                weighted.weak_line_sigma_cm2_per_molecule /= spectroscopy_weight;
                weighted.strong_line_sigma_cm2_per_molecule /= spectroscopy_weight;
                weighted.line_sigma_cm2_per_molecule /= spectroscopy_weight;
                weighted.line_mixing_sigma_cm2_per_molecule /= spectroscopy_weight;
                weighted.total_sigma_cm2_per_molecule /= spectroscopy_weight;
                weighted.d_sigma_d_temperature_cm2_per_molecule_per_k /= spectroscopy_weight;
                break :blk weighted;
            } else blk: {
                const absorber_mixing_ratio = if (active_line_species) |species|
                    Spectroscopy.speciesMixingRatioAtPressure(
                        scene,
                        species,
                        if (single_active_line_absorber) |line_absorber| line_absorber.volume_mixing_ratio_profile_ppmv else &.{},
                        pressure,
                        if (species == .o2)
                            oxygen_volume_mixing_ratio
                        else
                            null,
                    ) orelse oxygen_volume_mixing_ratio
                else
                    oxygen_volume_mixing_ratio;
                absorber_density_cm3 = density * absorber_mixing_ratio;

                if (operational_o2_lut.enabled()) {
                    const sigma = operational_o2_lut.sigmaAt(midpoint_nm, temperature, pressure);
                    break :blk ReferenceData.SpectroscopyEvaluation{
                        .weak_line_sigma_cm2_per_molecule = sigma,
                        .strong_line_sigma_cm2_per_molecule = 0.0,
                        .line_sigma_cm2_per_molecule = sigma,
                        .line_mixing_sigma_cm2_per_molecule = 0.0,
                        .total_sigma_cm2_per_molecule = sigma,
                        .d_sigma_d_temperature_cm2_per_molecule_per_k = operational_o2_lut.dSigmaDTemperatureAt(midpoint_nm, temperature, pressure),
                    };
                }

                if (owned_lines) |line_list| {
                    if (strong_line_states) |states| {
                        const delta_t = 0.5;
                        states[sublayer_write_index] = (try line_list.prepareStrongLineState(
                            allocator,
                            temperature,
                            pressure,
                        )).?;
                        strong_line_state_count += 1;

                        var evaluation = line_list.evaluateAtPrepared(
                            midpoint_nm,
                            temperature,
                            pressure,
                            &states[sublayer_write_index],
                        );
                        const upper = line_list.evaluateAt(midpoint_nm, temperature + delta_t, pressure);
                        const lower = line_list.evaluateAt(
                            midpoint_nm,
                            @max(temperature - delta_t, 150.0),
                            pressure,
                        );
                        evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k =
                            (upper.total_sigma_cm2_per_molecule - lower.total_sigma_cm2_per_molecule) / (2.0 * delta_t);
                        break :blk evaluation;
                    }
                    break :blk line_list.evaluateAt(midpoint_nm, temperature, pressure);
                }

                break :blk ReferenceData.SpectroscopyEvaluation{
                    .weak_line_sigma_cm2_per_molecule = 0.0,
                    .strong_line_sigma_cm2_per_molecule = 0.0,
                    .line_sigma_cm2_per_molecule = 0.0,
                    .line_mixing_sigma_cm2_per_molecule = 0.0,
                    .total_sigma_cm2_per_molecule = 0.0,
                    .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
                };
            };
            const o2_density_cm3 = density * oxygen_mixing_ratio;
            const continuum_density_cm3 = if (owned_cross_section_absorbers.len != 0)
                0.0
            else if (owned_line_absorbers.len != 0) blk: {
                const owner_species = continuum_owner_species orelse break :blk absorber_density_cm3;
                if (operational_o2_lut.enabled() and owner_species == .o2) break :blk o2_density_cm3;
                for (owned_line_absorbers) |line_absorber| {
                    if (line_absorber.species != owner_species) continue;
                    break :blk line_absorber.number_densities_cm3[sublayer_write_index];
                }
                break :blk absorber_density_cm3;
            } else absorber_density_cm3;
            const total_gas_density_cm3 = if (owned_cross_section_absorbers.len != 0 and !has_line_absorbers)
                cross_section_absorber_density_cm3
            else
                absorber_density_cm3 + cross_section_absorber_density_cm3;
            const total_gas_column_density_cm2 = total_gas_density_cm3 * sublayer_path_length_cm;
            const line_gas_column_density_cm2 = absorber_density_cm3 * sublayer_path_length_cm;
            const continuum_column_density_cm2 = continuum_density_cm3 * sublayer_path_length_cm;
            const molecular_gas_optical_depth =
                midpoint_continuum_sigma * continuum_column_density_cm2 +
                spectroscopy_eval.total_sigma_cm2_per_molecule * line_gas_column_density_cm2 +
                cross_section_optical_depth;
            const cia_sigma_cm5_per_molecule2 = if (operational_o2o2_lut.enabled())
                operational_o2o2_lut.sigmaAt(midpoint_nm, temperature, pressure)
            else if (collision_induced_absorption) |cia_table|
                cia_table.sigmaAt(midpoint_nm, temperature)
            else
                0.0;
            const d_cia_sigma_d_temperature = if (operational_o2o2_lut.enabled())
                operational_o2o2_lut.dSigmaDTemperatureAt(midpoint_nm, temperature, pressure)
            else if (collision_induced_absorption) |cia_table|
                cia_table.dSigmaDTemperatureAt(midpoint_nm, temperature)
            else
                0.0;
            const cia_optical_depth = cia_sigma_cm5_per_molecule2 * o2_density_cm3 * o2_density_cm3 * sublayer_path_length_cm;
            const gas_scattering_optical_depth = Rayleigh.scatteringOpticalDepthForColumn(
                midpoint_nm,
                density * sublayer_path_length_cm,
            );
            const gas_absorption_optical_depth = molecular_gas_optical_depth;
            const gas_extinction_optical_depth = gas_absorption_optical_depth + cia_optical_depth + gas_scattering_optical_depth;
            const d_cia_optical_depth_d_temperature = d_cia_sigma_d_temperature * o2_density_cm3 * o2_density_cm3 * sublayer_path_length_cm;
            const d_gas_optical_depth_d_temperature =
                spectroscopy_eval.d_sigma_d_temperature_cm2_per_molecule_per_k * line_gas_column_density_cm2 +
                cross_section_d_optical_depth_d_temperature;
            const aerosol_base_optical_depth = aerosol_sublayer_distribution[sublayer_write_index] * aerosol_extinction_scale;
            const cloud_base_optical_depth = cloud_sublayer_distribution[sublayer_write_index] * cloud_extinction_scale;
            const aerosol_optical_depth = aerosol_base_optical_depth * aerosol_fraction;
            const cloud_optical_depth = cloud_base_optical_depth * cloud_fraction;
            const aerosol_scattering_optical_depth = aerosol_optical_depth * aerosol_single_scatter_albedo;
            const cloud_scattering_optical_depth = cloud_optical_depth * cloud_single_scatter_albedo;
            const combined_phase_coefficients = PhaseFunctions.combinePhaseCoefficients(
                gas_scattering_optical_depth,
                aerosol_scattering_optical_depth,
                cloud_scattering_optical_depth,
                aerosol_phase_coefficients,
                cloud_phase_coefficients,
            );

            sublayers[sublayer_write_index] = .{
                .parent_layer_index = @intCast(index),
                .sublayer_index = @intCast(sublayer_index),
                .global_sublayer_index = @intCast(sublayer_write_index),
                .altitude_km = altitude_km,
                .pressure_hpa = pressure,
                .temperature_k = temperature,
                .number_density_cm3 = density,
                .oxygen_number_density_cm3 = density * oxygen_mixing_ratio,
                .absorber_number_density_cm3 = total_gas_density_cm3,
                .path_length_cm = sublayer_path_length_cm,
                .continuum_cross_section_cm2_per_molecule = if (owned_cross_section_absorbers.len == 0)
                    midpoint_continuum_sigma
                else
                    0.0,
                .line_cross_section_cm2_per_molecule = spectroscopy_eval.line_sigma_cm2_per_molecule,
                .line_mixing_cross_section_cm2_per_molecule = spectroscopy_eval.line_mixing_sigma_cm2_per_molecule,
                .cia_sigma_cm5_per_molecule2 = cia_sigma_cm5_per_molecule2,
                .cia_optical_depth = cia_optical_depth,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = spectroscopy_eval.d_sigma_d_temperature_cm2_per_molecule_per_k,
                .gas_absorption_optical_depth = gas_absorption_optical_depth,
                .gas_scattering_optical_depth = gas_scattering_optical_depth,
                .gas_extinction_optical_depth = gas_extinction_optical_depth,
                .d_gas_optical_depth_d_temperature = d_gas_optical_depth_d_temperature,
                .d_cia_optical_depth_d_temperature = d_cia_optical_depth_d_temperature,
                .aerosol_optical_depth = aerosol_optical_depth,
                .aerosol_base_optical_depth = aerosol_base_optical_depth,
                .cloud_optical_depth = cloud_optical_depth,
                .cloud_base_optical_depth = cloud_base_optical_depth,
                .aerosol_single_scatter_albedo = aerosol_single_scatter_albedo,
                .cloud_single_scatter_albedo = cloud_single_scatter_albedo,
                .aerosol_phase_coefficients = aerosol_phase_coefficients,
                .cloud_phase_coefficients = cloud_phase_coefficients,
                .combined_phase_coefficients = combined_phase_coefficients,
                .top_altitude_km = sublayer_top_altitude_km,
                .bottom_altitude_km = sublayer_bottom_altitude_km,
                .top_pressure_hpa = sublayer_top_pressure_hpa,
                .bottom_pressure_hpa = sublayer_bottom_pressure_hpa,
                .interval_index_1based = vertical_grid.sublayer_interval_indices_1based[sublayer_write_index],
                .subcolumn_label = vertical_grid.sublayer_subcolumn_labels[sublayer_write_index],
                .aerosol_fraction = aerosol_fraction,
                .cloud_fraction = cloud_fraction,
            };
            layer_density_weight += density * sublayer_weight;
            layer_density_sum += density * sublayer_weight;
            layer_temperature_sum += temperature * density * sublayer_weight;
            layer_pressure_sum += pressure * density * sublayer_weight;
            layer_line_sigma_sum += spectroscopy_eval.line_sigma_cm2_per_molecule;
            layer_line_mixing_sum += spectroscopy_eval.line_mixing_sigma_cm2_per_molecule;
            layer_d_cross_section_sum += spectroscopy_eval.d_sigma_d_temperature_cm2_per_molecule_per_k;
            layer_gas_optical_depth += gas_absorption_optical_depth + gas_scattering_optical_depth;
            layer_gas_scattering_optical_depth += gas_scattering_optical_depth;
            layer_cia_optical_depth += cia_optical_depth;
            layer_aerosol_optical_depth += aerosol_optical_depth;
            layer_aerosol_base_optical_depth += aerosol_base_optical_depth;
            layer_cloud_optical_depth += cloud_optical_depth;
            layer_cloud_base_optical_depth += cloud_base_optical_depth;
            air_column_density_factor += density * sublayer_path_length_cm;
            oxygen_column_density_factor += o2_density_cm3 * sublayer_path_length_cm;
            column_density_factor += total_gas_column_density_cm2;
            cia_pair_path_factor_cm5 += o2_density_cm3 * o2_density_cm3 * sublayer_path_length_cm;
            total_d_optical_depth_d_temperature += d_gas_optical_depth_d_temperature + d_cia_optical_depth_d_temperature;
        }

        const density = layer_density_sum;
        const temperature = if (layer_density_weight == 0.0) 0.0 else layer_temperature_sum / layer_density_weight;
        const pressure = if (layer_density_weight == 0.0) 0.0 else layer_pressure_sum / layer_density_weight;
        const gas_optical_depth = layer_gas_optical_depth;
        const aerosol_optical_depth = layer_aerosol_optical_depth;
        const aerosol_base_optical_depth = layer_aerosol_base_optical_depth;
        const cloud_optical_depth = layer_cloud_optical_depth;
        const cloud_base_optical_depth = layer_cloud_base_optical_depth;
        const optical_depth = gas_optical_depth + layer_cia_optical_depth + aerosol_optical_depth + cloud_optical_depth;
        const aerosol_scattering = aerosol_optical_depth * aerosol_single_scatter_albedo;
        const cloud_scattering = cloud_optical_depth * cloud_single_scatter_albedo;
        const gas_scattering = layer_gas_scattering_optical_depth;
        const scattering = aerosol_scattering + cloud_scattering + gas_scattering;
        const absorption = @max(optical_depth - scattering, 1e-9);
        const layer_single_scatter_albedo = scattering / @max(scattering + absorption, 1e-9);
        const depolarization = PhaseFunctions.computeLayerDepolarization(scene, gas_scattering, aerosol_scattering, cloud_scattering);
        total_optical_depth += optical_depth;
        total_temperature_weighted += temperature * density;
        total_pressure_weighted += pressure * density;
        total_weight += density;
        total_gas_optical_depth += gas_optical_depth;
        total_cia_optical_depth += layer_cia_optical_depth;
        total_aerosol_optical_depth += aerosol_optical_depth;
        total_aerosol_base_optical_depth += aerosol_base_optical_depth;
        total_cloud_optical_depth += cloud_optical_depth;
        total_cloud_base_optical_depth += cloud_base_optical_depth;
        total_scattering_optical_depth += scattering;
        depolarization_weighted += depolarization * optical_depth;

        layer.* = .{
            .layer_index = @intCast(index),
            .sublayer_start_index = layer_sublayer_start_index,
            .sublayer_count = layer_sublayer_count,
            .altitude_km = layer_center_altitude_km,
            .pressure_hpa = pressure,
            .temperature_k = temperature,
            .number_density_cm3 = density,
            .continuum_cross_section_cm2_per_molecule = mean_sigma,
            .line_cross_section_cm2_per_molecule = layer_line_sigma_sum / @as(f64, @floatFromInt(@max(layer_sublayer_count, 1))),
            .line_mixing_cross_section_cm2_per_molecule = layer_line_mixing_sum / @as(f64, @floatFromInt(@max(layer_sublayer_count, 1))),
            .cia_optical_depth = layer_cia_optical_depth,
            .d_cross_section_d_temperature_cm2_per_molecule_per_k = layer_d_cross_section_sum / @as(f64, @floatFromInt(@max(layer_sublayer_count, 1))),
            .gas_optical_depth = gas_optical_depth,
            .gas_scattering_optical_depth = gas_scattering,
            .aerosol_optical_depth = aerosol_optical_depth,
            .aerosol_base_optical_depth = aerosol_base_optical_depth,
            .cloud_optical_depth = cloud_optical_depth,
            .cloud_base_optical_depth = cloud_base_optical_depth,
            .layer_single_scatter_albedo = layer_single_scatter_albedo,
            .depolarization_factor = depolarization,
            .optical_depth = optical_depth,
            .top_altitude_km = layer_top_altitude_km,
            .bottom_altitude_km = layer_bottom_altitude_km,
            .top_pressure_hpa = layer_top_pressure_hpa,
            .bottom_pressure_hpa = layer_bottom_pressure_hpa,
            .interval_index_1based = layer_interval_index_1based,
            .subcolumn_label = layer_subcolumn_label,
            .aerosol_fraction = aerosol_fraction,
            .cloud_fraction = cloud_fraction,
        };
    }

    const effective_temperature = if (total_weight == 0.0) 0.0 else total_temperature_weighted / total_weight;
    const effective_pressure = if (total_weight == 0.0) 0.0 else total_pressure_weighted / total_weight;
    const cross_section_mean = if (owned_cross_section_absorbers.len != 0) blk: {
        var cross_section_total_weight: f64 = 0.0;
        var weighted_mean: f64 = 0.0;
        for (owned_cross_section_absorbers) |*cross_section_absorber| {
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
    } else mean_sigma;
    const line_means = if (owned_line_absorbers.len != 0 or operational_o2_lut.enabled()) blk: {
        var line_mean_weight: f64 = 0.0;
        var weighted: BandMeans.LineBandMeans = .{};
        if (operational_o2_lut.enabled() and oxygen_column_density_factor > 0.0) {
            const operational_mean = BandMeans.computeOperationalBandMean(
                scene,
                operational_o2_lut,
                effective_temperature,
                effective_pressure,
            );
            line_mean_weight += oxygen_column_density_factor;
            weighted.line_mean_cross_section_cm2_per_molecule += operational_mean * oxygen_column_density_factor;
        }
        for (owned_line_absorbers) |*line_absorber| {
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
    } else if (owned_lines) |*line_list|
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
    else if (collision_induced_absorption) |cia_table|
        cia_table.meanSigmaInRange(
            scene.spectral_grid.start_nm,
            scene.spectral_grid.end_nm,
            @max(effective_temperature, 150.0),
        )
    else
        0.0;

    return .{
        .layers = layers,
        .sublayers = sublayers,
        .strong_line_states = strong_line_states,
        .continuum_points = continuum_points,
        .collision_induced_absorption = owned_cia,
        .spectroscopy_lines = owned_lines,
        .cross_section_absorbers = owned_cross_section_absorbers,
        .line_absorbers = owned_line_absorbers,
        .continuum_owner_species = continuum_owner_species,
        .operational_o2_lut = operational_o2_lut,
        .operational_o2o2_lut = operational_o2o2_lut,
        .mean_cross_section_cm2_per_molecule = cross_section_mean + line_means.line_mean_cross_section_cm2_per_molecule + line_means.line_mixing_mean_cross_section_cm2_per_molecule,
        .line_mean_cross_section_cm2_per_molecule = line_means.line_mean_cross_section_cm2_per_molecule,
        .line_mixing_mean_cross_section_cm2_per_molecule = line_means.line_mixing_mean_cross_section_cm2_per_molecule,
        .cia_mean_cross_section_cm5_per_molecule2 = cia_mean_sigma,
        .effective_air_mass_factor = air_mass_factor,
        .effective_single_scatter_albedo = if (total_optical_depth == 0.0)
            base_single_scatter_albedo
        else
            total_scattering_optical_depth / total_optical_depth,
        .aerosol_single_scatter_albedo = aerosol_single_scatter_albedo,
        .cloud_single_scatter_albedo = cloud_single_scatter_albedo,
        .effective_temperature_k = effective_temperature,
        .effective_pressure_hpa = effective_pressure,
        .air_column_density_factor = air_column_density_factor,
        .oxygen_column_density_factor = oxygen_column_density_factor,
        .column_density_factor = column_density_factor,
        .cia_pair_path_factor_cm5 = cia_pair_path_factor_cm5,
        .aerosol_reference_wavelength_nm = scene.aerosol.reference_wavelength_nm,
        .aerosol_angstrom_exponent = scene.aerosol.angstrom_exponent,
        .cloud_reference_wavelength_nm = scene.cloud.reference_wavelength_nm,
        .cloud_angstrom_exponent = scene.cloud.angstrom_exponent,
        .gas_optical_depth = total_gas_optical_depth,
        .cia_optical_depth = total_cia_optical_depth,
        .aerosol_optical_depth = total_aerosol_optical_depth,
        .aerosol_base_optical_depth = total_aerosol_base_optical_depth,
        .cloud_optical_depth = total_cloud_optical_depth,
        .cloud_base_optical_depth = total_cloud_base_optical_depth,
        .d_optical_depth_d_temperature = total_d_optical_depth_d_temperature,
        .depolarization_factor = if (total_optical_depth == 0.0) 0.0 else depolarization_weighted / total_optical_depth,
        .total_optical_depth = total_optical_depth,
        .interval_semantics = scene.atmosphere.interval_grid.semantics,
        .fit_interval_index_1based = scene.atmosphere.interval_grid.fit_interval_index_1based,
        .subcolumn_semantics_enabled = scene.atmosphere.subcolumns.enabled,
        .aerosol_phase_support = if (aerosol_mie != null) .mie_table else if (scene.aerosol.enabled) .analytic_hg else .none,
        .cloud_phase_support = if (cloud_mie != null) .mie_table else if (scene.cloud.enabled) .analytic_hg else .none,
        .aerosol_fraction_control = aerosol_fraction_control,
        .cloud_fraction_control = cloud_fraction_control,
    };
}

const OwnedVerticalGrid = struct {
    layer_top_altitudes_km: []f64,
    layer_bottom_altitudes_km: []f64,
    layer_top_pressures_hpa: []f64,
    layer_bottom_pressures_hpa: []f64,
    layer_interval_indices_1based: []u32,
    layer_sublayer_starts: []u32,
    layer_sublayer_counts: []u32,
    layer_subcolumn_labels: []AtmosphereModel.PartitionLabel,
    sublayer_top_altitudes_km: []f64,
    sublayer_bottom_altitudes_km: []f64,
    sublayer_top_pressures_hpa: []f64,
    sublayer_bottom_pressures_hpa: []f64,
    sublayer_mid_altitudes_km: []f64,
    sublayer_interval_indices_1based: []u32,
    sublayer_subcolumn_labels: []AtmosphereModel.PartitionLabel,

    fn borrow(self: *const OwnedVerticalGrid) ParticleProfiles.PreparedVerticalGrid {
        return .{
            .layer_top_altitudes_km = self.layer_top_altitudes_km,
            .layer_bottom_altitudes_km = self.layer_bottom_altitudes_km,
            .layer_interval_indices_1based = self.layer_interval_indices_1based,
            .sublayer_top_altitudes_km = self.sublayer_top_altitudes_km,
            .sublayer_bottom_altitudes_km = self.sublayer_bottom_altitudes_km,
            .sublayer_mid_altitudes_km = self.sublayer_mid_altitudes_km,
            .sublayer_parent_interval_indices_1based = self.sublayer_interval_indices_1based,
        };
    }

    fn deinit(self: *OwnedVerticalGrid, allocator: Allocator) void {
        allocator.free(self.layer_top_altitudes_km);
        allocator.free(self.layer_bottom_altitudes_km);
        allocator.free(self.layer_top_pressures_hpa);
        allocator.free(self.layer_bottom_pressures_hpa);
        allocator.free(self.layer_interval_indices_1based);
        allocator.free(self.layer_sublayer_starts);
        allocator.free(self.layer_sublayer_counts);
        allocator.free(self.layer_subcolumn_labels);
        allocator.free(self.sublayer_top_altitudes_km);
        allocator.free(self.sublayer_bottom_altitudes_km);
        allocator.free(self.sublayer_top_pressures_hpa);
        allocator.free(self.sublayer_bottom_pressures_hpa);
        allocator.free(self.sublayer_mid_altitudes_km);
        allocator.free(self.sublayer_interval_indices_1based);
        allocator.free(self.sublayer_subcolumn_labels);
        self.* = undefined;
    }
};

fn buildVerticalGrid(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
) !OwnedVerticalGrid {
    if (scene.atmosphere.interval_grid.enabled()) {
        return buildExplicitVerticalGrid(allocator, scene, profile);
    }
    return buildLegacyVerticalGrid(allocator, scene, profile);
}

fn buildExplicitVerticalGrid(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
) !OwnedVerticalGrid {
    const intervals = scene.atmosphere.interval_grid.intervals;
    const layer_count = intervals.len;
    var total_sublayer_count: usize = 0;
    for (intervals) |interval| total_sublayer_count += interval.altitude_divisions;

    var grid = try allocateVerticalGrid(allocator, layer_count, total_sublayer_count);
    errdefer grid.deinit(allocator);

    var sublayer_cursor: usize = 0;
    var source_interval_index = intervals.len;
    var output_layer_index: usize = 0;
    while (source_interval_index > 0) : (output_layer_index += 1) {
        source_interval_index -= 1;
        const interval = intervals[source_interval_index];
        const index = output_layer_index;
        const has_altitude_bounds = interval.hasAltitudeBounds();
        const layer_top_altitude_km = if (has_altitude_bounds)
            interval.top_altitude_km
        else
            profile.interpolateAltitudeForPressure(interval.top_pressure_hpa);
        const layer_bottom_altitude_km = if (has_altitude_bounds)
            interval.bottom_altitude_km
        else
            profile.interpolateAltitudeForPressure(interval.bottom_pressure_hpa);

        grid.layer_top_altitudes_km[index] = layer_top_altitude_km;
        grid.layer_bottom_altitudes_km[index] = layer_bottom_altitude_km;
        grid.layer_top_pressures_hpa[index] = interval.top_pressure_hpa;
        grid.layer_bottom_pressures_hpa[index] = interval.bottom_pressure_hpa;
        grid.layer_interval_indices_1based[index] = interval.index_1based;
        grid.layer_sublayer_starts[index] = @intCast(sublayer_cursor);
        grid.layer_sublayer_counts[index] = interval.altitude_divisions;
        grid.layer_subcolumn_labels[index] = scene.atmosphere.subcolumns.labelForAltitude(
            0.5 * (layer_top_altitude_km + layer_bottom_altitude_km),
        );

        const log_bottom_pressure = @log(@max(interval.bottom_pressure_hpa, 1.0e-9));
        const log_top_pressure = @log(@max(interval.top_pressure_hpa, 1.0e-9));
        const layer_altitude_span_km = layer_top_altitude_km - layer_bottom_altitude_km;
        for (0..interval.altitude_divisions) |sublayer_index| {
            const bottom_fraction = @as(f64, @floatFromInt(sublayer_index)) / @as(f64, @floatFromInt(interval.altitude_divisions));
            const top_fraction = @as(f64, @floatFromInt(sublayer_index + 1)) / @as(f64, @floatFromInt(interval.altitude_divisions));
            const bottom_pressure_hpa = @exp(log_bottom_pressure + (log_top_pressure - log_bottom_pressure) * bottom_fraction);
            const top_pressure_hpa = @exp(log_bottom_pressure + (log_top_pressure - log_bottom_pressure) * top_fraction);
            const bottom_altitude_km = if (has_altitude_bounds)
                layer_bottom_altitude_km + layer_altitude_span_km * bottom_fraction
            else
                profile.interpolateAltitudeForPressure(bottom_pressure_hpa);
            const top_altitude_km = if (has_altitude_bounds)
                layer_bottom_altitude_km + layer_altitude_span_km * top_fraction
            else
                profile.interpolateAltitudeForPressure(top_pressure_hpa);
            const global_index = sublayer_cursor + sublayer_index;
            grid.sublayer_top_altitudes_km[global_index] = top_altitude_km;
            grid.sublayer_bottom_altitudes_km[global_index] = bottom_altitude_km;
            grid.sublayer_top_pressures_hpa[global_index] = top_pressure_hpa;
            grid.sublayer_bottom_pressures_hpa[global_index] = bottom_pressure_hpa;
            grid.sublayer_mid_altitudes_km[global_index] = 0.5 * (top_altitude_km + bottom_altitude_km);
            grid.sublayer_interval_indices_1based[global_index] = interval.index_1based;
            grid.sublayer_subcolumn_labels[global_index] = scene.atmosphere.subcolumns.labelForAltitude(
                grid.sublayer_mid_altitudes_km[global_index],
            );
        }
        sublayer_cursor += interval.altitude_divisions;
    }
    return grid;
}

fn buildLegacyVerticalGrid(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
) !OwnedVerticalGrid {
    const layer_count: usize = @max(scene.atmosphere.preparedLayerCount(), @as(u32, 1));
    const sublayer_divisions: usize = @max(@as(u32, scene.atmosphere.sublayer_divisions), @as(u32, 1));
    const total_sublayer_count = layer_count * sublayer_divisions;
    var grid = try allocateVerticalGrid(allocator, layer_count, total_sublayer_count);
    errdefer grid.deinit(allocator);

    const bottom_altitude_km = scene.geometry.surface_altitude_km;
    const top_altitude_km = @max(profile.maxAltitude(), bottom_altitude_km + 1.0);
    const layer_span_km = (top_altitude_km - bottom_altitude_km) / @as(f64, @floatFromInt(layer_count));

    var sublayer_cursor: usize = 0;
    for (0..layer_count) |index| {
        const layer_top_altitude = bottom_altitude_km + layer_span_km * @as(f64, @floatFromInt(index + 1));
        const layer_bottom_altitude = bottom_altitude_km + layer_span_km * @as(f64, @floatFromInt(index));
        grid.layer_top_altitudes_km[index] = layer_top_altitude;
        grid.layer_bottom_altitudes_km[index] = layer_bottom_altitude;
        grid.layer_top_pressures_hpa[index] = profile.interpolatePressure(layer_top_altitude);
        grid.layer_bottom_pressures_hpa[index] = profile.interpolatePressure(layer_bottom_altitude);
        grid.layer_interval_indices_1based[index] = @intCast(index + 1);
        grid.layer_sublayer_starts[index] = @intCast(sublayer_cursor);
        grid.layer_sublayer_counts[index] = @intCast(sublayer_divisions);
        grid.layer_subcolumn_labels[index] = scene.atmosphere.subcolumns.labelForAltitude(
            0.5 * (layer_top_altitude + layer_bottom_altitude),
        );

        for (0..sublayer_divisions) |sublayer_index| {
            const top_fraction = @as(f64, @floatFromInt(sublayer_index + 1)) / @as(f64, @floatFromInt(sublayer_divisions));
            const bottom_fraction = @as(f64, @floatFromInt(sublayer_index)) / @as(f64, @floatFromInt(sublayer_divisions));
            const sublayer_top_altitude = layer_bottom_altitude + layer_span_km * top_fraction;
            const sublayer_bottom_altitude = layer_bottom_altitude + layer_span_km * bottom_fraction;
            const global_index = sublayer_cursor + sublayer_index;
            grid.sublayer_top_altitudes_km[global_index] = sublayer_top_altitude;
            grid.sublayer_bottom_altitudes_km[global_index] = sublayer_bottom_altitude;
            grid.sublayer_top_pressures_hpa[global_index] = profile.interpolatePressure(sublayer_top_altitude);
            grid.sublayer_bottom_pressures_hpa[global_index] = profile.interpolatePressure(sublayer_bottom_altitude);
            grid.sublayer_mid_altitudes_km[global_index] = 0.5 * (sublayer_top_altitude + sublayer_bottom_altitude);
            grid.sublayer_interval_indices_1based[global_index] = @intCast(index + 1);
            grid.sublayer_subcolumn_labels[global_index] = scene.atmosphere.subcolumns.labelForAltitude(
                grid.sublayer_mid_altitudes_km[global_index],
            );
        }
        sublayer_cursor += sublayer_divisions;
    }
    return grid;
}

fn allocateVerticalGrid(
    allocator: Allocator,
    layer_count: usize,
    total_sublayer_count: usize,
) !OwnedVerticalGrid {
    const layer_top_altitudes_km = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_top_altitudes_km);
    const layer_bottom_altitudes_km = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_bottom_altitudes_km);
    const layer_top_pressures_hpa = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_top_pressures_hpa);
    const layer_bottom_pressures_hpa = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_bottom_pressures_hpa);
    const layer_interval_indices_1based = try allocator.alloc(u32, layer_count);
    errdefer allocator.free(layer_interval_indices_1based);
    const layer_sublayer_starts = try allocator.alloc(u32, layer_count);
    errdefer allocator.free(layer_sublayer_starts);
    const layer_sublayer_counts = try allocator.alloc(u32, layer_count);
    errdefer allocator.free(layer_sublayer_counts);
    const layer_subcolumn_labels = try allocator.alloc(AtmosphereModel.PartitionLabel, layer_count);
    errdefer allocator.free(layer_subcolumn_labels);
    const sublayer_top_altitudes_km = try allocator.alloc(f64, total_sublayer_count);
    errdefer allocator.free(sublayer_top_altitudes_km);
    const sublayer_bottom_altitudes_km = try allocator.alloc(f64, total_sublayer_count);
    errdefer allocator.free(sublayer_bottom_altitudes_km);
    const sublayer_top_pressures_hpa = try allocator.alloc(f64, total_sublayer_count);
    errdefer allocator.free(sublayer_top_pressures_hpa);
    const sublayer_bottom_pressures_hpa = try allocator.alloc(f64, total_sublayer_count);
    errdefer allocator.free(sublayer_bottom_pressures_hpa);
    const sublayer_mid_altitudes_km = try allocator.alloc(f64, total_sublayer_count);
    errdefer allocator.free(sublayer_mid_altitudes_km);
    const sublayer_interval_indices_1based = try allocator.alloc(u32, total_sublayer_count);
    errdefer allocator.free(sublayer_interval_indices_1based);
    const sublayer_subcolumn_labels = try allocator.alloc(AtmosphereModel.PartitionLabel, total_sublayer_count);
    errdefer allocator.free(sublayer_subcolumn_labels);

    return .{
        .layer_top_altitudes_km = layer_top_altitudes_km,
        .layer_bottom_altitudes_km = layer_bottom_altitudes_km,
        .layer_top_pressures_hpa = layer_top_pressures_hpa,
        .layer_bottom_pressures_hpa = layer_bottom_pressures_hpa,
        .layer_interval_indices_1based = layer_interval_indices_1based,
        .layer_sublayer_starts = layer_sublayer_starts,
        .layer_sublayer_counts = layer_sublayer_counts,
        .layer_subcolumn_labels = layer_subcolumn_labels,
        .sublayer_top_altitudes_km = sublayer_top_altitudes_km,
        .sublayer_bottom_altitudes_km = sublayer_bottom_altitudes_km,
        .sublayer_top_pressures_hpa = sublayer_top_pressures_hpa,
        .sublayer_bottom_pressures_hpa = sublayer_bottom_pressures_hpa,
        .sublayer_mid_altitudes_km = sublayer_mid_altitudes_km,
        .sublayer_interval_indices_1based = sublayer_interval_indices_1based,
        .sublayer_subcolumn_labels = sublayer_subcolumn_labels,
    };
}
