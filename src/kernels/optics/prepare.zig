const std = @import("std");
const Scene = @import("../../model/Scene.zig").Scene;
const ReferenceData = @import("../../model/ReferenceData.zig");
const OperationalReferenceGrid = @import("../../model/Instrument.zig").OperationalReferenceGrid;
const OperationalCrossSectionLut = @import("../../model/Instrument.zig").OperationalCrossSectionLut;
const transport_common = @import("../transport/common.zig");

const Allocator = std.mem.Allocator;
const phase_coefficient_count = 4;
const oxygen_volume_mixing_ratio = 0.2095;

pub const PreparedLayer = struct {
    layer_index: u32,
    sublayer_start_index: u32 = 0,
    sublayer_count: u32 = 0,
    altitude_km: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    continuum_cross_section_cm2_per_molecule: f64,
    line_cross_section_cm2_per_molecule: f64,
    line_mixing_cross_section_cm2_per_molecule: f64,
    cia_optical_depth: f64,
    d_cross_section_d_temperature_cm2_per_molecule_per_k: f64,
    gas_optical_depth: f64,
    aerosol_optical_depth: f64,
    cloud_optical_depth: f64,
    layer_single_scatter_albedo: f64,
    depolarization_factor: f64,
    optical_depth: f64,
};

pub const PreparedSublayer = struct {
    parent_layer_index: u32,
    sublayer_index: u32,
    altitude_km: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    continuum_cross_section_cm2_per_molecule: f64,
    line_cross_section_cm2_per_molecule: f64,
    line_mixing_cross_section_cm2_per_molecule: f64,
    cia_sigma_cm5_per_molecule2: f64,
    cia_optical_depth: f64,
    d_cross_section_d_temperature_cm2_per_molecule_per_k: f64,
    gas_absorption_optical_depth: f64,
    gas_scattering_optical_depth: f64,
    gas_extinction_optical_depth: f64,
    d_gas_optical_depth_d_temperature: f64,
    d_cia_optical_depth_d_temperature: f64,
    aerosol_optical_depth: f64,
    cloud_optical_depth: f64,
    aerosol_single_scatter_albedo: f64,
    cloud_single_scatter_albedo: f64,
    aerosol_phase_coefficients: [phase_coefficient_count]f64,
    cloud_phase_coefficients: [phase_coefficient_count]f64,
    combined_phase_coefficients: [phase_coefficient_count]f64,
};

pub const PreparedOpticalState = struct {
    layers: []PreparedLayer,
    sublayers: ?[]PreparedSublayer = null,
    continuum_points: []ReferenceData.CrossSectionPoint,
    collision_induced_absorption: ?ReferenceData.CollisionInducedAbsorptionTable = null,
    spectroscopy_lines: ?ReferenceData.SpectroscopyLineList = null,
    operational_o2_lut: OperationalCrossSectionLut = .{},
    operational_o2o2_lut: OperationalCrossSectionLut = .{},
    mean_cross_section_cm2_per_molecule: f64,
    line_mean_cross_section_cm2_per_molecule: f64,
    line_mixing_mean_cross_section_cm2_per_molecule: f64,
    cia_mean_cross_section_cm5_per_molecule2: f64,
    effective_air_mass_factor: f64,
    effective_single_scatter_albedo: f64,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
    column_density_factor: f64,
    cia_pair_path_factor_cm5: f64,
    aerosol_reference_wavelength_nm: f64,
    aerosol_angstrom_exponent: f64,
    cloud_reference_wavelength_nm: f64,
    cloud_angstrom_exponent: f64,
    gas_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    cloud_optical_depth: f64,
    d_optical_depth_d_temperature: f64,
    depolarization_factor: f64,
    total_optical_depth: f64,

    pub fn deinit(self: *PreparedOpticalState, allocator: Allocator) void {
        allocator.free(self.layers);
        if (self.sublayers) |sublayers| allocator.free(sublayers);
        allocator.free(self.continuum_points);
        if (self.collision_induced_absorption) |cia| {
            var owned_cia = cia;
            owned_cia.deinit(allocator);
        }
        if (self.spectroscopy_lines) |line_list| {
            var owned = line_list;
            owned.deinit(allocator);
        }
        self.* = undefined;
    }

    pub fn toForwardInput(self: PreparedOpticalState, scene: Scene) transport_common.ForwardInput {
        return self.toForwardInputAtWavelength(
            scene,
            (scene.spectral_grid.start_nm + scene.spectral_grid.end_nm) * 0.5,
        );
    }

    pub fn toForwardInputAtWavelength(
        self: PreparedOpticalState,
        scene: Scene,
        wavelength_nm: f64,
    ) transport_common.ForwardInput {
        const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
        const spectral_weight = if (scene.spectral_grid.sample_count == 0) 1.0 else span_nm / @as(f64, @floatFromInt(scene.spectral_grid.sample_count));
        return .{
            .wavelength_nm = wavelength_nm,
            .spectral_weight = @max(spectral_weight, 1.0),
            .air_mass_factor = self.effective_air_mass_factor,
            .optical_depth = self.totalOpticalDepthAtWavelength(wavelength_nm),
            .single_scatter_albedo = self.effective_single_scatter_albedo,
        };
    }

    pub fn totalCrossSectionAtWavelength(self: PreparedOpticalState, wavelength_nm: f64) f64 {
        const continuum = (ReferenceData.CrossSectionTable{
            .points = self.continuum_points,
        }).interpolateSigma(wavelength_nm);
        const line_sigma = if (self.operational_o2_lut.enabled())
            self.operational_o2_lut.sigmaAt(
                wavelength_nm,
                self.effective_temperature_k,
                self.effective_pressure_hpa,
            )
        else if (self.spectroscopy_lines) |line_list|
            line_list.evaluateAt(
                wavelength_nm,
                self.effective_temperature_k,
                self.effective_pressure_hpa,
            ).total_sigma_cm2_per_molecule
        else
            0.0;
        return continuum + line_sigma;
    }

    pub fn collisionInducedOpticalDepthAtWavelength(self: PreparedOpticalState, wavelength_nm: f64) f64 {
        if (self.operational_o2o2_lut.enabled()) {
            return self.operational_o2o2_lut.sigmaAt(
                wavelength_nm,
                self.effective_temperature_k,
                self.effective_pressure_hpa,
            ) * self.cia_pair_path_factor_cm5;
        }
        const cia_table = self.collision_induced_absorption orelse return 0.0;
        return cia_table.sigmaAt(wavelength_nm, self.effective_temperature_k) * self.cia_pair_path_factor_cm5;
    }

    pub fn gasOpticalDepthAtWavelength(self: PreparedOpticalState, wavelength_nm: f64) f64 {
        return self.totalCrossSectionAtWavelength(wavelength_nm) * self.column_density_factor +
            self.collisionInducedOpticalDepthAtWavelength(wavelength_nm);
    }

    pub fn aerosolOpticalDepthAtWavelength(self: PreparedOpticalState, wavelength_nm: f64) f64 {
        return scaleOpticalDepth(
            self.aerosol_optical_depth,
            self.aerosol_reference_wavelength_nm,
            self.aerosol_angstrom_exponent,
            wavelength_nm,
        );
    }

    pub fn cloudOpticalDepthAtWavelength(self: PreparedOpticalState, wavelength_nm: f64) f64 {
        return scaleOpticalDepth(
            self.cloud_optical_depth,
            self.cloud_reference_wavelength_nm,
            self.cloud_angstrom_exponent,
            wavelength_nm,
        );
    }

    pub fn totalOpticalDepthAtWavelength(self: PreparedOpticalState, wavelength_nm: f64) f64 {
        return self.gasOpticalDepthAtWavelength(wavelength_nm) +
            self.aerosolOpticalDepthAtWavelength(wavelength_nm) +
            self.cloudOpticalDepthAtWavelength(wavelength_nm);
    }
};

pub fn prepare(
    allocator: Allocator,
    scene: Scene,
    profile: ReferenceData.ClimatologyProfile,
    cross_sections: ReferenceData.CrossSectionTable,
    lut: ReferenceData.AirmassFactorLut,
) !PreparedOpticalState {
    return prepareWithParticleTables(
        allocator,
        scene,
        profile,
        cross_sections,
        null,
        null,
        lut,
        null,
        null,
    );
}

pub fn prepareWithSpectroscopy(
    allocator: Allocator,
    scene: Scene,
    profile: ReferenceData.ClimatologyProfile,
    cross_sections: ReferenceData.CrossSectionTable,
    spectroscopy_lines: ?ReferenceData.SpectroscopyLineList,
    lut: ReferenceData.AirmassFactorLut,
) !PreparedOpticalState {
    return prepareWithParticleTables(
        allocator,
        scene,
        profile,
        cross_sections,
        null,
        spectroscopy_lines,
        lut,
        null,
        null,
    );
}

pub fn prepareWithSpectroscopyAndCollisionInducedAbsorption(
    allocator: Allocator,
    scene: Scene,
    profile: ReferenceData.ClimatologyProfile,
    cross_sections: ReferenceData.CrossSectionTable,
    collision_induced_absorption: ?ReferenceData.CollisionInducedAbsorptionTable,
    spectroscopy_lines: ?ReferenceData.SpectroscopyLineList,
    lut: ReferenceData.AirmassFactorLut,
) !PreparedOpticalState {
    return prepareWithParticleTables(
        allocator,
        scene,
        profile,
        cross_sections,
        collision_induced_absorption,
        spectroscopy_lines,
        lut,
        null,
        null,
    );
}

pub fn prepareWithParticleTables(
    allocator: Allocator,
    scene: Scene,
    profile: ReferenceData.ClimatologyProfile,
    cross_sections: ReferenceData.CrossSectionTable,
    collision_induced_absorption: ?ReferenceData.CollisionInducedAbsorptionTable,
    spectroscopy_lines: ?ReferenceData.SpectroscopyLineList,
    lut: ReferenceData.AirmassFactorLut,
    aerosol_mie: ?ReferenceData.MiePhaseTable,
    cloud_mie: ?ReferenceData.MiePhaseTable,
) !PreparedOpticalState {
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
    const owned_lines = if (spectroscopy_lines) |line_list|
        try line_list.clone(allocator)
    else
        null;
    errdefer if (owned_lines) |line_list| {
        var owned = line_list;
        owned.deinit(allocator);
    };

    const midpoint_nm = (scene.spectral_grid.start_nm + scene.spectral_grid.end_nm) * 0.5;
    const mean_sigma = cross_sections.meanSigmaInRange(
        scene.spectral_grid.start_nm,
        scene.spectral_grid.end_nm,
    );
    const operational_o2_lut = scene.observation_model.o2_operational_lut;
    const operational_o2o2_lut = scene.observation_model.o2o2_operational_lut;
    const air_mass_factor = lut.nearest(
        scene.geometry.solar_zenith_deg,
        scene.geometry.viewing_zenith_deg,
        scene.geometry.relative_azimuth_deg,
    );
    const altitude_span = @max(profile.maxAltitude(), 1.0);
    const layer_span_km = altitude_span / @as(f64, @floatFromInt(layer_count));
    const base_single_scatter_albedo = computeSingleScatterAlbedo(scene);

    var total_optical_depth: f64 = 0.0;
    var total_temperature_weighted: f64 = 0.0;
    var total_pressure_weighted: f64 = 0.0;
    var total_weight: f64 = 0.0;
    var column_density_factor: f64 = 0.0;
    var cia_pair_path_factor_cm5: f64 = 0.0;
    var total_gas_optical_depth: f64 = 0.0;
    var total_cia_optical_depth: f64 = 0.0;
    var total_aerosol_optical_depth: f64 = 0.0;
    var total_cloud_optical_depth: f64 = 0.0;
    var total_scattering_optical_depth: f64 = 0.0;
    var total_d_optical_depth_d_temperature: f64 = 0.0;
    var depolarization_weighted: f64 = 0.0;

    const aerosol_sublayer_distribution = try buildAerosolSublayerDistribution(
        allocator,
        scene,
        profile,
        layer_count,
        sublayer_divisions,
    );
    defer allocator.free(aerosol_sublayer_distribution);
    const cloud_sublayer_distribution = try buildCloudSublayerDistribution(
        allocator,
        scene,
        profile,
        layer_count,
        sublayer_divisions,
    );
    defer allocator.free(cloud_sublayer_distribution);
    const aerosol_mie_point = if (aerosol_mie) |table| table.interpolate(midpoint_nm) else null;
    const cloud_mie_point = if (cloud_mie) |table| table.interpolate(midpoint_nm) else null;
    const aerosol_phase_coefficients = if (aerosol_mie_point) |point| point.phase_coefficients else hgPhaseCoefficients(scene.aerosol.asymmetry_factor);
    const cloud_phase_coefficients = if (cloud_mie_point) |point| point.phase_coefficients else hgPhaseCoefficients(scene.cloud.asymmetry_factor);
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
            const spectroscopy_eval = if (operational_o2_lut.enabled())
                ReferenceData.SpectroscopyEvaluation{
                    .weak_line_sigma_cm2_per_molecule = operational_o2_lut.sigmaAt(midpoint_nm, temperature, pressure),
                    .strong_line_sigma_cm2_per_molecule = 0.0,
                    .line_sigma_cm2_per_molecule = operational_o2_lut.sigmaAt(midpoint_nm, temperature, pressure),
                    .line_mixing_sigma_cm2_per_molecule = 0.0,
                    .total_sigma_cm2_per_molecule = operational_o2_lut.sigmaAt(midpoint_nm, temperature, pressure),
                    .d_sigma_d_temperature_cm2_per_molecule_per_k = operational_o2_lut.dSigmaDTemperatureAt(midpoint_nm, temperature, pressure),
                }
            else if (spectroscopy_lines) |line_list|
                line_list.evaluateAt(midpoint_nm, temperature, pressure)
            else
                ReferenceData.SpectroscopyEvaluation{
                    .line_sigma_cm2_per_molecule = 0.0,
                    .line_mixing_sigma_cm2_per_molecule = 0.0,
                    .total_sigma_cm2_per_molecule = 0.0,
                    .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
                };
            const molecular_gas_optical_depth = (mean_sigma + spectroscopy_eval.total_sigma_cm2_per_molecule) * density * air_mass_factor * 1.0e-18 * sublayer_weight;
            const o2_density_cm3 = density * oxygen_volume_mixing_ratio;
            const sublayer_path_length_cm = layer_span_km * 1.0e5 * air_mass_factor * sublayer_weight;
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
            const gas_extinction_optical_depth = molecular_gas_optical_depth + cia_optical_depth;
            const gas_scattering_optical_depth = molecular_gas_optical_depth * 0.08;
            const gas_absorption_optical_depth = @max(gas_extinction_optical_depth - gas_scattering_optical_depth, 0.0);
            const d_cia_optical_depth_d_temperature = d_cia_sigma_d_temperature * o2_density_cm3 * o2_density_cm3 * sublayer_path_length_cm;
            const d_gas_optical_depth_d_temperature =
                spectroscopy_eval.d_sigma_d_temperature_cm2_per_molecule_per_k * density * air_mass_factor * 1.0e-18 * sublayer_weight +
                d_cia_optical_depth_d_temperature;
            const aerosol_optical_depth = aerosol_sublayer_distribution[sublayer_write_index] * aerosol_extinction_scale;
            const cloud_optical_depth = cloud_sublayer_distribution[sublayer_write_index] * cloud_extinction_scale;
            const aerosol_scattering_optical_depth = aerosol_optical_depth * aerosol_single_scatter_albedo;
            const cloud_scattering_optical_depth = cloud_optical_depth * cloud_single_scatter_albedo;
            const combined_phase_coefficients = combinePhaseCoefficients(
                gas_scattering_optical_depth,
                aerosol_scattering_optical_depth,
                cloud_scattering_optical_depth,
                aerosol_phase_coefficients,
                cloud_phase_coefficients,
            );

            sublayers[sublayer_write_index] = .{
                .parent_layer_index = @intCast(index),
                .sublayer_index = @intCast(sublayer_index),
                .altitude_km = altitude_km,
                .pressure_hpa = pressure,
                .temperature_k = temperature,
                .number_density_cm3 = density,
                .continuum_cross_section_cm2_per_molecule = mean_sigma,
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
            layer_gas_optical_depth += gas_extinction_optical_depth;
            layer_gas_scattering_optical_depth += gas_scattering_optical_depth;
            layer_cia_optical_depth += cia_optical_depth;
            layer_aerosol_optical_depth += aerosol_optical_depth;
            layer_cloud_optical_depth += cloud_optical_depth;
            cia_pair_path_factor_cm5 += o2_density_cm3 * o2_density_cm3 * sublayer_path_length_cm;
            total_d_optical_depth_d_temperature += d_gas_optical_depth_d_temperature;

            sublayer_write_index += 1;
        }

        const density = layer_density_sum;
        const temperature = if (layer_density_weight == 0.0) 0.0 else layer_temperature_sum / layer_density_weight;
        const pressure = if (layer_density_weight == 0.0) 0.0 else layer_pressure_sum / layer_density_weight;
        const gas_optical_depth = layer_gas_optical_depth;
        const aerosol_optical_depth = layer_aerosol_optical_depth;
        const cloud_optical_depth = layer_cloud_optical_depth;
        const optical_depth = gas_optical_depth + aerosol_optical_depth + cloud_optical_depth;
        const aerosol_scattering = aerosol_optical_depth * aerosol_single_scatter_albedo;
        const cloud_scattering = cloud_optical_depth * cloud_single_scatter_albedo;
        const gas_scattering = layer_gas_scattering_optical_depth;
        const scattering = aerosol_scattering + cloud_scattering + gas_scattering;
        const absorption = @max(optical_depth - scattering, 1e-9);
        const layer_single_scatter_albedo = scattering / @max(scattering + absorption, 1e-9);
        const depolarization = computeLayerDepolarization(scene, gas_scattering, aerosol_scattering, cloud_scattering);
        total_optical_depth += optical_depth;
        total_temperature_weighted += temperature * density;
        total_pressure_weighted += pressure * density;
        total_weight += density;
        column_density_factor += layer_density_sum * air_mass_factor * 1.0e-18;
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
            .aerosol_optical_depth = aerosol_optical_depth,
            .cloud_optical_depth = cloud_optical_depth,
            .layer_single_scatter_albedo = layer_single_scatter_albedo,
            .depolarization_factor = depolarization,
            .optical_depth = optical_depth,
        };
    }

    const effective_temperature = if (total_weight == 0.0) 0.0 else total_temperature_weighted / total_weight;
    const effective_pressure = if (total_weight == 0.0) 0.0 else total_pressure_weighted / total_weight;
    const line_means = if (operational_o2_lut.enabled())
        LineBandMeans{
            .line_mean_cross_section_cm2_per_molecule = computeOperationalBandMean(
                scene,
                operational_o2_lut,
                effective_temperature,
                effective_pressure,
            ),
            .line_mixing_mean_cross_section_cm2_per_molecule = 0.0,
        }
    else if (spectroscopy_lines) |line_list|
        computeBandLineMeans(scene, line_list, effective_temperature, effective_pressure)
    else
        LineBandMeans{};
    const cia_mean_sigma = if (operational_o2o2_lut.enabled())
        computeOperationalBandMean(
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
        .continuum_points = continuum_points,
        .collision_induced_absorption = owned_cia,
        .spectroscopy_lines = owned_lines,
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

fn computeSingleScatterAlbedo(scene: Scene) f64 {
    const gas_ssa: f64 = 0.92;
    const aerosol_ssa = if (scene.atmosphere.has_aerosols) scene.aerosol.single_scatter_albedo else gas_ssa;
    const cloud_ssa = if (scene.atmosphere.has_clouds) scene.cloud.single_scatter_albedo else gas_ssa;
    const aerosol_weight: f64 = if (scene.atmosphere.has_aerosols) 0.20 else 0.0;
    const cloud_weight: f64 = if (scene.atmosphere.has_clouds) 0.30 else 0.0;
    const gas_weight: f64 = 1.0 - aerosol_weight - cloud_weight;
    return std.math.clamp(gas_weight * gas_ssa + aerosol_weight * aerosol_ssa + cloud_weight * cloud_ssa, 0.3, 0.999);
}

test "optical preparation derives deterministic layer optical depths from typed assets" {
    const scene: Scene = .{
        .id = "optical-scene",
        .atmosphere = .{
            .layer_count = 4,
            .has_clouds = true,
            .has_aerosols = false,
        },
        .geometry = .{
            .solar_zenith_deg = 40.0,
            .viewing_zenith_deg = 10.0,
            .relative_azimuth_deg = 30.0,
        },
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 121,
        },
    };

    var profile = ReferenceData.ClimatologyProfile{
        .rows = try std.testing.allocator.dupe(ReferenceData.ClimatologyPoint, &.{
            .{ .altitude_km = 0.0, .pressure_hpa = 1013.25, .temperature_k = 288.15, .air_number_density_cm3 = 2.547e19 },
            .{ .altitude_km = 20.0, .pressure_hpa = 54.75, .temperature_k = 216.65, .air_number_density_cm3 = 1.095e18 },
        }),
    };
    defer profile.deinit(std.testing.allocator);

    var cross_sections = ReferenceData.CrossSectionTable{
        .points = try std.testing.allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = 405.0, .sigma_cm2_per_molecule = 6.21e-19 },
            .{ .wavelength_nm = 465.0, .sigma_cm2_per_molecule = 4.17e-19 },
        }),
    };
    defer cross_sections.deinit(std.testing.allocator);
    const spectroscopy = try std.testing.allocator.dupe(ReferenceData.SpectroscopyLine, &.{
        .{ .center_wavelength_nm = 434.6, .line_strength_cm2_per_molecule = 1.15e-20, .air_half_width_nm = 0.041, .temperature_exponent = 0.69, .lower_state_energy_cm1 = 140.0, .pressure_shift_nm = 0.003, .line_mixing_coefficient = 0.07 },
    });
    var line_list = ReferenceData.SpectroscopyLineList{ .lines = spectroscopy };
    defer line_list.deinit(std.testing.allocator);

    var lut = ReferenceData.AirmassFactorLut{
        .points = try std.testing.allocator.dupe(ReferenceData.AirmassFactorPoint, &.{
            .{ .solar_zenith_deg = 40.0, .view_zenith_deg = 10.0, .relative_azimuth_deg = 30.0, .airmass_factor = 1.241 },
        }),
    };
    defer lut.deinit(std.testing.allocator);

    var prepared = try prepareWithSpectroscopy(std.testing.allocator, scene, profile, cross_sections, line_list, lut);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), prepared.layers.len);
    try std.testing.expect(prepared.total_optical_depth > 0.0);
    try std.testing.expect(prepared.layers[0].optical_depth > prepared.layers[3].optical_depth);
    try std.testing.expect(prepared.column_density_factor > 0.0);
    try std.testing.expectEqual(@as(f64, 0.0), prepared.line_mixing_mean_cross_section_cm2_per_molecule);
    try std.testing.expect(prepared.gas_optical_depth > 0.0);
    try std.testing.expect(prepared.d_optical_depth_d_temperature != 0.0);

    const input = prepared.toForwardInput(scene);
    try std.testing.expect(input.optical_depth > 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.241), input.air_mass_factor, 1e-9);
    try std.testing.expect(prepared.totalCrossSectionAtWavelength(434.6) > prepared.totalCrossSectionAtWavelength(465.0));
}

const LineBandMeans = struct {
    line_mean_cross_section_cm2_per_molecule: f64 = 0.0,
    line_mixing_mean_cross_section_cm2_per_molecule: f64 = 0.0,
};

fn computeBandLineMeans(
    scene: Scene,
    line_list: ReferenceData.SpectroscopyLineList,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
) LineBandMeans {
    const sample_count = @max(scene.spectral_grid.sample_count, @as(u32, 1));
    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const wavelength_step = if (sample_count <= 1) 0.0 else span_nm / @as(f64, @floatFromInt(sample_count - 1));

    var line_sum: f64 = 0.0;
    var line_mixing_sum: f64 = 0.0;
    for (0..sample_count) |index| {
        const wavelength_nm = scene.spectral_grid.start_nm + wavelength_step * @as(f64, @floatFromInt(index));
        const evaluation = line_list.evaluateAt(
            wavelength_nm,
            @max(effective_temperature_k, 150.0),
            @max(effective_pressure_hpa, 1.0),
        );
        line_sum += evaluation.line_sigma_cm2_per_molecule;
        line_mixing_sum += evaluation.line_mixing_sigma_cm2_per_molecule;
    }

    return .{
        .line_mean_cross_section_cm2_per_molecule = line_sum / @as(f64, @floatFromInt(sample_count)),
        .line_mixing_mean_cross_section_cm2_per_molecule = line_mixing_sum / @as(f64, @floatFromInt(sample_count)),
    };
}

fn computeOperationalBandMean(
    scene: Scene,
    lut: OperationalCrossSectionLut,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
) f64 {
    if (scene.observation_model.operational_refspec_grid.enabled()) {
        return computeWeightedOperationalBandMean(
            scene.observation_model.operational_refspec_grid,
            lut,
            effective_temperature_k,
            effective_pressure_hpa,
        );
    }

    const sample_count = @max(scene.spectral_grid.sample_count, @as(u32, 1));
    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const wavelength_step = if (sample_count <= 1) 0.0 else span_nm / @as(f64, @floatFromInt(sample_count - 1));

    var sigma_sum: f64 = 0.0;
    for (0..sample_count) |index| {
        const wavelength_nm = scene.spectral_grid.start_nm + wavelength_step * @as(f64, @floatFromInt(index));
        sigma_sum += lut.sigmaAt(
            wavelength_nm,
            @max(effective_temperature_k, 150.0),
            @max(effective_pressure_hpa, 1.0),
        );
    }

    return sigma_sum / @as(f64, @floatFromInt(sample_count));
}

fn computeWeightedOperationalBandMean(
    refspec_grid: OperationalReferenceGrid,
    lut: OperationalCrossSectionLut,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
) f64 {
    var sigma_sum: f64 = 0.0;
    var weight_sum: f64 = 0.0;
    for (refspec_grid.wavelengths_nm, refspec_grid.weights) |wavelength_nm, weight| {
        sigma_sum += weight * lut.sigmaAt(
            wavelength_nm,
            @max(effective_temperature_k, 150.0),
            @max(effective_pressure_hpa, 1.0),
        );
        weight_sum += weight;
    }
    return sigma_sum / @max(weight_sum, 1e-12);
}

fn scaleOpticalDepth(
    optical_depth: f64,
    reference_wavelength_nm: f64,
    angstrom_exponent: f64,
    wavelength_nm: f64,
) f64 {
    if (optical_depth == 0.0) return 0.0;
    const safe_wavelength = @max(wavelength_nm, 1.0);
    const safe_reference = @max(reference_wavelength_nm, 1.0);
    return optical_depth * std.math.pow(f64, safe_reference / safe_wavelength, angstrom_exponent);
}

fn buildAerosolSublayerDistribution(
    allocator: Allocator,
    scene: Scene,
    profile: ReferenceData.ClimatologyProfile,
    layer_count: u32,
    sublayer_divisions: u32,
) ![]f64 {
    return buildGaussianSublayerDistribution(
        allocator,
        scene,
        profile,
        layer_count,
        sublayer_divisions,
        scene.atmosphere.has_aerosols and scene.aerosol.enabled and scene.aerosol.optical_depth > 0.0,
        scene.aerosol.optical_depth,
        scene.aerosol.layer_center_km,
        scene.aerosol.layer_width_km,
    );
}

fn buildCloudSublayerDistribution(
    allocator: Allocator,
    scene: Scene,
    profile: ReferenceData.ClimatologyProfile,
    layer_count: u32,
    sublayer_divisions: u32,
) ![]f64 {
    const cloud_center_km = scene.cloud.top_altitude_km - 0.5 * scene.cloud.thickness_km;
    return buildGaussianSublayerDistribution(
        allocator,
        scene,
        profile,
        layer_count,
        sublayer_divisions,
        scene.atmosphere.has_clouds and scene.cloud.enabled and scene.cloud.optical_thickness > 0.0,
        scene.cloud.optical_thickness,
        cloud_center_km,
        @max(scene.cloud.thickness_km * 0.5, 0.25),
    );
}

fn buildGaussianSublayerDistribution(
    allocator: Allocator,
    scene: Scene,
    profile: ReferenceData.ClimatologyProfile,
    layer_count: u32,
    sublayer_divisions: u32,
    enabled: bool,
    total_optical_depth: f64,
    center_km: f64,
    width_km: f64,
) ![]f64 {
    _ = scene;
    const weights = try allocator.alloc(f64, @as(usize, layer_count) * @as(usize, sublayer_divisions));
    errdefer allocator.free(weights);

    if (!enabled or total_optical_depth == 0.0) {
        @memset(weights, 0.0);
        return weights;
    }

    var total_weight: f64 = 0.0;
    const altitude_span = @max(profile.maxAltitude(), 1.0);
    const total_slots = @as(usize, layer_count) * @as(usize, sublayer_divisions);
    for (weights, 0..) |*slot, index| {
        const altitude_fraction = (@as(f64, @floatFromInt(index)) + 0.5) / @as(f64, @floatFromInt(total_slots));
        const altitude_km = altitude_span * altitude_fraction;
        const delta = (altitude_km - center_km) / @max(width_km, 0.25);
        const weight = @exp(-0.5 * delta * delta);
        slot.* = weight;
        total_weight += weight;
    }
    if (total_weight == 0.0) total_weight = 1.0;
    for (weights) |*slot| slot.* = total_optical_depth * (slot.* / total_weight);
    return weights;
}

fn hgPhaseCoefficients(asymmetry_factor: f64) [phase_coefficient_count]f64 {
    var coefficients = [_]f64{0.0} ** phase_coefficient_count;
    coefficients[0] = 1.0;
    for (1..phase_coefficient_count) |index| {
        coefficients[index] = std.math.pow(f64, asymmetry_factor, @as(f64, @floatFromInt(index)));
    }
    return coefficients;
}

fn combinePhaseCoefficients(
    gas_scattering_optical_depth: f64,
    aerosol_scattering_optical_depth: f64,
    cloud_scattering_optical_depth: f64,
    aerosol_phase_coefficients: [phase_coefficient_count]f64,
    cloud_phase_coefficients: [phase_coefficient_count]f64,
) [phase_coefficient_count]f64 {
    const gas_phase_coefficients = [_]f64{ 1.0, 0.0, 0.05, 0.0 };
    const total_scattering = gas_scattering_optical_depth + aerosol_scattering_optical_depth + cloud_scattering_optical_depth;
    if (total_scattering == 0.0) return gas_phase_coefficients;

    var combined = [_]f64{0.0} ** phase_coefficient_count;
    for (0..phase_coefficient_count) |index| {
        combined[index] =
            (gas_scattering_optical_depth * gas_phase_coefficients[index] +
                aerosol_scattering_optical_depth * aerosol_phase_coefficients[index] +
                cloud_scattering_optical_depth * cloud_phase_coefficients[index]) / total_scattering;
    }
    combined[0] = 1.0;
    return combined;
}

fn computeLayerDepolarization(
    scene: Scene,
    gas_scattering_tau: f64,
    aerosol_scattering_tau: f64,
    cloud_scattering_tau: f64,
) f64 {
    const total = gas_scattering_tau + aerosol_scattering_tau + cloud_scattering_tau;
    if (total == 0.0) return 0.0;
    const gas_fraction = gas_scattering_tau / total;
    const aerosol_fraction = aerosol_scattering_tau / total;
    const cloud_fraction = cloud_scattering_tau / total;
    return gas_fraction * 0.0279 +
        aerosol_fraction * (0.04 + 0.02 * (1.0 - scene.aerosol.asymmetry_factor)) +
        cloud_fraction * (0.01 + 0.01 * (1.0 - scene.cloud.asymmetry_factor));
}
