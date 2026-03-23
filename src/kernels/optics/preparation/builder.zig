const std = @import("std");
const AbsorberModel = @import("../../../model/Absorber.zig");
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

pub const PreparationInputs = struct {
    profile: *const ReferenceData.ClimatologyProfile,
    cross_sections: *const ReferenceData.CrossSectionTable,
    lut: *const ReferenceData.AirmassFactorLut,
    collision_induced_absorption: ?*const ReferenceData.CollisionInducedAbsorptionTable = null,
    spectroscopy_lines: ?*const ReferenceData.SpectroscopyLineList = null,
    aerosol_mie: ?*const ReferenceData.MiePhaseTable = null,
    cloud_mie: ?*const ReferenceData.MiePhaseTable = null,
};

pub fn prepare(
    allocator: Allocator,
    scene: *const Scene,
    inputs: PreparationInputs,
) !PreparedOpticalState {
    return prepareWithInputs(allocator, scene, inputs);
}

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

    const layer_count = @max(scene.atmosphere.layer_count, @as(u32, 1));
    const sublayer_divisions = @max(@as(u32, scene.atmosphere.sublayer_divisions), @as(u32, 1));
    const layers = try allocator.alloc(PreparedLayer, layer_count);
    errdefer allocator.free(layers);
    const sublayers = try allocator.alloc(PreparedSublayer, @as(usize, layer_count) * @as(usize, sublayer_divisions));
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
    const operational_o2_lut = scene.observation_model.o2_operational_lut;
    const operational_o2o2_lut = scene.observation_model.o2o2_operational_lut;
    const total_sublayer_count = @as(usize, layer_count) * @as(usize, sublayer_divisions);
    const active_line_absorbers = try Spectroscopy.collectActiveLineAbsorbers(allocator, scene);
    defer allocator.free(active_line_absorbers);
    const single_active_line_absorber = if (active_line_absorbers.len == 1)
        active_line_absorbers[0]
    else
        null;

    var owned_line_absorbers: []PreparedLineAbsorber = &.{};
    var owned_line_absorber_count: usize = 0;
    errdefer if (owned_line_absorbers.len != 0) {
        for (owned_line_absorbers[0..owned_line_absorber_count]) |*line_absorber| {
            line_absorber.deinit(allocator);
        }
        allocator.free(owned_line_absorbers);
    };

    if (owned_lines) |*line_list| {
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
    const active_line_species = if (owned_line_absorbers.len == 0)
        Spectroscopy.resolveActiveLineSpecies(single_active_line_absorber, owned_lines, operational_o2_lut)
    else
        null;
    const continuum_owner_species = Spectroscopy.resolveContinuumOwnerSpecies(
        active_line_species,
        owned_line_absorbers,
        operational_o2_lut,
    );
    const mean_sigma = cross_sections.meanSigmaInRange(
        scene.spectral_grid.start_nm,
        scene.spectral_grid.end_nm,
    );
    const midpoint_continuum_sigma = cross_sections.interpolateSigma(midpoint_nm);
    const air_mass_factor = lut.nearest(
        scene.geometry.solar_zenith_deg,
        scene.geometry.viewing_zenith_deg,
        scene.geometry.relative_azimuth_deg,
    );
    const altitude_span = @max(profile.maxAltitude(), 1.0);
    const layer_span_km = altitude_span / @as(f64, @floatFromInt(layer_count));
    const base_single_scatter_albedo = PhaseFunctions.computeSingleScatterAlbedo(scene);

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
    var total_cloud_optical_depth: f64 = 0.0;
    var total_scattering_optical_depth: f64 = 0.0;
    var total_d_optical_depth_d_temperature: f64 = 0.0;
    var depolarization_weighted: f64 = 0.0;

    const aerosol_sublayer_distribution = try ParticleProfiles.buildAerosolSublayerDistribution(
        allocator,
        scene,
        profile,
        layer_count,
        sublayer_divisions,
    );
    defer allocator.free(aerosol_sublayer_distribution);
    const cloud_sublayer_distribution = try ParticleProfiles.buildCloudSublayerDistribution(
        allocator,
        scene,
        profile,
        layer_count,
        sublayer_divisions,
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

    var sublayer_write_index: usize = 0;
    for (layers, 0..) |*layer, index| {
        const layer_bottom_altitude_km = layer_span_km * @as(f64, @floatFromInt(index));
        const layer_center_altitude_km = layer_bottom_altitude_km + 0.5 * layer_span_km;
        const sublayer_weight = 1.0 / @as(f64, @floatFromInt(sublayer_divisions));

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
        var layer_cloud_optical_depth: f64 = 0.0;

        for (0..sublayer_divisions) |sublayer_index| {
            const sublayer_fraction = (@as(f64, @floatFromInt(sublayer_index)) + 0.5) / @as(f64, @floatFromInt(sublayer_divisions));
            const altitude_km = layer_bottom_altitude_km + layer_span_km * sublayer_fraction;
            const density = profile.interpolateDensity(altitude_km);
            const pressure = profile.interpolatePressure(altitude_km);
            const temperature = profile.interpolateTemperature(altitude_km);
            const oxygen_mixing_ratio = Spectroscopy.speciesMixingRatioAtPressure(
                scene,
                .o2,
                &.{},
                pressure,
                oxygen_volume_mixing_ratio,
            ) orelse oxygen_volume_mixing_ratio;
            var absorber_density_cm3: f64 = 0.0;
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
                        if (line_absorber.species == .o2) oxygen_volume_mixing_ratio else null,
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

                    const line_absorber_column_density_cm2 = line_absorber_density_cm3 * layer_span_km * centimeters_per_kilometer * sublayer_weight;
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
                        if (species == .o2) oxygen_volume_mixing_ratio else null,
                    ) orelse return error.InvalidRequest
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
            const continuum_density_cm3 = if (owned_line_absorbers.len != 0) blk: {
                const owner_species = continuum_owner_species orelse break :blk absorber_density_cm3;
                if (operational_o2_lut.enabled() and owner_species == .o2) break :blk o2_density_cm3;
                for (owned_line_absorbers) |line_absorber| {
                    if (line_absorber.species != owner_species) continue;
                    break :blk line_absorber.number_densities_cm3[sublayer_write_index];
                }
                break :blk absorber_density_cm3;
            } else absorber_density_cm3;
            const sublayer_path_length_cm = layer_span_km * centimeters_per_kilometer * sublayer_weight;
            const gas_column_density_cm2 = absorber_density_cm3 * sublayer_path_length_cm;
            const continuum_column_density_cm2 = continuum_density_cm3 * sublayer_path_length_cm;
            const molecular_gas_optical_depth =
                midpoint_continuum_sigma * continuum_column_density_cm2 +
                spectroscopy_eval.total_sigma_cm2_per_molecule * gas_column_density_cm2;
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
            const gas_scattering_optical_depth =
                Rayleigh.crossSectionCm2(midpoint_nm) * density * sublayer_path_length_cm;
            const gas_absorption_optical_depth = molecular_gas_optical_depth;
            const gas_extinction_optical_depth = gas_absorption_optical_depth + cia_optical_depth + gas_scattering_optical_depth;
            const d_cia_optical_depth_d_temperature = d_cia_sigma_d_temperature * o2_density_cm3 * o2_density_cm3 * sublayer_path_length_cm;
            const d_gas_optical_depth_d_temperature =
                spectroscopy_eval.d_sigma_d_temperature_cm2_per_molecule_per_k * gas_column_density_cm2;
            const aerosol_optical_depth = aerosol_sublayer_distribution[sublayer_write_index] * aerosol_extinction_scale;
            const cloud_optical_depth = cloud_sublayer_distribution[sublayer_write_index] * cloud_extinction_scale;
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
                .absorber_number_density_cm3 = absorber_density_cm3,
                .path_length_cm = sublayer_path_length_cm,
                .continuum_cross_section_cm2_per_molecule = midpoint_continuum_sigma,
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
                .cloud_optical_depth = cloud_optical_depth,
                .aerosol_single_scatter_albedo = aerosol_single_scatter_albedo,
                .cloud_single_scatter_albedo = cloud_single_scatter_albedo,
                .aerosol_phase_coefficients = aerosol_phase_coefficients,
                .cloud_phase_coefficients = cloud_phase_coefficients,
                .combined_phase_coefficients = combined_phase_coefficients,
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
            layer_cloud_optical_depth += cloud_optical_depth;
            air_column_density_factor += density * sublayer_path_length_cm;
            oxygen_column_density_factor += o2_density_cm3 * sublayer_path_length_cm;
            column_density_factor += gas_column_density_cm2;
            cia_pair_path_factor_cm5 += o2_density_cm3 * o2_density_cm3 * sublayer_path_length_cm;
            total_d_optical_depth_d_temperature += d_gas_optical_depth_d_temperature + d_cia_optical_depth_d_temperature;

            sublayer_write_index += 1;
        }

        const density = layer_density_sum;
        const temperature = if (layer_density_weight == 0.0) 0.0 else layer_temperature_sum / layer_density_weight;
        const pressure = if (layer_density_weight == 0.0) 0.0 else layer_pressure_sum / layer_density_weight;
        const gas_optical_depth = layer_gas_optical_depth;
        const aerosol_optical_depth = layer_aerosol_optical_depth;
        const cloud_optical_depth = layer_cloud_optical_depth;
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
        total_cloud_optical_depth += cloud_optical_depth;
        total_scattering_optical_depth += scattering;
        depolarization_weighted += depolarization * optical_depth;

        layer.* = .{
            .layer_index = @intCast(index),
            .sublayer_start_index = @intCast(index * sublayer_divisions),
            .sublayer_count = sublayer_divisions,
            .altitude_km = layer_center_altitude_km,
            .pressure_hpa = pressure,
            .temperature_k = temperature,
            .number_density_cm3 = density,
            .continuum_cross_section_cm2_per_molecule = mean_sigma,
            .line_cross_section_cm2_per_molecule = layer_line_sigma_sum / @as(f64, @floatFromInt(sublayer_divisions)),
            .line_mixing_cross_section_cm2_per_molecule = layer_line_mixing_sum / @as(f64, @floatFromInt(sublayer_divisions)),
            .cia_optical_depth = layer_cia_optical_depth,
            .d_cross_section_d_temperature_cm2_per_molecule_per_k = layer_d_cross_section_sum / @as(f64, @floatFromInt(sublayer_divisions)),
            .gas_optical_depth = gas_optical_depth,
            .gas_scattering_optical_depth = gas_scattering,
            .aerosol_optical_depth = aerosol_optical_depth,
            .cloud_optical_depth = cloud_optical_depth,
            .layer_single_scatter_albedo = layer_single_scatter_albedo,
            .depolarization_factor = depolarization,
            .optical_depth = optical_depth,
        };
    }

    const effective_temperature = if (total_weight == 0.0) 0.0 else total_temperature_weighted / total_weight;
    const effective_pressure = if (total_weight == 0.0) 0.0 else total_pressure_weighted / total_weight;
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
        .line_absorbers = owned_line_absorbers,
        .continuum_owner_species = continuum_owner_species,
        .operational_o2_lut = operational_o2_lut,
        .operational_o2o2_lut = operational_o2o2_lut,
        .mean_cross_section_cm2_per_molecule = mean_sigma + line_means.line_mean_cross_section_cm2_per_molecule + line_means.line_mixing_mean_cross_section_cm2_per_molecule,
        .line_mean_cross_section_cm2_per_molecule = line_means.line_mean_cross_section_cm2_per_molecule,
        .line_mixing_mean_cross_section_cm2_per_molecule = line_means.line_mixing_mean_cross_section_cm2_per_molecule,
        .cia_mean_cross_section_cm5_per_molecule2 = cia_mean_sigma,
        .effective_air_mass_factor = air_mass_factor,
        .effective_single_scatter_albedo = if (total_optical_depth == 0.0)
            base_single_scatter_albedo
        else
            total_scattering_optical_depth / total_optical_depth,
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
        .cloud_optical_depth = total_cloud_optical_depth,
        .d_optical_depth_d_temperature = total_d_optical_depth_d_temperature,
        .depolarization_factor = if (total_optical_depth == 0.0) 0.0 else depolarization_weighted / total_optical_depth,
        .total_optical_depth = total_optical_depth,
    };
}
